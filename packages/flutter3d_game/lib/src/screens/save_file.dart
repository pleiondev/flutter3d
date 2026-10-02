import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart';
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
  }) : onIssue = onIssue ?? printIssue,
       storage = storage ?? defaultStorage(appName, onIssue: onIssue);

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

  /// Where this says what it could not read.
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

  /// The name the document is kept under — and the slot a cloud copy of it is
  /// kept in, so the two are the same thing in both places.
  static const String name = 'save.json';

  /// The digest of what was last written, so a second write of the same run
  /// costs nothing. Autosave writes on every pause, and most pauses are the
  /// same run as the last one.
  String? _written;

  /// The run that was saved, or null if there is nothing to resume.
  ///
  /// **Never throws**, on the same argument as [SettingsFile.read]: a save that
  /// cannot be read is a run that has to start again, and that is a much
  /// smaller loss than a game that will not launch.
  ({String level, Snapshot run})? read() => switch (readRecord()) {
    final record? => (level: record.level, run: record.run),
    null => null,
  };

  /// [read], with the step, the digest and the schema it was written at.
  SaveRecord? readRecord() {
    final text = storage.read(name);
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
  /// `SaveRecord.step` for what it settles.
  bool write(String level, Snapshot run, {int step = 0}) => writeRecord(
    SaveRecord(level: level, run: run, step: step, schema: schema.version),
  );

  /// Writes [record] as it is: a run from a cloud copy, kept here.
  ///
  /// The same run written twice in a row is written once. True either way —
  /// the save on disk is that run.
  bool writeRecord(SaveRecord record) {
    if (record.digest == _written) return true;
    final wrote = storage.write(name, encode(record));
    if (wrote) _written = record.digest;
    return wrote;
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
  void clear() {
    _written = null;
    storage.remove(name);
  }
}
