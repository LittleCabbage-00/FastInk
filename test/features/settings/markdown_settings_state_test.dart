import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:fastink_flutter/src/core/markdown_preferences.dart';
import 'package:fastink_flutter/src/widgets/markdown_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder section(String id) => find.byWidgetPredicate(
  (widget) =>
      widget is ExpansionTile &&
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value == 'markdown-settings-$id',
);

bool expanded(WidgetTester tester, String id) => tester
    .widget<Expansible>(
      find.descendant(of: section(id), matching: find.byType(Expansible)),
    )
    .controller
    .isExpanded;

void main() {
  setUp(() => AppText.locale = const Locale('zh'));

  testWidgets(
    'scrolling then reopening Markdown settings does not confuse scroll offset with expanded state',
    (tester) async {
      final bucket = PageStorageBucket();
      final scroll = ScrollController();
      Future<void> show(bool visible) => tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: visible
                  ? SingleChildScrollView(
                      key: const PageStorageKey('settings-panel-markdown'),
                      controller: scroll,
                      child: MarkdownSettingsPanel(
                        value: const MarkdownPreferences(),
                        onChanged: (_) {},
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      );
      await show(true);
      await tester.pumpAndSettle();
      scroll.jumpTo(180);
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      await show(false);
      await tester.pumpAndSettle();
      await show(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(scroll.offset, closeTo(offset, .01));
      expect(expanded(tester, 'editing'), isTrue);
      for (final id in ['reading', 'preview', 'export', 'history']) {
        expect(expanded(tester, id), isFalse, reason: id);
      }
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets(
    'settings groups retain independent states and preference changes across reopening',
    (tester) async {
      final bucket = PageStorageBucket();
      var prefs = const MarkdownPreferences();
      final scroll = ScrollController();
      Future<void> show(bool visible) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: visible
                  ? SingleChildScrollView(
                      key: const PageStorageKey('settings-panel-markdown'),
                      controller: scroll,
                      child: MarkdownSettingsPanel(
                        value: prefs,
                        onChanged: (value) => prefs = value,
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      );
      await show(true);
      await tester.pumpAndSettle();
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('markdown-setting-lineNumbers')),
          )
          .onChanged!(false);
      await tester.pump();
      for (final id in ['editing', 'reading', 'preview']) {
        final header = find
            .descendant(of: section(id), matching: find.byType(ListTile))
            .first;
        await tester.ensureVisible(header);
        await tester.tap(header);
        await tester.pumpAndSettle();
      }
      expect(expanded(tester, 'editing'), isFalse);
      expect(expanded(tester, 'reading'), isTrue);
      expect(expanded(tester, 'preview'), isTrue);
      scroll.jumpTo(100);
      await tester.pumpAndSettle();
      await show(false);
      await tester.pumpAndSettle();
      await show(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(expanded(tester, 'editing'), isFalse);
      expect(expanded(tester, 'reading'), isTrue);
      expect(expanded(tester, 'preview'), isTrue);
      expect(expanded(tester, 'export'), isFalse);
      expect(expanded(tester, 'history'), isFalse);
      expect(prefs.lineNumbers, isFalse);
      expect(scroll.offset, closeTo(100, .01));
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
}
