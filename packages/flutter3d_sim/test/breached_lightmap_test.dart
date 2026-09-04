/// A rocket through one wall leaves the light on the others.
///
///     dart test test/breached_lightmap_test.dart
///
/// A lightmap is planned by brush index, and a breach puts up to six pieces
/// where one brush was — so every index past the hole shifts. The rebuild used
/// to answer that by dropping the atlas altogether, which took the bake off
/// every wall in the level: one rocket into a corridor, and the light in every
/// room changed at once.
///
/// `Breaches.origins` is the way back. Each piece remembers the brush it was
/// cut out of, and `BrushGeometry.build` measures the piece's face inside the
/// planned face it is part of — so a wall the hole missed keeps exactly the
/// texels it had, a wall it cut keeps them everywhere but the cut, and the
/// surfaces the cut made, which nothing ever baked, take the neutral texel.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Two free-standing walls, twelve metres apart, with nothing else to cull a
/// face against.
///
/// **The one the hole cuts is written first on purpose.** A cut puts its
/// pieces where the brush was, so everything after it moves down the list —
/// and the far wall, which nothing touches, is the brush whose index changes.
/// Written the other way round it would keep its index by luck, and the test
/// that matters here would pass against a build that had learnt nothing.
Level _walls() => Level(
  brushes: <Brush>[
    Brush(centre: Vector3(6.0, 2.0, 0.0), size: Vector3(4.0, 4.0, 1.0)),
    Brush(centre: Vector3(-6.0, 2.0, 0.0), size: Vector3(4.0, 4.0, 1.0)),
  ],
);

/// The hole: straight through the middle of the second wall.
final Aabb3 _hole = Aabb3.minMax(
  Vector3(5.0, 1.0, -1.0),
  Vector3(7.0, 3.0, 1.0),
);

/// One vertex as this test asks about it: where it is, which way its face
/// looks, and where in the atlas it reads. Flat arrays are what a surface
/// carries, and a lightmap question is asked a vertex at a time.
typedef Vertex = ({Vector3 at, Vector3 normal, double u, double v});

List<Vertex> _vertices(List<BrushSurface> surfaces) => <Vertex>[
  for (final surface in surfaces)
    for (var i = 0; i < surface.vertexCount; i++)
      (
        at: Vector3(
          surface.positions[i * 3],
          surface.positions[i * 3 + 1],
          surface.positions[i * 3 + 2],
        ),
        normal: Vector3(
          surface.normals[i * 3],
          surface.normals[i * 3 + 1],
          surface.normals[i * 3 + 2],
        ),
        u: surface.lightmapUvs![i * 2],
        v: surface.lightmapUvs![i * 2 + 1],
      ),
];

/// The vertices of the faces looking towards +Z — the front of both walls,
/// and the one face of a piece that is part of a face the atlas planned.
List<Vertex> _frontFaces(List<BrushSurface> surfaces) => <Vertex>[
  for (final vertex in _vertices(surfaces))
    if (vertex.normal.z > 0.5) vertex,
];

