import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/projection.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';

class SavingsScreen extends ConsumerStatefulWidget {
  const SavingsScreen({super.key});

  @override
  ConsumerState<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends ConsumerState<SavingsScreen> {
  static const _uuid = Uuid();

  final _startCtrl = TextEditingController(text: '500000');
  final _monthlyCtrl = TextEditingController(text: '50000');
  final _rateCtrl = TextEditingController(text: '6.5');
  final _yearsCtrl = TextEditingController(text: '3');
  final _taxCtrl = TextEditingController(text: '0');
  Compounding _compounding = Compounding.monthly;

  @override
  void dispose() {
    _startCtrl.dispose();
    _monthlyCtrl.dispose();
    _rateCtrl.dispose();
    _yearsCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final fx = ref.watch(fxServiceProvider);
    final meId = ref.watch(currentUserIdProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);
    final localeStr = l10n.locale.languageCode;

    var myNetWorthMinor = 0;
    var commonNetWorthMinor = 0;
    final savingsAccounts = <Account>[];

    for (final a in db.accounts) {
      if (a.archived) continue;
      final isMine =
          a.ownership == AccountOwnership.personal && a.ownerId == meId;
      final isCommon = a.ownership == AccountOwnership.common;
      if (!isMine && !isCommon) continue;

      final balMinor = db.computeAccountBalanceMinor(
        a.id,
        currentUserId: meId,
      );
      final baseMinor = fx
          .convert(Money(balMinor, a.currency), CurrencyCode.huf)
          .amountMinor;

      if (a.includeInNetWorth) {
        if (isMine) {
          myNetWorthMinor += baseMinor;
        } else if (isCommon) {
          commonNetWorthMinor += baseMinor;
        }
      }

      if (a.type == AccountType.savings ||
          a.type == AccountType.deposit ||
          (a.interestRatePct ?? 0) > 0) {
        savingsAccounts.add(a);
      }
    }

    final startMajor = int.tryParse(_startCtrl.text.trim()) ?? 0;
    final monthlyMajor = int.tryParse(_monthlyCtrl.text.trim()) ?? 0;
    final annualRate =
        double.tryParse(_rateCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
    final years = (int.tryParse(_yearsCtrl.text.trim()) ?? 1).clamp(1, 50);
    final taxPct =
        double.tryParse(_taxCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;

    final calcProjection = project(
      startMinor: startMajor * 100,
      monthlyContributionMinor: monthlyMajor * 100,
      annualRatePct: annualRate,
      compounding: _compounding,
      months: years * 12,
      taxPct: taxPct,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.savings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Strictly separated Net Worth cards (Mine 🔒 vs Common 👥)
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔒 ${l10n.netWorthMine}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Money(myNetWorthMinor, CurrencyCode.huf).format(
                            locale: localeStr,
                            hideAmounts: hideAmounts,
                          ),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.t(
                            'Your personal accounts only',
                            'Csak a saját számláid',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '👥 ${l10n.netWorthCommon}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Money(commonNetWorthMinor, CurrencyCode.huf).format(
                            locale: localeStr,
                            hideAmounts: hideAmounts,
                          ),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.t(
                            'Shared common accounts',
                            'Közös számlák egyenlege',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Savings & Deposit Projections
          Text(
            l10n.t(
              'Savings & Deposit Projections (12 Months)',
              'Megtakarítási és lekötési előrejelzés (12 hó)',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (savingsAccounts.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.t(
                    'No savings or interest-bearing accounts yet.',
                    'Még nincs kamatozó megtakarítási számla.',
                  ),
                ),
              ),
            ),
          for (final a in savingsAccounts)
            Builder(
              builder: (context) {
                final balMinor = db.computeAccountBalanceMinor(
                  a.id,
                  currentUserId: meId,
                );
                final rate = a.interestRatePct ?? 0.0;
                final comp = a.compounding ?? Compounding.monthly;
                final proj = project(
                  startMinor: balMinor,
                  monthlyContributionMinor: 0,
                  annualRatePct: rate,
                  compounding: comp,
                  months: 12,
                  taxPct: a.interestTaxPct,
                );
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.savings_outlined),
                    title: Text(
                      '${a.name} (${a.isCommon ? "👥" : "🔒"}) • ${rate.toStringAsFixed(2)}%',
                    ),
                    subtitle: Text(
                      '${l10n.t("Current:", "Jelenlegi:")} '
                      '${Money(balMinor, a.currency).format(locale: localeStr, hideAmounts: hideAmounts)}  →  '
                      '${l10n.t("In 1 yr:", "1 év múlva:")} '
                      '${Money(proj.finalBalanceMinor, a.currency).format(locale: localeStr, hideAmounts: hideAmounts)} '
                      '(+${Money(proj.totalInterestMinor, a.currency).format(locale: localeStr, hideAmounts: hideAmounts)})',
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),

          // Standalone Interest Calculator
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.interestCalculator,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _startCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText:
                                l10n.t('Starting (HUF)', 'Kezdő összeg (Ft)'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _monthlyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText:
                                l10n.t('Monthly (HUF)', 'Havi megtakarítás (Ft)'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: l10n.t('Annual Rate %', 'Éves kamat %'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _yearsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.t('Years', 'Futamidő (év)'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _taxCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: l10n.t('Tax %', 'Kamatadó %'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Compounding>(
                    initialValue: _compounding,
                    decoration: InputDecoration(
                      labelText: l10n.t('Compounding', 'Tőkésítés'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: Compounding.daily,
                        child: Text(l10n.t('Daily', 'Napi')),
                      ),
                      DropdownMenuItem(
                        value: Compounding.monthly,
                        child: Text(l10n.t('Monthly', 'Havi')),
                      ),
                      DropdownMenuItem(
                        value: Compounding.quarterly,
                        child: Text(l10n.t('Quarterly', 'Negyedéves')),
                      ),
                      DropdownMenuItem(
                        value: Compounding.yearly,
                        child: Text(l10n.t('Yearly', 'Éves')),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _compounding = v);
                    },
                  ),
                  const Divider(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _resultItem(
                        context,
                        l10n.t('Final Value', 'Végső érték'),
                        Money(
                          calcProjection.finalBalanceMinor,
                          CurrencyCode.huf,
                        ).format(locale: localeStr, hideAmounts: hideAmounts),
                      ),
                      _resultItem(
                        context,
                        l10n.t('Contributed', 'Befizetett'),
                        Money(
                          calcProjection.totalContributedMinor,
                          CurrencyCode.huf,
                        ).format(locale: localeStr, hideAmounts: hideAmounts),
                      ),
                      _resultItem(
                        context,
                        l10n.t('Net Interest', 'Nettó kamat'),
                        Money(
                          calcProjection.totalInterestMinor,
                          CurrencyCode.huf,
                        ).format(locale: localeStr, hideAmounts: hideAmounts),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final now = DateTime.now();
                      final hhId = db.household?.id ?? 'hh-default-001';
                      db.upsertGoal(
                        Goal(
                          id: _uuid.v4(),
                          householdId: hhId,
                          name: l10n.t(
                            'Savings Plan ($years yr)',
                            'Megtakarítási terv ($years év)',
                          ),
                          type: 'savings',
                          scope: 'personal',
                          ownerId: meId,
                          targetAmountMinor: calcProjection.finalBalanceMinor,
                          savedAmountMinor: startMajor * 100,
                          annualInterestRatePct: annualRate,
                          deadline: DateTime(
                            now.year + years,
                            now.month,
                            now.day,
                          ),
                          updatedAt: now,
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.t(
                              'Personal goal created from scenario!',
                              'Saját cél létrehozva a kalkulációból!',
                            ),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(
                      l10n.t(
                        'Create Goal from Scenario',
                        'Cél létrehozása ebből a tervből',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultItem(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
