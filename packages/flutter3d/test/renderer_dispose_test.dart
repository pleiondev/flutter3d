/// `Renderer.dispose` releases every reference it holds.
///
/// It drops the last Dart reference each cache holds — the pipeline cache,
/// the fragment-shader cache, the target pool's free list, and the two
/// fallback textures — which is the same contract `ResourceCache.clear`
/// already keeps for asset caches, and gives every pipeline it built back to
/// the device through `PipelineHandle.dispose`, which a backend with driver
/// pipelines answers with `releasePipeline`. So does a reload of the shaders,
/// once the frames in flight are done with the old ones.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_core/src/engine/geometry/device_mesh.dart';
import 'package:flutter3d_core/src/engine/render/material.dart';
import 'package:flutter3d_core/src/engine/render/render_view.dart';
import 'package:flutter3d_core/src/engine/render/renderer.dart';
import 'package:flutter3d_core/src/engine/scene/camera_node.dart';
import 'package:flutter3d_core/src/engine/scene/mesh_node.dart';
import 'package:flutter3d_core/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dispose clears the pipeline cache', () {
    final device = FakeBackend();
    final texel = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData(4),
    );
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    );

    final scene = Scene(name: 'dispose');
    final camera = CameraNode(name: 'eye');
    scene.root.add(camera);
    scene.add(
      MeshNode(
        DeviceMesh.upload(
          device,
          const PlaneShape(width: 4.0, depth: 4.0).build(),
        ),
        RenderMaterial(name: 'floor'),
        name: 'floor',
      ),
    );

    renderer.render(
      width: 32,
      height: 32,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
    );
    expect(
      renderer.pipelineCount,
      greaterThan(0),
      reason: 'drawing the floor should have built its pipeline',
    );

    renderer.dispose();

    expect(renderer.pipelineCount, 0);
  });

  test('dispose trims the target pool', () {
    final device = FakeBackend();
    final texel = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData(4),
    );
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    );
    final scene = Scene(name: 'dispose-pool');
    scene.root.add(CameraNode(name: 'eye'));

    // Frames after the first hand textures the ring no longer needs back to
    // the pool, so a second frame is what gives `dispose` a free list with
    // something in it to trim.
    for (var i = 0; i < 2; i++) {
      renderer.render(
        width: 32,
        height: 32,
        scene: scene,
        views: <RenderView>[RenderView(camera: scene.cameras.single)],
      );
      device.finishOldestFrame();
    }
    renderer.render(
      width: 32,
      height: 32,
      scene: scene,
      views: <RenderView>[RenderView(camera: scene.cameras.single)],
    );

    renderer.dispose();

    expect(renderer.targetPool.pooledCount, 0);
  });

  test('dispose releases the fallback textures; reading either after is a '
      'bug that throws rather than one that returns a stale texture', () {
    final device = FakeBackend();
    final texel = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData(4),
    );
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    );

    renderer.dispose();

    expect(() => renderer.fallbackAlbedo, throwsStateError);
    expect(() => renderer.fallbackNormal, throwsStateError);
  });

  test('dispose gives every pipeline it built back to the device', () {
    // Mutation: drop the release from `dispose` — the fake still holds every
    // pipeline the frame linked.
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final drawn = _floor(device);
    renderer.render(
      width: 32,
      height: 32,
      scene: drawn.scene,
      views: <RenderView>[RenderView(camera: drawn.camera)],
    );
    expect(_livePipelines(device), greaterThan(0));

    renderer.dispose();

    expect(_livePipelines(device), 0);
  });

  test('a shader reload gives the old pipelines back after the frames '
      'in flight', () {
    // Mutation: clear the caches in `relinkShaders` without retiring what
    // they held — each reload adds a full set of live pipelines.
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final drawn = _floor(device);
    void frame() => renderer.render(
      width: 32,
      height: 32,
      scene: drawn.scene,
      views: <RenderView>[RenderView(camera: drawn.camera)],
    );
    for (var i = 0; i < 4; i++) {
      frame();
    }
    final settled = _livePipelines(device);

    renderer.relinkShaders();
    for (var i = 0; i < 4; i++) {
      frame();
    }

    expect(_livePipelines(device), lessThanOrEqualTo(settled));
  });

  test('dispose is idempotent', () {
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);

    renderer.dispose();
    expect(renderer.dispose, returnsNormally);
  });
}

int _livePipelines(FakeBackend device) =>
    device.liveHandles.whereType<PipelineHandle>().length;

/// A camera over a plane, on [device].
({Scene scene, CameraNode camera}) _floor(FakeBackend device) {
  final scene = Scene(name: 'floor');
  final camera = CameraNode(name: 'eye');
  scene.root.add(camera);
  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        const PlaneShape(width: 4.0, depth: 4.0).build(),
      ),
      RenderMaterial(name: 'floor'),
      name: 'floor',
    ),
  );
  return (scene: scene, camera: camera);
}
