# FastInk 代码结构

这份文档说明模块职责、调用关系与不能随意破坏的约束。源码中文注释说明方法职责、变量归属/单位、失败语义和优化原因；[维护约定](AGENTS.md)要求功能变更同步修改本文及对应用户文档。[文档索引](docs/README.md)列出各类变更的更新位置。

## 目录结构概览

```
lib/
├── main.dart                  ← 固定 Flutter 入口，透传命令行参数
└── src/
    ├── app/                   ← 应用初始化、主题、主页状态和 part 装配
    ├── features/
    │   ├── document/          ← 文档、画布交互、文本、工具栏和侧栏
    │   ├── library/           ← 资料库、文件夹、导入入口和存储操作
    │   ├── settings/          ← 通用、手写与 Markdown 设置界面
    │   └── markdown/          ← Markdown 编辑器及工作台
    ├── core/                  ← 设置、布局策略、内存、本地化和崩溃防护
    ├── controllers/           ← 文档、视口、工具控制器
    ├── models/                ← 文稿、笔迹、模板与目录模型
    ├── engine/                ← 可编辑笔迹和显示缓存
    ├── storage/               ← 资料库、笔记、备份与配置保存
    ├── importing/             ← OneNote 与 PDF 目录解析
    ├── export/                ← PDF、图片和原稿导出
    ├── platform/              ← Windows 系统接口与运行组件调用
    ├── capture/               ← 截图编辑模型和交互
    └── widgets/               ← 可复用界面组件

scripts/                       ← 构建、测试、校验与清理入口及内部实现
test/                          ← 按对应模块分组的测试
windows/                       ← Windows 启动器、Flutter 工程和必需运行组件
packaging/                     ← Windows 打包配置
assets/                        ← 应用资源
docs/                          ← 功能与设置说明
build/                         ← 可清理的编译结果、诊断截图和报告
dist/                          ← 发行包和校验文件
```

## 应用与状态

- `lib/main.dart`：保持稳定的 Flutter 入口和组件导出，转交应用初始化并透传命令行参数。
- `lib/src/app/fastink_app.dart`：`_FastInkHomeState` 的共享状态和 `part` 装配。业务方法仍按功能放到各自模块，不在入口堆积。
- `lib/src/app/app_shell.dart`：Material 主题和根组件参数传递。
- `lib/src/core/app_localizations.dart`：全局中英字符串和系统语言判定；服务层错误信息也从这里取词。
- `lib/src/app/fastink_home.dart`：主页组件的稳定配置接口。
- `lib/src/core/app_settings_controller.dart`：运行时设置副本（~40 字段），从 Widget 同步，通过 `saveBool/saveNum/saveString` 自动持久化。
- `lib/src/features/settings/home_settings*.dart`：设置界面和持久化操作。

工作流设置的运行时变更放在 `home_settings_workflow.dart`，与其他设置方法分开。工具栏当前工具和"打开文稿时的默认工具"是两个状态，手动换笔不得改写后者。

`_FastInkHomeState` 只保存跨模块共享的 UI 状态。能封装在控制器或仓库里的状态，不应继续放进主页状态。

已提取的控制器（字段与行数会继续变化，不把这些易失效的统计当作维护契约）：
- `AppSettingsController`（`src/core/app_settings_controller.dart`）：运行时设置副本（~40 字段），通过 `_settings` 访问
- `ToolController`（`src/controllers/tool_controller.dart`）：工具运行时状态（15 字段），通过 `_toolState` 访问
- `ViewportController`（`src/controllers/viewport_controller.dart`）：视口/缩放/相机导航（16 字段），通过 `_viewport` 访问
- `DocumentController`（`src/controllers/document_controller.dart`）：文档生命周期/页面/保存（15 字段），通过 `_doc` 访问

仍需共享的首页字段按职责分组：仓库与控制器、UI 控制器、资料库导航、缓存与定时器、运行时标志。这些共享状态仍是耦合点；新增功能应优先使用独立组件或服务，不继续扩大隐式依赖。

## 导航与可维护组件

