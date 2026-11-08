import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/projection.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';

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
  String? _createdScenario;
  bool _reviewing = false;

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
      final baseMinor =
          fx.convert(Money(balMinor, a.currency), CurrencyCode.huf).amountMinor;

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

    final start = parsePositiveAmount(_startCtrl.text, allowZero: true);
    final monthly = parsePositiveAmount(_monthlyCtrl.text, allowZero: true);
    double? signedRate(String text) {
      if (!RegExp(r'^-?\d+(?:[.,]\d+)?$').hasMatch(text.trim())) return null;
      final n = double.tryParse(text.trim().replaceAll(',', '.'));
      return n != null && n.isFinite && n >= -100 && n <= 100 ? n : null;
    }

    final annualRate = signedRate(_rateCtrl.text);
    final years = int.tryParse(_yearsCtrl.text.trim());
    final tax = parsePositiveAmount(_taxCtrl.text, allowZero: true);
    final inputsValid = start != null &&
        monthly != null &&
        annualRate != null &&
        years != null &&
        years >= 1 &&
        years <= 50 &&
        tax != null &&
        tax <= 100;
    var projectionSafe = true;
    if (inputsValid) {
      final periods = _compounding.periodsPerYear;
      final monthlyFactor =
          math.pow(1 + annualRate / 100 / periods, periods / 12) - 1;
      var balance = start * 100;
      for (var month = 0; month < years * 12; month++) {
        balance += balance * monthlyFactor * (1 - tax / 100) + monthly * 100;
        if (!balance.isFinite || balance.abs() > 9007199254740991) {
          projectionSafe = false;
          break;
        }
      }
    }
    final valid = inputsValid && projectionSafe;
    final calcProjection = valid
        ? project(
            startMinor: Money.fromMajor(start, CurrencyCode.huf).amountMinor,
            monthlyContributionMinor:
                Money.fromMajor(monthly, CurrencyCode.huf).amountMinor,
            annualRatePct: annualRate,
            compounding: _compounding,
            months: years * 12,
            taxPct: tax,
          )
        : const Projection([]);
    final scenario =
        '${_startCtrl.text}|${_monthlyCtrl.text}|${_rateCtrl.text}|${_yearsCtrl.text}|${_taxCtrl.text}|$_compounding';

    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.menu),
              tooltip: l10n.t("Menu", "Menü"),
              onPressed: () => AppShell.openDrawer(context)),
          title: Text(l10n.savings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Strictly separated Net Worth cards (Mine vs Common)
          Column(
            children: [
              SizedBox(
                child: DuoSection(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.netWorthMine,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Money(myNetWorthMinor, CurrencyCode.huf).format(
                            locale: localeStr,
                            hideAmounts: hideAmounts,
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
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
              SizedBox(
                child: DuoSection(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.netWorthCommon,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Money(commonNetWorthMinor, CurrencyCode.huf).format(
                            locale: localeStr,
                            hideAmounts: hideAmounts,
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
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
            DuoSection(
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
                return DuoSection(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: MerchantAvatar(
                      name: a.name,
                      icon: Icons.savings_outlined,
                    ),
                    title: Text(
                      '${a.name} • ${rate.toStringAsFixed(2)}%',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    subtitle: Text(
                      '${l10n.t("Current:", "Jelenlegi:")} '
                      '${Money(balMinor, a.currency).format(locale: localeStr, hideAmounts: hideAmounts)}  →  '
                      '${l10n.t("In 1 yr:", "1 év múlva:")} '
                      '${Money(proj.finalBalanceMinor, a.currency).format(locale: localeStr, hideAmounts: hideAmounts)} '
                      '(+${Money(proj.totalInterestMinor, a.currency).format(locale: localeStr, hideAmounts: hideAmounts)})',
                      style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),

          // Standalone Interest Calculator
          DuoSection(
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
                  Column(
                    children: [
                      SizedBox(
                        child: TextField(
                          controller: _startCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            errorText: start == null
                                ? l10n.t('Enter a nonnegative amount',
                                    'Adj meg nem negatív összeget')
                                : null,
                            labelText:
                                l10n.t('Starting (HUF)', 'Kezdő összeg (Ft)'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        child: TextField(
                          controller: _monthlyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            errorText: monthly == null
                                ? l10n.t('Enter a nonnegative amount',
                                    'Adj meg nem negatív összeget')
                                : null,
                            labelText: l10n.t(
                                'Monthly (HUF)', 'Havi megtakarítás (Ft)'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      SizedBox(
                        child: TextField(
                          controller: _rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            errorText: annualRate == null
                                ? l10n.t('Use a rate from −100 to 100',
                                    '−100 és 100 közötti kamat szükséges')
                                : null,
                            labelText: l10n.t('Annual Rate %', 'Éves kamat %'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        child: TextField(
                          controller: _yearsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            errorText: years == null || years < 1 || years > 50
                                ? l10n.t('Use 1–50 years', '1–50 év szükséges')
                                : null,
                            labelText: l10n.t('Years', 'Futamidő (év)'),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        child: TextField(
                          controller: _taxCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            errorText: tax == null || tax > 100
                                ? l10n.t('Use 0–100%', '0–100% szükséges')
                                : null,
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
                  if (inputsValid && !projectionSafe)
                    Text(
                        l10n.t(
                            'This projection exceeds supported money precision. Reduce the amount, rate or duration.',
                            'A terv meghaladja a támogatott pénzpontosságot. Csökkentsd az összeget, kamatot vagy futamidőt.'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (valid)
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
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
                    onPressed:
                        _reviewing ||
                                !valid ||
                                calcProjection.finalBalanceMinor <= 0
                            ? null
                            : _createdScenario == scenario
                                ? () => context.push('/goals?scope=personal')
                                : () async {
                                    setState(() => _reviewing = true);
                                    final name = TextEditingController(
                                        text: l10n.t('Savings plan',
                                            'Megtakarítási terv'));
                                    final now = DateTime.now();
                                    var deadline = DateTime(
                                        now.year + years, now.month, now.day);
                                    final form = GlobalKey<FormState>();
                                    final approved = await showDialog<bool>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (ctx) => StatefulBuilder(
                                            builder: (ctx, update) => PopScope(
                                                canPop: false,
                                                onPopInvokedWithResult:
                                                    (didPop, result) async {
                                                  if (didPop) return;
                                                  final discard =
                                                      await confirmDiscardChanges(
                                                          ctx,
                                                          dirty: name.text !=
                                                                  l10n.t(
                                                                      'Savings plan',
                                                                      'Megtakarítási terv') ||
                                                              deadline !=
                                                                  DateTime(
                                                                      now.year +
                                                                          years,
                                                                      now.month,
                                                                      now.day));
                                                  if (discard && ctx.mounted) {
                                                    Navigator.pop(ctx, false);
                                                  }
                                                },
                                                child: AlertDialog(
                                                  title: Text(l10n.t(
                                                      'Review goal',
                                                      'Cél áttekintése')),
                                                  content:
                                                      SingleChildScrollView(
                                                          child: Form(
                                                              key: form,
                                                              child: Column(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    TextFormField(
                                                                        controller:
                                                                            name,
                                                                        decoration: InputDecoration(
                                                                            labelText: l10n.t('Goal name',
                                                                                'Cél neve')),
                                                                        validator: (v) => v == null ||
                                                                                v.trim().isEmpty
                                                                            ? l10n.t('Enter a name', 'Adj meg nevet')
                                                                            : null),
                                                                    Text(Money(
                                                                            calcProjection
                                                                                .finalBalanceMinor,
                                                                            CurrencyCode
                                                                                .huf)
                                                                        .format(
                                                                            locale:
                                                                                localeStr,
                                                                            hideAmounts:
                                                                                hideAmounts)),
                                                                    TextButton(
                                                                        onPressed:
                                                                            () async {
                                                                          final date = await showDatePicker(
                                                                              context: ctx,
                                                                              initialDate: deadline,
                                                                              firstDate: DateTime.now(),
                                                                              lastDate: DateTime(2200));
                                                                          if (date !=
                                                                              null) {
                                                                            update(() =>
                                                                                deadline = date);
                                                                          }
                                                                        },
                                                                        child: Text(
                                                                            DateFormat.yMMMd(localeStr).format(deadline))),
                                                                    Text(l10n.t(
                                                                        'Projection assumes constant rates and monthly deposits; returns are not guaranteed. Recording a goal does not move account money.',
                                                                        'A terv állandó kamatot és havi befizetést feltételez; a hozam nem garantált. A cél rögzítése nem mozgat számlapénzt.')),
                                                                  ]))),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () async {
                                                          if (await confirmDiscardChanges(
                                                              ctx,
                                                              dirty: name.text !=
                                                                      l10n.t(
                                                                          'Savings plan',
                                                                          'Megtakarítási terv') ||
                                                                  deadline !=
                                                                      DateTime(
                                                                          now.year +
                                                                              years,
                                                                          now.month,
                                                                          now.day))) {
                                                            if (ctx.mounted) {
                                                              Navigator.pop(
                                                                  ctx, false);
                                                            }
                                                          }
                                                        },
                                                        child: Text(l10n.t(
                                                            'Cancel',
                                                            'Mégse'))),
                                                    FilledButton(
                                                        onPressed: () {
                                                          if (form.currentState!
                                                              .validate()) {
                                                            Navigator.pop(
                                                                ctx, true);
                                                          }
                                                        },
                                                        child: Text(l10n.t(
                                                            'Create goal',
                                                            'Cél létrehozása')))
                                                  ],
                                                ))));
                                    if (approved == true &&
                                        mounted &&
                                        _createdScenario != scenario) {
                                      db.upsertGoal(Goal(
                                          id: _uuid.v4(),
                                          householdId: db.household?.id ??
                                              'hh-default-001',
                                          name: name.text.trim(),
                                          scope: 'personal',
                                          ownerId: meId,
                                          targetAmountMinor:
                                              calcProjection.finalBalanceMinor,
                                          savedAmountMinor: Money.fromMajor(
                                                  start, CurrencyCode.huf)
                                              .amountMinor,
                                          annualInterestRatePct: annualRate,
                                          deadline: deadline,
                                          updatedAt: DateTime.now()));
                                      setState(
                                          () => _createdScenario = scenario);
                                    }
                                    name.dispose();
                                    if (mounted) {
                                      setState(() => _reviewing = false);
                                    }
                                  },
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(
                      _createdScenario == scenario
                          ? l10n.t('View goal', 'Cél megtekintése')
                          : l10n.t('Create Goal from Scenario',
                              'Cél létrehozása ebből a tervből'),
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
