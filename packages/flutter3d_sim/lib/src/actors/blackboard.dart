/// What a behaviour tree remembers between one decision and the next.
///
/// ## A component, and that is the point of it
///
/// A tree is data and is shared by every actor that runs it; what differs
/// between two of them is where each is in it, what each has noticed and how
/// long each has been waiting. All of that is here, on the actor's entity, so
/// `EcsWorld.save()` writes it with everything else and a snapshot, a rewind
/// or a save file brings a decision back half made. The alternative was state
/// on the brain, written out through `Brain.save` — which works until the
/// first leaf somebody adds keeps a field and forgets to.
///
/// ## Only what a snapshot may hold
///
/// Every value is JSON-shaped: `null`, `bool`, `num`, `String`, lists and
/// string-keyed maps of those. [set] refuses anything else, because a
/// `Vector3` put here would be saved as nothing and the restored run would
/// part from the original without anybody being told why. A point is a list
/// of three numbers, and [setPoint] and [point] write and read one.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart' show readVector;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ComponentCodec;
import 'package:vector_math/vector_math.dart';

import '../ecs/ecs_world.dart';
import '../save/snapshot.dart' show SnapshotFormatException;

/// How a node came out of its last tick.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class BehaviorStatus {
  const BehaviorStatus._(this.name);

  /// The node did what it was for: a sequence goes on to its next child, a
  /// selector stops here.
  static const BehaviorStatus success = BehaviorStatus._('success');

  /// The node could not: a sequence stops here, a selector tries its next
  /// child.
  static const BehaviorStatus failure = BehaviorStatus._('failure');

  /// The node is not done: the tree stops here this tick, and the actor
  /// goes on acting on this leaf until a later tick decides.
  static const BehaviorStatus running = BehaviorStatus._('running');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<BehaviorStatus> values = <BehaviorStatus>[
    success,
    failure,
    running,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static BehaviorStatus? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'BehaviorStatus.$name';
}

/// One actor's memory for its behaviour tree: named JSON-shaped values,
/// its own clock, and where in the tree it was, all saved with it.
final class Blackboard {
  /// A board holding [values], each put through [set], so one a snapshot
  /// cannot hold throws an [ArgumentError].
  Blackboard({Map<String, Object?>? values}) : _values = <String, Object?>{} {
    values?.forEach(set);
  }

  final Map<String, Object?> _values;

  /// Seconds this actor has been acting, advanced every step it is alive.
  ///
  /// **Its own clock rather than the system's step count**, because thinking
  /// is throttled: an actor far from the focus decides every fourth step, and
  /// a wait measured in decisions would last four times as long out there.
  double clock = 0.0;

  /// The digest of the tree this was last ticked by, as eight hex digits.
  ///
  /// Node indices mean nothing under another tree, so a board restored under a
  /// tree that changed starts its decision again rather than resuming at an
  /// index that now names something else. See `BehaviorTree.prepare`.
  String tree = '';

  /// Per node, what it needs while it is running: a sequence's cursor, the
  /// moment a wait began. Dropped for every node that is not on the running
  /// path after a tick, so an abandoned branch starts afresh when it is next
  /// chosen.
  final Map<int, Object?> memory = <int, Object?>{};

  /// Per cooldown node, the clock at which it may run again. Kept off the
  /// running path, which is what a cooldown is for.
  final Map<int, double> readyAt = <int, double>{};

  /// The nodes ticked on the way to the last leaf, root first.
  final List<int> path = <int>[];

  /// How each node on [path] came out, in the same order.
  final List<BehaviorStatus> statuses = <BehaviorStatus>[];

  /// Whether the last tick left something running, which is what `act` asks.
  bool get isRunning =>
      statuses.isNotEmpty && statuses.first == BehaviorStatus.running;

  /// Every key with a value.
  Iterable<String> get keys => _values.keys;

  /// Whether [key] holds a value; a key set to null holds none.
  bool has(String key) => _values.containsKey(key);

  /// The value under [key], as stored, or null when there is none.
  Object? operator [](String key) => _values[key];

  /// Puts [value] under [key], or removes the key for `null`.
  ///
  /// Throws for a value a snapshot cannot hold — see the note at the top of
  /// this file. Thrown rather than skipped: a skipped value is a run that
  /// restores differently, found much later.
  void set(String key, Object? value) {
    if (value == null) {
      _values.remove(key);
      return;
    }
    if (!_jsonShaped(value)) {
      throw ArgumentError.value(
        value,
        key,
        'a blackboard holds what a snapshot may hold: null, bool, num, '
        'String, and lists and string-keyed maps of those',
      );
    }
    _values[key] = value;
  }