- `widgets/app_screen_transition.dart`：只挂载当前界面的轻量平移过渡。进入/返回以 destination 判断；不同时保留新旧画布，避免同一焦点、滚动控制器或已释放位图被两个编辑器使用。动画帧复用子树和重绘边界，不截取整屏快照。
- `widgets/library_document_picker.dart`：文档内文件夹选稿窗口，输入是轻量资料库快照，输出为选中文稿或取消。只展示手写/PDF 域；逐级目录与跨目录搜索分开处理，路径遍历检测循环父引用。它不自己保存或打开文稿，宿主收到选择后调用统一打开流程。
- `widgets/library_note_preview.dart` / `platform/note_cover_cache.dart`：卡片只显示低分辨率缓存，指纹包含首页顺序、底图、笔迹和嵌入资源。卡片 `BoxFit.cover + topCenter` 只裁切显示，不改原页面或缓存数据格式。
- `home_document_overlays.dart`：输入面板使用主题 onSurface 保证可读；`ToolController.textColor` 仍决定落字颜色。界面预览样式不得写回持久文本样式。

方法拆分时必须保留归属、锁、保存和资源释放顺序。只移动文件或改名不会自动降低耦合；对应回归测试也应随着职责一起迁移。

## 注释与验证契约

公共/私有方法均说明用途，非直观参数注明单位、坐标或编号起点，异步方法注明取消和失败结果。成员与共享变量说明归属、生命周期和失效条件；局部变量重点解释跨坐标换算、缓存键与并发代次，不用重复代码的空话占据正文。

纯注释修改应使用语法分析器比较修改前后的非注释 token，验证执行代码保持一致，并检查语法和静态分析；功能修改则运行对应操作回归。用户指南中的“支持”不代表所有格式都无损兼容，测试样本结果也不是通用性能保证。

## 文档界面

- `home_document_view.dart`：连续文稿视口、侧栏和可见页虚拟化。当前可见页矩形经相机逆变换用于截图放置，图片四角按整页宽高归一化。已选图片接管单指变换，选区外手势继续由相机处理。
- `home_screenshot.dart`：截图独占锁随对话框结束释放。插入使用文稿身份与页令牌核验，之后的资源清理不会打断选区拖动。
- `core/canvas_edit_shortcut.dart`：文稿和截图共用编辑键位解析，历史和选区操作由各自模型提交。截图接收宿主已解析的物理侧键动作，复用笔压映射和局部擦除算法。截图裁切由单独的工具按钮驱动。
- `document_viewport_layout.dart` / `home_document_viewport.dart`：文稿坐标、相机约束、前缀布局和二分可见页定位。
- `home_virtual_document_viewport.dart`：相机矩阵与页面树解耦；平移缩放只更新 Transform，可见窗口跨界时才重建页面。
- `home_document_load.dart`：切页、当前页解码、笔迹载入和邻页预取。
- `home_document_input.dart`：工具切换、触控缩放、笔侧键映射。
- `home_touch_page_flow.dart` / `page_motion.dart`：连续画布的单指跟手与有边界的惯性滑行。
- `home_input_tools.dart`：鼠标滚轮、键盘快捷键和缩放边界。
- `home_document_overlays.dart`：文本编辑框和选区菜单等页面内浮层。

页面图片解码可能在用户离开后才完成。所有异步页面结果必须通过 `_pageToken` 校验，过期的 `ui.Image` 必须主动释放。

页面图片、笔迹和纸张深浅必须在同一加载事务里提交。邻页深浅提前采样；切页时不能沿用上一页的背景色，否则黑白页交替会闪变。

切页前按笔迹实际所属页写入快照。写入失败时恢复导航到该页，保留笔迹控制器中的修改与撤销记录。写入队列使用同一个 Future 报告结果并清理占用；重新保存时仍可进入队列。

`DocumentController` 用三个互不替代的概念描述"现在忙什么"，别再把它们合成一个：

| 状态 | 作用域 | 谁置位 | 含义与后果 |
| --- | --- | --- | --- |
| `pageLoading` | 当前显示的页 | 只有 `_loadPage` | 位图和笔迹正在换，`_ink.strokes` 还属于上一页。笔迹层卸载（免得新页标签配旧页内容）、输入拒绝、转圈 |
| `busyDocumentId` → `busy` / `anyBusy` | 按文稿 | 导出、换纸、旋转 | 后台长任务正在处理**那一份文稿**。`busy` 是"本文稿在忙"（结构操作、转圈、菜单置灰看它），`anyBusy` 是"全应用有重活在跑"（只用于不让第二个重活开跑） |
| `_inkLocks` → `inkLocked` | 按文稿（计数） | 旋转、导出 | 要求笔迹冻结：笔迹层保持挂载，只拒绝落笔/撤销/插入图片。计数是为了多个持有者各自释放 |

