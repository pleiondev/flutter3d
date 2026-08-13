/// The particle contributor, drawn against a fake pass.
///
/// Moved here with the simulation. It needs `FakeBackend`, which lives in the
/// engine's `test/` and is therefore not importable across a package boundary
/// — so it is **copied**, not promoted to `lib/`. Promoting it would put a
/// fake device on the engine's public surface for the benefit of one consumer,
/// which is a larger price than a duplicated fixture.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'fake_backend.dart';

void main() {
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

/// Records what the scene node was asked to encode.
///
/// Copied with the group it serves, for the same reason `fake_backend.dart`
/// is: it is a test fixture, and the alternative is a public fake.
final class _RecordingServices implements RenderServices {
  final List<SceneShadows> shadows = <SceneShadows>[];
  final List<vm.Matrix4> viewProjections = <vm.Matrix4>[];
  PassEncoder? encoder;
  Scene? scene;

  @override
  void encodeScene({
    required NodeFrame frame,
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    int casterIndex = -1,
  }) {
    this.encoder = encoder;
    this.scene = scene;
    // Derived the way the real one does, so a test still sees what the node
    // would actually have been given rather than what it chose to pass.
    shadows.add(SceneShadows.from(frame, casterIndex: casterIndex));
    viewProjections.add(viewProjection);
  }
}
