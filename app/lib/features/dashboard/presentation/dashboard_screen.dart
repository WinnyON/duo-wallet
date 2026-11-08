import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/backend_session.dart';
import '../../../core/auth/cloud_status.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/balance.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../router.dart';
import '../../../theme.dart';
import '../../transactions/presentation/transactions_screen.dart';
import '../../transfers/presentation/transfer_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dbTickProvider);
    final l = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final me = ref.watch(currentUserIdProvider);
    final partner = ref.watch(partnerUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hide = ref.watch(hideAmountsProvider);
    final text = Theme.of(context).textTheme;
    final duo = context.duo;
    final now = DateTime.now();
    final month = db.transactions.where((t) =>
        t.deletedAt == null &&
        t.occurredOn.year == now.year &&
        t.occurredOn.month == now.month);
    int total(ExpenseView view) =>
        month.fold(0, (sum, t) => sum + amountFor(t, view, me));
    final accounts = db.accounts
        .where((a) => !a.archived && (a.isCommon || a.ownerId == me))
        .toList();
    final recent = db.transactions
        .where((t) =>
            t.deletedAt == null &&
            (t.visibility == VisibilityLevel.shared || t.createdBy == me))
        .toList()
      ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    final balance = computeSettleUpBalance(
        meId: me,
        partnerId: partner,
        transactions: db.transactions,
        settlements: db.settlements);
    final profile = db.findProfile(me);
    final name = profile?.displayName ?? '';
    final partnerName =
        db.findProfile(partner)?.displayName ?? l.t('Your partner', 'A párod');

    return Scaffold(
      body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
            children: [
              Row(children: [
                IconButton(
                    tooltip: l.t('Menu', 'Menü'),
                    icon: const Icon(Icons.menu),
                    onPressed: () => AppShell.openDrawer(context)),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(DateFormat('MMMM y', locale).format(now),
                          style: text.bodySmall),
                      Text(
                          name.isEmpty
                              ? l.dashboard
                              : l.t('Hi, $name', 'Szia, $name'),
                          style: text.headlineSmall),
                    ])),
                IconButton(
                    tooltip: l.t(
                        'Hide / Show Amounts', 'Összegek elrejtése / mutatása'),
                    onPressed: () =>
                        ref.read(hideAmountsProvider.notifier).state = !hide,
                    icon: Icon(hide
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined)),
                IconButton(
                    tooltip: l.t('Profile', 'Profil'),
                    onPressed: () => context.push('/auth'),
                    icon: const Icon(Icons.person_outline)),
              ]),
              if (ref.watch(productionModeProvider))
                const CloudStatusCard(compact: true)
              else
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        l.t('Demo · temporary data',
                            'Demó · ideiglenes adatok'),
                        style: text.bodySmall)),
              const SizedBox(height: 28),
              Text(
                  l.t('Together this month', 'Közös kiadások ebben a hónapban'),
                  style: text.titleSmall),
              const SizedBox(height: 8),
              DuoAmount(
                  money: Money(total(ExpenseView.together)),
                  locale: locale,
                  hideAmounts: hide,
                  fontSize: 40),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, constraints) {
                Widget metric(String label, int value) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: text.bodySmall),
                          const SizedBox(height: 6),
                          DuoAmount(
                              money: Money(value),
                              locale: locale,
                              hideAmounts: hide,
                              fontSize: 20),
                        ]);
                final values = [
                  metric(l.viewMyTotal, total(ExpenseView.myTotal)),
                  metric(l.viewIndividual, total(ExpenseView.individual))
                ];
                if (MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        values[0],
                        const SizedBox(height: 16),
                        values[1]
                      ]);
                }
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: values[0]),
                      const SizedBox(width: 20),
                      Expanded(child: values[1])
                    ]);
              }),
              const SizedBox(height: 24),
              Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton.icon(
                    onPressed: () => QuickAddTransactionSheet.show(context),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(l.quickAdd)),
                OutlinedButton.icon(
                    onPressed: () => TransferSheet.show(context),
                    icon: const Icon(Icons.swap_horiz, size: 20),
                    label: Text(l.transfer)),
              ]),
              const SizedBox(height: 20),
              if (balance.someoneOwes)
                DuoCard(
                    isHero: true,
                    onTap: () => context.go('/settle-up'),
                    child: Row(children: [
                      const Icon(Icons.swap_horiz, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                balance.partnerOwesMe
                                    ? l.t('$partnerName owes you',
                                        '$partnerName tartozik neked')
                                    : l.t('You owe $partnerName',
                                        'Tartozol neki: $partnerName'),
                                style: text.bodyMedium
                                    ?.copyWith(color: Colors.white)),
                            const SizedBox(height: 6),
                            Text(
                                Money(balance.absoluteOwedMinor)
                                    .format(locale: locale, hideAmounts: hide),
                                style: text.titleLarge
                                    ?.copyWith(color: Colors.white)),
                          ])),
                      const Icon(Icons.chevron_right, color: Colors.white),
                    ]))
              else
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.check_circle_outline, color: duo.positive),
                    title: Text(l.t('All settled up', 'Minden elszámolva')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/settle-up')),
              const SizedBox(height: 12),
              const Divider(),
              DuoSection(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    DuoSectionHeader(
                        title: l.accounts,
                        trailingLabel: l.t('View all', 'Összes'),
                        onTap: () => context.go('/accounts')),
                    const SizedBox(height: 8),
                    if (accounts.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              l.t('Add an account to track your money.',
                                  'Adj hozzá egy számlát a pénzügyeid követéséhez.'),
                              style: text.bodyMedium)),
                    for (final account in accounts.take(3))
                      _OverviewRow(
                          title: account.name,
                          subtitle: account.isCommon
                              ? l.commonAccount
                              : l.personalAccount,
                          amount: Money(
                                  db.computeAccountBalanceMinor(account.id,
                                      currentUserId: me),
                                  account.currency)
                              .format(locale: locale, hideAmounts: hide),
                          icon: account.isCommon
                              ? Icons.account_balance_outlined
                              : Icons.credit_card_outlined,
                          onTap: () => context.push('/accounts/${account.id}')),
                  ])),
              DuoSection(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    DuoSectionHeader(
                        title:
                            l.t('Recent transactions', 'Legutóbbi tranzakciók'),
                        trailingLabel: l.t('View all', 'Összes'),
                        onTap: () => context.go('/transactions')),
                    if (recent.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                              l.t('No transactions yet. Add your first expense.',
                                  'Még nincs tranzakció. Rögzítsd az első kiadást.'),
                              style: text.bodyMedium)),
                    for (final t in recent.take(4))
                      _OverviewRow(
                          title: t.merchant ??
                              db
                                  .findCategory(t.categoryId ?? '')
                                  ?.localizedName(locale) ??
                              l.t('Transaction', 'Tranzakció'),
                          subtitle:
                              DateFormat.MMMd(locale).format(t.occurredOn),
                          amount: Money(t.amountMinor, t.currency)
                              .format(locale: locale, hideAmounts: hide),
                          icon: t.kind == TxnKind.income
                              ? Icons.south_west
                              : t.kind == TxnKind.transfer
                                  ? Icons.swap_horiz
                                  : Icons.north_east,
                          onTap: () => showTransactionDetails(context, t)),
                  ])),
            ],
          )),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow(
      {required this.title,
      required this.subtitle,
      required this.amount,
      required this.icon,
      required this.onTap});
  final String title, subtitle, amount;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: LayoutBuilder(builder: (context, constraints) {
              final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(subtitle, style: text.bodySmall)
                  ]);
              final value = Text(amount, style: text.titleSmall);
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(icon, size: 22)),
                    const SizedBox(width: 12),
                    if (constraints.maxWidth < 330 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20)
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            details,
                            const SizedBox(height: 8),
                            value
                          ]))
                    else ...[
                      Expanded(child: details),
                      const SizedBox(width: 12),
                      Flexible(child: value)
                    ],
                  ]);
            })));
  }
}
