# 第三方组件

FastInk 自有代码使用 [MIT](LICENSE)。第三方源码和组件沿用各自的许可证。

- Flutter Windows 启动器包含依据 Flutter 模板改写的代码，许可证见 [FLUTTER-LICENSE](FLUTTER-LICENSE)。Dart 依赖的版本见 [pubspec.lock](pubspec.lock)。Flutter 构建生成的 `data/flutter_assets/NOTICES.Z` 包含依赖声明。
- PDF 渲染和文本提取使用 [Poppler](https://poppler.freedesktop.org/)，Windows 二进制取自 [Poppler for Windows](https://github.com/oschwartz10612/poppler-windows/releases/tag/v26.09.0-0)。Poppler 采用 GPL-2.0-or-later。发布包的 `tools/share/source` 提供源码、poppler-data 源包和 conda-forge 的实际构建配方、补丁与许可。数据许可位于 `tools/share/poppler`。
- PDF 页面重组和批注叠加使用 [qpdf 12.4.2](https://github.com/qpdf/qpdf/releases/tag/v12.4.2)，采用 Apache-2.0。
- Markdown 图表使用 [Mermaid 12.2.0](https://github.com/mermaid-js/mermaid)。许可证见 [MERMAID-LICENSE.txt](windows/tools/markdown/MERMAID-LICENSE.txt)。
- OneNote 导入使用本机的 Microsoft OneNote 桌面版和 Windows 组件。
- 启动器和部分外部程序使用 Microsoft Visual C++ Redistributable。详见 [Microsoft 的可再分发文件说明](https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files)。

## 从源码构建时准备组件

从源码构建时，在项目根目录执行 `.\scripts\setup_windows_tools.ps1`。脚本校验上游压缩包的 SHA-256，再将组件放到相应目录。便携发布包随软件提供这些组件。

qpdf 提供原生 ARM64 版本。Poppler 使用 x64 外部进程，在 Windows 11 ARM64 上由系统仿真运行。详见 [Windows on Arm 仿真](https://learn.microsoft.com/windows/arm/apps-on-arm-x86-emulation)。

## 手动安装到项目目录

下载上面的固定版本。目录以项目根目录为起点。保留上游包内的版权和许可文件。

| 下载文件 | 提取内容 | 放置位置 |
| --- | --- | --- |
| `Release-26.09.0-0.zip` | `Library/bin` 内的程序和 DLL | `windows/tools/poppler/` |
| 同一 Poppler 压缩包 | `share/poppler` 数据目录 | `windows/tools/share/poppler/` |
| `qpdf-12.4.2-msvc64.zip` 或 `qpdf-12.4.2-msvc-arm64.zip` | `bin` 内的程序和 DLL，以及包内许可说明 | `windows/tools/qpdf/` |
| [mermaid-12.2.0.tgz](https://registry.npmjs.org/mermaid/-/mermaid-12.2.0.tgz) | `package/dist/mermaid.min.js` | `windows/tools/markdown/mermaid.min.js` |

构建后可在 `FastInk.exe` 旁的 `tools` 目录确认上述组件。分发包含这批二进制的安装包时，按各上游组件的许可证准备声明和所需的对应源码。
