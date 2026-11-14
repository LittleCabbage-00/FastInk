import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

class MarkdownEncoding {
  /// 读取本地文件字节并按指定或自动识别的编码解码，返回正文与实际采用的编码名。
  static Future<(String, String)> read(
    File file, {
    String encoding = 'auto',
  }) async => decode(await file.readAsBytes(), encoding: encoding);

  /// 根据 BOM、显式选项和候选评分解码字节，返回文本及编码，避免把原字节直接按错误 UTF-8 替换。
  static (String, String) decode(Uint8List bytes, {String encoding = 'auto'}) {
    if (encoding == 'utf-8') return (utf8.decode(bytes), 'UTF-8');
    if (bytes.length >= 2 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255))) {
      if (bytes.length.isOdd) throw const FormatException('Invalid UTF-16');
      final endian = bytes[0] == 255 ? Endian.little : Endian.big;
      final data = ByteData.sublistView(bytes);
      return (
        String.fromCharCodes([
          for (int i = 2; i < bytes.length; i += 2) data.getUint16(i, endian),
        ]),
        'UTF-16',
      );
    }
    if (encoding == 'auto') {
      try {
        return (utf8.decode(bytes), 'UTF-8');
      } catch (_) {
        /* 继续尝试下方的旧编码。 */
      }
    }
    if (!Platform.isWindows) {
      throw const FormatException('Legacy encodings require Windows');
    }
    const pages = {'gbk': 936, 'big5': 950, 'shift-jis': 932};
    if (encoding != 'auto') {
      return (
        _decodePage(bytes, pages[encoding] ?? 936),
        encoding.toUpperCase(),
      );
    }
    final choices = <(String, String, double)>[];
    for (final entry in pages.entries) {
      try {
        final text = _decodePage(bytes, entry.value);
        choices.add((
          text,
          entry.key.toUpperCase(),
          _score(text, japanese: entry.key == 'shift-jis'),
        ));
      } catch (_) {
        /* 当前代码页无法解码，继续尝试。 */
      }
    }
    if (choices.isEmpty) throw const FormatException('无法识别文本编码，请手动选择编码');
    choices.sort((a, b) => b.$3.compareTo(a.$3));
    return (choices.first.$1, choices.first.$2);
  }

  /// 对候选解码文本计算可读性评分，japanese 控制日文字符判断，用于自动选择而非修改正文。
  static double _score(String text, {required bool japanese}) {
    const common =
        '的一是不了在人有我他这中大来上国个到说们为子和你地出道也时年得就那要下以生会自着去之过家学对可她里后小么心多天而能好都然没日于起还发成事只作当想看文无开手十用主行方又如前所本见经头面公同三已老从动两长知民样现分将外但身些与高意进把法此全正部因它然前外成天华文字中国测试文件笔记学习内容标题记录开始结束时间项目表格中文繁體測試筆記學習內容標題記錄開始結束時間項目數據結果';
    double score = 0;
    final sample = text.length > 12000 ? text.substring(0, 12000) : text;
    for (final rune in sample.runes) {
      if (rune < 128) continue;
      if (common.contains(String.fromCharCode(rune))) {
        score += 3;
      } else if (rune >= 0x3040 && rune <= 0x30ff) {
        score += japanese ? 4 : -2;
      } else if (rune >= 0x4e00 && rune <= 0x9fff) {
        score += .2;
      } else if (rune >= 0xe000 && rune <= 0xf8ff) {
        score -= 6;
      } else if (rune == 0xfffd) {
        score -= 20;
      }
    }
    return score;
  }

  /// 通过指定 Windows 代码页解码字节，原生缓冲在调用结束后释放。
  static String _decodePage(Uint8List bytes, int page) {
    if (bytes.isEmpty) return '';
    final convert = ffi.DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Uint32,
            ffi.Uint32,
            ffi.Pointer<ffi.Uint8>,
            ffi.Int32,
            ffi.Pointer<ffi.Uint16>,
            ffi.Int32,
          ),
          int Function(
            int,
            int,
            ffi.Pointer<ffi.Uint8>,
            int,
            ffi.Pointer<ffi.Uint16>,
            int,
          )
        >('MultiByteToWideChar');
    final input = calloc<ffi.Uint8>(bytes.length);
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final count = convert(page, 8, input, bytes.length, ffi.nullptr, 0);
      if (count <= 0) throw FormatException('Invalid code page $page');
      final output = calloc<ffi.Uint16>(count);
      try {
        if (convert(page, 8, input, bytes.length, output, count) != count) {
          throw const FormatException('Text decoding failed');
        }
        return String.fromCharCodes(output.asTypedList(count));
      } finally {
        calloc.free(output);
      }
    } finally {
      calloc.free(input);
    }
  }
}
