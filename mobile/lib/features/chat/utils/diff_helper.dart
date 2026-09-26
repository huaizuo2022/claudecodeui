enum DiffLineType { added, removed, context }

class DiffLineItem {
  const DiffLineItem(this.type, this.text);
  final DiffLineType type;
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiffLineItem &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          text == other.text;

  @override
  int get hashCode => Object.hash(type, text);

  @override
  String toString() => '${type.name}: $text';
}

/// Computes a unified line-by-line diff with common prefix/suffix detection
/// and up to 2 lines of surrounding context.
List<DiffLineItem> computeDiffLines(String oldStr, String newStr) {
  if (oldStr.isEmpty && newStr.isEmpty) return const [];
  if (oldStr.isEmpty) {
    return newStr.split('\n').map((l) => DiffLineItem(DiffLineType.added, l)).toList();
  }
  if (newStr.isEmpty) {
    return oldStr.split('\n').map((l) => DiffLineItem(DiffLineType.removed, l)).toList();
  }

  final oldLines = oldStr.split('\n');
  final newLines = newStr.split('\n');

  int prefix = 0;
  while (prefix < oldLines.length && prefix < newLines.length && oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }

  int suffix = 0;
  while (suffix < (oldLines.length - prefix) &&
      suffix < (newLines.length - prefix) &&
      oldLines[oldLines.length - 1 - suffix] == newLines[newLines.length - 1 - suffix]) {
    suffix++;
  }

  final result = <DiffLineItem>[];

  // Up to 2 lines of prefix context
  final prefixStart = prefix > 2 ? prefix - 2 : 0;
  for (var i = prefixStart; i < prefix; i++) {
    result.add(DiffLineItem(DiffLineType.context, oldLines[i]));
  }

  // Removed lines
  for (var i = prefix; i < oldLines.length - suffix; i++) {
    result.add(DiffLineItem(DiffLineType.removed, oldLines[i]));
  }

  // Added lines
  for (var i = prefix; i < newLines.length - suffix; i++) {
    result.add(DiffLineItem(DiffLineType.added, newLines[i]));
  }

  // Up to 2 lines of suffix context
  final suffixEnd = oldLines.length - suffix;
  final suffixLimit = suffix > 2 ? 2 : suffix;
  for (var i = suffixEnd; i < suffixEnd + suffixLimit; i++) {
    result.add(DiffLineItem(DiffLineType.context, oldLines[i]));
  }

  return result;
}
