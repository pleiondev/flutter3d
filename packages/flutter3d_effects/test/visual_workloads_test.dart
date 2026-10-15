/// The physics core's visual systems handed to the engine as compute
/// workloads — particles, debris, cloth and the fluid tank — against the
/// core's own steps, within the tolerances
/// `flutter3d_physics_native/doc/gpu_water.md` gives under *The visual
/// systems*.
///
///     dart test test/visual_workloads_test.dart
///
/// Each runs where the hardware layer puts it, read back through its test
/// seam (`computePlacementOf`), on machines set up the way a registry sets
/// them up: the software device made to stand in for a GPU
/// (`cpuComputeDeviceStandingInForGpu`) drawing the frame, which runs the kernels'
/// Dart translation; the real wgpu sidecar beside a drawing device without
/// compute, which runs their WGSL on the machine's GPU (skipped where it
/// will not start); and the plain software device, which leaves each to
/// the core. Nothing asks for a placement. The scenes on the stand-in are
/// smaller than on the sidecar: its kernels are interpreted one
/// invocation at a time.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart'
    show cpuComputeDeviceStandingInForGpu;
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart'
    show FakeBackend, computePlacementOf;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_wgpu/flutter3d_wgpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A renderer drawing an empty frame on [device], which keeps the
/// workloads added to it in the frame; and the frame.
({Renderer renderer, Future<void> Function() frame}) _renderer(
  GraphicsDevice device,
) {
  final renderer = Renderer.create(device: device);
  final camera = CameraNode()..setPosition(0.0, 2.0, 2.0);
  camera.lookAt(Vector3.zero());
  final scene = Scene()..add(camera);
  return (
    renderer: renderer,
    frame: () async {
      renderer.render(
        width: 8,
        height: 8,
        scene: scene,
        views: <CameraView>[CameraView(camera: camera)],
      );
      // The reads back land on the host's own turn.
      await Future<void>.delayed(Duration.zero);
    },
  );
}

/// A machine a workload is placed on, as a registry would set it up.
typedef _Machine = ({
  String name,
  Future<GraphicsDevice?> Function() open,
  ComputePlacement? lands,
});

/// The software device standing in for the GPU that draws.
final _Machine _standIn = (
  name: 'on the software device standing in for a GPU',
  open: () async => cpuComputeDeviceStandingInForGpu(),
  lands: ComputePlacement.device,
);

/// The wgpu sidecar beside a drawing device without compute; null where
/// it will not start.
final _Machine _sidecar = (
  name: 'on the wgpu sidecar',
  open: () async {
    final registry = DeviceRegistry<Object>();
    final sidecar = registerWgpuSidecar(registry);
    addTearDown(sidecar.cancel);
    final executors = await registry.computeExecutors(FakeBackend());
    if (executors.sidecar == null) return null;
    executors.sidecar!.dispose();
    final drawing = FakeBackend(maxColorAttachments: 4);
    registry.adopt(drawing);
    return drawing;
  },
  lands: ComputePlacement.sidecar,
);

/// Adds [workload] to a renderer on [machine]'s device and checks where
/// the hardware layer put it; null where the machine will not start.
Future<Future<void> Function()?> _place(
  _Machine machine,
  ComputeWorkload workload,
) async {
  final device = await machine.open();
  if (device == null) {
    markTestSkipped('no wgpu sidecar here');
    return null;
  }
  final (:renderer, :frame) = _renderer(device);
  final added = renderer.renderSteps.addWorkload(workload);
  await renderer.renderSteps.whenPlaced();
  addTearDown(added.cancel);
  final binding = renderer.renderSteps.workloadStep(workload)!.binding!;
  expect(computePlacementOf(binding.site!), machine.lands);
  return frame;
}

/// Frames drawn until [read] answers, at most [most].
Future<T> _until<T>(
  Future<void> Function() frame,
  T? Function() read, {
  int most = 8,
}) async {
  for (var i = 0; i < most; i++) {
    await frame();
    if (read() case final T value) return value;
  }
  throw StateError('nothing was read back in $most frames');
}

double _worst(Float32List a, Float32List b) {
  expect(b.length, a.length);
  var worst = 0.0;
  for (var i = 0; i < a.length; i++) {
    worst = math.max(worst, (a[i] - b[i]).abs());
  }
  return worst;
}

