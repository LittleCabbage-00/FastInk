import 'dart:convert';
import 'dart:io';

import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:fastink_flutter/src/core/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'separate repository instances wait for the same pending index save',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fastink-shared-library-',
      );
      try {
        final first = LibraryRepository(root: root.path);
        final second = LibraryRepository(root: root.path.replaceAll('\\', '/'));
        final now = DateTime.utc(2026);
        final folders = List.generate(
          500,
          (i) => LibraryFolder(id: 'f$i', name: 'Folder $i', createdAt: now),
        );
        final saving = first.save(LibraryState(folders: folders));
        final observed = await second.load();
        await saving;
        expect(observed.folders, hasLength(500));
        expect(observed.folders.last.name, 'Folder 499');
        expect(
          await root.list().where((e) => e.path.endsWith('.tmp')).length,
          0,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  test('old library entries default to the first page', () {
    final LibraryDocument document = LibraryDocument.fromJson(<String, Object?>{
      'id': 'doc-1',
      'title': '旧文档',
      'sourcePath': r'D:\notes\page-1.png',
      'coverPath': r'D:\notes\page-1.png',
      'pageCount': 20,
    });
    expect(document.lastPageIndex, 0);
  });

  test('last page is persisted with each library document', () {
    final LibraryDocument original = LibraryDocument(
      id: 'doc-2',
      title: 'PDF',
      sourcePath: r'D:\notes\page-1.png',
      coverPath: r'D:\notes\page-1.png',
      pageCount: 80,
      importedAt: DateTime.utc(2026),
      lastOpenedAt: DateTime.utc(2026),
      bookmarkedPages: const <int>[2, 19, 47],
      pageTitles: const <int, String>{19: '第二章'},
      lastPageIndex: 47,
    );
    final LibraryDocument restored = LibraryDocument.fromJson(
      original.toJson(),
    );
    expect(restored.lastPageIndex, 47);
    expect(restored.bookmarkedPages, <int>[2, 19, 47]);
    expect(restored.pageTitles[19], '第二章');
  });

  test('nested folder parent survives library serialization', () {
    final LibraryFolder folder = LibraryFolder(
      id: 'child',
      name: '课程笔记',
      createdAt: DateTime.utc(2026),
      parentId: 'school',
    );
    expect(LibraryFolder.fromJson(folder.toJson()).parentId, 'school');
  });

  test('settings persist theme and selected data root outside data', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink-settings-',
    );
    try {
      final SettingsRepository settings = SettingsRepository(
        configRoot: directory.path,
      );
      await settings.save(
        const AppSettings(
          themeMode: ThemeMode.dark,
          language: 'en',
          dataRoot: r'E:\Notes\FastInkData',
          pressureEnabled: false,
          pressureSensitivity: 1.7,
          pressureCurve: 'firm',
          stylusOnly: true,
          showPerformance: false,
          doubleTapZoomEnabled: false,
          edgeBounceEnabled: false,
          keepZoomOnPageChange: false,
          maximumZoom: 7,
          wheelZoomSensitivity: 1.5,
          pdfCachePages: 80,
          pdfPrefetchPages: 4,
          pdfImportDpi: 108,
          jpgExportQuality: 78,
          imageCacheEntries: 80,
          imageCacheMegabytes: 144,
          pagePreviewWidth: 600,
          pageAnimationsEnabled: false,
          touchInertiaStrength: 1.75,
          tooltipsEnabled: false,
          compactToolbar: true,
          openSidebarByDefault: true,
          defaultReadOnly: true,
          confirmClearInk: false,
          showLibraryStatusBar: false,
          defaultSidebarTab: 2,
          sidebarWidth: 320,
          defaultTool: 'laser',
          defaultPageFit: 'page',
          penStyle: 'brush',
          autoSaveEnabled: false,
          autoSaveDelayMs: 900,
          selectionPriority: true,
          selectionHitRadius: 88,
          lassoShape: 'rectangle',
          eraserMode: 'point',
          eraserSize: 22,
          defaultTextSize: 36,
          showPageNumber: false,
          penColor: 0xffd93025,
          penWidth: 5,
          highlighterWidth: 20,
          penWidthPresets: <double>[0.5, 5, 12],
          highlighterWidthPresets: <double>[6, 20, 42],
          penButtonOneAction: 'defaultEraser',
          penButtonTwoAction: 'shape',
          penButtonMomentary: false,
          swapPenButtons: true,
          penColorPresets: <int>[0xff112233, 0xff445566, 0xff778899],
          laserMode: 'dot',
          laserColor: 0xff34c759,
          laserWidth: 12,
          laserFadeMs: 1200,
          configStorageLocation: 'user',
        ),
      );
      final AppSettings restored = await settings.load();
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.language, 'en');
      expect(restored.dataRoot, r'E:\Notes\FastInkData');
      expect(restored.pressureEnabled, isFalse);
      expect(restored.pressureSensitivity, closeTo(1.7, 0.001));
      expect(restored.pressureCurve, 'firm');
      expect(restored.stylusOnly, isTrue);
      expect(restored.showPerformance, isFalse);
      expect(restored.doubleTapZoomEnabled, isFalse);
      expect(restored.edgeBounceEnabled, isFalse);
      expect(restored.keepZoomOnPageChange, isFalse);
      expect(restored.maximumZoom, closeTo(7, 0.001));
      expect(restored.wheelZoomSensitivity, closeTo(1.5, 0.001));
      expect(restored.pdfCachePages, 80);
      expect(restored.pdfPrefetchPages, 4);
      expect(restored.pdfImportDpi, 108);
      expect(restored.jpgExportQuality, 78);
      expect(restored.imageCacheEntries, 80);
      expect(restored.imageCacheMegabytes, 144);
      expect(restored.pagePreviewWidth, 600);
      expect(restored.pageAnimationsEnabled, isFalse);
      expect(restored.touchInertiaStrength, closeTo(1.75, 0.001));
      expect(restored.tooltipsEnabled, isFalse);
      expect(restored.compactToolbar, isTrue);
      expect(restored.openSidebarByDefault, isTrue);
      expect(restored.defaultReadOnly, isTrue);
      expect(restored.confirmClearInk, isFalse);
      expect(restored.showLibraryStatusBar, isFalse);
      expect(restored.defaultSidebarTab, 2);
      expect(restored.sidebarWidth, closeTo(320, 0.001));
      expect(restored.defaultTool, 'laser');
      expect(restored.defaultPageFit, 'page');
      expect(restored.penStyle, 'brush');
      expect(restored.autoSaveEnabled, isFalse);
      expect(restored.autoSaveDelayMs, 900);
      expect(restored.selectionPriority, isTrue);
      expect(restored.selectionHitRadius, closeTo(88, 0.001));
      expect(restored.lassoShape, 'rectangle');
      expect(restored.eraserMode, 'point');
      expect(restored.eraserSize, closeTo(22, 0.001));
      expect(restored.defaultTextSize, closeTo(36, 0.001));
      expect(restored.showPageNumber, isFalse);
      expect(restored.penColor, 0xffd93025);
      expect(restored.penWidth, closeTo(5, 0.001));
      expect(restored.highlighterWidth, closeTo(20, 0.001));
      expect(restored.penWidthPresets, <double>[0.5, 5, 12]);
      expect(restored.highlighterWidthPresets, <double>[6, 20, 42]);
      expect(restored.penButtonOneAction, 'defaultEraser');
      expect(restored.penButtonTwoAction, 'shape');
      expect(restored.penButtonMomentary, isFalse);
      expect(restored.swapPenButtons, isTrue);
      expect(restored.penColorPresets, <int>[
        0xff112233,
        0xff445566,
        0xff778899,
      ]);
      expect(restored.laserMode, 'dot');
      expect(restored.laserColor, 0xff34c759);
      expect(restored.laserWidth, 12);
      expect(restored.laserFadeMs, 1200);
      expect(restored.configStorageLocation, 'user');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('concurrent setting changes preserve each independent value', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink-settings-queue-',
    );
    try {
      final SettingsRepository settings = SettingsRepository(
        configRoot: directory.path,
      );
      await settings.save(AppSettings(dataRoot: directory.path));
      await Future.wait(<Future<void>>[
        settings.update((current) => current.copyWith(pressureCurve: 'gentle')),
        settings.update((current) => current.copyWith(pdfImportDpi: 96)),
        settings.update((current) => current.copyWith(jpgExportQuality: 70)),
        settings.update((current) => current.copyWith(pagePreviewWidth: 400)),
      ]);
      final AppSettings restored = await settings.load();
      expect(restored.pressureCurve, 'gentle');
      expect(restored.pdfImportDpi, 96);
      expect(restored.jpgExportQuality, 70);
      expect(restored.pagePreviewWidth, 400);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('storage migration copies files and rewrites owned paths', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink-migrate-',
    );
    final Directory source = Directory('${directory.path}\\old');
    final Directory target = Directory('${directory.path}\\new');
    try {
      final File page = File('${source.path}\\imports\\note\\page.png');
      await page.parent.create(recursive: true);
      await page.writeAsBytes(<int>[1, 2, 3]);
      final File manifest = File(
        '${source.path}\\documents\\doc\\manifest.json',
      );
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        jsonEncode(<String, Object?>{
          'directory': page.parent.path,
          'pages': <Object?>[
            <String, Object?>{'path': page.path},
          ],
        }),
      );
      await File('${source.path}\\library.json').writeAsString(
        jsonEncode(<String, Object?>{
          'documents': <Object?>[
            <String, Object?>{
              'sourcePath': page.path,
              'external': r'Z:\external\unchanged.png',
            },
          ],
        }),
      );

      await StorageMigration.copyLibrary(
        sourceRoot: source.path,
        destinationRoot: target.path,
      );

      final String migratedIndex = await File(
        '${target.path}\\library.json',
      ).readAsString();
      expect(migratedIndex, contains(target.path.replaceAll('\\', r'\\')));
      expect(migratedIndex, contains(r'Z:\\external\\unchanged.png'));
      expect(
        await File('${target.path}\\imports\\note\\page.png').readAsBytes(),
        <int>[1, 2, 3],
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('storage migration refuses a destination inside its source', () async {
    final Directory source = await Directory.systemTemp.createTemp(
      'fastink-nested-migrate-',
    );
    try {
      await expectLater(
        StorageMigration.copyLibrary(
          sourceRoot: source.path,
          destinationRoot: '${source.path}\\FastInkData',
        ),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await source.delete(recursive: true);
    }
  });
}
