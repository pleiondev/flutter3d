/// `Renderer.relinkShaders` drops every pipeline the renderer linked, and the
/// next frame links each of them again.
///
/// The one headless place this is held. The pixel test in `flutter3d_webgl`
/// proves a reload changes the picture through one material pipeline; what it
/// cannot see is the other fourteen fields — the shadow, sky, bloom, composite
/// and debug-line pipelines the renderer holds beside its material cache —
/// and a regression that forgot one of them would leave that pass drawing the
/// old code with every check in the browser green.
///
/// So the check is the *linking*, not the picture: `FakeBackend` records every
/// pair it links, in order, and a frame after a relink has to link exactly the
/// set the first frame did. A field that was not cleared is a pipeline that is
/// not linked again, and the set says which.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Every kind of pass the renderer holds a pipeline for, in one frame: two
/// shadowed lights so the map and the cube atlas are both drawn, a skinned and
/// an instanced caster so their shadow stages link beside the static one, a
/// gradient sky, bloom, and a debug overlay for the line pipeline.
const RenderSettings _everything = RenderSettings(
  sky: SkySettings(enabled: true),
  bloom: BloomSettings(intensity: 1.0),
  debug: DebugDrawOptions(bounds: true, lightGizmos: true),
);

({Scene scene, CameraNode camera, MeshNode box}) _scene(FakeBackend device) {
  final scene = Scene(name: 'relink');

  scene.add(
    MeshNode(
      DeviceMesh.upload(
        device,
        const PlaneShape(width: 10.0, depth: 10.0).build(),
      ),
      Material(name: 'floor'),
      name: 'floor',
    )..setPosition(0.0, -1.5, 0.0),
  );

  final box = MeshNode(
    DeviceMesh.upload(device, CuboidShape(size: Vector3.all(2.0)).build()),
    Material(name: 'box'),
    name: 'box',
  );
  scene.add(box);

  final joint = SceneNode(name: 'joint');
  scene.add(joint);
  scene.add(
    MeshNode(
        DeviceMesh.upload(
          device,
          CuboidShape(
            size: Vector3.all(1.0),
          ).build(layout: VertexLayout.skinned),
        ),
        Material(name: 'skinned'),
        name: 'skinned',
      )
      ..skinReach = 1.0
      ..skeleton = Skeleton(
        name: 'one bone',
        joints: <SceneNode>[joint],
        inverseBindMatrices: <Matrix4>[Matrix4.identity()],
      )
      ..setPosition(2.5, 0.0, 0.0),
  );

  scene.add(
    InstancedMeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(0.5)).build()),
        Material(name: 'crowd'),
        capacity: 2,
        name: 'crowd',
      )
      ..setTransform(0, Matrix4.translation(Vector3(-2.5, 0.0, 0.0)))
      ..setTransform(1, Matrix4.translation(Vector3(-2.5, 0.0, 1.0)))
      ..count = 2,
  );

  scene.add(
    LightNode(name: 'sun', castsShadow: true)
      ..setPosition(4.0, 6.0, 4.0)
      ..lookAt(Vector3.zero()),
  );
  scene.add(
    LightNode(name: 'lamp', type: LightType.point)
      ..intensity = 12.0
      ..range = 14.0
      ..castsShadow = true
      ..setPosition(0.0, 2.0, 0.0),
  );

  final camera = CameraNode(name: 'eye')
    ..setPosition(0.0, 1.6, 6.0)
    ..lookAt(Vector3(0.0, -1.0, 0.0));
  scene.add(camera);

  return (scene: scene, camera: camera, box: box);
}

void main() {
  late FakeBackend device;
  late Renderer renderer;
  late ({Scene scene, CameraNode camera, MeshNode box}) scene;

  setUp(() {
    device = FakeBackend();
    final texel = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData(4),
    )!;
    renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    );
    scene = _scene(device);
  });

  /// One frame, with the box moved so every shadow is drawn again rather
  /// than kept from the frame before — a tile the renderer decides is still
  /// current is a pass that opens no pipeline, and this test is about the
  /// pipelines.
  void frame(int n) {
    scene.box.setPosition(0.0, 0.1 * n, 0.0);
    renderer.render(
      width: 64,
      height: 48,
      scene: scene.scene,
      views: <RenderView>[RenderView(camera: scene.camera)],
      settings: _everything,
    );
    device.finishOldestFrame();
  }

  test('a relink drops every pipeline and the next frame links them all '
      'again', () {
    frame(1);
    final first = device.linkedPipelines.toList();

    // Printed as well as asserted: when this fails after a new pass is added,
    // the useful output is the two lists side by side.
    // ignore: avoid_print
    print('first frame linked: ${first.join(', ')}');

    expect(renderer.pipelineCount, greaterThan(0));
    // The frame has to have reached every kind of pass, or a field this test
    // means to cover is one it never exercised. Named by the fragment stage
    // each pass is the only user of, so the list does not have to know how
    // the vertex side is spelt.
    for (final pair in <String>[
      'MeshVertex+Pbr',
      'MeshSkinnedVertex+Pbr',
      'MeshInstancedVertex+Pbr',
      'MeshVertex+ShadowDepth',
      'MeshSkinnedVertex+ShadowDepth',
      'MeshInstancedVertex+ShadowDepth',
      'MeshVertex+ShadowDistance',
      'MeshSkinnedVertex+ShadowDistance',
      'MeshInstancedVertex+ShadowDistance',
      'ShadowTileResetVertex+ShadowTileReset',
      'SkyVertex+Sky',
      'FullscreenVertex+BloomUpsample',
      'FullscreenVertex+Composite',
      'DebugLineVertex+DebugLine',
    ]) {
      expect(
        first,
        contains(pair),
        reason: 'the first frame should have linked $pair',
      );
    }

    // A second frame links nothing: every pipeline is held. That is the
    // baseline the relink is measured against — without it, "linked again"
    // could be "linked for the first time" for a pass the first frame skipped.
    frame(2);
    expect(
      device.linkedPipelines.length,
      first.length,
      reason: 'a frame with nothing changed links nothing',
    );

    renderer.relinkShaders();
    expect(renderer.pipelineCount, 0);

    // And the frame after links exactly what the first one did. Mutation:
    // leave one field out of `relinkShaders` — say `_skyPipeline` — and its
    // pipeline is the one missing here.
    frame(3);
    final relinked = device.linkedPipelines.sublist(first.length);
    expect(
      relinked.toSet(),
      first.toSet(),
      reason: 'every pipeline the renderer held should link again, and once',
    );
    expect(relinked, hasLength(first.length));
    expect(renderer.pipelineCount, greaterThan(0));
  });

  test('relinking twice is the same as once', () {
    frame(1);
    renderer.relinkShaders();
    expect(renderer.relinkShaders, returnsNormally);
    expect(renderer.pipelineCount, 0);
  });
}
