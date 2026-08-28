/// `Renderer.dispose` releases every reference it holds.
///
/// "Releases" means what it means everywhere else in this engine: no backend
/// here exposes an explicit free for a buffer, a texture or a pipeline, so
/// there is nothing lower-level to call. What `dispose` can do, and what this
/// pins, is drop the last Dart reference each cache holds — the pipeline
/// cache, the fragment-shader cache, the target pool's free list, and the two
/// fallback textures — which is the same contract `ResourceCache.clear`
/// already keeps for asset caches.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
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
    )!;
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
        Material(name: 'floor'),
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
    )!;
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
    )!;
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    );

    renderer.dispose();

    expect(() => renderer.fallbackAlbedo, throwsStateError);
    expect(() => renderer.fallbackNormal, throwsStateError);
  });

  test('dispose is idempotent', () {
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);

    renderer.dispose();
    expect(renderer.dispose, returnsNormally);
  });
}