**锁必须跟着文稿走。** 导出文稿 A 期间切到 B，B 应该照常能写、能增删页面——两份文稿连文件都不沾边，用全局标志会让 A 的任务把 B 冻住。`anyBusy` 只挡"再开一个重活"（导出/换纸/旋转共用进度条和磁盘队列，旋转还会把页面换成新文件、正好被导出的旧路径读到），不挡日常编辑。会改写笔迹的输入统一看 `inkInputBlocked`（= `pageLoading || inkLocked`），别在每个入口各抄一遍。

导出用 `busy + inkLocked` 保持同一时刻的笔迹快照。换纸仅持有结构操作的 `busy`。成功写入每一页后推进底图版本，当前页刷新只重新解码底图，笔迹、选区和撤销记录留在原控制器。异步结果提交前核对文稿、页令牌与底图版本。

`_loadPage` 失败时要把 `pageIndex` 和页号框回滚到 `inkPage` 指向的那一页：异步等待前页码就翻新了，不回滚会留下"新页标签配旧页内容"的半新半旧状态。

导出期间**本文稿的页面结构整体锁死**：增删页、旋转、排序、换纸全部拒绝（`_rejectStructuralChange`，同时禁用侧栏页菜单和"添加页面"按钮）。导出是逐页读盘生成的，中途改页面会让结果既不是开始时的样子、也不是结束时的样子——要"以点导出按钮那一刻的状态导出"，就只能整段锁住。加上 `inkLocked` 冻住笔迹，导出内容就等于点击瞬间（`await _saveNow()` 之后）的文稿。标志要在 `await` 之前置位：刷盘本身是 await，先刷盘后置位会留下重入窗口。

## 侧栏预览

主画布和侧栏共用纸张外观数据。普通浅色导入页可应用深色滤镜，模板页显示原纸色并在绘制时解析中性墨色。文件路径与底图版本共同标识缩略图缓存，笔迹 Picture 以显示墨色区分，栅格瓦片也包含纸色策略。换纸后只重绘必要内容，彩色墨迹、嵌入图和已保存的 ARGB 数据各自保留。侧栏订阅当前页笔迹修订，因此图片和笔迹变换可即时显示。

- `home_page_sidebar.dart`：页码缩略图列表、目录树和书签。
- `_animateSidebarToPage`：翻页时自动滚动到当前页，使用 `_thumbExtent` 精确累计偏移。
- `_scheduleSidebarThumbnailLoad`：滚动 150ms 去抖后触发可见区域的加载，带 generation counter 取消过期任务。
- `_loadVisibleSidebarThumbnails`：只对懒渲染的 PDF 按需生成页面缩略图。
- `_loadVisibleSidebarInk`：读取可见范围内各页的笔迹填进 `PageInkCache`。对任何文档都要跑——笔记本的页面图本来就在磁盘上，但笔迹不在。
- `MemoryPolicy.sidebarThumbnailBudget`：每次滚动停止后最多处理的页数。缩略图渲染和笔迹读取共用这一个上限，且都挂在串行队列上，所以它同时就是并发上限。
- `MemoryPolicy.sidebarInkCachePages`：`PageInkCache` 的 LRU 容量。

### 笔迹为什么需要额外一层缓存

主画布的 `InkController.strokes` 是**一个扁平列表，只装当前页**，翻页时整体 `replace()`。缩略图要同时显示多页，所以侧栏自己留一份按页的快照（`src/core/page_ink_cache.dart`），容量由内存档位决定——一页笔迹是几百 KB 量级的 `InkStroke` 列表，按文档页数缓存会把内存吃光。

必须守住的规则：

1. **"哪页的笔迹在内存里"由 `DocumentController.inkPage/inkDocument` 标记**，只在 `_ink.replace()` 的同一段同步代码里翻页。侧栏判断走实时笔迹还是缓存快照看这个标记（`identical(_doc.inkPage, page)`），**不要看 `pageIndex` 或 `_doc.pageLoading`**——翻页的异步窗口里 `pageIndex` 已经翻新但 `_ink.strokes` 还是上一页的。`_saveNow` 的保存目标同样是 `inkPage`，不是 `currentPage`，否则会把旧页的笔迹写进新页的 JSON。
2. **离开某页时把实时笔迹存入缓存**（`_loadPage` 里的 put-on-leave），否则翻走再回来会看到编辑前的旧快照。进入某页**不作废**它的缓存：缓存内容与磁盘一致（离开时已刷盘），加载窗口里正好拿它顶着显示。换文稿和结构性改动（增删页、旋转、排序）整体 `_pageInkCache.clear()`。
3. **`await _saveNow()` 的契约是刷盘**：即使没有新内容也会等在途写入落地。旋转、复制页这类"先读后写"的存储层操作依赖这一点；`loadPageInk` 自己也会等同键的在途写入。
4. **会改写笔迹的输入（落笔、撤销/重做、删除或复制选区、清空、插入图片、提交文本）必须避开加载和旋转/导出窗口**——统一判据是 `DocumentController.inkInputBlocked`（= `pageLoading || inkLocked`），别在入口各抄一遍两个标志。窗口里的修改属于旧页或旧坐标系，提交块结尾的 `dirty = false` 会把它无声吞掉，保存回去则会覆盖刚写好的盘上内容。

