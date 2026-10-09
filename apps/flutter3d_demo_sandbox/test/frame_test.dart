/// The sandbox drawn: the picture, not the simulation — a frame of the
/// fresh world through the software backend, and a chunk drawn again after
/// an edit.
///
///     flutter test test/frame_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_sandbox/src/chunk_meshes.dart';
import 'package:flutter3d_demo_sandbox/src/staging.dart';
import 'package:flutter3d_game_kit/world.dart' show Daylight;
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a fresh world draws hills against the sky', () async {
    final it = cpuTestDevice(width: 160, height: 90);
    final renderer = Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    );
    final run = SandboxRun.fresh(backend: const DartPhysics());
    final camera = CameraNode(name: 'eye');
    final scene = Scene()
      ..ambientIntensity = 0.35 * Photometric.legacyUnit
      ..add(LightNode(name: 'sun')..setLocalForward(Vector3(-0.4, -1, -0.3)))
      ..add(camera);
    final meshes = ChunkMeshes(it.device, scene, run.blocks);
    expect(meshes.nodeCount, greaterThan(16));
    run.walk.pitch = -0.3;
    run.walk.placeCamera(camera);

    final result = renderer.render(
      width: 160,
      height: 90,
      scene: scene,
      views: <RenderView>[
        RenderView(camera: camera, clearColorSrgb: Vector4(0.55, 0.72, 0.9, 1)),
      ],
      settings: const RenderSettings(),
    );
    expect(result.drawCalls, greaterThan(0));
    final rgba = (await it.device.readback(result.frame)).buffer.asUint8List();
    // The bottom row is ground, the top row sky: two colours, the sky blue.
    int at(int x, int y, int channel) => rgba[(y * 160 + x) * 4 + channel];
    expect(at(80, 2, 2), greaterThan(at(80, 2, 0)), reason: 'blue sky');
    expect(
      (at(80, 87, 0) - at(80, 2, 0)).abs() +
          (at(80, 87, 2) - at(80, 2, 2)).abs(),
      greaterThan(40),
      reason: 'the ground is not the sky',
    );
  });

  test(
    'the morning sky is blue overhead, and the midnight one has stars',
    () async {
      // The sky alone, looked at straight up through the day's own settings.
      Future<Uint8List> skyAt(double hour) async {
        final it = cpuTestDevice(width: 96, height: 72);
        final renderer = Renderer.create(
          device: it.device,
          fallbackAlbedo: it.albedo,
          fallbackNormal: it.normal,
        );
        final camera = CameraNode(name: 'eye')
          ..lookAt(Vector3(0.0, 1.0, 0.0), up: Vector3(0.0, 0.0, -1.0));
        final result = renderer.render(
          width: 96,
          height: 72,
          scene: Scene()..add(camera),
          views: <RenderView>[RenderView(camera: camera)],
          settings: RenderSettings(sky: Daylight(hour: hour).sky),
        );
        return (await it.device.readback(result.frame)).buffer.asUint8List();
      }

      final morning = await skyAt(Daylight.morning);
      final middle = (36 * 96 + 48) * 4;
      expect(morning[middle + 2], greaterThan(morning[middle] + 40));

      // Mutation: a sun that stays up at midnight — the angle measured from
      // midnight rather than from sunrise — puts the stars out.
      final night = await skyAt(0.0);
      var stars = 0;
      var dark = 0;
      for (var i = 0; i < night.length; i += 4) {
        final light = night[i] + night[i + 1] + night[i + 2];
        if (light > 120) stars++;
        if (light < 30) dark++;
      }
      expect(dark, greaterThan(96 * 72 * 9 ~/ 10), reason: 'a night sky');
      expect(stars, greaterThan(3), reason: 'with stars in it');
    },
  );

  test('an edit draws again the chunks it changed, and only those', () {
    final it = cpuTestDevice();
    final run = SandboxRun.fresh(backend: const DartPhysics());
    final scene = Scene();
    final meshes = ChunkMeshes(it.device, scene, run.blocks);
    final chunk = (x: 1, y: 0, z: 1);
    final before = meshes.nodesOf(chunk);
    final elsewhere = meshes.nodesOf((x: 3, y: 0, z: 3));
    var top = run.blocks.sizeY - 1;
    while (!run.blocks.isSolid(20, top, 20)) {
      top--;
    }
    run.blocks.edit(20, top + 1, 20, Voxels.firstPlaced + 2);
    meshes.refresh(run.blocks.drainChanges().surfaces);

    // Mutation: refreshing without taking the old nodes out of the scene
    // leaves them drawn under the new ones.
    expect(meshes.nodesOf(chunk), isNot(before));
    expect(meshes.nodesOf(chunk).length, before.length + 1, reason: 'gold');
    expect(meshes.nodesOf((x: 3, y: 0, z: 3)), elsewhere);
    for (final node in before) {
      expect(node.parent, isNull);
    }
  });
}