// ------------------------------------------------------------- particles

/// [n] particles thrown every way from a grid above a floor.
List<NativeParticle> _spray(int n) => <NativeParticle>[
  for (var i = 0; i < n; i++)
    NativeParticle(
      position: Vector3(
        (i % 10).toDouble(),
        1.0 + (i % 7) * 0.1,
        (i ~/ 100).toDouble(),
      ),
      velocity: Vector3(
        ((i * 37) % 11) - 5.0,
        ((i * 13) % 9).toDouble(),
        ((i * 7) % 5) - 2.0,
      ),
      life: 0.5 + (i % 30) * 0.1,
    ),
];

final ParticleForces _weather = ParticleForces(
  wind: Vector3(2.0, 0.0, 1.0),
  drag: 0.5,
  floorY: 0.0,
  restitution: 0.6,
  friction: 0.2,
);

/// [n] particles stepped for two seconds in [frames] frames by the
/// workload on [machine] and by the core: the worst float apart.
Future<double?> _particles(_Machine machine, int n, int frames) async {
  final cpu = NativeParticles(n);
  addTearDown(cpu.dispose);
  final onDevice = ParticleCloudWorkload(n);
  addTearDown(onDevice.dispose);
  // Told before it is placed: played where it lands.
  onDevice.emit(_spray(n));
  cpu.emit(_spray(n));
  final frame = await _place(machine, onDevice);
  if (frame == null) return null;
  final per = 120 ~/ frames;
  for (var f = 0; f < frames; f++) {
    final step = ParticleCloudStep(forces: _weather, dt: 1 / 60, steps: per);
    cpu.step(step);
    onDevice.step(step);
    await frame();
  }
  await frame();
  await frame();
  return _worst(cpu.read(), onDevice.read());
}

// ----------------------------------------------------------------- debris

/// A pen two metres wide: a floor and four walls.
final List<DebrisStatic> _pen = <DebrisStatic>[
  DebrisPlane(Vector3(0.0, 1.0, 0.0), 0.0),
  DebrisPlane(Vector3(1.0, 0.0, 0.0), -1.0),
  DebrisPlane(Vector3(-1.0, 0.0, 0.0), -1.0),
  DebrisPlane(Vector3(0.0, 0.0, 1.0), -1.0),
  DebrisPlane(Vector3(0.0, 0.0, -1.0), -1.0),
];

/// [n] balls of three sizes in layers of a hundred above the pen.
List<DebrisBody> _pour(int n) => <DebrisBody>[
  for (var i = 0; i < n; i++)
    DebrisBody(
      position: Vector3(
        -0.85 + (i % 10) * 0.19 + (i % 3) * 0.01,
        0.3 + (i ~/ 100) * 0.25,
        -0.85 + ((i ~/ 10) % 10) * 0.19,
      ),
      velocity: Vector3(0.0, -1.0, 0.0),
      radius: 0.05 + (i % 3) * 0.02,
      mass: 1.0,
    ),
];

double _meanHeight(Float32List bodies) {
  var sum = 0.0;
  for (var i = 0; i < bodies.length ~/ 8; i++) {
    sum += bodies[i * 8 + 1];
  }
  return sum / (bodies.length ~/ 8);
}

/// How far into another any ball sits, over the smaller radius, and how
/// many are through the floor or a wall by more than a centimetre.
({double overlap, int leaked}) _heap(Float32List b) {
  final n = b.length ~/ 8;
  var overlap = 0.0;
  var leaked = 0;
  for (var i = 0; i < n; i++) {
    final r = b[i * 8 + 7];
    if (b[i * 8 + 1] < r - 0.01 ||
        b[i * 8].abs() > 1 - r + 0.01 ||
        b[i * 8 + 2].abs() > 1 - r + 0.01) {
      leaked++;
    }
    for (var j = i + 1; j < n; j++) {
      final dx = b[i * 8] - b[j * 8];
      final dy = b[i * 8 + 1] - b[j * 8 + 1];
      final dz = b[i * 8 + 2] - b[j * 8 + 2];
      final depth = r + b[j * 8 + 7] - math.sqrt(dx * dx + dy * dy + dz * dz);
      overlap = math.max(overlap, depth / math.min(r, b[j * 8 + 7]));
    }
  }
  return (overlap: overlap, leaked: leaked);
}

