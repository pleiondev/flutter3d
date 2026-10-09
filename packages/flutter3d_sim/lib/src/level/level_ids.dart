import 'dart:math' as math;

import '../save/state_digest.dart';

/// The ids a level gives its entities, brushes and lights.
///
/// **An id is what a thing in a level is called by everything that has to
/// find it again**: a prefab override, the editor's selection, a tool that
/// patches one entity. A name is for people and may change; an index moves
/// when something is inserted before it. An id does neither — it is written
/// into the document beside the thing and survives renaming and reordering.
///
/// Opaque strings, compared only for equality. Two kinds are made:
///
/// * [fresh], eight random characters, for something a person or a tool adds;
/// * [derive], a digest of what the thing is, for something that arrives
///   without one — a level written before ids existed, or one built in code
///   by a generator. **Deterministic on purpose:** a level's digest is what a
///   recorded run is checked against, so an id assigned on load must be the
///   same on every load, on every platform.
abstract final class LevelIds {
  static const String _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  /// Eight characters from [random] — a seeded one where a generator must
  /// make the same level twice, the editor's own where a person adds a row.
  /// Handed in, never made here: the simulation asks no generator it was not
  /// given.
  static String fresh(math.Random random) => String.fromCharCodes(<int>[
    for (var i = 0; i < 8; i++)
      _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
  ]);

  /// An id made from [parts], the same for the same parts on every platform.
  static String derive(List<Object?> parts) =>
      contentDigestHex(<String, Object?>{'id': parts});

  /// [items] with every id unique: the first holder of an id keeps it, and a
  /// later one is given one derived from it and its place, so pasting a copy
  /// of a row — id and all — into a level makes two things, not one thing
  /// twice. [taken] collects the ids handed out, so several lists can share
  /// one space of ids.
  static List<T> unique<T>(
    List<T> items, {
    required String Function(T item) idOf,
    required T Function(T item, String id) withId,
    required Set<String> taken,
  }) => <T>[
    for (final (index, item) in items.indexed)
      if (taken.add(idOf(item)))
        item
      else
        withId(item, _salted(idOf(item), index, taken)),
  ];

  static String _salted(String id, int index, Set<String> taken) {
    final candidate = Iterable<int>.generate(1 << 16)
        .map((int salt) => derive(<Object?>[id, index, salt]))
        .firstWhere((String c) => !taken.contains(c));
    taken.add(candidate);
    return candidate;
  }
}
