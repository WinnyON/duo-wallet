/// Advance by the calendar, retaining an explicit original day across short months.
DateTime nextRecurringDate(DateTime due, String frequency, {int? anchorDay}) {
  if (frequency == 'daily') return DateTime(due.year, due.month, due.day + 1);
  if (frequency == 'weekly') return DateTime(due.year, due.month, due.day + 7);
  if (frequency != 'monthly' && frequency != 'yearly') {
    throw ArgumentError.value(frequency, 'frequency', 'Unsupported schedule');
  }
  final target = DateTime(due.year + (frequency == 'yearly' ? 1 : 0),
      due.month + (frequency == 'monthly' ? 1 : 0));
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  final day = anchorDay ?? due.day;
  return DateTime(target.year, target.month, day > lastDay ? lastDay : day);
}
