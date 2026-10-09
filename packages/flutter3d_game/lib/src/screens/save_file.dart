import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show SaveFound, SaveNotRead, SaveRecord, SaveSchema, Snapshot;

import 'settings_file.dart';

/// Where a run in progress is kept between launches.
///
/// The same shape as [SettingsFile] and for the same reason — the right
/// directory is per-application — but a separate file on purpose: settings are
/// what a player chose and a save is where they got to, and one of those must
/// survive a delete of the other. Wiping a corrupt save should not cost
/// somebody their key bindings.
///
/// **A save is a level and a snapshot together.** A snapshot restored into the
/// wrong level is worse than no save at all: the positions are real numbers
/// that mean nothing here, so the runner arrives inside a wall of a level they
/// were never in. So the level's asset path is stored beside it and checked on
/// the way back in.
/// **Moved here when the second game wanted one**, which is this repository's
/// habit rather than a new rule. Nothing in it was ever the platformer's: a
/// level's path and a `Snapshot` are what any game that can be quit halfway
/// through has to keep, and the only thing that differed was the name of the
/// directory — which is what [appName] is.
///
/// The document is a [SaveRecord]: the step and the digest ride along so a
/// copy kept elsewhere — see `SaveSync` — can be compared with this one, and
/// the game's [schema] version so a later build can migrate it.
final class SaveFile {
  SaveFile({
    required this.appName,
    Storage? storage,
    IssueSink? onIssue,
    this.schema = const SaveSchema(),
    this.slot = defaultSlot,
  }) : onIssue = onIssue ?? printIssue,
       storage = storage ?? defaultStorage(appName, onIssue: onIssue),
       _slots = null;

  SaveFile._inSlots(SaveSlots slots, this.slot)
    : appName = slots.appName,
      storage = slots.storage,
      onIssue = slots.onIssue,
      schema = slots.schema,
      _slots = slots;

  /// Which game's save this is. Two games served from one browser origin would
  /// otherwise resume into each other's levels — see [SettingsFile.appName],
  /// which had the same problem and the same answer.
  final String appName;

  /// Where the document is kept, which differs per platform — see [Storage].
  ///
  /// **The web build and the Android build kept nothing**, and both looked
  /// fine: the old file-backed path threw where there was no filesystem and
  /// wrote where nothing was reading, and both throws were swallowed into "no
  /// save". A checkpoint that is not written is indistinguishable from a player
  /// who has not reached one.
  final Storage storage;

  /// Where this says what it could not read or write.
  ///
  /// **The one that costs a player something.** A save that will not parse is
  /// where they got to, and swallowing it turns "your progress could not be
  /// read" into "you have no progress" — the same screen a new player sees, so
  /// nobody can tell the two apart, least of all the person it happened to.
  final IssueSink onIssue;

  /// The game's own save fields, by version, and the migrations between them.
  ///
  /// Empty by default, which is version 0 — what every save written before
  /// games had a schema is read as.
  final SaveSchema schema;

  /// Which of a game's saves this is — see [SaveSlots]. [defaultSlot] for a
  /// game with one, which is every game written before there were slots.
  final String slot;

  final SaveSlots? _slots;

  /// The slot a game with one save uses, kept under [name] as it always was.
  static const String defaultSlot = 'main';

  /// The name [defaultSlot]'s document is kept under — and the slot a cloud
  /// copy of it is kept in, so the two are the same thing in both places.
  static const String name = 'save.json';

  /// The name [slot]'s document is kept under: [name] for [defaultSlot], so
  /// a save written before there were slots is the default slot's, and
  /// `save.<slot>.json` for any other.
  static String documentNameOf(String slot) =>
      slot == defaultSlot ? name : 'save.$slot.json';

  /// The name this slot's document is kept under, here and in a cloud store.
  String get documentName => documentNameOf(slot);

  /// The digest of what was last written, so a second write of the same run
  /// costs nothing. Autosave writes on every pause, and most pauses are the
  /// same run as the last one.
  String? _written;

