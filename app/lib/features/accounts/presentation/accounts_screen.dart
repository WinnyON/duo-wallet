import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';
import '../../../router.dart';
import '../../transfers/presentation/transfer_sheet.dart';

double? parseSignedAccountAmount(String text) {
  final value = text.trim();
  final negative = value.startsWith('-');
  final parsed = parsePositiveAmount(negative ? value.substring(1) : value,
      allowZero: true);
  return parsed == null
      ? null
      : negative
          ? -parsed
          : parsed;
}

String accountTypeLabel(AccountType type, AppLocalizations l10n) =>
    switch (type) {
      AccountType.bank => l10n.t('Bank', 'Bankszámla'),
      AccountType.cash => l10n.t('Cash', 'Készpénz'),
      AccountType.savings => l10n.t('Savings', 'Megtakarítás'),
      AccountType.deposit => l10n.t('Deposit', 'Lekötött betét'),
      AccountType.investment => l10n.t('Investment', 'Befektetés'),
    };
String compoundingLabel(Compounding value, AppLocalizations l10n) =>
    switch (value) {
      Compounding.daily => l10n.t('Daily', 'Naponta'),
      Compounding.monthly => l10n.t('Monthly', 'Havonta'),
      Compounding.quarterly => l10n.t('Quarterly', 'Negyedévente'),
      Compounding.yearly => l10n.t('Yearly', 'Évente'),
    };

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  static Future<void> showAccountDialog(
      BuildContext context, AppDatabase db, String meId,
      {Account? existing, AccountOwnership? initialOwnership}) async {
    final l10n = AppLocalizations.of(context);
    final form = GlobalKey<FormState>();
    final nameFocus = FocusNode();
    final openingFocus = FocusNode();
    final rateFocus = FocusNode();
    final taxFocus = FocusNode();
    final name = TextEditingController(text: existing?.name ?? '');
    final opening = TextEditingController(
        text: existing == null
            ? '0'
            : Money(existing.openingBalanceMinor, existing.currency)
                .majorAmount
                .toStringAsFixed(2));
    final rate = TextEditingController(
        text: existing?.interestRatePct?.toString() ?? '0');
    final tax =
        TextEditingController(text: (existing?.interestTaxPct ?? 0).toString());
    var type = existing?.type ?? AccountType.bank;
    var ownership =
        existing?.ownership ?? initialOwnership ?? AccountOwnership.personal;
    var currency = existing?.currency ?? CurrencyCode.huf;
    var compounding = existing?.compounding ?? Compounding.monthly;
    final linked = existing != null &&
        db.transactions.any(
            (t) => t.accountId == existing.id || t.toAccountId == existing.id);
    String draft() =>
        '${name.text}|${opening.text}|${rate.text}|${tax.text}|$type|$ownership|$currency|$compounding';
    final initial = draft();
    Future<void> close(BuildContext ctx) async {
      if (await confirmDiscardChanges(ctx, dirty: draft() != initial) &&
          ctx.mounted) {
        Navigator.pop(ctx);
      }
    }

    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
              final interest =
                  type == AccountType.savings || type == AccountType.deposit;
              final invalid =
                  l10n.t('Enter a valid number.', 'Adj meg érvényes számot.');
              return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) close(ctx);
                  },
                  child: AlertDialog(
                      scrollable: true,
                      title: Text(existing == null
                          ? l10n.t('New account', 'Új számla')
                          : l10n.t('Edit account', 'Számla szerkesztése')),
                      content: Form(
                          key: form,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            TextFormField(
                                controller: name,
                                focusNode: nameFocus,
                                decoration: InputDecoration(
                                    labelText:
                                        l10n.t('Account name', 'Számla neve')),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? l10n.t('Enter a name.', 'Adj meg nevet.')
                                    : null),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<AccountOwnership>(
                                isExpanded: true,
                                initialValue: ownership,
                                decoration: InputDecoration(
                                    labelText: l10n.t('Ownership / visibility',
                                        'Tulajdon / láthatóság')),
                                items: [
                                  DropdownMenuItem(
                                      value: AccountOwnership.personal,
                                      child: Text(l10n.personalAccount)),
                                  DropdownMenuItem(
                                      value: AccountOwnership.common,
                                      child: Text(l10n.commonAccount))
                                ],
                                onChanged: linked
                                    ? null
                                    : (v) {
                                        if (v != null) {
                                          update(() => ownership = v);
                                        }
                                      }),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<AccountType>(
                                isExpanded: true,
                                initialValue: type,
                                decoration: InputDecoration(
                                    labelText: l10n.t('Type', 'Típus')),
                                items: AccountType.values
                                    .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(accountTypeLabel(t, l10n))))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) update(() => type = v);
                                }),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<CurrencyCode>(
                                isExpanded: true,
                                initialValue: currency,
                                decoration: InputDecoration(
                                    labelText: l10n.t('Currency', 'Pénznem')),
                                items: CurrencyCode.values
                                    .map((c) => DropdownMenuItem(
                                        value: c, child: Text(c.code)))
                                    .toList(),
                                onChanged: linked
                                    ? null
                                    : (v) {
                                        if (v != null) {
                                          update(() => currency = v);
                                        }
                                      }),
                            if (linked)
                              Text(l10n.t(
                                  'Currency and ownership are fixed because this account has recorded entries.',
                                  'A pénznem és tulajdon rögzített, mert a számlán már vannak tételek.')),
                            const SizedBox(height: 12),
                            TextFormField(
                                controller: opening,
                                focusNode: openingFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true, signed: true),
                                decoration: InputDecoration(
                                    labelText: l10n.t(
                                        'Opening balance', 'Nyitó egyenleg')),
                                validator: (v) =>
                                    parseSignedAccountAmount(v ?? '') == null
                                        ? invalid
                                        : null),
                            if (interest) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                  controller: rate,
                                  focusNode: rateFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true, signed: true),
                                  decoration: InputDecoration(
                                      labelText: l10n.t(
                                          'Annual interest %', 'Éves kamat %')),
                                  validator: (v) =>
                                      parseSignedAccountAmount(v ?? '') == null
                                          ? invalid
                                          : null),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<Compounding>(
                                  isExpanded: true,
                                  initialValue: compounding,
                                  decoration: InputDecoration(
                                      labelText:
                                          l10n.t('Compounding', 'Tőkésítés')),
                                  items: Compounding.values
                                      .map((c) => DropdownMenuItem(
                                          value: c,
                                          child:
                                              Text(compoundingLabel(c, l10n))))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      update(() => compounding = v);
                                    }
                                  }),
                              const SizedBox(height: 12),
                              TextFormField(
                                  controller: tax,
                                  focusNode: taxFocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                      labelText: l10n.t(
                                          'Interest tax %', 'Kamatadó %')),
                                  validator: (v) {
                                    final n = parsePositiveAmount(v ?? '',
                                        allowZero: true);
                                    return n == null || n > 100
                                        ? l10n.t(
                                            'Enter a percentage from 0 to 100.',
                                            'Adj meg 0 és 100 közötti százalékot.')
                                        : null;
                                  }),
                            ],
                          ])),
                      actions: [
                        TextButton(
                            onPressed: () => close(ctx),
                            child: Text(l10n.t('Cancel', 'Mégse'))),
                        FilledButton(
                            onPressed: db.household == null
                                ? null
                                : () {
                                    if (!form.currentState!.validate()) {
                                      final focus = name.text.trim().isEmpty
                                          ? nameFocus
                                          : parseSignedAccountAmount(
                                                      opening.text) ==
                                                  null
                                              ? openingFocus
                                              : interest &&
                                                      parseSignedAccountAmount(
                                                              rate.text) ==
                                                          null
                                                  ? rateFocus
                                                  : taxFocus;
                                      focus.requestFocus();
                                      if (focus.context != null) {
                                        Scrollable.ensureVisible(
                                            focus.context!);
                                      }
                                      return;
                                    }
                                    db.upsertAccount(Account(
                                        id: existing?.id ?? const Uuid().v4(),
                                        householdId: existing?.householdId ??
                                            db.household!.id,
                                        name: name.text.trim(),
                                        type: type,
                                        ownership: ownership,
                                        ownerId: ownership == AccountOwnership.personal
                                            ? existing?.ownerId ?? meId
                                            : null,
                                        currency: currency,
                                        openingBalanceMinor:
                                            Money.fromMajor(parseSignedAccountAmount(opening.text)!, currency)
                                                .amountMinor,
                                        openingDate: existing?.openingDate ??
                                            DateTime.now(),
                                        interestRatePct: interest
                                            ? parseSignedAccountAmount(
                                                rate.text)
                                            : existing?.interestRatePct,
                                        compounding: interest
                                            ? compounding
                                            : existing?.compounding,
                                        interestTaxPct: interest
                                            ? parsePositiveAmount(tax.text,
                                                allowZero: true)!
                                            : existing?.interestTaxPct ?? 0,
                                        maturityDate: existing?.maturityDate,
                                        autoPostInterest:
                                            existing?.autoPostInterest ?? false,
                                        includeInNetWorth:
                                            existing?.includeInNetWorth ?? true,
                                        icon: existing?.icon,
                                        color: existing?.color,
                                        archived: existing?.archived ?? false,
                                        deletedAt: existing?.deletedAt,
                                        updatedAt: DateTime.now()));
                                    Navigator.pop(ctx);
                                  },
                            child: Text(l10n.t('Save', 'Mentés')))
                      ]));
            }));
    for (final focus in [nameFocus, openingFocus, rateFocus, taxFocus]) {
      focus.dispose();
    }
    name.dispose();
    opening.dispose();
    rate.dispose();
    tax.dispose();
  }

  static Future<void> showValuationDialog(
      BuildContext context, AppDatabase db, Account account) async {
    final l10n = AppLocalizations.of(context);
    final form = GlobalKey<FormState>();
    final valueFocus = FocusNode();
    final value = TextEditingController(
        text: Money(db.computeAccountBalanceMinor(account.id), account.currency)
            .majorAmount
            .toStringAsFixed(2));
    final note = TextEditingController();
    final initial = value.text;
    Future<void> close(BuildContext ctx) async {
      if (await confirmDiscardChanges(ctx,
              dirty: value.text != initial || note.text.isNotEmpty) &&
          ctx.mounted) {
        Navigator.pop(ctx);
      }
    }

    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) close(ctx);
            },
            child: AlertDialog(
                scrollable: true,
                title: Text(l10n.t('Update valuation: ${account.name}',
                    'Értékbecslés: ${account.name}')),
                content: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          controller: value,
                          focusNode: valueFocus,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText:
                                  '${l10n.t('Current value', 'Aktuális érték')} (${account.currency.code})'),
                          validator: (v) =>
                              parsePositiveAmount(v ?? '', allowZero: true) ==
                                      null
                                  ? l10n.t('Enter a valid nonnegative value.',
                                      'Adj meg érvényes nemnegatív értéket.')
                                  : null),
                      TextFormField(
                          controller: note,
                          decoration: InputDecoration(
                              labelText: l10n.t('Note', 'Megjegyzés'))),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => close(ctx),
                      child: Text(l10n.t('Cancel', 'Mégse'))),
                  FilledButton(
                      onPressed: () {
                        if (!form.currentState!.validate()) {
                          valueFocus.requestFocus();
                          return;
                        }
                        db.upsertValuation(AccountValuation(
                            id: const Uuid().v4(),
                            accountId: account.id,
                            valuedOn: DateTime.now(),
                            valueMinor: Money.fromMajor(
                                    parsePositiveAmount(value.text,
                                        allowZero: true)!,
                                    account.currency)
                                .amountMinor,
                            note: note.text.trim().isEmpty
                                ? null
                                : note.text.trim(),
                            createdAt: DateTime.now()));
                        Navigator.pop(ctx);
                      },
                      child: Text(l10n.t('Save snapshot', 'Érték mentése')))
                ])));
    valueFocus.dispose();
    value.dispose();
    note.dispose();
  }

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  Future<void> _showEditPledgeDialog(
      BuildContext context, AppDatabase db, Profile profile) async {
    final l10n = AppLocalizations.of(context);
    final form = GlobalKey<FormState>();
    final valueFocus = FocusNode();
    final value = TextEditingController(
        text: Money(profile.monthlyCommonContributionMinor ?? 0)
            .majorAmount
            .toStringAsFixed(2));
    final initial = value.text;
    Future<void> close(BuildContext ctx) async {
      if (await confirmDiscardChanges(ctx, dirty: value.text != initial) &&
          ctx.mounted) {
        Navigator.pop(ctx);
      }
    }

    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) close(ctx);
            },
            child: AlertDialog(
                scrollable: true,
                title: Text(l10n.t('Monthly pledge (${profile.displayName})',
                    'Havi vállalás (${profile.displayName})')),
                content: Form(
                    key: form,
                    child: TextFormField(
                        controller: value,
                        focusNode: valueFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: l10n.t(
                                'Monthly amount (HUF)', 'Havi összeg (Ft)')),
                        validator: (v) =>
                            parsePositiveAmount(v ?? '', allowZero: true) ==
                                    null
                                ? l10n.t('Enter a valid nonnegative value.',
                                    'Adj meg érvényes nemnegatív értéket.')
                                : null)),
                actions: [
                  TextButton(
                      onPressed: () => close(ctx),
                      child: Text(l10n.t('Cancel', 'Mégse'))),
                  FilledButton(
                      onPressed: () {
                        if (!form.currentState!.validate()) {
                          valueFocus.requestFocus();
                          return;
                        }
                        db.upsertProfile(Profile(
                            id: profile.id,
                            householdId: profile.householdId,
                            displayName: profile.displayName,
                            color: profile.color,
                            locale: profile.locale,
                            avatarType: profile.avatarType,
                            avatarUrl: profile.avatarUrl,
                            monthlyCommonContributionMinor: Money.fromMajor(
                                    parsePositiveAmount(value.text,
                                        allowZero: true)!,
                                    CurrencyCode.huf)
                                .amountMinor,
                            updatedAt: DateTime.now()));
                        Navigator.pop(ctx);
                      },
                      child: Text(l10n.t('Save', 'Mentés')))
                ])));
    valueFocus.dispose();
    value.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);

    final commonAccounts = db.accounts
        .where((a) => a.deletedAt == null && !a.archived && a.isCommon)
        .toList();
    final myPersonalAccounts = db.accounts
        .where((a) =>
            a.deletedAt == null &&
            !a.archived &&
            !a.isCommon &&
            a.ownerId == meId)
        .toList();

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    // Common-account monthly cash-flow calculations
    final contributionsByUser = <String, int>{
      for (final p in db.profiles) p.id: 0,
    };
    var commonExpensesMinor = 0;
    var commonIncomeMinor = 0;

    for (final t in db.transactions) {
      if (t.occurredOn.isBefore(monthStart) ||
          !t.occurredOn.isBefore(DateTime(now.year, now.month + 1))) {
        continue;
      }
      if (t.kind == TxnKind.transfer && t.isContribution) {
        contributionsByUser[t.paidBy] =
            (contributionsByUser[t.paidBy] ?? 0) + t.baseAmountMinor;
      } else if (t.kind == TxnKind.expense && t.paidFromCommon) {
        commonExpensesMinor += t.baseAmountMinor;
      } else if (t.kind == TxnKind.income && t.paidFromCommon) {
        commonIncomeMinor += t.baseAmountMinor;
      }
    }

    int movement(Txn t, String id) {
      if (t.toAccountId == id && t.kind == TxnKind.transfer) {
        return t.toAccountAmountMinor ?? 0;
      }
      if (t.accountId != id) return 0;
      return t.kind == TxnKind.income
          ? t.accountAmountMinor
          : -t.accountAmountMinor;
    }

    String periodBalance(bool closing) {
      return CurrencyCode.values
          .where(
              (currency) => commonAccounts.any((a) => a.currency == currency))
          .map((currency) {
        var total = 0;
        for (final account
            in commonAccounts.where((a) => a.currency == currency)) {
          final boundary =
              closing ? DateTime(now.year, now.month + 1) : monthStart;
          if (closing
              ? !account.openingDate.isBefore(boundary)
              : account.openingDate.isAfter(boundary)) {
            continue;
          }
          total += account.openingBalanceMinor;
          for (final t in db.transactions.where(
              (t) => t.deletedAt == null && t.occurredOn.isBefore(boundary))) {
            total += movement(t, account.id);
          }
        }
        return Money(total, currency)
            .format(locale: locale, hideAmounts: hideAmounts);
      }).join(' / ');
    }

    final duo = context.duo;
    final textTheme = Theme.of(context).textTheme;

    Widget accountCard(Account account) => DuoCard(
        onTap: () => context.push('/accounts/${account.id}'),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(
                account.isCommon
                    ? Icons.account_balance_outlined
                    : Icons.account_balance_wallet_outlined,
                color: duo.icon),
            const SizedBox(width: 12),
            Expanded(
                child: Text(account.name,
                    style: textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)),
            const Icon(Icons.chevron_right)
          ]),
          const SizedBox(height: 6),
          Text(
              '${accountTypeLabel(account.type, l10n)} · ${account.currency.code}'),
          const SizedBox(height: 12),
          Text(
              Money(
                      db.computeAccountBalanceMinor(account.id,
                          currentUserId: meId),
                      account.currency)
                  .format(locale: locale, hideAmounts: hideAmounts),
              style: textTheme.headlineMedium),
          if (account.type == AccountType.investment)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => AccountsScreen.showValuationDialog(
                        context, db, account),
                    icon: const Icon(Icons.candlestick_chart_outlined),
                    label: Text(l10n.t(
                        'Update valuation', 'Értékbecslés frissítése')))),
        ]));
    Widget emptyGroup(bool common) => DuoCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text(common
                  ? l10n.t('No common accounts yet.', 'Még nincs közös számla.')
                  : l10n.t(
                      'No personal accounts yet.', 'Még nincs saját számla.')),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: () => AccountsScreen.showAccountDialog(
                      context, db, meId,
                      initialOwnership: common
                          ? AccountOwnership.common
                          : AccountOwnership.personal),
                  child: Text(common
                      ? l10n.t('Add common account', 'Közös számla létrehozása')
                      : l10n.t(
                          'Add personal account', 'Saját számla létrehozása')))
            ]));
    return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                onPressed: () => AppShell.openDrawer(context),
                icon: const Icon(Icons.menu),
                tooltip:
                    MaterialLocalizations.of(context).openAppDrawerTooltip),
            title: Text(l10n.accounts),
            actions: [
              IconButton(
                  onPressed: () => TransferSheet.show(context),
                  tooltip: l10n.transfer,
                  icon: const Icon(Icons.swap_horiz))
            ]),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
            children: [
              Text(l10n.commonAccount, style: textTheme.titleMedium),
              if (commonAccounts.isEmpty) emptyGroup(true),
              ...commonAccounts.map(accountCard),
              if (commonAccounts.isNotEmpty)
                DuoCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text(
                          l10n.t('Common account · this month',
                              'Közös számla · aktuális hónap'),
                          style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(l10n.t(
                          'Flows use recorded HUF values. Opening and closing balances are grouped by account currency.',
                          'A forgalom rögzített HUF értékeket használ. A nyitó és záró egyenlegek számlapénznemenként szerepelnek.')),
                      const SizedBox(height: 8),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                              onPressed: myPersonalAccounts.isEmpty
                                  ? null
                                  : () => TransferSheet.show(context,
                                      initialFromAccountId:
                                          myPersonalAccounts.first.id,
                                      initialToAccountId:
                                          commonAccounts.first.id),
                              icon: const Icon(Icons.add),
                              label: Text(l10n.t('Record contribution',
                                  'Befizetés rögzítése')))),
                      if (myPersonalAccounts.isEmpty)
                        Text(l10n.t(
                            'Add a personal account to record a contribution.',
                            'Befizetés rögzítéséhez hozz létre saját számlát.')),
                      for (final profile in db.profiles)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(profile.displayName,
                                            style: textTheme.titleSmall)),
                                    if (profile.id == meId)
                                      IconButton(
                                          onPressed: () =>
                                              _showEditPledgeDialog(
                                                  context, db, profile),
                                          tooltip: l10n.t('Edit monthly pledge',
                                              'Havi vállalás szerkesztése'),
                                          icon: const Icon(Icons.edit_outlined))
                                  ]),
                                  Text(
                                      '${l10n.t('Recorded', 'Rögzített')}: ${Money(contributionsByUser[profile.id] ?? 0).format(locale: locale, hideAmounts: hideAmounts)}'),
                                  Text(
                                      '${l10n.t('Monthly pledge', 'Havi vállalás')}: ${Money(profile.monthlyCommonContributionMinor ?? 0).format(locale: locale, hideAmounts: hideAmounts)}'),
                                  if ((profile.monthlyCommonContributionMinor ??
                                          0) >
                                      0) ...[
                                    const SizedBox(height: 8),
                                    DuoProgressBar(
                                        progress: ((contributionsByUser[
                                                        profile.id] ??
                                                    0) /
                                                profile
                                                    .monthlyCommonContributionMinor!)
                                            .clamp(0, 1),
                                        color: duo.positive),
                                    Text((contributionsByUser[profile.id] ??
                                                0) >=
                                            profile
                                                .monthlyCommonContributionMinor!
                                        ? l10n.t('Pledge reached',
                                            'Vállalás teljesítve')
                                        : l10n.t('Pledge in progress',
                                            'Vállalás folyamatban'))
                                  ],
                                ])),
                      const Divider(),
                      Text(l10n.t('Common expenses', 'Közös kiadások')),
                      Text(
                          Money(commonExpensesMinor)
                              .format(locale: locale, hideAmounts: hideAmounts),
                          style: textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text(l10n.t('Common income', 'Közös bevételek')),
                      Text(
                          Money(commonIncomeMinor)
                              .format(locale: locale, hideAmounts: hideAmounts),
                          style: textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text(l10n.t(
                          'Month opening balance', 'Hónap nyitó egyenlege')),
                      Text(periodBalance(false), style: textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text(l10n.t('Month closing balance (recorded entries)',
                          'Hónap záró egyenlege (rögzített tételek)')),
                      Text(periodBalance(true), style: textTheme.titleLarge),
                    ])),
              const SizedBox(height: 20),
              Text(l10n.personalAccount, style: textTheme.titleMedium),
              Text(l10n.t(
                  'Visible to your selected local profile. Local demo privacy is not server authorization.',
                  'A kiválasztott helyi profil számára látható. A helyi demó adatvédelem nem szerveroldali jogosultságkezelés.')),
              if (myPersonalAccounts.isEmpty) emptyGroup(false),
              ...myPersonalAccounts.map(accountCard),
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                AccountsScreen.showAccountDialog(context, db, meId),
            icon: const Icon(Icons.add),
            label: Text(l10n.t('Add account', 'Új számla'))));
  }
}
