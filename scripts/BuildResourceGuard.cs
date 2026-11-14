using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace FastInk.Build {
  // 仅管理本次构建创建的 Windows Job；关闭句柄结束该作业内的进程树，不枚举或结束其他应用。
  public sealed class ResourceJob : IDisposable {
    // 原生基本限制结构，布局不可随意调整。ProcessTime/JobTime 为 100ns 时间单位；Flags 指示哪些限制有效。
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit {
      public long ProcessTime, JobTime; public uint Flags;
      // 工作集最小/最大值为字节；本项目主要限制提交内存，不把工作集大小误当提交预算。
      public UIntPtr MinWorkingSet, MaxWorkingSet;
      // 活动进程上限与处理器亲和性掩码，保留 Windows ABI 字段宽度。
      public uint ActiveProcesses; public UIntPtr Affinity;
      // 进程优先级类别与调度类别，不是用户界面刷新频率。
      public uint Priority, Scheduling;
    }
    // IO_COUNTERS：A/B/C 为读、写、其他操作次数；D/E/F 为对应传输字节数。
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong A,B,C,D,E,F; }
    // 作业扩展限制：ProcessMemory/JobMemory 及峰值均为字节，不能与 MB 参数混用。
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit {
      public BasicLimit Basic; public IoCounters Io;
      public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    // CPU 限速结构；Rate 是百分之一百分比，50% 写入 5000，Flags 选择硬上限等策略。
    [StructLayout(LayoutKind.Sequential)] struct CpuLimit { public uint Flags, Rate; }
    // 作业完成端口关联：Key 区分消息来源，Port 是本对象拥有的 IO 完成端口句柄。
    [StructLayout(LayoutKind.Sequential)] struct CompletionPort { public IntPtr Key, Port; }
    // 作业统计：时间为 100ns 单位，PageFaults 为缺页次数，其余计数为该作业进程数。
    [StructLayout(LayoutKind.Sequential)] struct Accounting {
      public long UserTime, KernelTime, PeriodUser, PeriodKernel;
      public uint PageFaults, TotalProcesses, ActiveProcesses, TerminatedProcesses;
    }
    // 全局内存结构：Length 为结构字节数，Load 为占用百分比；TotalPhys/AvailPhys 为物理内存字节。
    // TotalPage/AvailPage 等其余成员保留原生布局，本项目的系统余量依据 AvailPhys，而不是分页池或提交量。
    [StructLayout(LayoutKind.Sequential)] struct MemoryStatus {
      public uint Length, Load;
      public ulong TotalPhys, AvailPhys, TotalPage, AvailPage, TotalVirtual, AvailVirtual, AvailExtended;
    }
    // 句柄安全属性：Length 为结构大小，Descriptor 为安全描述符，Inherit 控制子进程是否继承日志句柄。
    [StructLayout(LayoutKind.Sequential)] struct Security { public int Length; public IntPtr Descriptor; public int Inherit; }
    // 原生启动信息：Size 为结构大小，Flags 决定哪些字段有效；Input/Output/Error 为本次日志重定向句柄。
    // 其余窗口位置、字符尺寸、标题和保留字段遵循 STARTUPINFO 布局，不用于查找用户前台窗口。
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
      public int Size; public string Reserved, Desktop, Title;
      public uint X,Y,Width,Height,CountX,CountY,Fill,Flags;
      public ushort Show, ReservedSize; public IntPtr ReservedData, Input, Output, Error;
    }
    // 本次 CreateProcess 的输出：进程/主线程句柄需关闭，ID 只用于所属 Job 的监控。
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
    // 以下绑定只封装 Windows Job、进程与完成端口 API，参数宽度必须与系统 ABI 保持一致。
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int type,IntPtr info,uint size);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int type,IntPtr info,uint size,IntPtr length);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string executable,StringBuilder command,IntPtr a,IntPtr b,bool inherit,uint flags,IntPtr environment,string directory,ref Startup startup,out ProcessInfo process);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateFile(string name,uint access,uint share,ref Security security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process,uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateJobObject(IntPtr job,uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateIoCompletionPort(IntPtr file,IntPtr port,UIntPtr key,uint threads);
    [DllImport("kernel32.dll")] static extern bool GetQueuedCompletionStatus(IntPtr port,out uint message,out UIntPtr key,out IntPtr value,uint timeout);
    // 本对象拥有的作业、主进程和完成端口句柄；释放后置零以保证 Dispose 可重复调用。
    IntPtr job, process, completion;
    // 完成端口报告进程/作业内存超限后置位，不用采样峰值推测是否触发系统硬限制。
    public bool MemoryLimitReached { get; private set; }
    // 本对象启动的根工作进程编号，不是任意前台进程 ID。
    public int ProcessId { get; private set; }
    // 实际应用到 Job 的私有提交内存上限，单位字节。
    public ulong MemoryLimitBytes { get; private set; }

    // 读取系统可用物理内存字节；查询失败抛错，不以 0 或无限量冒充成功。
    public static ulong AvailablePhysicalBytes() {
      var status = new MemoryStatus(); status.Length = (uint)Marshal.SizeOf(status);
      if (!GlobalMemoryStatusEx(ref status)) throw new Win32Exception();
      return status.AvailPhys;
    }
    // 将 T 按原生布局写入 Job。type 必须与结构 T 对应；临时非托管缓冲始终在 finally 释放。
    static void Set<T>(IntPtr job, int type, T value) {
      int size = Marshal.SizeOf(value); var buffer = Marshal.AllocHGlobal(size);
      try { Marshal.StructureToPtr(value,buffer,false);
        if (!SetInformationJobObject(job,type,buffer,(uint)size)) throw new Win32Exception();
      } finally { Marshal.FreeHGlobal(buffer); }
    }
    // 查询当前作业的指定统计结构。type 与 T 必须匹配；原生查询失败向监控层报告。
    T Query<T>(int type) where T : struct {
      int size = Marshal.SizeOf(typeof(T)); var buffer = Marshal.AllocHGlobal(size);
      try {
        if (!QueryInformationJobObject(job,type,buffer,(uint)size,IntPtr.Zero)) throw new Win32Exception();
        return (T)Marshal.PtrToStructure(buffer,typeof(T));
      } finally { Marshal.FreeHGlobal(buffer); }
    }
    // 创建受内存、CPU 和低优先级限制的作业；任一步失败释放已创建句柄，不返回半初始化监督器。
    // memoryBytes 为整棵作业树的私有提交字节预算，cpuPercent 为百分比，不是线程数。
    public ResourceJob(ulong memoryBytes, int cpuPercent) {
      job = CreateJobObject(IntPtr.Zero,null);
      if (job == IntPtr.Zero) throw new Win32Exception();
      try {
        var limits = new ExtendedLimit();
        // 合计限制所有子进程的私有提交内存，并降低其运行优先级，
        // 监督句柄关闭时只结束本次编译进程树。
        limits.Basic.Flags = 0x2000 | 0x200 | 0x20 | 0x400;
        limits.Basic.Priority = 0x4000;
        limits.JobMemory = new UIntPtr(memoryBytes);
        Set(job,9,limits);
        Set(job,15,new CpuLimit { Flags = 1 | 4, Rate = (uint)(cpuPercent * 100) });
        completion = CreateIoCompletionPort(new IntPtr(-1),IntPtr.Zero,UIntPtr.Zero,1);
        if (completion == IntPtr.Zero) throw new Win32Exception();
        Set(job,7,new CompletionPort { Key=job, Port=completion });
        MemoryLimitBytes = memoryBytes;
      } catch { Dispose(); throw; }
    }
    // 在挂起状态创建自有工作进程，先加入 Job 再恢复主线程；子进程不能在限制前抢先启动。
    // directory 是工作目录；logPath 接收 stdout/stderr；所有临时输入输出与线程句柄配对关闭。
    public void Start(string executable,string arguments,string directory,string logPath) {
      if (process != IntPtr.Zero) throw new InvalidOperationException("Already started");
      var security = new Security { Length = Marshal.SizeOf(typeof(Security)), Inherit = 1 };
      var output = CreateFile(logPath,0x40000000,1|2|4,ref security,2,0x80,IntPtr.Zero);
      if (output == new IntPtr(-1)) throw new Win32Exception();
      var input = CreateFile("NUL",0x80000000,1|2,ref security,3,0x80,IntPtr.Zero);
      if (input == new IntPtr(-1)) { CloseHandle(output); throw new Win32Exception(); }
      var startup = new Startup { Size=Marshal.SizeOf(typeof(Startup)), Flags=0x100, Input=input, Output=output, Error=output };
      ProcessInfo info;
      try {
        // 执行首条指令前先加入作业，防止编译器抢先启动而逃离资源限制。
        if (!CreateProcess(executable,new StringBuilder("\""+executable+"\" "+arguments),IntPtr.Zero,IntPtr.Zero,true,
            0x4 | 0x08000000,IntPtr.Zero,directory,ref startup,out info)) throw new Win32Exception();
      } finally { CloseHandle(output); CloseHandle(input); }
      process = info.Process; ProcessId = (int)info.ProcessId;
      try {
        if (!AssignProcessToJobObject(job,process)) {
          TerminateProcess(process,1); throw new Win32Exception();
        }
        if (ResumeThread(info.Thread) == UInt32.MaxValue) {
          TerminateJobObject(job,1); throw new Win32Exception();
        }
      } finally { CloseHandle(info.Thread); }
    }
    // 无阻塞查询根进程是否退出，不等待用户应用或其他 Job。
    public bool HasExited { get { return process != IntPtr.Zero && WaitForSingleObject(process,0) == 0; } }
    // 获取根进程原生退出码；只有 HasExited 后才应当作最终结果。
    public long ExitCode { get { uint code; if (!GetExitCodeProcess(process,out code)) throw new Win32Exception(); return code; } }
    // 当前作业中仍活动的进程数量，根进程退出不一定代表所有子进程已结束。
    public uint ActiveProcesses { get { return Query<Accounting>(1).ActiveProcesses; } }
    // Windows 记录的整棵作业树提交峰值，单位字节，与逐进程采样工作集不同。
    public ulong PeakCommitBytes { get { return Query<ExtendedLimit>(9).PeakJobMemory.ToUInt64(); } }
    // 查询本 Job 的进程 ID 以便统计采样，不扫描/终止系统全部进程；查询缓冲始终释放。
    public int[] ProcessIds() {
      int bytes = 8 + 8 * 4096; var buffer = Marshal.AllocHGlobal(bytes);
      try {
        if (!QueryInformationJobObject(job,3,buffer,(uint)bytes,IntPtr.Zero)) throw new Win32Exception();
        int count = Marshal.ReadInt32(buffer,4); var ids = new int[count];
        for (int i=0;i<count;i++) ids[i]=(int)Marshal.ReadInt64(buffer,8+i*8);
        return ids;
      } finally { Marshal.FreeHGlobal(buffer); }
    }
    // 只停止本对象拥有的作业树，退出码 99 表示资源监督中止；不能替换为杀全部 Dart/前台应用。
    public void Stop() { if (job != IntPtr.Zero) TerminateJobObject(job,99); }
    // 非阻塞清空完成端口通知，将内存超限事件记录为终止原因，避免仅靠低频采样漏报。
    public void PollNotifications() {
      uint message; UIntPtr key; IntPtr value;
      while (GetQueuedCompletionStatus(completion,out message,out key,out value,0)) {
        if (message == 9 || message == 10) MemoryLimitReached = true;
      }
    }
    // 关闭所属句柄并置零；Job 配置了关闭时清理其进程树，因此监督器必须活到任务结束。
    public void Dispose() {
      if (job != IntPtr.Zero) { CloseHandle(job); job=IntPtr.Zero; }
      if (process != IntPtr.Zero) { CloseHandle(process); process=IntPtr.Zero; }
      if (completion != IntPtr.Zero) { CloseHandle(completion); completion=IntPtr.Zero; }
    }
  }
}
