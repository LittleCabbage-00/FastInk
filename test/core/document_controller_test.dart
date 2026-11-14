import 'package:fastink_flutter/src/controllers/document_controller.dart';
import 'package:fastink_flutter/src/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

NoteDocument _document(String id) => NoteDocument(
  id: id,
  title: id,
  directory: 'C:\\docs\\$id',
  pages: <NotePage>[
    NotePage(
      index: 0,
      originalPage: 1,
      path: 'C:\\docs\\$id\\1.png',
      name: '1',
    ),
  ],
  initialIndex: 0,
);

void main() {
  test('locks and busy state are scoped to one document', () {
    final DocumentController controller = DocumentController();
    controller.document = _document('a');
    controller.busyDocumentId = 'a';
    controller.lockInk('a');

    expect(controller.busy, isTrue);
    expect(controller.anyBusy, isTrue);
    expect(controller.inkLocked, isTrue);
    expect(controller.inkInputBlocked, isTrue);

    // 导出 A 期间切到 B：B 连文件都不沾边，必须照常能写、能增删页。
    controller.document = _document('b');
    expect(controller.busy, isFalse);
    expect(controller.inkLocked, isFalse);
    expect(controller.inkInputBlocked, isFalse);
    // 但重活还在跑，防重入仍然生效：不能同时开第二个导出。
    expect(controller.anyBusy, isTrue);

    // 切回 A：锁还在它身上。
    controller.document = _document('a');
    expect(controller.busy, isTrue);
    expect(controller.inkInputBlocked, isTrue);
  });

  test('ink locks are counted so nested holders release independently', () {
    final DocumentController controller = DocumentController();
    controller.document = _document('a');
    controller.lockInk('a');
    controller.lockInk('a');

    controller.unlockInk('a');
    expect(controller.inkLocked, isTrue);

    controller.unlockInk('a');
    expect(controller.inkLocked, isFalse);

    // 多余的释放不该抛异常，也不该把别人的锁算错。
    controller.unlockInk('a');
    expect(controller.inkLocked, isFalse);
  });

  test('page loading blocks ink input even without an ink lock', () {
    final DocumentController controller = DocumentController();
    controller.document = _document('a');
    expect(controller.inkInputBlocked, isFalse);

    controller.pageLoading = true;
    expect(controller.inkInputBlocked, isTrue);
    expect(controller.inkLocked, isFalse);
    expect(controller.busy, isFalse);
  });
}
