import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart'
    show Issue, IssueSink, Snapshot, SnapshotFormatException, printIssue;

import 'settings_file.dart';
import 'storage/storage.dart';

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
final class SaveFile {
  SaveFile({required this.appName, Storage? storage, IssueSink? onIssue})
    : onIssue = onIssue ?? printIssue,
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

  /// A separate document from the settings on purpose: settings are what a
  /// player chose and a save is where they got to, and one of those must survive
  /// a delete of the other. Wiping a corrupt save should not cost the bindings.
  static const String _name = 'save.json';

  /// The run that was saved, or null if there is nothing to resume.
  ///
  /// **Never throws**, on the same argument as [SettingsFile.read]: a save that
  /// cannot be read is a run that has to start again, and that is a much
  /// smaller loss than a game that will not launch.
  ({String level, Snapshot run})? read() {
    final text = storage.read(_name);
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      // **These three said nothing at all**, which is worse than the `catch`
      // below: a document that parses as JSON but is not a save — an empty
      // object, a half-written file, a save from a build that named its keys
      // differently — went back as "no save" without a word anywhere.
      if (json is! Map<String, Object?>) {
        onIssue(Issue('save: the document is not an object, starting fresh'));
        return null;
      }
      final level = json['level'];
      final run = json['run'];
      if (level is! String || run is! Map<String, Object?>) {
        onIssue(Issue('save: no level and run in it, starting fresh'));
        return null;
      }
      // A save with no version in it was written by a build that had the
      // version and did not send it — `write` used to hand over `run.data`,
      // which is the payload without the header `toJson` adds, so the key
      // never reached the disk and `Snapshot.fromJson` was never called on the
      // way back. That is every save this build can find. The shape did not
      // change, so it is a version 1 document that failed to say so, and
      // refusing it would cost a player a run to fix a bug that was never
      // theirs. Deletable once no save predates the fix.
      final versioned = run.containsKey('version')
          ? run
          : <String, Object?>{'version': Snapshot.formatVersion, ...run};
      return (level: level, run: Snapshot.fromJson(versioned));
    } on SnapshotFormatException catch (error) {
      // The case the version exists for, and it is worth its own arm: this is
      // a save from a *newer* build, and "starting fresh" would silently
      // discard a run the player can still open by going back to the build
      // that wrote it. Saying which is which is the whole point of refusing
      // rather than misreading.
      onIssue(Issue('save: ${error.message}, starting fresh'));
      return null;
    } catch (error) {
      onIssue(Issue('save: could not be read, starting fresh ($error)'));
      return null;
    }
  }

  /// Writes the run, and says whether it managed to.
  ///
  /// Through [Snapshot.toJson] rather than around it: the version is added
  /// there, and a document written from `run.data` carries the payload with no
  /// header, which is what made the refusal above unreachable.
  bool write(String level, Snapshot run) => storage.write(
    _name,
    const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, Object?>{'level': level, 'run': run.toJson()}),
  );

  /// Forgets the run. Called when it ends, either way.
  ///
  /// A finished run left behind is resumed on the next launch, and the player is
  /// put back on the last checkpoint of a level they already beat.
  void clear() => storage.remove(_name);
}