`InkPreview` 只接受 `List<InkStroke>`，不认 `InkController`，所以当前页和缓存页走同一套绘制代码。嵌入图片要访问文件系统，引擎层不依赖 `dart:io`，因此由调用方通过 `imagesBuilder` 构造图层——注意缩略图必须传 `cacheWidth`，否则每张嵌入图都会按原图分辨率解码；实时页还要给 `EmbeddedImageLayer` 传同一个 `committedRepaint`，拖动图片选区时缩略图才会跟手。

侧栏列表的槽位不等于页码：书签页签里槽位是"第几个书签"。所有按滚动范围装载的流程（笔迹、懒 PDF 缩略图）都必须先按槽位取可见区间，再经书签映射换成文档页码。

## 触控板支持

- `home_input_tools.dart`：滚轮灵敏度对触控板 0.28x 衰减（`PointerDeviceKind.trackpad` 检测）。
- `_trackpadGesture*`：`PointerPanZoomStart/Update/End` 事件驱动的双指缩放和平移，松手后弹性回弹。
- `home_document_view.dart`：`Listener` 绑定三个 `onPointerPanZoom*` 回调。

## PDF 书签自动导入

- `NoteRepository.readPdfOutline`：异步调用随包提供的 Poppler pdftohtml，仅处理首页文字，读取完整书签 XML；不渲染全部页面。
- `pdf_outline_parser.dart`：解析 XML，按相邻 item/outline 关系保留层级、中文与同页多个书签。`PdfOutlineEntry` 保存原 PDF 页标识，显示时映射到当前页面顺序。
- 导入和打开旧文稿时补读，独立保存在 `LibraryDocument.pdfOutline`，不覆盖用户的 `pageTitles`。`pdfOutlineVersion` 控制一次性迁移，目录侧栏也提供手动刷新。

## Markdown 编辑器

- `markdown_editor.dart`：分栏布局编辑器，左侧编辑 + 右侧实时预览。
- `src/platform/markdown_editor_service.dart`：文件读写、自动保存、PDF 导出。
- `flutter_markdown`：Markdown 渲染引擎。
- `flutter_math_fork`：LaTeX 数学公式渲染。
- `_LatexInlineSyntax`：匹配 `$...$` 和 `$$...$$` 格式的行内公式。
- `_MathBuilder`：将 LaTeX 元素渲染为 Math.tex 组件。
- 目录提取：逐行扫描 `#` 开头的标题行，生成扁平 TocItem 列表。

编辑器支持：深色/浅色模式、可拖拽分割线、目录侧栏、格式化工具栏、
自动保存、导出 PDF（A4 分页或连续长页）、Ctrl+S 快捷键保存。

### 外部文件流程（右键 / 文件选择器）

外部 .md 文件和手写笔记共用同一套 temp 模式：

```
原始文件 → 复制到 %temp%/FastInk/ → 只读预览
  ├─ "编辑原文件" → 解除只读，保存时直接覆盖原始文件
  └─ "导入到资料库" → 复制到 app 资料库目录，切换为资料库模式
```

资料库内 .md 文件（从侧栏"Markdown"分区打开）直接编辑，不走 temp 流程。

## Windows 右键上下文菜单

- `src/platform/windows_registry.dart`：纯 dart:ffi 实现的注册表操作（advapi32.dll / kernel32.dll）。
- `--open-external "%1"`：右键菜单命令参数，`main()` 解析后调用 `_openExternalFile`。
- `_openExternalFile`：复制到 `%temp%/FastInk/`，以只读模式打开临时副本。
- `_importExternalToLibrary`：用户确认编辑后导入到资料库。
- 设置页 `_contextMenuSettingsCard`：一键添加/移除右键菜单，检测当前状态。

## 笔迹引擎

