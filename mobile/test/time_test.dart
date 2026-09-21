import 'package:cloudcli_mobile/core/util/time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 21, 15, 30);

  group('relativeTime', () {
    test('walks from seconds to older dates', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 10)), now: now), '刚刚');
      expect(relativeTime(now.subtract(const Duration(minutes: 12)), now: now), '12 分钟前');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now), '3 小时前');
      expect(relativeTime(DateTime(2026, 9, 20, 21, 40), now: now), '昨天 21:40');
      expect(relativeTime(DateTime(2026, 9, 14, 9, 5), now: now), '09-14');
      expect(relativeTime(DateTime(2025, 12, 31, 9, 5), now: now), '2025-12-31');
    });
  });

  group('sectionLabel', () {
    test('groups by day, week, month and older', () {
      expect(sectionLabel(DateTime(2026, 9, 21, 1, 0), now: now), '今天');
      expect(sectionLabel(DateTime(2026, 9, 20, 23, 0), now: now), '昨天');
      expect(sectionLabel(DateTime(2026, 9, 17, 10, 0), now: now), '本周');
      expect(sectionLabel(DateTime(2026, 8, 30, 10, 0), now: now), '8 月');
      expect(sectionLabel(DateTime(2025, 8, 30, 10, 0), now: now), '2025 年 8 月');
    });
  });

  group('elapsedClock', () {
    test('formats minutes and hours', () {
      expect(elapsedClock(const Duration(seconds: 42)), '00:42');
      expect(elapsedClock(const Duration(minutes: 12, seconds: 3)), '12:03');
      expect(elapsedClock(const Duration(hours: 1, minutes: 2, seconds: 11)), '1:02:11');
    });
  });
}
