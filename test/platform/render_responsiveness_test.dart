import 'package:fastink_flutter/src/platform/render_power_policy.dart';
import 'package:fastink_flutter/src/widgets/text_object_toolbar.dart';
import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows power status selects AC, battery and saver policies automatically',
    () {
      RenderPowerPolicy status(int ac, int flags, int saver) =>
          RenderPowerPolicy.fromWindowsStatus(
            acLineStatus: ac,
            batteryFlag: flags,
            systemStatusFlag: saver,
          );
      expect(status(0, 1, 0).onBattery, isTrue);
      expect(status(1, 1, 0).economical, isFalse);
      expect(status(1, 1, 1).economical, isTrue);
      expect(status(0, 128, 0).onBattery, isFalse);
    expect(status(0, 255, 0).onBattery, isTrue);
      expect(status(255, 255, 0).onBattery, isFalse);
    },
  );
  testWidgets(
    'battery previews wait for interaction, cancel stale work and resume on AC',
    (tester) async {
      RenderPowerMonitor.instance.value = const RenderPowerPolicy(
        onBattery: true,
      );
      bool active = true, busy = true;
      bool? result;
      waitForPreviewTurn(
        active: () => active,
        busy: () => busy,
      ).then((v) => result = v);
      await tester.pump(const Duration(milliseconds: 240));
      expect(result, isNull);
      busy = false;
      await tester.pump(const Duration(milliseconds: 120));
      expect(result, isTrue);
      result = null;
      busy = true;
      waitForPreviewTurn(
        active: () => active,
        busy: () => busy,
      ).then((v) => result = v);
      active = false;
      await tester.pump(const Duration(milliseconds: 120));
      expect(result, isFalse);
      active = true;
      result = null;
      waitForPreviewTurn(
        active: () => active,
        busy: () => busy,
      ).then((v) => result = v);
      RenderPowerMonitor.instance.value = const RenderPowerPolicy();
      await tester.pump(const Duration(milliseconds: 120));
      expect(result, isTrue);
    },
  );
  setUp(() => AppText.locale = const Locale('zh'));
  tearDown(() => RenderPowerMonitor.instance.value = const RenderPowerPolicy());

  testWidgets(
    'battery and system reduced motion suppress decorative transitions',
    (tester) async {
      late BuildContext current;
      Future<void> show({bool reduced = false}) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Builder(
              builder: (context) {
                current = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await show();
      expect(appMotionDuration(current, 180).inMilliseconds, 180);
      RenderPowerMonitor.instance.value = const RenderPowerPolicy(
        onBattery: true,
      );
      expect(appMotionDuration(current, 180), Duration.zero);
      expect(appMotionStyle(current), AnimationStyle.noAnimation);
      expect(
        RenderPowerMonitor.instance.value.pageWidth,
        lessThan(const RenderPowerPolicy().pageWidth),
      );
      expect(RenderPowerMonitor.instance.value.rasterDensity, 2);
      RenderPowerMonitor.instance.value = const RenderPowerPolicy();
      await show(reduced: true);
      expect(appMotionDuration(current, 180), Duration.zero);
    },
  );

  testWidgets(
    'text toolbar has labelled editing, direct movement and named actions',
    (tester) async {
      int edits = 0, starts = 0, ends = 0;
      Offset moved = Offset.zero;
      String? action;
      bool enabled = true;
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: Material(
              color: Colors.black,
              child: SizedBox(
                width: 214,
                height: 40,
                child: TextObjectToolbar(
                  enabled: enabled,
                  onEdit: () => edits++,
                  onMoveMode: () {},
                  onMoveStart: () => starts++,
                  onMove: (d) => moved += d,
                  onMoveEnd: () => ends++,
                  onAction: (v) => action = v,
                ),
              ),
            ),
          ),
        ),
      );
      RenderPowerMonitor.instance.value = const RenderPowerPolicy(
        onBattery: true,
      );
      await show();
      await tester.tap(find.text('编辑'));
      expect(edits, 1);
      await tester.drag(find.text('拖动'), const Offset(40, 15));
      expect(starts, 1);
      expect(ends, 1);
      expect(moved.distance, greaterThan(0));
      await tester.tap(find.byTooltip('更多文本操作'));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('文字颜色'), findsOneWidget);
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(action, 'copy');
      enabled = false;
      await show();
      await tester.tap(find.text('编辑'));
      await tester.drag(find.text('拖动'), const Offset(40, 15));
      expect(edits, 1);
      expect(starts, 1);
      await tester.tap(find.byTooltip('更多文本操作'));
      await tester.pumpAndSettle();
      final items = tester.widgetList<PopupMenuItem<String>>(
        find.byType(PopupMenuItem<String>),
      );
      expect(items.where((e) => e.enabled).map((e) => e.value), ['copy']);
      expect(tester.takeException(), isNull);
    },
  );
}