/// Three balls of different sizes and masses stacked on a floor, each pair
/// counting different contacts on either side, by the workload on
/// [machine] and by the core, compared every tenth step.
Future<void> _stack(_Machine machine) async {
  final bodies = <DebrisBody>[
    for (var i = 0; i < 3; i++)
      DebrisBody(
        position: Vector3(0.0, 0.15 + i * 0.35, 0.0),
        velocity: Vector3.zero(),
        radius: 0.15 - i * 0.03,
        mass: 4.0 - i * 1.5,
      ),
  ];
  final cpu = NativeDebris(3);
  addTearDown(cpu.dispose);
  final onDevice = DebrisWorkload(3);
  addTearDown(onDevice.dispose);
  for (final DebrisSystem d in <DebrisSystem>[cpu, onDevice]) {
    d
      ..setStatics(_pen.sublist(0, 1))
      ..add(bodies);
  }
  final frame = await _place(machine, onDevice);
  if (frame == null) return;
  final settings = DebrisSettings(restitution: 0.0);
  for (var step = 1; step <= 120; step++) {
    cpu.step(DebrisSystemStep(settings: settings, dt: 1 / 60));
    onDevice.step(DebrisSystemStep(settings: settings, dt: 1 / 60));
    await frame();
    if (step % 10 != 0) continue;
    final x = cpu.read()!;
    final y = await _until(
      frame,
      () => switch (onDevice.read()) {
        final f? when f.step == step => f,
        _ => null,
      },
    );
    expect(x.step, y.step);
    expect(_worst(x.bodies, y.bodies), lessThan(1e-4), reason: 'step $step');
  }
}

/// [n] balls poured into the pen for [steps] steps by the workload on
/// [machine] and by the core: falling, body for body before they meet;
/// settled, the same heap.
Future<void> _pourInto(_Machine machine, int n, int steps) async {
  final cpu = NativeDebris(n);
  addTearDown(cpu.dispose);
  final onDevice = DebrisWorkload(n);
  addTearDown(onDevice.dispose);
  for (final DebrisSystem d in <DebrisSystem>[cpu, onDevice]) {
    d
      ..setStatics(_pen)
      ..add(_pour(n));
  }
  final frame = await _place(machine, onDevice);
  if (frame == null) return;
  final settings = DebrisSettings(restitution: 0.0);
  Future<DebrisFrame> stepTo(int to) async {
    for (var s = 0; s < to; s++) {
      cpu.step(DebrisSystemStep(settings: settings, dt: 1 / 60));
      onDevice.step(DebrisSystemStep(settings: settings, dt: 1 / 60));
      await frame();
    }
    return _until(frame, () => onDevice.read());
  }

  final falling = await stepTo(5);
  expect(_worst(cpu.read()!.bodies, falling.bodies), lessThan(1e-4));
  final settled = (await stepTo(steps - 5)).bodies;
  final settledCpu = cpu.read()!.bodies;
  expect(
    _meanHeight(settled),
    closeTo(_meanHeight(settledCpu), 0.01 * _meanHeight(settledCpu)),
  );
  final heap = _heap(settled);
  expect(heap.leaked, 0);
  expect(heap.overlap, lessThan(0.1));
}

// ------------------------------------------------------------------ cloth

/// A sheet a metre square hanging from the two corners of its first row.
CoreClothMesh _sheet(int side) => CoreClothMesh.grid(
  columns: side,
  rows: side,
  origin: Vector3(-0.5, 0.0, -0.5),
  pinned: <int>{0, side - 1},
);

