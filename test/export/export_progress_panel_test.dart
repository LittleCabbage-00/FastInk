import 'package:fastink_flutter/src/models/export_progress.dart';
import 'package:fastink_flutter/src/widgets/export_progress_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'progress shows phase, percentage and elapsed time in a compact fullscreen overlay',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget screen(ExportProgress progress) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              Positioned(
                right: 16,
                bottom: 16,
                child: SizedBox(
                  width: 380,
                  child: ExportProgressPanel(
                    title: 'Capital · 3088 pages',
                    progress: progress,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(
        screen(const ExportProgress('Annotations: 6 / 8 pages', value: .6)),
      );
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('Annotations: 6 / 8 pages'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('export-progress-bar')),
            )
            .value,
        .6,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining(RegExp(r'0:0[1-9]')), findsOneWidget);
      await tester.pumpWidget(
        screen(const ExportProgress('Writing PDF: 3088 pages', value: .9)),
      );
      expect(find.text('90%'), findsOneWidget);
      expect(find.textContaining(RegExp(r'0:0[1-9]')), findsOneWidget);
      final expandedHeight = tester
          .getSize(find.byType(ExportProgressPanel))
          .height;
      await tester.tap(find.byKey(const ValueKey('collapse-export-progress')));
      await tester.pump();
      expect(find.text('Writing PDF: 3088 pages'), findsNothing);
      expect(find.text('90%'), findsOneWidget);
      expect(
        tester.getSize(find.byType(ExportProgressPanel)).height,
        lessThan(expandedHeight - 60),
      );
      await tester.pumpWidget(
        screen(const ExportProgress('Finishing PDF', value: .98)),
      );
      expect(find.text('98%'), findsOneWidget);
      expect(find.byKey(const ValueKey('export-progress-bar')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('collapse-export-progress')));
      await tester.pump();
      expect(find.text('Finishing PDF'), findsOneWidget);
      expect(find.textContaining(RegExp(r'0:0[1-9]')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}
