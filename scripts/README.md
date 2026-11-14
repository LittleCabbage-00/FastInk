# 开发脚本

从项目根目录执行，脚本也支持从其他工作目录调用。

```powershell
.\scripts\build.ps1                     # 编译并打包；默认限制内存 2560 MB、CPU 50%
.\scripts\build.ps1 -Mode FlutterOnly   # 复用兼容的 Windows 启动器
.\scripts\build.ps1 -Architecture arm64 -Mode Native # 在 ARM64 Windows 上构建
.\scripts\setup_windows_tools.ps1       # 下载 PDF 和 Mermaid 组件
.\scripts\test.ps1                      # 串行静态分析和完整测试，同样受资源限制
.\scripts\test.ps1 -Preview             # 额外保存界面预览
.\scripts\verify_windows.ps1            # 校验当前版本 ZIP 并用自己的隐藏进程验证启动
.\scripts\clean.ps1 -WhatIf             # 查看可清理的构建产物
.\scripts\clean.ps1                     # 清理产物，保留启动器缓存、非空资料库和正在运行的包
```

PowerShell 脚本使用 UTF-8 BOM 编码，以兼容 Windows PowerShell 5.1；修改中文注释时也应保留该编码。

`build.cmd` 是双击入口。`build_windows_impl.ps1`、`build_windows_worker.ps1` 与 `test.ps1 -Worker` 是内部工作进程，日常使用公开入口即可；构建和测试共用互斥锁，防止同时占满内存。

`workspace_paths.ps1` 统一检查生成目录范围，并只解除链接本身，不进入链接目标。非空资料库和 OneNote 的 `Notebook.url` 入口目录会保留；清理不会进入项目外的安装目录，也不会结束已运行的 FastInk。

诊断截图写入 `build/diagnostics/`，构建、测试与校验报告写入 `build/reports/`。测试可通过 `-DenseInkPath` 和 `-PdfSamplePath` 指定本机样本，样本不放入代码或发行包。

`windows/tools/` 存放运行时组件。GitHub Actions 使用 `-ExternalTools` 打包应用和下载脚本，解压后可下载 PDF 与 Mermaid 组件。每种架构独立输出便携包和 SHA-256 文件。校验脚本检查 PE 和 Dart AOT 文件头，并启动本次校验的副本。

Windows 原生探针、打包与资源保护回归在 `test/windows/`。图标由 `generate_icon.py` 生成，普通构建直接读取项目内的 PNG 和 ICO。

脚本入口、函数、资源预算和关键原生句柄已补充中文说明。`BuildResourceGuard.cs` 是公开入口使用的 Job 桥，MB 参数进入原生层后按字节处理，CPU 比例转换为原生限速单位；进程必须先加入作业再运行。不要把整棵 Job 的私有提交峰值、逐进程工作集和系统可用物理内存混称为同一种“占用”。

修改参数、目录、安全边界或发布流程时，必须同步更新本页对应段落和 [AGENTS.md](../AGENTS.md)要求的关联文档。纯注释修改同样应检查脚本解析、编码和非注释 token，没有执行行为差异时无需为了注释重新打包原生启动器。