/// Nothing folds in these, so point for point every tenth step, to half a
/// millimetre: a rigid pendulum, a damped spring in a wind, a rod dropped
/// onto a ball that slides off it, and loose points blown along the floor.
final List<(CoreClothMesh, CoreClothSettings, List<ClothBall>)> _clothScenes =
    <(CoreClothMesh, CoreClothSettings, List<ClothBall>)>[
      (
        CoreClothMesh(
          points: <Vector3>[Vector3.zero(), Vector3(1.0, 0.0, 0.0)],
          inverseMasses: <double>[0.0, 1.0],
          edges: <(int, int)>[(0, 1)],
          compliances: <double>[0.0],
        ),
        CoreClothSettings(damping: 0.0),
        <ClothBall>[],
      ),
      (
        CoreClothMesh(
          points: <Vector3>[Vector3.zero(), Vector3(0.0, -1.0, 0.0)],
          inverseMasses: <double>[0.0, 1.0],
          edges: <(int, int)>[(0, 1)],
          compliances: <double>[1e-3],
        ),
        CoreClothSettings(
          damping: 2.0,
          wind: Vector3(3.0, 0.0, 0.0),
          drag: 0.5,
        ),
        <ClothBall>[],
      ),
      (
        CoreClothMesh(
          points: <Vector3>[Vector3(0.1, 1.0, 0.0), Vector3(0.3, 1.0, 0.05)],
          inverseMasses: <double>[2.0, 2.0],
          edges: <(int, int)>[(0, 1)],
          compliances: <double>[1e-6],
        ),
        CoreClothSettings(floorY: 0.0, friction: 0.2),
        <ClothBall>[ClothBall(center: Vector3(0.0, 0.3, 0.0), radius: 0.3)],
      ),
      (
        CoreClothMesh(
          points: <Vector3>[Vector3(0.0, 0.5, 0.0), Vector3(0.3, 0.2, 0.0)],
          inverseMasses: <double>[1.0, 1.0],
          edges: <(int, int)>[],
          compliances: <double>[],
        ),
        CoreClothSettings(
          floorY: 0.1,
          thickness: 0.02,
          friction: 0.4,
          wind: Vector3(2.0, 0.0, 1.0),
          drag: 1.0,
        ),
        <ClothBall>[],
      ),
    ];

Future<void> _clothPoints(_Machine machine) async {
  for (final (mesh, settings, balls) in _clothScenes) {
    final cpu = NativeCloth(mesh);
    addTearDown(cpu.dispose);
    final onDevice = ClothWorkload(mesh);
    addTearDown(onDevice.dispose);
    cpu.setBalls(balls);
    onDevice.setBalls(balls);
    final frame = await _place(machine, onDevice);
    if (frame == null) return;
    for (var step = 1; step <= 120; step++) {
      cpu.step(ClothSystemStep(settings: settings, dt: 1 / 60));
      onDevice.step(ClothSystemStep(settings: settings, dt: 1 / 60));
      await frame();
      if (step % 10 != 0) continue;
      final x = cpu.read()!.points;
      final y = await _until(
        frame,
        () => switch (onDevice.read()) {
          final f? when f.step == step => f,
          _ => null,
        },
      );
      expect(_worst(x, y.points), lessThan(5e-4), reason: 'step $step');
    }
  }
}

/// How much longer than it started the longest structural edge of a
/// [side] × [side] sheet a metre wide is, as a fraction.
double _stretch(Float32List p, int side) {
  var worst = 0.0;
  for (var j = 0; j < side; j++) {
    for (var i = 0; i + 1 < side; i++) {
      final a = (j * side + i) * 4;
      final b = a + 4;
      final d = math.sqrt(
        math.pow(p[a] - p[b], 2) +
            math.pow(p[a + 1] - p[b + 1], 2) +
            math.pow(p[a + 2] - p[b + 2], 2),
      );
      worst = math.max(worst, d * (side - 1) - 1.0);
    }
  }
  return worst;
}

double _lowest(Float32List p) {
  var low = double.infinity;
  for (var i = 1; i < p.length; i += 4) {
    low = math.min(low, p[i]);
  }
  return low;
}

/// A [side]² sheet hung for three seconds: point for point while it falls,
/// then the same sheet; and its pins carried where they are moved.
Future<void> _hang(_Machine machine, int side) async {
  final cpu = NativeCloth(_sheet(side));
  addTearDown(cpu.dispose);
  final onDevice = ClothWorkload(_sheet(side));
  addTearDown(onDevice.dispose);
  final frame = await _place(machine, onDevice);
  if (frame == null) return;
  final settings = CoreClothSettings(damping: 1.0);
  Future<ClothFrame> stepTo(int to) async {
    for (var s = 0; s < to; s++) {
      cpu.step(ClothSystemStep(settings: settings, dt: 1 / 60));
      onDevice.step(ClothSystemStep(settings: settings, dt: 1 / 60));
      await frame();
    }
    return _until(frame, () => onDevice.read());
  }

  final falling = await stepTo(30);
  expect(_worst(cpu.read()!.points, falling.points), lessThan(1e-4));
  final settled = (await stepTo(150)).points;
  final settledCpu = cpu.read()!.points;
  expect(
    <double>[settled[0], settled[1], settled[2]],
    <double>[-0.5, 0.0, -0.5],
  );
  expect(_stretch(settled, side), closeTo(_stretch(settledCpu, side), 0.005));
  expect(_lowest(settled), closeTo(_lowest(settledCpu), 0.01));
  // Its pins carried up a metre.
  onDevice
    ..movePoint(ClothPointMove(index: 0, at: Vector3(-0.5, 1.0, -0.5)))
    ..movePoint(ClothPointMove(index: side - 1, at: Vector3(0.5, 1.0, -0.5)));
  final lifted = (await stepTo(30)).points;
  expect(lifted[1], 1.0);
  expect(lifted[(side - 1) * 4 + 1], 1.0);
}