void main() {
  final geometry = const BrushGeometry();

  group('which wall a piece came out of', () {
    test('is itself, until something cuts it', () {
      final level = _walls();
      final world = CollisionWorld();
      level.addTo(world);

      expect(Breaches(level, world).origins, <int>[0, 1]);
    });

    test('and the wall it was cut from afterwards', () {
      // Mutation: leave `origins` alone in `_apply`. It goes on saying
      // `[0, 1]` for five brushes, and the geometry reads past its end or
      // hands a piece of the second wall the first wall's texels.
      final level = _walls();
      final world = CollisionWorld();
      level.addTo(world);
      final breaches = Breaches(level, world)..hole(_hole);

      expect(breaches.brushes, hasLength(5));
      expect(breaches.origins, hasLength(breaches.brushes.length));
      expect(breaches.origins, <int>[
        0,
        0,
        0,
        0,
        1,
      ], reason: 'four pieces of the wall it cut, then the wall it missed');
    });

    test('and a piece cut again still names the wall it started as', () {
      final level = _walls();
      final world = CollisionWorld();
      level.addTo(world);
      final breaches = Breaches(level, world)
        ..hole(_hole)
        ..hole(Aabb3.minMax(Vector3(4.2, 1.0, -1.0), Vector3(4.8, 3.0, 1.0)));

      expect(breaches.origins.every((int it) => it == 0 || it == 1), isTrue);
      expect(breaches.origins.last, 1, reason: 'the wall neither hole reached');
      expect(
        breaches.origins.where((int it) => it == 0).length,
        greaterThan(4),
        reason: 'a piece cut again is two pieces of the same wall',
      );
    });

    test('and restoring puts the level back to naming itself', () {
      // Mutation: forget the `origins` reset in `restore`. A demo replayed
      // through a rocket then rebuilds against a list longer than the level.
      final level = _walls();
      final world = CollisionWorld();
      level.addTo(world);
      final breaches = Breaches(level, world)..hole(_hole);
      final saved = breaches.save();

      breaches.restore(<String, Object?>{});
      expect(breaches.origins, <int>[0, 1]);

      breaches.restore(saved);
      expect(breaches.origins, <int>[0, 0, 0, 0, 1]);
    });
  });

  group('the light after a breach', () {
    final level = _walls();
    final layout = LightmapLayout.plan(level);
    final whole = geometry.build(level, lightmap: layout);

    // Where a point on an unbroken wall's front face reads, said by that
    // face's own four corners rather than by restating the layout's
    // arithmetic: the unwrap is planar, so the atlas coordinate is affine in
    // the world position and four corners fix it everywhere on the rectangle.
    (double, double) expectedAt(Vector3 point) {
      final corners = _frontFaces(
        whole,
      ).where((Vertex it) => (it.at.x < 0.0) == (point.x < 0.0)).toList();
      final left = corners.reduce(
        (Vertex a, Vertex b) => a.at.x < b.at.x ? a : b,
      );
      final right = corners.reduce(
        (Vertex a, Vertex b) => a.at.x > b.at.x ? a : b,
      );
      final low = corners.reduce(
        (Vertex a, Vertex b) => a.at.y < b.at.y ? a : b,
      );
      final high = corners.reduce(
        (Vertex a, Vertex b) => a.at.y > b.at.y ? a : b,
      );
      return (
        left.u +
            (right.u - left.u) /
                (right.at.x - left.at.x) *
                (point.x - left.at.x),
        low.v +
            (high.v - low.v) / (high.at.y - low.at.y) * (point.y - low.at.y),
      );
    }

    /// The level after the blast, drawn the way the bridge draws it: the
    /// atlas the level loaded with, and the way back to the brushes it was
    /// planned for.
    List<BrushSurface> rebuilt() {
      final world = CollisionWorld();
      level.addTo(world);
      final breaches = Breaches(level, world)..hole(_hole);
      return geometry.build(
        Level(name: level.name, brushes: breaches.brushes),
        lightmap: layout,
        origins: breaches.origins,
      );
    }

    test('stays exactly where it was on the wall nothing touched', () {
      // The whole point, and the one a picture would show: the far wall is
      // still lit by the bake, texel for texel, after a rocket went through
      // its neighbour.
      //
      // Mutation: look a face up by its own index in `placeOf` —
      // `layout.faceOf(face.brush, face.face)` rather than
      // `layout.faceOf(origins[face.brush], ...)`. Every index past the hole
      // has shifted, so the far wall reads a stranger's texels.
      final after = _frontFaces(
        rebuilt(),
      ).where((Vertex it) => it.at.x < 0.0).toList();
      expect(after, hasLength(4), reason: 'the untouched wall, front face');

      for (final vertex in after) {
        final (wantU, wantV) = expectedAt(vertex.at);
        expect(vertex.u, closeTo(wantU, 1e-6));
        expect(vertex.v, closeTo(wantV, 1e-6));
      }
    });

    test('and follows the pieces of the wall it did cut', () {
      // A piece's front face is a rectangle inside the planned one, so its
      // corners are nowhere near the planned corners and its place has to be
      // measured. Every one of them must read what the whole wall read there.
      //
      // Mutation: use `uvAt(at, su, sv)` for a measured face too. Each piece
      // then stretches the whole wall's atlas rectangle across itself, and
      // the four pieces of a breached wall each repeat the whole wall's light.
      final after = _frontFaces(
        rebuilt(),
      ).where((Vertex it) => it.at.x > 0.0).toList();
      expect(after, hasLength(16), reason: 'four pieces, four corners each');

      for (final vertex in after) {
        final (wantU, wantV) = expectedAt(vertex.at);
        expect(vertex.u, closeTo(wantU, 1e-6), reason: 'at ${vertex.at}');
        expect(vertex.v, closeTo(wantV, 1e-6), reason: 'at ${vertex.at}');
      }
    });

    test(
      'and the surfaces the blast made have none, because none was baked',
      () {
        // The inside of the hole: four faces at x = 5 and x = 7 that were solid
        // stone when the level was baked. They take the reserved texel.
        //
        // Mutation: drop the `isOnPlane` test from `placeOf`. The inside of the
        // hole then samples the wall's own front-face texels, which is the far
        // side of the wall's light wrapped around the cut.
        final inside = _vertices(rebuilt())
            .where(
              (Vertex it) =>
                  it.normal.x.abs() > 0.5 &&
                  ((it.at.x - 5.0).abs() < 1e-6 ||
                      (it.at.x - 7.0).abs() < 1e-6),
            )
            .toList();
        expect(inside, isNotEmpty);

        final (neutralU, neutralV) = layout.neutralUv;
        for (final vertex in inside) {
          expect(vertex.u, closeTo(neutralU, 1e-9), reason: 'at ${vertex.at}');
          expect(vertex.v, closeTo(neutralV, 1e-9), reason: 'at ${vertex.at}');
        }
      },
    );
  });

  group('the mode survives a cut', () {
    test('a wall that casts from both faces still does in pieces', () {
      // Mutation: `castsShadow: brush.castsShadow` in `subtractBox`. Every
      // piece comes back as an ordinary caster and the breached wall starts
      // leaking light along the seam the whole wall did not.
      final wall = Brush(
        centre: Vector3(6.0, 2.0, 0.0),
        size: Vector3(4.0, 4.0, 1.0),
        shadowCasting: ShadowCasting.doubleSided,
      );

      final pieces = subtractBox(wall, _hole);

      expect(pieces, hasLength(4));
      expect(
        pieces.every(
          (Brush it) => it.shadowCasting == ShadowCasting.doubleSided,
        ),
        isTrue,
      );
    });
  });
}
