/// `PolylineVertexShader`'s join, checked against the vertex stage directly
/// rather than through a rendered frame.
///
/// The join used to mitre: bisect the two neighbouring directions and
/// stretch the offset so both segments kept their full width through the
/// turn, clamped past four half widths. That stretch read the *angle*
/// between two independently projected directions, and a projection puts no
/// floor under how extreme an angle it will report for a turn that is
/// nowhere near that sharp in three dimensions — which is what let a
/// handful of ordinary joints explode into unrelated triangles from the
/// right camera angle. The join now offsets by one direction per point, the
/// point before to the point after, with no angle and no stretch: the
/// tests below hold the one invariant that replaces the old ones — the
/// offset is always exactly the half width, whatever the turn.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/src/cpu_shader_bindings.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_layout.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_polyline.dart';
import 'package:flutter3d_cpu/src/cpu_texture.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _width = 8.0;
const double _viewport = 200.0;

ShaderBindings _identityBindings() =>
    ShaderBindings(<String, Map<String, Float32List>>{
      'FrameInfo': <String, Float32List>{
        'mvp': Float32List.fromList(Matrix4.identity().storage),
        'model': Float32List.fromList(Matrix4.identity().storage),
        'normal_matrix': Float32List.fromList(Matrix4.identity().storage),
      },
      'MaterialParams': <String, Float32List>{
        'viewport': Float32List.fromList(<double>[_viewport, _viewport, 0, 0]),
      },
    }, <String, BoundTexture>{});

/// One joint vertex: `here`, with `before` and `after` as its neighbours and
/// `side`/`halfWidth` packed into `tangent.w` the way `buildPolyline` packs
/// them.
Float32List _vertex({
  required Vector3 here,
  required Vector3 before,
  required Vector3 after,
  required bool sideZero,
}) {
  final a = Float32List(16);
  a[kPosition] = here.x;
  a[kPosition + 1] = here.y;
  a[kPosition + 2] = here.z;
  a[kNormal] = before.x;
  a[kNormal + 1] = before.y;
  a[kNormal + 2] = before.z;
  a[kTangent] = after.x;
  a[kTangent + 1] = after.y;
  a[kTangent + 2] = after.z;
  a[kTangent + 3] = sideZero ? -_width / 2 : _width / 2;
  return a;
}

/// The offset the vertex stage applied, in pixels — read back out of the
/// clip position it returned, at `here`'s own w (which is 1 under an
/// identity MVP), the same conversion the vertex stage's own last line does
/// in reverse.
Vector2 _offsetPixels(Vector4 clip, Vector3 here) => Vector2(
  (clip.x - here.x) * (_viewport * 0.5),
  (clip.y - here.y) * (_viewport * 0.5),
);

void main() {
  const shader = PolylineVertexShader();
  final out = Float32List(shader.varyingCount);

  Vector2 offsetFor({
    required Vector3 before,
    required Vector3 after,
    bool sideZero = false,
  }) {
    final vertex = _vertex(
      here: Vector3.zero(),
      before: before,
      after: after,
      sideZero: sideZero,
    );
    final clip = shader.runAt(1, 0, vertex, _identityBindings(), out);
    return _offsetPixels(clip, Vector3.zero());
  }

  test('a straight run offsets by exactly the half width, on either side', () {
    final offset = offsetFor(
      before: Vector3(-1, 0, 0),
      after: Vector3(1, 0, 0),
    );
    expect(offset.x.abs(), lessThan(1e-6));
    expect(offset.y, closeTo(_width / 2, 1e-6));
  });

  test('a right-angle turn still offsets by exactly the half width', () {
    // Mutation: bring back a stretch keyed on the turn angle — this passes
    // only because there is none left to key on.
    final offset = offsetFor(
      before: Vector3(-1, 0, 0),
      after: Vector3(0, 1, 0),
    );
    expect(offset.length, closeTo(_width / 2, 1e-6));
  });

  test('a joint folding straight back on itself still offsets by exactly '
      'the half width', () {
    // The one case a mitre used to single out for special handling — a
    // route reversing on itself has no single "outward" side to bisect
    // towards, and no longer needs one: the offset is the same half width
    // it is everywhere else, along whichever perpendicular the fold leaves
    // well defined.
    final offset = offsetFor(
      before: Vector3(-1, 0, 0),
      after: Vector3(-1, 0, 0),
    );
    expect(offset.length, closeTo(_width / 2, 1e-6));
  });

  test('a true end of the line offsets by exactly the half width too', () {
    // `buildPolyline` marks an end by copying `position` into `normal` (no
    // point before) or `tangent.xyz` (no point after) — the join's own
    // "one direction only" case, not a special one.
    final atStart = offsetFor(before: Vector3.zero(), after: Vector3(1, 0, 0));
    expect(atStart.length, closeTo(_width / 2, 1e-6));

    final atEnd = offsetFor(before: Vector3(-1, 0, 0), after: Vector3.zero());
    expect(atEnd.length, closeTo(_width / 2, 1e-6));
  });

  test('the two sides of the band are opposite, at every turn', () {
    for (final after in <Vector3>[
      Vector3(1, 0, 0),
      Vector3(0, 1, 0),
      Vector3(-1, 0.3, 0),
      Vector3(-1, 0, 0),
    ]) {
      final left = offsetFor(before: Vector3(-1, 0, 0), after: after);
      final right = offsetFor(
        before: Vector3(-1, 0, 0),
        after: after,
        sideZero: true,
      );
      expect(
        (left + right).length,
        lessThan(1e-6),
        reason: 'the two sides should cancel exactly for $after',
      );
    }
  });
}
