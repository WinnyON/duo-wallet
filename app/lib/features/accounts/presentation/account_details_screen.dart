import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';
import '../../../router.dart';
import '../../transactions/presentation/transactions_screen.dart';
import '../../transfers/presentation/transfer_sheet.dart';
import 'accounts_screen.dart';

class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({
    super.key,
    required this.accountId,
  });

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final duo = context.duo;
    final textTheme = Theme.of(context).textTheme;

    final account = db.findAccount(accountId);
    if (account == null ||
        account.archived ||
        account.deletedAt != null ||
        (!account.isCommon && account.ownerId != meId)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.accounts)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 48, color: duo.icon),
              const SizedBox(height: 16),
              Text(
                l10n.t('Account unavailable', 'A számla nem elérhető'),
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => AppShell.goBackOrHome(context),
                child: Text(l10n.t('Back', 'Vissza')),
              ),
            ],
          ),
        ),
      );
    }

    final balanceMinor =
        db.computeAccountBalanceMinor(account.id, currentUserId: meId);

    // Collect all transactions linked to this account
    final linkedTxns = db.transactions.where((t) {
      if (t.deletedAt != null ||
          (t.visibility == VisibilityLevel.private && t.createdBy != meId)) {
        return false;
      }
      return t.accountId == account.id || t.toAccountId == account.id;
    }).toList()
      ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));

    return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                onPressed: () => AppShell.goBackOrHome(context),
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip),
            title: Text(account.name)),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
            children: [
              DuoSection(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(
                        '${accountTypeLabel(account.type, l10n)} · ${account.currency.code}',
                        style: textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Text(l10n.t('Recorded balance', 'Rögzített egyenleg')),
                    Text(
                        Money(balanceMinor, account.currency)
                            .format(locale: locale, hideAmounts: hideAmounts),
                        style: textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: () => TransferSheet.show(context,
                              initialFromAccountId: account.id),
                          icon: const Icon(Icons.swap_horiz),
                          label: Text(l10n.transfer)),
                      FilledButton.icon(
                          onPressed: () => AccountsScreen.showAccountDialog(
                              context, db, meId, existing: account),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(
                              l10n.t('Edit account', 'Számla szerkesztése'))),
                      if (account.type == AccountType.investment)
                        OutlinedButton.icon(
                            onPressed: () => AccountsScreen.showValuationDialog(
                                context, db, account),
                            icon: const Icon(Icons.candlestick_chart_outlined),
                            label: Text(l10n.t('Update valuation',
                                'Értékbecslés frissítése'))),
                    ]),
                  ])),
              const SizedBox(height: 20),
              Text(
                  l10n.t('Account history (${linkedTxns.length})',
                      'Számlatörténet (${linkedTxns.length})'),
                  style: textTheme.titleMedium),
              if (linkedTxns.isEmpty)
                DuoSection(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text(l10n.t(
                          'No transactions recorded for this account yet.',
                          'Még nincs rögzített tranzakció ezen a számlán.')),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: () => QuickAddTransactionSheet.show(
                              context,
                              initialAccountId: account.id),
                          child: Text(l10n.quickAdd))
                    ])),
              for (final t in linkedTxns)
                Builder(builder: (context) {
                  final incoming = t.kind == TxnKind.income ||
                      (t.kind == TxnKind.transfer &&
                          t.toAccountId == account.id);
                  final amount =
                      t.kind == TxnKind.transfer && t.toAccountId == account.id
                          ? t.toAccountAmountMinor ?? 0
                          : t.accountAmountMinor;
                  final category = t.categoryId == null
                      ? null
                      : db.findCategory(t.categoryId!);
                  return DuoSection(
                      onTap: () => showTransactionDetails(context, t),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                t.merchant ??
                                    category?.localizedName(locale) ??
                                    (t.kind == TxnKind.transfer
                                        ? l10n.transfer
                                        : t.kind == TxnKind.income
                                            ? l10n.income
                                            : l10n.expense),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(
                                '${incoming ? '+' : '−'}${Money(amount, account.currency).format(locale: locale, hideAmounts: hideAmounts)}',
                                style: textTheme.titleLarge),
                            Text(MaterialLocalizations.of(context)
                                .formatMediumDate(t.occurredOn)),
                            if (t.note?.isNotEmpty == true)
                              Text(t.note!,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                          ]));
                }),
            ]));
  }
}