- `src/engine/ink_canvas.dart`：数据控制器、撤销历史和共享枚举。
- `src/engine/ink_controller_drawing.dart`：落笔、形状、文本创建与编辑。
- `src/engine/ink_controller_selection.dart`：套索、命中测试和橡皮擦。
- `src/engine/ink_controller_transform.dart`：移动、等比缩放、自由旋转、撤销/重做。
- `src/engine/ink_layer_state.dart`：单指针输入状态机和笔侧键中途切换。
- `src/engine/ink_painters.dart`：持久笔迹、活动笔迹、选区和光标绘制。
- `src/engine/ink_laser.dart`：完全独立的临时激光层。

笔迹点使用页面归一化坐标（0–1）。命中半径和控制柄使用屏幕像素，并通过当前缩放比例转换。旋转计算必须先转为页面物理像素，否则纵横比会令内容变形。

**笔迹粗细 `InkStroke.width` 也按页面归一化**，基准是页面尺寸的几何平均边长：像素粗细 = `inkPixelWidth(width, size)` = `width × √(宽×高)`。主画布布局、侧栏缩略图、导出图片各用各的 `size`，同一笔在任何尺度下占页面的比例都相同——以前存的是"当时布局的像素"，导出却按图片像素画，Surface Pro 上导出比屏幕细约 1.8 倍。

输入用压感曲线与灵敏度平方响应生成有效压力。灵敏度 1 保持所选曲线，极值区分轻按的线宽。设置里的固定压力样本复用同一输入映射和画布笔型倍率。旧笔迹、缩略图和导出按已保存的有效压力绘制。

- 基准取几何平均而不是页宽：90° 旋转宽高互换、几何平均不变，`rotatePage` 只换点列、原样 `copy()` 字段即可，不必额外折算粗细。
- 落笔时用 `_normalizedInkWidth(工具条像素, 页面布局尺寸)` 换算；工具条上的"3px"始终是相对纸面的粗细，与相机缩放无关。
- 文件格式 `PageInk.version`：v2 及以前存布局像素，v3 起存归一化值。**所有读取路径都必须过 `loadPageInk`**（它在读取时用 `legacyWidthReference` 完成换算），转换要一次做对——把 v2 的像素值当 v3 归一化值存回去，粗细会错一个页面尺度。存储层的"先读后写"操作（旋转、复制页）要把同一个基准透传下去。导出脱离界面，由调用方在开始导出前设置 `ExportRepository.inkWidthReference`。

激光笔不得进入 `InkController.strokes`，也不得触发保存或撤销记录。

## 存储和大 PDF

- `src/storage/note_repository.dart`：仓库共享状态、路径规则、LRU 缓存。
- `src/storage/note_pdf_operations.dart`：PDF 元数据、按需渲染和预取。
- `page_prefetch_planner.dart`：根据翻页间隔的指数移动平均、方向和跳页距离动态选邻页。
- `src/core/memory_policy_catalog.dart`：集中声明设备内存档位；设置页、缓存、页面预读和分块导出共用同一策略。
- `src/storage/note_ink_operations.dart`：按页笔迹读写。
- `src/storage/note_page_operations.dart`：页面增删、旋转和模板操作。
- `src/storage/library_repository.dart`：资料库索引和文件夹元数据。
- `src/core/settings_repository.dart`：配置位置选择和原子写入。
- `export_repository.dart` / `export_image_operations.dart`：分块导出。

大 PDF 导入时只创建页面描述并渲染首页。可见页请求优先于预取；新的预取代次会使旧任务停止；同一页面的并发请求必须共享一个 Future。缓存淘汰不能删除当前页、邻页或正在生成的文件。

预取是推测工作，只允许一个后台 PDF 转换同时进行，并在快速翻页时延迟启动。可见页渲染不等待这个延迟；普通钢笔悬停也不能触发整个笔迹层重建。

笔迹保存按页面串行。开始等待磁盘前先截取不可变快照，失败后必须允许下一次保存继续执行。

## 修改功能时

1. 新工具：在 `InkTool`、工具栏、`InkLayer` 状态机和相应 Painter 中各自处理，临时工具不要混入持久笔迹。
2. 新设置：同时更新 `AppSettings`、`SettingsRepository`、`FastInkHome` 参数、运行时状态和实际行为，并补持久化测试。
3. 新笔迹字段：JSON 读取必须提供旧版本默认值；复制、旋转、导出路径都要保留该字段。
4. 新异步加载：必须考虑切页、关闭文档和异常后的过期结果。
5. 新手势：先明确与文稿相机、笔迹层、选区手柄之间的优先级，避免一个事件被两个层同时消费。页面滚动不得重新引入独立页槽或吸附状态。
