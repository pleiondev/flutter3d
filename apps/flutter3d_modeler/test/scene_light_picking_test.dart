/// `mat-24`'s own light-marker picking: a ray against a list of positions,
/// sized in screen pixels the way a gizmo arrow already is.
///
///     flutter test test/scene_light_picking_test.dart
library;

import 'package:flutter3d_modeler/src/scene_light_picking.dart';
import 'package:flutter3d_modeler/src/transform_gizmo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('a single marker', () {
    test('a ray straight at it is picked', () {
      final view = GizmoView(eye: Vector3.zero(), pixel: 0.01);
      final index = pickLightMarker(
        positions: <Vector3>[Vector3(0, 0, -5)],
        eye: Vector3.zero(),
        along: Vector3(0, 0, -1),
        view: view,
      );

      expect(index, 0);
    });

    test('a ray that passes well wide of it picks nothing', () {
      final view = GizmoView(eye: Vector3.zero(), pixel: 0.01);
      final index = pickLightMarker(
        positions: <Vector3>[Vector3(0, 0, -5)],
        eye: Vector3.zero(),
        along: Vector3(1, 0, 0),
        view: view,
      );

      expect(index, isNull);
    });
  });

  group('several markers', () {
    test('the nearer of two markers on the same ray wins', () {
      final view = GizmoView(eye: Vector3.zero(), pixel: 0.01);
      final index = pickLightMarker(
        positions: <Vector3>[Vector3(0, 0, -10), Vector3(0, 0, -4)],
        eye: Vector3.zero(),
        along: Vector3(0, 0, -1),
        view: view,
      );

      // Mutation: return the first entry that hits rather than tracking the
      // nearest — index 0 is listed first and is also the far one, so this
      // fails unless the distance is actually compared.
      expect(index, 1);
    });

    test('a marker off to the side does not steal a ray aimed at another', () {
      final view = GizmoView(eye: Vector3.zero(), pixel: 0.01);
      final index = pickLightMarker(
        positions: <Vector3>[Vector3(0, 0, -5), Vector3(5, 5, -5)],
        eye: Vector3.zero(),
        along: Vector3(0, 0, -1),
        view: view,
      );

      expect(index, 0);
    });
  });

  group('marker size follows distance the way a gizmo arrow does', () {
    test(
      'the same offset from the ray misses a near marker and hits a far one',
      () {
        // At one world unit of distance a perspective `GizmoView` with this
        // `pixel` makes `kLightMarkerPixels` about 0.14 world units wide; at
        // ten units out the identical marker is ten times that, about 1.4 —
        // wide enough to catch a ray that a marker one tenth as close would
        // have let straight through.
        final view = GizmoView(eye: Vector3.zero(), pixel: 0.01);
        const offset = 0.4;

        final missesNear = pickLightMarker(
          positions: <Vector3>[Vector3(offset, 0, -1)],
          eye: Vector3.zero(),
          along: Vector3(0, 0, -1),
          view: view,
        );
        final hitsFar = pickLightMarker(
          positions: <Vector3>[Vector3(offset, 0, -10)],
          eye: Vector3.zero(),
          along: Vector3(0, 0, -1),
          view: view,
        );

        expect(missesNear, isNull);
        expect(hitsFar, 0);
      },
    );

    test('an orthographic view sizes every marker alike regardless of depth', () {
      final view = GizmoView(eye: Vector3.zero(), pixel: 0.05, perspective: false);
      const offset = 0.5;

      final near = pickLightMarker(
        positions: <Vector3>[Vector3(offset, 0, -1)],
        eye: Vector3.zero(),
        along: Vector3(0, 0, -1),
        view: view,
      );
      final far = pickLightMarker(
        positions: <Vector3>[Vector3(offset, 0, -50)],
        eye: Vector3.zero(),
        along: Vector3(0, 0, -1),
        view: view,
      );

      // Mutation: multiply the marker radius by distance even when the view
      // says it is not a perspective one — both would then disagree on
      // whether `offset` is inside the marker, and this catches it because
      // an orthographic view must answer the same either way.
      expect(near, far);
    });
  });

  test('no positions at all picks nothing', () {
    final view = GizmoView(eye: Vector3.zero(), pixel: 0.01);
    final index = pickLightMarker(
      positions: const <Vector3>[],
      eye: Vector3.zero(),
      along: Vector3(0, 0, -1),
      view: view,
    );

    expect(index, isNull);
  });
}
