/// The three things a viewport's chips do, without a viewport.
///
///     flutter test test/display_modes_test.dart
///
/// The picture these produce is checked in `frame_test.dart`, where a +Y face
/// in the normals view has to come out the colour of a +Y normal. What is here
/// is everything that has an answer before anything is drawn: where a named
/// view stands, that a lens switch keeps the model the size it was, and that a
/// shading mode can be switched back.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_modeler/src/display_modes.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Where the camera ends up once [view] has been asked for and the turn has
/// finished, relative to the point it is orbiting.
Vector3 _standing(OrbitController orbit, StandardView view) {
  lookFrom(orbit, view, seconds: 0.0);
  return orbit.node.readWorldPosition() - orbit.target;
}

void main() {
  group('a named view', () {
    test('stands where its name says', () {
      final orbit = OrbitController(SceneNode(), distance: 10.0);

      // Front is down −Z from +Z, and the rest are quarter turns from it. The
      // sign of the yaw is the assertion worth having: the gizmo's `−X` chip
      // and the `Right` menu item both come through here, and a quarter turn
      // the wrong way puts the key light on the far side of the model, which
      // reads as the model being wrong rather than the view.
      expect(_standing(orbit, StandardView.front).z, closeTo(10.0, 1e-6));
      expect(_standing(orbit, StandardView.back).z, closeTo(-10.0, 1e-6));
      expect(_standing(orbit, StandardView.right).x, closeTo(10.0, 1e-6));
      expect(_standing(orbit, StandardView.left).x, closeTo(-10.0, 1e-6));
      expect(_standing(orbit, StandardView.top).y, closeTo(10.0, 0.06));
      expect(_standing(orbit, StandardView.bottom).y, closeTo(-10.0, 0.06));
    });

    test('is level, whatever the camera was doing before', () {
      final orbit = OrbitController(SceneNode(), distance: 10.0, pitch: 1.0);

      // Mutation: have `lookFrom` pass only the yaw on to `animateTo`, on the
      // argument that a named view is about which way round the model is, and
      // `Front` from a camera that was looking down keeps looking down. A side
      // view that is not level is not a side view: it is what somebody measures
      // a wall against and gets a wrong answer from.
      final at = _standing(orbit, StandardView.front);
      expect(at.y, closeTo(0.0, 1e-6));
      expect(at.z, closeTo(10.0, 1e-6));
    });

    test('is the same view every time it is asked for', () {
      final orbit = OrbitController(SceneNode(), distance: 10.0, yaw: 2.0);
      final first = _standing(orbit, StandardView.top);
      orbit.rotate(300.0, 40.0);
      final again = _standing(orbit, StandardView.top);

      // Mutation: have `lookFrom` pass only the pitch on to `animateTo`, which
      // is what "keep the caller's yaw, a pure tilt is less disorienting" comes
      // out as — and this is a different picture each time, the model turned by
      // however far the last drag happened to go.
      expect((first - again).length, closeTo(0.0, 1e-6));
    });

    test('turns rather than jumps, unless asked for no time at all', () {
      final orbit = OrbitController(SceneNode(), yaw: 0.0);
      lookFrom(orbit, StandardView.back);

      expect(orbit.isTurning, isTrue);
      expect(orbit.yaw, closeTo(0.0, 1e-9));
      orbit.advance(1.0);
      expect(orbit.yaw.abs(), closeTo(math.pi, 1e-6));
    });
  });

  group('the lens', () {
    test('switching keeps the model the size it was', () {
      final camera = CameraNode();
      final orbit = OrbitController(camera, distance: 10.0);
      useLens(camera, ViewLens.perspective, orbit);
      final perspective = camera.projection as PerspectiveProjection;

      useLens(camera, ViewLens.orthographic, orbit);
      final ortho = camera.projection as OrthographicProjection;

      // What each lens shows at the depth the model is at. Mutation: hand
      // `OrthographicProjection` its own default height instead of the orbit's,
      // and switching to it shows two world units whatever was being looked at
      // — a model framed at ten metres vanishes and one framed at a centimetre
      // fills the screen.
      final shown =
          2.0 * orbit.distance * math.tan(perspective.fovYRadians / 2);
      expect(ortho.height, closeTo(shown, 1e-6));
    });

    test('switching back does not lose the field of view', () {
      final camera = CameraNode();
      final orbit = OrbitController(camera, distance: 4.0, framingFov: 0.6);
      useLens(camera, ViewLens.orthographic, orbit);
      useLens(camera, ViewLens.perspective, orbit);

      // Mutation: build the perspective lens with the constructor's default
      // rather than `orbit.framingFov`, and a viewport set to a narrow lens
      // widens to forty-five degrees the first time somebody looks at it
      // orthographically and back.
      expect(
        (camera.projection as PerspectiveProjection).fovYRadians,
        closeTo(0.6, 1e-9),
      );
    });
  });

  group('the shading', () {
    test('a wireframe is the renderer\'s business and the others are not', () {
      const base = RenderSettings();

      expect(settingsFor(ShadingMode.wireframe, base).wireframe, isTrue);
      expect(settingsFor(ShadingMode.material, base).wireframe, isFalse);
      // Mutation: ask for the wireframe in the normals view as well, on the
      // argument that both are diagnostic views — and every normal is then read
      // through a mesh of lines, which is the one thing that makes a colour
      // impossible to judge.
      expect(settingsFor(ShadingMode.normals, base).wireframe, isFalse);
    });

    test('normals can be switched back', () {
      final it = cpuTestDevice(width: 8, height: 8);
      final stage = ModelerStage.build(device: it.device);
      final shading = SurfaceShading();
      final MeshNode node = stage.subject as MeshNode;
      final Material own = node.material;

      shading.apply(stage.subject, ShadingMode.normals);
      expect(node.material.lighting, LightingModel.normals);

      shading.apply(stage.subject, ShadingMode.material);
      // Mutation: put back `SurfaceShading.normals` instead of the recorded
      // material — or record the material inside the swap, after it has already
      // been overwritten — and a person who looked at the normals once finds
      // their model grey for the rest of the session, with nothing in the undo
      // stack to explain it.
      expect(identical(node.material, own), isTrue);
    });

    test('a node that arrives late is swapped too', () {
      final it = cpuTestDevice(width: 8, height: 8);
      final stage = ModelerStage.build(device: it.device);
      final shading = SurfaceShading()
        ..apply(stage.subject, ShadingMode.normals);

      final arrived = MeshNode(
        (stage.subject as MeshNode).mesh,
        Material(name: 'late'),
        name: 'late',
      );
      stage.subject.add(arrived);
      shading.apply(stage.subject, ShadingMode.normals);

      // Mutation: return early from `apply` when the mode has not changed,
      // which is the obvious way to save the walk — and a model opened while
      // the normals view is on is drawn with its own materials in a view that
      // exists to show normals.
      expect(arrived.material.lighting, LightingModel.normals);

      shading.apply(stage.subject, ShadingMode.material);
      expect(arrived.material.name, 'late');
    });

    test('forgetting lets a replaced subject go', () {
      final it = cpuTestDevice(width: 8, height: 8);
      final stage = ModelerStage.build(device: it.device);
      final shading = SurfaceShading()
        ..apply(stage.subject, ShadingMode.normals)
        ..forget();

      // Back to where a fresh one starts, so the next model is asked about from
      // scratch rather than measured against the last one's answer.
      expect(shading.mode, ShadingMode.material);
    });
  });
}
