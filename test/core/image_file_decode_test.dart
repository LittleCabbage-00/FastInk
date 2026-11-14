import 'dart:io';

import 'package:fastink_flutter/src/core/image_file_decode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('file-backed decoder preserves quality and never upscales', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'fastink-decode-',
    );
    try {
      final File file = File('${directory.path}\\sample.png');
      await file.writeAsBytes(
        raster.encodePng(raster.Image(width: 8, height: 4)),
      );
      final dimensions = await readImageFileDimensions(file.path);
      expect(dimensions.width, 8);
      expect(dimensions.height, 4);
      final image = await decodeImageFile(file.path, targetWidth: 4);
      expect(image.width, 4);
      expect(image.height, 2);
      image.dispose();
      final original = await decodeImageFile(file.path, targetWidth: 1800);
      expect(original.width, 8);
      expect(original.height, 4);
      original.dispose();
      final bounded = await decodeImageFile(
        file.path,
        targetWidth: 1800,
        maximumHeight: 2,
      );
      expect((bounded.width, bounded.height), (4, 2));
      bounded.dispose();
      final small = await decodeImageFile(
        file.path,
        targetWidth: 1800,
        maximumHeight: 2400,
      );
      expect((small.width, small.height), (8, 4));
      small.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'long pages keep their aspect ratio within the battery texture limit',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fastink-long-decode-',
      );
      try {
        final file = File('${directory.path}/long.png');
        await file.writeAsBytes(
          raster.encodePng(raster.Image(width: 200, height: 8000)),
        );
        final image = await decodeImageFile(
          file.path,
          targetWidth: 1600,
          maximumHeight: 2400,
        );
        expect((image.width, image.height), (60, 2400));
        image.dispose();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
