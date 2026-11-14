# FastInk

FastInk 是一款用 Flutter 开发的 Windows 手写笔记和 Markdown 编辑器。

[下载 Windows 便携包](https://github.com/LittleCabbage-00/FastInk/releases/latest)

Intel 和 AMD 的 64 位 Windows 使用 x64 包。高通 Surface 等 Windows on Arm 设备使用 ARM64 包。运行 PDF 和 Mermaid 功能前，在解压目录执行 `powershell -ExecutionPolicy Bypass -File .\setup_windows_tools.ps1` 下载上游组件。

## 为什么写 FastInk

我经常在 Windows 上看 PDF、用笔做批注。OneNote 导入和导出 PDF 的步骤很繁琐。Scrble Ink 对我来说太贵，导入大文件也很慢。我手头那份 3088 页的《资本论》，导入 Scrble Ink 花了大约一个小时，这个等待时间我接受不了。我用 Inkodo 时只能导入单页 PDF，读整本书很不方便。

我写 FastInk，是为了导入整本 PDF 后就能翻页，在原页上写字，写完也能直接导出。导入时保留原文件，翻到哪页就按需解码哪页。

## 首页

资料库以文稿首页作为封面。支持文件夹、收藏、废纸篓和标题搜索。

新建笔记支持分类模板与预览，包括基础纹理、学习笔记、计划和工作布局，可调整尺寸、纸色、方向和适用模板的间距。导入支持 PDF、多张图片及本地 OneNote `.one`、`.onex`、`.onepkg`；OneNote 的组件依赖和转换限制见[用户指南](docs/user-guide.md)。PDF 保留原文件，页面按需渲染，不在导入时预先展开整本数千页文稿。

手写笔记与 Markdown 的文件夹分别管理。封面顶部对齐并铺满卡片，裁切只影响预览；返回资料库保留浏览位置，搜索输入直接更新列表，不反复重建整块资料库。

## 文档界面

当前页按原始宽高比显示，相邻页使用低分辨率预览以节省内存。

左侧有可收起的"页面/目录/书签"侧栏。页面可以新增、复制、删除、拖拽排序，目录标题可以编辑，点了就跳转。支持只读模式。

文稿切换菜单列出已打开文稿，并用勾选标记当前项；“按文件夹打开文稿”支持逐级浏览和跨文件夹搜索其他手写/PDF 文稿。Markdown 使用自己的标签与快速打开入口。

文字默认字号 12，可自定义字号、字体和宽度。输入面板文字使用主题色保证可读，落字仍用用户选定的文本颜色。较长文本可在属性窗口继续编辑；适应页面会避开现有内容，空间不足时缩小，明显过小时提示。

## 书写工具

- 钢笔、画笔和铅笔随压感改变粗细，圆珠笔固定粗细，荧光笔用于高亮。手写设置中可即时比较轻、中、重压力下的笔宽。
- 12 种颜色，多档粗细
- 笔画擦和局部橡皮擦。局部擦会把笔迹线段逐段裁切，擦到哪里消失到哪里
- 形状工具：直线、矩形、椭圆。形状和普通笔迹一样可以被擦除、选中、移动、缩放、旋转、复制、删除
- 框选后可以整体拖动、拖角缩放、拖柄旋转，选区上方有操作条
- 局部橡皮有 12–120 px 可见范围滑杆，悬停时显示实际擦除范围

笔侧键可以自定义。按住侧键 1 临时切橡皮，按住侧键 2 临时切框选，松手自动恢复。按下和松开分开处理，第一次接触就生效，不用先落笔再切工具。

## 快捷键和手势

- `Ctrl+A` 全选，`Delete/Backspace` 删除选区，`Esc` 取消选区
- `Ctrl+Z` 撤销，`Ctrl+Y` 或 `Ctrl+Shift+Z` 重做，`Ctrl+D` 生成选区副本。画布和工具栏共用编辑键位，截图标注采用相同按键，文本框使用自己的编辑历史。
- 资料库 `Ctrl+F` 聚焦搜索，`Esc` 先清除查询，再关闭文件夹；文档内 `Ctrl+F` 搜索键入文字、目录和 PDF 文本层
- 页码点击后全选，Enter 确认；空值恢复当前页，超范围规范到首末页，未确认就离开会恢复实际页码
- 触摸屏双指捏合缩放，单指从选区外开始拖动可浏览页面。图片插入或粘贴后自动选中，单指可直接抓住图片移动。
- 鼠标滚轮竖向翻页，`Ctrl` 滚轮缩放
- 工具栏空间不够时自动变成横向可滚动

## 保存和存储

自动保存延迟可在设置中调整。切页和关闭文稿会先保存笔迹。写入失败时，编辑器保留当前页的笔迹和撤销历史。恢复写入后按 `Ctrl+S` 重试。

所有数据统一存在一个目录下（Portable 版在程序旁边，安装版在用户目录）。笔迹、设置、资料库索引都用 JSON。不会覆盖原始导入的 PDF 或图片。

## 导出

文档内可将整本或当前页导出为 PDF、PNG 或 JPG。资料库卡片导出整本文稿。导出 PDF 时优先在原 PDF 页面上叠加批注，其余页面逐页生成。进度面板显示当前阶段和已处理页数。

## Markdown

支持源码、分栏、预览和块级编辑。内置目录、查找替换、表格、待办列表、双向链接、版本历史、LaTeX 和 Mermaid。可导出 Markdown、HTML、DOCX、PDF 和图片。操作与设置见 [Markdown 工作台](docs/markdown-workbench.md)。

## 截图

文稿工具栏可以截取桌面区域或当前页。截图编辑器支持标注、图形、马赛克、旋转和裁切，沿用文稿的编辑快捷键和笔侧键。截图可复制、另存 PNG 或插入当前页。

## 自动供电策略

应用约每 2 秒读取 Windows 供电状态，拔插电源后自动切换；系统节电模式也启用经济渲染。电池模式限制屏幕底图和预览解码尺寸，减少显示瓦片及装饰效果；侧栏笔迹读取与 PDF 缩略图生成等待书写、手势和滚动空隙，同一可见范围合并排队，关闭侧栏或切换文稿后取消尚未开始的旧任务。接入电源后解除相应等待条件。

保存和导出继续使用原始压感数据。

## 性能实现

| 场景 | 用到的方法 | 省掉的开销 |
| --- | --- | --- |
| 打开大 PDF | 导入时先读取页数、尺寸和首页。翻页时按需渲染，同页的并发请求合并，邻页预取根据翻页方向和速度调整。 | 等封面生成后就能打开文稿。很少翻到的页面无需解码，多处请求同一页也只渲染一次。 |
| 连续滚动 | 预先累加各页的位置，用二分查找定位可见页。滑动窗口只挂载屏幕附近的页面，窗口范围内的平移复用页面组件。 | 二分定位用时随页数对数增长，Flutter 的布局和绘制主要处理可见区域。 |
| 书写和擦除 | 活动笔迹按笔宽分组增量追加线段。已提交笔迹按空间划分瓦片并使用有容量上限的缓存。局部橡皮计算擦除圆与笔画线段的交点。 | 落笔时只追加新增线段。移动视口时复用已有瓦片，擦除时无需为整条笔画重新采样。 |
| 文本框避让 | 放置时按距离优先试探候选位置，遇到第一个空白位置就停止。适应页面时将笔迹边界投影到占用网格，用直方图单调栈找连续空白矩形，再用实际字体测量全文并二分试字号。 | 搜索集中在有限的候选区域，减少全文排版次数。 |
| 资料库封面与 Markdown | 封面用首页和资源的指纹检查缓存。Markdown 合并连续输入触发的预览请求，并复用内容未变的预览结果。 | 滚动资料库时复用小图，连续输入时减少整篇预览重排。 |
| PDF 与图片导出 | 可保留的 PDF 页直接复用原内容，只有批注页生成叠加层。新页面分段处理，重复底图按内容去重。Windows JPEG 编码在后台执行。 | 避免把整本 PDF 转成位图再写回，减少重复的图像解析、编码和文件写入。 |
| 电池供电 | 降低屏幕位图的解码尺寸，推迟侧栏预览，合并同一可见范围的任务。 | 将更多处理时间留给触笔、拖动和翻页。 |

缓存预算、坐标换算和保存流程见 [架构说明](ARCHITECTURE.md)。

## 自适应

资料库在 1100 px 以下使用抽屉导航，文档导航在 1400 px 以下收起次要操作；页面缩略图在窄窗口中变为覆盖层，工具栏保持可滚动。UI 字体跟随 Windows 的 Segoe UI Variable，中文回退 Microsoft YaHei UI。

外观支持跟随系统、固定浅色和固定深色，选择会存到 `settings.json`。主画布和侧栏同步更新。模板页显示选定纸色，黑白墨迹随纸色调整屏幕对比，导出保留原有墨色。

## 构建和发布

用户操作见[用户指南](docs/user-guide.md)。代码结构、维护和脚本说明见[文档索引](docs/README.md)。

双击 `scripts/build.cmd`，或在 PowerShell 中运行：

```powershell
.\scripts\build.ps1
```

脚本自动同步“关于”版本号、获取依赖、编译 Release，在 `dist` 中生成 `FastInk-版本-windows-x64-portable.zip` 和 SHA-256 校验文件。ZIP 发布前逐文件核对内容，不打包个人资料库和配置；每次使用独立暂存目录。可从任意工作目录调用脚本。

构建入口默认启用资源保护：整棵构建进程树的私有提交内存预算最多 2560 MB，CPU 上限 50%，低于正常优先级；可用物理内存低于 2560 MB 时停止本次构建。启动时还会按当前余量缩小预算，余量过低则拒绝启动。同一时间只允许一个 FastInk 构建，编译、静态分析、测试和打包顺序执行，测试并发固定为 1。前端编译器和 AOT 编译器默认分别限制为 1024 MB 堆，原生 CMake 并行度为 1；保留增量缓存。

保护由 Windows Job Object 覆盖构建子进程，在工作进程开始运行前挂接；取消或超限时清理本次进程树。每次在 `build/reports` 保存完整日志和 JSON，记录采样内存峰值、Windows Job 计数、系统可用内存最低值及退出原因。控制台每 15 秒显示一次资源状态。`scripts/build_windows_impl.ps1` 与 `build_windows_worker.ps1` 是内部实现；开发和自动化应统一调用 scripts/build.ps1 入口，避免绕过保护。

通过 `-MaxBuildMemoryMB`、`-ReserveMemoryMB`、`-CpuPercent` 和 `-CompilerHeapMB` 可以调整资源预算。

```powershell
.\scripts\build.ps1 -RunTests                         # 编译前运行静态分析和完整测试
.\scripts\build.ps1 -Installer                        # 额外生成 Inno Setup 安装包
.\scripts\build.ps1 -Mode Native                      # 强制完整编译 Windows C++ 启动器
.\scripts\build.ps1 -Architecture arm64 -Mode Native  # 在 Windows ARM64 上构建
.\scripts\build.ps1 -Mode FlutterOnly                 # 重编译 Dart/资源，复用兼容启动器
.\scripts\build.ps1 -OutputDirectory .\release         # 自定义输出位置
```

默认 `Auto` 检查 Visual Studio C++ / CMake 工具链，有则完整编译；缺少工具链时从本项目已有 Windows 包寻找启动器，校验 Flutter 引擎 DLL 后复用，完成后缓存到 `build/windows-launcher`。可用 `-FlutterPath <flutter.bat 路径>` 或 `-LauncherDirectory <已解压 Windows 包目录>` 显式指定。初次没有兼容启动器时需要先安装 C++ 工具链并执行 Native 构建。

FlutterOnly 会重编译应用业务代码，保留原 EXE 的文件版本元数据；“关于”仍使用当前项目版本。原生插件需要 Native 构建，缓存建立后原生源码有变化也会要求重新完整编译。每个包的 `BUILD-INFO.json` 记录版本、构建方式及时间。`-KeepStaging` 可保留本次打包暂存文件。

`-Installer` 首次使用且未找到 Inno Setup 时，脚本自动下载安装工具并验证数字签名。已有完整 Release 时也可单独执行 `scripts/package_windows.ps1 -SkipBuild -SkipInstaller` 打包。

Portable 包带 `.fastink-portable` 标记，数据目录默认在程序旁边；安装版默认放用户目录，卸载时不会删文稿。

## 开发环境

将 Flutter SDK 加入 PATH。首次 Windows 构建需要 Visual Studio 的「使用 C++ 的桌面开发」工作负载和 CMake。x64 和 ARM64 使用各自架构的 Flutter SDK 和 C++ 工具链。Flutter 的 Windows 桌面构建目标见[支持平台](https://docs.flutter.dev/reference/supported-platforms#desktop-platforms)。

运行 `.\scripts\setup_windows_tools.ps1` 准备 PDF 和 Mermaid 组件。GitHub Actions 为每个架构单独构建并检查便携包，包内附组件下载脚本和[第三方组件说明](THIRD_PARTY_NOTICES.md)。

FastInk 自有代码使用 [MIT 许可证](LICENSE)。
