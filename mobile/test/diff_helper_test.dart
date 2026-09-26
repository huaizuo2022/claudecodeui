import 'package:flutter_test/flutter_test.dart';
import 'package:cloudcli_mobile/features/chat/utils/diff_helper.dart';

void main() {
  group('computeDiffLines', () {
    test('returns empty when both strings are empty', () {
      expect(computeDiffLines('', ''), isEmpty);
    });

    test('marks all lines as added when oldStr is empty', () {
      final diff = computeDiffLines('', 'line 1\nline 2');
      expect(diff.length, 2);
      expect(diff[0].type, DiffLineType.added);
      expect(diff[0].text, 'line 1');
      expect(diff[1].type, DiffLineType.added);
      expect(diff[1].text, 'line 2');
    });

    test('marks all lines as removed when newStr is empty', () {
      final diff = computeDiffLines('line 1\nline 2', '');
      expect(diff.length, 2);
      expect(diff[0].type, DiffLineType.removed);
      expect(diff[0].text, 'line 1');
      expect(diff[1].type, DiffLineType.removed);
      expect(diff[1].text, 'line 2');
    });

    test('computes modified line in the middle with context', () {
      const oldStr = 'prefix\nold content\nsuffix';
      const newStr = 'prefix\nnew content\nsuffix';
      final diff = computeDiffLines(oldStr, newStr);

      expect(diff.length, 4);
      expect(diff[0], const DiffLineItem(DiffLineType.context, 'prefix'));
      expect(diff[1], const DiffLineItem(DiffLineType.removed, 'old content'));
      expect(diff[2], const DiffLineItem(DiffLineType.added, 'new content'));
      expect(diff[3], const DiffLineItem(DiffLineType.context, 'suffix'));
    });
  });
}
