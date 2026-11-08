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
import '../../../theme.dart';
import '../../../router.dart';
import '../../transfers/presentation/transfer_sheet.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  ExpenseView _selectedView = ExpenseView.together;
  final _search = TextEditingController();
  DateTimeRange? _dates;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final me = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hide = ref.watch(hideAmountsProvider);
    final query = _search.text.trim().toLowerCase();
    final rows = db.transactions.where((t) {
      if (t.deletedAt != null ||
          (t.visibility == VisibilityLevel.private && t.createdBy != me)) {
        return false;
      }
      if (_dates != null &&
          (t.occurredOn.isBefore(_dates!.start) ||
              !t.occurredOn
                  .isBefore(_dates!.end.add(const Duration(days: 1))))) {
        return false;
      }
      if (query.isNotEmpty &&
          ![
            t.merchant ?? '',
            t.note ?? '',
            ...t.tags,
            if (t.categoryId != null)
              db.findCategory(t.categoryId!)?.localizedName(locale) ?? ''
          ].join(' ').toLowerCase().contains(query)) {
        return false;
      }
      if (t.kind == TxnKind.expense) {
        return isIncludedInView(t, _selectedView, me);
      }
      return _selectedView == ExpenseView.together
          ? t.visibility == VisibilityLevel.shared
          : t.createdBy == me || t.visibility == VisibilityLevel.shared;
    }).toList()
      ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    final total =
        rows.fold<int>(0, (sum, t) => sum + amountFor(t, _selectedView, me));
    void reset() => setState(() {
          _search.clear();
          _dates = null;
        });
    return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                onPressed: () => AppShell.openDrawer(context),
                icon: const Icon(Icons.menu),
                tooltip:
                    MaterialLocalizations.of(context).openAppDrawerTooltip),
            title: Text(l10n.transactions),
            actions: [
              IconButton(
                  onPressed: () => TransferSheet.show(context),
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: l10n.transfer)
            ]),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final view in ExpenseView.values)
                  ChoiceChip(
                      selected: _selectedView == view,
                      label: Text(switch (view) {
                        ExpenseView.together => l10n.viewTogether,
                        ExpenseView.individual => l10n.viewIndividual,
                        ExpenseView.myTotal => l10n.viewMyTotal
                      }),
                      onSelected: (_) => setState(() => _selectedView = view))
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: l10n.t('Search merchant, note or tag',
                          'Kereskedő, megjegyzés vagy címke keresése'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(Icons.clear),
                              tooltip:
                                  l10n.t('Clear search', 'Keresés törlése')))),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                    onPressed: () async {
                      final dates = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2200),
                          initialDateRange: _dates);
                      if (dates != null && mounted) {
                        setState(() => _dates = dates);
                      }
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text(_dates == null
                        ? l10n.t('All dates · choose period',
                            'Minden dátum · időszak választása')
                        : '${MaterialLocalizations.of(context).formatShortDate(_dates!.start)} – ${MaterialLocalizations.of(context).formatShortDate(_dates!.end)}')),
                if (query.isNotEmpty || _dates != null)
                  TextButton(
                      onPressed: reset,
                      child: Text(l10n.t('Clear filters', 'Szűrők törlése')))
              ]),
              DuoSection(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(_dates == null
                        ? l10n.t('All-time spending · current filters',
                            'Összes eddigi kiadás · aktuális szűrők')
                        : l10n.t('Period spending · current filters',
                            'Időszak kiadásai · aktuális szűrők')),
                    const SizedBox(height: 8),
                    Text(Money(total).format(locale: locale, hideAmounts: hide),
                        style: Theme.of(context).textTheme.headlineSmall)
                  ])),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                DuoSection(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text(l10n.t('No matching transactions.',
                          'Nincs megfelelő tranzakció.')),
                      const SizedBox(height: 8),
                      if (query.isNotEmpty || _dates != null)
                        OutlinedButton(
                            onPressed: reset,
                            child:
                                Text(l10n.t('Clear filters', 'Szűrők törlése')))
                      else
                        FilledButton(
                            onPressed: () =>
                                QuickAddTransactionSheet.show(context),
                            child: Text(l10n.quickAdd))
                    ])),
              for (var index = 0; index < rows.length; index++) ...[
                if (index == 0 ||
                    !DateUtils.isSameDay(
                        rows[index - 1].occurredOn, rows[index].occurredOn))
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          MaterialLocalizations.of(context)
                              .formatFullDate(rows[index].occurredOn),
                          style: Theme.of(context).textTheme.titleSmall)),
                Builder(builder: (context) {
                  final t = rows[index];
                  final category = t.categoryId == null
                      ? null
                      : db.findCategory(t.categoryId!);
                  final title = t.merchant?.isNotEmpty == true
                      ? t.merchant!
                      : category?.localizedName(locale) ??
                          (t.kind == TxnKind.transfer
                              ? l10n.transfer
                              : t.kind == TxnKind.income
                                  ? l10n.income
                                  : l10n.expense);
                  final source = db.findAccount(t.accountId);
                  final accountLabel = source != null &&
                          (source.isCommon || source.ownerId == me)
                      ? source.name
                      : l10n.partnerPersonalAccount;
                  final value = t.kind == TxnKind.expense
                      ? amountFor(t, _selectedView, me)
                      : t.baseAmountMinor;
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DuoSection(
                          onTap: () => showTransactionDetails(context, t),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: Text(title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis)),
                                      PopupMenuButton<String>(
                                          tooltip:
                                              l10n.t('Options', 'Műveletek'),
                                          onSelected: (action) {
                                            if (action == 'edit') {
                                              QuickAddTransactionSheet.show(
                                                  context,
                                                  existing: t);
                                            } else {
                                              confirmDeleteTransaction(
                                                  context, db, t);
                                            }
                                          },
                                          itemBuilder: (_) => [
                                                PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text(l10n.t('Edit',
                                                        'Szerkesztés'))),
                                                PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text(l10n.t(
                                                        'Delete', 'Törlés')))
                                              ])
                                    ]),
                                Text(
                                    '${t.kind == TxnKind.income ? '+' : t.kind == TxnKind.expense ? '−' : ''}${Money(value).format(locale: locale, hideAmounts: hide)}',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                if (t.currency != CurrencyCode.huf)
                                  Text(Money(t.amountMinor, t.currency).format(
                                      locale: locale, hideAmounts: hide)),
                                Text(
                                    '${db.findProfile(t.paidBy)?.displayName ?? t.paidBy} · $accountLabel',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                if (t.note?.isNotEmpty == true)
                                  Text(t.note!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                if (t.tags.isNotEmpty)
                                  Text(t.tags.join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                              ])));
                }),
              ],
            ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => QuickAddTransactionSheet.show(context),
            icon: const Icon(Icons.add),
            label: Text(l10n.quickAdd)));
  }
}

