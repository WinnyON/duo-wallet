import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/fx_service.dart';
import '../../../core/money/money.dart';

class TransferSheet extends ConsumerStatefulWidget {
  final String? initialFromAccountId;
  final String? initialToAccountId;
  final bool initialIsContribution;

  const TransferSheet({
    super.key,
    this.initialFromAccountId,
    this.initialToAccountId,
    this.initialIsContribution = false,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialFromAccountId,
    String? initialToAccountId,
    bool initialIsContribution = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransferSheet(
        initialFromAccountId: initialFromAccountId,
        initialToAccountId: initialToAccountId,
        initialIsContribution: initialIsContribution,
      ),
    );
  }

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  final _amountCtrl = TextEditingController();
  final _rateCtrl = TextEditingController(text: '1.0');
  final _noteCtrl = TextEditingController();

  String? _fromAccountId;
  String? _toAccountId;
  bool _isContribution = false;
  final DateTime _occurredOn = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fromAccountId = widget.initialFromAccountId;
    _toAccountId = widget.initialToAccountId;
    _isContribution = widget.initialIsContribution;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _rateCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _recalcAutoFlags(List<Account> visibleAccounts) {
    final fromAcc = visibleAccounts
        .where((a) => a.id == _fromAccountId)
        .firstOrNull;
    final toAcc = visibleAccounts
        .where((a) => a.id == _toAccountId)
        .firstOrNull;
    if (fromAcc != null && toAcc != null) {
      _isContribution = !fromAcc.isCommon && toAcc.isCommon;
      final fx = ref.read(fxServiceProvider);
      final quote = fx.getRate(fromAcc.currency, toAcc.currency);
      _rateCtrl.text = quote.rate.toStringAsFixed(
        fromAcc.currency == toAcc.currency ? 1 : 4,
      );
    }
  }

