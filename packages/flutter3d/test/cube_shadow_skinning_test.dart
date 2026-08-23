/// What the point light's atlas pass does with a rigged caster.
///
/// The cube pass skipped every skinned node outright, so a character walking
/// through a torch-lit room cast no shadow at all — the cascade pass had grown
/// a skinned stage and this one never did. The claims below are the ones that
/// were wrong: that the node is drawn, that it is drawn through a pipeline
/// pairing the *skinned* vertex stage with `ShadowDistance` rather than with
/// the cascade's `ShadowDepth`, and that the joints reach the shader.
///
/// Off a device, because all four are decisions the encoder makes and none of
/// them needs a pixel to check. What the pixels then look like is asked in
/// `flutter3d_webgl/test/point_shadow_skinning_test.dart`, which is the only
/// harness in this repository that can render a frame without a GPU.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/light_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d/src/engine/scene/scene_node.dart';
import 'package:flutter3d/src/engine/scene/skeleton.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter3d_graphics/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;


/// A joint that counts how often the pose was evaluated from it.
///
/// [Skeleton.update] is the only thing in a frame that wants a joint's whole
/// world *matrix*: the bounds want its position, and nothing else looks at a
/// node that holds neither mesh nor camera. So the matrix reads are the pose
/// evaluations, which is what separates "the joints are uploaded once per face"
/// — they are, and must be, because that is what a draw needs — from "the joint
/// matrices are recomputed once per face", which would be sixty-odd matrix
/// allocations repeated for a pose that cannot change inside one pass.
///
/// Two other things reach a joint every frame and both route through the same
/// getter, so both are discounted rather than left to inflate the count:
/// [readWorldPosition], which the skinned bounds use, and [worldVersion], which
/// [Skeleton.poseVersion] sums and which the bounds cache and the face
/// signatures both ask for. What is left is `update`.
final class _CountingJoint extends SceneNode {
  _CountingJoint({super.name});

  int poseReads = 0;

  @override
  Matrix4 get worldMatrix {
    poseReads++;
    return super.worldMatrix;
  }

  @override
  int get worldVersion {
    final version = super.worldVersion;
    poseReads--;
    return version;
  }

  @override
  Vector3 readWorldPosition([Vector3? out]) {
    final result = super.readWorldPosition(out);
    poseReads--;
    return result;
  }
}

/// The scene: a box hanging off one joint, lit by one shadowing point light.
///
/// A single joint bound at the identity, so the skinned mesh sits exactly where
/// an unskinned one would. That is deliberate — it means a difference between
/// the two paths is a difference in the *path*, not in the pose.
({Scene scene, CameraNode camera, MeshNode box, _CountingJoint joint}) _scene(
  FakeBackend device, {
  required bool skinned,
}) {
  final scene = Scene(name: 'cube shadow');

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
    DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3.all(2.0)).build(
        layout: skinned ? VertexLayout.skinned : VertexLayout.standard,
      ),
    ),
    Material(name: 'box'),
    name: 'box',
  )..skinReach = 1.8;
  scene.add(box);

  final joint = _CountingJoint(name: 'joint');
  scene.add(joint);
  if (skinned) {
    box.skeleton = Skeleton(
      name: 'one bone',
      joints: <SceneNode>[joint],
      inverseBindMatrices: <Matrix4>[Matrix4.identity()],
    );
  }

  scene.add(
    LightNode(name: 'lamp', type: LightType.point)
      ..intensity = 12.0
      ..range = 14.0
      ..castsShadow = true
      ..setPosition(0.0, 2.0, 0.0),
  );

  final camera = CameraNode(name: 'eye')
    ..setPosition(0.0, 1.6, 5.0)
    ..lookAt(Vector3(0.0, -1.0, 0.0));
  scene.add(camera);

  return (scene: scene, camera: camera, box: box, joint: joint);
}

