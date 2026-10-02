/// What a game's own save data looks like, by version, and how an old one
/// becomes a new one.
///
/// ## Two versions, and why
///
/// [Snapshot.formatVersion] is the engine's: it changes when the envelope does,
/// and no game can move it. A game's fields change far more often — a health
/// bar becomes a list of hearts, a key ring gains a colour — and until this
/// existed the only answer was the one `Snapshot` gives a newer document:
/// refuse it. An *older* document was read as if it were current, so a renamed
/// field came back as its default and the player lost what it held without a
/// word.
///
/// ## The version is the number of migrations
///
/// **There is no separate number to bump.** A schema with three migrations is
/// version 3, and the only way to make it 4 is to write the fourth. A number
/// kept beside the list could be raised without a migration, and the save from
/// the version in between would then be read as current — the failure this
/// exists to end. A change that needs no rewriting is a migration that returns
/// its argument, written down so the history is complete.
library;

import 'snapshot.dart' show Snapshot;

/// Turns a game's save data at one version into the next.
///
/// Given the run's fields — a copy, so a migration may change it in place and
/// return it — and returns the fields at the next version.
typedef SaveMigration = Map<String, Object?> Function(Map<String, Object?> run);

/// A game's save schema: the migrations from version 0 to now.
final class SaveSchema {
  const SaveSchema([this.migrations = const <SaveMigration>[]]);

  /// `migrations[n]` takes a version-`n` run to version `n + 1`.
  final List<SaveMigration> migrations;

  /// The version this build writes.
  int get version => migrations.length;

  /// Brings [run], written at version [from], up to [version].
  ///
  /// A refusal rather than a throw, in both cases that can go wrong: a save
  /// from a newer build cannot be read here and must not be overwritten
  /// either, and a migration that throws on somebody's real save is a bug
  /// whose report should name the step it failed at.
  SaveUpgrade upgrade(Map<String, Object?> run, int from) {
    if (from > version) {
      return SaveRefused(
        'save schema $from is newer than this build understands ($version)',
        newer: true,
      );
    }
    if (from < 0) return SaveRefused('save schema $from is not a version');
    try {
      final upgraded = migrations.skip(from).fold(<String, Object?>{
        ...run,
      }, (fields, step) => step({...fields}));
      return SaveUpgraded(upgraded, from: from);
    } catch (error) {
      return SaveRefused('a migration from save schema $from failed: $error');
    }
  }
}

/// What [SaveSchema.upgrade] made of a run.
sealed class SaveUpgrade {
  const SaveUpgrade();
}

/// The run at the current version, and the version it was written at.
final class SaveUpgraded extends SaveUpgrade {
  const SaveUpgraded(this.run, {required this.from});

  final Map<String, Object?> run;
  final int from;
}

/// Why the run cannot be read by this build.
final class SaveRefused extends SaveUpgrade {
  const SaveRefused(this.reason, {this.newer = false});

  /// A sentence, in the words a log line or a bug report wants.
  final String reason;

  /// Whether the document is from a newer build — and so is somebody's real
  /// progress that this build must leave alone rather than replace.
  final bool newer;
}
