/// `ImpostorAtlas`/`ImpostorCard` — `pro-lod-05n`: the angles, their cells,
/// which one a camera is shown, and the card they are drawn on.
///
///     dart test test/impostor_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('the atlas', () {
    test('eight angles land in a 3×3 grid of square cells', () {
      final ImpostorAtlas atlas = ImpostorAtlas(size: 1024);
      expect(atlas.angles, 8);
      expect(atlas.views, hasLength(8));
      // **Square-ish, not a row.** Mutation: lay the eight out in one strip.
      // Each cell is then a letterbox a silhouette does not fill, and a tree
      // baked into it is a tree three pixels wide.
      expect(atlas.columns, 3);
      expect(atlas.rows, 3);
      expect(atlas.cellSize, 1024 ~/ 3);
    });

    test('and no two cells overlap', () {
      final ImpostorAtlas atlas = ImpostorAtlas();
      final List<ImpostorView> views = atlas.views;
      for (var i = 0; i < views.length; i++) {
        for (var j = i + 1; j < views.length; j++) {
          final AtlasCell a = views[i].cell;
          final AtlasCell b = views[j].cell;
          final bool apart =
              a.x + a.width <= b.x + 1e-9 ||
              b.x + b.width <= a.x + 1e-9 ||
              a.y + a.height <= b.y + 1e-9 ||
              b.y + b.height <= a.y + 1e-9;
          expect(apart, isTrue, reason: 'cells $i and $j overlap');
        }
      }
    });

    test('the angles go round the equator, evenly', () {
      final ImpostorAtlas atlas = ImpostorAtlas();
      for (var i = 0; i < atlas.angles; i++) {
        expect(atlas.viewAt(i).yaw, closeTo(i * math.pi / 4, 1e-9));
      }
    });

    test('and a camera for one of them stands level with the model', () {
      final ImpostorAtlas atlas = ImpostorAtlas();
      final Vector3 centre = Vector3(0, 3, 0);
      for (var i = 0; i < atlas.angles; i++) {
        final SnapshotCamera camera = atlas.cameraFor(
          i,
          centre: centre,
          distance: 20,
        );
        // **The pitch an impostor is baked at is the pitch it is honest at.**
        // Mutation: bake from above. Every card in the scene then looks like
        // a sticker of a tree seen from a helicopter.
        expect(camera.position.y, closeTo(centre.y, 1e-9));
        expect(camera.position.distanceTo(centre), closeTo(20, 1e-6));
        expect(camera.target, centre);
      }
    });

    test('an impostor of one angle is still an impostor', () {
      final ImpostorAtlas atlas = ImpostorAtlas(angles: 1, size: 256);
      expect(atlas.views, hasLength(1));
      expect(atlas.viewAt(0).cell.width, 1);
      expect(atlas.pick(3.0).view, 0);
    });

    test('and none at all is not', () {
      expect(() => ImpostorAtlas(angles: 0), throwsA(isA<AssertionError>()));
    });
  });

  group('picking a view', () {
    test(
      'takes the one the camera is standing in, with the blend beside it',
      () {
        final ImpostorAtlas atlas = ImpostorAtlas();
        final picked = atlas.pick(0);
        expect(picked.view, 0);
        expect(picked.next, 1);
        expect(picked.blend, closeTo(0, 1e-9));

        // Half way between the first two.
        final half = atlas.pick(math.pi / 8);
        expect(half.view, 0);
        expect(half.next, 1);
        // **The blend is what turns eight pictures into something that reads
        // as turning.** Mutation: snap to the nearest and answer nothing else.
        // A shader then has no way to cross-fade and the card flicks between
        // angles, which is the one thing everybody notices about impostors.
        expect(half.blend, closeTo(0.5, 1e-9));
      },
    );

    test('and wraps round rather than running off the end', () {
      final ImpostorAtlas atlas = ImpostorAtlas();
      final picked = atlas.pick(2 * math.pi - 0.01);
      expect(picked.view, 7);
      expect(picked.next, 0);
      expect(atlas.pick(2 * math.pi).view, 0);
      // A camera that has turned round three times is a camera pointing
      // somewhere, not an index out of range.
      expect(atlas.pick(7 * math.pi).view, inInclusiveRange(0, 7));
    });
  });

  group('the card', () {
    test('is as wide as it was asked for, whichever way it faces', () {
      const ImpostorCard card = ImpostorCard(width: 4, height: 9);
      for (final double yaw in <double>[0, 1, math.pi / 2, math.pi, 5.5]) {
        final List<Vector3> corners = card.cornersAt(Vector3.zero(), yaw);
        expect(corners, hasLength(4));
        expect(corners[0].distanceTo(corners[1]), closeTo(4, 1e-6));
        expect(corners[1].distanceTo(corners[2]), closeTo(9, 1e-6));
      }
    });

    test('and turns about the up axis only', () {
      const ImpostorCard card = ImpostorCard(width: 2, height: 2);
      final List<Vector3> corners = card.cornersAt(Vector3(0, 5, 0), 1.2);
      // **Mutation: point the card at the camera in three dimensions.** A
      // camera looking down then swings the card's own baked horizon into
      // view, and the picture and the view stop agreeing about where level
      // is — which is the whole trick.
      expect(corners[0].y, closeTo(4, 1e-9));
      expect(corners[1].y, closeTo(4, 1e-9));
      expect(corners[2].y, closeTo(6, 1e-9));
      expect(corners[3].y, closeTo(6, 1e-9));
    });

    test('and stands where it was put', () {
      const ImpostorCard card = ImpostorCard(width: 2, height: 2);
      final List<Vector3> corners = card.cornersAt(Vector3(7, 0, -3), 0.4);
      final Vector3 middle =
          (corners[0] + corners[1] + corners[2] + corners[3]) / 4;
      expect(middle.x, closeTo(7, 1e-6));
      expect(middle.z, closeTo(-3, 1e-6));
    });
  });

  test('it prints the atlas it stands for', () {
    expect(ImpostorAtlas().toString(), contains('8 angles'));
  });
}