  /// The run that was saved — its [SaveRecord.level] and [SaveRecord.run],
  /// with the step and digest beside them — or null if there is nothing to
  /// resume.
  ///
  /// A class rather than a record, so a later release can say more about a
  /// save without changing this signature; it is [readRecord].
  ///
  /// **Never throws**, on the same argument as [SettingsFile.read]: a save that
  /// cannot be read is a run that has to start again, and that is a much
  /// smaller loss than a game that will not launch.
  Future<SaveRecord?> read() => readRecord();

  /// [read], with the step, the digest and the schema it was written at.
  Future<SaveRecord?> readRecord() async {
    final text = await storage.read(documentName);
    return text == null ? null : parse(text);
  }

  /// Reads a save document from wherever it came from — this device's storage
  /// or a cloud copy — migrating it to [schema] on the way.
  ///
  /// Null, with an issue said, when it is not a save this build can use.
  SaveRecord? parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (error) {
      onIssue(Issue('save: could not be read, starting fresh ($error)'));
      return null;
    }
    switch (SaveRecord.read(json, schema)) {
      case SaveFound(:final record):
        return record;
      case SaveNotRead(:final reason):
        // A save from a *newer* build is the case the versions exist for:
        // "starting fresh" without a word would silently discard a run the
        // player can still open by going back to the build that wrote it.
        onIssue(Issue('save: $reason, starting fresh'));
        return null;
    }
  }

  /// Writes the run, and says whether it managed to.
  ///
  /// [step] is how far the run has got across its levels — see
  /// `SaveRecord.step` for what it settles. The run is read now, when this is
  /// called; only the write waits.
  Future<bool> write(String level, Snapshot run, {int step = 0}) => writeRecord(
    SaveRecord(level: level, run: run, step: step, schema: schema.version),
  );

  /// Writes [record] as it is: a run from a cloud copy, kept here.
  ///
  /// The same run written twice in a row is written once. True either way —
  /// the save on disk is that run. A write the platform refused is said
  /// through [onIssue] and answered false.
  Future<bool> writeRecord(SaveRecord record) async {
    if (record.digest == _written) return true;
    try {
      await storage.write(documentName, encode(record));
    } on StorageException catch (error) {
      onIssue(Issue('save: could not be written (${error.message})'));
      return false;
    }
    _written = record.digest;
    await _slots?._touched(slot);
    return true;
  }

  /// The document [writeRecord] keeps, for a caller that keeps it elsewhere.
  ///
  /// Through `Snapshot.toJson` rather than around it: the version is added
  /// there, and a document written from `run.data` carries the payload with no
  /// header — which is what once made every refusal of a newer save
  /// unreachable.
  static String encode(SaveRecord record) =>
      const JsonEncoder.withIndent('  ').convert(record.toJson());

  /// Forgets the run. Called when it ends, either way.
  ///
  /// A finished run left behind is resumed on the next launch, and the player is
  /// put back on the last checkpoint of a level they already beat.
  Future<void> clear() async {
    _written = null;
    await storage.remove(documentName);
    await _slots?._forgot(slot);
  }
}

/// A game's saves, one per slot: three runs on a title screen, an autosave
/// beside a manual save, a profile per player on one device.
///
/// **Each slot is a [SaveFile]**, which is what a run is written through
/// already: [slot] hands out the one for an id, and a game that had one save
/// keeps it as [SaveFile.defaultSlot], under the name it always had. Which
/// slots hold a run is kept in a small index document of its own, because a
/// [Storage] has names and no listing.
final class SaveSlots {
  SaveSlots({
    required this.appName,
    Storage? storage,
    IssueSink? onIssue,
    this.schema = const SaveSchema(),
  }) : onIssue = onIssue ?? printIssue,
       storage = storage ?? defaultStorage(appName, onIssue: onIssue);

  /// Which game's saves these are. See [SaveFile.appName].
  final String appName;

  /// Where every slot and the index are kept.
  final Storage storage;

  /// Where a slot says what it could not read or write.
  final IssueSink onIssue;

  /// The schema every slot is read and written at.
  final SaveSchema schema;

