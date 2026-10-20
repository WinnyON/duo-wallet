import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/projection.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  static const _uuid = Uuid();
  String _scopeFilter = 'shared'; // 'shared' | 'personal'

  Future<void> _showContributeDialog(
    BuildContext context,
    AppDatabase db,
    String meId,
    Goal goal,
  ) async {
    final l10n = AppLocalizations.of(context);
    final amountCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${l10n.t("Contribute to", "Befizetés ide:")} ${goal.name}',
        ),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText:
                '${l10n.t("Amount", "Összeg")} (${goal.currency.code})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.t('Cancel', 'Mégse')),
          ),
          FilledButton(
            onPressed: () {
              final major =
                  double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ??
                      0;
              if (major <= 0) return;
              final money = Money.fromMajor(major, goal.currency);
              final updatedContribs =
                  Map<String, int>.from(goal.contributionsByUser);
              updatedContribs[meId] =
                  (updatedContribs[meId] ?? 0) + money.amountMinor;

              final updatedGoal = Goal(
                id: goal.id,
                householdId: goal.householdId,
                name: goal.name,
                type: goal.type,
                scope: goal.scope,
                ownerId: goal.ownerId,
                targetAmountMinor: goal.targetAmountMinor,
                currency: goal.currency,
                deadline: goal.deadline,
                savedAmountMinor: goal.savedAmountMinor + money.amountMinor,
                annualInterestRatePct: goal.annualInterestRatePct,
                linkedAccountIds: goal.linkedAccountIds,
                contributionsByUser: updatedContribs,
                updatedAt: DateTime.now(),
              );
              db.upsertGoal(updatedGoal);

              if (goal.isShared) {
                final meName = db.findProfile(meId)?.displayName ?? 'Partner';
                db.addActivity(
                  ActivityEvent(
                    id: _uuid.v4(),
                    householdId: goal.householdId,
                    actorId: meId,
                    eventType: 'goal_milestone',
                    summaryEn:
                        '$meName contributed ${money.format(locale: "en")} to ${goal.name}',
                    summaryHu:
                        '$meName befizetett ${money.format(locale: "hu")}-ot ide: ${goal.name}',
                    amountMinor: money.amountMinor,
                    currency: goal.currency,
                    createdAt: DateTime.now(),
                  ),
                );
              }
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.t('Contribute', 'Befizetés')),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateGoalDialog(
    BuildContext context,
    AppDatabase db,
    String meId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: '5.0');
    final monthsCtrl = TextEditingController(text: '12');
    var scope = _scopeFilter;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.t('New Goal', 'Új cél')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'shared',
                      label: Text('👥 ${l10n.sharedBadge}'),
                    ),
                    ButtonSegment(
                      value: 'personal',
                      label: Text('🔒 ${l10n.privateBadge}'),
                    ),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) =>
                      setDialogState(() => scope = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.t('Goal Name', 'Cél megnevezése'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: targetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.t('Target Amount (HUF)', 'Célösszeg (Ft)'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.t('Interest %', 'Kamat %'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: monthsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              l10n.t('Months to deadline', 'Hónapok száma'),
                        ),
                      ),
                    ),
                  ],
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
                final name = nameCtrl.text.trim();
                final targetMajor = int.tryParse(targetCtrl.text.trim()) ?? 0;
                if (name.isEmpty || targetMajor <= 0) return;
                final rate =
                    double.tryParse(rateCtrl.text.trim().replaceAll(',', '.')) ??
                        0.0;
                final months =
                    (int.tryParse(monthsCtrl.text.trim()) ?? 12).clamp(1, 600);
                final now = DateTime.now();

                db.upsertGoal(
                  Goal(
                    id: _uuid.v4(),
                    householdId: db.household?.id ?? 'hh-default-001',
                    name: name,
                    type: 'savings',
                    scope: scope,
                    ownerId: scope == 'personal' ? meId : null,
                    targetAmountMinor: targetMajor * 100,
                    savedAmountMinor: 0,
                    annualInterestRatePct: rate,
                    deadline: DateTime(now.year, now.month + months, now.day),
                    updatedAt: now,
                  ),
                );
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

    // Filter out any personal goal not owned by currentUserId
    final visibleGoals = db.goals.where((g) {
      if (g.isShared) return _scopeFilter == 'shared';
      return _scopeFilter == 'personal' &&
          (g.ownerId == null || g.ownerId == meId);
    }).toList();

    final essentialCatIds = db.categories
        .where((c) => c.isEssential)
        .map((c) => c.id)
        .toSet();
    final targetMonths = db.household?.emergencyFundMonths ?? 6;

    final computedSharedEfTarget = computeEmergencyFundTarget(
      transactions: db.transactions,
      essentialCategoryIds: essentialCatIds,
      isSharedFund: true,
      meId: meId,
      targetMonths: targetMonths,
    );
    final computedPersonalEfTarget = computeEmergencyFundTarget(
      transactions: db.transactions,
      essentialCategoryIds: essentialCatIds,
      isSharedFund: false,
      meId: meId,
      targetMonths: targetMonths,
    );

    final sharedEfGoal = db.goals
        .where((g) => g.isEmergencyFund && g.isShared)
        .firstOrNull;
    final personalEfGoal = db.goals
        .where(
          (g) =>
              g.isEmergencyFund &&
              !g.isShared &&
              (g.ownerId == null || g.ownerId == meId),
        )
        .firstOrNull;

    final sharedEfTargetMinor = sharedEfGoal?.targetAmountMinor ??
        (computedSharedEfTarget > 0 ? computedSharedEfTarget : 60000000);
    final sharedEfSavedMinor = sharedEfGoal?.savedAmountMinor ?? 0;
    final sharedMonthlyEssential = targetMonths > 0
        ? (sharedEfTargetMinor / targetMonths)
        : 1.0;
    final sharedMonthsCovered = sharedMonthlyEssential > 0
        ? (sharedEfSavedMinor / sharedMonthlyEssential)
        : 0.0;

    final personalEfTargetMinor = personalEfGoal?.targetAmountMinor ??
        (computedPersonalEfTarget > 0 ? computedPersonalEfTarget : 45000000);
    final personalEfSavedMinor = personalEfGoal?.savedAmountMinor ?? 0;
    final personalMonthlyEssential = targetMonths > 0
        ? (personalEfTargetMinor / targetMonths)
        : 1.0;
    final personalMonthsCovered = personalMonthlyEssential > 0
        ? (personalEfSavedMinor / personalMonthlyEssential)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.goals),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateGoalDialog(context, db, meId),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Emergency Fund Summary Card (Shared 👥 and Personal 🔒)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.emergencyFund} ($targetMonths ${l10n.t("months target", "havi cél")})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '👥 ${l10n.t("Shared Emergency Fund:", "Közös vésztartalék:")} '
                    '${Money(sharedEfSavedMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} / '
                    '${Money(sharedEfTargetMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} '
                    '• ${sharedMonthsCovered.toStringAsFixed(1)} ${l10n.t("months covered", "hónap fedezve")}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '🔒 ${l10n.t("Personal Emergency Fund:", "Saját vésztartalék:")} '
                    '${Money(personalEfSavedMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} / '
                    '${Money(personalEfTargetMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} '
                    '• ${personalMonthsCovered.toStringAsFixed(1)} ${l10n.t("months covered", "hónap fedezve")}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.t(
                      'Auto-calculated from essential expenses: ${Money(computedSharedEfTarget, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} (Shared) / ${Money(computedPersonalEfTarget, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} (My Total)',
                      'Alapvető kiadásokból számított $targetMonths havi cél: ${Money(computedSharedEfTarget, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} (Közös) / ${Money(computedPersonalEfTarget, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)} (Saját)',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'shared',
                label: Text('👥 ${l10n.t("Shared Goals", "Közös célok")}'),
              ),
              ButtonSegment(
                value: 'personal',
                label: Text('🔒 ${l10n.t("Personal Goals", "Saját célok")}'),
              ),
            ],
            selected: {_scopeFilter},
            onSelectionChanged: (s) =>
                setState(() => _scopeFilter = s.first),
          ),
          const SizedBox(height: 16),

          if (visibleGoals.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  l10n.t(
                    'No goals in this view yet.',
                    'Ebben a nézetben még nincs cél.',
                  ),
                ),
              ),
            ),

          for (final g in visibleGoals)
            Builder(
              builder: (context) {
                final progress = g.targetAmountMinor > 0
                    ? (g.savedAmountMinor / g.targetAmountMinor).clamp(0.0, 1.0)
                    : 0.0;
                final pct = (progress * 100).round();

                int? requiredMonthlyMinor;
                if (g.deadline != null &&
                    g.savedAmountMinor < g.targetAmountMinor) {
                  final monthsLeft = ((g.deadline!.year - now.year) * 12 +
                          (g.deadline!.month - now.month))
                      .clamp(1, 600);
                  requiredMonthlyMinor = solveRequiredMonthlyContribution(
                    startMinor: g.savedAmountMinor,
                    targetMinor: g.targetAmountMinor,
                    annualRatePct: g.annualInterestRatePct,
                    compounding: Compounding.monthly,
                    months: monthsLeft,
                  );
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${g.isShared ? "👥" : "🔒"} ${g.name}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              '$pct%',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${Money(g.savedAmountMinor, g.currency).format(locale: localeStr, hideAmounts: hideAmounts)} / '
                          '${Money(g.targetAmountMinor, g.currency).format(locale: localeStr, hideAmounts: hideAmounts)}',
                        ),
                        if (requiredMonthlyMinor != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            l10n.t(
                              'Required monthly saving: ${Money(requiredMonthlyMinor, g.currency).format(locale: localeStr, hideAmounts: hideAmounts)}/mo',
                              'Szükséges havi megtakarítás: ${Money(requiredMonthlyMinor, g.currency).format(locale: localeStr, hideAmounts: hideAmounts)}/hó',
                            ),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (g.isShared && g.contributionsByUser.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            children: g.contributionsByUser.entries.map((e) {
                              final name =
                                  db.findProfile(e.key)?.displayName ?? e.key;
                              final amt = Money(e.value, g.currency).format(
                                locale: localeStr,
                                hideAmounts: hideAmounts,
                              );
                              return Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text('$name: $amt'),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: () =>
                                _showContributeDialog(context, db, meId, g),
                            icon: const Icon(Icons.add),
                            label: Text(l10n.t('Contribute', 'Befizetés')),
                          ),
                        ),
                      ],
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
