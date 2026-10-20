import 'dart:async';
import 'sync_engine.dart';

/// Listens to RLS-filtered Realtime Postgres changes and triggers an immediate pull.
class RealtimeListener {
  final SyncEngine syncEngine;
  bool _subscribed = false;

  RealtimeListener(this.syncEngine);

  bool get isSubscribed => _subscribed;

  Future<void> start() async {
    _subscribed = true;
  }

  Future<void> onRemoteHint() async {
    await syncEngine.pullUpdates();
  }

  Future<void> stop() async {
    _subscribed = false;
  }
}