TextureHandle _texel(FakeBackend device) => device.createTexture(
      const RenderTargetSpec(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );

Renderer _renderer(FakeBackend device) => Renderer.create(
      device: device,
      fallbackAlbedo: _texel(device),
      fallbackNormal: _texel(device),
    );

/// The pass the two atlases are drawn into, told apart from every other pass in
/// the frame by the fragment stage it binds.
///
/// `ShadowDistance` is only ever paired in the cube pass, so a pipeline whose
/// name ends in it identifies the pass without the test having to know how many
/// passes a frame opens or in what order.
Iterable<FakePass> _atlasPasses(FakeBackend device) => device.passes.where(
      (pass) => pass
          .recordedOf<RecordedPipeline>()
          .any((p) => p.pipeline.name.endsWith('+ShadowDistance')),
    );

void main() {
  group('a skinned caster in the point light atlas', () {
    late FakeBackend device;

    setUp(() => device = FakeBackend());

    void draw({required bool skinned}) {
      final built = _scene(device, skinned: skinned);
      _renderer(device).render(
        width: 256,
        height: 192,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
      );
    }

    test('it is drawn at all', () {
      // MUTATION: put `if (node.skeleton != null) continue;` back in the caster
      // loop of _renderCubeShadow. Nothing throws — the pass still runs and
      // still draws the floor — and five of the seven tests here go red, this
      // one on the plainest possible reading: the count is zero.
      draw(skinned: true);
      final skinnedDraws = <RecordedPipeline>[
        for (final pass in _atlasPasses(device))
          ...pass
              .recordedOf<RecordedPipeline>()
              .where((p) => p.pipeline.name.startsWith('MeshSkinnedVertex+')),
      ];
      expect(skinnedDraws, isNotEmpty,
          reason: 'the rigged caster never reached the atlas');
    });

    test('it goes through the skinned stage paired with ShadowDistance', () {
      // MUTATION: bind `_cubeShadowPipeline` for the skinned node too, or reuse
      // `_skinnedShadowPipeline`. Both draw something, and both are wrong: the
      // first reads joints and weights as position and normal because a backend
      // takes the vertex layout off the shader's `in` declarations, and the
      // second writes clip depth into a target the shading reads as a radial
      // distance.
      draw(skinned: true);
      final names = <String>{
        for (final pass in _atlasPasses(device))
          for (final p in pass.recordedOf<RecordedPipeline>()) p.pipeline.name,
      };
      expect(names, contains('MeshSkinnedVertex+ShadowDistance'));
      expect(names, isNot(contains('MeshSkinnedVertex+ShadowDepth')),
          reason: 'that is the cascade pass\'s pipeline, not this one\'s');
    });

    test('the joints reach the shader on every skinned draw', () {
      // MUTATION: drop the SkinInfo bind from the cube pass. The pipeline is
      // still the skinned one and the draw still happens, so the two tests
      // above pass; the shader reads an unbound joint array, which is a mesh
      // collapsed onto the origin.
      draw(skinned: true);
      for (final pass in _atlasPasses(device)) {
        final skinnedDraws = pass
            .recordedOf<RecordedPipeline>()
            .where((p) => p.pipeline.name.startsWith('MeshSkinnedVertex+'))
            .length;
        final skinUploads = pass
            .recordedOf<RecordedUniformBlock>()
            .where((u) => u.block == 'SkinInfo')
            .length;
        expect(skinUploads, skinnedDraws,
            reason: 'every skinned draw needs the pose bound to it');
      }
    });

    test('a static caster binds no joints at all', () {
      // MUTATION: hoist the SkinInfo bind out of the `skeleton != null` guard,
      // so every caster gets one. Binding a block the static stage does not
      // declare is the phantom-uniform trap the vertex layout comment warns
      // about, and only this test and the count above notice it — nothing about
      // the skinned path changes at all.
      draw(skinned: false);
      final blocks = <String>{
        for (final pass in _atlasPasses(device))
          for (final u in pass.recordedOf<RecordedUniformBlock>()) u.block,
      };
      expect(blocks, contains('FrameInfo'));
      expect(blocks, isNot(contains('SkinInfo')));
    });

    /// Draws [frames] frames through one renderer, running [between] after
    /// each, and answers how many skinned draws each frame's atlas pass made.
    ///
    /// One renderer on purpose: the face scheduler is a renderer field, and
    /// what a second frame redraws is the whole question. A fresh renderer per
    /// frame would redraw everything and the answer would always be yes.
    List<int> skinnedDrawsPerFrame(
      Scene scene,
      CameraNode camera, {
      required int frames,
      required void Function() between,
    }) {
      final renderer = _renderer(device);
      final counts = <int>[];
      for (var frame = 0; frame < frames; frame++) {
        final before = device.passes.length;
        renderer.render(
          width: 256,
          height: 192,
          scene: scene,
          views: <RenderView>[RenderView(camera: camera)],
        );
        counts.add(device.passes
            .skip(before)
            // The atlas passes only. The scene pass draws the same character
            // through its own skinned pipeline every frame, and counting that
            // would make an atlas that redrew nothing look like one that did.
            .where((pass) => pass
                .recordedOf<RecordedPipeline>()
                .any((p) => p.pipeline.name.endsWith('+ShadowDistance')))
            .expand((pass) => pass.recordedOf<RecordedPipeline>())
            .where((p) => p.pipeline.name.startsWith('MeshSkinnedVertex+'))
            .length);
        between();
      }
      return counts;
    }

    test('moving a joint reschedules the faces it shows in', () {
      // MUTATION: drop `skeleton.poseVersion` from _casterKeyFor, or put
      // `if (node.skeleton != null) continue;` back in _computeFaceSignatures.
      // Either way the second frame's signature equals the first's, the face
      // scheduler concludes nothing changed, and the atlas keeps a shadow of a
      // pose the character has left — which is a *worse* bug than no shadow,
      // because it looks deliberate. Every other test here passes with both.
      final built = _scene(device, skinned: true);
      final counts = skinnedDrawsPerFrame(
        built.scene,
        built.camera,
        frames: 2,
        between: () => built.joint.setPosition(0.8, 0.0, 0.0),
      );
      expect(counts.first, greaterThan(0), reason: 'nothing was drawn at all');
      expect(counts.last, greaterThan(0),
          reason: 'the pose moved and the atlas was not redrawn');
    });

    test('a character standing still costs no redraw', () {
      // The other half of the same mechanism, and the reason the signature is a
      // signature rather than an unconditional redraw: an idle character must
      // not drag six faces through the atlas every frame.
      //
      // MUTATION: return a fresh value from _casterKeyFor for a skinned node —
      // say, mixing in a counter instead of the pose stamp. The test above goes
      // on passing, and every frame redraws every face for ever.
      final built = _scene(device, skinned: true);
      final counts = skinnedDrawsPerFrame(
        built.scene,
        built.camera,
        frames: 2,
        between: () {},
      );
      expect(counts.first, 6);
      expect(counts.last, 0);
    });

    test('the pose is evaluated once per pass, not once per face', () {
      // The per-face cost, measured rather than asserted in prose. The joint
      // array is *bound* once per face — that is what a draw needs, and there
      // is no way round it — but recomputing it per face would be a matrix
      // allocated per joint, six times over, for a pose that cannot change
      // inside one pass.
      //
      // MUTATION: drop the `_cubeShadowPosed.add(node)` guard and call
      // `skeleton.update` unconditionally. Every pixel of every frame stays
      // identical and every other test here still passes; this count goes from
      // two to seven.
      final built = _scene(device, skinned: true);
      _renderer(device).render(
        width: 256,
        height: 192,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
      );
      final skinnedDraws = _atlasPasses(device)
          .expand((pass) => pass.recordedOf<RecordedPipeline>())
          .where((p) => p.pipeline.name.startsWith('MeshSkinnedVertex+'))
          .length;
      // The light sits inside the caster's bounding sphere, so it lands in all
      // six faces. Without that this measures nothing.
      expect(skinnedDraws, 6);
      // Two: once for the atlas pass and once for the scene pass, which poses
      // the same character again to draw it.
      expect(built.joint.poseReads, lessThan(skinnedDraws),
          reason: 'the pose was recomputed for every face');
    });
  });

  group('and the pose it draws is the pose the joint is in', () {
    // **The hole the review found**, and it is the one that matters most: every
    // fixture above pins its single joint at the identity with an identity
    // inverse bind, deliberately, so the skinned box sits where an unskinned
    // one would. That makes the whole suite blind to *which* matrices reach the
    // atlas — bind the bind pose instead of the real one and all of it stays
    // green, which is a shadow that never animates.
    //
    // Mutation: in `renderer.dart`, bind a fresh identity `Float32List` where
    // the cube pass binds `skeleton.matrices`. The joints below stop arriving
    // and this reads zeros.
    test('a moved joint arrives in the atlas, not the bind pose', () async {
      final device = FakeBackend();
      final built = _scene(device, skinned: true);
      // Off the identity, and by more than any tolerance: the joint carries the
      // caster, so this is the difference between a shadow that follows the
      // animation and one painted at the bind pose for ever.
      built.joint.setPosition(0.0, 0.0, 3.0);

      _renderer(device).render(
        width: 64,
        height: 64,
        scene: built.scene,
        views: <RenderView>[RenderView(camera: built.camera)],
        settings: const RenderSettings(),
      );

      final skins = <Float32List>[
        for (final pass in _atlasPasses(device))
          for (final block in pass.recordedOf<RecordedUniformBlock>())
            if (block.block == 'SkinInfo')
              for (final member in block.members.values) member,
      ];

      expect(skins, isNotEmpty, reason: 'no joints reached the atlas at all');

      // The translation lives in the last row of each 4x4. Identity has zeroes
      // there; this joint has a 3 in one of them.
      final carried = skins.any((Float32List m) {
        for (var i = 0; i + 15 < m.length; i += 16) {
          if ((m[i + 14] - 3.0).abs() < 1e-3) return true;
        }
        return false;
      });

      expect(carried, isTrue,
          reason: 'the atlas was given a pose that does not contain the '
              'joint\'s 3 m offset, so it is drawing the bind pose');
    });
  });
}
