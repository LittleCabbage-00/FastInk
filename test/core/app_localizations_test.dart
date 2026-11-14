import 'package:fastink_flutter/src/core/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppText.locale = const Locale('en'));

  test('system language uses Chinese only for a Chinese system locale', () {
    expect(
      AppLanguage.system.resolve(const Locale('zh', 'CN')),
      const Locale('zh'),
    );
    expect(
      AppLanguage.system.resolve(const Locale('en', 'US')),
      const Locale('en'),
    );
    expect(
      AppLanguage.system.resolve(const Locale('ja', 'JP')),
      const Locale('en'),
    );
  });

  test('explicit language overrides the system locale', () {
    expect(AppLanguage.zh.resolve(const Locale('en')), const Locale('zh'));
    expect(AppLanguage.en.resolve(const Locale('zh')), const Locale('en'));
  });

  test('application text changes with the active locale', () {
    AppText.locale = const Locale('zh');
    expect(tr('设置'), '设置');
    AppText.locale = const Locale('en');
    expect(tr('设置'), 'Settings');
    expect(tr('动态文字', 'Dynamic text'), 'Dynamic text');
  });
}
