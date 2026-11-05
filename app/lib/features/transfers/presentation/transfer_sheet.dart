import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/fx_service.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';

double? parsePositiveRate(String text) {
  final input = text.trim();
  if (!RegExp(r'^\d+(?:[.,]\d{1,12})?$').hasMatch(input)) return null;
  final value = double.tryParse(input.replaceAll(',', '.'));
  return value == null || !value.isFinite || value <= 0 || value > 1000000000
      ? null
      : value;
}

int? safeConvertedMinor(int amountMinor, double rate) {
  final converted = amountMinor * rate;
  if (!converted.isFinite || converted < .5 || converted > 9007199254740991) {
    return null;
  }
  return converted.round();
}

class TransferSheet extends ConsumerStatefulWidget {
  final String? initialFromAccountId;
  final String? initialToAccountId;
  final bool initialIsContribution;
  final Txn? existing;

  const TransferSheet(
      {super.key,
      this.initialFromAccountId,
      this.initialToAccountId,
      this.initialIsContribution = false,
      this.existing});

  static Future<void> show(BuildContext context,
      {String? initialFromAccountId,
      String? initialToAccountId,
      bool initialIsContribution = false,
      Txn? existing}) {
    return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        sheetAnimationStyle: Motion.sheet,
        builder: (_) => TransferSheet(
            initialFromAccountId: initialFromAccountId,
            initialToAccountId: initialToAccountId,
            initialIsContribution: initialIsContribution,
            existing: existing));
  }

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountFocus = FocusNode();
  final _rateFocus = FocusNode();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();
  final _amountCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _fromAccountId;
  String? _toAccountId;
  late DateTime _occurredOn;
  String? _initialDraft;
  String? _initialRate;
  bool _closing = false;
  bool _saving = false;

  String get _draft =>
      '$_fromAccountId|$_toAccountId|${_amountCtrl.text}|${_rateCtrl.text}|${_noteCtrl.text}|$_occurredOn';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fromAccountId = e?.accountId ?? widget.initialFromAccountId;
    _toAccountId = e?.toAccountId ?? widget.initialToAccountId;
    _occurredOn = e?.occurredOn ?? DateTime.now();
    if (e != null) {
      _amountCtrl.text = Money(e.accountAmountMinor, e.currency)
          .majorAmount
          .toStringAsFixed(2);
      _rateCtrl.text = e.accountAmountMinor == 0
          ? '1'
          : ((e.toAccountAmountMinor ?? e.accountAmountMinor) /
                  e.accountAmountMinor)
              .toStringAsFixed(12);
      _noteCtrl.text = e.note ?? '';
    }
    for (final ctrl in [_amountCtrl, _rateCtrl, _noteCtrl]) {
      ctrl.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final focus in [_amountFocus, _rateFocus, _fromFocus, _toFocus]) {
      focus.dispose();
    }
    _amountCtrl.dispose();
    _rateCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (await confirmDiscardChanges(context, dirty: _initialDraft != _draft) &&
        mounted) {
      setState(() => _closing = true);
      Navigator.of(context).pop();
    }
  }

  void _quote(List<Account> accounts) {
    final from = accounts.where((a) => a.id == _fromAccountId).firstOrNull;
    final to = accounts.where((a) => a.id == _toAccountId).firstOrNull;
    if (from != null && to != null) {
      _rateCtrl.text = ref
          .read(fxServiceProvider)
          .getRate(from.currency, to.currency)
          .rate
          .toStringAsFixed(12);
    }
  }

  Future<void> _submit(Account from, Account to) async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      final focus = _fromAccountId == _toAccountId
          ? _toFocus
          : parsePositiveAmount(_amountCtrl.text) == null
              ? _amountFocus
              : _rateFocus;
      focus.requestFocus();
      if (focus.context != null) Scrollable.ensureVisible(focus.context!);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final amount =
        Money.fromMajor(parsePositiveAmount(_amountCtrl.text)!, from.currency)
            .amountMinor;
    final rate =
        from.currency == to.currency ? 1.0 : parsePositiveRate(_rateCtrl.text)!;
    final e = widget.existing;
    final preserveCredit = e != null &&
        e.accountId == from.id &&
        e.toAccountId == to.id &&
        e.accountAmountMinor == amount &&
        _rateCtrl.text == _initialRate;
    final credit = preserveCredit
        ? e.toAccountAmountMinor ?? amount
        : safeConvertedMinor(amount, rate);
    if (credit == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(l10n.t('Record transfer?', 'Átvezetés rögzítése?')),
                content: Text(
                    '${from.name}: −${Money(amount, from.currency).format(locale: l10n.locale.languageCode)}\n${to.name}: +${Money(credit, to.currency).format(locale: l10n.locale.languageCode)}\n\n${l10n.t('Records only; does not send a bank payment.', 'Csak rögzítés; nem indít banki utalást.')}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l10n.t('Cancel', 'Mégse'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l10n.t('Record', 'Rögzítés')))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final db = ref.read(appDatabaseProvider);
    final meId = ref.read(currentUserIdProvider);
    final now = DateTime.now();
    final baseRate = e != null && e.currency == from.currency
        ? e.fxRateToBase
        : ref
            .read(fxServiceProvider)
            .getRate(from.currency, CurrencyCode.huf)
            .rate;
    final common = from.isCommon || to.isCommon;
    final saved = db.saveTransaction(Txn(
        id: e?.id ?? const Uuid().v4(),
        householdId: e?.householdId ?? db.household!.id,
        kind: TxnKind.transfer,
        scope: common ? Scope.together : Scope.individual,
        visibility: common ? VisibilityLevel.shared : VisibilityLevel.private,
        occurredOn: _occurredOn,
        amountMinor: amount,
        currency: from.currency,
        fxRateToBase: baseRate,
        fxSource: e?.fxSource ??
            ref
                .read(fxServiceProvider)
                .getRate(from.currency, CurrencyCode.huf)
                .source,
        baseAmountMinor: FxService.convertMinor(amount, baseRate),
        paidBy: e?.paidBy ?? meId,
        paidFromCommon: from.isCommon,
        accountId: from.id,
        accountAmountMinor: amount,
        toAccountId: to.id,
        toAccountAmountMinor: credit,
        isContribution: !from.isCommon && to.isCommon,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        createdBy: e?.createdBy ?? meId,
        createdAt: e?.createdAt ?? now,
        recurringRuleId: e?.recurringRuleId,
        tags: e?.tags ?? const [],
        updatedAt: now));
    if (e == null && saved.visibility == VisibilityLevel.shared) {
      db.addActivity(ActivityEvent(
          id: const Uuid().v4(),
          householdId: saved.householdId,
          actorId: meId,
          eventType:
              saved.isContribution ? 'contribution_added' : 'transfer_added',
          summaryEn: saved.isContribution
              ? 'Common-account contribution recorded locally'
              : 'Transfer recorded locally',
          summaryHu: saved.isContribution
              ? 'Közös számla befizetése helyben rögzítve'
              : 'Átvezetés helyben rögzítve',
          createdAt: now));
    }
    if (mounted) {
      setState(() => _closing = true);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final l10n = AppLocalizations.of(context);
    final accounts = db.accounts
        .where((a) =>
            a.deletedAt == null &&
            !a.archived &&
            (a.isCommon || a.ownerId == meId))
        .toList();
    if (_initialDraft == null) {
      _fromAccountId ??= accounts.where((a) => !a.isCommon).firstOrNull?.id ??
          accounts.firstOrNull?.id;
      _toAccountId ??= accounts
              .where((a) => a.id != _fromAccountId && a.isCommon)
              .firstOrNull
              ?.id ??
          accounts.where((a) => a.id != _fromAccountId).firstOrNull?.id;
      if (widget.existing == null) _quote(accounts);
      _initialRate = _rateCtrl.text;
      _initialDraft = _draft;
    }
    final from = accounts.where((a) => a.id == _fromAccountId).firstOrNull;
    final to = accounts.where((a) => a.id == _toAccountId).firstOrNull;
    final available = from != null && to != null && db.household != null;
    final cross = from != null && to != null && from.currency != to.currency;
    final raw = parsePositiveAmount(_amountCtrl.text);
    final rate = cross ? parsePositiveRate(_rateCtrl.text) : 1.0;
    final creditPreview = raw == null || rate == null || from == null
        ? null
        : safeConvertedMinor(
            Money.fromMajor(raw, from.currency).amountMinor, rate);
    final error = l10n.t(
        'Enter a valid positive number.', 'Adj meg érvényes pozitív számot.');
    return PopScope(
        canPop: _closing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: SingleChildScrollView(
                child: Form(
                    key: _formKey,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(
                                    l10n.t('Record transfer',
                                        'Átvezetés rögzítése'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge)),
                            IconButton(
                                onPressed: _close,
                                icon: const Icon(Icons.close),
                                tooltip: l10n.t('Close', 'Bezárás'))
                          ]),
                          Text(l10n.t(
                              'Records only; does not send a bank payment.',
                              'Csak rögzítés; nem indít banki utalást.')),
                          if (accounts.length < 2 || !available)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(l10n.t(
                                    'Two accessible accounts and a local household are required. Create accounts first.',
                                    'Két elérhető számla és helyi háztartás szükséges. Előbb hozz létre számlákat.'))),
                          for (final source in [true, false]) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                                focusNode: source ? _fromFocus : _toFocus,
                                isExpanded: true,
                                initialValue:
                                    accounts.any((a) => a.id == (source ? _fromAccountId : _toAccountId))
                                        ? (source
                                            ? _fromAccountId
                                            : _toAccountId)
                                        : null,
                                decoration: InputDecoration(
                                    labelText: source
                                        ? l10n.t(
                                            'From account', 'Forrás számla')
                                        : l10n.t('To account', 'Cél számla')),
                                items: accounts
                                    .map((a) => DropdownMenuItem(
                                        value: a.id,
                                        child: Text(
                                            '${a.name} (${a.currency.code})',
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (v) =>
                                    v == null || _fromAccountId == _toAccountId
                                        ? l10n.t(
                                            'Choose two different accounts.',
                                            'Válassz két különböző számlát.')
                                        : null,
                                onChanged: (v) => setState(() {
                                      if (source) {
                                        _fromAccountId = v;
                                      } else {
                                        _toAccountId = v;
                                      }
                                      _quote(accounts);
                                    })),
                          ],
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: _amountCtrl,
                              focusNode: _amountFocus,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText:
                                      '${l10n.t('Amount', 'Összeg')} (${from?.currency.code ?? ''})'),
                              validator: (v) =>
                                  parsePositiveAmount(v ?? '') == null ||
                                          (from != null &&
                                              Money.fromMajor(
                                                          parsePositiveAmount(
                                                              v ?? '')!,
                                                          from.currency)
                                                      .amountMinor <=
                                                  0)
                                      ? error
                                      : null),
                          if (cross) ...[
                            const SizedBox(height: 12),
                            Text(widget.existing == null
                                ? l10n.t(
                                    'Starts from a local estimated quote; check and edit the rate before recording.',
                                    'Helyi becsült árfolyammal indul; rögzítés előtt ellenőrizd és módosítsd.')
                                : l10n.t(
                                    'Recorded exchange rate; editing changes the credited amount.',
                                    'Rögzített árfolyam; módosítása megváltoztatja a jóváírt összeget.')),
                            TextFormField(
                                controller: _rateCtrl,
                                focusNode: _rateFocus,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText:
                                        '${l10n.t('Exchange rate', 'Árfolyam')} (${from.currency.code} → ${to.currency.code})'),
                                validator: (v) {
                                  final quote = parsePositiveRate(v ?? '');
                                  return quote == null ||
                                          (raw != null &&
                                              safeConvertedMinor(
                                                      Money.fromMajor(raw,
                                                              from.currency)
                                                          .amountMinor,
                                                      quote) ==
                                                  null)
                                      ? error
                                      : null;
                                })
                          ],
                          if (from != null &&
                              to != null &&
                              raw != null &&
                              rate != null &&
                              creditPreview != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                    '${l10n.t('Debit', 'Terhelés')}: ${Money.fromMajor(raw, from.currency).format(locale: l10n.locale.languageCode)}\n${l10n.t('Credit', 'Jóváírás')}: ${Money(creditPreview, to.currency).format(locale: l10n.locale.languageCode)}')),
                          if (from != null &&
                              to != null &&
                              !from.isCommon &&
                              to.isCommon)
                            Text(l10n.t(
                                'Counts as a common-account contribution; does not change settle-up debt.',
                                'Közös számla befizetésének számít; nem módosítja az elszámolási tartozást.')),
                          TextButton.icon(
                              onPressed: () async {
                                final date = await showDatePicker(
                                    context: context,
                                    initialDate: _occurredOn,
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime(2200));
                                if (date != null && mounted) {
                                  setState(() => _occurredOn = date);
                                }
                              },
                              icon: const Icon(Icons.calendar_today),
                              label: Text(MaterialLocalizations.of(context)
                                  .formatMediumDate(_occurredOn))),
                          TextFormField(
                              controller: _noteCtrl,
                              decoration: InputDecoration(
                                  labelText: l10n.t('Note (optional)',
                                      'Megjegyzés (opcionális)'))),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                              onPressed: available && !_saving
                                  ? () => _submit(from, to)
                                  : null,
                              icon: const Icon(Icons.check),
                              label: Text(l10n.t(
                                  'Review transfer', 'Átvezetés ellenőrzése'))),
                        ])))));
  }
}
