import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  static const _uuid = Uuid();
  Scope _selectedScope = Scope.together;

  Color _thresholdColor(double ratio) {
    if (ratio >= 1.0) return Colors.red;
    if (ratio >= 0.8) return Colors.deepOrange;
    if (ratio >= 0.5) return Colors.amber.shade700;
    return Colors.green;
  }

  String _thresholdLabel(AppLocalizations l10n, double ratio) {
    if (ratio >= 1.0) return l10n.t('100%+ Exceeded', '100%+ Túllépve');
    if (ratio >= 0.8) return l10n.t('80% Warning', '80% Figyelmeztetés');
    if (ratio >= 0.5) return l10n.t('50% Reached', '50% Elérve');
    return l10n.t('On track', 'Rendben');
  }

  int _spentInMonth(
    Iterable<Txn> txns,
    ExpenseView view,
    String meId,
    int year,
    int month,
    String? categoryId,
  ) {
    var sum = 0;
    for (final t in txns) {
      if (t.occurredOn.year != year || t.occurredOn.month != month) continue;
      if (categoryId != null && t.categoryId != categoryId) continue;
      sum += amountFor(t, view, meId);
    }
    return sum;
  }

  Future<void> _showBudgetDialog(
    BuildContext context,
    AppDatabase db,
    String meId, {
    Budget? existing,
  }) async {
    final l10n = AppLocalizations.of(context);
    final expenseCats =
        db.categories.where((c) => c.kind == 'expense').toList();
    var scope = existing?.scope ?? _selectedScope;
    var categoryId = existing?.categoryId;
    var rollover = existing?.rollover ?? false;
    final amountCtrl = TextEditingController(
      text: existing != null ? (existing.amountMinor ~/ 100).toString() : '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? l10n.t('New Budget', 'Új költségkeret')
                : l10n.t('Edit Budget', 'Költségkeret szerkesztése'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<Scope>(
                  segments: [
                    ButtonSegment(
                      value: Scope.together,
                      label: Text('👥 ${l10n.viewTogether}'),
                    ),
                    ButtonSegment(
                      value: Scope.individual,
                      label: Text('🔒 ${l10n.viewMyTotal}'),
                    ),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) =>
                      setDialogState(() => scope = s.first),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: categoryId,
                  decoration: InputDecoration(
                    labelText: l10n.t('Category', 'Kategória'),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        l10n.t('Total Monthly Budget', 'Teljes havi keret'),
                      ),
                    ),
                    ...expenseCats.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.localizedName(l10n.locale.languageCode)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => categoryId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.t('Monthly Limit (HUF)', 'Havi keret (Ft)'),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.t(
                      'Rollover unused amount',
                      'Maradvány átvitele következő hónapra',
                    ),
                  ),
                  value: rollover,
                  onChanged: (v) => setDialogState(() => rollover = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.t('Cancel', 'Mégse')),
            ),
            FilledButton(
              onPressed: () {
                final major = int.tryParse(amountCtrl.text.trim()) ?? 0;
                if (major <= 0) return;
                final hhId = db.household?.id ?? 'hh-default-001';
                final budget = Budget(
                  id: existing?.id ?? _uuid.v4(),
                  householdId: hhId,
                  scope: scope,
                  ownerId: scope == Scope.individual ? meId : null,
                  categoryId: categoryId,
                  amountMinor: major * 100,
                  rollover: rollover,
                  updatedAt: DateTime.now(),
                );
                db.upsertBudget(budget);
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.t('Save', 'Mentés')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);
    final localeStr = l10n.locale.languageCode;

    final now = DateTime.now();
    final prevMonthDate = DateTime(now.year, now.month - 1, 1);
    final activeView = _selectedScope == Scope.together
        ? ExpenseView.together
        : ExpenseView.myTotal;

    final budgets = db.budgets.where((b) {
      if (_selectedScope == Scope.together) {
        return b.scope == Scope.together;
      }
      return b.scope == Scope.individual &&
          (b.ownerId == null || b.ownerId == meId);
    }).toList()
      ..sort((a, b) {
        if (a.categoryId == null && b.categoryId != null) return -1;
        if (a.categoryId != null && b.categoryId == null) return 1;
        return 0;
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.budgets),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.t('Add Budget', 'Új keret'),
            onPressed: () => _showBudgetDialog(context, db, meId),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<Scope>(
            segments: [
              ButtonSegment(
                value: Scope.together,
                label: Text(
                  '👥 ${l10n.t('Together Budgets', 'Közös keretek')}',
                ),
              ),
              ButtonSegment(
                value: Scope.individual,
                label: Text(
                  '🔒 ${l10n.t('My Budgets (My Total)', 'Saját keretek')}',
                ),
              ),
            ],
            selected: {_selectedScope},
            onSelectionChanged: (s) =>
                setState(() => _selectedScope = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedScope == Scope.together
                ? l10n.t(
                    'Shared with your partner • Tracks Together expenses',
                    'Megosztva a partnereddel • A Közös kiadásokat követi',
                  )
                : l10n.t(
                    'Private to you • Tracks My Total (individual + your share of Together)',
                    'Csak neked látható • A Saját összesen költést követi',
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (budgets.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      l10n.t(
                        'No budgets configured for this view yet.',
                        'Ehhez a nézethez még nincs beállítva költségkeret.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _showBudgetDialog(context, db, meId),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.t('Create Budget', 'Keret létrehozása')),
                    ),
                  ],
                ),
              ),
            ),
          for (final b in budgets)
            Builder(
              builder: (context) {
                final cat =
                    b.categoryId != null ? db.findCategory(b.categoryId!) : null;
                final title = cat != null
                    ? cat.localizedName(localeStr)
                    : l10n.t('Total Monthly Budget', 'Teljes havi keret');

                final spentMinor = _spentInMonth(
                  db.transactions,
                  activeView,
                  meId,
                  now.year,
                  now.month,
                  b.categoryId,
                );

                var rolloverBonusMinor = 0;
                if (b.rollover) {
                  final prevSpent = _spentInMonth(
                    db.transactions,
                    activeView,
                    meId,
                    prevMonthDate.year,
                    prevMonthDate.month,
                    b.categoryId,
                  );
                  if (prevSpent > 0 && prevSpent < b.amountMinor) {
                    rolloverBonusMinor = b.amountMinor - prevSpent;
                  }
                }

                final effectiveLimitMinor = b.amountMinor + rolloverBonusMinor;
                final ratio = effectiveLimitMinor > 0
                    ? spentMinor / effectiveLimitMinor
                    : 0.0;
                final color = _thresholdColor(ratio);
                final pctText = '${(ratio * 100).round()}%';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () =>
                        _showBudgetDialog(context, db, meId, existing: b),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  '$pctText • ${_thresholdLabel(l10n, ratio)}',
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: ratio.clamp(0.0, 1.0),
                              minHeight: 10,
                              color: color,
                              backgroundColor:
                                  Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${Money(spentMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} / '
                                '${Money(effectiveLimitMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.t('Rollover', 'Átvitel'),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Switch(
                                    value: b.rollover,
                                    onChanged: (v) {
                                      db.upsertBudget(
                                        Budget(
                                          id: b.id,
                                          householdId: b.householdId,
                                          scope: b.scope,
                                          ownerId: b.ownerId,
                                          categoryId: b.categoryId,
                                          amountMinor: b.amountMinor,
                                          rollover: v,
                                          updatedAt: DateTime.now(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