  /// The document the index of slots is kept in.
  static const String indexName = 'saves.json';

  /// The version of the index document [indexFormat] describes.
  static const int indexVersion = 1;

  /// The index of slots in the format envelope: `f3d.saveSlots`, then
  /// `slots`, the ids in the order they were first written.
  ///
  /// The index from before the envelope, `{"version": 1, "slots": [...]}`,
  /// reads as version 1. Keys a later build added are kept when the index is
  /// written again; an index from a newer build is read for its ids and
  /// never written over.
  static const FormatSpec indexFormat = FormatSpec(
    id: 'f3d.saveSlots',
    version: indexVersion,
    fixture: 'test/fixtures/v<N>/saves.json',
  );

  final Map<String, SaveFile> _files = <String, SaveFile>{};

  /// The save in slot [id], one object per id.
  ///
  /// An id is part of a document name, so it is letters, digits, `-` and `_`.
  SaveFile slot(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'a slot id is letters, digits, - and _',
      );
    }
    return _files.putIfAbsent(id, () => SaveFile._inSlots(this, id));
  }

  /// The ids of every slot holding a run, in the order they were first
  /// written. The default slot is among them when its document is there,
  /// even if it was written before there were slots.
  Future<List<String>> ids() async {
    final (:listed, unknown: _, writable: _) = await _index();
    if (!listed.contains(SaveFile.defaultSlot) &&
        await storage.read(SaveFile.name) != null) {
      return <String>[SaveFile.defaultSlot, ...listed];
    }
    return listed;
  }

  /// Forgets the run in slot [id].
  Future<void> delete(String id) => slot(id).clear();

  /// The index's ids, the keys this build did not read, and whether it may
  /// be written over: not when a newer build wrote it.
  Future<({List<String> listed, Map<String, Object?> unknown, bool writable})>
  _index() async {
    const empty = (
      listed: <String>[],
      unknown: <String, Object?>{},
      writable: true,
    );
    final text = await storage.read(indexName);
    if (text == null) return empty;
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      onIssue(Issue('saves: the index could not be read (${error.message})'));
      return empty;
    }
    if (json is! Map<String, Object?>) {
      onIssue(Issue('saves: the index is not a JSON object'));
      return empty;
    }
    final Map<String, Object?> opened;
    try {
      opened = indexFormat.open(json, refuse: DocumentFormatException.new);
    } on DocumentFormatException catch (error) {
      // A newer build's index: its ids are still the slots on this device,
      // so they are listed, and it is left as it is for that build.
      onIssue(Issue('saves: ${error.message}; the index is left as it is'));
      return (
        listed: _slotsIn(json),
        unknown: const <String, Object?>{},
        writable: false,
      );
    }
    return (
      listed: _slotsIn(opened),
      unknown: FormatDocument.unknownIn(
        opened,
        known: const <String>{'slots'},
        spec: indexFormat,
      ),
      writable: true,
    );
  }

  static List<String> _slotsIn(Map<String, Object?> json) => switch (json) {
    {'slots': final List<Object?> slots} => <String>[
      for (final id in slots)
        if (id is String) id,
    ],
    _ => <String>[],
  };

  Future<void> _touched(String id) async {
    final index = await _index();
    if (index.listed.contains(id)) return;
    await _keep(<String>[...index.listed, id], index);
  }

  Future<void> _forgot(String id) async {
    final index = await _index();
    if (!index.listed.contains(id)) return;
    await _keep(<String>[
      for (final kept in index.listed)
        if (kept != id) kept,
    ], index);
  }

  Future<void> _keep(
    List<String> ids,
    ({List<String> listed, Map<String, Object?> unknown, bool writable}) read,
  ) async {
    if (!read.writable) return;
    try {
      await storage.write(
        indexName,
        jsonEncode(<String, Object?>{
          ...indexFormat.envelope(),
          'slots': ids,
          for (final MapEntry(:key, :value) in read.unknown.entries) key: value,
        }),
      );
    } on StorageException catch (error) {
      onIssue(
        Issue('saves: the index could not be written (${error.message})'),
      );
    }
  }
}