Future<bool> confirmDeleteTransaction(
    BuildContext context, AppDatabase db, Txn transaction) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text(l10n.t('Delete transaction?', 'Tranzakció törlése?')),
              content: Text(
                  '${transaction.merchant ?? l10n.transactions}\n${MaterialLocalizations.of(context).formatMediumDate(transaction.occurredOn)}\n${l10n.t('This removes the recorded account and debt effects.', 'Ez eltávolítja a rögzített számla- és tartozásmódosításokat.')}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(l10n.t('Cancel', 'Mégse'))),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l10n.t('Delete', 'Törlés')))
              ]));
  if (confirmed != true) return false;
  db.softDeleteTransaction(transaction.id);
  return true;
}

Future<void> showTransactionDetails(
    BuildContext context, Txn transaction) async {
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
            final db = ref.watch(appDatabaseProvider);
            final meId = ref.watch(currentUserIdProvider);
            final hide = ref.watch(hideAmountsProvider);
            final locale = ref.watch(appLocaleProvider);
            final l10n = AppLocalizations.of(ctx);
            if (transaction.deletedAt != null ||
                (transaction.visibility == VisibilityLevel.private &&
                    transaction.createdBy != meId)) {
              return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.t('Transaction unavailable.',
                      'A tranzakció nem elérhető.')));
            }
            final category = transaction.categoryId == null
                ? null
                : db.findCategory(transaction.categoryId!);
            return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                l10n.t('Transaction details',
                                    'Tranzakció részletei'),
                                style: Theme.of(ctx).textTheme.titleLarge)),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                            tooltip: l10n.t('Close', 'Bezárás'))
                      ]),
                      Text(
                          transaction.merchant ??
                              category?.localizedName(locale) ??
                              (transaction.kind == TxnKind.transfer
                                  ? l10n.transfer
                                  : transaction.kind == TxnKind.income
                                      ? l10n.income
                                      : l10n.expense),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(ctx).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Text(
                          Money(transaction.amountMinor, transaction.currency)
                              .format(locale: locale, hideAmounts: hide),
                          style: Theme.of(ctx).textTheme.headlineSmall),
                      Text(MaterialLocalizations.of(ctx)
                          .formatFullDate(transaction.occurredOn)),
                      if (category != null)
                        Text(category.localizedName(locale)),
                      if (transaction.note?.isNotEmpty == true)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(transaction.note!,
                                maxLines: 6, overflow: TextOverflow.ellipsis)),
                      if (transaction.tags.isNotEmpty)
                        Text(transaction.tags.join(' · '),
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 16),
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              QuickAddTransactionSheet.show(context,
                                  existing: transaction);
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(l10n.t('Edit', 'Szerkesztés'))),
                        OutlinedButton.icon(
                            onPressed: () async {
                              if (await confirmDeleteTransaction(
                                      ctx, db, transaction) &&
                                  ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: Text(l10n.t('Delete', 'Törlés'))),
                      ]),
                    ]));
          }));
}

