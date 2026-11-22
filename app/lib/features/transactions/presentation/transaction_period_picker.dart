import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';

enum TransactionPeriod { week, month, year }

DateTimeRange transactionPeriod(DateTime date, TransactionPeriod period) {
  final day = DateUtils.dateOnly(date);
  return switch (period) {
    TransactionPeriod.week => DateTimeRange(
        start: DateTime(day.year, day.month, day.day - day.weekday + 1),
        end: DateTime(day.year, day.month, day.day - day.weekday + 7)),
    TransactionPeriod.month => DateTimeRange(
        start: DateTime(day.year, day.month),
        end: DateTime(day.year, day.month + 1, 0)),
    TransactionPeriod.year =>
      DateTimeRange(start: DateTime(day.year), end: DateTime(day.year, 12, 31)),
  };
}

Future<DateTimeRange?> showTransactionPeriodPicker({
  required BuildContext context,
  DateTimeRange? initialRange,
}) async {
  final l10n = AppLocalizations.of(context);
  final initial = initialRange ??
      transactionPeriod(DateTime.now(), TransactionPeriod.month);
  var anchor = initial.start;
  var period = TransactionPeriod.values.firstWhere(
      (p) => transactionPeriod(anchor, p) == initial,
      orElse: () => TransactionPeriod.month);
  var customRange = false;
  final result = await showDialog<DateTimeRange>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final range = transactionPeriod(anchor, period);
      final material = MaterialLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.t('Select period', 'Időszak kiválasztása')),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in TransactionPeriod.values)
                  ChoiceChip(
                    label: Text(switch (p) {
                      TransactionPeriod.week => l10n.t('Week', 'Hét'),
                      TransactionPeriod.month => l10n.t('Month', 'Hónap'),
                      TransactionPeriod.year => l10n.t('Year', 'Év'),
                    }),
                    selected: period == p,
                    onSelected: (_) => setState(() => period = p),
                  ),
                TextButton(
                  onPressed: () {
                    customRange = true;
                    Navigator.pop(context);
                  },
                  child: Text(l10n.t('Date range', 'Dátumtartomány')),
                ),
              ]),
              const SizedBox(height: 12),
              Text(l10n.t('Choose any date in the period.',
                  'Válassz egy napot az időszakon belül.')),
              CalendarDatePicker(
                initialDate: anchor,
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
                onDateChanged: (date) => setState(() => anchor = date),
              ),
              Text('${material.formatShortDate(range.start)} – '
                  '${material.formatShortDate(range.end)}'),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(material.cancelButtonLabel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, range),
              child: Text(material.okButtonLabel)),
        ],
      );
    }),
  );
  if (!customRange || !context.mounted) return result;
  return showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      initialDateRange: initialRange);
}
