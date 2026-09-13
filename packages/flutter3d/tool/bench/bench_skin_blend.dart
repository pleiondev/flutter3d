// ignore_for_file: avoid_print — a command-line benchmark whose whole output
// is stdout.

/// `anim-31a-n`'s own second number: what `SkinBlend.blend` costs at 200k
/// vertices.
///
///     dart compile exe tool/bench/bench_skin_blend.dart -o /tmp/skbench && /tmp/skbench
///
/// **Standalone on purpose, the same as `bench_geometry.dart` beside it.**
/// `skin_blend.dart` itself imports nothing but `dart:typed_data` and
/// `flutter3d_geometry` — no Flutter, no `GraphicsDevice` — so this compiles
/// ahead of time the same way, even though the package it lives in needs the
/// Flutter SDK for everything else in it.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/src/engine/animation/skin_blend.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// A grid of `(side + 1)²` vertices, [VertexLayout.skinned], each rigidly
/// bound to whichever of [jointCount] joints its own X falls under — a
/// spine's own shape of influence, near enough for a cost measurement that
/// only cares how many vertices and joints [SkinBlend] is asked about.
MeshData skinnedGrid(int side, int jointCount) {
  const layout = VertexLayout.skinned;
  final stride = layout.floatsPerVertex;
  final vertices = (side + 1) * (side + 1);
  final data = Float32List(vertices * stride);

  var v = 0;
  for (var y = 0; y <= side; y++) {
    for (var x = 0; x <= side; x++) {
      final at = v * stride;
      final u = x / side;
      data[at] = u - 0.5;
      data[at + 1] = 0;
      data[at + 2] = y / side - 0.5;
      data[at + 3] = 0;
      data[at + 4] = 1;
      data[at + 5] = 0;
      data[at + 8] = 1;
      data[at + 11] = 1;
      data[at + 12] = 1;
      data[at + 13] = 1;
      data[at + 14] = 1;
      data[at + 15] = 1;
      final joint = (u * jointCount).floor().clamp(0, jointCount - 1);
      data[at + 16] = joint.toDouble();
      data[at + 20] = 1.0;
      v++;
    }
  }

  final indices = <int>[];
  int idx(int x, int y) => y * (side + 1) + x;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      indices
        ..add(idx(x, y))
        ..add(idx(x + 1, y))
        ..add(idx(x + 1, y + 1))
        ..add(idx(x, y))
        ..add(idx(x + 1, y + 1))
        ..add(idx(x, y + 1));
    }
  }

  return MeshData(
    layout: layout,
    vertices: data,
    indices: Uint32List.fromList(indices),
  );
}

Float32List identityJoints(int count) {
  final out = Float32List(count * 16);
  for (var j = 0; j < count; j++) {
    Matrix4.identity().copyIntoArray(out, j * 16);
  }
  return out;
}

void bench(String name, int iterations, void Function() body, {int? items}) {
  body();
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
    line += '   (${(perIteration * 1000 / items).toStringAsFixed(2)} ns/vertex)';
  }
  print(line);
}

void main() {
  print('--- SkinBlend, anim-31a-n\'s own second number -------------------');

  // 316² = 99 856; 447² = 199 809, near enough the row's own "200k".
  const side = 447;
  const jointCount = 30;
  final mesh = skinnedGrid(side, jointCount);
  final rest = identityJoints(jointCount);
  final moved = identityJoints(jointCount);
  for (var j = 0; j < jointCount; j++) {
    Matrix4.translation(Vector3(0, 0.1 * (j.isEven ? 1 : -1), 0)).copyIntoArray(moved, j * 16);
  }
  print('');
  print('$side x $side grid: ${mesh.vertexCount} vertices, $jointCount joints');

  // Every call after the first differs from what is already applied — a
  // paused rig is not what this measures, `blend`'s own early return
  // already covers that case for free.
  var toggle = false;
  bench(
    'SkinBlend.blend (every call moves something)',
    5,
    () {
      final skin = SkinBlend(mesh);
      toggle = !toggle;
      skin.blend(toggle ? moved : rest);
    },
    items: mesh.vertexCount,
  );

  final skin = SkinBlend(mesh);
  skin.blend(rest);
  bench(
    'SkinBlend.blend (no change — the early-return path)',
    5,
    () => skin.blend(rest),
    items: mesh.vertexCount,
  );

  print('');
  print(
    'A number with no machine and no date is a number nobody can hold to '
    '(ARCHITECTURE.md §14\'s own rule for the engine\'s benches). Machine '
    'and date go beside this in doc/model-editor-plan.md alongside it.',
  );
}
