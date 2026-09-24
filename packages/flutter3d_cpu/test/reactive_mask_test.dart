/// What blends is taken from this frame, not from the history — `R4`.
///
///     dart test test/reactive_mask_test.dart
///
/// On the software rasteriser. An ember is a particle, and a particle writes
/// no depth and no velocity: the temporal resolve reprojects the wall behind
/// it and keeps most of that wall, so an ember that moves every frame shows
/// at a fraction of its brightness. The reactive mask is the ember saying
/// where it is.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

const int _width = 64;
const int _height = 48;

RenderSettings _settings({bool temporal = true, double reactive = 0.0}) =>
    RenderSettings(
      tonemap: false,
      // The glow would spread the ember whatever the resolve did with it.
      bloom: const BloomSettings(enabled: false),
      antiAlias: AntiAliasSettings(
        temporal: TemporalSettings(enabled: temporal, reactive: reactive),
      ),
    );

/// Copies the velocity resource out as floats, each frame it runs — see
/// `camera_velocity_test.dart`.
final class _VelocityProbe extends RenderNode {
  _VelocityProbe(this._device);

  final CpuDevice _device;
  Float32List? last;

  @override
  String get name => 'velocity probe';

  @override
  FramePhase get preferredPhase => FramePhase.present;

  @override
  List<ResourceId> get reads => const <ResourceId>[
    FrameResourceIds.frame,
    FrameResourceIds.velocity,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    last = _device.readHdrPixels(
      frame.resources.texture(FrameResourceIds.velocity),
    );
    frame.resources.provide(
      FrameResourceIds.frame,
      frame.resources.texture(FrameResourceIds.frame),
    );
  }
}

typedef _Staged = ({
  CpuDevice device,
  Renderer renderer,
  Scene scene,
  RenderView view,
  _VelocityProbe probe,
});

/// A dark wall six metres off, square to the camera, and whatever [extra]
/// adds in front of it.
_Staged _staged({void Function(CpuDevice device, Scene scene)? extra}) {
  final device = CpuDevice(
    width: _width,
    height: _height,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode();
  final wall = MeshNode(
    DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(20.0, 20.0, 1.0)).build(),
    ),
    Material(
      lighting: LightingModel.unlit,
      baseColor: Vector4(0.2, 0.2, 0.2, 1.0),
    ),
  )..setPosition(0.0, 0.0, -6.5);
  final scene = Scene()
    ..add(wall)
    ..add(camera);
  extra?.call(device, scene);
  final probe = _VelocityProbe(device);
  return (
    device: device,
    renderer: Renderer.create(device: device)..addNode(probe),
    scene: scene,
    view: RenderView(camera: camera, clearColor: Vector4(0.0, 0.0, 0.0, 1.0)),
    probe: probe,
  );
}

Float32List _draw(_Staged it, RenderSettings settings) {
  final result = it.renderer.render(
    width: _width,
    height: _height,
    scene: it.scene,
    views: <RenderView>[it.view],
    settings: settings,
  );
  return it.device.readHdrPixels(result.frame);
}

/// The brightest red in [pixels]: the ember's core, which is the only thing
/// in the frame redder than the wall.
double _peak(Float32List pixels) {
  var peak = 0.0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i] > peak) peak = pixels[i];
  }
  return peak;
}

/// An ember crossing the wall, a little more than its own width a frame, for
/// [frames] frames, and the last frame drawn.
Float32List _embers(RenderSettings settings, {int frames = 12}) {
  final particles = ParticleSystem(capacity: 4, seed: 1);
  final ember = ParticleEffect(
    count: 1,
    // Still where it is put: the test moves it, so each frame's position is
    // exactly the one asked for.
    emitter: const SphereEmitter(speed: Range.exact(0.0)),
    lifetime: const Range.exact(10.0),
    // A few pixels across, so the neighbourhood the resolve clips the
    // history to has wall in it as well as ember; a large one's core would
    // clip the wall away on its own.
    size: const Range.exact(0.3),
    color: Vector4(1.0, 0.6, 0.2, 1.0),
  );
  final it = _staged();
  it.renderer.addContributor(ParticleContributor(particles));
  late Float32List last;
  for (var frame = 0; frame < frames; frame++) {
    particles
      ..clear()
      ..burst(ember, Vector3(-2.2 + 0.4 * frame, 0.0, -5.0));
    last = _draw(it, settings);
  }
  return last;
}

