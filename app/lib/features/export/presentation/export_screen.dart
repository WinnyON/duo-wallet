import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/auth/backend_session.dart';
import '../../../core/sync/supabase_adapter.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';
import '../../../router.dart';

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
      [
        'Date',
        'Kind',
        'Scope',
        'Category',
        'Merchant',
        'Account',
        'Amount (HUF)',
        'Note'
      ],
    ];
    final byCategory = <String, int>{};
    final byMonth = <String, int>{};

    for (final t in visibleTxns) {
      final cat = t.categoryId != null
          ? db.findCategory(t.categoryId!)?.nameEn ?? 'Other'
          : 'Uncategorized';
      final acc = db.findAccount(t.accountId);
      // Privacy rule: if paid from partner's private account, never reveal account name
      final accLabel = t.paidFromCommon
          ? (acc?.name ?? 'Common Account')
          : (t.paidBy == meId
              ? (acc?.name ?? 'My Personal Account')
              : "Partner's personal account");
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
      for (final e in byCategory.entries)
        [e.key, (e.value / 100).round().toString()],
    ];

    final monthRows = <List<String>>[
      ['Month', 'Total (HUF)'],
      for (final e in byMonth.entries)
        [e.key, (e.value / 100).round().toString()],
    ];

    final accRows = <List<String>>[
      ['Account', 'Ownership', 'Type', 'Currency', 'Live Balance'],
      for (final a in db.accounts.where((a) => a.isCommon || a.ownerId == meId))
        [
          a.name,
          a.ownership.value,
          a.type.value,
          a.currency.code,
          Money(db.computeAccountBalanceMinor(a.id, currentUserId: meId),
                  a.currency)
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
        .map(
            (r) => r.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','))
        .join('\n');
  }

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  ExpenseView _view = ExpenseView.together;
  int _year = DateTime.now().year;
  int? _month;
  String _sheet = 'Transactions';
  String? _status;
  bool _failed = false;
  bool _busy = false;

  Future<void> _copy(String value, String success) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        setState(() {
          _status = success;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = AppLocalizations.of(context).t('Could not copy. Try again.',
              'Nem sikerült másolni. Próbáld újra.');
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final me = ref.watch(currentUserIdProvider);
    final l = AppLocalizations.of(context);
    final sheets = ExportScreen.buildVisibleSheets(
        db: db, meId: me, view: _view, year: _year, month: _month);
    final rows = sheets[_sheet]!;
    final names = {
      'Transactions': l.transactions,
      'By Category': l.t('By category', 'Kategóriánként'),
      'By Month': l.t('By month', 'Havonta'),
      'Accounts': l.accounts,
      'Goals': l.goals,
    };
    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => AppShell.goBackOrHome(context)),
          title: Text(l.exportBackup)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (ref.watch(productionModeProvider))
          DuoSection(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(l.t('Private cloud backup', 'Privát felhőmentés'),
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(l.t(
                            'Stored in your private Supabase bucket folder. Only your authenticated account can read it. Database changes sync separately.',
                            'A Supabase tárhely saját privát mappájában tárolva. Csak a bejelentkezett fiókod olvashatja. Az adatbázis módosításai külön szinkronizálódnak.')),
                        FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _cloudBackup(db, me, restore: false),
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: Text(l.t('Save private cloud backup',
                                'Privát felhőmentés készítése'))),
                        OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _cloudBackup(db, me, restore: true),
                            icon: const Icon(Icons.cloud_download_outlined),
                            label: Text(l.t('Review cloud backup for restore',
                                'Felhőmentés ellenőrzése visszaállításhoz'))),
                      ]))),
        if (_status != null)
          Semantics(
              liveRegion: true,
              child: DuoSection(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Icon(
                            _failed
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: _failed
                                ? Theme.of(context).colorScheme.error
                                : context.duo.positive),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_status!)),
                      ])))),
        DuoSection(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.t('Copy a report', 'Kimutatás másolása'),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(l.t(
                          'Copies text to your clipboard. Paste it into a document or spreadsheet to save it. No file is created.',
                          'Szöveget másol a vágólapra. A mentéshez illeszd be egy dokumentumba vagy táblázatba. Nem készül fájl.')),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final view in ExpenseView.values)
                          ChoiceChip(
                              label: Text(switch (view) {
                                ExpenseView.together => l.viewTogether,
                                ExpenseView.individual => l.viewIndividual,
                                ExpenseView.myTotal => l.viewMyTotal
                              }),
                              selected: _view == view,
                              onSelected: (_) => setState(() => _view = view))
                      ]),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                          initialValue: _year,
                          isExpanded: true,
                          decoration:
                              InputDecoration(labelText: l.t('Year', 'Év')),
                          items: [
                            for (final y in List.generate(
                                11, (i) => DateTime.now().year - 5 + i))
                              DropdownMenuItem(value: y, child: Text('$y'))
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _year = v);
                          }),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                          initialValue: _month,
                          isExpanded: true,
                          decoration:
                              InputDecoration(labelText: l.t('Month', 'Hónap')),
                          items: [
                            DropdownMenuItem(
                                value: null,
                                child: Text(l.t('Full year', 'Egész év'))),
                            for (var m = 1; m <= 12; m++)
                              DropdownMenuItem(
                                  value: m,
                                  child: Text(l.t('Month $m', '$m. hónap')))
                          ],
                          onChanged: (v) => setState(() => _month = v)),
                      const SizedBox(height: 12),
                      Text(l.t(
                          'Only your private records and shared household records are included. Transaction totals use HUF.',
                          'Csak a saját privát és a háztartás közös adatai kerülnek bele. A tranzakcióösszesítők pénzneme HUF.')),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        for (final name in sheets.keys)
                          ChoiceChip(
                              label: Text(
                                  '${names[name]} (${sheets[name]!.length - 1})'),
                              selected: _sheet == name,
                              onSelected: (_) => setState(() => _sheet = name))
                      ]),
                      const SizedBox(height: 12),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _copy(
                                      ExportScreen.toCsvString(rows),
                                      l.t('CSV copied · ${rows.length - 1} rows.',
                                          'CSV másolva · ${rows.length - 1} sor.')),
                              icon: const Icon(Icons.copy),
                              label: Text(l.t('Copy CSV', 'CSV másolása')))),
                      const SizedBox(height: 8),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _copy(
                                      sheets.entries
                                          .map((e) =>
                                              '${names[e.key]}\n${ExportScreen.toCsvString(e.value)}')
                                          .join('\n\n'),
                                      l.t('All sheets copied as text.',
                                          'Minden munkalap szövegként másolva.')),
                              icon: const Icon(Icons.copy_all),
                              label: Text(l.t('Copy all sheets as text',
                                  'Minden munkalap másolása szövegként')))),
                    ]))),
        const SizedBox(height: 12),
        Text(l.t('Preview · first 20 rows', 'Előnézet · első 20 sor'),
            style: Theme.of(context).textTheme.titleMedium),
        DuoSection(
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    for (final col in rows.first) DataColumn(label: Text(col))
                  ],
                  rows: [
                    for (final row in rows.skip(1).take(20))
                      DataRow(cells: [
                        for (final cell in row)
                          DataCell(ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(cell,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis)))
                      ])
                  ],
                ))),
        const SizedBox(height: 12),
        DuoSection(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.t('Local backup', 'Helyi biztonsági mentés'),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(l.t(
                          ref.watch(productionModeProvider)
                              ? 'Your data is encrypted on this device and changes sync with your household when connected. Clipboard copies contain readable financial data: paste only into a private file. Restoring merges matching IDs and queues the restored records for cloud sync.'
                              : 'This demo keeps data in memory. Copy your visible data before closing the app, then paste it into a private file. The clipboard is temporary and may be accessible to other apps. Restore merges records by ID; matching records are replaced. It does not upload or sync them.',
                          ref.watch(productionModeProvider)
                              ? 'Az adatok ezen az eszközön titkosítva vannak, és kapcsolódáskor szinkronizálódnak a háztartással. A vágólap olvasható pénzügyi adatokat tartalmaz: csak privát fájlba illeszd. A visszaállítás azonosító szerint egyesít és felhőszinkronizálásra sorba állítja a tételeket.'
                              : 'A demó a memóriában tárolja az adatokat. Bezárás előtt másold ki a látható adatokat, majd illeszd be egy privát fájlba. A vágólap ideiglenes és más alkalmazások is elérhetik. A visszaállítás azonosító szerint egyesít, az egyező tételeket felülírja. Nem tölt fel és nem szinkronizál.')),
                      const SizedBox(height: 12),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                              onPressed: _busy
                                  ? null
                                  : () => _copy(
                                      const JsonEncoder.withIndent('  ')
                                          .convert(
                                              db.exportVisibleJson(meId: me)),
                                      l.t('JSON copied. Paste it into a private file to keep it.',
                                          'JSON másolva. A megőrzéshez illeszd be privát fájlba.')),
                              icon: const Icon(Icons.copy),
                              label: Text(l.t('Copy JSON backup',
                                  'JSON mentés másolása')))),
                      const SizedBox(height: 8),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _restore(db, me),
                              icon: const Icon(Icons.restore),
                              label: Text(l.t('Restore JSON backup',
                                  'JSON mentés visszaállítása')))),
                    ]))),
      ]),
    );
  }

  Future<void> _cloudBackup(AppDatabase db, String me,
      {required bool restore}) async {
    if (_busy) return;
    final backend = ref.read(backendSessionProvider);
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _status = null;
    });
    Map<String, dynamic>? downloaded;
    try {
      final adapter = SupabaseSyncAdapter(backend.client!);
      if (restore) {
        downloaded = await adapter.downloadBackup();
      } else {
        await backend.flushLocal();
        await adapter.uploadBackup(db.exportVisibleJson(meId: me));
      }
      if (mounted && !restore) {
        setState(() {
          _status =
              l.t('Private cloud backup saved.', 'Privát felhőmentés mentve.');
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = l.t(
              'Cloud backup unavailable. Your local data has not changed. Check your connection and retry.',
              'A felhőmentés nem elérhető. A helyi adatok nem változtak. Ellenőrizd a kapcsolatot és próbáld újra.');
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (downloaded != null && mounted) {
      await _restore(db, me, initialBackup: downloaded);
    }
  }

  Future<void> _restore(AppDatabase db, String me,
      {Map<String, dynamic>? initialBackup}) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(
        text: initialBackup == null
            ? ''
            : const JsonEncoder.withIndent('  ').convert(initialBackup));
    String? error;
    Map<String, dynamic>? reviewed;
    Future<void> close(BuildContext ctx) async {
      if (await confirmDiscardChanges(ctx, dirty: controller.text.isNotEmpty) &&
          ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    }

    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, refresh) => PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) close(ctx);
                  },
                  child: AlertDialog(
                    scrollable: true,
                    title: Text(l.t(
                        'Restore local backup', 'Helyi mentés visszaállítása')),
                    content: SizedBox(
                        width: 480,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.t(
                                  'Paste a Duo Wallet backup for this household. Existing matching IDs will be replaced; other records stay. Review before applying.',
                                  'Illeszd be a háztartás Duo Wallet mentését. Az egyező azonosítók felülíródnak, a többi tétel megmarad. Alkalmazás előtt ellenőrizd.')),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: controller,
                                  minLines: 3,
                                  maxLines: 8,
                                  decoration: InputDecoration(
                                      labelText:
                                          l.t('Backup JSON', 'Mentés JSON'),
                                      errorText: error,
                                      errorMaxLines: 4),
                                  onChanged: (_) => refresh(() {
                                        reviewed = null;
                                        error = null;
                                      })),
                              if (reviewed != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(l.t(
                                        'Ready to merge ${(reviewed!['transactions'] as List).length} transactions and ${(reviewed!['accounts'] as List).length} accounts. Matching records will be replaced. This cannot be undone.',
                                        '${(reviewed!['transactions'] as List).length} tranzakció és ${(reviewed!['accounts'] as List).length} számla egyesíthető. Az egyező tételek felülíródnak. Ez nem vonható vissza.'))),
                            ])),
                    actions: [
                      TextButton(
                          onPressed: () => close(ctx),
                          child: Text(l.t('Cancel', 'Mégse'))),
                      FilledButton(
                          onPressed: () {
                            try {
                              if (reviewed == null) {
                                final decoded = jsonDecode(controller.text);
                                if (decoded is! Map<String, dynamic>) {
                                  throw const FormatException();
                                }
                                db.restoreFromJson(decoded,
                                    meId: me, validateOnly: true);
                                refresh(() {
                                  reviewed = decoded;
                                  error = null;
                                });
                              } else {
                                db.restoreFromJson(reviewed!,
                                    meId: me,
                                    queueWrites:
                                        ref.read(productionModeProvider));
                                Navigator.of(ctx).pop();
                                setState(() {
                                  _status = l.t(
                                      ref.read(productionModeProvider)
                                          ? 'Backup restored; changes queued for cloud sync.'
                                          : 'Backup merged locally. Nothing has been uploaded.',
                                      ref.read(productionModeProvider)
                                          ? 'Mentés visszaállítva; módosítások sorba állítva a felhőszinkronhoz.'
                                          : 'Mentés helyben egyesítve. Nem történt feltöltés.');
                                  _failed = false;
                                });
                              }
                            } catch (_) {
                              refresh(() {
                                reviewed = null;
                                error = l.t(
                                    'This backup is invalid, unsupported, or belongs to another household or user. Your data has not changed.',
                                    'A mentés hibás, nem támogatott, vagy más háztartásé/felhasználóé. Az adatok nem változtak.');
                              });
                            }
                          },
                          child: Text(reviewed == null
                              ? l.t('Review backup', 'Mentés ellenőrzése')
                              : l.t('Apply merge', 'Egyesítés alkalmazása')))
                    ],
                  ),
                )));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
  }
}
