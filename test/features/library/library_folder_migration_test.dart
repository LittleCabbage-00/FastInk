import 'dart:convert';
import 'dart:io';
import 'package:fastink_flutter/src/storage/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy shared nested trees split without changing metadata or source files',
    () async {
      final temp = await Directory.systemTemp.createTemp('fastink-folders-');
      addTearDown(() => temp.delete(recursive: true));
      final repo = LibraryRepository(root: temp.path);
      final now = DateTime.utc(2026);
      LibraryDocument doc(String id, String path) => LibraryDocument(
        id: id,
        title: id,
        sourcePath: path,
        coverPath: '',
        pageCount: 2,
        importedAt: now,
        lastOpenedAt: now,
        folderId: 'child',
        favorite: true,
        bookmarkedPages: const [1],
        pageTitles: const {1: 'Chapter'},
        trashed: id == 'trash',
      );
      final old = <String, Object?>{
        'version': 1,
        'folders': [
          {'id': 'root', 'name': 'Shared', 'colorValue': 123},
          {'id': 'child', 'name': 'Nested', 'parentId': 'root'},
          {'id': 'empty', 'name': 'Empty'},
          // Deliberately collide with the preferred migrated id.
          LibraryFolder(
            id: 'child-markdown',
            name: 'Existing',
            createdAt: now,
          ).toJson(),
        ],
        'documents': [
          doc('note', 'n.png').toJson(),
          doc('md', 'a.MD').toJson(),
          doc('trash', 'deleted.md').toJson(),
        ],
      };
      await File('${temp.path}/library.json').writeAsString(jsonEncode(old));
      final state = await repo.load();
      expect(
        state.folders.where((f) => f.scope == LibraryScope.legacy),
        isEmpty,
      );
      expect(state.folders.length, 7);
      expect(state.documents.first.folderId, 'child');
      final md = state.documents[1];
      expect(md.folderId, 'child-markdown-2');
      expect(md.sourcePath, 'a.MD');
      expect(md.favorite, isTrue);
      expect(md.bookmarkedPages, [1]);
      expect(md.pageTitles, {1: 'Chapter'});
      expect(state.documents.last.trashed, isTrue);
      expect(state.documents.last.folderId, md.folderId);
      final folder = state.folders.firstWhere((f) => f.id == md.folderId);
      expect(folder.scope, LibraryScope.markdown);
      expect(folder.parentId, 'root-markdown');
      expect(identical(separateLibraryFolders(state), state), isTrue);
      final again = await repo.load();
      expect(
        again.folders.map((f) => f.toJson()).toList(),
        state.folders.map((f) => f.toJson()).toList(),
      );
    },
  );

  test('rapid saves are serialized and latest moves survive reload', () async {
    final temp = await Directory.systemTemp.createTemp('fastink-save-');
    addTearDown(() => temp.delete(recursive: true));
    final repo = LibraryRepository(root: temp.path);
    final writes = <Future<void>>[];
    for (var i = 0; i < 30; i++) {
      writes.add(
        repo.save(
          LibraryState(
            folders: [
              LibraryFolder(
                id: '$i',
                name: 'Folder $i',
                createdAt: DateTime.utc(2026),
                scope: LibraryScope.markdown,
              ),
            ],
          ),
        ),
      );
    }
    await Future.wait(writes);
    final state = await repo.load();
    expect(state.folders.single.id, '29');
    expect(state.folders.single.scope, LibraryScope.markdown);
    expect(File('${temp.path}/library.json.tmp').existsSync(), isFalse);
  });
}
