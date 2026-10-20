import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/balance.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/fx_service.dart';
import '../../../core/money/money.dart';

class SettleUpScreen extends ConsumerStatefulWidget {
  const SettleUpScreen({super.key});

  @override
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen> {
  static const _uuid = Uuid();

  Future<void> _showProposeDialog(
    BuildContext context,
    AppDatabase db,
    FxService fx,
    String meId,
    String partnerId,
    SettleUpSummary summary,
  ) async {
    final l10n = AppLocalizations.of(context);
    final myPersonalAccounts = db.accounts
        .where(
          (a) =>
              a.ownership == AccountOwnership.personal && a.ownerId == meId,
        )
        .toList();

    var iAmPayer = !summary.partnerOwesMe;
    var currency = CurrencyCode.huf;
    String? selectedAccountId;
    final defaultMajor = summary.absoluteOwedMinor > 0
        ? (summary.absoluteOwedMinor ~/ 100).toString()
        : '';
    final amountCtrl = TextEditingController(text: defaultMajor);
    final noteCtrl = TextEditingController();

    final meName = db.findProfile(meId)?.displayName ?? 'Me';
    final partnerName = db.findProfile(partnerId)?.displayName ?? 'Partner';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            l10n.t('Propose Settlement', 'Elszámolás kezdeményezése'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      label: Text('$meName → $partnerName'),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('$partnerName → $meName'),
                    ),
                  ],
                  selected: {iAmPayer},
                  onSelectionChanged: (s) =>
                      setDialogState(() => iAmPayer = s.first),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.t('Amount', 'Összeg'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<CurrencyCode>(
                        initialValue: currency,
                        decoration: InputDecoration(
                          labelText: l10n.t('Currency', 'Pénznem'),
                        ),
                        items: CurrencyCode.values
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.code),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => currency = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.t('Note (optional)', 'Megjegyzés'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: selectedAccountId,
                  decoration: InputDecoration(
                    labelText: l10n.t(
                      '🔒 Adjust my own account (private)',
                      '🔒 Saját számla módosítása (privát)',
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        l10n.t('None (do not adjust)', 'Nincs számlamódosítás'),
                      ),
                    ),
                    ...myPersonalAccounts.map(
                      (a) => DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text('${a.name} (${a.currency.code})'),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedAccountId = v),
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
                final major =
                    double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ??
                        0;
                if (major <= 0) return;
                final money = Money.fromMajor(major, currency);
                final baseMoney = fx.convert(money, CurrencyCode.huf);
                final id = _uuid.v4();
                final hhId = db.household?.id ?? 'hh-default-001';
                final fromUser = iAmPayer ? meId : partnerId;
                final toUser = iAmPayer ? partnerId : meId;

                SettlementPosting? ownPosting;
                if (selectedAccountId != null) {
                  final acc = db.findAccount(selectedAccountId!);
                  final acctMinor = acc != null
                      ? fx.convert(money, acc.currency).amountMinor
                      : money.amountMinor;
                  ownPosting = SettlementPosting(
                    settlementId: id,
                    userId: meId,
                    accountId: selectedAccountId!,
                    amountMinor: iAmPayer ? -acctMinor : acctMinor,
                  );
                }

                final settlement = Settlement(
                  id: id,
                  householdId: hhId,
                  fromUser: fromUser,
                  toUser: toUser,
                  amountMinor: money.amountMinor,
                  currency: currency,
                  baseAmountMinor: baseMoney.amountMinor,
                  fromConfirmed: meId == fromUser,
                  toConfirmed: meId == toUser,
                  note: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                  createdBy: meId,
                  updatedAt: DateTime.now(),
                );
                db.upsertSettlement(settlement, ownPosting: ownPosting);
                db.addActivity(
                  ActivityEvent(
                    id: _uuid.v4(),
                    householdId: hhId,
                    actorId: meId,
                    eventType: 'settlement_proposed',
                    summaryEn:
                        '$meName proposed a settlement of ${money.format(locale: 'en')}',
                    summaryHu:
                        '$meName elszámolást javasolt: ${money.format(locale: 'hu')}',
                    amountMinor: money.amountMinor,
                    currency: currency,
                    createdAt: DateTime.now(),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.t('Propose', 'Javaslat küldése')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConfirmDialog(
    BuildContext context,
    AppDatabase db,
    FxService fx,
    String meId,
    Settlement s,
  ) async {
    final l10n = AppLocalizations.of(context);
    final myPersonalAccounts = db.accounts
        .where(
          (a) =>
              a.ownership == AccountOwnership.personal && a.ownerId == meId,
        )
        .toList();
    String? selectedAccountId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            l10n.t('Confirm Settlement', 'Elszámolás jóváhagyása'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t(
                  'Both partners must confirm before the running balance updates.',
                  'Mindkét fél jóváhagyása szükséges az egyenleg frissítéséhez.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: selectedAccountId,
                decoration: InputDecoration(
                  labelText: l10n.t(
                    '🔒 Adjust my own account (private)',
                    '🔒 Saját számla módosítása (privát)',
                  ),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      l10n.t('None (do not adjust)', 'Nincs számlamódosítás'),
                    ),
                  ),
                  ...myPersonalAccounts.map(
                    (a) => DropdownMenuItem<String?>(
                      value: a.id,
                      child: Text('${a.name} (${a.currency.code})'),
                    ),
                  ),
                ],
                onChanged: (v) =>
                    setDialogState(() => selectedAccountId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.t('Cancel', 'Mégse')),
            ),
            FilledButton(
              onPressed: () {
                SettlementPosting? ownPosting;
                if (selectedAccountId != null) {
                  final acc = db.findAccount(selectedAccountId!);
                  final money = Money(s.amountMinor, s.currency);
                  final acctMinor = acc != null
                      ? fx.convert(money, acc.currency).amountMinor
                      : s.amountMinor;
                  final isPayer = s.fromUser == meId;
                  ownPosting = SettlementPosting(
                    settlementId: s.id,
                    userId: meId,
                    accountId: selectedAccountId!,
                    amountMinor: isPayer ? -acctMinor : acctMinor,
                  );
                }

                final confirmed = Settlement(
                  id: s.id,
                  householdId: s.householdId,
                  fromUser: s.fromUser,
                  toUser: s.toUser,
                  amountMinor: s.amountMinor,
                  currency: s.currency,
                  baseAmountMinor: s.baseAmountMinor,
                  fromConfirmed: true,
                  toConfirmed: true,
                  note: s.note,
                  createdBy: s.createdBy,
                  updatedAt: DateTime.now(),
                );
                db.upsertSettlement(confirmed, ownPosting: ownPosting);
                final meName = db.findProfile(meId)?.displayName ?? 'Partner';
                final money = Money(s.amountMinor, s.currency);
                db.addActivity(
                  ActivityEvent(
                    id: _uuid.v4(),
                    householdId: s.householdId,
                    actorId: meId,
                    eventType: 'settlement_confirmed',
                    summaryEn:
                        '$meName confirmed settlement of ${money.format(locale: 'en')}',
                    summaryHu:
                        '$meName jóváhagyta az elszámolást: ${money.format(locale: 'hu')}',
                    amountMinor: s.amountMinor,
                    currency: s.currency,
                    createdAt: DateTime.now(),
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.t('Confirm', 'Jóváhagyás')),
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
    final fx = ref.watch(fxServiceProvider);
    final meId = ref.watch(currentUserIdProvider);
    final partnerId = ref.watch(partnerUserIdProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);
    final localeStr = l10n.locale.languageCode;

    final meName = db.findProfile(meId)?.displayName ?? 'Sam';
    final partnerName = db.findProfile(partnerId)?.displayName ?? 'Anna';

    final summary = computeSettleUpBalance(
      meId: meId,
      partnerId: partnerId,
      transactions: db.transactions,
      settlements: db.settlements,
    );

    final formattedOwed = Money(
      summary.absoluteOwedMinor,
      CurrencyCode.huf,
    ).format(locale: localeStr, hideAmounts: hideAmounts);

    final headline = !summary.someoneOwes
        ? l10n.t('All settled up!', 'Minden elszámolva!')
        : summary.partnerOwesMe
            ? l10n.t(
                '$partnerName owes $meName $formattedOwed',
                '$partnerName tartozik neked ($meName): $formattedOwed',
              )
            : l10n.t(
                '$meName owes $partnerName $formattedOwed',
                '$meName tartozik neki ($partnerName): $formattedOwed',
              );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settleUp)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        summary.someoneOwes
                            ? Icons.handshake_outlined
                            : Icons.verified_outlined,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          headline,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  if (summary.pendingBaseMinor > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.t(
                        'Pending confirmation: ${Money(summary.pendingBaseMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)}',
                        'Jóváhagyásra vár: ${Money(summary.pendingBaseMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)}',
                      ),
                      style: TextStyle(color: Colors.amber.shade800),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    l10n.t(
                      'Only Together expenses paid from a personal account create debt. Common-account expenses and contributions to the common account create no debt.',
                      'Csak a saját számláról fizetett Közös kiadások keletkeztetnek tartozást. A közös számlás költések és befizetések nem módosítják az egyenleget.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showProposeDialog(
                      context,
                      db,
                      fx,
                      meId,
                      partnerId,
                      summary,
                    ),
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      l10n.t('Propose Settlement', 'Elszámolás kezdeményezése'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.t('Settlement History', 'Elszámolási előzmények'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (db.settlements.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.t(
                    'No settlements proposed yet.',
                    'Még nincs rögzített elszámolás.',
                  ),
                ),
              ),
            ),
          for (final s in db.settlements)
            Builder(
              builder: (context) {
                final fromName =
                    db.findProfile(s.fromUser)?.displayName ?? s.fromUser;
                final toName =
                    db.findProfile(s.toUser)?.displayName ?? s.toUser;
                final amtStr = Money(s.amountMinor, s.currency).format(
                  locale: localeStr,
                  hideAmounts: hideAmounts,
                );
                final status = s.status;
                final needsMyConfirm = status == 'pending' &&
                    ((s.fromUser == meId && !s.fromConfirmed) ||
                        (s.toUser == meId && !s.toConfirmed) ||
                        s.createdBy != meId);

                final myPosting = db.settlementPostings
                    .where(
                      (p) => p.settlementId == s.id && p.userId == meId,
                    )
                    .firstOrNull;
                final myPostingAccount = myPosting != null
                    ? db.findAccount(myPosting.accountId)
                    : null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$fromName → $toName • $amtStr',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                switch (status) {
                                  'confirmed' =>
                                    l10n.t('Confirmed', 'Jóváhagyva'),
                                  'rejected' =>
                                    l10n.t('Rejected', 'Elutasítva'),
                                  _ => l10n.t('Pending', 'Függőben'),
                                },
                              ),
                            ),
                          ],
                        ),
                        if (s.note != null && s.note!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(s.note!),
                          ),
                        if (myPostingAccount != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '🔒 ${l10n.t('Private posting:', 'Privát könyvelés:')} ${myPostingAccount.name}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (status == 'pending') ...[
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (needsMyConfirm)
                                FilledButton.tonalIcon(
                                  onPressed: () => _showConfirmDialog(
                                    context,
                                    db,
                                    fx,
                                    meId,
                                    s,
                                  ),
                                  icon: const Icon(Icons.check),
                                  label: Text(
                                    l10n.t('Confirm', 'Jóváhagyás'),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () {
                                  db.upsertSettlement(
                                    Settlement(
                                      id: s.id,
                                      householdId: s.householdId,
                                      fromUser: s.fromUser,
                                      toUser: s.toUser,
                                      amountMinor: s.amountMinor,
                                      currency: s.currency,
                                      baseAmountMinor: s.baseAmountMinor,
                                      fromConfirmed: s.fromConfirmed,
                                      toConfirmed: s.toConfirmed,
                                      rejectedBy: meId,
                                      note: s.note,
                                      createdBy: s.createdBy,
                                      updatedAt: DateTime.now(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.close),
                                label: Text(l10n.t('Reject', 'Elutasítás')),
                              ),
                            ],
                          ),
                        ],
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
