/// A lightmap baked, from the direct light to the bounce.
///
///     dart test test/lightmap_bake_test.dart
///
/// A closed room with one lamp in it. The direct bake lights the floor
/// under the lamp by inverse square and leaves the floor behind a pillar
/// dark; a bounce lights a corner the lamp cannot see; the sidecar round
/// trips; and two bakes are the same bytes.
library;

import 'dart:typed_data';

import 'package:flutter3d_build/lightmap.dart';
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
  group('a direct bake', () {
    test('lights the floor under the lamp by inverse square', () {
      final level = _room();
      final layout = LightmapLayout.plan(level, texelsPerMeter: 4.0);
      final map = const LightmapBaker(
        bounces: 0,
        includeDirect: true,
      ).bake(level, layout: layout);
      final floor = _floorTop(layout);
      final center = Vector3.zero();

      // Right under the lamp: a metre and a half away, straight down, so
      // 10 / 1.5² = 4.44. Four metres away along the floor: the distance is
      // √(16 + 2.25) = 4.27 and the cosine 1.5 / 4.27, so 10 / 18.25 × 0.35.
      final (ci, cj) = layout.texelOf(floor, Vector3(0.0, 0.0, 0.0));
      final under = map.irradianceAt(floor.x + ci, floor.y + cj);
      expect(under.x, closeTo(10.0 / 2.25, 0.15));
      final (fi, fj) = layout.texelOf(floor, Vector3(4.0, 0.0, 0.0));
      final far = map.irradianceAt(floor.x + fi, floor.y + fj);
      expect(far.x, closeTo(10.0 / 18.25 * (1.5 / 4.272), 0.05));
      layout.texelCenter(floor, ci, cj, center);
      expect(center.length, lessThan(0.2));
    });

    test('leaves the floor behind a pillar dark', () {
      // A pillar between the lamp and the east end of the floor.
      final level = _room(extra: <Brush>[_box(2.0, 1.5, 0.0, 0.5, 3.0, 1.0)]);
      final layout = LightmapLayout.plan(level, texelsPerMeter: 4.0);
      final map = const LightmapBaker(
        bounces: 0,
        includeDirect: true,
      ).bake(level, layout: layout);
      final floor = _floorTop(layout);

      final (si, sj) = layout.texelOf(floor, Vector3(3.5, 0.0, 0.0));
      final shadowed = map.irradianceAt(floor.x + si, floor.y + sj);
      final (li, lj) = layout.texelOf(floor, Vector3(-3.5, 0.0, 0.0));
      final lit = map.irradianceAt(floor.x + li, floor.y + lj);
      expect(shadowed.x, 0.0, reason: 'the pillar is between');
      expect(lit.x, greaterThan(0.1));
    });

    test('is empty with no direct term and no bounces', () {
      final level = _room();
      final map = const LightmapBaker(bounces: 0).bake(level);
      expect(map.pixels.every((byte) => byte == 0), isTrue);
    });
  });

  group('a bounce', () {
    test('lights the floor behind the pillar, which the lamp cannot', () {
      final level = _room(
        extra: <Brush>[_box(2.0, 1.5, 0.0, 0.5, 3.0, 1.0)],
        intensity: 20.0,
      );
      final layout = LightmapLayout.plan(level, texelsPerMeter: 2.0);
      final map = const LightmapBaker(
        bounces: 1,
        samples: 64,
      ).bake(level, layout: layout);
      final floor = _floorTop(layout);

      final (si, sj) = layout.texelOf(floor, Vector3(3.5, 0.0, 0.0));
      final behind = map.irradianceAt(floor.x + si, floor.y + sj);
      expect(behind.x, greaterThan(0.0), reason: 'the walls throw light there');
      // Grey walls: the bounce is grey.
      expect(behind.x, closeTo(behind.y, 1e-6));
      // And less than the direct light where the lamp shines.
      final (li, lj) = layout.texelOf(floor, Vector3(0.0, 0.0, 0.0));
      final direct = const LightmapBaker(
        bounces: 0,
        includeDirect: true,
      ).bake(level, layout: layout).irradianceAt(floor.x + li, floor.y + lj);
      expect(behind.x, lessThan(direct.x));
    });

    test('is the same bytes twice', () {
      final level = _room();
      final a = const LightmapBaker(bounces: 2, samples: 16).bake(level);
      final b = const LightmapBaker(bounces: 2, samples: 16).bake(level);
      expect(a.toBytes(), b.toBytes());
      expect(a.pixels.any((byte) => byte != 0), isTrue);
    });

    test('fills the reserved texel with the average', () {
      final level = _room();
      final map = const LightmapBaker(bounces: 1, samples: 16).bake(level);
      final reserved = map.irradianceAt(
        LightmapLayout.reservedX,
        LightmapLayout.reservedY,
      );
      expect(reserved.x, greaterThan(0.0));
    });
  });

  group('the sidecar', () {
    test('round trips', () {
      final level = _room();
      final map = const LightmapBaker(bounces: 1, samples: 8).bake(level);
      final again = Lightmap.fromBytes(map.toBytes());

      expect(again.width, map.width);
      expect(again.height, map.height);
      expect(again.texelsPerMeter, map.texelsPerMeter);
      expect(again.levelHash, map.levelHash);
      expect(again.pixels, map.pixels);
      expect(again.isStaleFor(level), isFalse);
    });

    test('is stale for a level whose lamp moved', () {
      final map = const LightmapBaker(bounces: 0).bake(_room());
      final moved = _room()..lights.first.position.x += 1.0;
      expect(map.isStaleFor(moved), isTrue);
    });

    // The density is the one number the sidecar narrows: `toBytes` writes it
    // as float32 and the loader re-plans from what it read. 1.2 is the case
    // that shows why it matters — `1.2 * 10` ceils to 12 and
    // `1.2000000476837158 * 10` to 13, so the ten-metre floor would come
    // back one texel wider and every shelf under it would move. Mutation:
    // dropping the `Float32List` narrowing at the top of `LightmapLayout.plan`
    // makes the baked and the re-planned atlas disagree, and both the width
    // and the per-face expectations report false.
    test('plans the same atlas from the density it read back', () {
      final level = _room();
      const density = 1.2;
      final baked = const LightmapBaker(
        texelsPerMeter: density,
        bounces: 0,
      ).bake(level);
      final again = Lightmap.fromBytes(baked.toBytes());
      final replanned = LightmapLayout.plan(
        level,
        texelsPerMeter: again.texelsPerMeter,
      );

      expect(again.texelsPerMeter, isNot(density), reason: 'float32 narrows');
      expect(replanned.width, baked.width);
      expect(replanned.height, baked.height);
      final planned = LightmapLayout.plan(level, texelsPerMeter: density);
      for (final face in planned.faces) {
        final other = replanned.faceOf(face.brush, face.face);
        expect(other, isNotNull);
        expect(
          (other!.x, other.y, other.width, other.height),
          (face.x, face.y, face.width, face.height),
        );
      }
    });

    // A moulding stops nothing, so it never reaches the collision world —
    // but `LightmapLayout.plan` packs a rectangle for its faces all the same,
    // and every face packed after it moves. Mutation: dropping
    // `mix(brush.solid ? 'solid' : 'open')` and the whole-brush loop's reach
    // over non-solid brushes in `Lightmap.hashOf` — that is, restoring the
    // delegation to `LevelVisibility.hashBrushes`, which skips them — leaves
    // the hash equal and this expectation reports false.
    test('is stale for a level that grew a decorative moulding', () {
      final moulding = Brush(
        center: Vector3(0.0, 2.5, 3.0),
        size: Vector3(3.0, 0.3, 0.3),
        solid: false,
      );
      final map = const LightmapBaker(bounces: 0).bake(_room());
      final decorated = _room(extra: <Brush>[moulding]);
      // The layout really does change: this is what makes the map wrong.
      expect(
        LightmapLayout.plan(decorated).faces.length,
        greaterThan(LightmapLayout.plan(_room()).faces.length),
      );
      expect(map.isStaleFor(decorated), isTrue);
    });

    // Repainting is not moving: every box and both materials are untouched,
    // only which material the floor names. The bounce reads it through
    // `Level.materialFor`, so the map is wrong. Mutation: dropping
    // `mix(brush.material)` from `Lightmap.hashOf` leaves the hash equal and
    // this expectation reports false.
    test('is stale for a wall repainted from one material to another', () {
      final map = const LightmapBaker(bounces: 1, samples: 8).bake(_room());
      final repainted = _room(floorMaterial: 'soot');
      final dark = const LightmapBaker(
        bounces: 1,
        samples: 8,
      ).bake(repainted).pixels;
      expect(map.pixels, isNot(dark), reason: 'the bounce really did change');
      expect(map.isStaleFor(repainted), isTrue);
    });

    test('refuses the wrong magic and a short file', () {
      final map = const LightmapBaker(bounces: 0).bake(_room());
      final bytes = map.toBytes();
      expect(
        () => Lightmap.fromBytes(Uint8List.sublistView(bytes, 0, 12)),
        throwsA(isA<LightmapFormatException>()),
      );
      final wrong = Uint8List.fromList(bytes)..[0] = 0;
      expect(
        () => Lightmap.fromBytes(wrong),
        throwsA(isA<LightmapFormatException>()),
      );
    });

    test('RGBM holds a bright texel and a dim one to a percent', () {
      final map = Lightmap(
        width: 2,
        height: 1,
        texelsPerMeter: 1.0,
        levelHash: 0,
      );
      map.setIrradiance(0, 0, 6.0, 3.0, 0.5);
      map.setIrradiance(1, 0, 0.05, 0.02, 0.01);
      final bright = map.irradianceAt(0, 0);
      final dim = map.irradianceAt(1, 0);
      expect(bright.x, closeTo(6.0, 0.06));
      expect(bright.y, closeTo(3.0, 0.06));
      expect(bright.z, closeTo(0.5, 0.06));
      expect(dim.x, closeTo(0.05, 0.002));
      expect(dim.z, closeTo(0.01, 0.002));
    });
  });
}
