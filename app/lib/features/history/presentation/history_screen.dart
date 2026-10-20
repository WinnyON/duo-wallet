import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchCtrl = TextEditingController();
  late int _year;
  late int _month;
  ExpenseView _view = ExpenseView.together;
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _stepMonth(int delta) {
    setState(() {
      final next = DateTime(_year, _month + delta, 1);
      _year = next.year;
      _month = next.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);

    final query = _searchCtrl.text.trim().toLowerCase();

    final filtered = db.transactions.where((t) {
      if (t.occurredOn.year != _year || t.occurredOn.month != _month) {
        return false;
      }
      if (!isIncludedInView(t, _view, meId)) return false;
      if (_selectedCategoryId != null && t.categoryId != _selectedCategoryId) {
        return false;
      }
      if (query.isNotEmpty) {
        final m = (t.merchant ?? '').toLowerCase();
        final n = (t.note ?? '').toLowerCase();
        final tags = t.tags.map((e) => e.toLowerCase()).join(' ');
        if (!m.contains(query) && !n.contains(query) && !tags.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    final monthlyTotalMinor = filtered.fold<int>(
      0,
      (sum, t) => sum + amountFor(t, _view, meId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.history),
      ),
      body: Column(
        children: [
          // Year / Month selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _stepMonth(-1),
                ),
                Text(
                  '$_year-${_month.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _stepMonth(1),
                ),
              ],
            ),
          ),
          // ExpenseView filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ExpenseView>(
              segments: [
                ButtonSegment(
                  value: ExpenseView.together,
                  label: Text(l10n.viewTogether),
                ),
                ButtonSegment(
                  value: ExpenseView.individual,
                  label: Text(l10n.viewIndividual),
                ),
                ButtonSegment(
                  value: ExpenseView.myTotal,
                  label: Text(l10n.viewMyTotal),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          // Search + Category filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.t(
                        'Search merchant, note, tag...',
                        'Keresés (kereskedő, megjegyzés, címke)...',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedCategoryId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.t('Category', 'Kategória'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l10n.t('All', 'Mind')),
                      ),
                      ...db.categories.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(
                            c.localizedName(locale),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                ),
              ],
            ),
          ),
          // Monthly summary total card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              child: ListTile(
                title: Text(
                  l10n.t(
                    'Filtered Total (${filtered.length} items)',
                    'Szűrt összesen (${filtered.length} tétel)',
                  ),
                ),
                trailing: Text(
                  Money(monthlyTotalMinor).format(
                    locale: locale,
                    hideAmounts: hideAmounts,
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      l10n.t(
                        'No matching transactions.',
                        'Nincs találat a megadott szűrőkre.',
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final t = filtered[index];
                      final cat = t.categoryId != null
                          ? db.findCategory(t.categoryId!)
                          : null;
                      final amtMinor = amountFor(t, _view, meId);
                      final dateStr =
                          t.occurredOn.toIso8601String().split('T').first;
                      return ListTile(
                        title: Text(
                          t.merchant ?? cat?.localizedName(locale) ?? l10n.expense,
                        ),
                        subtitle: Text(
                          [
                            dateStr,
                            if (cat != null) cat.localizedName(locale),
                            if (t.note != null && t.note!.isNotEmpty) t.note!,
                            if (t.tags.isNotEmpty)
                              t.tags.map((e) => '#$e').join(' '),
                          ].join(' • '),
                        ),
                        trailing: Text(
                          Money(amtMinor).format(
                            locale: locale,
                            hideAmounts: hideAmounts,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
