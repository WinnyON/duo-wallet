import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/balance.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../router.dart';
import '../../../theme.dart';
import '../../transactions/presentation/transactions_screen.dart';

class SettleUpScreen extends ConsumerStatefulWidget {
  const SettleUpScreen({super.key});
  @override
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen> {
  Future<void> _recordDialog(SettleUpSummary summary,
      {Settlement? existing}) async {
    final db = ref.read(appDatabaseProvider);
    final me = ref.read(currentUserIdProvider);
    final partner = ref.read(partnerUserIdProvider);
    final fx = ref.read(fxServiceProvider);
    final l10n = AppLocalizations.of(context);
    final accounts = db.accounts
        .where((a) =>
            a.deletedAt == null &&
            !a.archived &&
            !a.isCommon &&
            a.ownerId == me)
        .toList();
    final amountFocus = FocusNode();
    final amount = TextEditingController(
        text: existing != null
            ? Money(existing.amountMinor, existing.currency)
                .majorAmount
                .toStringAsFixed(2)
            : summary.someoneOwes
                ? Money(summary.absoluteOwedMinor)
                    .majorAmount
                    .toStringAsFixed(2)
                : '');
    final note = TextEditingController(text: existing?.note ?? '');
    var currency = existing?.currency ?? CurrencyCode.huf;
    var payer = existing?.fromUser ?? (summary.partnerOwesMe ? partner : me);
    var accountId = '';
    var busy = false;
    final form = GlobalKey<FormState>();
    String draft() => '${amount.text}|${note.text}|$currency|$payer|$accountId';
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
              final raw = parsePositiveAmount(amount.text);
              final account =
                  accounts.where((a) => a.id == accountId).firstOrNull;
              final recipient = payer == me ? partner : me;
              final names =
                  '${db.findProfile(payer)?.displayName ?? payer} → ${db.findProfile(recipient)?.displayName ?? recipient}';
              String effect() {
                if (account == null || raw == null) {
                  return l10n.t('No account balance will change.',
                      'Nem változik számlaegyenleg.');
                }
                final converted = fx.convert(
                    Money.fromMajor(raw, currency), account.currency);
                return '${account.name}: ${payer == me ? '−' : '+'}${converted.format(locale: l10n.locale.languageCode)}\n${l10n.t('Applied locally only after both partners approve.', 'Csak helyben, mindkét fél jóváhagyása után kerül könyvelésre.')}';
              }

              return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) close(ctx);
                  },
                  child: AlertDialog(
                      scrollable: true,
                      title: Text(existing == null
                          ? l10n.t(
                              'Propose settlement', 'Elszámolás kezdeményezése')
                          : l10n.t(
                              'Approve settlement', 'Elszámolás jóváhagyása')),
                      content: Form(
                          key: form,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(l10n.t(
                                    'Local record only. This does not send a bank payment.',
                                    'Csak helyi rögzítés. Nem indít banki utalást.')),
                                const SizedBox(height: 12),
                                if (existing == null)
                                  DropdownButtonFormField<String>(
                                      initialValue: payer,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText: l10n.t(
                                              'Who paid?', 'Ki fizetett?')),
                                      items: [me, partner]
                                          .map((id) => DropdownMenuItem(
                                              value: id,
                                              child: Text(
                                                  db
                                                          .findProfile(id)
                                                          ?.displayName ??
                                                      id,
                                                  overflow:
                                                      TextOverflow.ellipsis)))
                                          .toList(),
                                      onChanged: (id) {
                                        if (id != null) {
                                          update(() => payer = id);
                                        }
                                      }),
                                const SizedBox(height: 12),
                                Text(names),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: amount,
                                    focusNode: amountFocus,
                                    readOnly: existing != null,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: InputDecoration(
                                        labelText: l10n.t('Amount', 'Összeg')),
                                    onChanged: (_) => update(() {}),
                                    validator: (v) => parsePositiveAmount(
                                                v ?? '') ==
                                            null
                                        ? l10n.t(
                                            'Enter a valid positive amount.',
                                            'Adj meg érvényes pozitív összeget.')
                                        : null),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<CurrencyCode>(
                                    isExpanded: true,
                                    initialValue: currency,
                                    decoration: InputDecoration(
                                        labelText:
                                            l10n.t('Currency', 'Pénznem')),
                                    items: CurrencyCode.values
                                        .map((c) => DropdownMenuItem(
                                            value: c, child: Text(c.code)))
                                        .toList(),
                                    onChanged: existing != null
                                        ? null
                                        : (c) {
                                            if (c != null) {
                                              update(() => currency = c);
                                            }
                                          }),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: accountId,
                                    decoration: InputDecoration(
                                        labelText: l10n.t(
                                            'My account effect (private)',
                                            'Saját számla módosítása (privát)')),
                                    items: [
                                      DropdownMenuItem(
                                          value: '',
                                          child: Text(
                                              l10n.t('No account change',
                                                  'Nincs számlamódosítás'),
                                              overflow: TextOverflow.ellipsis)),
                                      ...accounts.map((a) => DropdownMenuItem(
                                          value: a.id,
                                          child: Text(
                                              '${a.name} (${a.currency.code})',
                                              overflow: TextOverflow.ellipsis)))
                                    ],
                                    onChanged: (id) =>
                                        update(() => accountId = id ?? '')),
                                const SizedBox(height: 12),
                                Text(effect()),
                                if (account != null &&
                                    account.currency != currency)
                                  Text(l10n.t(
                                      'Account conversion uses the current local estimate shown above.',
                                      'A számla átváltása a fent látható aktuális helyi becslést használja.')),
                                if (existing == null)
                                  TextFormField(
                                      controller: note,
                                      decoration: InputDecoration(
                                          labelText: l10n.t('Note (optional)',
                                              'Megjegyzés (opcionális)'))),
                              ])),
                      actions: [
                        TextButton(
                            onPressed: busy ? null : () => close(ctx),
                            child: Text(l10n.t('Cancel', 'Mégse'))),
                        FilledButton(
                            onPressed: busy ||
                                    db.household == null ||
                                    me == partner
                                ? null
                                : () async {
                                    if (!form.currentState!.validate()) {
                                      amountFocus.requestFocus();
                                      return;
                                    }
                                    final major =
                                        parsePositiveAmount(amount.text)!;
                                    final money =
                                        Money.fromMajor(major, currency);
                                    if (money.amountMinor <= 0) return;
                                    update(() => busy = true);
                                    final approved = await showDialog<bool>(
                                        context: ctx,
                                        builder: (review) => AlertDialog(
                                                title: Text(l10n.t(
                                                    'Review local record',
                                                    'Helyi rögzítés ellenőrzése')),
                                                content: Text(
                                                    '$names\n${money.format(locale: l10n.locale.languageCode)}\n\n${effect()}\n\n${l10n.t('No bank payment is sent.', 'Nem indul banki utalás.')}'),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              review, false),
                                                      child: Text(l10n.t(
                                                          'Keep editing',
                                                          'Szerkesztés folytatása'))),
                                                  FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              review, true),
                                                      child: Text(l10n.t(
                                                          'Record',
                                                          'Rögzítés')))
                                                ]));
                                    if (!ctx.mounted) return;
                                    if (approved != true) {
                                      update(() => busy = false);
                                      return;
                                    }
                                    final id =
                                        existing?.id ?? const Uuid().v4();
                                    final now = DateTime.now();
                                    final record = Settlement(
                                        id: id,
                                        householdId: existing?.householdId ??
                                            db.household!.id,
                                        fromUser: payer,
                                        toUser: recipient,
                                        amountMinor: money.amountMinor,
                                        currency: currency,
                                        baseAmountMinor:
                                            existing?.baseAmountMinor ??
                                                fx
                                                    .convert(
                                                        money, CurrencyCode.huf)
                                                    .amountMinor,
                                        fromConfirmed:
                                            (existing?.fromConfirmed ??
                                                    false) ||
                                                payer == me,
                                        toConfirmed:
                                            (existing?.toConfirmed ?? false) ||
                                                recipient == me,
                                        note: note.text.trim().isEmpty
                                            ? null
                                            : note.text.trim(),
                                        createdBy: existing?.createdBy ?? me,
                                        updatedAt: now);
                                    final posting = account == null
                                        ? null
                                        : SettlementPosting(
                                            settlementId: id,
                                            userId: me,
                                            accountId: account.id,
                                            amountMinor: fx
                                                    .convert(
                                                        money, account.currency)
                                                    .amountMinor *
                                                (payer == me ? -1 : 1));
                                    db.upsertSettlement(record,
                                        ownPosting: posting);
                                    db.addActivity(ActivityEvent(
                                        id: const Uuid().v4(),
                                        householdId: record.householdId,
                                        actorId: me,
                                        eventType: record.isConfirmed
                                            ? 'settlement_confirmed'
                                            : 'settlement_proposed',
                                        summaryEn: record.isConfirmed
                                            ? 'Settlement recorded locally'
                                            : 'Settlement proposed locally',
                                        summaryHu: record.isConfirmed
                                            ? 'Elszámolás helyben rögzítve'
                                            : 'Helyi elszámolási javaslat',
                                        createdAt: now));
                                    Navigator.pop(ctx);
                                  },
                            child: Text(existing == null
                                ? l10n.t(
                                    'Review proposal', 'Javaslat ellenőrzése')
                                : l10n.t('Review approval',
                                    'Jóváhagyás ellenőrzése')))
                      ]));
            }));
    amountFocus.dispose();
    amount.dispose();
    note.dispose();
  }

  Future<void> _reject(Settlement s) async {
    final l10n = AppLocalizations.of(context);
    final me = ref.read(currentUserIdProvider);
    final withdraw = s.createdBy == me;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(withdraw
                    ? l10n.t('Withdraw proposal?', 'Visszavonod a javaslatot?')
                    : l10n.t('Reject proposal?', 'Elutasítod a javaslatot?')),
                content: Text(l10n.t(
                    'The pending record will close without changing account balances or settle-up debt.',
                    'A függő javaslat lezárul, a számlaegyenlegek és elszámolási tartozás módosítása nélkül.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l10n.t('Cancel', 'Mégse'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(withdraw
                          ? l10n.t('Withdraw', 'Visszavonás')
                          : l10n.t('Reject', 'Elutasítás')))
                ]));
    if (confirmed != true || !mounted) return;
    ref.read(appDatabaseProvider).upsertSettlement(Settlement(
        id: s.id,
        householdId: s.householdId,
        fromUser: s.fromUser,
        toUser: s.toUser,
        amountMinor: s.amountMinor,
        currency: s.currency,
        baseAmountMinor: s.baseAmountMinor,
        fromConfirmed: s.fromConfirmed,
        toConfirmed: s.toConfirmed,
        rejectedBy: me,
        note: s.note,
        createdBy: s.createdBy,
        updatedAt: DateTime.now()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(withdraw
            ? l10n.t('Proposal withdrawn.', 'Javaslat visszavonva.')
            : l10n.t('Proposal rejected.', 'Javaslat elutasítva.'))));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final me = ref.watch(currentUserIdProvider);
    final partner = ref.watch(partnerUserIdProvider);
    final hide = ref.watch(hideAmountsProvider);
    final locale = ref.watch(appLocaleProvider);
    final l10n = AppLocalizations.of(context);
    final summary = computeSettleUpBalance(
        meId: me,
        partnerId: partner,
        transactions: db.transactions,
        settlements: db.settlements);
    final records = db.settlements
        .where(
            (s) => s.deletedAt == null && (s.fromUser == me || s.toUser == me))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final pending = records.where((s) => s.status == 'pending').toList();
    final completed = records.where((s) => s.status != 'pending').toList();
    final meName = db.findProfile(me)?.displayName ?? l10n.viewIndividual;
    final partnerName =
        db.findProfile(partner)?.displayName ?? l10n.partnerPersonalAccount;
    Widget recordCard(Settlement s) {
      final needsApproval = s.status == 'pending' &&
          ((s.fromUser == me && !s.fromConfirmed) ||
              (s.toUser == me && !s.toConfirmed));
      final waiting = s.fromConfirmed ? s.toUser : s.fromUser;
      final posting = db.settlementPostings
          .where((p) => p.settlementId == s.id && p.userId == me)
          .firstOrNull;
      final account =
          posting == null ? null : db.findAccount(posting.accountId);
      return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DuoSection(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Text(
                    '${db.findProfile(s.fromUser)?.displayName ?? s.fromUser} → ${db.findProfile(s.toUser)?.displayName ?? s.toUser}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                    Money(s.amountMinor, s.currency)
                        .format(locale: locale, hideAmounts: hide),
                    style: Theme.of(context).textTheme.titleLarge),
                Text(s.status == 'pending'
                    ? needsApproval
                        ? l10n.t('Needs your approval', 'Jóváhagyásodra vár')
                        : l10n.t(
                            'Waiting for ${db.findProfile(waiting)?.displayName ?? waiting}',
                            '${db.findProfile(waiting)?.displayName ?? waiting} jóváhagyására vár')
                    : s.isConfirmed
                        ? l10n.t('Recorded locally · approved by both',
                            'Helyben rögzítve · mindketten jóváhagyták')
                        : s.rejectedBy == s.createdBy
                            ? l10n.t('Withdrawn', 'Visszavonva')
                            : l10n.t('Rejected', 'Elutasítva')),
                Text(
                    '${l10n.t('Proposed by', 'Kezdeményezte')}: ${db.findProfile(s.createdBy)?.displayName ?? s.createdBy}'),
                Text(
                    '${l10n.t('Last updated', 'Utoljára módosítva')}: ${MaterialLocalizations.of(context).formatMediumDate(s.updatedAt)}'),
                if (s.note?.isNotEmpty == true)
                  Text(s.note!, maxLines: 4, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Text(posting == null || account == null
                    ? l10n.t('Your accounts: no balance change.',
                        'Saját számlák: nincs egyenlegmódosítás.')
                    : '${account.name}: ${Money(posting.amountMinor, account.currency).format(locale: locale, hideAmounts: hide)} · ${s.isConfirmed ? l10n.t('recorded locally', 'helyben könyvelve') : l10n.t('only if both approve', 'csak mindkét jóváhagyás után')}'),
                if (s.status == 'pending')
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (needsApproval)
                      FilledButton.icon(
                          onPressed: () => _recordDialog(summary, existing: s),
                          icon: const Icon(Icons.check),
                          label: Text(l10n.t('Review and approve',
                              'Ellenőrzés és jóváhagyás'))),
                    TextButton(
                        onPressed: () => _reject(s),
                        child: Text(s.createdBy == me
                            ? l10n.t('Withdraw', 'Visszavonás')
                            : l10n.t('Reject', 'Elutasítás'))),
                  ]),
              ])));
    }

    return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                onPressed: () => AppShell.openDrawer(context),
                icon: const Icon(Icons.menu),
                tooltip:
                    MaterialLocalizations.of(context).openAppDrawerTooltip),
            title: Text(l10n.settleUp)),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
            children: [
              DuoCard(
                  isHero: true,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            !summary.someoneOwes
                                ? l10n.t('All settled up', 'Minden elszámolva')
                                : summary.partnerOwesMe
                                    ? l10n.t('$partnerName owes $meName',
                                        '$partnerName tartozik neked ($meName)')
                                    : l10n.t('$meName owes $partnerName',
                                        '$meName tartozik neki ($partnerName)'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: context.duo.onHeroSurface)),
                        const SizedBox(height: 12),
                        Text(
                            Money(summary.absoluteOwedMinor)
                                .format(locale: locale, hideAmounts: hide),
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(color: context.duo.onHeroSurface)),
                        const SizedBox(height: 12),
                        Text(
                            l10n.t(
                                'Local records only; no bank payment is sent. Only approved settlements change this balance.',
                                'Csak helyi rögzítés; nem indul banki utalás. Az egyenleget csak jóváhagyott elszámolások módosítják.'),
                            style: TextStyle(color: context.duo.onHeroSurface)),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed: db.household == null || me == partner
                                ? null
                                : () => _recordDialog(summary),
                            icon: const Icon(Icons.edit_note),
                            label: Text(l10n.t('Propose settlement',
                                'Elszámolás kezdeményezése'))),
                      ])),
              const SizedBox(height: 20),
              Text(
                  l10n.t('Pending proposals (${pending.length})',
                      'Függő javaslatok (${pending.length})'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (pending.isEmpty)
                DuoSection(
                    child: Text(l10n.t(
                        'No pending proposals.', 'Nincs függő javaslat.'))),
              ...pending.map(recordCard),
              const SizedBox(height: 16),
              DuoSection(
                  child: ExpansionTile(
                      title: Text(l10n.t('How the balance is calculated',
                          'Az egyenleg számítása')),
                      childrenPadding: const EdgeInsets.all(16),
                      children: [
                    Text(l10n.t(
                        'Shared expenses paid from personal accounts create debt according to their recorded splits. Common-account spending and contributions create no personal debt. Confirmed settlements reduce the debt.',
                        'A személyes számláról fizetett közös kiadások a rögzített megosztás szerint hoznak létre tartozást. A közös számla kiadásai és befizetései nem keletkeztetnek személyes tartozást. A jóváhagyott elszámolások csökkentik a tartozást.')),
                    for (final t in db.transactions.where((t) =>
                        t.kind == TxnKind.expense &&
                        t.scope == Scope.together &&
                        !t.paidFromCommon &&
                        !t.isContribution))
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.merchant ?? l10n.expense,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(MaterialLocalizations.of(context)
                              .formatMediumDate(t.occurredOn)),
                          onTap: () => showTransactionDetails(context, t)),
                  ])),
              const SizedBox(height: 16),
              DuoSection(
                  child: ExpansionTile(
                      title: Text(l10n.t(
                          'Settlement history (${completed.length})',
                          'Elszámolási előzmények (${completed.length})')),
                      childrenPadding: const EdgeInsets.all(12),
                      children: completed.map(recordCard).toList())),
            ]));
  }
}
