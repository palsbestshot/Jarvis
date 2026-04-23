import 'package:intl/intl.dart';

class AppUtils {
  static String formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (e) {
      return isoDate;
    }
  }

  static String formatDateTime(DateTime dt) {
    return DateFormat('h:mm a').format(dt);
  }

  static String formatDateFromDateTime(DateTime dt) {
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  static String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else if (hour < 21) {
      return 'Good evening';
    } else {
      return 'Good night';
    }
  }

  static String getTodayDateFormatted() {
    return DateFormat('dd/MM/yyyy').format(DateTime.now());
  }

  static String getRelativeDateLabel(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final taskDate = DateTime(date.year, date.month, date.day);
      final diff = taskDate.difference(today).inDays;

      if (diff == 0) return 'Today';
      if (diff == 1) return 'Tomorrow';
      if (diff == -1) return 'Yesterday';
      if (diff > 1 && diff <= 7) return DateFormat('EEEE').format(date);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (e) {
      return isoDate;
    }
  }
}