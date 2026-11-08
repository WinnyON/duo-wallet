import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../router.dart';
import '../../../theme.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key, this.initialScope = 'shared'});
  final String initialScope;
  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  late String _scope;
  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope == 'personal' ? 'personal' : 'shared';
  }

  int _targetMonths = 6;

  Future<void> _edit(AppDatabase db, String me,
      {Goal? goal, bool savings = false}) async {
    final l = AppLocalizations.of(context);
    final name = TextEditingController(text: goal?.name ?? '');
    final amount = TextEditingController(
        text: goal == null
            ? ''
            : ((savings ? goal.savedAmountMinor : goal.targetAmountMinor) / 100)
                .toString());
    final form = GlobalKey<FormState>();
    var deadline = goal?.deadline;
    final initialName = name.text;
    final initialAmount = amount.text;
    bool dirty() =>
        name.text != initialName ||
        amount.text != initialAmount ||
        deadline != goal?.deadline;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          Future<void> close() async {
            if (await confirmDiscardChanges(ctx, dirty: dirty())) {
              if (ctx.mounted) Navigator.pop(ctx);
            }
          }

          return StatefulBuilder(
              builder: (ctx, update) => PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, result) {
                      if (!didPop) close();
                    },
                    child: AlertDialog(
                      title: Text(savings
                          ? l.t('Record savings', 'Megtakarítás rögzítése')
                          : goal == null
                              ? l.t('New goal', 'Új cél')
                              : l.t('Edit goal', 'Cél szerkesztése')),
                      content: SingleChildScrollView(
                          child: Form(
                              key: form,
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (savings)
                                      Text(l.t(
                                          'Set the correct total saved, including corrections or reversals. Account balances stay unchanged.',
                                          'Add meg a helyes teljes megtakarítást; javítás és visszavonás is lehetséges. A számlaegyenlegek nem változnak.')),
                                    if (!savings)
                                      TextFormField(
                                          controller: name,
                                          decoration: InputDecoration(
                                              labelText:
                                                  l.t('Name', 'Megnevezés')),
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                                  ? l.t('Enter a name',
                                                      'Adj meg nevet')
                                                  : null),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                        controller: amount,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                            labelText:
                                                '${savings ? l.t("Saved total", "Teljes megtakarítás") : l.t("Target", "Célösszeg")} (${goal?.currency.code ?? "HUF"})'),
                                        validator: (v) => parsePositiveAmount(
                                                    v ?? '',
                                                    allowZero: savings) ==
                                                null
                                            ? l.t('Enter a valid amount',
                                                'Adj meg érvényes összeget')
                                            : null),
                                    if (!savings)
                                      TextButton.icon(
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                                context: ctx,
                                                initialDate: deadline ??
                                                    DateTime.now().add(
                                                        const Duration(
                                                            days: 365)),
                                                firstDate: DateTime(2000),
                                                lastDate: DateTime(2200));
                                            if (picked != null) {
                                              update(() => deadline = picked);
                                            }
                                          },
                                          icon:
                                              const Icon(Icons.calendar_today),
                                          label: Text(deadline == null
                                              ? l.t('Choose deadline',
                                                  'Határidő kiválasztása')
                                              : DateFormat.yMMMd(
                                                      l.locale.languageCode)
                                                  .format(deadline!))),
                                  ]))),
                      actions: [
                        TextButton(
                            onPressed: close,
                            child: Text(l.t('Cancel', 'Mégse'))),
                        FilledButton(
                            onPressed: () {
                              if (!form.currentState!.validate()) return;
                              final minor = Money.fromMajor(
                                      parsePositiveAmount(amount.text,
                                          allowZero: savings)!,
                                      goal?.currency ?? CurrencyCode.huf)
                                  .amountMinor;
                              final json = goal?.toJson() ??
                                  Goal(
                                          id: const Uuid().v4(),
                                          householdId: db.household?.id ??
                                              'hh-default-001',
                                          name: name.text.trim(),
                                          scope: _scope,
                                          ownerId:
                                              _scope == 'personal' ? me : null,
                                          targetAmountMinor: minor,
                                          updatedAt: DateTime.now())
                                      .toJson();
                              if (savings) {
                                final difference =
                                    minor - goal!.savedAmountMinor;
                                final contributions = Map<String, int>.from(
                                    goal.contributionsByUser);
                                contributions[me] =
                                    (contributions[me] ?? 0) + difference;
                                json['saved_amount_minor'] = minor;
                                json['contributions_by_user'] = contributions;
                              } else {
                                json['name'] = name.text.trim();
                                json['target_amount_minor'] = minor;
                                json['deadline'] = deadline?.toIso8601String();
                              }
                              json['updated_at'] =
                                  DateTime.now().toIso8601String();
                              db.upsertGoal(Goal.fromJson(json));
                              Navigator.pop(ctx);
                            },
                            child: Text(l.t('Save', 'Mentés'))),
                      ],
                    ),
                  ));
        });
    name.dispose();
    amount.dispose();
  }

  Future<void> _remove(AppDatabase db, Goal goal) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(l.t('Archive goal?', 'Cél archiválása?')),
                content: Text(goal.name),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l.t('Cancel', 'Mégse'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l.t('Archive', 'Archiválás')))
                ]));
    if (confirmed == true) {
      db.upsertGoal(Goal.fromJson({
        ...goal.toJson(),
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String()
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final me = ref.watch(currentUserIdProvider);
    final hidden = ref.watch(hideAmountsProvider);
    final l = AppLocalizations.of(context);
    final locale = l.locale.languageCode;
    final goals = db.goals
        .where((g) =>
            g.deletedAt == null &&
            g.scope == _scope &&
            (g.isShared || g.ownerId == null || g.ownerId == me))
        .toList();
    final totals = <CurrencyCode, ({int saved, int target})>{};
    for (final goal in goals) {
      final old = totals[goal.currency] ?? (saved: 0, target: 0);
      totals[goal.currency] = (
        saved: old.saved + goal.savedAmountMinor,
        target: old.target + goal.targetAmountMinor
      );
    }
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 3);
    final end = DateTime(now.year, now.month);
    final essential =
        db.categories.where((c) => c.isEssential).map((c) => c.id).toSet();
    final history = db.transactions
        .where((t) =>
            !t.occurredOn.isBefore(start) &&
            t.occurredOn.isBefore(end) &&
            essential.contains(t.categoryId) &&
            amountFor(
                    t,
                    _scope == 'shared'
                        ? ExpenseView.together
                        : ExpenseView.myTotal,
                    me) >
                0)
        .toList();
    final essentialTotal = history.fold<int>(
        0,
        (sum, t) =>
            sum +
            amountFor(
                t,
                _scope == 'shared' ? ExpenseView.together : ExpenseView.myTotal,
                me));
    final efTarget = (essentialTotal / 3 * _targetMonths).round();
    String money(int value, CurrencyCode currency) =>
        Money(value, currency).format(locale: locale, hideAmounts: hidden);
    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.menu),
              tooltip: l.t('Menu', 'Menü'),
              onPressed: () => AppShell.openDrawer(context)),
          title: Text(l.goals),
          actions: [
            IconButton(
                tooltip: l.t('New goal', 'Új cél'),
                icon: const Icon(Icons.add),
                onPressed: () => _edit(db, me))
          ]),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
          children: [
            SegmentedButton<String>(segments: [
              ButtonSegment(
                  value: 'shared', label: Text(l.t('Shared', 'Közös'))),
              ButtonSegment(
                  value: 'personal', label: Text(l.t('Personal', 'Saját')))
            ], selected: {
              _scope
            }, onSelectionChanged: (s) => setState(() => _scope = s.first)),
            const SizedBox(height: 12),
            for (final entry in totals.entries)
              DuoSection(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(l.t('Saved / target', 'Megtakarítva / célösszeg')),
                    Text(
                        '${money(entry.value.saved, entry.key)} / ${money(entry.value.target, entry.key)}',
                        style: Theme.of(context).textTheme.titleLarge)
                  ])),
            DuoSection(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(l.emergencyFund,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(history.isEmpty
                      ? l.t(
                          'Insufficient essential spending history. Mark essential categories and record expenses to calculate a target.',
                          'Nincs elegendő alapvető kiadási adat. Jelöld az alapvető kategóriákat, és rögzíts kiadásokat a cél kiszámításához.')
                      : l.t(
                          'Suggested target: ${money(efTarget, CurrencyCode.huf)}',
                          'Javasolt cél: ${money(efTarget, CurrencyCode.huf)}')),
                  Text(l.t(
                      'Uses essential categories in the selected scope, averaged over the last three complete months (${DateFormat.yMMMd(locale).format(start)} – ${DateFormat.yMMMd(locale).format(end.subtract(const Duration(days: 1)))}).',
                      'A kiválasztott nézet alapvető kategóriáit használja az utolsó három teljes hónap átlagával (${DateFormat.yMMMd(locale).format(start)} – ${DateFormat.yMMMd(locale).format(end.subtract(const Duration(days: 1)))}).')),
                  DropdownButtonFormField<int>(
                      initialValue: _targetMonths,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText:
                              l.t('Months to cover', 'Fedezendő hónapok')),
                      items: [3, 6, 9, 12]
                          .map((n) =>
                              DropdownMenuItem(value: n, child: Text('$n')))
                          .toList(),
                      onChanged: (n) {
                        if (n != null) setState(() => _targetMonths = n);
                      }),
                ])),
            if (goals.isEmpty)
              DuoSection(
                  child: Column(children: [
                Text(l.t('No goals in this view yet.',
                    'Ebben a nézetben még nincs cél.')),
                TextButton(
                    onPressed: () => _edit(db, me),
                    child: Text(l.t('Create goal', 'Cél létrehozása')))
              ])),
            for (final g in goals)
              DuoSection(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(g.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    DuoProgressBar(
                        value: g.targetAmountMinor > 0
                            ? (g.savedAmountMinor / g.targetAmountMinor)
                                .clamp(0.0, 1.0)
                            : 0,
                        color: context.duo.positive),
                    const SizedBox(height: 8),
                    Text(
                        '${money(g.savedAmountMinor, g.currency)} / ${money(g.targetAmountMinor, g.currency)}'),
                    if (g.deadline != null)
                      Text(DateFormat.yMMMd(locale).format(g.deadline!)),
                    Wrap(spacing: 8, children: [
                      FilledButton.tonal(
                          onPressed: () =>
                              _edit(db, me, goal: g, savings: true),
                          child: Text(
                              l.t('Record savings', 'Megtakarítás rögzítése'))),
                      TextButton(
                          onPressed: () => _edit(db, me, goal: g),
                          child: Text(l.t('Edit', 'Szerkesztés'))),
                      TextButton(
                          onPressed: () => _remove(db, g),
                          child: Text(l.t('Archive', 'Archiválás'))),
                    ]),
                  ])),
          ]),
    );
  }
}