// ------------------------------------------------------------------ fluid

/// A tank a metre long, half a metre wide.
FluidSettings _tank() => FluidSettings(
  tankMin: Vector3(-0.5, 0.0, -0.25),
  tankMax: Vector3(0.5, 2.0, 0.25),
);

/// A block of [n]³ particles 5 cm apart against the tank's low end.
List<FluidParticle> _dam(int n) => <FluidParticle>[
  for (var i = 0; i < n * n * n; i++)
    FluidParticle(
      position: Vector3(
        -0.475 + (i % n) * 0.05,
        0.025 + (i ~/ (n * n)) * 0.05,
        -0.225 + ((i ~/ n) % n) * 0.05,
      ),
      velocity: Vector3.zero(),
    ),
];

/// Two particles passing each other, too few to push: viscosity alone,
/// point for point every tenth step; then a dam of [side]³ slumping, point
/// for point before it splashes.
Future<void> _fluid(_Machine machine, int side) async {
  final pair = <FluidParticle>[
    FluidParticle(
      position: Vector3(0.0, 1.0, 0.0),
      velocity: Vector3(0.0, 0.0, 0.02),
    ),
    FluidParticle(
      position: Vector3(0.06, 1.0, 0.0),
      velocity: Vector3(0.0, 0.0, -0.02),
    ),
  ];
  final cpu = NativeFluid(2, 0.05)..add(pair);
  addTearDown(cpu.dispose);
  final onDevice = FluidWorkload(2, 0.05)..add(pair);
  addTearDown(onDevice.dispose);
  final frame = await _place(machine, onDevice);
  if (frame == null) return;
  expect(onDevice.restDensity, closeTo(cpu.restDensity, 1e-3));
  final still = FluidSettings(
    tankMin: Vector3(-1.0, 0.0, -1.0),
    tankMax: Vector3(1.0, 2.0, 1.0),
    gravity: Vector3.zero(),
    viscosity: 0.5,
  );
  for (var step = 1; step <= 60; step++) {
    cpu.step(FluidSystemStep(settings: still, dt: 1 / 60));
    onDevice.step(FluidSystemStep(settings: still, dt: 1 / 60));
    await frame();
    if (step % 10 != 0) continue;
    final x = cpu.read()!.particles;
    final y = await _until(
      frame,
      () => switch (onDevice.read()) {
        final f? when f.step == step => f,
        _ => null,
      },
    );
    expect(_worst(x, y.particles), lessThan(1e-5), reason: 'step $step');
  }

  final n = side * side * side;
  final damCpu = NativeFluid(n, 0.05)..add(_dam(side));
  addTearDown(damCpu.dispose);
  final dam = FluidWorkload(n, 0.05)..add(_dam(side));
  addTearDown(dam.dispose);
  final damFrame = await _place(machine, dam);
  if (damFrame == null) return;
  for (var i = 0; i < 5; i++) {
    damCpu.step(FluidSystemStep(settings: _tank(), dt: 1 / 60));
    dam.step(FluidSystemStep(settings: _tank(), dt: 1 / 60));
    await damFrame();
  }
  final slumping = await _until(damFrame, () => dam.read());
  expect(slumping.step, 5);
  expect(_worst(damCpu.read()!.particles, slumping.particles), lessThan(1e-4));
}

