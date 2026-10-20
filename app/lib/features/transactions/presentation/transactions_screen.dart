import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/splits.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/fx_service.dart';
import '../../../core/money/money.dart';
import '../../transfers/presentation/transfer_sheet.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  ExpenseView _selectedView = ExpenseView.together;

  String _accountLabel(
    AppDatabase db,
    Txn t,
    String meId,
    AppLocalizations l10n,
  ) {
    if (t.paidFromCommon) {
      final common = db.findAccount(t.accountId);
      return '👥 ${common?.name ?? l10n.commonAccount}';
    }
    final acc = db.findAccount(t.accountId);
    // Privacy rule: if the expense was paid from partner's personal account, hide the account name!
    if (acc == null || (acc.ownerId != null && acc.ownerId != meId)) {
      final payer = db.findProfile(t.paidBy);
      final payerName = payer?.displayName;
      return payerName != null
          ? l10n.t(
              "$payerName's personal account",
              '$payerName saját számlája',
            )
          : l10n.partnerPersonalAccount;
    }
    return '🔒 ${acc.name}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);

    final allTxns = db.transactions.where((t) {
      if (t.visibility == VisibilityLevel.private && t.createdBy != meId) {
        return false;
      }
      if (t.kind == TxnKind.expense) {
        return isIncludedInView(t, _selectedView, meId);
      }
      // Show visible income & transfers when on Together (shared) or Individual/MyTotal (mine)
      if (_selectedView == ExpenseView.together) {
        return t.visibility == VisibilityLevel.shared;
      }
      return t.createdBy == meId || t.visibility == VisibilityLevel.shared;
    }).toList();

    final viewExpenseTotalMinor = db.transactions.fold<int>(
      0,
      (sum, t) => sum + amountFor(t, _selectedView, meId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.transactions),
        actions: [
          IconButton(
            tooltip: l10n.transfer,
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => TransferSheet.show(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<ExpenseView>(
              segments: [
                ButtonSegment(
                  value: ExpenseView.together,
                  icon: const Icon(Icons.group_outlined),
                  label: Text(l10n.viewTogether),
                ),
                ButtonSegment(
                  value: ExpenseView.individual,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(l10n.viewIndividual),
                ),
                ButtonSegment(
                  value: ExpenseView.myTotal,
                  icon: const Icon(Icons.person_pin_circle_outlined),
                  label: Text(l10n.viewMyTotal),
                ),
              ],
              selected: {_selectedView},
              onSelectionChanged: (s) => setState(() => _selectedView = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    switch (_selectedView) {
                      ExpenseView.together => Icons.groups,
                      ExpenseView.individual => Icons.lock,
                      ExpenseView.myTotal => Icons.calculate_outlined,
                    },
                  ),
                ),
                title: Text(
                  switch (_selectedView) {
                    ExpenseView.together => l10n.t(
                      'Together Expenses (Full Amount)',
                      'Közös kiadások (Teljes összeg)',
                    ),
                    ExpenseView.individual => l10n.t(
                      'My Individual Expenses (🔒 Private)',
                      'Egyéni kiadásaim (🔒 Privát)',
                    ),
                    ExpenseView.myTotal => l10n.t(
                      'My Total (Individual + My Share of Together)',
                      'Saját összesen (Egyéni + Közös rám eső része)',
                    ),
                  },
                ),
                trailing: Text(
                  Money(viewExpenseTotalMinor).format(
                    locale: locale,
                    hideAmounts: hideAmounts,
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: allTxns.isEmpty
                ? Center(
                    child: Text(
                      l10n.t(
                        'No transactions in this view yet.',
                        'Még nincs tranzakció ebben a nézetben.',
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    itemCount: allTxns.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final t = allTxns[index];
                      final cat = t.categoryId != null
                          ? db.findCategory(t.categoryId!)
                          : null;
                      final payer = db.findProfile(t.paidBy);
                      final displayMinor = t.kind == TxnKind.expense
                          ? amountFor(t, _selectedView, meId)
                          : t.baseAmountMinor;
                      final isPartialShare =
                          t.kind == TxnKind.expense &&
                          _selectedView == ExpenseView.myTotal &&
                          t.scope == Scope.together;

                      final title =
                          t.merchant?.isNotEmpty == true
                              ? t.merchant!
                              : (cat?.localizedName(locale) ??
                                  (t.isContribution
                                      ? l10n.t('Contribution', 'Közös befizetés')
                                      : l10n.t(t.kind.value, t.kind.value)));

                      final accLabel = _accountLabel(db, t, meId, l10n);
                      final dateStr =
                          t.occurredOn.toIso8601String().split('T').first;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: switch (t.kind) {
                            TxnKind.expense =>
                              Theme.of(context).colorScheme.errorContainer,
                            TxnKind.income =>
                              Theme.of(context).colorScheme.primaryContainer,
                            TxnKind.transfer =>
                              Theme.of(context).colorScheme.secondaryContainer,
                          },
                          child: Icon(
                            switch (t.kind) {
                              TxnKind.expense => Icons.arrow_upward,
                              TxnKind.income => Icons.arrow_downward,
                              TxnKind.transfer => Icons.swap_horiz,
                            },
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (t.visibility == VisibilityLevel.private)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    '🔒 ${l10n.privateBadge}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Chip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    '👥 ${l10n.sharedBadge}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$dateStr • ${payer?.displayName ?? t.paidBy} • $accLabel',
                            ),
                            if (t.note != null && t.note!.isNotEmpty)
                              Text(t.note!),
                            if (t.tags.isNotEmpty)
                              Wrap(
                                spacing: 4,
                                children: t.tags
                                    .map(
                                      (tag) => Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(
                                          '#$tag',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${t.kind == TxnKind.income ? "+" : t.kind == TxnKind.expense ? "-" : ""}${Money(displayMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: t.kind == TxnKind.income
                                    ? Colors.teal
                                    : null,
                              ),
                            ),
                            if (isPartialShare)
                              Text(
                                '${l10n.t("Total", "Össz")}: ${Money(t.baseAmountMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else if (t.currency != CurrencyCode.huf)
                              Text(
                                Money(t.amountMinor, t.currency).format(
                                  locale: locale,
                                  hideAmounts: hideAmounts,
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        onTap: () => QuickAddTransactionSheet.show(
                          context,
                          existing: t,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => QuickAddTransactionSheet.show(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.quickAdd),
      ),
    );
  }
}

class QuickAddTransactionSheet extends ConsumerStatefulWidget {
  final Txn? existing;

  const QuickAddTransactionSheet({super.key, this.existing});

  static Future<void> show(BuildContext context, {Txn? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => QuickAddTransactionSheet(existing: existing),
    );
  }

  @override
  ConsumerState<QuickAddTransactionSheet> createState() =>
      _QuickAddTransactionSheetState();
}

class _QuickAddTransactionSheetState
    extends ConsumerState<QuickAddTransactionSheet> {
  final _amountCtrl = TextEditingController();
  final _fxRateCtrl = TextEditingController(text: '1.0');
  final _merchantCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  TxnKind _kind = TxnKind.expense;
  Scope _scope = Scope.together;
  CurrencyCode _currency = CurrencyCode.huf;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  int _mySplitPct = 50;
  DateTime _occurredOn = DateTime.now();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _kind = e.kind;
      _scope = e.scope;
      _currency = e.currency;
      _amountCtrl.text = Money(e.amountMinor, e.currency).majorAmount.toStringAsFixed(
        e.currency.displayDecimals,
      );
      _fxRateCtrl.text = e.fxRateToBase.toString();
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
      _categoryId = e.categoryId;
      _merchantCtrl.text = e.merchant ?? '';
      _noteCtrl.text = e.note ?? '';
      _tagsCtrl.text = e.tags.join(', ');
      _occurredOn = e.occurredOn;
      if (e.baseAmountMinor > 0 && e.baseShares.isNotEmpty) {
        final meId = e.paidBy;
        final share = e.baseShares[meId] ?? (e.baseAmountMinor ~/ 2);
        _mySplitPct = ((share / e.baseAmountMinor) * 100).round().clamp(0, 100);
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _fxRateCtrl.dispose();
    _merchantCtrl.dispose();
    _noteCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _onCurrencyChanged(CurrencyCode next) {
    final fx = ref.read(fxServiceProvider);
    final quote = fx.getRate(next, CurrencyCode.huf);
    setState(() {
      _currency = next;
      _fxRateCtrl.text = quote.rate.toStringAsFixed(
        next == CurrencyCode.huf ? 1 : 2,
      );
    });
  }

  void _submit(List<Account> visibleAccounts, List<Category> categories) {
    final l10n = AppLocalizations.of(context);
    final rawAmt = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (rawAmt <= 0 || _accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('Enter a valid amount and account.', 'Adj meg érvényes összeget és számlát.'),
          ),
        ),
      );
      return;
    }

    final db = ref.read(appDatabaseProvider);
    final meId = ref.read(currentUserIdProvider);
    final partnerId = ref.read(partnerUserIdProvider);

    final selectedAcc = visibleAccounts
        .where((a) => a.id == _accountId)
        .firstOrNull;
    final paidFromCommon = selectedAcc?.isCommon ?? false;
    final effectiveScope = paidFromCommon ? Scope.together : _scope;

    final amountMinor = Money.fromMajor(rawAmt, _currency).amountMinor;
    final fxRate = _currency == CurrencyCode.huf
        ? 1.0
        : (double.tryParse(_fxRateCtrl.text.replaceAll(',', '.')) ?? 1.0);
    final baseAmountMinor = FxService.convertMinor(amountMinor, fxRate);

    final split = effectiveScope == Scope.together
        ? calculatePercentageSplit(
            amountMinor: amountMinor,
            baseAmountMinor: baseAmountMinor,
            userA: meId,
            userB: partnerId,
            pctA: _mySplitPct,
          )
        : calculateIndividualSplit(
            amountMinor: amountMinor,
            baseAmountMinor: baseAmountMinor,
            ownerId: meId,
          );

    final tags = _tagsCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final toAcc = _toAccountId != null
        ? visibleAccounts.where((a) => a.id == _toAccountId).firstOrNull
        : null;
    final isContribution =
        _kind == TxnKind.transfer &&
        !paidFromCommon &&
        (toAcc?.isCommon ?? false);

    final now = DateTime.now();
    final draft = Txn(
      id: widget.existing?.id ?? const Uuid().v4(),
      householdId: db.household?.id ?? 'hh-default-001',
      kind: _kind,
      scope: effectiveScope,
      visibility: effectiveScope == Scope.together
          ? VisibilityLevel.shared
          : VisibilityLevel.private,
      occurredOn: _occurredOn,
      amountMinor: amountMinor,
      currency: _currency,
      fxRateToBase: fxRate,
      fxSource: _currency == CurrencyCode.huf ? FxSource.ecb : FxSource.manual,
      baseAmountMinor: baseAmountMinor,
      paidBy: widget.existing?.paidBy ?? meId,
      paidFromCommon: paidFromCommon,
      accountId: _accountId!,
      accountAmountMinor: amountMinor,
      toAccountId: _kind == TxnKind.transfer ? _toAccountId : null,
      toAccountAmountMinor: _kind == TxnKind.transfer ? amountMinor : null,
      isContribution: isContribution,
      categoryId: _categoryId,
      merchant: _merchantCtrl.text.trim().isEmpty
          ? null
          : _merchantCtrl.text.trim(),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      createdBy: widget.existing?.createdBy ?? meId,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      shares: split.sharesMinor,
      baseShares: split.baseSharesMinor,
      tags: tags,
    );

    final saved = db.saveTransaction(draft);

    // Record shared activity feed event only for shared items
    if (saved.visibility == VisibilityLevel.shared && widget.existing == null) {
      final meProfile = db.findProfile(meId);
      final actorName = meProfile?.displayName ?? meId;
      final label = saved.merchant ?? 'Transaction';
      final fmtEn = Money(saved.baseAmountMinor).format(locale: 'en');
      final fmtHu = Money(saved.baseAmountMinor).format(locale: 'hu');
      db.addActivity(
        ActivityEvent(
          id: const Uuid().v4(),
          householdId: saved.householdId,
          actorId: meId,
          eventType: 'expense_added',
          summaryEn: '$actorName added $label $fmtEn (Together)',
          summaryHu: '$actorName hozzáadta: $label $fmtHu (Közös)',
          amountMinor: saved.baseAmountMinor,
          createdAt: now,
        ),
      );
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final partnerId = ref.watch(partnerUserIdProvider);
    final locale = ref.watch(appLocaleProvider);

    final visibleAccounts = db.accounts
        .where((a) => !a.archived && (a.isCommon || a.ownerId == meId))
        .toList();

    if (_accountId == null && visibleAccounts.isNotEmpty) {
      _accountId = visibleAccounts.first.id;
    }

    final selectedAcc = visibleAccounts
        .where((a) => a.id == _accountId)
        .firstOrNull;
    final isCommonSelected = selectedAcc?.isCommon ?? false;
    if (isCommonSelected && _scope != Scope.together) {
      _scope = Scope.together;
    }

    final filteredCategories = db.categories
        .where(
          (c) => _kind == TxnKind.income
              ? c.kind == 'income'
              : c.kind == 'expense',
        )
        .toList();
    if (_categoryId == null && filteredCategories.isNotEmpty) {
      _categoryId = filteredCategories.first.id;
    }

    final meName = db.findProfile(meId)?.displayName ?? 'Me';
    final partnerName = db.findProfile(partnerId)?.displayName ?? 'Partner';

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.existing == null
                      ? l10n.quickAdd
                      : l10n.t('Edit Transaction', 'Tranzakció szerkesztése'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Row(
                  children: [
                    if (widget.existing != null)
                      IconButton(
                        tooltip: l10n.t('Delete', 'Törlés'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          db.softDeleteTransaction(widget.existing!.id);
                          Navigator.of(context).pop();
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<TxnKind>(
              segments: [
                ButtonSegment(value: TxnKind.expense, label: Text(l10n.expense)),
                ButtonSegment(value: TxnKind.income, label: Text(l10n.income)),
                ButtonSegment(
                  value: TxnKind.transfer,
                  label: Text(l10n.transfer),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amountCtrl,
                    autofocus: widget.existing == null,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.t('Amount', 'Összeg'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<CurrencyCode>(
                    initialValue: _currency,
                    decoration: InputDecoration(
                      labelText: l10n.t('Currency', 'Pénznem'),
                      border: const OutlineInputBorder(),
                    ),
                    items: CurrencyCode.values
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.code),
                          ),
                        )
                        .toList(),
                    onChanged: (c) {
                      if (c != null) _onCurrencyChanged(c);
                    },
                  ),
                ),
              ],
            ),
            if (_currency != CurrencyCode.huf) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _fxRateCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.t(
                    'Locked FX Rate (${_currency.code} → HUF)',
                    'Rögzített árfolyam (${_currency.code} → HUF)',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  visibleAccounts.any((a) => a.id == _accountId)
                      ? _accountId
                      : null,
              decoration: InputDecoration(
                labelText: l10n.t('Account', 'Számla'),
                border: const OutlineInputBorder(),
                helperText: isCommonSelected
                    ? l10n.t(
                        'Common account automatically forces Together scope (no settle-up debt).',
                        'Közös számla esetén automatikusan Közös (nincs elszámolási tartozás).',
                      )
                    : null,
              ),
              items: visibleAccounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.isCommon ? "👥" : "🔒"} ${a.name} (${a.currency.code})',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _accountId = v;
                  final acc = visibleAccounts
                      .where((a) => a.id == v)
                      .firstOrNull;
                  if (acc != null && acc.isCommon) {
                    _scope = Scope.together;
                  }
                });
              },
            ),
            if (_kind == TxnKind.transfer) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    visibleAccounts.any((a) => a.id == _toAccountId)
                        ? _toAccountId
                        : null,
                decoration: InputDecoration(
                  labelText: l10n.t('To Account', 'Cél számla'),
                  border: const OutlineInputBorder(),
                ),
                items: visibleAccounts
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.isCommon ? "👥" : "🔒"} ${a.name} (${a.currency.code})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _toAccountId = v),
              ),
            ],
            if (_kind == TxnKind.expense) ...[
              const SizedBox(height: 12),
              SegmentedButton<Scope>(
                segments: [
                  ButtonSegment(
                    value: Scope.together,
                    icon: const Icon(Icons.groups_outlined),
                    label: Text('👥 ${l10n.viewTogether}'),
                  ),
                  ButtonSegment(
                    value: Scope.individual,
                    enabled: !isCommonSelected,
                    icon: const Icon(Icons.lock_outline),
                    label: Text('🔒 ${l10n.viewIndividual}'),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (s) {
                  if (!isCommonSelected) {
                    setState(() => _scope = s.first);
                  }
                },
              ),
              if (_scope == Scope.together) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$meName: $_mySplitPct%'),
                    Text('$partnerName: ${100 - _mySplitPct}%'),
                  ],
                ),
                Slider(
                  value: _mySplitPct.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '$_mySplitPct% / ${100 - _mySplitPct}%',
                  onChanged: (v) => setState(() => _mySplitPct = v.round()),
                ),
              ],
            ],
            if (_kind != TxnKind.transfer && filteredCategories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.t('Category', 'Kategória'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: filteredCategories.map((c) {
                  final selected = _categoryId == c.id;
                  return ChoiceChip(
                    label: Text(c.localizedName(locale)),
                    selected: selected,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _merchantCtrl,
              decoration: InputDecoration(
                labelText: l10n.t('Merchant / Title', 'Kereskedő / Megnevezés'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: l10n.t('Note', 'Megjegyzés'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tagsCtrl,
              decoration: InputDecoration(
                labelText: l10n.t(
                  'Tags (comma separated, e.g. Greece 2027)',
                  'Címkék (vesszővel elválasztva, pl. Görögország 2027)',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _submit(visibleAccounts, filteredCategories),
              icon: const Icon(Icons.check),
              label: Text(l10n.t('Save', 'Mentés')),
            ),
          ],
        ),
      ),
    );
  }
}
