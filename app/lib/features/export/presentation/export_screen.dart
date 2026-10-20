import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  /// Builds tabular sheets (Transactions, By Category, By Month, Accounts, Goals)
  /// strictly from data visible to [meId] in [view] and [year].
  static Map<String, List<List<String>>> buildVisibleSheets({
    required AppDatabase db,
    required String meId,
    required ExpenseView view,
    required int year,
    int? month,
  }) {
    final visibleTxns = db.transactions.where((t) {
      if (t.occurredOn.year != year) return false;
      if (month != null && t.occurredOn.month != month) return false;
      if (t.visibility == VisibilityLevel.private && t.createdBy != meId) {
        return false;
      }
      return t.kind != TxnKind.expense || isIncludedInView(t, view, meId);
    }).toList();

    final txnRows = <List<String>>[
      ['Date', 'Kind', 'Scope', 'Category', 'Merchant', 'Account', 'Amount (HUF)', 'Note'],
    ];
    final byCategory = <String, int>{};
    final byMonth = <String, int>{};

    for (final t in visibleTxns) {
      final cat = t.categoryId != null ? db.findCategory(t.categoryId!)?.nameEn ?? 'Other' : 'Uncategorized';
      final acc = db.findAccount(t.accountId);
      // Privacy rule: if paid from partner's private account, never reveal account name
      final accLabel = t.paidFromCommon
          ? (acc?.name ?? 'Common Account')
          : (t.paidBy == meId ? (acc?.name ?? 'My Personal Account') : "Partner's personal account");
      final effectiveMinor = t.kind == TxnKind.expense
          ? amountFor(t, view, meId)
          : t.baseAmountMinor;
      final dateStr = t.occurredOn.toIso8601String().split('T').first;
      txnRows.add([
        dateStr,
        t.kind.value,
        t.scope.value,
        cat,
        t.merchant ?? '',
        accLabel,
        (effectiveMinor / 100).round().toString(),
        t.note ?? '',
      ]);

      if (t.kind == TxnKind.expense && effectiveMinor > 0) {
        byCategory[cat] = (byCategory[cat] ?? 0) + effectiveMinor;
        final ym = dateStr.substring(0, 7);
        byMonth[ym] = (byMonth[ym] ?? 0) + effectiveMinor;
      }
    }

    final catRows = <List<String>>[
      ['Category', 'Total (HUF)'],
      for (final e in byCategory.entries) [e.key, (e.value / 100).round().toString()],
    ];

    final monthRows = <List<String>>[
      ['Month', 'Total (HUF)'],
      for (final e in byMonth.entries) [e.key, (e.value / 100).round().toString()],
    ];

    final accRows = <List<String>>[
      ['Account', 'Ownership', 'Type', 'Currency', 'Live Balance'],
      for (final a in db.accounts.where((a) => a.isCommon || a.ownerId == meId))
        [
          a.name,
          a.ownership.value,
          a.type.value,
          a.currency.code,
          Money(db.computeAccountBalanceMinor(a.id, currentUserId: meId), a.currency)
              .format(locale: 'en'),
        ],
    ];

    final goalRows = <List<String>>[
      ['Goal', 'Scope', 'Target', 'Saved', 'Deadline'],
      for (final g in db.goals.where((g) => g.isShared || g.ownerId == meId))
        [
          g.name,
          g.scope,
          (g.targetAmountMinor / 100).round().toString(),
          (g.savedAmountMinor / 100).round().toString(),
          g.deadline?.toIso8601String().split('T').first ?? '-',
        ],
    ];

    return {
      'Transactions': txnRows,
      'By Category': catRows,
      'By Month': monthRows,
      'Accounts': accRows,
      'Goals': goalRows,
    };
  }

  static String toCsvString(List<List<String>> rows) {
    return rows
        .map((r) => r.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','))
        .join('\n');
  }

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  ExpenseView _selectedView = ExpenseView.together;
  int _selectedYear = DateTime.now().year;
  int? _selectedMonth; // null = full year
  String _selectedSheet = 'Transactions';
  String? _statusBanner;

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final l10n = AppLocalizations.of(context);

    final sheets = ExportScreen.buildVisibleSheets(
      db: db,
      meId: meId,
      view: _selectedView,
      year: _selectedYear,
      month: _selectedMonth,
    );
    final activeRows = sheets[_selectedSheet] ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.exportBackup)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_statusBanner != null)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_statusBanner!),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Tabular Export (CSV / XLSX)', 'Táblázatos exportálás (CSV / XLSX)'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t(
                      'Contains only data visible to you (Together + your own personal items). Partner private data never reaches your phone.',
                      'Csak a számodra látható adatokat tartalmazza (Közös + saját tételek).',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      SegmentedButton<ExpenseView>(
                        segments: [
                          ButtonSegment(
                            value: ExpenseView.together,
                            label: Text(l10n.viewTogether),
                          ),
                          ButtonSegment(
                            value: ExpenseView.myTotal,
                            label: Text(l10n.viewMyTotal),
                          ),
                        ],
                        selected: {_selectedView},
                        onSelectionChanged: (s) => setState(() => _selectedView = s.first),
                      ),
                      DropdownButton<int>(
                        value: _selectedYear,
                        items: [
                          for (final y in [_selectedYear - 1, _selectedYear, _selectedYear + 1])
                            DropdownMenuItem(value: y, child: Text('$y')),
                        ],
                        onChanged: (y) {
                          if (y != null) setState(() => _selectedYear = y);
                        },
                      ),
                      DropdownButton<int?>(
                        value: _selectedMonth,
                        hint: Text(l10n.t('Full year', 'Egész év')),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(l10n.t('Full year', 'Egész év')),
                          ),
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem<int?>(value: m, child: Text('Month $m')),
                        ],
                        onChanged: (m) => setState(() => _selectedMonth = m),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final name in sheets.keys)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$name (${(sheets[name]!.length - 1).clamp(0, 9999)})'),
                              selected: _selectedSheet == name,
                              onSelected: (_) => setState(() => _selectedSheet = name),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          final csv = ExportScreen.toCsvString(activeRows);
                          await Clipboard.setData(ClipboardData(text: csv));
                          setState(() {
                            _statusBanner = l10n.t(
                              'Copied $_selectedSheet CSV (${activeRows.length - 1} rows) to clipboard.',
                              '$_selectedSheet CSV a vágólapra másolva (${activeRows.length - 1} sor).',
                            );
                          });
                        },
                        icon: const Icon(Icons.table_view),
                        label: Text(l10n.t('Export CSV', 'CSV exportálás')),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final allSheetsText = sheets.entries
                              .map((e) => '=== ${e.key} ===\n${ExportScreen.toCsvString(e.value)}')
                              .join('\n\n');
                          await Clipboard.setData(ClipboardData(text: allSheetsText));
                          setState(() {
                            _statusBanner = l10n.t(
                              'Multi-sheet workbook (${sheets.length} sheets) prepared & copied.',
                              'Többlapos munkafüzet (${sheets.length} munkalap) elkészítve.',
                            );
                          });
                        },
                        icon: const Icon(Icons.grid_on),
                        label: Text(l10n.t('Export Workbook (XLSX/TSV)', 'Munkafüzet exportálás')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: activeRows.isEmpty
                  ? const SizedBox.shrink()
                  : DataTable(
                      columns: [
                        for (final col in activeRows.first) DataColumn(label: Text(col)),
                      ],
                      rows: [
                        for (final row in activeRows.skip(1))
                          DataRow(
                            cells: [for (final cell in row) DataCell(Text(cell))],
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Full JSON Backup & Restore', 'Teljes JSON biztonsági mentés és visszaállítás'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t(
                      'Safe to store offline: local database only holds your own private data and shared household rows.',
                      'Biztonságosan tárolható: a helyi adatbázis csak a saját és a közös adatokat tartalmazza.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final jsonStr = const JsonEncoder.withIndent('  ')
                              .convert(db.exportVisibleJson());
                          await Clipboard.setData(ClipboardData(text: jsonStr));
                          setState(() {
                            _statusBanner = l10n.t(
                              'Full JSON backup copied (${db.transactions.length} txns, ${db.accounts.length} accounts).',
                              'Teljes JSON mentés vágólapra másolva (${db.transactions.length} tranzakció).',
                            );
                          });
                        },
                        icon: const Icon(Icons.backup_outlined),
                        label: Text(l10n.t('Export JSON Backup', 'JSON mentés')),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _showRestoreDialog(context, db, l10n),
                        icon: const Icon(Icons.restore),
                        label: Text(l10n.t('Restore from JSON', 'Visszaállítás JSON-ból')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRestoreDialog(
    BuildContext context,
    AppDatabase db,
    AppLocalizations l10n,
  ) async {
    final ctrl = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(db.exportVisibleJson()),
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('Restore JSON Backup', 'JSON mentés visszaállítása')),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '{ "household": ... }',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.t('Cancel', 'Mégse')),
          ),
          FilledButton(
            onPressed: () {
              try {
                final decoded = jsonDecode(ctrl.text) as Map<String, dynamic>;
                db.restoreFromJson(decoded);
                Navigator.of(ctx).pop();
                setState(() {
                  _statusBanner = l10n.t(
                    'Backup restored successfully.',
                    'A biztonsági mentés sikeresen visszaállítva.',
                  );
                });
              } catch (e) {
                setState(() {
                  _statusBanner = 'Invalid JSON: $e';
                });
                Navigator.of(ctx).pop();
              }
            },
            child: Text(l10n.t('Restore', 'Visszaállítás')),
          ),
        ],
      ),
    );
  }
}