void main() {
  group('particles', () {
    test('step as the core steps them on the stand-in', () async {
      // Mutation: drag the velocity towards the wind the wrong way round,
      // and the spray lands metres off the core's.
      expect(await _particles(_standIn, 100, 12), lessThan(1e-4));
    });

    test('step as the core steps them on the wgpu sidecar', () async {
      final worst = await _particles(_sidecar, 1000, 4);
      if (worst != null) expect(worst, lessThan(1e-4));
    });
  });

  group('debris', () {
    test('stacks as the core stacks on the stand-in', () => _stack(_standIn));

    test(
      'stacks as the core stacks on the wgpu sidecar',
      () => _stack(_sidecar),
    );

    test('pours the heap the core pours on the stand-in', () async {
      // Mutation: an impulse shared over its own contacts only, not over the
      // other body's, and the heap sinks into itself.
      await _pourInto(_standIn, 60, 90);
    });

    test('pours the heap the core pours on the wgpu sidecar', () async {
      await _pourInto(_sidecar, 1000, 240);
    });
  });

  group('cloth', () {
    test('swings, springs and slides as the core does on the stand-in', () {
      // Mutation: solve the colours in another order, and the pendulum's
      // swing leaves the core's by more than half a millimetre.
      return _clothPoints(_standIn);
    });

    test('swings, springs and slides as the core does on the wgpu sidecar', () {
      return _clothPoints(_sidecar);
    });

    test('hangs the sheet the core hangs on the stand-in', () {
      return _hang(_standIn, 8);
    });

    test('hangs the sheet the core hangs on the wgpu sidecar', () {
      return _hang(_sidecar, 32);
    });
  });

  group('fluid', () {
    test('slides a viscous pair and slumps a dam as the core does on the '
        'stand-in', () {
      // Mutation: a neighbour walk that stops at the first cell, and the
      // dam's density is a twenty-seventh of the core's.
      return _fluid(_standIn, 4);
    });

    test('slides a viscous pair and slumps a dam as the core does on the '
        'wgpu sidecar', () {
      return _fluid(_sidecar, 10);
    });
  });

  test('a software device leaves each to the core, bit for bit', () async {
    // Mutation: place a system with host code on a device that computes on
    // the CPU, and its kernels run interpreted while the core sits idle.
    final device = cpuComputeDevice();
    final (:renderer, :frame) = _renderer(device);
    final cpu = NativeParticles(50)..emit(_spray(50));
    addTearDown(cpu.dispose);
    final onHost = ParticleCloudWorkload(50)..emit(_spray(50));
    addTearDown(onHost.dispose);
    final added = renderer.renderSteps.addWorkload(onHost);
    await renderer.renderSteps.whenPlaced();
    addTearDown(added.cancel);
    expect(
      renderer.renderSteps.workloadStep(onHost)!.binding!.isOnHost,
      isTrue,
    );
    final step = ParticleCloudStep(forces: _weather, dt: 1 / 60, steps: 30);
    cpu.step(step);
    onHost.step(step);
    await frame();
    expect(onHost.read(), cpu.read());
  });

  test(
    'taken out of the frame, it goes back to the core where it stood',
    () async {
      // Mutation: drop what was read back when the frame lets go, and the
      // particles start again from nothing.
      final device = cpuComputeDeviceStandingInForGpu();
      final (:renderer, :frame) = _renderer(device);
      final onDevice = ParticleCloudWorkload(20)..emit(_spray(20));
      addTearDown(onDevice.dispose);
      final added = renderer.renderSteps.addWorkload(onDevice);
      await renderer.renderSteps.whenPlaced();
      onDevice.step(ParticleCloudStep(forces: _weather, dt: 1 / 60, steps: 10));
      await frame();
      await frame();
      final before = onDevice.read();
      added.cancel();
      // Let go once no frame in flight can still be using it.
      for (var i = 0; i < 4; i++) {
        await frame();
      }
      // Read from the core now, the same particles.
      expect(_worst(before, onDevice.read()), lessThan(1e-6));
      onDevice.step(ParticleCloudStep(forces: _weather, dt: 1 / 60, steps: 10));
      expect(_worst(before, onDevice.read()), greaterThan(0.0));
    },
  );

  test('a disposed workload says so', () {
    final w = ParticleCloudWorkload(4)..dispose();
    expect(() => w.read(), throwsStateError);
    expect(() => w.emit(const <NativeParticle>[]), throwsStateError);
    expect(() => ParticleCloudWorkload(0), throwsArgumentError);
  });
}
