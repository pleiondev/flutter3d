/// The particle contributor, drawn against a fake pass.
///
/// Moved here with the simulation. It needs `FakeBackend`, which lives in the
/// engine's `test/` and is therefore not importable across a package boundary
/// — so it is **copied**, not promoted to `lib/`. Promoting it would put a
/// fake device on the engine's public surface for the benefit of one consumer,
/// which is a larger price than a duplicated fixture.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;


void main() {
  _meshParticleTests();

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

  /// Recorded rather than ignored: a contributor that started drawing
  /// full-screen would be doing something this test could otherwise not see.
  final List<FullscreenDraw> fullscreens = <FullscreenDraw>[];

  @override
  void drawFullscreen(FullscreenDraw draw) => fullscreens.add(draw);
}

/// A mesh already on the device, as far as the contributor can tell.
///
/// The fake backend hands out opaque handles, so a mesh here is a description
/// and nothing more — which is the whole of what an instanced draw needs from
/// one: two buffers, two counts and an index type.
final class _FakeMesh implements DrawableGeometry {
  _FakeMesh(this.vertices, this.indices);

  @override
  final GeometryBuffer vertices;
  @override
  final GeometryBuffer indices;
  @override
  int get vertexCount => 24;
  @override
  int get indexCount => 36;
  @override
  IndexType get indexType => IndexType.int16;
  @override
  vm.Aabb3 get bounds => vm.Aabb3();
  @override
  double get boundingRadius => 1.0;
  @override
  MeshData? get source => null;
}

/// The mesh path, which is a different set of calls from the billboard one.
void _meshParticleTests() {
  group('the mesh particle contributor', () {
    late FakeBackend device;
    late FakePass pass;
    late ParticleSystem particles;
    late _FakeMesh mesh;

    setUp(() {
      device = FakeBackend();
      pass = FakePass(const RenderPassDescriptor(colors: <ColorTarget>[]));
      mesh = _FakeMesh(
        device.uploadGeometry(ByteData(64 * 24), GeometryUsage.vertices),
        device.uploadGeometry(ByteData(2 * 36), GeometryUsage.indices),
      );
      particles = ParticleSystem(capacity: 64)
        ..burst(
          ParticleEffect(
            count: 5,
            emitter: const SphereEmitter(speed: Range.exact(1.0)),
            lifetime: const Range.exact(1.0),
            size: const Range.exact(0.5),
            color: vm.Vector4(1.0, 0.5, 0.2, 1.0),
          ),
          vm.Vector3.zero(),
        );
    });

    ContributorFrame frame() => ContributorFrame(
          encoder: pass,
          device: device,
          services: _RecordingServices(),
          state: FramePassState(),
          settings: const RenderSettings(),
          width: 320,
          height: 200,
          view: RenderView(camera: CameraNode()),
          viewProjection: vm.Matrix4.identity(),
        );

    test('binds the mesh in slot zero and the placements in slot one', () {
      MeshParticleContributor(particles, mesh: mesh).encode(frame());

      final vertices =
          pass.commands.whereType<RecordedVertices>().toList();
      expect(vertices, hasLength(2),
          reason: 'a mesh particle draw is two vertex buffers, which is the '
              'only draw in this engine that is');

      // The mesh: slot zero, already on the device, its own vertex count.
      expect(vertices[0].slot, 0);
      expect(vertices[0].transient, isFalse);
      expect(vertices[0].count, 24);

      // The placements: slot one, rebuilt this frame, one per live particle.
      expect(vertices[1].slot, 1);
      expect(vertices[1].transient, isTrue);
      expect(vertices[1].count, 5);
    });

    test('draws once, with one instance per live particle', () {
      MeshParticleContributor(particles, mesh: mesh).encode(frame());

      final draws = pass.commands.whereType<RecordedDraw>().toList();
      expect(draws, hasLength(1),
          reason: 'the point of instancing is that five particles are one call');
      expect(draws.single.instanceCount, 5);
    });

    test('the index buffer is the mesh\'s, not one built per frame', () {
      MeshParticleContributor(particles, mesh: mesh).encode(frame());

      final indices = pass.commands.whereType<RecordedIndices>().toList();
      expect(indices, hasLength(1));
      expect(indices.single.transient, isFalse,
          reason: 'the geometry is on the device already; rebuilding indices '
              'every frame is what the billboard path has to do and this one '
              'exists to avoid');
      expect(indices.single.count, 36);
    });

    test('draws nothing when nothing is alive', () {
      final empty = ParticleSystem(capacity: 8);
      final contributor = MeshParticleContributor(empty, mesh: mesh);
      expect(contributor.isActive, isFalse);

      contributor.encode(frame());
      expect(pass.commands.whereType<RecordedDraw>(), isEmpty);
    });
  });
}
