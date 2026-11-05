import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../theme.dart';
import '../../../router.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});
  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  String _kind = 'expense';
  bool _showRetired = false;

  Category _updated(Category c, Map<String, dynamic> values) =>
      Category.fromJson({
        ...c.toJson(),
        ...values,
        'updated_at': DateTime.now().toIso8601String()
      });

  Future<void> _edit(AppDatabase db, {Category? existing}) async {
    final l = AppLocalizations.of(context);
    final name = TextEditingController(
        text: existing?.localizedName(l.locale.languageCode) ?? '');
    final translation = TextEditingController(
        text: existing == null
            ? ''
            : (l.isHu ? existing.nameEn : existing.nameHu));
    final form = GlobalKey<FormState>();
    var essential = existing?.isEssential ?? false;
    var color = existing?.color ?? '#6366F1';
    final originalName = name.text;
    final originalTranslation = translation.text;
    bool dirty() =>
        name.text != originalName ||
        translation.text != originalTranslation ||
        essential != (existing?.isEssential ?? false) ||
        color != (existing?.color ?? '#6366F1');
    Future<void> close(BuildContext ctx) async {
      if (await confirmDiscardChanges(ctx, dirty: dirty()) && ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) close(ctx);
                },
                child: AlertDialog(
                  scrollable: true,
                  title: Text(existing == null
                      ? l.t('New category', 'Új kategória')
                      : l.t('Edit category', 'Kategória szerkesztése')),
                  content: Form(
                      key: form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                                controller: name,
                                autofocus: true,
                                maxLength: 80,
                                decoration: InputDecoration(
                                    labelText:
                                        l.t('Category name', 'Kategória neve')),
                                validator: (v) => (v?.trim().isEmpty ?? true)
                                    ? l.t('Enter a name.', 'Adj meg egy nevet.')
                                    : null),
                            ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: Text(l.t('Optional translation',
                                    'Fordítás (nem kötelező)')),
                                children: [
                                  TextField(
                                      controller: translation,
                                      maxLength: 80,
                                      decoration: InputDecoration(
                                          labelText:
                                              l.isHu ? 'English' : 'Magyar'))
                                ]),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(l.t(
                                    'Essential expense', 'Alapvető kiadás')),
                                subtitle: Text(l.t(
                                    'Include in the emergency-fund spending estimate.',
                                    'Beleszámít a vésztartalék kiadásbecslésébe.')),
                                value: essential,
                                onChanged: (v) =>
                                    setDialogState(() => essential = v)),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              for (final swatch in [
                                ('#10B981', l.t('Green', 'Zöld')),
                                ('#3B82F6', l.t('Blue', 'Kék')),
                                ('#F59E0B', l.t('Amber', 'Borostyán')),
                                ('#6366F1', l.t('Indigo', 'Indigó')),
                                ('#EF4444', l.t('Red', 'Piros')),
                                ('#EC4899', l.t('Pink', 'Rózsaszín'))
                              ])
                                ChoiceChip(
                                    label: Text(swatch.$2),
                                    selected: color == swatch.$1,
                                    avatar: CircleAvatar(
                                        backgroundColor: Color(int.parse(
                                            'FF${swatch.$1.substring(1)}',
                                            radix: 16))),
                                    onSelected: (_) => setDialogState(
                                        () => color = swatch.$1)),
                            ]),
                          ])),
                  actions: [
                    TextButton(
                        onPressed: () => close(ctx),
                        child: Text(l.t('Cancel', 'Mégse'))),
                    FilledButton(
                        onPressed: () {
                          if (!form.currentState!.validate()) return;
                          final localized = name.text.trim();
                          final other = translation.text.trim().isEmpty
                              ? localized
                              : translation.text.trim();
                          db.upsertCategory(Category(
                              id: existing?.id ?? const Uuid().v4(),
                              householdId: existing?.householdId ??
                                  db.household?.id ??
                                  'hh-default-001',
                              nameEn: l.isHu ? other : localized,
                              nameHu: l.isHu ? localized : other,
                              kind: existing?.kind ?? _kind,
                              icon: existing?.icon ?? 'category',
                              color: color,
                              isEssential: essential,
                              parentId: existing?.parentId,
                              sortOrder:
                                  existing?.sortOrder ?? db.categories.length,
                              updatedAt: DateTime.now(),
                              deletedAt: existing?.deletedAt));
                          Navigator.of(ctx).pop();
                        },
                        child: Text(l.t('Save', 'Mentés')))
                  ],
                ),
              )),
    );
    // The dialog exit transition may still use the field controllers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    translation.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final l = AppLocalizations.of(context);
    final retired = db.retiredCategories.where((e) => e.kind == _kind).toList();
    final cats = _showRetired
        ? retired
        : db.categories.where((e) => e.kind == _kind).toList();
    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => AppShell.goBackOrHome(context)),
          title: Text(l.t('Categories', 'Kategóriák'))),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Wrap(spacing: 8, children: [
              for (final kind in ['expense', 'income'])
                ChoiceChip(
                    label: Text(kind == 'expense' ? l.expense : l.income),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind))
            ]),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    l.t('Show retired categories', 'Archivált kategóriák')),
                value: _showRetired,
                onChanged: (v) => setState(() => _showRetired = v)),
            if (cats.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_showRetired
                      ? l.t('No retired categories.',
                          'Nincs archivált kategória.')
                      : l.t('Add a category to organize your spending.',
                          'Adj hozzá kategóriát a kiadások rendszerezéséhez.'))),
            for (var i = 0; i < cats.length; i++)
              Card(
                  child: ListTile(
                leading: const Icon(Icons.category_outlined),
                title: Text(cats[i].localizedName(l.locale.languageCode)),
                subtitle: Text(_showRetired
                    ? l.t('Retired · kept in past transactions',
                        'Archivált · a korábbi tételeken megmarad')
                    : cats[i].isEssential
                        ? l.t('Essential expense', 'Alapvető kiadás')
                        : l.t('Optional expense', 'Nem alapvető kiadás')),
                onTap: _showRetired ? null : () => _edit(db, existing: cats[i]),
                trailing: PopupMenuButton<String>(
                    tooltip: l.t('Category actions', 'Kategóriaműveletek'),
                    onSelected: (action) {
                      final c = cats[i];
                      if (action == 'retire' || action == 'restore') {
                        db.upsertCategory(_updated(c, {
                          'deleted_at': action == 'retire'
                              ? DateTime.now().toIso8601String()
                              : null
                        }));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(action == 'retire'
                                ? l.t(
                                    'Category retired. Past entries are kept.',
                                    'Kategória archiválva. A korábbi tételek megmaradnak.')
                                : l.t('Category restored.',
                                    'Kategória visszaállítva.'))));
                      } else {
                        final j = action == 'up' ? i - 1 : i + 1;
                        if (j < 0 || j >= cats.length) return;
                        final ordered = [...cats];
                        final moved = ordered.removeAt(i);
                        ordered.insert(j, moved);
                        for (var rank = 0; rank < ordered.length; rank++) {
                          db.upsertCategory(
                              _updated(ordered[rank], {'sort_order': rank}));
                        }
                      }
                    },
                    itemBuilder: (_) => [
                          if (!_showRetired && i > 0)
                            PopupMenuItem(
                                value: 'up',
                                child: Text(l.t('Move up', 'Mozgatás fel'))),
                          if (!_showRetired && i < cats.length - 1)
                            PopupMenuItem(
                                value: 'down',
                                child: Text(l.t('Move down', 'Mozgatás le'))),
                          PopupMenuItem(
                              value: _showRetired ? 'restore' : 'retire',
                              child: Text(_showRetired
                                  ? l.t('Restore category', 'Visszaállítás')
                                  : l.t('Retire category', 'Archiválás'))),
                        ]),
              )),
          ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(db),
          icon: const Icon(Icons.add),
          label: Text(l.t('Add category', 'Új kategória'))),
    );
  }
}
