class MarkdownTableData {
  /// 保存表格单元格和列对齐，补齐列数，使编辑与序列化使用一致的矩形结构。
  MarkdownTableData(this.rows, List<String> alignments)
    : alignments = List.of(alignments);

  /// rows：表格二维单元格数据，首行为表头。
  final List<List<String>> rows;

  /// alignments：各列表头对齐标识，与列数对应。
  final List<String> alignments;

  /// 按行列数创建空表格；首行仍作为 Markdown 表头处理。
  factory MarkdownTableData.empty(int rows, int columns) => MarkdownTableData([
    for (int row = 0; row < rows; row++) List.filled(columns, ''),
  ], List.filled(columns, 'left'));

  /// 返回尾部增加一行的新表格，不修改现有单元格对象的结构。
  MarkdownTableData withRow() => MarkdownTableData([
    ...rows,
    List.filled(rows.first.length, ''),
  ], alignments);

  /// 返回尾部增加一列的新表格，并为新列补充对齐设置。
  MarkdownTableData withColumn() => MarkdownTableData(
    [
      for (final row in rows) [...row, ''],
    ],
    [...alignments, 'left'],
  );

  /// 生成表头、对齐分隔行和正文行；转义单元格竖线，避免内容被误拆成多列。
  String toMarkdown() {
    // 将一行单元格转义并拼为 Markdown 表格行，保留单元格内部内容。
    String line(List<String> cells) =>
        '| ${cells.map((cell) => cell.replaceAll('|', r'\|').replaceAll('\n', '<br>')).join(' | ')} |';
    return [
      line(rows.first),
      line([
        for (final alignment in alignments)
          switch (alignment) {
            'center' => ':---:',
            'right' => '---:',
            _ => '---',
          },
      ]),
      for (final row in rows.skip(1)) line(row),
    ].join('\n');
  }

  /// 拆分 Markdown 表格行，识别转义竖线而不是直接按所有竖线切分。
  static List<String> _cells(String line) {
    var value = line.trim();
    if (value.startsWith('|')) value = value.substring(1);
    if (value.endsWith('|') && !value.endsWith(r'\|')) {
      value = value.substring(0, value.length - 1);
    }
    return value
        .split(RegExp(r'(?<!\\)\|'))
        .map((cell) => cell.trim().replaceAll(r'\|', '|'))
        .toList();
  }

  /// 寻找 position 所在的完整表格块并解析；不处于受支持表格时返回 null。
  static (int, int, MarkdownTableData)? around(String content, int position) {
    final lines = content.split('\n');
    final offsets = <int>[];
    int offset = 0;
    for (final line in lines) {
      offsets.add(offset);
      offset += line.length + 1;
    }
    int row = 0;
    while (row + 1 < lines.length && offsets[row + 1] <= position) {
      row++;
    }
    if (!lines[row].contains('|')) return null;
    int first = row, last = row;
    while (first > 0 && lines[first - 1].contains('|')) {
      first--;
    }
    while (last + 1 < lines.length && lines[last + 1].contains('|')) {
      last++;
    }
    if (last <= first) return null;
    final separators = _cells(lines[first + 1]);
    if (!separators.every((cell) => RegExp(r'^:?-{3,}:?$').hasMatch(cell))) {
      return null;
    }
    final header = _cells(lines[first]);
    if (header.length != separators.length) return null;
    final data = [
      header,
      for (int i = first + 2; i <= last; i++) _cells(lines[i]),
    ];
    if (data.length == 1) data.add(List.filled(header.length, ''));
    final normalized = [
      for (final cells in data)
        [
          for (int i = 0; i < header.length; i++)
            i < cells.length ? cells[i] : '',
        ],
    ];
    return (
      offsets[first],
      offsets[last] + lines[last].length,
      MarkdownTableData(normalized, [
        for (final cell in separators)
          cell.endsWith(':')
              ? (cell.startsWith(':') ? 'center' : 'right')
              : 'left',
      ]),
    );
  }
}
