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

import 'package:vector_math/vector_math.dart';

/// Thrown when a snapshot cannot be read at all.
final class SnapshotFormatException implements Exception {
  const SnapshotFormatException(this.message);
  final String message;
  @override
  String toString() => 'SnapshotFormatException: $message';
}

final class Snapshot {
  const Snapshot(this.data);

  /// Bumped when an existing field changes meaning.
  static const int formatVersion = 1;

  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': formatVersion,
        ...data,
      };

  factory Snapshot.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! num) {
      throw const SnapshotFormatException('no version, so this is not a '
          'snapshot');
    }
    if (version > formatVersion) {
      throw SnapshotFormatException(
        'snapshot format version $version is newer than this build '
        'understands ($formatVersion)',
      );
    }
    return Snapshot(json);
  }
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

  bool flag(String key, [bool orElse = false]) {
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

  /// Reads a vector into [out], leaving it alone when the field is missing.
  void vectorInto(String key, Vector3 out) {
    final value = this[key];
    if (value is! List || value.length < 3) return;
    out.setValues(
      (value[0] as num).toDouble(),
      (value[1] as num).toDouble(),
      (value[2] as num).toDouble(),
    );
  }
}

/// A vector as three numbers, which is what JSON has.
List<double> vectorOf(Vector3 v) => <double>[v.x, v.y, v.z];