  /// Forgets [key]; nothing happens for a key with no value.
  void remove(String key) => _values.remove(key);

  /// The number under [key], or null when there is none.
  double? number(String key) => switch (_values[key]) {
    final num value => value.toDouble(),
    _ => null,
  };

  /// Whether [key] holds anything other than `false`.
  bool flag(String key) => switch (_values[key]) {
    null || false => false,
    _ => true,
  };

  /// Writes [at] as a point, three numbers.
  void setPoint(String key, Vector3 at) =>
      _values[key] = <double>[at.x, at.y, at.z];

  /// Reads the point under [key] into [into], and says whether there was one.
  bool point(String key, Vector3 into) => readVector(_values[key], into);

  /// Forgets where the tree was, keeping what it noticed and the clock.
  void restart() {
    memory.clear();
    readyAt.clear();
    path.clear();
    statuses.clear();
  }

  /// The whole board as JSON: values, clock, tree digest, node memory,
  /// cooldowns and the last path with its statuses.
  Map<String, Object?> toJson() => <String, Object?>{
    'values': Map<String, Object?>.of(_values),
    'clock': clock,
    'tree': tree,
    'memory': <String, Object?>{
      for (final entry in memory.entries) '${entry.key}': entry.value,
    },
    'readyAt': <String, Object?>{
      for (final entry in readyAt.entries) '${entry.key}': entry.value,
    },
    'path': List<int>.of(path),
    'statuses': <String>[for (final status in statuses) status.name],
  };

  /// How a board is written in a snapshot, under `'blackboard'`.
  static final ComponentCodec<Blackboard> codec = ComponentCodec<Blackboard>.of(
    id: 'blackboard',
    encode: (value) => value.toJson(),
    decode: (context) {
      final data = context.data;
      return fromJson(data);
    },
  );

  /// Reads a board back. Throws a [SnapshotFormatException] when [data] is
  /// not one.
  ///
  /// Lenient about the parts: a row with the values and nothing else is a
  /// board that has not decided anything yet, which is what it reads as.
  static Blackboard fromJson(Object? data) {
    if (data is! Map) {
      throw const SnapshotFormatException('a blackboard is an object');
    }
    final values = data['values'];
    final board = Blackboard();
    if (values is Map) {
      for (final entry in values.entries) {
        final key = entry.key;
        if (key is String && _jsonShaped(entry.value)) {
          board._values[key] = entry.value;
        }
      }
    }
    board
      ..clock = switch (data['clock']) {
        final num value => value.toDouble(),
        _ => 0.0,
      }
      ..tree = switch (data['tree']) {
        final String value => value,
        _ => '',
      };
    if (data['memory'] case final Map memory) {
      for (final entry in memory.entries) {
        final index = int.tryParse('${entry.key}');
        if (index != null) board.memory[index] = entry.value;
      }
    }
    if (data['readyAt'] case final Map readyAt) {
      for (final entry in readyAt.entries) {
        final index = int.tryParse('${entry.key}');
        if (index != null && entry.value is num) {
          board.readyAt[index] = (entry.value as num).toDouble();
        }
      }
    }
    final path = data['path'];
    final statuses = data['statuses'];
    if (path is List && statuses is List && path.length == statuses.length) {
      final names = <String, BehaviorStatus>{
        for (final status in BehaviorStatus.values) status.name: status,
      };
      final read = <(int, BehaviorStatus)>[
        for (var i = 0; i < path.length; i++)
          if (path[i] case final num index)
            if (names[statuses[i]] case final BehaviorStatus status)
              (index.toInt(), status),
      ];
      // All or nothing: half a path would act on a leaf the tree never chose.
      if (read.length == path.length) {
        board.path.addAll(read.map((entry) => entry.$1));
        board.statuses.addAll(read.map((entry) => entry.$2));
      }
    }
    return board;
  }

  static bool _jsonShaped(Object? value) => switch (value) {
    null || bool() || num() || String() => true,
    final List list => list.every(_jsonShaped),
    final Map map => map.entries.every(
      (entry) => entry.key is String && _jsonShaped(entry.value),
    ),
    _ => false,
  };
}

/// Teaches [entities] to write a [Blackboard] down.
///
/// A value component, decoded rather than restored in place: a board owns
/// nothing live, so a restore can build a new one, and an entity whose board
/// the save did not have gets a fresh one the next time its brain thinks.
void registerBlackboard(EcsWorld entities) =>
    entities.components.register<Blackboard>(Blackboard.codec);
