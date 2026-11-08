import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../router.dart';
import '../../../theme.dart';
import '../../transactions/presentation/transactions_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  ExpenseView _view = ExpenseView.together;
  String? _category;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
        _search.clear();
        _category = null;
      });

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: _month,
        firstDate: DateTime(1970),
        lastDate: DateTime(2100, 12, 31));
    if (picked != null && mounted) {
      setState(() => _month = DateTime(picked.year, picked.month));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final me = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hidden = ref.watch(hideAmountsProvider);
    final l = AppLocalizations.of(context);
    final query = _search.text.trim().toLowerCase();
    final rows = db.transactions
        .where((t) =>
            t.occurredOn.year == _month.year &&
            t.occurredOn.month == _month.month &&
            isIncludedInView(t, _view, me) &&
            (_category == null || t.categoryId == _category) &&
            (query.isEmpty ||
                [t.merchant ?? '', t.note ?? '', ...t.tags]
                    .join(' ')
                    .toLowerCase()
                    .contains(query)))
        .toList();
    final total = rows.fold<int>(0, (s, t) => s + amountFor(t, _view, me));
    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => AppShell.goBackOrHome(context)),
          title: Text(l.history)),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
                l.t('Monthly expense report · HUF',
                    'Havi kiadáskimutatás · HUF'),
                style: Theme.of(context).textTheme.bodySmall),
            Row(children: [
              IconButton(
                  tooltip: l.t('Previous month', 'Előző hónap'),
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1))),
              Expanded(
                  child: TextButton(
                      onPressed: _pickMonth,
                      child: Text(DateFormat.yMMMM(locale).format(_month),
                          textAlign: TextAlign.center))),
              IconButton(
                  tooltip: l.t('Next month', 'Következő hónap'),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1))),
            ]),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => setState(() => _month =
                        DateTime(DateTime.now().year, DateTime.now().month)),
                    icon: const Icon(Icons.today),
                    label: Text(l.t('This month', 'Ez a hónap')))),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final view in ExpenseView.values)
                ChoiceChip(
                    label: Text(switch (view) {
                      ExpenseView.together => l.viewTogether,
                      ExpenseView.individual => l.viewIndividual,
                      ExpenseView.myTotal => l.viewMyTotal
                    }),
                    selected: _view == view,
                    onSelected: (_) => setState(() => _view = view))
            ]),
            const SizedBox(height: 12),
            TextField(
                controller: _search,
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: l.t('Merchant, note or tag',
                        'Kereskedő, megjegyzés vagy címke'),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l.t('Clear search', 'Keresés törlése'),
                            onPressed: () => setState(_search.clear),
                            icon: const Icon(Icons.close))),
                onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
                key: ValueKey(_category),
                initialValue: _category,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: l.t('Category', 'Kategória')),
                items: [
                  DropdownMenuItem(
                      value: null,
                      child: Text(l.t('All categories', 'Minden kategória'))),
                  for (final c in db.categories)
                    DropdownMenuItem(
                        value: c.id,
                        child: Text(c.localizedName(locale),
                            overflow: TextOverflow.ellipsis))
                ],
                onChanged: (v) => setState(() => _category = v)),
            const SizedBox(height: 12),
            DuoSection(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.t('Filtered total · ${rows.length} entries',
                              'Szűrt összesen · ${rows.length} tétel')),
                          Text(
                              Money(total)
                                  .format(locale: locale, hideAmounts: hidden),
                              style: Theme.of(context).textTheme.titleLarge),
                        ]))),
            if (rows.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Text(l.t('No expenses match this month and these filters.',
                        'Nincs a hónapnak és a szűrőknek megfelelő kiadás.')),
                    TextButton(
                        onPressed: _reset,
                        child: Text(l.t('Clear filters', 'Szűrők törlése'))),
                  ])),
            for (final t in rows)
              DuoSection(
                  child: InkWell(
                      onTap: () => showTransactionDetails(context, t),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  t.merchant ??
                                      db
                                          .findCategory(t.categoryId ?? '')
                                          ?.localizedName(locale) ??
                                      l.expense,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(
                                  DateFormat.yMMMd(locale).format(t.occurredOn),
                                  style: Theme.of(context).textTheme.bodySmall),
                              if (t.note?.isNotEmpty ?? false)
                                Text(t.note!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 8),
                              Text(
                                  Money(amountFor(t, _view, me)).format(
                                      locale: locale, hideAmounts: hidden),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ]),
                      ))),
          ]),
    );
  }
}
