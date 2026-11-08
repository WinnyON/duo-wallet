import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/budget_summary.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';
import '../../../router.dart';

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  static const _uuid = Uuid();
  Scope _selectedScope = Scope.together;

  Color _thresholdColor(BuildContext context, double ratio) {
    final duo = context.duo;
    if (ratio >= 1.0) return duo.negative;
    if (ratio >= 0.8) return duo.warning;
    if (ratio >= 0.5) return duo.info;
    return duo.positive;
  }

  String _thresholdLabel(AppLocalizations l10n, double ratio) {
    if (ratio >= 1.0) return l10n.t('100%+ Exceeded', '100%+ Túllépve');
    if (ratio >= 0.8) return l10n.t('80% Warning', '80% Figyelmeztetés');
    if (ratio >= 0.5) return l10n.t('50% Reached', '50% Elérve');
    return l10n.t('On track', 'Rendben');
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
      text: existing != null ? (existing.amountMinor / 100).toString() : '',
    );

    final formKey = GlobalKey<FormState>();
    final initialAmount = amountCtrl.text;
    final initialScope = scope;
    final initialCategory = categoryId;
    final initialRollover = rollover;
    Future<void> close(BuildContext ctx) async {
      if (await confirmDiscardChanges(ctx,
          dirty: amountCtrl.text != initialAmount ||
              scope != initialScope ||
              categoryId != initialCategory ||
              rollover != initialRollover)) {
        if (ctx.mounted) Navigator.of(ctx).pop();
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) close(ctx);
            },
            child: AlertDialog(
              title: Text(
                existing == null
                    ? l10n.t('New Budget', 'Új költségkeret')
                    : l10n.t('Edit Budget', 'Költségkeret szerkesztése'),
              ),
              content: SingleChildScrollView(
                child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SegmentedButton<Scope>(
                          segments: [
                            ButtonSegment(
                              value: Scope.together,
                              label: Text(l10n.viewTogether),
                            ),
                            ButtonSegment(
                              value: Scope.individual,
                              label: Text(l10n.viewMyTotal),
                            ),
                          ],
                          selected: {scope},
                          onSelectionChanged: (s) =>
                              setDialogState(() => scope = s.first),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          isExpanded: true,
                          initialValue: categoryId,
                          decoration: InputDecoration(
                            labelText: l10n.t('Category', 'Kategória'),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                l10n.t('Total Monthly Budget',
                                    'Teljes havi keret'),
                              ),
                            ),
                            ...expenseCats.map(
                              (c) => DropdownMenuItem<String?>(
                                value: c.id,
                                child: Text(
                                    c.localizedName(l10n.locale.languageCode)),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setDialogState(() => categoryId = v),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: amountCtrl,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (v) => parsePositiveAmount(v ?? '') == null
                              ? l10n.t('Enter a positive amount',
                                  'Adj meg pozitív összeget')
                              : null,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.t(
                                'Monthly Limit (HUF)', 'Havi keret (Ft)'),
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
                    )),
              ),
              actions: [
                TextButton(
                  onPressed: () => close(ctx),
                  child: Text(l10n.t('Cancel', 'Mégse')),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    final major = parsePositiveAmount(amountCtrl.text)!;
                    final hhId = db.household?.id ?? 'hh-default-001';
                    final budget = Budget(
                      id: existing?.id ?? _uuid.v4(),
                      householdId: hhId,
                      scope: scope,
                      ownerId: scope == Scope.individual ? meId : null,
                      categoryId: categoryId,
                      amountMinor:
                          Money.fromMajor(major, CurrencyCode.huf).amountMinor,
                      rollover: rollover,
                      updatedAt: DateTime.now(),
                    );
                    db.upsertBudget(budget);
                    Navigator.of(ctx).pop();
                  },
                  child: Text(l10n.t('Save', 'Mentés')),
                ),
              ],
            )),
      ),
    );
    amountCtrl.dispose();
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
        leading: IconButton(
            icon: const Icon(Icons.menu),
            tooltip: l10n.t("Menu", "Menü"),
            onPressed: () => AppShell.openDrawer(context)),
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
                  l10n.t('Together Budgets', 'Közös keretek'),
                ),
              ),
              ButtonSegment(
                value: Scope.individual,
                label: Text(
                  l10n.t('My Budgets (My Total)', 'Saját keretek'),
                ),
              ),
            ],
            selected: {_selectedScope},
            onSelectionChanged: (s) => setState(() => _selectedScope = s.first),
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
            DuoSection(
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
                final cat = b.categoryId != null
                    ? db.findCategory(b.categoryId!)
                    : null;
                final title = cat != null
                    ? cat.localizedName(localeStr)
                    : l10n.t('Total Monthly Budget', 'Teljes havi keret');

                final summary = budgetSummary(
                    budget: b,
                    transactions: db.transactions,
                    month: now,
                    meId: meId);
                final spentMinor = summary.spentMinor;
                final effectiveLimitMinor = summary.effectiveLimitMinor;
                final ratio = effectiveLimitMinor > 0
                    ? spentMinor / effectiveLimitMinor
                    : 0.0;
                final color = _thresholdColor(context, ratio);
                final pctText = '${(ratio * 100).round()}%';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Pressable(
                    onTap: () =>
                        _showBudgetDialog(context, db, meId, existing: b),
                    child: DuoSection(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Text(
                                  title,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                DuoBadge(
                                  '$pctText • ${_thresholdLabel(l10n, ratio)}',
                                  color: color,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            DuoProgressBar(
                              value: ratio.clamp(0.0, 1.0),
                              color: color,
                            ),
                            const SizedBox(height: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${Money(spentMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} / '
                                  '${Money(effectiveLimitMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                Text(
                                    '${spentMinor > effectiveLimitMinor ? l10n.t("Over budget", "Túllépés") : l10n.t("Remaining", "Maradvány")}: ${Money((effectiveLimitMinor - spentMinor).abs(), CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)}'),
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
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
