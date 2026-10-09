import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        SaveFound,
        SaveNotRead,
        SaveRead,
        SaveRecord,
        SaveResolution,
        resolveSaves;

import '../screens/save_file.dart';
import 'cloud_save_store.dart';

/// How a sync ended.
///
/// **Constants rather than an enum**, so a later outcome — a player signed
/// out, a quota reached — is an addition and not a break in every game's
/// `switch`. Compare with `==`; [SyncReport.message] is the sentence.
final class SyncOutcome {
  const SyncOutcome._(this.name);

  final String name;

  /// The player has not agreed to cloud saves. Nothing was sent or asked.
  static const SyncOutcome notConsented = SyncOutcome._('notConsented');

  /// Both copies are the same run, or there is none.
  static const SyncOutcome inSync = SyncOutcome._('inSync');

  /// This device's run was sent.
  static const SyncOutcome uploaded = SyncOutcome._('uploaded');

  /// The cloud's run was written here. A run already loaded is stale now.
  static const SyncOutcome downloaded = SyncOutcome._('downloaded');

  /// Two different runs equally far along. Settle with [SaveSync.settle].
  static const SyncOutcome ask = SyncOutcome._('ask');

  /// The cloud copy is not one this build can use, and was left alone.
  static const SyncOutcome refused = SyncOutcome._('refused');

  /// The store could not be reached, or would not do it.
  static const SyncOutcome unavailable = SyncOutcome._('unavailable');

  @override
  String toString() => 'SyncOutcome.$name';
}

/// What [SaveSync.sync] did, in a sentence, and for [SyncOutcome.ask] the two
/// runs to choose between.
final class SyncReport {
  const SyncReport(
    this.outcome,
    this.message, {
    this.local,
    this.remote,
    this.remoteVersion,
  });

  final SyncOutcome outcome;
  final String message;

  final SaveRecord? local;
  final SaveRecord? remote;

  /// The version of [remote] in the store, which a settling write replaces.
  final String? remoteVersion;
}

/// The save on this device and a copy of it in a [CloudSaveStore], made one.
///
/// ## Consent first
///
/// **Nothing leaves the device until the player says it may.** [hasConsent] is
/// false on a fresh install, kept in a document of its own beside the save,
/// and every call below that would touch the store checks it first and
/// answers [SyncOutcome.notConsented] without a request. Withdrawing forgets
/// what the two sides last agreed on as well, so turning it back on later is
/// a first sync again rather than a resolution against a stale base.
///
/// ## When to call it
///
/// Before `RunSession.begin`, and after `Autosave` wrote at a pause or in the
/// background. A run that is already loaded keeps playing from memory, so a
/// download under it is overwritten by its next autosave — which is why
/// [SyncOutcome.downloaded] says the run is stale and the game should begin
/// again from the save.
///
/// ## Which copy wins
///
/// `resolveSaves`, by step and digest against the digest the two last agreed
/// on. Recorded after every sync that ended with both sides holding one run.
final class SaveSync {
  /// Cloud copies of [saves] in [store], with consent and the last agreed
  /// digest kept in [storage] — read straight away, see [ready].
  SaveSync({required this.saves, required this.store, Storage? storage})
    : storage = storage ?? saves.storage {
    _ready = _load();
  }

  final SaveFile saves;
  final CloudSaveStore store;

  /// Where consent and the last agreed digest are kept.
  final Storage storage;

  /// The document consent is kept in. Separate from the save so clearing a
  /// finished run does not quietly turn cloud saves off, and from the
  /// settings so a reset of the controls does not quietly turn them on.
  static const String stateName = 'cloud_saves.json';

  /// The version of [stateName]'s document.
  static const int stateVersion = 1;

  /// [stateName]'s document: `f3d.cloudSaves`, then `consented` and `base`,
  /// and whatever a later build added, kept when this one writes it again.
  /// A document from before the envelope reads as version 1; one from a
  /// newer build, or one that does not read, is no consent and no base.
  static const FormatSpec stateFormat = FormatSpec(
    id: 'f3d.cloudSaves',
    version: stateVersion,
    fixture: 'test/fixtures/v<N>/cloud_saves.json',
  );

  late final Future<void> _ready;

  /// Completes once consent and the agreed digest have been read. Until
  /// then [hasConsent] is false, which is the safe answer; [sync] waits for
  /// it itself.
  Future<void> get ready => _ready;

  Map<String, Object?> _state = const <String, Object?>{};

  Future<void> _load() async {
    final text = await storage.read(stateName);
    if (text == null) return;
    try {
      final json = jsonDecode(text);
      if (json is Map<String, Object?>) {
        _state = <String, Object?>{
          for (final MapEntry(:key, :value)
              in stateFormat
                  .open(json, refuse: DocumentFormatException.new)
                  .entries)
            if (!FormatSpec.envelopeKeys.contains(key)) key: value,
        };
      }
    } on FormatException {
      _state = const <String, Object?>{};
    } on DocumentFormatException {
      _state = const <String, Object?>{};
    }
  }

