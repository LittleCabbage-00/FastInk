import 'dart:collection';

import '../models/models.dart';

/// 按页缓存的笔迹，供侧栏缩略图预览使用。
///
/// 主画布只把当前页的笔迹放在 [InkController] 里，翻页就整体替换，所以
/// 侧栏想看别的页必须自己去读盘并留一份。容量由
/// [MemoryPolicy.sidebarInkCachePages] 决定，按最近使用淘汰——一页笔迹
/// 是几百 KB 量级的 [InkStroke] 列表，按文档页数缓存会把内存吃光
/// （3000 页的 PDF 尤其如此）。
///
/// 这里只负责存和淘汰，不做 IO。加载由调用方挂在侧栏的串行队列上，
/// 每次装载的页数上限取自 MemoryPolicy，而不是散落在各处各自决定。
class PageInkCache {
  /// 建立限定容量的页面笔迹 LRU；容量后续可随内存档位调整。
  PageInkCache(this.capacity);

  /// 允许保留的页数。内存档位变化时可以直接调小，下一次 put 就会淘汰。
  int capacity;

  /// 按插入顺序排列，取用时重新插入即实现 LRU。
  final LinkedHashMap<String, PageInk> _entries =
      LinkedHashMap<String, PageInk>();

  /// 返回当前缓存的页面条目数量，不代表笔画数或占用字节数。
  int get length => _entries.length;

  /// 取一页的笔迹，命中时把它移到最近使用的一端。
  PageInk? take(String key) {
    final PageInk? ink = _entries.remove(key);
    if (ink != null) _entries[key] = ink;
    return ink;
  }

  /// 只读查询，不影响淘汰顺序。用于判断"要不要去读盘"。
  PageInk? peek(String key) => _entries[key];

  /// 写入页面快照并更新最近使用顺序，超出容量时淘汰最旧条目。
  void put(String key, PageInk ink) {
    _entries
      ..remove(key)
      ..[key] = ink;
    _evict();
  }

  /// 删除指定页面缓存；原始笔迹文件不受影响。
  void remove(String key) => _entries.remove(key);

  /// 清除全部内存快照，换文稿时避免复用旧页笔迹。
  void clear() => _entries.clear();

  /// 按当前容量淘汰最早使用的缓存条目，容量降低时同样执行。
  void _evict() {
    // capacity 为 0 或负数时这里会一路清空，不会死循环。
    while (_entries.length > capacity && _entries.isNotEmpty) {
      _entries.remove(_entries.keys.first);
    }
  }
}
