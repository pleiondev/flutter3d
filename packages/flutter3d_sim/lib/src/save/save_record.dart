/// A saved run as a document: which level, the snapshot, and the two numbers
/// that let two copies of it be compared.
///
/// ## Why the step and the digest travel with it
///
/// A save that lives in two places — a phone and a tablet, a machine and a
/// server — sooner or later differs between them, and the question is which
/// one the player wants. A wall clock cannot answer it: two devices disagree
/// about the time, and the newer file is not the further run when somebody
/// replayed an old checkpoint. Two things can. The **step** says how far the
/// run has got, in simulation steps across its levels; the **digest** says
/// whether two copies are the same run at all, without comparing them field
/// by field. Equal digests are one save in two places. Different digests are
/// two runs, and the further one is what a player who kept playing wants.
///
/// The digest is [contentDigestHex] — the same bits-not-text hash a replay
/// checks itself with, so a phone and a browser agree on it.
library;

import 'save_schema.dart';
import 'snapshot.dart';
import 'state_digest.dart' show contentDigestHex;

final class SaveRecord {
  SaveRecord({
    required this.level,
    required this.run,
    this.step = 0,
    this.schema = 0,
  });

  /// The level the snapshot belongs to — see `SaveFile` for why the two are
  /// never kept apart.
  final String level;

  final Snapshot run;

  /// How far the run has got, in simulation steps across all its levels.
  ///
  /// Zero for a game that does not count them, which leaves a conflict
  /// between two different runs to the player — see [resolveSaves].
  final int step;

  /// The game's [SaveSchema.version] the run's fields are at.
  final int schema;

  /// Whether two records are the same run, as eight hexadecimal digits.
  ///
  /// Of the level and the run and nothing else: the step counts how the run
  /// got here, and two copies of one save that disagree about it are still
  /// one save.
  late final String digest = contentDigestHex(<String, Object?>{
    'level': level,
    'run': run.toJson(),
  });

  /// The document. The digest is written down for whoever stores it — a
  /// server can show and compare it without understanding a snapshot — and
  /// recomputed on the way back in rather than trusted.
  Map<String, Object?> toJson() => <String, Object?>{
    'level': level,
    'schema': schema,
    'step': step,
    'digest': digest,
    'run': run.toJson(),
  };

  /// Reads a document written by [toJson], or by a build from before it
  /// carried a schema, and brings the run up to [schema].
  ///
  /// **Never throws.** Every way a document can fail to be a save is a
  /// [SaveNotRead] that says which.
  static SaveRead read(Object? json, SaveSchema schema) {
    if (json is! Map<String, Object?>) {
      return const SaveNotRead('the document is not an object');
    }
    final level = json['level'];
    final run = json['run'];
    if (level is! String || run is! Map<String, Object?>) {
      return const SaveNotRead('no level and run in it');
    }
    // A run with no version in it was written by a build that had the version
    // and did not send it — `SaveFile.write` once handed over `run.data`,
    // which is the payload without the header `toJson` adds. The shape did not
    // change, so it is a version 1 document that failed to say so, and
    // refusing it would cost a player a run to fix a bug that was never
    // theirs.
    final envelope = run[Snapshot.versionKey];
    if (envelope is num && envelope > Snapshot.formatVersion) {
      return SaveNotRead(
        'snapshot format version $envelope is newer than this build '
        'understands (${Snapshot.formatVersion})',
        newer: true,
      );
    }
    final Snapshot snapshot;
    try {
      snapshot = Snapshot.fromJson(
        envelope == null
            ? <String, Object?>{
                Snapshot.versionKey: Snapshot.formatVersion,
                ...run,
              }
            : run,
      );
    } on SnapshotFormatException catch (error) {
      return SaveNotRead(error.message);
    }
    final written = switch (json['schema']) {
      final num value => value.toInt(),
      // A save from before games had a schema: the first one.
      _ => 0,
    };
    return switch (schema.upgrade(snapshot.data, written)) {
      SaveUpgraded(:final run, :final from) => SaveFound(
        SaveRecord(
          level: level,
          run: Snapshot(run),
          step: switch (json['step']) {
            final num value => value.toInt(),
            _ => 0,
          },
          schema: schema.version,
        ),
        upgradedFrom: from,
      ),
      SaveRefused(:final reason, :final newer) => SaveNotRead(
        reason,
        newer: newer,
      ),
    };
  }
}

/// What [SaveRecord.read] made of a document.
sealed class SaveRead {
  const SaveRead();
}

final class SaveFound extends SaveRead {
  const SaveFound(this.record, {required this.upgradedFrom});

  final SaveRecord record;

  /// The schema the document was written at. Less than `record.schema` when
  /// it was migrated on the way in.
  final int upgradedFrom;
}

final class SaveNotRead extends SaveRead {
  const SaveNotRead(this.reason, {this.newer = false});

  final String reason;

  /// From a newer build: somebody's real progress, to be left alone rather
  /// than overwritten. See [SaveRefused.newer].
  final bool newer;
}

/// Which of two copies of a save to keep.
enum SaveResolution {
  /// They are the same run, or there is neither.
  inSync,

  /// The local copy is the one to keep, and to send.
  keepLocal,

  /// The other copy is the one to keep, and to write here.
  takeRemote,

  /// Two different runs equally far along. Only the player can say.
  ask,
}

/// Decides between [local] and [remote], given the digest both sides last
/// agreed on, [base], when there was one.
///
/// **The base is what makes this more than "the further one wins".** When one
/// copy is still the base, only the other has moved since the two last met,
/// and it wins whatever its step: a player who went back to an earlier
/// checkpoint on the tablet meant to. Only when both moved — two devices
/// played apart — is the step asked, and a tie between two different runs
/// goes to the player, because either answer picked here throws away
/// somebody's evening.
SaveResolution resolveSaves({
  required SaveRecord? local,
  required SaveRecord? remote,
  String? base,
}) => switch ((local, remote)) {
  (null, null) => SaveResolution.inSync,
  (_?, null) => SaveResolution.keepLocal,
  (null, _?) => SaveResolution.takeRemote,
  (final here?, final there?) when here.digest == there.digest =>
    SaveResolution.inSync,
  (final here?, _) when here.digest == base => SaveResolution.takeRemote,
  (_, final there?) when there.digest == base => SaveResolution.keepLocal,
  (final here?, final there?) when here.step > there.step =>
    SaveResolution.keepLocal,
  (final here?, final there?) when here.step < there.step =>
    SaveResolution.takeRemote,
  _ => SaveResolution.ask,
};