  Future<bool> _keep(Map<String, Object?> state) async {
    _state = state;
    try {
      await storage.write(
        stateName,
        jsonEncode(<String, Object?>{...stateFormat.envelope(), ...state}),
      );
      return true;
    } on StorageException {
      return false;
    }
  }

  /// Whether the player has agreed to keep saves in [store].
  ///
  /// Anything but an explicit `true` on disk is no — a document that will not
  /// read is not consent, and neither is one not read yet.
  bool get hasConsent => _state['consented'] == true;

  /// The player agreed. Answers whether that was kept.
  Future<bool> consent() async {
    await _ready;
    return _keep(<String, Object?>{..._state, 'consented': true});
  }

  /// The player took it back. Answers whether that was kept.
  Future<bool> withdraw() async {
    await _ready;
    return _keep(const <String, Object?>{'consented': false});
  }

  /// The digest both sides last held, if they have met.
  String? get base => switch (_state['base']) {
    final String digest => digest,
    _ => null,
  };

  Future<void> _agreed(String? digest) =>
      _keep(<String, Object?>{..._state, 'base': digest});

  static const SyncReport _notConsented = SyncReport(
    SyncOutcome.notConsented,
    'cloud saves are off, so nothing was sent',
  );

  /// Compares the two copies and moves whichever one should move.
  Future<SyncReport> sync() => _sync(retried: false);

  Future<SyncReport> _sync({required bool retried}) async {
    await _ready;
    if (!hasConsent) return _notConsented;
    final SaveRecord? remote;
    final String? version;
    switch (await store.fetch(saves.documentName)) {
      case CloudUnavailable(:final reason):
        return SyncReport(SyncOutcome.unavailable, reason);
      case CloudEmpty():
        (remote, version) = (null, null);
      case CloudDocument(:final document, version: final stored):
        switch (_read(document)) {
          case SaveFound(:final record):
            (remote, version) = (record, stored);
          case SaveNotRead(:final reason, :final newer):
            return SyncReport(
              SyncOutcome.refused,
              newer
                  ? 'the save in ${store.name} is from a newer build of the '
                        'game ($reason); update to use it — it was left alone'
                  : 'the save in ${store.name} could not be read ($reason); '
                        'it was left alone',
            );
        }
    }
    final local = await saves.readRecord();
    switch (resolveSaves(local: local, remote: remote, base: base)) {
      case SaveResolution.inSync:
        await _agreed(local?.digest);
        return SyncReport(
          SyncOutcome.inSync,
          'the save here and in ${store.name} are the same',
        );
      case SaveResolution.keepLocal:
        return switch (await _send(local!, replacing: version)) {
          // Another device wrote between the fetch and the write. Once more
          // from the top, against what it wrote; twice in a row is a device
          // that is syncing in a loop, and that is said rather than chased.
          null when !retried => _sync(retried: true),
          null => _movedReport,
          final sent => sent,
        };
      case SaveResolution.takeRemote:
        return _take(remote!);
      case SaveResolution.ask:
        return SyncReport(
          SyncOutcome.ask,
          'this device and ${store.name} hold two different runs, equally '
          'far along',
          local: local,
          remote: remote,
          remoteVersion: version,
        );
    }
  }

  /// Finishes an [SyncOutcome.ask] with the player's choice: [keepLocal]
  /// sends this device's run, otherwise the cloud's is written here.
  Future<SyncReport> settle(SyncReport asked, {required bool keepLocal}) async {
    await _ready;
    if (!hasConsent) return _notConsented;
    final local = asked.local;
    final remote = asked.remote;
    if (asked.outcome != SyncOutcome.ask || local == null || remote == null) {
      return const SyncReport(
        SyncOutcome.refused,
        'there was no choice to settle; sync again',
      );
    }
    return keepLocal
        ? await _send(local, replacing: asked.remoteVersion) ?? _movedReport
        : await _take(remote);
  }

  SyncReport get _movedReport => SyncReport(
    SyncOutcome.unavailable,
    '${store.name} changed while this was syncing; try again',
  );

  /// Sends [local]; null when another device wrote first.
  Future<SyncReport?> _send(SaveRecord local, {String? replacing}) async {
    switch (await store.put(
      saves.documentName,
      SaveFile.encode(local),
      replacing: replacing,
    )) {
      case CloudStored():
        await _agreed(local.digest);
        return SyncReport(
          SyncOutcome.uploaded,
          'this run was saved to ${store.name}',
        );
      case CloudMoved():
        return null;
      case CloudUnavailable(:final reason):
        return SyncReport(SyncOutcome.unavailable, reason);
    }
  }

  Future<SyncReport> _take(SaveRecord remote) async {
    if (!await saves.writeRecord(remote)) {
      return SyncReport(
        SyncOutcome.unavailable,
        'the run from ${store.name} could not be written on this device',
      );
    }
    await _agreed(remote.digest);
    return SyncReport(
      SyncOutcome.downloaded,
      'the run from ${store.name} was kept on this device',
    );
  }

  SaveRead _read(String document) {
    try {
      return SaveRecord.read(jsonDecode(document), saves.schema);
    } on FormatException catch (error) {
      return SaveNotRead(error.message);
    }
  }
}
