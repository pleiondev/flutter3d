/// `pro-rt-03`'s own wiring half, without a screen: which two objects a quad
/// is drawn between, and what of them lands on the glass.
///
///     flutter test test/retopo_draw_test.dart
library;

import 'package:flutter3d_core/geometry.dart' show Ray;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/retopo_draw.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

bool _always(int _) => true;

/// A camera looking down −Z from the origin, as plainly as one can be
/// written: what is in front lands at its own x and y, what is behind is not
/// on the glass at all.
Offset? _lookDownZ(vm.Vector3 world) =>
    world.z < 0 ? Offset(world.x, world.y) : null;

void main() {
  group('RetopoDraw.pairFor', () {
    test('the last picked is drawn onto, the one before it is traced', () {
      // Mutation: read the pair the other way round. `DrawQuad` then adds
      // its faces to the high mesh and pulls them onto the low one.
      expect(RetopoDraw().pairFor(const <int>[7, 3], _always), (
        sourceId: 7,
        targetId: 3,
      ));
      // Three selected: still the last two, since "active" is the last.
      expect(RetopoDraw().pairFor(const <int>[1, 7, 3], _always), (
        sourceId: 7,
        targetId: 3,
      ));
    });

    test('one object, or none, is no pair', () {
      expect(RetopoDraw().pairFor(const <int>[3], _always), isNull);
      expect(RetopoDraw().pairFor(const <int>[], _always), isNull);
    });

    test('the target alone goes on meaning the pair, since DrawQuad leaves '
        'exactly that selected', () {
      final draw = RetopoDraw()..pairFor(const <int>[7, 3], _always);

      // Mutation: forget. The first quad lands, the selection is the target
      // alone, and the second quad of a retopology cannot be drawn without
      // going back to select both objects again.
      expect(draw.pairFor(const <int>[3], _always), (sourceId: 7, targetId: 3));

      // But only that. The source alone is a different thing to have
      // selected, and a source deleted since is not traced over.
      expect(draw.pairFor(const <int>[7], _always), isNull);
      draw.pairFor(const <int>[7, 3], _always);
      expect(draw.pairFor(const <int>[3], (int id) => id != 7), isNull);
    });

    test('a different pair abandons the quad in progress', () {
      final draw = RetopoDraw()
        ..pairFor(const <int>[7, 3], _always)
        ..corners.add(vm.Vector3.zero());

      // The same pair, reached the other way, keeps it…
      draw.pairFor(const <int>[3], _always);
      expect(draw.corners, hasLength(1));

      // …and another surface does not: a corner is a point on the one that
      // was being traced.
      draw.pairFor(const <int>[8, 3], _always);
      expect(draw.corners, isEmpty);
    });
  });

  group('what lands on the glass', () {
    test('every face in front of the camera, as its own corners', () {
      final EditMesh cube = EditMesh.cuboid();
      final toWorld = vm.Matrix4.translationValues(0, 0, -5);

      final faces = retopoFacesOnScreen(cube, toWorld, _lookDownZ);
      expect(faces, hasLength(6));
      expect(faces.every((List<Offset> it) => it.length == 4), isTrue);
    });

    test('a face with a corner behind the camera is left out whole', () {
      // The cube straddles the camera: its far face is all in front, its
      // near face all behind, and the four sides have two corners each way.
      // Mutation: skip the missing corners and close the polygon through
      // what is left. Four wedges are drawn across the picture.
      final faces = retopoFacesOnScreen(
        EditMesh.cuboid(),
        vm.Matrix4.identity(),
        _lookDownZ,
      );
      expect(faces, hasLength(1));
    });

    test('and never more than the budget', () {
      final faces = retopoFacesOnScreen(
        EditMesh.cuboid(),
        vm.Matrix4.translationValues(0, 0, -5),
        _lookDownZ,
        budget: 2,
      );
      expect(faces, hasLength(2));
    });

    test('the open quad stops at the first corner the camera cannot see', () {
      final corners = <vm.Vector3>[
        vm.Vector3(1, 2, -1),
        vm.Vector3(3, 4, 1),
        vm.Vector3(5, 6, -1),
      ];
      expect(retopoCornersOnScreen(corners, _lookDownZ), const <Offset>[
        Offset(1, 2),
      ]);
    });
  });

  group('the surface a click is cast against', () {
    test('is where the object stands, not where its mesh was made', () {
      final draw = RetopoDraw();
      final EditMesh cube = EditMesh.cuboid();
      final surface = draw.surfaceFor(
        cube,
        vm.Matrix4.translationValues(10, 0, 0),
        1,
      );

      // Mutation: build it in the mesh's own space. A click on the cube
      // where it is drawn misses, and one on empty space ten units to the
      // left hits.
      final down = Ray(vm.Vector3(10, 5, 0), vm.Vector3(0, -1, 0));
      expect(surface.raycast(down), isNotNull);
      final atOrigin = Ray(vm.Vector3(0, 5, 0), vm.Vector3(0, -1, 0));
      expect(surface.raycast(atOrigin), isNull);
    });

    test('is kept between clicks, and rebuilt when the version moves', () {
      final draw = RetopoDraw();
      final EditMesh cube = EditMesh.cuboid();
      final at = vm.Matrix4.identity();

      final first = draw.surfaceFor(cube, at, 1);
      expect(identical(draw.surfaceFor(cube, at, 1), first), isTrue);
      expect(identical(draw.surfaceFor(cube, at, 2), first), isFalse);
    });
  });
}
