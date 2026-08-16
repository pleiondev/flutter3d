/// A brush with a corner cut off, in the document and in the triangles.
///
///     flutter test test/ramp_brush_test.dart
///
/// The level format has said, since it was written, that "there are no slopes,
/// and vertical movement comes from stairs and lifts". That was a decision
/// about authoring — a brush is what an editor drags out in two clicks — and it
/// held until the collision world stopped moving bodies by their bounding boxes
/// and a shape could report a face that is not an axis.
///
/// **A ramp is not a new kind of thing in the document.** Same centre, same
/// size, same material, same surface, one more word. There is no angle: the cut
/// runs corner to corner, so the steepness is the brush's own proportions and
/// an author reads it off the numbers already typed.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Level _level(List<Brush> brushes) => Level(
      name: 'ramps',
      materials: <String, LevelMaterial>{'stone': LevelMaterial()},
      brushes: brushes,
      entities: const <EntityDef>[],
    );

Brush _ramp({WedgeUphill uphill = WedgeUphill.positiveZ}) => Brush(
      centre: Vector3(0.0, 1.0, 4.0),
      size: Vector3(6.0, 2.0, 8.0),
      material: 'stone',
      ramp: uphill,
    );

void main() {
  group('in the document', () {
    test('a brush with no ramp is a block, as every level ever saved is', () {
      final brush = Brush(centre: Vector3.zero(), size: Vector3.all(2.0));

      expect(brush.isRamp, isFalse);
      expect(brush.ramp, isNull);
      expect(brush.toJson().containsKey('ramp'), isFalse,
          reason: 'a document that has nothing to say must say nothing');
    });

    test('and one that climbs says which way, and round-trips', () {
      final brush = _ramp(uphill: WedgeUphill.negativeX);
      final back = Brush.fromJson(brush.toJson());

      expect(brush.toJson()['ramp'], '-x');
      expect(back.ramp, WedgeUphill.negativeX);
      expect(back.centre, brush.centre);
      expect(back.size, brush.size);
    });

    test('a direction nobody recognises is refused, not ignored', () {
      // **The names are the format's, not the enum's.** Spelling them out means
      // renaming a Dart identifier cannot silently invalidate every level ever
      // saved — and a typo in a hand-edited document has to be an error, or a
      // ramp quietly becomes a block and the level becomes unfinishable.
      expect(
        () => Brush.fromJson(<String, Object?>{
          'at': <double>[0.0, 0.0, 0.0],
          'size': <double>[1.0, 1.0, 1.0],
          'ramp': 'up',
        }),
        throwsA(isA<LevelFormatException>()),
      );
    });
  });

  group('in the collision world', () {
    test('a ramp becomes a wedge and a block becomes a box', () {
      final world = CollisionWorld();
      _level(<Brush>[
        Brush(centre: Vector3(0.0, -0.5, 0.0), size: Vector3(20.0, 1.0, 20.0)),
        _ramp(),
      ]).addTo(world);

      // Through a query rather than a private list: a box big enough to reach
      // everything, which is what any caller has.
      final found = <Collider>[];
      world.update();
      world.overlap(CollisionBox(Vector3.all(50.0)), Vector3.zero(), found);
      final shapes = found.map((Collider c) => c.shape).toList();
      expect(shapes.whereType<CollisionBox>(), hasLength(1));
      expect(shapes.whereType<CollisionWedge>(), hasLength(1));
      expect(
        shapes.whereType<CollisionWedge>().single.uphill,
        WedgeUphill.positiveZ,
      );
    });
  });

  group('in the triangles', () {
    List<BrushSurface> surfaces(List<Brush> brushes) =>
        const BrushGeometry().build(_level(brushes));

    test('a ramp is five faces, and a block is six', () {
      // Two of the block's faces survive — the floor and the wall at the top of
      // the climb. The one at the thin end is gone entirely, which is the
      // corner being cut, and the sides become triangles.
      final block = surfaces(<Brush>[
        Brush(centre: Vector3(0.0, 1.0, 4.0), size: Vector3(6.0, 2.0, 8.0)),
      ]).single;
      final ramp = surfaces(<Brush>[_ramp()]).single;

      expect(block.triangleCount, 12, reason: 'six quads');
      // The floor, the wall at the top and the slope are quads; the two sides
      // are single triangles. Six and two.
      expect(ramp.triangleCount, 8);
    });

    test('and one of its faces is the slope', () {
      // The face that cannot exist on a block: a normal that is not an axis.
      final ramp = surfaces(<Brush>[_ramp()]).single;
      final wedge = CollisionWedge(
        Vector3(3.0, 1.0, 4.0),
        uphill: WedgeUphill.positiveZ,
      );

      var found = 0;
      for (var i = 0; i < ramp.vertexCount; i++) {
        final ny = ramp.normals[i * 3 + 1];
        final nz = ramp.normals[i * 3 + 2];
        if ((ny - wedge.slopeNormal.y).abs() < 1e-5 &&
            (nz - wedge.slopeNormal.z).abs() < 1e-5) {
          found++;
        }
      }

      expect(found, 4, reason: 'the slope is one quad, so four vertices');
    });

    test('every face winds outward, so none of them is a hole', () {
      // **A face wound the wrong way is culled as a back face**, which looks
      // like a hole and not like a mistake — and the two triangles are wound
      // from the geometry rather than from four cases worked out by hand, so
      // this is what says the working-out was right for all four directions.
      for (final uphill in WedgeUphill.values) {
        final ramp = surfaces(<Brush>[_ramp(uphill: uphill)]).single;

        for (var t = 0; t < ramp.triangleCount; t++) {
          final a = ramp.indices[t * 3];
          final b = ramp.indices[t * 3 + 1];
          final c = ramp.indices[t * 3 + 2];
          Vector3 at(int i) => Vector3(
                ramp.positions[i * 3],
                ramp.positions[i * 3 + 1],
                ramp.positions[i * 3 + 2],
              );
          final winding = (at(b) - at(a)).cross(at(c) - at(a));
          final normal = Vector3(
            ramp.normals[a * 3],
            ramp.normals[a * 3 + 1],
            ramp.normals[a * 3 + 2],
          );

          expect(winding.dot(normal), greaterThan(0.0),
              reason: '$uphill: triangle $t faces backwards');
        }
      }
    });

    test('and every normal points out of the solid, not into it', () {
      // **The winding test above cannot catch a whole ramp built inside out**:
      // it checks that the corners agree with the normal they were given, which
      // is true of a face and of its mirror image. This asks the shape instead
      // — a step along the normal from any vertex has to leave the wedge — and
      // it is the assertion that would fail if the slope's normal were negated.
      for (final uphill in WedgeUphill.values) {
        final brush = _ramp(uphill: uphill);
        final ramp = surfaces(<Brush>[brush]).single;
        final wedge = CollisionWedge(brush.halfExtents, uphill: uphill);

        for (var i = 0; i < ramp.vertexCount; i++) {
          final outward = Vector3(
            ramp.positions[i * 3] + ramp.normals[i * 3] * 0.05,
            ramp.positions[i * 3 + 1] + ramp.normals[i * 3 + 1] * 0.05,
            ramp.positions[i * 3 + 2] + ramp.normals[i * 3 + 2] * 0.05,
          );
          expect(wedge.containsPoint(brush.centre, outward), isFalse,
              reason: '$uphill: vertex $i faces into the ramp');
        }
      }
    });

    test('and a ramp hides nothing behind it', () {
      // **Its box is half empty — that is what a ramp is.** Treating it as
      // solid in the hidden-face index culls a neighbour's face standing in the
      // air above the slope, and a hole in a wall is far worse than a triangle
      // nobody sees.
      final wall = Brush(
        centre: Vector3(0.0, 1.0, 4.0),
        size: Vector3(1.0, 2.0, 8.0),
        material: 'stone',
      );

      final alone = surfaces(<Brush>[wall]).single.triangleCount;
      final beside = surfaces(<Brush>[wall, _ramp()]);
      final wallNow = beside.single.triangleCount - 8;

      expect(wallNow, alone,
          reason: 'the ramp swallowed a face of the wall inside it');
    });
  });
}