class QuickAddTransactionSheet extends ConsumerStatefulWidget {
  final Txn? existing;
  final String? initialAccountId;
  const QuickAddTransactionSheet(
      {super.key, this.existing, this.initialAccountId});
  static Future<void> show(BuildContext context,
      {Txn? existing, String? initialAccountId}) {
    if (existing?.kind == TxnKind.transfer) {
      return TransferSheet.show(context, existing: existing);
    }
    return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        useSafeArea: true,
        sheetAnimationStyle: Motion.sheet,
        builder: (_) => QuickAddTransactionSheet(
            existing: existing, initialAccountId: initialAccountId));
  }

  @override
  ConsumerState<QuickAddTransactionSheet> createState() =>
      _QuickAddTransactionSheetState();
}

class _QuickAddTransactionSheetState
    extends ConsumerState<QuickAddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountFocus = FocusNode();
  final _rateFocus = FocusNode();
  final _accountFocus = FocusNode();
  final _categoryFocus = FocusNode();
  final _amountCtrl = TextEditingController();
  final _fxRateCtrl = TextEditingController(text: '1');
  final _merchantCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  TxnKind _kind = TxnKind.expense;
  Scope _scope = Scope.together;
  CurrencyCode _currency = CurrencyCode.huf;
  String? _accountId;
  String? _categoryId;
  int _mySplitPct = 50;
  DateTime _occurredOn = DateTime.now();
  String? _initialDraft;
  bool _closing = false;
  bool _saving = false;
  String get _draft =>
      '$_kind|$_scope|$_currency|$_accountId|$_categoryId|$_mySplitPct|$_occurredOn|${_amountCtrl.text}|${_fxRateCtrl.text}|${_merchantCtrl.text}|${_noteCtrl.text}|${_tagsCtrl.text}';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _accountId = widget.initialAccountId;
    if (ref.read(partnerUserIdProvider).isEmpty) _scope = Scope.individual;
    if (e != null) {
      _kind = e.kind;
      _scope = e.scope;
      _currency = e.currency;
      _amountCtrl.text =
          Money(e.amountMinor, e.currency).majorAmount.toStringAsFixed(2);
      _fxRateCtrl.text = e.fxRateToBase.toString();
      _accountId = e.accountId;
      _categoryId = e.categoryId;
      _merchantCtrl.text = e.merchant ?? '';
      _noteCtrl.text = e.note ?? '';
      _tagsCtrl.text = e.tags.join(', ');
      _occurredOn = e.occurredOn;
      final me = ref.read(currentUserIdProvider);
      if (e.baseAmountMinor > 0 && e.baseShares.isNotEmpty) {
        _mySplitPct = (((e.baseShares[me] ?? 0) / e.baseAmountMinor) * 100)
            .round()
            .clamp(0, 100);
      }
    }
  }

  @override
  void dispose() {
    for (final focus in [
      _amountFocus,
      _rateFocus,
      _accountFocus,
      _categoryFocus
    ]) {
      focus.dispose();
    }
    for (final c in [
      _amountCtrl,
      _fxRateCtrl,
      _merchantCtrl,
      _noteCtrl,
      _tagsCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _close() async {
    if (await confirmDiscardChanges(context, dirty: _draft != _initialDraft) &&
        mounted) {
      setState(() => _closing = true);
      Navigator.pop(context);
    }
  }

  void _submit(List<Account> accounts, bool partnerPaid) {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      final focus = parsePositiveAmount(_amountCtrl.text) == null
          ? _amountFocus
          : _currency != CurrencyCode.huf &&
                  parsePositiveRate(_fxRateCtrl.text) == null
              ? _rateFocus
              : _accountId == null
                  ? _accountFocus
                  : _categoryFocus;
      focus.requestFocus();
      if (focus.context != null) Scrollable.ensureVisible(focus.context!);
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final me = ref.read(currentUserIdProvider);
    final partner = ref.read(partnerUserIdProvider);
    final e = widget.existing;
    final selected = accounts.where((a) => a.id == _accountId).firstOrNull;
    if (db.household == null || (!partnerPaid && selected == null)) return;
    final amount =
        Money.fromMajor(parsePositiveAmount(_amountCtrl.text)!, _currency)
            .amountMinor;
    final rate = _currency == CurrencyCode.huf
        ? 1.0
        : parsePositiveRate(_fxRateCtrl.text)!;
    final base = FxService.convertMinor(amount, rate);
    final common = partnerPaid ? e!.paidFromCommon : selected!.isCommon;
    final scope = common
        ? Scope.together
        : !partnerPaid && partner.isEmpty
            ? Scope.individual
            : _scope;
    final split = scope == Scope.together && partner.isNotEmpty
        ? calculatePercentageSplit(
            amountMinor: amount,
            baseAmountMinor: base,
            userA: me,
            userB: partner,
            pctA: _mySplitPct)
        : calculateIndividualSplit(
            amountMinor: amount,
            baseAmountMinor: base,
            ownerId: e?.paidBy ?? me);
    final unchangedSplit = e != null &&
        e.amountMinor == amount &&
        e.baseAmountMinor == base &&
        e.scope == scope &&
        _mySplitPct ==
            (e.baseAmountMinor == 0
                ? 50
                : (((e.baseShares[me] ?? 0) / e.baseAmountMinor) * 100)
                    .round()
                    .clamp(0, 100));
    // Preserve the original split proportions, including rounding, for partner-paid edits.
    Map<String, int> proportional(
        Map<String, int> original, int total, int oldTotal) {
      if (original.isEmpty || oldTotal <= 0) return {};
      final result = <String, int>{};
      var allocated = 0;
      for (final key in original.keys) {
        final value = key == original.keys.last
            ? total - allocated
            : (original[key]! * total / oldTotal).round();
        result[key] = value;
        allocated += value;
      }
      return result;
    }

    final now = DateTime.now();
    setState(() => _saving = true);
    final saved = db.saveTransaction(Txn(
        id: e?.id ?? const Uuid().v4(),
        householdId: e?.householdId ?? db.household!.id,
        kind: _kind,
        scope: scope,
        visibility: scope == Scope.together
            ? VisibilityLevel.shared
            : VisibilityLevel.private,
        occurredOn: _occurredOn,
        amountMinor: amount,
        currency: _currency,
        fxRateToBase: rate,
        fxSource: e?.fxSource ??
            (_currency == CurrencyCode.huf ? FxSource.ecb : FxSource.manual),
        baseAmountMinor: base,
        paidBy: e?.paidBy ?? me,
        paidFromCommon: common,
        accountId: partnerPaid ? e!.accountId : _accountId!,
        accountAmountMinor: e != null &&
                e.currency == _currency &&
                e.accountId == _accountId &&
                e.amountMinor > 0
            ? (e.accountAmountMinor * amount / e.amountMinor).round()
            : (selected!.currency == _currency
                ? amount
                : FxService.convertMinor(
                    amount,
                    ref
                        .read(fxServiceProvider)
                        .getRate(_currency, selected.currency)
                        .rate)),
        categoryId: _categoryId,
        merchant: _merchantCtrl.text.trim().isEmpty
            ? null
            : _merchantCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        recurringRuleId: e?.recurringRuleId,
        createdBy: e?.createdBy ?? me,
        createdAt: e?.createdAt ?? now,
        updatedAt: now,
        shares: unchangedSplit
            ? e.shares
            : partnerPaid
                ? proportional(e!.shares, amount, e.amountMinor)
                : split.sharesMinor,
        baseShares: unchangedSplit
            ? e.baseShares
            : partnerPaid
                ? proportional(e!.baseShares, base, e.baseAmountMinor)
                : split.baseSharesMinor,
        tags: _tagsCtrl.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()));
    if (e == null && saved.visibility == VisibilityLevel.shared) {
      db.addActivity(ActivityEvent(
          id: const Uuid().v4(),
          householdId: saved.householdId,
          actorId: me,
          eventType:
              saved.kind == TxnKind.income ? 'income_added' : 'expense_added',
          summaryEn: 'Transaction recorded locally',
          summaryHu: 'Tranzakció helyben rögzítve',
          createdAt: now));
    }
    setState(() => _closing = true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final me = ref.watch(currentUserIdProvider);
    final partner = ref.watch(partnerUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final l10n = AppLocalizations.of(context);
    final e = widget.existing;
    final accounts = db.accounts
        .where((a) =>
            a.deletedAt == null &&
            !a.archived &&
            (a.isCommon || a.ownerId == me))
        .toList();
    final partnerPaid = e != null && e.paidBy != me && !e.paidFromCommon;
    final categories = db.categories
        .where(
            (c) => c.kind == (_kind == TxnKind.income ? 'income' : 'expense'))
        .toList();
    if (_initialDraft == null) {
      _accountId ??= accounts.firstOrNull?.id;
      _categoryId ??= categories.firstOrNull?.id;
      _initialDraft = _draft;
    }
    final selected = accounts.where((a) => a.id == _accountId).firstOrNull;
    final common = partnerPaid ? e.paidFromCommon : selected?.isCommon == true;
    final error = l10n.t(
        'Enter a valid positive amount.', 'Adj meg érvényes pozitív összeget.');
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
                                    e == null
                                        ? l10n.quickAdd
                                        : l10n.t('Edit transaction',
                                            'Tranzakció szerkesztése'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge)),
                            if (e != null)
                              IconButton(
                                  onPressed: () async {
                                    if (await confirmDeleteTransaction(
                                            context, db, e) &&
                                        context.mounted) {
                                      setState(() => _closing = true);
                                      Navigator.pop(context);
                                    }
                                  },
                                  tooltip: l10n.t('Delete', 'Törlés'),
                                  icon: const Icon(Icons.delete_outline)),
                            IconButton(
                                onPressed: _close,
                                tooltip: l10n.t('Close', 'Bezárás'),
                                icon: const Icon(Icons.close))
                          ]),
                          if (db.household == null ||
                              (accounts.isEmpty && !partnerPaid))
                            Text(l10n.t(
                                'Create an account and local household before recording a transaction.',
                                'Tranzakció rögzítése előtt hozz létre számlát és helyi háztartást.')),
                          if (!partnerPaid)
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final kind in [
                                TxnKind.expense,
                                TxnKind.income
                              ])
                                ChoiceChip(
                                    label: Text(kind == TxnKind.expense
                                        ? l10n.expense
                                        : l10n.income),
                                    selected: _kind == kind,
                                    onSelected: (_) => setState(() {
                                          _kind = kind;
                                          _categoryId = null;
                                        })),
                              if (e == null)
                                ActionChip(
                                    label: Text(l10n.transfer),
                                    onPressed: () async {
                                      if (await confirmDiscardChanges(context,
                                              dirty: _draft != _initialDraft) &&
                                          context.mounted) {
                                        setState(() => _closing = true);
                                        Navigator.pop(context);
                                        TransferSheet.show(context);
                                      }
                                    }),
                            ]),
                          const SizedBox(height: 12),
                          TextFormField(
                              controller: _amountCtrl,
                              focusNode: _amountFocus,
                              autofocus: false,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: l10n.t('Amount', 'Összeg')),
                              validator: (v) => parsePositiveAmount(v ?? '') ==
                                          null ||
                                      Money.fromMajor(
                                                  parsePositiveAmount(v ?? '')!,
                                                  _currency)
                                              .amountMinor <=
                                          0
                                  ? error
                                  : null),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<CurrencyCode>(
                              isExpanded: true,
                              initialValue: _currency,
                              decoration: InputDecoration(
                                  labelText: l10n.t('Currency', 'Pénznem')),
                              items: CurrencyCode.values
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c.code)))
                                  .toList(),
                              onChanged: partnerPaid
                                  ? null
                                  : (c) {
                                      if (c != null) {
                                        setState(() {
                                          _currency = c;
                                          _fxRateCtrl.text = ref
                                              .read(fxServiceProvider)
                                              .getRate(c, CurrencyCode.huf)
                                              .rate
                                              .toString();
                                        });
                                      }
                                    }),
                          const SizedBox(height: 12),
                          if (partnerPaid)
                            Text(l10n.t(
                                'Paid by ${db.findProfile(e.paidBy)?.displayName ?? l10n.partnerPersonalAccount}. Original private account and split are preserved.',
                                'Fizette: ${db.findProfile(e.paidBy)?.displayName ?? l10n.partnerPersonalAccount}. Az eredeti privát számla és megosztás megmarad.'))
                          else
                            DropdownButtonFormField<String>(
                                focusNode: _accountFocus,
                                isExpanded: true,
                                initialValue:
                                    accounts.any((a) => a.id == _accountId)
                                        ? _accountId
                                        : null,
                                decoration: InputDecoration(
                                    labelText: l10n.t('Account', 'Számla'),
                                    helperMaxLines: 5,
                                    helperText: common
                                        ? l10n.t(
                                            'Common account: shared expense with no personal settle-up debt.',
                                            'Közös számla: közös kiadás, személyes elszámolási tartozás nélkül.')
                                        : null),
                                items: accounts
                                    .map((a) => DropdownMenuItem(
                                        value: a.id,
                                        child: Text(
                                            '${a.name} (${a.currency.code})',
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                validator: (v) => v == null
                                    ? l10n.t('Choose an account.',
                                        'Válassz számlát.')
                                    : null,
                                onChanged: (v) => setState(() {
                                      _accountId = v;
                                      if (accounts
                                              .where((a) => a.id == v)
                                              .firstOrNull
                                              ?.isCommon ==
                                          true) {
                                        _scope = Scope.together;
                                      }
                                    })),
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
                          DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: ValueKey(_kind),
                              focusNode: _categoryFocus,
                              initialValue:
                                  categories.any((c) => c.id == _categoryId)
                                      ? _categoryId
                                      : null,
                              decoration: InputDecoration(
                                  labelText: l10n.t('Category', 'Kategória')),
                              items: categories
                                  .map((c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.localizedName(locale),
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              validator: (v) => v == null
                                  ? l10n.t(
                                      'Choose a category. Create one first if needed.',
                                      'Válassz kategóriát. Ha szükséges, előbb hozz létre egyet.')
                                  : null,
                              onChanged: (v) =>
                                  setState(() => _categoryId = v)),
                          if (_kind == TxnKind.expense &&
                              !partnerPaid &&
                              !common) ...[
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, children: [
                              for (final scope in Scope.values)
                                ChoiceChip(
                                    label: Text(scope == Scope.together
                                        ? l10n.viewTogether
                                        : l10n.viewIndividual),
                                    selected: _scope == scope,
                                    onSelected: scope == Scope.together &&
                                            partner.isEmpty
                                        ? null
                                        : (_) => setState(() => _scope = scope))
                            ]),
                            if (partner.isEmpty)
                              Text(l10n.t('Invite a partner to split expenses.',
                                  'Hívj meg egy társat a kiadások megosztásához.')),
                            if (_scope == Scope.together &&
                                partner.isNotEmpty) ...[
                              Text(
                                  '${db.findProfile(me)?.displayName ?? l10n.viewIndividual}: $_mySplitPct% / ${db.findProfile(partner)?.displayName ?? l10n.partnerPersonalAccount}: ${100 - _mySplitPct}%'),
                              Slider(
                                  value: _mySplitPct.toDouble(),
                                  min: 0,
                                  max: 100,
                                  divisions: 20,
                                  label: '$_mySplitPct%',
                                  onChanged: (v) =>
                                      setState(() => _mySplitPct = v.round()))
                            ],
                          ],
                          ExpansionTile(
                              key: ValueKey(_currency),
                              maintainState: true,
                              initiallyExpanded: _currency != CurrencyCode.huf,
                              tilePadding: EdgeInsets.zero,
                              title: Text(l10n.t(
                                  'Optional details', 'További részletek')),
                              children: [
                                if (_currency != CurrencyCode.huf)
                                  TextFormField(
                                      controller: _fxRateCtrl,
                                      focusNode: _rateFocus,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: InputDecoration(
                                          labelText:
                                              '${l10n.t('Exchange rate', 'Árfolyam')} (${_currency.code} → HUF)'),
                                      validator: (v) =>
                                          parsePositiveRate(v ?? '') == null
                                              ? error
                                              : null),
                                TextFormField(
                                    controller: _merchantCtrl,
                                    decoration: InputDecoration(
                                        labelText: l10n.t('Merchant / title',
                                            'Kereskedő / megnevezés'))),
                                TextFormField(
                                    controller: _noteCtrl,
                                    decoration: InputDecoration(
                                        labelText:
                                            l10n.t('Note', 'Megjegyzés'))),
                                TextFormField(
                                    controller: _tagsCtrl,
                                    decoration: InputDecoration(
                                        labelText: l10n.t(
                                            'Tags (comma separated)',
                                            'Címkék (vesszővel elválasztva)'))),
                              ]),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                              onPressed: !_saving &&
                                      db.household != null &&
                                      (partnerPaid || accounts.isNotEmpty)
                                  ? () => _submit(accounts, partnerPaid)
                                  : null,
                              icon: const Icon(Icons.check),
                              label: Text(l10n.t('Save', 'Mentés'))),
                        ])))));
  }
}
