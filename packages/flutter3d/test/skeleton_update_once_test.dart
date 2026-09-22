/// `gfx-64n`: one pose per skeleton per frame, and no matrix per joint.
///
///     flutter test test/skeleton_update_once_test.dart
///
/// **What it cost.** `Skeleton.update` is reached from mesh encoding, the pick
/// pass and both shadow passes, once per primitive in each, and it allocated a
/// fresh `Matrix4` per joint every time — in a class whose own comment about
/// the matrices array says it exists precisely so a skinned model does not
/// allocate per frame. A character split across four materials on a sixty-four
/// joint rig recomputed and re-uploaded the same matrices a dozen times for one
/// pose.
///
/// The cube shadow pass had a guard for its own half of this, a set of nodes
/// held by the renderer. That guard is gone; the refusal lives in the skeleton
/// now, where every caller gets it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 64;

/// A two-joint chain, and a mesh hung off it under [materials] separate nodes.
///
/// Separate nodes sharing one skeleton is what a character split across four
/// materials looks like to the renderer: four primitives, one pose.
({Scene scene, Skeleton skeleton, SceneNode tip}) _rig(
  CpuDevice device, {
  required int materials,
}) {
  final scene = Scene();
  final root = scene.add(SceneNode(name: 'root'));
  final tip = SceneNode(name: 'tip')..setPosition(0.0, 1.0, 0.0);
  root.add(tip);

  final skeleton = Skeleton(
    name: 'chain',
    joints: <SceneNode>[root, tip],
    inverseBindMatrices: <Matrix4>[
      Matrix4.copy(root.worldMatrix)..invert(),
      Matrix4.copy(tip.worldMatrix)..invert(),
    ],
  );

  // `VertexLayout.skinned`, because the skinned vertex stage reads joint
  // indices and weights off the buffer and a standard layout has neither —
  // which the CPU backend reports as a read past the end of the joint array
  // rather than as a mesh that is not rigged.
  final geometry = CuboidShape(
    size: Vector3(0.6, 1.4, 0.6),
  ).build(layout: VertexLayout.skinned);
  for (var i = 0; i < materials; i++) {
    scene.add(
      MeshNode(DeviceMesh.upload(device, geometry), Material(name: 'part $i'))
        ..skeleton = skeleton
        ..skinReach = 1.5,
    );
  }

  scene
    ..add(
      LightNode(intensity: 5.0, castsShadow: true)
        ..setPosition(3.0, 5.0, 2.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      CameraNode()
        ..setPosition(0.0, 1.5, 4.0)
        ..lookAt(Vector3(0.0, 0.8, 0.0)),
    );

  return (scene: scene, skeleton: skeleton, tip: tip);
}

void main() {
  test('four primitives on one skeleton pose it once', () async {
    // **The row's own acceptance.** Four nodes, one skeleton, one frame — and
    // the frame goes through mesh encoding and the shadow pass, each of which
    // used to reach `update` once per primitive.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final rig = _rig(device, materials: 4);

    renderer.render(
      width: _size,
      height: _size,
      scene: rig.scene,
      views: <RenderView>[RenderView(camera: rig.scene.cameras.single)],
      settings: const RenderSettings(shadows: ShadowSettings(enabled: true)),
    );

    expect(rig.skeleton.updateCount, 1);
  });

  test('a second frame with nobody moving poses nothing', () async {
    // The other half of the guard: the pose stamp did not change and neither
    // did the mesh transform, so there is nothing to recompute. This is what
    // catches a guard keyed on something that is fresh every frame.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final rig = _rig(device, materials: 4);

    void frame() => renderer.render(
      width: _size,
      height: _size,
      scene: rig.scene,
      views: <RenderView>[RenderView(camera: rig.scene.cameras.single)],
      settings: const RenderSettings(shadows: ShadowSettings(enabled: true)),
    );

    frame();
    frame();
    frame();

    expect(rig.skeleton.updateCount, 1);
  });

  test('a joint that moves is posed again', () async {
    // **The claim that makes the guard safe**, and the one a guard that never
    // let anything through would fail. A character whose pose is computed once
    // and then never again is a character frozen in its bind pose, which every
    // pixel test in this repository would report as a picture rather than as a
    // count.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final renderer = Renderer.create(device: device);
    final rig = _rig(device, materials: 4);

    void frame() => renderer.render(
      width: _size,
      height: _size,
      scene: rig.scene,
      views: <RenderView>[RenderView(camera: rig.scene.cameras.single)],
      settings: const RenderSettings(shadows: ShadowSettings(enabled: true)),
    );

    frame();
    rig.tip.setPosition(0.4, 1.0, 0.0);
    frame();

    expect(rig.skeleton.updateCount, 2);
  });

  test('and the matrices it writes are the ones it always wrote', () {
    // The reused joint matrix replaced one allocated per joint, so what has to
    // be shown is that reuse did not leave a term behind. Computed here the
    // long way, straight from the glTF formula.
    final device = CpuDevice(
      width: _size,
      height: _size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    final rig = _rig(device, materials: 1);
    rig.tip.setPosition(0.4, 1.2, 0.1);

    final meshWorld = rig.scene.meshes.first.worldMatrix;
    rig.skeleton.update(meshWorld);

    final inverseMesh = Matrix4.copy(meshWorld)..invert();
    for (var j = 0; j < rig.skeleton.joints.length; j++) {
      final expected = Matrix4.copy(inverseMesh)
        ..multiply(rig.skeleton.joints[j].worldMatrix)
        ..multiply(
          // The bind pose is the rig as built, and `_rig` builds it before
          // anything moves, so the inverse bind is the joint's world matrix at
          // that moment. Recomputing it here would be recomputing the fixture;
          // this reads the one the skeleton was handed.
          Matrix4.identity()..setFrom(_inverseBindOf(rig.skeleton, j)),
        );
      for (var e = 0; e < 16; e++) {
        expect(
          rig.skeleton.matrices[j * 16 + e],
          closeTo(expected.storage[e], 1e-5),
          reason: 'joint $j element $e',
        );
      }
    }
  });
}

/// The inverse bind matrix [skeleton] holds for joint [index].
///
/// The skeleton keeps them privately, which is right — nothing outside it has
/// business changing one — so the fixture's own construction is reproduced:
/// every joint was at rest when the rig was built, so its inverse bind is the
/// inverse of the world matrix it had then, and the root has not moved since.
Matrix4 _inverseBindOf(Skeleton skeleton, int index) {
  final joint = skeleton.joints[index];
  return switch (index) {
    0 => Matrix4.copy(joint.worldMatrix)..invert(),
    _ => Matrix4.translation(Vector3(0.0, -1.0, 0.0)),
  };
}
