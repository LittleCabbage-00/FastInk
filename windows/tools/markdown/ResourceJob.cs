using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace FastInk.MarkdownRuntime {
  public sealed class ResourceJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit {
      public long ProcessTime, JobTime; public uint Flags;
      public UIntPtr MinWorkingSet, MaxWorkingSet;
      public uint ActiveProcesses; public UIntPtr Affinity;
      public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong A,B,C,D,E,F; }
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit {
      public BasicLimit Basic; public IoCounters Io;
      public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [StructLayout(LayoutKind.Sequential)] struct CpuLimit { public uint Flags, Rate; }
    [StructLayout(LayoutKind.Sequential)] struct CompletionPort { public IntPtr Key, Port; }
    [StructLayout(LayoutKind.Sequential)] struct Accounting {
      public long UserTime, KernelTime, PeriodUser, PeriodKernel;
      public uint PageFaults, TotalProcesses, ActiveProcesses, TerminatedProcesses;
    }
    [StructLayout(LayoutKind.Sequential)] struct MemoryStatus {
      public uint Length, Load;
      public ulong TotalPhys, AvailPhys, TotalPage, AvailPage, TotalVirtual, AvailVirtual, AvailExtended;
    }
    [StructLayout(LayoutKind.Sequential)] struct Security { public int Length; public IntPtr Descriptor; public int Inherit; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
      public int Size; public string Reserved, Desktop, Title;
      public uint X,Y,Width,Height,CountX,CountY,Fill,Flags;
      public ushort Show, ReservedSize; public IntPtr ReservedData, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
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
    IntPtr job, process, completion;
    public bool MemoryLimitReached { get; private set; }
    public int ProcessId { get; private set; }
    public ulong MemoryLimitBytes { get; private set; }

    public static ulong AvailablePhysicalBytes() {
      var status = new MemoryStatus(); status.Length = (uint)Marshal.SizeOf(status);
      if (!GlobalMemoryStatusEx(ref status)) throw new Win32Exception();
      return status.AvailPhys;
    }
    static void Set<T>(IntPtr job, int type, T value) {
      int size = Marshal.SizeOf(value); var buffer = Marshal.AllocHGlobal(size);
      try { Marshal.StructureToPtr(value,buffer,false);
        if (!SetInformationJobObject(job,type,buffer,(uint)size)) throw new Win32Exception();
      } finally { Marshal.FreeHGlobal(buffer); }
    }
    T Query<T>(int type) where T : struct {
      int size = Marshal.SizeOf(typeof(T)); var buffer = Marshal.AllocHGlobal(size);
      try {
        if (!QueryInformationJobObject(job,type,buffer,(uint)size,IntPtr.Zero)) throw new Win32Exception();
        return (T)Marshal.PtrToStructure(buffer,typeof(T));
      } finally { Marshal.FreeHGlobal(buffer); }
    }
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
        // 执行首条指令前先加入作业，避免进程抢先启动而逃离资源限制。
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
    public bool HasExited { get { return process != IntPtr.Zero && WaitForSingleObject(process,0) == 0; } }
    public long ExitCode { get { uint code; if (!GetExitCodeProcess(process,out code)) throw new Win32Exception(); return code; } }
    public uint ActiveProcesses { get { return Query<Accounting>(1).ActiveProcesses; } }
    public ulong PeakCommitBytes { get { return Query<ExtendedLimit>(9).PeakJobMemory.ToUInt64(); } }
    public int[] ProcessIds() {
      int bytes = 8 + 8 * 4096; var buffer = Marshal.AllocHGlobal(bytes);
      try {
        if (!QueryInformationJobObject(job,3,buffer,(uint)bytes,IntPtr.Zero)) throw new Win32Exception();
        int count = Marshal.ReadInt32(buffer,4); var ids = new int[count];
        for (int i=0;i<count;i++) ids[i]=(int)Marshal.ReadInt64(buffer,8+i*8);
        return ids;
      } finally { Marshal.FreeHGlobal(buffer); }
    }
    public void Stop() { if (job != IntPtr.Zero) TerminateJobObject(job,99); }
    public void PollNotifications() {
      uint message; UIntPtr key; IntPtr value;
      while (GetQueuedCompletionStatus(completion,out message,out key,out value,0)) {
        if (message == 9 || message == 10) MemoryLimitReached = true;
      }
    }
    public void Dispose() {
      if (job != IntPtr.Zero) { CloseHandle(job); job=IntPtr.Zero; }
      if (process != IntPtr.Zero) { CloseHandle(process); process=IntPtr.Zero; }
      if (completion != IntPtr.Zero) { CloseHandle(completion); completion=IntPtr.Zero; }
    }
  }
}
