/// What a node and a contributor actually draw, asserted with no device.
///
/// A `RenderNode`'s *declaration* — what it reads, what it writes, when it is
/// active — has been testable since the frame graph existed, and is tested.
/// Its **behaviour** was not: `execute` opened a `gpu.RenderPass`, and there is
/// no such thing off a device. So the questions below had exactly two answers
/// available before this suite — read the code, or run the twelve-minute golden
/// suite and look at a picture:
///
///  * Does the view model draw into the scene's colour, or over it?
///  * Does it *load* that colour, or clear it and take the world with it?
///  * Does it clear its own depth, which is the whole reason it is a pass?
///  * Does it submit? A pass that is never submitted draws nothing, silently.
///  * Do particles blend additively, and do they leave depth alone?
///
/// Every one of those is a one-line mistake with no compile error and no test
/// failure, and three of them are invisible in any single frame.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter3d/src/engine/geometry/mesh_geometry.dart';
import 'package:flutter3d/src/engine/geometry/primitive_shapes.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter3d/src/engine/particles/particle.dart';
import 'package:flutter3d/src/engine/particles/particle_contributor.dart';
import 'package:flutter3d/src/engine/particles/particle_emitter.dart';
import 'package:flutter3d/src/engine/particles/particle_system.dart';
import 'package:flutter3d/src/engine/render/frame_graph.dart';
import 'package:flutter3d/src/engine/render/frame_plan.dart';
import 'package:flutter3d/src/engine/render/frame_resources.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/pass_contributor.dart';
import 'package:flutter3d/src/engine/render/render_node.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/render/view_model_node.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';

import 'fake_backend.dart';

/// Records the one call a node can make back into the renderer.
///
/// It draws nothing, which is the point: what a node hands *to* `encodeScene`
/// is the node's own decision — which camera, which shadows — and that is the
/// half worth pinning. What `encodeScene` then does with a mesh belongs to the
/// renderer and is the same for every caller.
final class _RecordingServices implements RenderServices {
  final List<SceneShadows> shadows = <SceneShadows>[];
  final List<vm.Matrix4> viewProjections = <vm.Matrix4>[];
  PassEncoder? encoder;
  Scene? scene;

  @override
  void encodeScene({
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    required RenderSettings settings,
    required FramePassState state,
    required SceneShadows shadows,
  }) {
    this.encoder = encoder;
    this.scene = scene;
    this.shadows.add(shadows);
    viewProjections.add(viewProjection);
  }
}

/// The lit scene, as the frame would have it.
final TextureHandle _sceneColor = TextureHandle(
  backend: 'hdr colour',
  width: 320,
  height: 200,
  format: TextureFormat.r16g16b16a16Float,
);

/// Refuses to hand anything out. Nothing in this file wants a pooled texture,
/// and a source that quietly produced one would hide it if something did.
final class _NoSource implements FrameTextureSource {
  @override
  TextureHandle acquire(RenderTargetSpec spec) =>
      throw StateError('nothing here should be acquiring a pooled texture');

  @override
  void release(TextureHandle texture) =>
      throw StateError('nothing here should be releasing a texture');
}

/// A node holding CPU-only geometry.
///
/// The view model never touches it — `encodeScene` is the recording fake — and
/// that a mesh which never reached the device serves here at all is the point
/// of `MeshGeometry` being what the scene layer deals in.
MeshNode _meshNode() =>
    MeshNode(CpuMesh(CuboidShape().build()), Material());

