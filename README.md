# FastInk

FastInk 是我为 Windows 写的手写笔记工具，也能编辑 Markdown。

## 下载

[Windows 便携版](https://github.com/LittleCabbage-00/FastInk/releases/tag/v1.0.0)

Intel 或 AMD 的 64 位 Windows 选 `x64`。高通 Surface 等 Windows on Arm 设备选 `arm64`。解压后打开 `FastInk.exe`，文稿和设置保存在同目录下的 `FastInkData`。

## 为什么写 FastInk

我经常在 Windows 上看 PDF，用笔在书页上做批注。OneNote 导入和导出 PDF 都要点好几步。Scrble Ink 对我来说太贵，导入 PDF 也慢。我试过把手头那份 3088 页的《资本论》导进去，等了大约一个小时。Inkodo 在我用的时候只能导入单页 PDF，读整本书很麻烦。

我就想把整本书拖进去，翻到哪页就在哪页写，写完能直接导出。FastInk 就是这么来的。

## 能做什么

- 导入 PDF，打开原有目录，搜索 PDF 的文字层。书签、页面排序和跨文稿复制页都在左侧导航里。
- 用触笔写字、局部擦除、圈选和移动笔迹。可以插图、输入文字，也可以在全屏里只留书写工具。
- 截取当前页或桌面区域，画框、写字、打马赛克，再把截图插到笔记里。
- 用 Markdown 写文稿，按需切换源码、分栏预览和块级编辑。待办、表格、双向链接、公式、Mermaid 和本地历史都在编辑器里。
- 导出 PDF、PNG、JPG 和 Markdown 支持的其他格式。整本导出时可以看进度。

操作和设置见 [用户指南](docs/user-guide.md) 与 [Markdown 工作台](docs/markdown-workbench.md)。导入本地 OneNote 文件需要已安装的桌面版 OneNote。

## 大 PDF 和密集笔迹怎么处理

**打开和翻页。** 导入先读取页数和页面尺寸，生成封面，剩下的页面等翻到再解码。预取会根据翻页方向和速度挑邻页，同一页的重复请求合并。各页位置预先累加，滚动时用二分查找可见页，滑动窗口只保留屏幕附近的页面组件。

**写字和擦除。** 每个新采样点只往当前笔画补一段。已写完的笔迹按位置分成瓦片，平移页面时复用仍在缓存里的瓦片。局部橡皮计算擦除圆和笔画线段的交点，直接切掉擦过的部分。

**给文字找空位。** 新放文本框时，从落点附近开始试探，找到第一个空位就停。选「适应页面」后，先把字迹占用投到网格上，用单调栈找连续空白矩形，再用实际字体排版。字号放不下时用二分查找试出可用的大小。

**导出和预览。** 导出优先保留原 PDF 页面，只有写过的页面才生成批注层。新页面分段生成，内容相同的底图只存一份。资料库封面会复用缓存小图，Markdown 预览会把连续输入合并处理。切到电池供电时，界面降低预览解码尺寸，侧栏等笔尖和页面停下来再更新。

具体的缓存、坐标和保存逻辑见 [架构说明](ARCHITECTURE.md)。

## 从源码构建

在对应架构的 Windows 上安装 [Flutter 3.44.4](https://docs.flutter.dev/install/archive) 和 Visual Studio 的「使用 C++ 的桌面开发」工作负载。ARM64 还需要 ARM64 C++ 工具。将 Flutter 加入 PATH 后，在项目根目录运行下面两条命令。

```powershell
.\scripts\setup_windows_tools.ps1
.\scripts\build.ps1 -Mode Native
```

构建结果写到 `dist`。构建脚本默认限制内存和 CPU，并串行编译。第三方组件的版本、下载来源和许可见 [第三方组件说明](THIRD_PARTY_NOTICES.md)。测试、打包校验和其他参数见 [开发脚本](scripts/README.md)。

FastInk 自有代码使用 [MIT 许可证](LICENSE)。
