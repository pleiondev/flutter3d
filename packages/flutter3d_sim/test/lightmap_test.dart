/// A lightmap's unwrap.
///
///     dart test test/lightmap_test.dart
///
/// A closed room with one lamp in it. The layout gives every visible face a
/// rectangle and no two overlap; the geometry hands each vertex a second
/// coordinate inside its face's rectangle. The bake and the sidecar it
/// writes are `flutter3d_build`'s, and tested there.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double cx, double cy, double cz, double sx, double sy, double sz) =>
    Brush(center: Vector3(cx, cy, cz), size: Vector3(sx, sy, sz));

/// An 8 × 3 × 8 room: floor at y = 0, ceiling at y = 3, walls a metre
/// thick, all grey. Lit by one lamp in the middle, a metre and a half up.
///
/// [floorMaterial] repaints the floor without moving anything, and [extra]
/// keeps each brush's own solidity, so the staleness tests can change one
/// thing the bake reads at a time.
Level _room({
  List<Brush> extra = const <Brush>[],
  double intensity = 10.0,
  String floorMaterial = 'stone',
}) => Level(
  name: 'a room',
  materials: <String, LevelMaterial>{
    'stone': LevelMaterial(baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6)),
    'soot': LevelMaterial(baseColor: LinearColor.fromSrgb(0.02, 0.02, 0.02)),
  },
  brushes: <Brush>[
    Brush(
      center: Vector3(0.0, -0.5, 0.0),
      size: Vector3(10.0, 1.0, 10.0),
      material: floorMaterial,
    ),
    ...<Brush>[
      _box(0.0, 3.5, 0.0, 10.0, 1.0, 10.0),
      _box(-4.5, 1.5, 0.0, 1.0, 3.0, 10.0),
      _box(4.5, 1.5, 0.0, 1.0, 3.0, 10.0),
      _box(0.0, 1.5, -4.5, 8.0, 3.0, 1.0),
      _box(0.0, 1.5, 4.5, 8.0, 3.0, 1.0),
      ...extra,
    ].map(
      (b) => Brush(
        center: b.center,
        size: b.size,
        material: b.material == 'default' ? 'stone' : b.material,
        solid: b.solid,
      ),
    ),
  ],
  lights: <LevelLight>[
    // [intensity] in the unit a lightmap's texels are in, one pre-1.0 unit
    // each: the light itself is in candela.
    LevelLight(
      position: Vector3(0.0, 1.5, 0.0),
      intensity: intensity * LevelLight.defaultIntensity,
    ),
  ],
);

/// The floor's upward face, which the layout planned.
LightmapFace _floorTop(LightmapLayout layout) =>
    layout.faces.singleWhere((f) => f.brush == 0 && f.normal.y > 0.5);

void main() {
  group('the layout', () {
    test('gives every visible face a rectangle, and no two overlap', () {
      final level = _room();
      final layout = LightmapLayout.plan(level, texelsPerMeter: 4.0);

      // Six faces face the room; the outer faces of the shell are visible
      // too since nothing hides them, so more than six — but the ones that
      // touch another brush are not.
      expect(layout.faces.length, greaterThanOrEqualTo(6));
      final floor = _floorTop(layout);
      expect(floor.width, 40);
      expect(floor.height, 40);

      final claimed = <int>{};
      for (final face in layout.faces) {
        for (var j = 0; j < face.height; j++) {
          for (var i = 0; i < face.width; i++) {
            final texel = (face.y + j) * layout.width + face.x + i;
            expect(claimed.add(texel), isTrue, reason: 'texel $texel twice');
          }
        }
        expect(face.x, greaterThan(0));
        expect(face.y, greaterThan(1));
        expect(face.x + face.width, lessThan(layout.width));
        expect(face.y + face.height, lessThan(layout.height));
      }
      expect(
        claimed.contains(
          LightmapLayout.reservedY * layout.width + LightmapLayout.reservedX,
        ),
        isFalse,
      );
    });

    test('is the same twice', () {
      final a = LightmapLayout.plan(_room());
      final b = LightmapLayout.plan(_room());
      expect(a.width, b.width);
      expect(a.height, b.height);
      for (var i = 0; i < a.faces.length; i++) {
        expect(a.faces[i].x, b.faces[i].x);
        expect(a.faces[i].y, b.faces[i].y);
        expect(a.faces[i].brush, b.faces[i].brush);
      }
    });

    test('maps a texel to the world and back', () {
      final layout = LightmapLayout.plan(_room(), texelsPerMeter: 4.0);
      final floor = _floorTop(layout);
      final at = Vector3.zero();
      layout.texelCenter(floor, 3, 7, at);
      expect(at.y, closeTo(0.0, 1e-6));
      expect(layout.texelOf(floor, at), const LightmapTexel(x: 3, y: 7));
    });
  });

  group('the geometry', () {
    test('hands every vertex a coordinate inside its face', () {
      final level = _room();
      final layout = LightmapLayout.plan(level);
      final surfaces = const BrushGeometry().build(level, lightmap: layout);

      for (final surface in surfaces) {
        final uvs = surface.lightmapUvs;
        expect(uvs, isNotNull);
        expect(uvs!.length, surface.vertexCount * 2);
        for (var i = 0; i < uvs.length; i++) {
          expect(uvs[i], inInclusiveRange(0.0, 1.0));
        }
      }
      final without = const BrushGeometry().build(level);
      expect(without.every((s) => s.lightmapUvs == null), isTrue);
    });

    test('the floor corners land on the floor rectangle', () {
      final level = _room();
      final layout = LightmapLayout.plan(level);
      final floor = _floorTop(layout);
      final LightmapUv(u: u0, v: v0) = layout.uvAt(floor, -1.0, -1.0);
      final LightmapUv(u: u1, v: v1) = layout.uvAt(floor, 1.0, 1.0);
      expect(u0 * layout.width, closeTo(floor.x, 1e-6));
      expect(v0 * layout.height, closeTo(floor.y, 1e-6));
      expect(u1 * layout.width, closeTo(floor.x + floor.width, 1e-6));
      expect(v1 * layout.height, closeTo(floor.y + floor.height, 1e-6));
    });
  });
}
