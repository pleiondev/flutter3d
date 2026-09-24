/// Six-way particles — `N6`: the importer, the order they are drawn in, and
/// what the contributor binds for them.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('importSixWay', () {
    test('reads each quantity from where the layout says it is', () {
      // One texel, packed as a sheet that keeps right, left and top in one
      // image and the rest in another.
      final a = Uint8List.fromList(<int>[10, 20, 30, 40]);
      final b = Uint8List.fromList(<int>[50, 60, 70, 80]);
      const layout = SixWayLayout(
        right: (image: 0, channel: 0),
        left: (image: 0, channel: 1),
        top: (image: 0, channel: 2),
        bottom: (image: 0, channel: 3),
        back: (image: 1, channel: 0),
        front: (image: 1, channel: 1),
        coverage: (image: 1, channel: 2),
      );
      final sheet = importSixWay(
        images: <Uint8List>[a, b],
        width: 1,
        height: 1,
        layout: layout,
      );
      // Positive: right, top, back, coverage. Negative: left, bottom, front,
      // and nothing for the emission this layout does not have.
      expect(sheet.positive, <int>[10, 30, 50, 70]);
      expect(sheet.negative, <int>[20, 40, 60, 0]);
    });

    test('turns each cell over and keeps the cells where they were', () {
      // One column, two cells of two rows; each row's red is its row number.
      final image = Uint8List(4 * 4);
      for (var row = 0; row < 4; row++) {
        image[row * 4] = row;
      }
      final sheet = importSixWay(
        images: <Uint8List>[image, Uint8List(16)],
        width: 1,
        height: 4,
        rows: 2,
      );
      // Mutation: flip the whole image. The cells trade places: 3, 2, 1, 0.
      expect(
        <int>[for (var r = 0; r < 4; r++) sheet.positive[r * 4]],
        <int>[1, 0, 3, 2],
      );
      final unturned = importSixWay(
        images: <Uint8List>[image, Uint8List(16)],
        width: 1,
        height: 4,
        rows: 2,
        flipCells: false,
      );
      expect(
        <int>[for (var r = 0; r < 4; r++) unturned.positive[r * 4]],
        <int>[0, 1, 2, 3],
      );
    });

    test('refuses an image too small for its size', () {
      expect(
        () => importSixWay(
          images: <Uint8List>[Uint8List(4), Uint8List(4)],
          width: 2,
          height: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ParticleSystem', () {
    ParticleSystem threeInARow() {
      final particles = ParticleSystem(capacity: 8);
      for (final z in <double>[-1.0, -5.0, -3.0]) {
        particles.burst(
          ParticleEffect(
            count: 1,
            emitter: const SphereEmitter(speed: Range.exact(0.0)),
            lifetime: const Range.exact(5.0),
            size: const Range.exact(0.5),
            color: vm.Vector4(1.0, 1.0, 1.0, 1.0),
          ),
          vm.Vector3(0.0, 0.0, z),
        );
      }
      return particles;
    }

    List<double> depths(ParticleSystem particles, {vm.Vector3? along}) {
      final vertices = Float32List(8 * ParticleSystem.floatsPerParticle);
      final written = particles.writeQuads(
        vm.Vector3(1.0, 0.0, 0.0),
        vm.Vector3(0.0, 1.0, 0.0),
        vertices,
        Uint32List(8 * 6),
        farthestAlong: along,
      );
      return <double>[
        for (var i = 0; i < written; i++)
          vertices[i * ParticleSystem.floatsPerParticle + 2],
      ];
    }

    test('writes farthest first along the axis it is given', () {
      // Looking down −z: the particle at −5 is the farthest.
      // Mutation: compare `depth[a]` with `depth[b]`. Nearest first.
      expect(depths(threeInARow(), along: vm.Vector3(0.0, 0.0, -1.0)), <double>[
        -5.0,
        -3.0,
        -1.0,
      ]);
    });

    test('keeps the pool order when it is given none', () {
      expect(depths(threeInARow()), <double>[-1.0, -5.0, -3.0]);
    });

    test('bounds every quad of what is alive', () {
      final centre = vm.Vector3.zero();
      final radius = threeInARow().boundsInto(centre);
      expect(centre.z, closeTo(-3.0, 1e-9));
      // Two metres to either end, and half a quad's diagonal past that.
      expect(radius, closeTo(2.0 + 0.5 * 0.7071067811865476, 1e-9));
      expect(ParticleSystem().boundsInto(centre), 0.0);
    });
  });

  group('the six-way contributor, drawn against a fake pass', () {
    late FakeBackend device;
    late FakePass pass;
    late ParticleSystem particles;
    late SixWayMaterial sheet;

    ContributorFrame frame({ContributorLights? lights}) => ContributorFrame(
      encoder: pass,
      device: device,
      services: _NoServices(),
      state: FramePassState(),
      settings: const RenderSettings(),
      width: 320,
      height: 200,
      view: RenderView(camera: CameraNode()),
      viewProjection: vm.Matrix4.identity(),
      lights: lights,
    );

    setUp(() {
      device = FakeBackend();
      pass = FakePass(const RenderPassDescriptor(colors: <ColorTarget>[]));
      particles = ParticleSystem(capacity: 16)
        ..burst(
          ParticleEffect(
            count: 4,
            emitter: const SphereEmitter(),
            lifetime: const Range.exact(5.0),
            size: const Range.exact(0.5),
            color: vm.Vector4(1.0, 1.0, 1.0, 1.0),
          ),
          vm.Vector3.zero(),
        );
      TextureHandle texture() => device.createTextureFromPixels(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData(4),
      )!;
      sheet = SixWayMaterial(positive: texture(), negative: texture());
    });

    test('blends over, binds both pictures and asks for its lights', () {
      final lights = _RecordingLights();
      ParticleContributor(
        particles,
        sixWay: sheet,
      ).encode(frame(lights: lights));

      expect(pass.drawCount, 1);
      expect(
        pass.recordedOf<RecordedBlend>().single.state,
        BlendState.alphaBlend,
        reason: 'smoke darkens what it covers, which addition cannot',
      );
      expect(pass.depthWrite, isFalse);
      final pipeline = pass.recordedOf<RecordedPipeline>().single.pipeline;
      expect(pipeline, isNotNull);
      final textures = pass.recordedOf<RecordedTexture>();
      expect(textures.map((t) => t.slot), <String>[
        'six_way_positive',
        'six_way_negative',
      ]);
      expect(textures.every((t) => t.shader?.name == 'ParticleSixWay'), isTrue);
      final block = pass
          .recordedOf<RecordedUniformBlock>()
          .where((b) => b.block == 'SixWayInfo')
          .single;
      // The camera's axes: an unmoved camera looks down −z.
      expect(block.members['forward']!.sublist(0, 3), <double>[0.0, 0.0, -1.0]);
      expect(lights.stages.single.name, 'ParticleSixWay');
      expect(lights.radii.single, greaterThan(0.0));
    });

    test('draws nothing with no lights to bind', () {
      ParticleContributor(particles, sixWay: sheet).encode(frame());
      expect(pass.commands, isEmpty);
    });

    test('leaves the additive path as it was', () {
      ParticleContributor(particles).encode(frame(lights: _RecordingLights()));
      expect(
        pass.recordedOf<RecordedBlend>().single.state,
        BlendState.additive,
      );
      expect(pass.recordedOf<RecordedTexture>(), isEmpty);
    });
  });
}

final class _RecordingLights implements ContributorLights {
  final List<ShaderHandle> stages = <ShaderHandle>[];
  final List<double> radii = <double>[];

  @override
  void bind(
    PassEncoder encoder,
    ShaderHandle stage, {
    required vm.Vector3 centre,
    required double radius,
  }) {
    stages.add(stage);
    radii.add(radius);
  }
}

final class _NoServices implements RenderServices {
  @override
  void encodeScene({
    required NodeFrame frame,
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    int casterIndex = -1,
  }) {}

  @override
  void drawFullscreen(FullscreenDraw draw) {}
}
