/// Point-shadow faces under the frame's allowance for deferred work — `N3`.
///
///     flutter test test/point_shadow_budget_test.dart
///
/// A torch over a floor with a slab in its light. Under an allowance of one
/// microsecond each frame draws the one face it must (the first piece of work
/// always runs) and puts the rest off; a face put off is not recorded as
/// drawn, so later frames come back for it, and once they have all been drawn
/// the picture is the one a renderer with no allowance drew on its first
/// frame. A scheduler that marked the refused faces clean would leave them
/// holding nothing, and the slab's shadow would be missing from the floor for
/// good.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 64;
const int _height = 48;

({Scene scene, CameraNode camera}) _room(CpuDevice device) {
  MeshNode block(Vector3 size, Vector3 at) => MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: size).build()),
    Material(baseColor: Vector4(0.8, 0.8, 0.8, 1.0)),
  )..setPosition(at.x, at.y, at.z);

  final scene = Scene()
    ..ambientIntensity = 0.0
    ..add(block(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0)))
    // Off to one side of the torch, so the faces it falls in are not the
    // first ones in the atlas: a budget that only ever drew the leading
    // faces would miss it.
    ..add(block(Vector3(1.2, 0.4, 1.2), Vector3(1.5, 2.0, 0.5)))
    ..add(
      LightNode(
        type: LightType.point,
        intensity: 60.0,
        range: 20.0,
        castsShadow: true,
      )..setPosition(0.0, 5.0, 0.0),
    );
  final camera = CameraNode()
    ..setPosition(0.0, 9.0, -9.0)
    ..lookAt(Vector3(0.0, 0.0, 0.5));
  return (scene: scene, camera: camera);
}

typedef _Engine = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  CameraNode camera,
});

_Engine _engine() {
  final it = cpuTestDevice(width: _width, height: _height);
  final room = _room(it.device);
  return (
    device: it.device,
    renderer: Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    ),
    scene: room.scene,
    camera: room.camera,
  );
}

Future<Uint8List> _frame(_Engine it, int allowance) async {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[RenderView(camera: it.camera)],
    settings: RenderSettings(
      bloom: const BloomSettings(enabled: false),
      frameWorkBudget: allowance,
    ),
  );
  final pixels = await it.device.readPixels(result.frame);
  return pixels!.buffer.asUint8List();
}

void main() {
  test(
    'faces the allowance refuses stay pending until they are drawn',
    () async {
      final free = _engine();
      final unlimited = await _frame(free, 0);

      final tight = _engine();
      final first = await _frame(tight, 1);
      // One face, the one a frame always gets; every other face asked and was
      // told to wait.
      expect(tight.renderer.frameWorkBudget.items, 1);
      expect(tight.renderer.frameWorkBudget.deferred, greaterThan(0));
      expect(
        first,
        isNot(unlimited),
        reason: 'a frame that drew one face drew the whole atlas',
      );

      // A face a frame, then nothing: the scene is still, so once every face
      // has been drawn there is nothing left to schedule.
      var frames = 1;
      var last = first;
      while (tight.renderer.frameWorkBudget.items > 0 && frames < 40) {
        last = await _frame(tight, 1);
        frames++;
      }
      expect(frames, lessThan(40), reason: 'the faces never ran out');
      expect(tight.renderer.frameWorkBudget.deferred, 0);

      // Mutation: record every selected face as drawn (`recordDrawn()` with no
      // argument in the point-shadow node). The refused faces are then never
      // drawn, the loop above ends after two frames, and the slab's shadow is
      // missing from this picture.
      expect(last, unlimited);
    },
  );

  test(
    'with no allowance every changed face is drawn in the one frame',
    () async {
      final it = _engine();
      await _frame(it, 0);
      expect(it.renderer.frameWorkBudget.deferred, 0);
      // A still scene: the second frame has no face to draw.
      await _frame(it, 0);
      expect(it.renderer.frameWorkBudget.items, 0);
    },
  );
}
