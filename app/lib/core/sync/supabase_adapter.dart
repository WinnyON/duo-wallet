import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sync_engine.dart';

/// Uses only the signed-in user's publishable client; RLS applies to every call.
class SupabaseSyncAdapter implements SnapshotSyncAdapter {
  SupabaseSyncAdapter(this.client);
  final SupabaseClient client;

  static Map<String, dynamic> toRemote(
      String table, Map<String, dynamic> source) {
    final row = Map<String, dynamic>.from(source);
    if (table == 'transactions') {
      row.remove('shares');
      row.remove('base_shares');
    }
    if (table == 'budgets' && row['scope'] == 'individual') {
      row['scope'] = 'personal';
    }
    if (table == 'recurring_rules') {
      row['next_due_date'] = row.remove('next_due_on');
      row['split_pct'] = row.remove('split_pct_creator');
      row['paid_by'] = row['created_by'];
    }
    if (table == 'goals') {
      row['target_minor'] = row.remove('target_amount_minor');
    }
    if (table == 'account_valuations') {
      row['updated_at'] = row.remove('created_at');
    }
    if (table == 'activity') {
      row['payload'] = {
        for (final key in [
          'summary_en',
          'summary_hu',
          'amount_minor',
          'currency'
        ])
          key: row.remove(key)
      };
    }
    return row;
  }

  static Map<String, dynamic> fromRemote(
      String table, Map<String, dynamic> source) {
    final row = Map<String, dynamic>.from(source);
    if (table == 'transactions') {
      final shares =
          (row.remove('transaction_shares') as List? ?? []).cast<Map>();
      row['shares'] = {for (final s in shares) s['user_id']: s['share_minor']};
      row['base_shares'] = {
        for (final s in shares) s['user_id']: s['share_base_minor']
      };
    }
    if (table == 'budgets' && row['scope'] == 'personal') {
      row['scope'] = 'individual';
    }
    if (table == 'recurring_rules') {
      row['next_due_on'] = row.remove('next_due_date');
      row['split_pct_creator'] = row.remove('split_pct');
      row['auto_create'] = row['auto_create'] == true && row['active'] != false;
    }
    if (table == 'goals') {
      row['target_amount_minor'] = row.remove('target_minor');
    }
    if (table == 'account_valuations') row['created_at'] = row['updated_at'];
    if (table == 'activity') {
      row.addAll(
          Map<String, dynamic>.from(row.remove('payload') as Map? ?? {}));
    }
    return row;
  }

  @override
  Future<void> upsertRows(String table, List<Map<String, dynamic>> rows) async {
    if (client.auth.currentUser == null) {
      throw const AuthException('Sign in required');
    }
    for (final source in rows) {
      final row = toRemote(table, source);
      if (table == 'transactions') {
        await client.rpc('duo_save_transaction', params: {
          'p_transaction': row,
          'p_shares': source['shares'] ?? {},
          'p_base_shares': source['base_shares'] ?? {}
        }).timeout(const Duration(seconds: 20));
      } else if (table == 'profiles') {
        const editable = [
          'display_name',
          'color',
          'locale',
          'monthly_common_contribution_minor',
          'avatar_type',
          'avatar_url'
        ];
        await client
            .from(table)
            .update({for (final k in editable) k: row[k]})
            .eq('id', client.auth.currentUser!.id)
            .select()
            .single()
            .timeout(const Duration(seconds: 20));
      } else if (table == 'households') {
        await client
            .from(table)
            .update({
              for (final k in [
                'name',
                'default_split_pct',
                'emergency_fund_months'
              ])
                k: row[k]
            })
            .eq('id', row['id'] as String)
            .select()
            .single()
            .timeout(const Duration(seconds: 20));
      } else if (table == 'settlement_postings') {
        await client
            .from(table)
            .upsert(row, onConflict: 'settlement_id,user_id')
            .select()
            .single()
            .timeout(const Duration(seconds: 20));
      } else {
        final id = row['id'] as String;
        final existing = await client
            .from(table)
            .select('id')
            .eq('id', id)
            .maybeSingle()
            .timeout(const Duration(seconds: 20));
        // An UPSERT runs INSERT actor guards even for a partner's existing row.
        final write = existing == null
            ? client.from(table).insert(row)
            : client.from(table).update(row).eq('id', id);
        await write.select().single().timeout(const Duration(seconds: 20));
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChangedRows(
      String table, DateTime? since) async {
    // Snapshot sync below is authoritative and includes tombstones; no cursor races.
    final rows = await client.from(table).select().limit(1000);
    return rows.map((row) => fromRemote(table, row)).toList();
  }

  @override
  Future<Map<String, dynamic>> fetchSnapshot() async {
    final raw = Map<String, dynamic>.from(await client
        .rpc('duo_snapshot')
        .timeout(const Duration(seconds: 20)) as Map);
    const names = {
      'profiles': 'profiles',
      'accounts': 'accounts',
      'categories': 'categories',
      'transactions': 'transactions',
      'budgets': 'budgets',
      'settlements': 'settlements',
      'settlement_postings': 'settlement_postings',
      'recurring_rules': 'recurring_rules',
      'account_valuations': 'valuations',
      'goals': 'goals',
      'activity': 'activities'
    };
    return {
      'schema_version': 1,
      'household': raw['household'],
      for (final entry in names.entries)
        entry.value: (raw[entry.key] as List? ?? [])
            .map((row) =>
                fromRemote(entry.key, Map<String, dynamic>.from(row as Map)))
            .toList()
    };
  }

  Future<void> uploadBackup(Map<String, dynamic> visibleData) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Sign in required');
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(visibleData)));
    await client.storage
        .from('backups')
        .uploadBinary('$uid/latest.json', bytes,
            fileOptions: const FileOptions(
                upsert: true, contentType: 'application/json'))
        .timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> downloadBackup() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Sign in required');
    final bytes = await client.storage
        .from('backups')
        .download('$uid/latest.json')
        .timeout(const Duration(seconds: 20));
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }
}
