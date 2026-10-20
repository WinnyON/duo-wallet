import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  String _selectedKind = 'expense';

  Color _parseHex(String hex) {
    final clean = hex.replaceAll('#', '');
    final val = int.tryParse('FF$clean', radix: 16) ?? 0xFF6366F1;
    return Color(val);
  }

  Future<void> _showCategoryDialog(
    BuildContext context,
    AppDatabase db, {
    Category? existing,
  }) async {
    final l10n = AppLocalizations.of(context);
    final enCtrl = TextEditingController(text: existing?.nameEn ?? '');
    final huCtrl = TextEditingController(text: existing?.nameHu ?? '');
    final orderCtrl = TextEditingController(
      text: (existing?.sortOrder ?? (db.categories.length + 1)).toString(),
    );
    var kind = existing?.kind ?? _selectedKind;
    var isEssential = existing?.isEssential ?? false;
    var color = existing?.color ?? '#6366F1';

    const colors = [
      '#10B981',
      '#3B82F6',
      '#F59E0B',
      '#6366F1',
      '#EF4444',
      '#EC4899',
      '#14B8A6',
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? l10n.t('New Category', 'Új kategória')
                : l10n.t('Edit Category', 'Kategória szerkesztése'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: enCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.t('English Name', 'Angol név (EN)'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: huCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.t('Hungarian Name', 'Magyar név (HU)'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: InputDecoration(
                    labelText: l10n.t('Kind', 'Típus'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'expense',
                      child: Text(l10n.expense),
                    ),
                    DropdownMenuItem(value: 'income', child: Text(l10n.income)),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => kind = v);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.t(
                      'Essential (Emergency Fund)',
                      'Alapvető kiadás (Vésztartalékhoz)',
                    ),
                  ),
                  value: isEssential,
                  onChanged: (v) => setDialogState(() => isEssential = v),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: colors.map((c) {
                    return ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: _parseHex(c)),
                      label: Text(c),
                      selected: color == c,
                      onSelected: (_) => setDialogState(() => color = c),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: orderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.t('Sort Order', 'Sorrend'),
                  ),
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
                final en = enCtrl.text.trim();
                final hu = huCtrl.text.trim();
                if (en.isEmpty && hu.isEmpty) return;
                final cat = Category(
                  id: existing?.id ?? const Uuid().v4(),
                  householdId: db.household?.id ?? 'hh-default-001',
                  nameEn: en.isEmpty ? hu : en,
                  nameHu: hu.isEmpty ? en : hu,
                  kind: kind,
                  color: color,
                  isEssential: isEssential,
                  sortOrder: int.tryParse(orderCtrl.text) ?? 0,
                  updatedAt: DateTime.now(),
                );
                db.upsertCategory(cat);
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.t('Save', 'Mentés')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);

    final cats = db.categories.where((c) => c.kind == _selectedKind).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('Categories', 'Kategóriák')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'expense', label: Text(l10n.expense)),
                ButtonSegment(value: 'income', label: Text(l10n.income)),
              ],
              selected: {_selectedKind},
              onSelectionChanged: (s) => setState(() => _selectedKind = s.first),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              itemCount: cats.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final c = cats[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _parseHex(c.color),
                    foregroundColor: Colors.white,
                    child: Text('${c.sortOrder}'),
                  ),
                  title: Text('${c.nameEn} / ${c.nameHu}'),
                  subtitle: Text(
                    c.isEssential
                        ? l10n.t(
                            'Essential • Included in Emergency Fund',
                            'Alapvető • Vésztartalék alapja',
                          )
                        : l10n.t('Optional / Discretionary', 'Nem alapvető'),
                  ),
                  trailing: Switch(
                    value: c.isEssential,
                    onChanged: (v) {
                      db.upsertCategory(
                        Category(
                          id: c.id,
                          householdId: c.householdId,
                          nameEn: c.nameEn,
                          nameHu: c.nameHu,
                          kind: c.kind,
                          icon: c.icon,
                          color: c.color,
                          isEssential: v,
                          parentId: c.parentId,
                          sortOrder: c.sortOrder,
                          updatedAt: DateTime.now(),
                        ),
                      );
                    },
                  ),
                  onTap: () => _showCategoryDialog(context, db, existing: c),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryDialog(context, db),
        icon: const Icon(Icons.add),
        label: Text(l10n.t('Add Category', 'Új kategória')),
      ),
    );
  }
}
