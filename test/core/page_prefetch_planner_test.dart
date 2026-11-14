import 'package:flutter_test/flutter_test.dart';
import 'package:fastink_flutter/src/core/page_prefetch_planner.dart';

void main() {
  test('first page only warms its immediate neighbor', () {
    final planner = PagePrefetchPlanner();
    expect(
      planner.plan(
        index: 0,
        pageCount: 3022,
        direction: 1,
        maximumAhead: 6,
        now: DateTime(2026),
      ),
      <int>[1],
    );
  });

  test('steady reading expands the directional window', () {
    final planner = PagePrefetchPlanner();
    final start = DateTime(2026);
    planner.plan(
      index: 5,
      pageCount: 100,
      direction: 1,
      maximumAhead: 3,
      now: start,
    );
    expect(
      planner.plan(
        index: 6,
        pageCount: 100,
        direction: 1,
        maximumAhead: 3,
        now: start.add(const Duration(seconds: 2)),
      ),
      <int>[7, 8, 9, 5],
    );
  });

  test('fast turns and distant jumps avoid a large speculative queue', () {
    final planner = PagePrefetchPlanner();
    final start = DateTime(2026);
    planner.plan(
      index: 5,
      pageCount: 3022,
      direction: 1,
      maximumAhead: 6,
      now: start,
    );
    expect(
      planner.plan(
        index: 6,
        pageCount: 3022,
        direction: 1,
        maximumAhead: 6,
        now: start.add(const Duration(milliseconds: 100)),
      ),
      <int>[7, 5],
    );
    expect(
      planner.plan(
        index: 2700,
        pageCount: 3022,
        direction: 1,
        maximumAhead: 6,
        now: start.add(const Duration(seconds: 2)),
      ),
      <int>[2701],
    );
  });

  test('bounds and user-disabled prefetch are respected', () {
    final planner = PagePrefetchPlanner();
    final now = DateTime(2026);
    expect(
      planner.plan(
        index: 2,
        pageCount: 3,
        direction: 1,
        maximumAhead: 2,
        now: now,
      ),
      isEmpty,
    );
    expect(
      planner.plan(
        index: 1,
        pageCount: 3,
        direction: -1,
        maximumAhead: 0,
        now: now,
      ),
      isEmpty,
    );
  });
}
