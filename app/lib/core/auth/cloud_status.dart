import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/generated/app_localizations.dart';
import 'backend_session.dart';

class CloudStatusCard extends ConsumerWidget {
  const CloudStatusCard({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(backendSessionProvider);
    final l = AppLocalizations.of(context);
    final pending = session.db.pendingOutbox.length;
    final needsAttention = session.localSaveFailed || session.error != null;
    // Background polling is silent. Only unsaved work or a problem belongs on Home.
    if (compact && !needsAttention && pending == 0) {
      return const SizedBox.shrink();
    }
    final status = session.localSaveFailed
        ? l.t('Could not save on this device. Keep the app open and retry.',
            'Nem sikerült menteni az eszközön. Tartsd nyitva az alkalmazást és próbáld újra.')
        : session.error != null
            ? l.t(
                'Cloud connection needs attention. Changes are saved on this device.',
                'A felhőkapcsolat figyelmet igényel. A módosítások az eszközön mentve vannak.')
            : pending > 0
                ? l.t('$pending changes waiting to sync',
                    '$pending módosítás vár szinkronizálásra')
                : l.t('Cloud up to date', 'Felhő naprakész');
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(status,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: needsAttention
                      ? Theme.of(context).colorScheme.error
                      : null)),
          if (!compact) ...[
            Text(session.user?.email ?? ''),
            if (session.db.household?.inviteCode != null)
              TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: session.db.household!.inviteCode!));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(l.t(
                              'Invite code copied', 'Meghívókód másolva'))));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: Text(l.t('Copy partner invite code',
                      'Párom meghívókódjának másolása'))),
          ],
          Wrap(spacing: 8, children: [
            if (!compact || needsAttention)
              TextButton(
                  onPressed: session.syncing ? null : session.syncNow,
                  child: Text(l.t('Sync now', 'Szinkronizálás most'))),
            if (!compact)
              TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                                title: Text(l.t('Sign out?', 'Kijelentkezel?')),
                                content: Text(l.t(
                                    'Queued changes stay encrypted for your next sign-in. Financial data is hidden immediately after signing out.',
                                    'A sorban álló módosítások titkosítva megmaradnak a következő bejelentkezésedig. Kijelentkezés után a pénzügyi adatok azonnal eltűnnek.')),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(l.t('Cancel', 'Mégse'))),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(
                                          l.t('Sign out', 'Kijelentkezés')))
                                ]));
                    if (confirmed == true) await session.signOut();
                  },
                  child: Text(l.t('Sign out', 'Kijelentkezés'))),
          ]),
        ]));
  }
}
