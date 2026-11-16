import '../../app/localization/app_localizations.dart';

String relativeTime(DateTime? time, AppLocalizations l10n) {
  if (time == null) return '';
  final difference = DateTime.now().difference(time);
  if (difference.isNegative || difference.inMinutes < 1) {
    return l10n.commonJustNow;
  }
  if (difference.inMinutes < 60) {
    return l10n.commonMinutesAgo(difference.inMinutes);
  }
  if (difference.inHours < 24) return l10n.commonHoursAgo(difference.inHours);
  if (difference.inDays == 1) return l10n.commonYesterday;
  if (difference.inDays < 7) return l10n.commonDaysAgo(difference.inDays);
  return '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
}

String formatDate(DateTime? time) {
  if (time == null) return '';
  return '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = size >= 100 || unit == 0 ? 0 : 1;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}

String formatCount(int? value) {
  if (value == null || value <= 0) return '';
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '$value';
}
