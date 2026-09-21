import 'package:intl/intl.dart';

/// Compact relative time for list rows: 刚刚 / 12 分钟前 / 3 小时前 / 昨天 21:40 / 09-14.
String relativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24 && reference.day == time.day) return '${diff.inHours} 小时前';

  final yesterday = DateTime(reference.year, reference.month, reference.day)
      .subtract(const Duration(days: 1));
  if (time.year == yesterday.year && time.month == yesterday.month && time.day == yesterday.day) {
    return '昨天 ${DateFormat('HH:mm').format(time)}';
  }
  if (reference.year == time.year) return DateFormat('MM-dd').format(time);
  return DateFormat('yyyy-MM-dd').format(time);
}

/// Sticky section headers for the session list.
String sectionLabel(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) return '今天';
  if (day == yesterday) return '昨天';
  if (today.difference(day).inDays < 7) return '本周';
  if (reference.year == time.year) return DateFormat('M 月').format(time);
  return DateFormat('yyyy 年 M 月').format(time);
}

/// Elapsed clock for a running turn: 00:42 / 12:03 / 1:02:11.
String elapsedClock(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}
