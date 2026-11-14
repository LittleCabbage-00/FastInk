import 'package:flutter_test/flutter_test.dart';
import 'package:fastink_flutter/src/core/page_ink_cache.dart';
import 'package:fastink_flutter/src/models/models.dart';

const PageInk _empty = PageInk(strokes: <InkStroke>[]);

void main() {
  test('超出容量时淘汰最久未使用的那一页', () {
    final PageInkCache cache = PageInkCache(2);
    cache.put('a', _empty);
    cache.put('b', _empty);
    cache.take('a'); // a 变成最近使用
    cache.put('c', _empty); // 应该淘汰 b

    expect(cache.peek('a'), isNotNull);
    expect(cache.peek('b'), isNull);
    expect(cache.peek('c'), isNotNull);
  });

  test('peek 不改变淘汰顺序', () {
    final PageInkCache cache = PageInkCache(2);
    cache.put('a', _empty);
    cache.put('b', _empty);
    cache.peek('a'); // 只读查询，a 仍是最久未用
    cache.put('c', _empty);

    expect(cache.peek('a'), isNull);
    expect(cache.peek('b'), isNotNull);
  });

  test('容量调小后下一次写入即按新容量淘汰', () {
    final PageInkCache cache = PageInkCache(4);
    for (final String key in <String>['a', 'b', 'c', 'd']) {
      cache.put(key, _empty);
    }
    cache.capacity = 2;
    cache.put('e', _empty);

    // 一路淘汰到 2，留下的是最近用过的 d 和刚写入的 e。
    expect(cache.length, 2);
    expect(cache.peek('a'), isNull);
    expect(cache.peek('b'), isNull);
    expect(cache.peek('c'), isNull);
    expect(cache.peek('d'), isNotNull);
    expect(cache.peek('e'), isNotNull);
  });

  test('容量为 0 时不会死循环，直接不保留', () {
    final PageInkCache cache = PageInkCache(0);
    cache.put('a', _empty);

    expect(cache.length, 0);
    expect(cache.peek('a'), isNull);
  });

  test('remove 与 clear 生效', () {
    final PageInkCache cache = PageInkCache(4);
    cache.put('a', _empty);
    cache.put('b', _empty);
    cache.remove('a');
    expect(cache.peek('a'), isNull);

    cache.clear();
    expect(cache.length, 0);
    expect(cache.peek('b'), isNull);
  });
}