  void _submit(List<Account> visibleAccounts) {
    final l10n = AppLocalizations.of(context);
    final rawAmt = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (rawAmt <= 0 ||
        _fromAccountId == null ||
        _toAccountId == null ||
        _fromAccountId == _toAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'Select two different accounts and enter a positive amount.',
              'Válassz két különböző számlát és adj meg pozitív összeget.',
            ),
          ),
        ),
      );
      return;
    }

    final db = ref.read(appDatabaseProvider);
    final meId = ref.read(currentUserIdProvider);
    final fx = ref.read(fxServiceProvider);

    final fromAcc = visibleAccounts.firstWhere((a) => a.id == _fromAccountId);
    final toAcc = visibleAccounts.firstWhere((a) => a.id == _toAccountId);

    final amountMinor = Money.fromMajor(rawAmt, fromAcc.currency).amountMinor;
    final crossRate =
        double.tryParse(_rateCtrl.text.replaceAll(',', '.')) ??
        fx.getRate(fromAcc.currency, toAcc.currency).rate;
    final toAmountMinor = fromAcc.currency == toAcc.currency
        ? amountMinor
        : FxService.convertMinor(amountMinor, crossRate);

    final rateToBase = fx.getRate(fromAcc.currency, CurrencyCode.huf).rate;
    final baseAmountMinor = FxService.convertMinor(amountMinor, rateToBase);

    final isContribution =
        _isContribution || (!fromAcc.isCommon && toAcc.isCommon);
    final involvesCommon = fromAcc.isCommon || toAcc.isCommon || isContribution;
    final now = DateTime.now();

    final txn = Txn(
      id: const Uuid().v4(),
      householdId: db.household?.id ?? 'hh-default-001',
      kind: TxnKind.transfer,
      scope: involvesCommon ? Scope.together : Scope.individual,
      visibility: involvesCommon
          ? VisibilityLevel.shared
          : VisibilityLevel.private,
      occurredOn: _occurredOn,
      amountMinor: amountMinor,
      currency: fromAcc.currency,
      fxRateToBase: rateToBase,
      fxSource: FxSource.ecb,
      baseAmountMinor: baseAmountMinor,
      paidBy: meId,
      paidFromCommon: fromAcc.isCommon,
      accountId: fromAcc.id,
      accountAmountMinor: amountMinor,
      toAccountId: toAcc.id,
      toAccountAmountMinor: toAmountMinor,
      isContribution: isContribution,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      createdBy: meId,
      createdAt: now,
      updatedAt: now,
    );

    db.saveTransaction(txn);

    if (isContribution) {
      final meProfile = db.findProfile(meId);
      final name = meProfile?.displayName ?? meId;
      final formattedEn = Money(amountMinor, fromAcc.currency).format(locale: 'en');
      final formattedHu = Money(amountMinor, fromAcc.currency).format(locale: 'hu');
      db.addActivity(
        ActivityEvent(
          id: const Uuid().v4(),
          householdId: txn.householdId,
          actorId: meId,
          eventType: 'contribution_added',
          summaryEn: '$name contributed $formattedEn to common account',
          summaryHu: '$name befizetett $formattedHu összeget a közös számlára',
          amountMinor: baseAmountMinor,
          currency: CurrencyCode.huf,
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

    final visibleAccounts = db.accounts
        .where((a) => !a.archived && (a.isCommon || a.ownerId == meId))
        .toList();

    if (visibleAccounts.isNotEmpty) {
      if (_fromAccountId == null ||
          !visibleAccounts.any((a) => a.id == _fromAccountId)) {
        final personal = visibleAccounts.where((a) => !a.isCommon).firstOrNull;
        _fromAccountId = (personal ?? visibleAccounts.first).id;
      }
      if (_toAccountId == null ||
          !visibleAccounts.any((a) => a.id == _toAccountId)) {
        final common = visibleAccounts.where((a) => a.isCommon).firstOrNull;
        final fallback = visibleAccounts
            .where((a) => a.id != _fromAccountId)
            .firstOrNull;
        _toAccountId = (common ?? fallback ?? visibleAccounts.first).id;
      }
    }

    final fromAcc = visibleAccounts
        .where((a) => a.id == _fromAccountId)
        .firstOrNull;
    final toAcc = visibleAccounts
        .where((a) => a.id == _toAccountId)
        .firstOrNull;
    final crossCurrency =
        fromAcc != null && toAcc != null && fromAcc.currency != toAcc.currency;
    final personalToCommon =
        fromAcc != null && toAcc != null && !fromAcc.isCommon && toAcc.isCommon;

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
                  l10n.t('Transfer / Contribution', 'Átvezetés / Befizetés'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _fromAccountId,
              decoration: InputDecoration(
                labelText: l10n.t('From account', 'Forrás számla'),
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
              onChanged: (v) {
                setState(() {
                  _fromAccountId = v;
                  _recalcAutoFlags(visibleAccounts);
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _toAccountId,
              decoration: InputDecoration(
                labelText: l10n.t('To account', 'Cél számla'),
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
              onChanged: (v) {
                setState(() {
                  _toAccountId = v;
                  _recalcAutoFlags(visibleAccounts);
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    '${l10n.t('Amount', 'Összeg')} (${fromAcc?.currency.code ?? 'HUF'})',
                border: const OutlineInputBorder(),
              ),
            ),
            if (crossCurrency) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.t(
                    'Exchange rate (${fromAcc.currency.code} → ${toAcc.currency.code})',
                    'Árfolyam (${fromAcc.currency.code} → ${toAcc.currency.code})',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.t(
                  'Count as common-account contribution',
                  'Közös számla havi befizetésként számít',
                ),
              ),
              subtitle: Text(
                l10n.t(
                  'Shared with partner (source personal account stays hidden). Does not affect settle-up.',
                  'Megosztva a partnerrel (a forrás számla rejtett marad). Nem módosítja az elszámolást.',
                ),
              ),
              value: _isContribution || personalToCommon,
              onChanged: personalToCommon
                  ? null
                  : (v) => setState(() => _isContribution = v),
            ),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: l10n.t('Note (optional)', 'Megjegyzés (opcionális)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _submit(visibleAccounts),
              icon: const Icon(Icons.swap_horiz),
              label: Text(l10n.t('Save Transfer', 'Átvezetés mentése')),
            ),
          ],
        ),
      ),
    );
  }
}
