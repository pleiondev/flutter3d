// ignore_for_file: avoid_print — a command-line benchmark whose whole output is
// stdout.

/// What a step of history costs, measured two ways.
///
///     dart compile exe tool/bench_persistence.dart -o /tmp/bench && /tmp/bench
///
/// **The question `p0-05` asks, and why it decides a data structure.** Undo in
/// a modeller is a stack of previous values, and the naive answer — copy the
/// whole vertex array per step — is 2.4 MB per undo on a 200 000-vertex mesh.
/// Sixty-four of those is 150 MB of history for a model somebody is nudging.
/// So the plan's two candidates are measured here against the same edits:
///
///   * **Chunked copy-on-write.** Positions live in fixed-size chunks; writing
///     to one copies that chunk and shares the rest. A step costs the chunks
///     that were touched.
///   * **A patch log.** Positions live in one flat array; a step records the
///     indices and the values they had. A step costs the edits themselves,
///     and reading is free — but every read of an old version has to replay.
///
/// Two distributions, because they are the two things a person actually does:
/// a **cluster** (drag one face, and the vertices are adjacent) and a
/// **scatter** (select every rib of a mesh and move them, and they are not).
/// Chunking wins the first by construction; the second is where it is decided.
///
/// The thresholds are `p0-05`'s own: at or under 10 % of a full copy and at or
/// under 2 ms in both distributions, chunking is fixed as the structure. Only
/// the cluster passing means a flat array with a journal. Neither means a
/// snapshot per transaction and no per-command undo at all.
library;

import 'dart:math';
import 'dart:typed_data';

/// A vector of floats kept in fixed-size chunks, shared until written to.
///
/// The prototype of `mesh-10`'s `PersistentFloat32Vector`, with everything the
/// real one will need left out: no transient, no ownership token, no freeze.
/// What is here is the cost model — a write copies one chunk, a version shares
/// the rest — and that is the thing being measured.
final class ChunkedFloat32 {
  ChunkedFloat32(this.length, this.chunkSize)
    : _chunks = List<Float32List>.generate(
        (length + chunkSize - 1) ~/ chunkSize,
        (_) => Float32List(chunkSize),
        growable: false,
      );

  ChunkedFloat32._(this.length, this.chunkSize, this._chunks);

  final int length;
  final int chunkSize;
  final List<Float32List> _chunks;

  double operator [](int index) =>
      _chunks[index ~/ chunkSize][index % chunkSize];

  /// A new version with [edits] applied, sharing every chunk they did not
  /// touch. Returns the version and how many bytes are not shared with this one.
  (ChunkedFloat32, int) write(Map<int, double> edits) {
    final copied = <int>{};
    final chunks = List<Float32List>.of(_chunks, growable: false);
    for (final entry in edits.entries) {
      final chunk = entry.key ~/ chunkSize;
      if (copied.add(chunk)) {
        chunks[chunk] = Float32List.fromList(chunks[chunk]);
      }
      chunks[chunk][entry.key % chunkSize] = entry.value;
    }
    return (
      ChunkedFloat32._(length, chunkSize, chunks),
      copied.length * chunkSize * 4,
    );
  }
}

/// One flat array and a log of what each step overwrote.
///
/// The alternative `p0-05` names. Writing is a store plus a record of the old
/// value; undo is replaying the record backwards. Cheap to write, cheap to
/// read *now*, and it holds one array rather than a version per step — which
/// is also its cost: an old version does not exist until it is replayed.
final class PatchedFloat32 {
  PatchedFloat32(int length) : values = Float32List(length);

  final Float32List values;
  final List<(Int32List indices, Float32List before)> log =
      <(Int32List, Float32List)>[];

  /// Applies [edits] and records what they replaced. Returns the bytes the
  /// step added to the log.
  int write(Map<int, double> edits) {
    final indices = Int32List(edits.length);
    final before = Float32List(edits.length);
    var i = 0;
    for (final entry in edits.entries) {
      indices[i] = entry.key;
      before[i] = values[entry.key];
      values[entry.key] = entry.value;
      i++;
    }
    log.add((indices, before));
    return edits.length * 8;
  }

  /// Takes the last step back.
  void undo() {
    final (indices, before) = log.removeLast();
    for (var i = 0; i < indices.length; i++) {
      values[indices[i]] = before[i];
    }
  }
}

/// The floats a step touches: one per cent of the mesh, as a cluster or
/// scattered over it.
Map<int, double> edits(int floats, Random random, {required bool clustered}) {
  final count = floats ~/ 100;
  final map = <int, double>{};
  if (clustered) {
    // A drag of one region: consecutive vertices, which is what a face or a
    // loop is in a mesh that came out of a modeller.
    final start = random.nextInt(floats - count);
    for (var i = 0; i < count; i++) {
      map[start + i] = i.toDouble();
    }
  } else {
    while (map.length < count) {
      map[random.nextInt(floats)] = map.length.toDouble();
    }
  }
  return map;
}

void bench(String name, int iterations, void Function() body) {
  body();
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  stopwatch.stop();
  final per = stopwatch.elapsedMicroseconds / iterations;
  print('${name.padRight(52)} ${(per / 1000).toStringAsFixed(3)} ms');
}

void main() {
  // 200 000 vertices, three floats apiece: the mesh size every threshold in
  // the plan is stated against.
  const vertices = 200000;
  const floats = vertices * 3;
  const fullCopyBytes = floats * 4;

  print(
    '200 000 vertices — a full copy of the positions is '
    '${(fullCopyBytes / 1024).round()} KB',
  );

  for (final clustered in <bool>[true, false]) {
    print('');
    print(
      '--- ${clustered ? "one per cent, clustered" : "one per cent, scattered"}'
      ' ------------------',
    );

    // A seeded generator, so two runs on two machines edit the same floats.
    final random = Random(1234);
    final step = edits(floats, random, clustered: clustered);

    for (final chunkSize in <int>[256, 1024, 4096]) {
      final base = ChunkedFloat32(floats, chunkSize);
      var bytes = 0;
      bench('chunked copy-on-write, chunk $chunkSize', 20, () {
        final (_, cost) = base.write(step);
        bytes = cost;
      });
      final share = bytes / fullCopyBytes * 100;
      print(
        '${" " * 52}${(bytes / 1024).toStringAsFixed(1)} KB per step '
        '(${share.toStringAsFixed(1)} % of a full copy)',
      );
    }

    final patched = PatchedFloat32(floats);
    var patchBytes = 0;
    bench('flat array with a patch log', 20, () {
      patchBytes = patched.write(step);
      patched.undo();
    });
    print(
      '${" " * 52}${(patchBytes / 1024).toStringAsFixed(1)} KB per step '
      '(${(patchBytes / fullCopyBytes * 100).toStringAsFixed(1)} % of a full '
      'copy)',
    );

    final flat = Float32List(floats);
    bench('a full copy, for scale', 20, () => Float32List.fromList(flat));
  }
}
