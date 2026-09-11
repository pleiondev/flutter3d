import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';

/// One keyframe in a [KeyTable] — a time, a value, and the two tangents a
/// cubic-interpolated key carries whether or not the table is currently
/// showing them.
///
/// **Tangents are never dropped by switching modes.** [KeyTable
/// .setInterpolation] toggles between linear and cubic display without
/// touching a single [Key] — a key authored as cubic and viewed as linear
/// for a moment still has its tangents when the table switches back, rather
/// than losing the curve shape a person spent time shaping.
final class Key {
  const Key({required this.time, required this.values, this.inTangent, this.outTangent});

  final double time;

  /// One value per component — the point itself, never a tangent.
  final List<double> values;

  /// Read only when the table's own [KeyTable.interpolation] is
  /// [AnimationInterpolation.cubicSpline]. Treated as all zeros when null,
  /// which is a flat tangent — the ordinary shape a key gets the moment a
  /// table switches into cubic mode and nobody has sculpted this one yet.
  final List<double>? inTangent;
  final List<double>? outTangent;

  Key withTime(double newTime) =>
      Key(time: newTime, values: values, inTangent: inTangent, outTangent: outTangent);

  Key withTangents({List<double>? inTangent, List<double>? outTangent}) => Key(
    time: time,
    values: values,
    inTangent: inTangent ?? this.inTangent,
    outTangent: outTangent ?? this.outTangent,
  );
}

/// An editable keyframe track — `anim-04`'s own row, the mutable half of
/// what [AnimationTrack] is the immutable, sample-ready half of.
///
/// **Why this exists beside [AnimationTrack].** That class is built once by
/// a decoder or a writer and samples fast — binary search over a flat
/// `Float32List`, the shape a player reads sixty times a second. Editing one
/// key of a hundred means rebuilding the whole flat array regardless, which
/// is the wrong cost to pay on every drag of a timeline. [KeyTable] holds
/// the same information as a list of [Key]s instead — cheap to insert into,
/// move within, or delete from — and [toAnimationTrack] is the one place
/// that pays the flattening cost, once, when something actually needs to
/// sample.
///
/// **Keys stay sorted by [Key.time], always.** [AnimationTrack]'s own
/// contract requires ascending times for its binary search to mean
/// anything, and a table that let them fall out of order would produce a
/// track that silently samples the wrong key. Every mutator here restores
/// the order before returning rather than trusting a caller to have kept it.
final class KeyTable {
  KeyTable({
    required this.componentCount,
    this.interpolation = AnimationInterpolation.linear,
    List<Key>? keys,
  }) : _keys = List<Key>.of(keys ?? const <Key>[])
         ..sort((a, b) => a.time.compareTo(b.time));

  final int componentCount;
  AnimationInterpolation interpolation;

  final List<Key> _keys;

  /// Read-only — see [KeyTable.values] and every mutator on this class for
  /// the one way to change what is here.
  List<Key> get keys => List<Key>.unmodifiable(_keys);

  int get keyCount => _keys.length;

  double get duration => _keys.isEmpty ? 0.0 : _keys.last.time;

  /// [track] read into an editable table — the same values, split back out
  /// of whichever of [AnimationTrack]'s two flat layouts [track.interpolation]
  /// used, cubic's own in/value/out triple included.
  factory KeyTable.fromAnimationTrack(AnimationTrack track) {
    final cubic = track.interpolation == AnimationInterpolation.cubicSpline;
    final stride = track.componentCount * (cubic ? 3 : 1);
    final keys = <Key>[
      for (var i = 0; i < track.keyCount; i++)
        if (cubic)
          Key(
            time: track.times[i],
            inTangent: _slice(track.values, i * stride, track.componentCount),
            values: _slice(
              track.values,
              i * stride + track.componentCount,
              track.componentCount,
            ),
            outTangent: _slice(
              track.values,
              i * stride + track.componentCount * 2,
              track.componentCount,
            ),
          )
        else
          Key(
            time: track.times[i],
            values: _slice(track.values, i * stride, track.componentCount),
          ),
    ];
    return KeyTable(
      componentCount: track.componentCount,
      interpolation: track.interpolation,
      keys: keys,
    );
  }

  static List<double> _slice(Float32List from, int at, int count) => <double>[
    for (var c = 0; c < count; c++) from[at + c],
  ];