void main() {
  test('taa-embers: a moving ember keeps its brightness', () {
    final sharp = _peak(_embers(_settings(temporal: false)));
    final smeared = _peak(_embers(_settings()));
    final reactive = _peak(_embers(_settings(reactive: 1.0)));

    // Without the mask the resolve keeps nine tenths of a wall that never
    // had the ember in it, and the ember is a ghost of itself.
    expect(smeared, lessThan(sharp * 0.6));
    // With it the core is taken from this frame. Mutation: drop the
    // `(1 - reactive)` factor in the resolve's mirror, or return early from
    // `ParticleContributor.encodeReactive`; either leaves this at `smeared`.
    // Not all of it: the disc's soft edge is only partly reactive, and the
    // resolve reads a jittered frame between texels.
    expect(reactive, greaterThan(sharp * 0.75));
  });

  test('the mask is the coverage: a pane by its alpha, a splat by its '
      'falloff, nothing behind the wall', () {
    final cloud = SplatCloud(
      centres: Float32List.fromList(<double>[1.5, 0.0, -5.0]),
      colours: Float32List.fromList(<double>[1.0, 1.0, 1.0, 0.8]),
      scales: Float32List.fromList(<double>[0.3, 0.3, 0.3]),
      rotations: Float32List.fromList(<double>[0.0, 0.0, 0.0, 1.0]),
    );
    final it = _staged(
      extra: (device, scene) {
        MeshNode pane(double x, double z) => MeshNode(
          DeviceMesh.upload(
            device,
            CuboidShape(size: Vector3(1.0, 1.0, 0.01)).build(),
          ),
          Material(
            lighting: LightingModel.unlit,
            baseColor: Vector4(0.5, 0.7, 1.0, 0.4),
            alphaMode: MaterialAlphaMode.blend,
          ),
        )..setPosition(x, 0.0, z);
        scene
          // In front of the wall, to the left.
          ..add(pane(-1.5, -5.0))
          // Behind it, straight ahead: the wall hides it.
          ..add(pane(0.0, -8.0));
      },
    );
    it.renderer.addContributor(SplatContributor(cloud));

    _draw(it, _settings(reactive: 0.5));
    final v = it.probe.last!;
    double blueAt(double x) {
      // A world point on the plane five metres off, to its pixel.
      final column = (_width / 2 + x / 5.0 / 0.41421356 * _height / 2).round();
      return v[((_height ~/ 2) * _width + column) * 4 + 2];
    }

    // The pane at a strength of a half: two tenths.
    expect(blueAt(-1.5), closeTo(0.2, 1e-3));
    // The splat's middle: its alpha, near enough the peak of its falloff.
    expect(blueAt(1.5), inInclusiveRange(0.3, 0.4));
    // Straight ahead is the wall, and the pane behind it marks nothing.
    // Mutation: drop the surface-buffer test in `ReactiveShader`.
    expect(blueAt(0.0), 0.0);
    // Far from all three, nothing either.
    expect(v[2], 0.0);
  });

  test('the mask adds only blue: the motion under it is untouched', () {
    // A box sliding across the wall writes a motion; a pane over it is
    // marked. With the mask off and on, red and green agree to the bit.
    late MeshNode box;
    _Staged staged() => _staged(
      extra: (device, scene) {
        box = MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          Material(lighting: LightingModel.unlit),
        )..setPosition(-0.5, 0.0, -5.5);
        scene
          ..add(box)
          ..add(
            MeshNode(
              DeviceMesh.upload(
                device,
                CuboidShape(size: Vector3(1.0, 1.0, 0.01)).build(),
              ),
              Material(
                lighting: LightingModel.unlit,
                baseColor: Vector4(1.0, 1.0, 1.0, 0.5),
                alphaMode: MaterialAlphaMode.blend,
              ),
            )..setPosition(0.0, 0.0, -4.0),
          );
      },
    );
    Float32List motion(double reactive) {
      final it = staged();
      _draw(it, _settings(reactive: reactive));
      box.setPosition(0.0, 0.0, -5.5);
      _draw(it, _settings(reactive: reactive));
      return it.probe.last!;
    }

    final off = motion(0.0);
    final on = motion(1.0);
    var marked = 0;
    for (var i = 0; i < off.length; i += 4) {
      expect(on[i], off[i], reason: 'red at pixel ${i ~/ 4}');
      expect(on[i + 1], off[i + 1], reason: 'green at pixel ${i ~/ 4}');
      expect(on[i + 3], off[i + 3], reason: 'alpha at pixel ${i ~/ 4}');
      if (on[i + 2] > 0.0) marked++;
    }
    // Alpha is one everywhere, so it is red and green that show a motion was
    // there to be kept.
    var moving = 0;
    for (var i = 0; i < off.length; i += 4) {
      if (off[i] != 0.0 || off[i + 1] != 0.0) moving++;
    }
    expect(moving, greaterThan(0));
    expect(marked, greaterThan(0));
  });

  test('with nothing that blends, the mask moves no byte', () {
    Float32List settle(double reactive) {
      final it = _staged(
        extra: (device, scene) => scene.add(
          MeshNode(
            DeviceMesh.upload(device, CuboidShape().build()),
            Material(lighting: LightingModel.unlit),
          )..setPosition(0.0, 0.0, -5.0),
        ),
      );
      late Float32List last;
      for (var i = 0; i < 6; i++) {
        last = _draw(it, _settings(reactive: reactive));
      }
      return last;
    }

    expect(settle(1.0), orderedEquals(settle(0.0)));
  });

  test('off by default, and its pass is where the order says', () {
    expect(const TemporalSettings().reactive, 0.0);
    final order = RenderSettings.passOrder;
    expect(
      order.indexOf('reactive mask'),
      order.indexOf('object velocity') + 1,
    );
  });
}