void main() {
  group('the view model node, drawn against a fake device', () {
    late FakeBackend device;
    late ViewModelNode node;
    late _RecordingServices services;

    setUp(() {
      device = FakeBackend();
      final scene = Scene()..add(_meshNode());
      node = ViewModelNode(scene: scene, camera: CameraNode());
      services = _RecordingServices();
    });

    NodeFrame frameWith({bool withSceneColor = true}) {
      // The atlases are declared as *external* rather than written by a stub,
      // which is the honest shape of this test: it is asking what the view
      // model does with a frame that produced no shadows, and an external name
      // nobody provided is exactly that — `tryTexture` answers null, and the
      // node has to cope rather than reach for a renderer field.
      final graph = FrameGraph()
        ..addExternal(FrameResourceIds.cubeShadow)
        ..addExternal(FrameResourceIds.cubeShadowStatic)
        ..addNode(node);
      final compiled =
          graph.compile(outputs: const <ResourceId>[FrameResourceIds.hdrColour]);
      final resources = FrameResources(
        source: _NoSource(),
        graph: compiled,
        frameWidth: 320,
        frameHeight: 200,
      )
        // As the frame does before it runs a node. Without it the node's reads
        // arrive from outside any node, which the resource layer no longer
        // allows — and used to allow only because this test asked it to.
        ..beginNode(0);
      return NodeFrame(
        device: device,
        resources: resources,
        services: services,
        state: FramePassState(),
        settings: const RenderSettings(),
        width: 320,
        height: 200,
        sceneColor: withSceneColor ? _sceneColor : null,
      );
    }

    test('draws over the scene rather than clearing it', () {
      node.execute(frameWith());

      expect(device.passes, hasLength(1));
      final pass = device.passes.single;
      expect(identical(pass.color.texture, _sceneColor), isTrue,
          reason: 'the weapon goes into the lit scene, not a target of its own');
      expect(pass.color.loadAction, LoadAction.load,
          reason: 'clearing here would take the whole world with it');
      expect(pass.color.resolveTexture, isNull,
          reason: 'straight into the resolved target, without MSAA — a '
              'multisampled attachment cannot be loaded back');
    });

    test('clears its own depth, which is the reason it is a separate pass', () {
      node.execute(frameWith());

      final depth = device.passes.single.descriptor.depth;
      expect(depth, isNotNull);
      expect(depth!.clearValue, 1.0,
          reason: 'nothing in the world may occlude what is in the hands');
      expect(depth.texture.storageMode, StorageMode.deviceTransient,
          reason: 'never sampled, so it belongs in tile memory');
      expect(identical(depth.texture, _sceneColor), isFalse);
    });

    test('submits the pass it opened', () {
      node.execute(frameWith());
      expect(device.passes.single.submitted, isTrue,
          reason: 'an unsubmitted pass draws nothing and says nothing');
    });

    test('sets a viewport and a scissor covering the frame', () {
      node.execute(frameWith());

      const full = ScreenRect(width: 320, height: 200);
      expect(
        device.passes.single.recordedOf<RecordedViewport>().single.rect,
        full,
      );
      expect(
        device.passes.single.recordedOf<RecordedScissor>().single.rect,
        full,
      );
    });

    test('tests depth nearest-first and writes it', () {
      node.execute(frameWith());
      expect(device.passes.single.depthWrite, isTrue);
      expect(device.passes.single.depthCompare, CompareFunction.less);
    });

    test('forgets the pipeline the scene pass left bound', () {
      final frame = frameWith();
      frame.state
        ..boundSkinned = false
        ..pipelineSwitches = 3;
      node.execute(frame);
      expect(frame.state.boundPipeline, isNull);
      expect(frame.state.boundSkinned, isNull,
          reason: 'nothing is bound in a new pass, so the tracker must not '
              'claim otherwise');
    });

    test('draws with no shadow map and only the atlases it declared', () {
      node.execute(frameWith());

      final shadows = services.shadows.single;
      expect(shadows.directional, isNull,
          reason: "the world's shadow matrix belongs to the world's camera");
      expect(shadows.point, isNull,
          reason: 'no atlas was provided to this frame, so there is none to '
              'sample — rather than one found lying in a renderer field');
      expect(shadows.pointStatic, isNull);
    });

    test('opens no pass at all when the frame has no scene colour', () {
      node.execute(frameWith(withSceneColor: false));
      expect(device.passes, isEmpty,
          reason: 'there is nothing to draw over until the world has drawn');
    });

    test('reuses its depth buffer until the size changes', () {
      node.execute(frameWith());
      node.execute(frameWith());
      expect(device.createdTextures, hasLength(1),
          reason: 'a full-size depth buffer per frame is megabytes nobody '
              'asked for');
    });
  });

  group('the particle contributor, drawn against a fake pass', () {
    late FakeBackend device;
    late FakePass pass;
    late ParticleSystem particles;

    ContributorFrame frame({FakeBackend? backend}) {
      final used = backend ?? device;
      return ContributorFrame(
        encoder: pass,
        device: used,
        services: _RecordingServices(),
        state: FramePassState(),
        settings: const RenderSettings(),
        width: 320,
        height: 200,
        view: RenderView(camera: CameraNode()),
        viewProjection: vm.Matrix4.identity(),
      );
    }

    setUp(() {
      device = FakeBackend();
      pass = FakePass(const RenderPassDescriptor(colors: <ColorTarget>[]));
      particles = ParticleSystem(capacity: 64)
        ..burst(
          ParticleEffect(
            count: 8,
            emitter: const SphereEmitter(),
            lifetime: const Range.exact(5.0),
            size: const Range.exact(0.2),
            color: vm.Vector4(1.0, 0.5, 0.2, 1.0),
          ),
          vm.Vector3.zero(),
        );
    });

    test('is active only while something is alive', () {
      expect(ParticleContributor(particles).isActive, isTrue);
      particles.clear();
      expect(ParticleContributor(particles).isActive, isFalse);
    });

    test('blends additively and never writes depth', () {
      ParticleContributor(particles).encode(frame());

      expect(pass.recordedOf<RecordedBlend>().single.state, BlendState.additive,
          reason: 'addition is commutative, which is what removes the sort');
      expect(pass.depthWrite, isFalse,
          reason: 'particles must not occlude each other');
      expect(pass.depthCompare, CompareFunction.less,
          reason: 'but they are still hidden by the world');
      expect(pass.cullMode, CullMode.none,
          reason: 'a quad seen from behind is still a quad');
    });

    test('is one draw of transient geometry, six indices per particle', () {
      ParticleContributor(particles).encode(frame());

      expect(pass.drawCount, 1,
          reason: 'one batch, which is the whole point of additive blending');
      final vertices = pass.recordedOf<RecordedVertices>().single;
      expect(vertices.transient, isTrue,
          reason: 'the quads were built this frame; they have no device buffer');
      final indices = pass.recordedOf<RecordedIndices>().single;
      expect(indices.count, vertices.count ~/ 4 * 6);
      expect(indices.type, IndexType.int32);
    });

    test('clears the bindings the mesh draws left behind', () {
      ParticleContributor(particles).encode(frame());
      expect(pass.commands.first, isA<RecordedClearBindings>(),
          reason: 'the mesh draws left a different vertex layout bound, and '
              'this must be the first thing the contributor does');
    });

    test('counts its draw and invalidates the pipeline tracker', () {
      final f = frame();
      f.state
        ..boundSkinned = true
        ..drawCalls = 5;
      ParticleContributor(particles).encode(f);

      expect(f.state.drawCalls, 6,
          reason: 'a contributor that does not count makes the frame '
              'statistics lie');
      expect(f.state.boundPipeline, isNull);
      expect(f.state.boundSkinned, isNull);
    });

    test('draws nothing at all when the bundle has no particle stage', () {
      final withoutStages = FakeBackend(missingShaders: <String>{'Particle'});
      ParticleContributor(particles).encode(frame(backend: withoutStages));

      expect(pass.commands, isEmpty,
          reason: 'the fragment stage is called "Particle", not '
              '"ParticleFragment"; guessing it wrong used to be invisible');
    });
  });
}
