/// A lightmap, from the unwrap to the bounce.
///
///     dart test test/lightmap_test.dart
///
/// A closed room with one lamp in it. The layout gives every visible face a
/// rectangle and no two overlap; the geometry hands each vertex a second
/// coordinate inside its face's rectangle; the direct bake lights the floor
/// under the lamp by inverse square and leaves the floor behind a pillar
/// dark; a bounce lights a corner the lamp cannot see; the sidecar round
/// trips; and two bakes are the same bytes.
library;

import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double cx, double cy, double cz, double sx, double sy, double sz) =>
    Brush(centre: Vector3(cx, cy, cz), size: Vector3(sx, sy, sz));

/// An 8 × 3 × 8 room: floor at y = 0, ceiling at y = 3, walls a metre
/// thick, all grey. Lit by one lamp in the middle, a metre and a half up.
Level _room({List<Brush> extra = const <Brush>[], double intensity = 10.0}) =>
    Level(
      name: 'a room',
      materials: <String, LevelMaterial>{
        'stone': LevelMaterial(baseColor: Vector4(0.6, 0.6, 0.6, 1.0)),
      },
      brushes:
          <Brush>[
                _box(0.0, -0.5, 0.0, 10.0, 1.0, 10.0),
                _box(0.0, 3.5, 0.0, 10.0, 1.0, 10.0),
                _box(-4.5, 1.5, 0.0, 1.0, 3.0, 10.0),
                _box(4.5, 1.5, 0.0, 1.0, 3.0, 10.0),
                _box(0.0, 1.5, -4.5, 8.0, 3.0, 1.0),
                _box(0.0, 1.5, 4.5, 8.0, 3.0, 1.0),
                ...extra,
              ]
              .map(
                (b) => Brush(centre: b.centre, size: b.size, material: 'stone'),
              )
              .toList(),
      lights: <LevelLight>[
        LevelLight(position: Vector3(0.0, 1.5, 0.0), intensity: intensity),
      ],
    );

/// The floor's upward face, which the layout planned.
LightmapFace _floorTop(LightmapLayout layout) =>
    layout.faces.singleWhere((f) => f.brush == 0 && f.normal.y > 0.5);

void main() {
  group('the layout', () {
    test('gives every visible face a rectangle, and no two overlap', () {
      final level = _room();
      final layout = LightmapLayout.plan(level, texelsPerMetre: 4.0);

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
      final layout = LightmapLayout.plan(_room(), texelsPerMetre: 4.0);
      final floor = _floorTop(layout);
      final at = Vector3.zero();
      layout.texelCentre(floor, 3, 7, at);
      expect(at.y, closeTo(0.0, 1e-6));
      expect(layout.texelOf(floor, at), (3, 7));
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
      final (u0, v0) = layout.uvAt(floor, -1.0, -1.0);
      final (u1, v1) = layout.uvAt(floor, 1.0, 1.0);
      expect(u0 * layout.width, closeTo(floor.x, 1e-6));
      expect(v0 * layout.height, closeTo(floor.y, 1e-6));
      expect(u1 * layout.width, closeTo(floor.x + floor.width, 1e-6));
      expect(v1 * layout.height, closeTo(floor.y + floor.height, 1e-6));
    });
  });

  group('a direct bake', () {
    test('lights the floor under the lamp by inverse square', () {
      final level = _room();
      final layout = LightmapLayout.plan(level, texelsPerMetre: 4.0);
      final map = const LightmapBaker(
        bounces: 0,
        includeDirect: true,
      ).bake(level, layout: layout);
      final floor = _floorTop(layout);
      final centre = Vector3.zero();

      // Right under the lamp: a metre and a half away, straight down, so
      // 10 / 1.5² = 4.44. Four metres away along the floor: the distance is
      // √(16 + 2.25) = 4.27 and the cosine 1.5 / 4.27, so 10 / 18.25 × 0.35.
      final (ci, cj) = layout.texelOf(floor, Vector3(0.0, 0.0, 0.0));
      final under = map.irradianceAt(floor.x + ci, floor.y + cj);
      expect(under.x, closeTo(10.0 / 2.25, 0.15));
      final (fi, fj) = layout.texelOf(floor, Vector3(4.0, 0.0, 0.0));
      final far = map.irradianceAt(floor.x + fi, floor.y + fj);
      expect(far.x, closeTo(10.0 / 18.25 * (1.5 / 4.272), 0.05));
      layout.texelCentre(floor, ci, cj, centre);
      expect(centre.length, lessThan(0.2));
    });

    test('leaves the floor behind a pillar dark', () {
      // A pillar between the lamp and the east end of the floor.
      final level = _room(extra: <Brush>[_box(2.0, 1.5, 0.0, 0.5, 3.0, 1.0)]);
      final layout = LightmapLayout.plan(level, texelsPerMetre: 4.0);
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
      final layout = LightmapLayout.plan(level, texelsPerMetre: 2.0);
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
      expect(again.texelsPerMetre, map.texelsPerMetre);
      expect(again.levelHash, map.levelHash);
      expect(again.pixels, map.pixels);
      expect(again.isStaleFor(level), isFalse);
    });

    test('is stale for a level whose lamp moved', () {
      final map = const LightmapBaker(bounces: 0).bake(_room());
      final moved = _room()..lights.first.position.x += 1.0;
      expect(map.isStaleFor(moved), isTrue);
    });

    test('refuses the wrong magic and a short file', () {
      final map = const LightmapBaker(bounces: 0).bake(_room());
      final bytes = map.toBytes();
      expect(
        () => Lightmap.fromBytes(Uint8List.sublistView(bytes, 0, 12)),
        throwsFormatException,
      );
      final wrong = Uint8List.fromList(bytes)..[0] = 0;
      expect(() => Lightmap.fromBytes(wrong), throwsFormatException);
    });

    test('RGBM holds a bright texel and a dim one to a percent', () {
      final map = Lightmap(
        width: 2,
        height: 1,
        texelsPerMetre: 1.0,
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