  /// This table's keys, flattened into an [AnimationTrack] ready to sample
  /// or write — the exact inverse of [KeyTable.fromAnimationTrack]. Throws
  /// the same [ArgumentError] [AnimationTrack]'s own constructor would for
  /// an empty table: a track with no keyframes is not a thing either class
  /// can honestly claim to sample.
  AnimationTrack toAnimationTrack({required int nodeIndex, required AnimationPath path}) {
    final times = Float32List.fromList(<double>[for (final k in _keys) k.time]);
    final cubic = interpolation == AnimationInterpolation.cubicSpline;
    final stride = componentCount * (cubic ? 3 : 1);
    final values = Float32List(_keys.length * stride);

    for (var i = 0; i < _keys.length; i++) {
      final key = _keys[i];
      final base = i * stride;
      if (cubic) {
        final inT = key.inTangent ?? List<double>.filled(componentCount, 0.0);
        final outT = key.outTangent ?? List<double>.filled(componentCount, 0.0);
        for (var c = 0; c < componentCount; c++) {
          values[base + c] = inT[c];
          values[base + componentCount + c] = key.values[c];
          values[base + componentCount * 2 + c] = outT[c];
        }
      } else {
        for (var c = 0; c < componentCount; c++) {
          values[base + c] = key.values[c];
        }
      }
    }

    return AnimationTrack(
      nodeIndex: nodeIndex,
      path: path,
      interpolation: interpolation,
      times: times,
      values: values,
      componentCount: componentCount,
    );
  }

  /// Samples this table at [time] as it currently stands — `anim-04`'s own
  /// "sample(t) после правок" acceptance, so an edit is visible to a
  /// caller without a manual round trip through [toAnimationTrack] first.
  void sample(double time, Float32List out) {
    // A dummy target: sampling reads only interpolation, times and values,
    // never `nodeIndex`/`path`, so building the real one is not this
    // method's business to know.
    toAnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.values.first,
    ).sample(time, out);
  }

  void _resort() => _keys.sort((a, b) => a.time.compareTo(b.time));

  /// Writes (or replaces) the key at [time]. An existing key at exactly
  /// this time is replaced outright rather than getting a second key beside
  /// it — `setKey` is what a person calling it once, twice, or a hundred
  /// times while dragging a value at a fixed playhead expects every time.
  void setKey(
    double time,
    List<double> values, {
    List<double>? inTangent,
    List<double>? outTangent,
  }) {
    final key = Key(time: time, values: values, inTangent: inTangent, outTangent: outTangent);
    final existing = _keys.indexWhere((k) => k.time == time);
    if (existing >= 0) {
      _keys[existing] = key;
    } else {
      _keys.add(key);
      _resort();
    }
  }

  /// Shifts the keys at [indices] by [deltaTime], re-sorting afterward so
  /// two keys crossing each other on the way past land in the order their
  /// new times say rather than the order they had before the move.
  void moveKeys(List<int> indices, double deltaTime) {
    for (final i in indices) {
      if (i < 0 || i >= _keys.length) continue;
      _keys[i] = _keys[i].withTime(_keys[i].time + deltaTime);
    }
    _resort();
  }

  /// Removes the keys at [indices]. Sorted and walked back to front
  /// internally, so an earlier removal never shifts a later index still
  /// waiting to be read — the caller hands over indices into the table as
  /// it was before this call, in whatever order it likes.
  void deleteKeys(List<int> indices) {
    final sorted = List<int>.of(indices)..sort();
    for (var i = sorted.length - 1; i >= 0; i--) {
      final index = sorted[i];
      if (index < 0 || index >= _keys.length) continue;
      _keys.removeAt(index);
    }
  }

  /// Switches how the table's own keys are read — linear or cubic, `anim
  /// -04`'s own "linear↔cubic". Every [Key]'s own tangents stay exactly as
  /// they were; only [interpolation] itself changes, which is what lets a
  /// key already sculpted survive a person switching modes to check what a
  /// straight line would have looked like and switching straight back.
  void setInterpolation(AnimationInterpolation next) {
    interpolation = next;
  }

  /// Sets one key's own tangents, leaving its time and value untouched.
  /// Read only while [interpolation] is [AnimationInterpolation.cubicSpline]
  /// — see [Key.inTangent] for what a tangent set while linear is showing
  /// still means once the table switches back.
  void setTangent(int index, {List<double>? inTangent, List<double>? outTangent}) {
    if (index < 0 || index >= _keys.length) return;
    _keys[index] = _keys[index].withTangents(inTangent: inTangent, outTangent: outTangent);
  }
}
