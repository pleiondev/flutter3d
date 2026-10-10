/// The state of a running game, written down.
///
/// ## One mechanism, three uses
///
/// A save file, a network packet and the input to a determinism test are the
/// same thing: everything needed to carry on simulating, and nothing needed
/// only to draw. Keeping three of those right costs three times what keeping
/// one right costs, so there is one.
///
/// ## What is deliberately not here
///
/// **It is not a level loader.** A snapshot restores objects that already
/// exist — the same collision world, the same monsters, the same mechanisms —
/// which is what loading a save into the level it was taken in means, and what
/// a determinism check needs. Restoring into a freshly loaded level is the
/// caller's job: load the level, then apply the snapshot.
///
/// That boundary is what keeps this from having to name every collider: a
/// monster is the *n*th monster, a door is the door called `crypt_door`, and
/// neither needs an identity scheme invented for it.
///
/// ## Versioning
///
/// The same shape as the level format, and for the same reason: a document
/// from a newer build is refused with a sentence rather than misread. Adding a
/// field does not need a bump — an older reader ignores what it does not know,
/// and a newer reader treats a missing field as its default.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException, FormatMigration, FormatSpec;
import 'package:vector_math/vector_math.dart';

/// Thrown when a snapshot cannot be read at all.
final class SnapshotFormatException extends Flutter3dFormatException {
  const SnapshotFormatException(this.message);
  @override
  final String message;
  @override
  String toString() => 'SnapshotFormatException: $message';
}

final class Snapshot {
  const Snapshot(this.data);

  /// Bumped when an existing field changes meaning.
  static const int formatVersion = 1;

  /// What the game wrote, and only that.
  ///
  /// The version is not in here: [toJson] puts it on the way out and
  /// [fromJson] takes it off on the way back, so a system reading its own
  /// fields never sees a key it did not write. That symmetry is worth stating
  /// because it was not held for as long as nothing called [fromJson] — the
  /// header would otherwise arrive inside the payload and every restore would
  /// carry a field belonging to the envelope.
  final Map<String, Object?> data;

  /// The name the version is written under, which is therefore a name a game
  /// cannot use for a field of its own. The envelope's other keys —
  /// `format`, `requires`, `generator` ([FormatSpec.envelopeKeys]) — are
  /// reserved the same way.
  static const String versionKey = 'version';

  /// The save format in the registry: `f3d.save`.
  ///
  /// **The envelope is additive at version 1.** A build from before it reads
  /// `format`, `requires` and `generator` as three fields no system asked
  /// for, and ignores them, so the version did not move.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.save',
    version: formatVersion,
    suffixes: <String>['.save.json'],
    fixture: 'test/fixtures/v<N>/save.json',
    migrations: _migrations,
  );

  /// The envelope, then [data] beside it.
  ///
  /// **Beside it rather than under a key of its own**, because every save's
  /// digest and every recorded run's checkpoints are taken over this map: a
  /// nested shape would be version 2 and move every digest a released run
  /// was recorded with. What nesting would have prevented — a field of the
  /// game's overwriting `version` or `format` — is refused here instead:
  /// [data] holding an envelope key throws an [ArgumentError] naming it,
  /// a mistake in the game's snapshot parts rather than in a file.
  Map<String, Object?> toJson() {
    final taken = data.keys.where(FormatSpec.envelopeKeys.contains);
    if (taken.isNotEmpty) {
      throw ArgumentError.value(
        taken.join(', '),
        'data',
        'a snapshot field may not be named like the envelope\'s keys '
            '(${FormatSpec.envelopeKeys.join(', ')})',
      );
    }
    return <String, Object?>{...format.envelope(), ...data};
  }

  factory Snapshot.fromJson(Map<String, Object?> json) {
    final version = json[versionKey];
    if (version is! num) {
      throw const SnapshotFormatException(
        'no version, so this is not a '
        'snapshot',
      );
    }
    if (version < 1) {
      throw SnapshotFormatException(
        'snapshot format version $version is not one any build has written',
      );
    }
    // Every envelope version up to this one, lifted step by step; the game's
    // own fields are `SaveSchema`'s and pass through untouched, unknown ones
    // included. A newer version, another format's document or a `requires`
    // this build does not know is refused by the spec, with the reason.
    final lifted = format.open(json, refuse: SnapshotFormatException.new);
    return Snapshot(<String, Object?>{
      for (final entry in lifted.entries)
        if (!FormatSpec.envelopeKeys.contains(entry.key))
          entry.key: entry.value,
    });
  }

  /// Entry `i` lifts an envelope from version `i + 1` to `i + 2`. Empty while
  /// version 1 is the only one, which makes reading it the identity; a bump
  /// adds its step here and a fixture under `test/fixtures/v<N>/`.
  static const List<FormatMigration> _migrations = <FormatMigration>[];
}

/// Reading and writing the handful of shapes a snapshot is made of.
///
/// Free functions rather than an encoder object: every one of them is two
/// lines, and the systems that call them have nothing else in common.
extension SnapshotFields on Map<String, Object?> {
  double number(String key, [double orElse = 0.0]) {
    final value = this[key];
    return value is num ? value.toDouble() : orElse;
  }

  int integer(String key, [int orElse = 0]) {
    final value = this[key];
    return value is num ? value.toInt() : orElse;
  }

  bool flag(String key, {bool orElse = false}) {
    final value = this[key];
    return value is bool ? value : orElse;
  }

  String? text(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  List<Map<String, Object?>> rows(String key) {
    final value = this[key];
    if (value is! List) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final row in value)
        if (row is Map) row.cast<String, Object?>(),
    ];
  }

  /// A nested object, or null when the field is missing or is not one.
  ///
  /// **The one idiom this extension was missing**, and it is written out in
  /// every restore in the repository: read the field, check it is a map, cast
  /// it, hand it on. The cast is the half people leave out, and the half that
  /// fails at a distance — a map of `dynamic` keys passed to something
  /// expecting `String` ones throws in the callee rather than here.
  Map<String, Object?>? object(String key) {
    final value = this[key];
    return value is Map ? value.cast<String, Object?>() : null;
  }

  /// Reads a vector into [out], leaving it alone when the field is missing,
  /// and says whether it found one.
  ///
  /// **Lenient about the contents as well as the key**, which it was not: a
  /// list holding anything but numbers used to throw out of a restore, and a
  /// snapshot is exactly the document that must not do that — see the note on
  /// [Snapshot] about older builds. The strictness lived here and in the
  /// shooter's projectiles, both since fixed.
  ///
  /// The reading itself is `flutter3d_physics`'s `readVector`, which two bodies
  /// there restore themselves with. **The primitive lives in the package
  /// underneath**, because that is the direction the dependency runs: a
  /// character controller cannot reach up to a save file, and a save file can
  /// always reach down to a vector.
  bool vectorInto(String key, Vector3 out) => readVector(this[key], out);

  /// The value of [values] whose name was written down, or [orElse].
  ///
  /// An enum saved by name rather than by index, which is what this repository
  /// does everywhere: an index is a promise never to reorder a declaration,
  /// and nobody keeps that promise.
  ///
  /// For a game's own enums in its snapshot part. The genres' run states
  /// stopped being enums in 1.0 and read themselves with their own `byName`,
  /// so nothing in this repository calls it now; a game written against 0.8
  /// that saves an enum of its own does.
  T enumOf<T extends Enum>(String key, List<T> values, T orElse) {
    final name = this[key];
    if (name is! String) return orElse;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return orElse;
  }
}

/// A vector as three numbers, which is what JSON has.
List<double> vectorOf(Vector3 v) => <double>[v.x, v.y, v.z];
