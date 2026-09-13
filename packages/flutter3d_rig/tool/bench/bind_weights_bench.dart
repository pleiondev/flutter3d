// ignore_for_file: avoid_print — a command-line benchmark whose whole output
// is stdout.

/// `anim-31a-n`'s own third number: what `bindWeights` costs at 100k
/// vertices, the pipeline `BindWeightsJobRequest` runs inside an isolate.
///
///     dart compile exe tool/bench/bind_weights_bench.dart -o /tmp/bwbench && /tmp/bwbench
///
/// **Standalone Dart on purpose, as `flutter3d_mesh/tool/bench.dart` is.**
/// `dart compile exe` cannot resolve anything reaching the Flutter SDK, so
/// measuring through the same pipeline `BindWeightsJobRequest.run` uses —
/// `bindWeights`, `pruneSkinWeights`, `normalizeSkinWeights` in sequence —
/// is a property of this package being plain Dart, not a coincidence.
///
/// This measures the arithmetic `bindWeights` itself runs, not the isolate
/// boundary it crosses inside `BindWeightsJobRequest.run` — that crossing is
/// the same `editInIsolate` every other job in this repository already pays,
/// measured once for its own sake elsewhere. What this number answers is
/// whether the *work*, run on the isolate that receives it, fits inside the
/// row's own 8 ms — the question a caller choosing whether to chunk it
/// actually has.
library;

import 'package:flutter3d_rig/flutter3d_rig.dart';
import 'package:vector_math/vector_math.dart';

/// A grid of `(side + 1)²` vertices, flat on Y, the cheapest shape to a
/// stated vertex count — the same trick `flutter3d_mesh/tool/bench.dart`
/// uses for its own triangle counts.
List<Vector3> grid(int side) => <Vector3>[
  for (var y = 0; y <= side; y++)
    for (var x = 0; x <= side; x++)
      Vector3(x.toDouble() / side - 0.5, 0, y.toDouble() / side - 0.5),
];

List<int> gridTriangles(int side) {
  final triangles = <int>[];
  int at(int x, int y) => y * (side + 1) + x;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      triangles
        ..add(at(x, y))
        ..add(at(x + 1, y))
        ..add(at(x + 1, y + 1))
        ..add(at(x, y))
        ..add(at(x + 1, y + 1))
        ..add(at(x, y + 1));
    }
  }
  return triangles;
}

/// A chain of [count] bones spanning the grid's own -0.5..0.5 range along X
/// — a spine's own shape, near enough to what a real rig's own influence
/// spread looks like for a cost measurement that only cares how many bones
/// [bindWeights] is asked about.
List<BoneSegment> spineOf(int count) => <BoneSegment>[
  for (var i = 0; i < count; i++)
    BoneSegment(
      Vector3(-0.5 + i / count, 0, 0),
      Vector3(-0.5 + (i + 1) / count, 0, 0),
      name: 'bone$i',
    ),
];

void bench(String name, int iterations, void Function() body, {int? items}) {
  body(); // once untimed, so lazy paths are not counted
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  stopwatch.stop();

  final perIteration = stopwatch.elapsedMicroseconds / iterations;
  final label = perIteration >= 1000
      ? '${(perIteration / 1000).toStringAsFixed(2)} ms'
      : '${perIteration.toStringAsFixed(1)} us';
  var line = '${name.padRight(44)} $label';
  if (items != null && items > 0) {
    line +=
        '   (${(perIteration * 1000 / items).toStringAsFixed(2)} ns/vertex)';
  }
  print(line);
}

void main() {
  print('--- bindWeights, anim-31a-n\'s own third number ------------------');

  // Small sides first: `bindWeights` walks every (vertex, bone) pair and,
  // with `useVisibility`, casts a ray for each — a cost this loop finds by
  // measuring rather than assuming, before spending an iteration at the
  // row's own "100k". `useVisibility: true`'s own numbers grow far faster
  // than the vertex count does (ns/vertex itself roughly doubling every
  // step below) — super-linear, not the O(vertices × bones) the
  // `useVisibility: false` numbers beside them show — so a real run at
  // 100k with it on is not attempted here; the trend is the answer.
  for (final side in <int>[32, 64, 128]) {
    final positions = grid(side);
    final triangles = gridTriangles(side);
    final bones = spineOf(20);
    print('');
    print(
      '$side x $side grid: ${positions.length} vertices, ${bones.length} bones',
    );

    bench(
      'bindWeights (useVisibility: true)',
      1,
      () =>
          bindWeights(positions: positions, triangles: triangles, bones: bones),
      items: positions.length,
    );
    bench(
      'bindWeights (useVisibility: false)',
      1,
      () => bindWeights(
        positions: positions,
        triangles: triangles,
        bones: bones,
        useVisibility: false,
      ),
      items: positions.length,
    );
  }

  // The row's own "100k" — only `useVisibility: false`, for the reason
  // given above.
  const side = 316;
  final positions = grid(side);
  final triangles = gridTriangles(side);
  final bones = spineOf(20);
  print('');
  print(
    '$side x $side grid: ${positions.length} vertices, ${bones.length} bones',
  );
  bench(
    'bindWeights (useVisibility: false)',
    1,
    () => bindWeights(
      positions: positions,
      triangles: triangles,
      bones: bones,
      useVisibility: false,
    ),
    items: positions.length,
  );

  print('');
  print(
    'A number with no machine and no date is a number nobody can hold to '
    '(ARCHITECTURE.md §14\'s own rule for the engine\'s benches). Machine '
    'and date go beside this in doc/model-editor-plan.md alongside it.',
  );
}
