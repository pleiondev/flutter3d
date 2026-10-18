/// The physics core's visual systems — particles, debris, cloth and the
/// fluid tank — as compute workloads: each one's step as kernels
/// (`particleKernels`, `debrisKernels`, `clothKernels`, `fluidKernels`,
/// which the core publishes beside the systems they step), handed to a
/// renderer, which runs it where the hardware layer's rule says.
///
/// **Here and not in the core**, because the core draws nothing and names
/// no device: it says what each step is in its own terms, and this file
/// says it in the engine's. **And it decides nothing about where.** A
/// workload is handed to `RendererSteps.addWorkload`; the hardware layer
/// puts it on the GPU that draws the frame, then on the compute sidecar
/// beside it, and where neither is it leaves it to its host — the core's
/// own system for the same step ([NativeParticles], [NativeDebris],
/// [NativeCloth], [NativeFluid]) — which it prefers to the CPU device,
/// whose Dart translation of the kernels was written for a GPU.
///
/// **Each is the system it steps.** A [ParticleCloudWorkload] is a
/// [NativeParticleCloud], a [DebrisWorkload] a [DebrisSystem], a
/// [ClothWorkload] a [ClothSystem] and a [FluidWorkload] a [FluidSystem],
/// so code written against the system steps it the same either way:
///
///  * **until it is placed**, what it is told is kept, and played where it
///    lands — on the host's system, or onto the device — so nothing is
///    lost to the moment the renderer took to place it; a read before then
///    has nothing to read;
///  * **on the host**, every call is the core system's own;
///  * **on a device**, each call is recorded, and the frame runs the steps
///    told since the last: what a read answers is read back a frame or two
///    late, and a read never waits, whatever `wait` says — the frame brings
///    it. Steps whose settings differ from the first told since the last
///    frame wait for the next frame, and so does anything told after them,
///    so they run in the order they were told;
///  * **taken out of the frame** (`released`), it goes back to its host,
///    rebuilt from what was read back last: the particles whole, the debris
///    without its spin and its turn, the cloth and the fluid where they
///    stood.
///
/// The tolerance each holds against the core's own step is in
/// `flutter3d_physics_native/doc/gpu_water.md`, *The visual systems*.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// How many workgroups of 64 cover [count].
int _groups(int count) => (count + 63) ~/ 64;

/// The smallest power of two at least [n], and at least one.
int _powerOfTwoAtLeast(int n) {
  var p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}

/// [values] as the bytes a buffer write takes.
ByteData _bytes(Float32List values) => ByteData.sublistView(values);

/// Whether two parameter blocks are the same, float for float.
bool _same(Float32List a, Float32List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i] && !(a[i].isNaN && b[i].isNaN)) return false;
  }
  return true;
}

/// One thing told to a workload placed on a device, in the order told: a
/// write, or a step.
sealed class _Told {
  const _Told();
}

/// [values] written into [buffer] at [offsetFloats].
final class _Write extends _Told {
  const _Write(this.buffer, this.offsetFloats, this.values);
  final String buffer;
  final int offsetFloats;
  final Float32List values;
}

/// A step under [params].
final class _Step extends _Told {
  const _Step(this.params);
  final Float32List params;
}

/// What the four workloads share: the name a frame calls each by, where it
/// landed, what was told before it landed, and the queue a device's frames
/// take from.
abstract base class _VisualWorkload<H extends Object> extends ComputeWorkload {
  _VisualWorkload(String kind) : name = '$kind ${_serial++}';

  static int _serial = 0;

  @override
  final String name;

  /// The core's own system: what steps it where no GPU is.
  @override
  bool get hasHost => true;

  /// Where it was last placed, or null before.
  WorkloadBinding? get binding => _binding;
  WorkloadBinding? _binding;

  /// The host's system, while it steps this.
  H? _host;

  /// What was told before it was placed, played where it lands.
  final List<void Function()> _beforePlacing = <void Function()>[];

  /// What was told since the last frame, while a device steps this.
  final List<_Told> _queue = <_Told>[];

  /// Whether the next frame writes the whole state first.
  bool _fresh = true;

  /// How many steps the device has run.
  int _ran = 0;

  bool _disposed = false;

  bool get _onDevice => _binding != null && !_binding!.isOnHost;

  /// Runs [onHost] on the host's system when there is one, records
  /// [onDevice] when a device steps it, and keeps both until it is placed.
  void _tell(void Function(H host) onHost, void Function() onDevice) {
    if (_disposed) throw StateError('$name was disposed');
    if (_host case final host?) return onHost(host);
    if (_onDevice) return onDevice();
    _beforePlacing.add(() {
      if (_host case final host?) {
        onHost(host);
      } else {
        onDevice();
      }
    });
  }

  /// Throws when it was disposed, as the core's systems do.
  void _checkLive() {
    if (_disposed) throw StateError('$name was disposed');
  }

  /// A new host system with nothing in it.
  H _makeHost();

  /// The host system rebuilt from what a device last read back.
  H _hostFromDevice();

  @override
  void placed(WorkloadBinding binding) {
    if (_disposed) return;
    final wasOnDevice = _onDevice;
    _binding = binding;
    if (binding.isOnHost) {
      _host ??= wasOnDevice ? _hostFromDevice() : _makeHost();
    } else {
      _hostLeft();
      _fresh = true;
    }
    _playTold();
  }

  /// The host's system let go, as a device takes the system over.
  void _hostLeft() {
    _host = null;
  }

  void _playTold() {
    final told = List<void Function()>.of(_beforePlacing);
    _beforePlacing.clear();
    for (final play in told) {
      play();
    }
  }

  @override
  void released() {
    if (_disposed) return;
    if (_onDevice) _host = _hostFromDevice();
    _binding = null;
    _queue.clear();
  }

  /// The writes a fresh device needs before anything told.
  void _writeFresh(WorkloadRecorder recorder) {}

  /// Records [steps] steps under [params]: their dispatches.
  void _dispatchSteps(WorkloadRecorder recorder, Float32List params, int steps);

  /// Asks for what [read] answers, as it stands after this frame's steps.
  void _readBack(WorkloadRecorder recorder, int ran);

  @override
  void record(WorkloadRecorder recorder) {
    if (_disposed || !_onDevice) return;
    if (_fresh) {
      _writeFresh(recorder);
      _fresh = false;
    }
    // Every write lands before the frame's first dispatch, so a frame takes
    // the writes told first, then the steps that follow them under one set
    // of parameters, and leaves the rest, in order, for the next.
    var at = 0;
    while (at < _queue.length && _queue[at] is _Write) {
      final w = _queue[at] as _Write;
      recorder.write(
        w.buffer,
        _bytes(w.values),
        offsetInBytes: w.offsetFloats * 4,
      );
      at += 1;
    }
    Float32List? params;
    var steps = 0;
    while (at < _queue.length) {
      final told = _queue[at];
      if (told is! _Step) break;
      if (params != null && !_same(params, told.params)) break;
      params = told.params;
      steps += 1;
      at += 1;
    }
    _queue.removeRange(0, at);
    if (params != null) {
      recorder.write('params', _bytes(params));
      _dispatchSteps(recorder, params, steps);
      _ran += steps;
    }
    _readBack(recorder, _ran);
  }

  /// Lets go of the host's system and of what is kept.
  void _disposeAll(void Function(H host) disposeHost) {
    if (_disposed) return;
    _disposed = true;
    if (_host case final host?) disposeHost(host);
    _host = null;
    _beforePlacing.clear();
    _queue.clear();
  }
}

// ------------------------------------------------------------- particles

/// Particles stepped where the hardware layer puts them: the core's
/// `ParticleStep` on a GPU, or [NativeParticles] on the host. See the
/// library comment.
final class ParticleCloudWorkload extends _VisualWorkload<NativeParticles>
    with NativeParticleCloud {
  /// [capacity] particle slots, filled round and round.
  ParticleCloudWorkload(this.capacity) : super('particles') {
    if (capacity <= 0 || capacity > 1 << 22) {
      throw ArgumentError.value(capacity, 'capacity', 'none, or too many');
    }
  }

  @override
  final int capacity;

  @override
  String get kernelSource => particleKernels;

  @override
  List<WorkloadBuffer> get buffers => <WorkloadBuffer>[
    WorkloadBuffer('slots', capacity * particleSlotFloats * 4, readable: true),
    const WorkloadBuffer('params', particleParamFloats * 4),
  ];

  /// The next slot a device fills.
  int _next = 0;

  /// The slots as a device last read them back.
  Float32List? _slots;

  @override
  NativeParticles _makeHost() => NativeParticles(capacity);

  @override
  NativeParticles _hostFromDevice() {
    final host = NativeParticles(capacity);
    final slots = _slots;
    if (slots == null) return host;
    host.emit(<NativeParticle>[
      for (var i = 0; i < capacity; i++)
        if (slots[i * particleSlotFloats + 3] > 0.0)
          NativeParticle(
            position: Vector3(
              slots[i * particleSlotFloats],
              slots[i * particleSlotFloats + 1],
              slots[i * particleSlotFloats + 2],
            ),
            velocity: Vector3(
              slots[i * particleSlotFloats + 4],
              slots[i * particleSlotFloats + 5],
              slots[i * particleSlotFloats + 6],
            ),
            life: slots[i * particleSlotFloats + 3],
          ),
    ]);
    return host;
  }

  @override
  void emit(List<NativeParticle> particles) {
    final copied = List<NativeParticle>.of(particles);
    _tell((NativeParticles host) => host.emit(copied), () {
      for (final p in copied) {
        _queue.add(
          _Write(
            'slots',
            _next * particleSlotFloats,
            Float32List.fromList(<double>[
              p.position.x,
              p.position.y,
              p.position.z,
              p.life,
              p.velocity.x,
              p.velocity.y,
              p.velocity.z,
              0.0,
            ]),
          ),
        );
        _next = (_next + 1) % capacity;
      }
    });
  }

  @override
  void step(ParticleCloudStep step) {
    if (!(step.dt > 0.0) || step.steps <= 0) return;
    final forces = step.forces;
    final params = Float32List(particleParamFloats)
      ..setAll(0, <double>[
        forces.gravity.x,
        forces.gravity.y,
        forces.gravity.z,
        0.0,
        forces.wind.x,
        forces.wind.y,
        forces.wind.z,
        0.0,
        forces.drag,
        forces.floorY == double.negativeInfinity ? -3.4e38 : forces.floorY,
        forces.restitution,
        forces.friction,
        step.dt,
      ]);
    final copied = ParticleCloudStep(
      forces: forces,
      dt: step.dt,
      steps: step.steps,
    );
    final count = step.steps;
    _tell((NativeParticles host) => host.step(copied), () {
      for (var s = 0; s < count; s++) {
        _queue.add(_Step(params));
      }
    });
  }

  @override
  void _dispatchSteps(
    WorkloadRecorder recorder,
    Float32List params,
    int steps,
  ) {
    for (var s = 0; s < steps; s++) {
      recorder.dispatch('ParticleStep', _groups(capacity));
    }
  }

  @override
  void _readBack(WorkloadRecorder recorder, int ran) {
    recorder.readBack('slots', (ByteData bytes) {
      _slots = Float32List.fromList(
        bytes.buffer.asFloat32List(
          bytes.offsetInBytes,
          capacity * particleSlotFloats,
        ),
      );
    });
  }

  /// Every slot, position xyz and the life left: on a device, as it was
  /// last read back, a frame or two behind; before it is placed, every
  /// slot dead.
  @override
  Float32List read() {
    _checkLive();
    if (_host case final host?) return host.read();
    final out = Float32List(capacity * 4);
    final slots = _slots;
    if (slots == null) return out;
    for (var i = 0; i < capacity; i++) {
      out.setRange(i * 4, i * 4 + 4, slots, i * particleSlotFloats);
    }
    return out;
  }

  @override
  void dispose() => _disposeAll((NativeParticles host) => host.dispose());
}

// ----------------------------------------------------------------- debris

/// Debris stepped where the hardware layer puts it: the core's debris
/// passes on a GPU, or [NativeDebris] on the host. See the library
/// comment.
final class DebrisWorkload extends _VisualWorkload<NativeDebris>
    with DebrisSystem {
  /// [capacity] debris slots, filled round and round.
  DebrisWorkload(this.capacity)
    : _cells = _powerOfTwoAtLeast(capacity * 2),
      super('debris') {
    if (capacity <= 0 || capacity > 1 << 20) {
      throw ArgumentError.value(capacity, 'capacity', 'none, or too many');
    }
  }

  @override
  final int capacity;

  /// The grid's cells: a power of two, twice the slots or more.
  final int _cells;

  @override
  String get kernelSource => debrisKernels;

  @override
  List<WorkloadBuffer> get buffers => <WorkloadBuffer>[
    WorkloadBuffer('bodies', capacity * debrisBodyFloats * 4, readable: true),
    WorkloadBuffer('motion', capacity * 8 * 4),
    WorkloadBuffer('contacts', capacity * 4),
    WorkloadBuffer('head', _cells * 4),
    WorkloadBuffer('next', capacity * 4),
    const WorkloadBuffer('statics', debrisMaxStatics * debrisStaticFloats * 4),
    const WorkloadBuffer('params', debrisParamFloats * 4),
  ];

  int _next = 0;
  int _staticCount = 0;
  double _maxRadius = 0.0;

  /// The bodies as a device last read them back, and the step they are
  /// from; whether that frame was read.
  Float32List? _bodies;
  int _readStep = 0;
  int _taken = 0;

  @override
  NativeDebris _makeHost() => NativeDebris(capacity);

  @override
  NativeDebris _hostFromDevice() {
    final host = NativeDebris(capacity);
    final bodies = _bodies;
    if (bodies == null) return host;
    host.add(<DebrisBody>[
      for (var i = 0; i < capacity; i++)
        if (bodies[i * debrisBodyFloats + 3] > 0.0)
          DebrisBody(
            position: Vector3(
              bodies[i * debrisBodyFloats],
              bodies[i * debrisBodyFloats + 1],
              bodies[i * debrisBodyFloats + 2],
            ),
            velocity: Vector3(
              bodies[i * debrisBodyFloats + 4],
              bodies[i * debrisBodyFloats + 5],
              bodies[i * debrisBodyFloats + 6],
            ),
            radius: bodies[i * debrisBodyFloats + 3],
            mass: 1.0 / bodies[i * debrisBodyFloats + 7],
          ),
    ]);
    return host;
  }

  @override
  void _writeFresh(WorkloadRecorder recorder) {
    // Every slot empty: radius nought, unturned.
    final empty = Float32List(capacity * debrisBodyFloats);
    for (var i = 0; i < capacity; i++) {
      empty[i * debrisBodyFloats + 15] = 1.0;
    }
    recorder.write('bodies', _bytes(empty));
  }

  @override
  void add(List<DebrisBody> bodies) {
    final copied = List<DebrisBody>.of(bodies);
    _tell((NativeDebris host) => host.add(copied), () {
      for (final b in copied) {
        final body = Float32List(debrisBodyFloats)..[15] = 1.0;
        final r = b.radius, m = b.mass;
        if (r.isFinite && m.isFinite && r > 0.0 && m > 0.0) {
          body
            ..[0] = b.position.x
            ..[1] = b.position.y
            ..[2] = b.position.z
            ..[3] = r
            ..[4] = b.velocity.x
            ..[5] = b.velocity.y
            ..[6] = b.velocity.z
            ..[7] = 1.0 / m
            ..[11] = 2.5 / (m * r * r);
          _maxRadius = math.max(
            _maxRadius,
            Float32List.fromList(<double>[r])[0],
          );
        }
        _queue.add(_Write('bodies', _next * debrisBodyFloats, body));
        _next = (_next + 1) % capacity;
      }
    });
  }

  @override
  void setStatics(List<DebrisStatic> statics) {
    if (statics.length > debrisMaxStatics) {
      throw ArgumentError.value(statics.length, 'statics', 'more than 64');
    }
    final copied = List<DebrisStatic>.of(statics);
    _tell((NativeDebris host) => host.setStatics(copied), () {
      final all = Float32List(debrisMaxStatics * debrisStaticFloats);
      for (var i = 0; i < copied.length; i++) {
        final o = i * debrisStaticFloats;
        switch (copied[i]) {
          case DebrisPlane(:final normal, :final offset):
            all
              ..[o] = normal.x
              ..[o + 1] = normal.y
              ..[o + 2] = normal.z
              ..[o + 3] = offset;
          case DebrisBox(:final center, :final halfExtents):
            all
              ..[o] = center.x
              ..[o + 1] = center.y
              ..[o + 2] = center.z
              ..[o + 4] = halfExtents.x
              ..[o + 5] = halfExtents.y
              ..[o + 6] = halfExtents.z
              ..[o + 7] = 1.0;
          default:
            throw UnsupportedError('no still shape for ${copied[i]}');
        }
      }
      _queue.add(_Write('statics', 0, all));
      _staticCount = copied.length;
    });
  }

  @override
  void step(DebrisSystemStep step) {
    if (!(step.dt > 0.0)) return;
    final settings = step.settings;
    final dt = step.dt;
    final copied = DebrisSystemStep(settings: settings, dt: dt);
    _tell((NativeDebris host) => host.step(copied), () {
      final cell = _f(_maxRadius * 3.0);
      if (!(cell > 0.0)) {
        // Nothing has a size yet: the step counts, and moves nothing.
        _queue.add(_Step(Float32List(debrisParamFloats)));
        return;
      }
      final substeps = math.max(settings.substeps, 1);
      final iterations = math.max(settings.iterations, 1);
      final h = _f(dt / substeps);
      final params = Float32List(debrisParamFloats)
        ..setAll(0, <double>[
          settings.gravity.x,
          settings.gravity.y,
          settings.gravity.z,
          h,
          settings.friction,
          settings.restitution,
          1.0 / (1.0 + _f(settings.linearDamping * h)),
          1.0 / (1.0 + _f(settings.angularDamping * h)),
          settings.maxSpeed,
          1.0 / cell,
          substeps.toDouble(),
          iterations.toDouble(),
          capacity.toDouble(),
          _cells.toDouble(),
          _staticCount.toDouble(),
        ]);
      _queue.add(_Step(params));
    });
  }

  @override
  void _dispatchSteps(
    WorkloadRecorder recorder,
    Float32List params,
    int steps,
  ) {
    // A step nothing had a size for moves nothing.
    if (params[3] == 0.0) return;
    final substeps = params[10].toInt(), iterations = params[11].toInt();
    final bodies = _groups(capacity), cells = _groups(_cells);
    for (var s = 0; s < steps * substeps; s++) {
      recorder
        ..dispatch('DebrisClearCells', cells)
        ..dispatch('DebrisGravityGrid', bodies)
        ..dispatch('DebrisCountContacts', bodies);
      for (var it = 0; it < iterations; it++) {
        if (it > 0) recorder.dispatch('DebrisAdopt', bodies);
        recorder.dispatch('DebrisSolve', bodies);
      }
      recorder.dispatch('DebrisIntegrate', bodies);
    }
  }

  @override
  void _readBack(WorkloadRecorder recorder, int ran) {
    if (ran == _readStep) return;
    recorder.readBack('bodies', (ByteData bytes) {
      _bodies = Float32List.fromList(
        bytes.buffer.asFloat32List(
          bytes.offsetInBytes,
          capacity * debrisBodyFloats,
        ),
      );
      _readStep = ran;
    });
  }

  /// The latest step's bodies not read yet; null when there is none. On a
  /// device, as they were last read back, a frame or two behind: a read
  /// never waits for one, whatever [wait] says.
  @override
  DebrisFrame? read({bool wait = true}) {
    _checkLive();
    if (_host case final host?) return host.read(wait: wait);
    final bodies = _bodies;
    if (bodies == null || _readStep == _taken) return null;
    _taken = _readStep;
    final out = Float32List(capacity * 8);
    for (var i = 0; i < capacity; i++) {
      final b = i * debrisBodyFloats, o = i * 8;
      out
        ..[o] = bodies[b]
        ..[o + 1] = bodies[b + 1]
        ..[o + 2] = bodies[b + 2]
        ..[o + 3] = bodies[b + 12]
        ..[o + 4] = bodies[b + 13]
        ..[o + 5] = bodies[b + 14]
        ..[o + 6] = bodies[b + 15]
        ..[o + 7] = bodies[b + 3];
    }
    return DebrisFrame(step: _readStep, bodies: out);
  }

  @override
  void dispose() => _disposeAll((NativeDebris host) => host.dispose());
}

/// [x] rounded to the nearest f32, as the core's float arithmetic leaves
/// it.
double _f(double x) => (Float32List(1)..[0] = x)[0];

// ------------------------------------------------------------------ cloth

/// Cloth stepped where the hardware layer puts it: the core's cloth
/// passes on a GPU, a dispatch a colour of the core's colouring
/// ([ClothColoring]), or [NativeCloth] on the host. See the library
/// comment.
final class ClothWorkload extends _VisualWorkload<NativeCloth>
    with ClothSystem {
  /// [mesh] as a cloth.
  ClothWorkload(this.mesh)
    : _colouring = ClothColoring.of(mesh),
      super('cloth');

  /// The cloth as it was made.
  final CoreClothMesh mesh;

  final ClothColoring _colouring;

  @override
  int get pointCount => mesh.points.length;

  @override
  String get kernelSource => clothKernels;

  @override
  List<WorkloadBuffer> get buffers => <WorkloadBuffer>[
    WorkloadBuffer(
      'position',
      pointCount * clothPointFloats * 4,
      readable: true,
    ),
    WorkloadBuffer('previous', pointCount * clothPointFloats * 4),
    WorkloadBuffer('velocity', pointCount * clothPointFloats * 4),
    WorkloadBuffer('edges', math.max(_colouring.edgeCount, 1) * 4 * 4),
    WorkloadBuffer('colours', math.max(_colouring.colorCount, 1) * 2 * 4),
    const WorkloadBuffer('colour', 4),
    const WorkloadBuffer('balls', clothMaxBalls * 4 * 4),
    const WorkloadBuffer('params', clothParamFloats * 4),
  ];

  int _ballCount = 0;

  /// The points as a device last read them back, and the step they are
  /// from.
  Float32List? _points;
  int _readStep = 0;
  int _taken = 0;

  /// The balls last told, which a host rebuilt from a device is told too.
  List<ClothBall> _balls = const <ClothBall>[];

  double _inverseMass(int i) => math.max(mesh.inverseMasses[i], 0.0);

  @override
  NativeCloth _makeHost() => NativeCloth(mesh);

  @override
  NativeCloth _hostFromDevice() {
    final points = _points;
    final host = NativeCloth(
      points == null
          ? mesh
          : CoreClothMesh(
              points: <Vector3>[
                for (var i = 0; i < pointCount; i++)
                  Vector3(
                    points[i * clothPointFloats],
                    points[i * clothPointFloats + 1],
                    points[i * clothPointFloats + 2],
                  ),
              ],
              inverseMasses: mesh.inverseMasses,
              edges: mesh.edges,
              compliances: mesh.compliances,
            ),
    );
    if (_balls.isNotEmpty) host.setBalls(_balls);
    return host;
  }

  @override
  void _writeFresh(WorkloadRecorder recorder) {
    final start = Float32List(pointCount * clothPointFloats);
    for (var i = 0; i < pointCount; i++) {
      start
        ..[i * 4] = mesh.points[i].x
        ..[i * 4 + 1] = mesh.points[i].y
        ..[i * 4 + 2] = mesh.points[i].z
        ..[i * 4 + 3] = _inverseMass(i);
    }
    final c = _colouring;
    final edges = Float32List(math.max(c.edgeCount, 1) * 4);
    for (var e = 0; e < c.edgeCount; e++) {
      edges
        ..[e * 4] = c.pairs[e * 2].toDouble()
        ..[e * 4 + 1] = c.pairs[e * 2 + 1].toDouble()
        ..[e * 4 + 2] = c.rest[e]
        ..[e * 4 + 3] = math.max(c.compliance[e], 0.0);
    }
    final colours = Uint32List(math.max(c.colorCount, 1) * 2);
    for (var k = 0; k < c.colorCount; k++) {
      colours
        ..[k * 2] = c.colorStart[k]
        ..[k * 2 + 1] = c.colorStart[k + 1] - c.colorStart[k];
    }
    recorder
      ..write('position', _bytes(start))
      ..write('previous', _bytes(start))
      ..write('edges', _bytes(edges))
      ..write('colours', ByteData.sublistView(colours));
  }

  @override
  void setBalls(List<ClothBall> balls) {
    if (balls.length > clothMaxBalls) {
      throw ArgumentError.value(balls.length, 'balls', 'more than 16');
    }
    final copied = List<ClothBall>.of(balls);
    _balls = copied;
    _tell((NativeCloth host) => host.setBalls(copied), () {
      final all = Float32List(clothMaxBalls * 4);
      for (var k = 0; k < copied.length; k++) {
        all
          ..[k * 4] = copied[k].center.x
          ..[k * 4 + 1] = copied[k].center.y
          ..[k * 4 + 2] = copied[k].center.z
          ..[k * 4 + 3] = copied[k].radius;
      }
      _queue.add(_Write('balls', 0, all));
      _ballCount = copied.length;
    });
  }

  @override
  void movePoint(ClothPointMove move) {
    final index = move.index;
    final at = move.at.clone();
    final copied = ClothPointMove(index: index, at: at);
    _tell((NativeCloth host) => host.movePoint(copied), () {
      if (index < 0 || index >= pointCount) return;
      _queue
        ..add(
          _Write(
            'position',
            index * clothPointFloats,
            Float32List.fromList(<double>[
              at.x,
              at.y,
              at.z,
              _inverseMass(index),
            ]),
          ),
        )
        ..add(_Write('velocity', index * clothPointFloats, Float32List(4)));
    });
  }

  @override
  void step(ClothSystemStep step) {
    if (!(step.dt > 0.0)) return;
    final s = step.settings;
    final dt = step.dt;
    final copied = ClothSystemStep(settings: s, dt: dt);
    _tell((NativeCloth host) => host.step(copied), () {
      final substeps = math.max(s.substeps, 1);
      final h = _f(dt / substeps);
      final params = Float32List(clothParamFloats)
        ..setAll(0, <double>[
          s.gravity.x,
          s.gravity.y,
          s.gravity.z,
          h,
          s.wind.x,
          s.wind.y,
          s.wind.z,
          1.0 / (1.0 + _f(s.drag * h)),
          1.0 / (1.0 + _f(s.damping * h)),
          1.0 / _f(h * h),
          s.floorY + s.thickness,
          s.thickness,
          s.friction,
          substeps.toDouble(),
          0.0,
          0.0,
          pointCount.toDouble(),
          _ballCount.toDouble(),
        ]);
      _queue.add(_Step(params));
    });
  }

  @override
  void _dispatchSteps(
    WorkloadRecorder recorder,
    Float32List params,
    int steps,
  ) {
    final substeps = params[13].toInt();
    final points = _groups(pointCount);
    final c = _colouring;
    for (var s = 0; s < steps * substeps; s++) {
      recorder.dispatch('ClothPredict', points);
      for (var k = 0; k < c.colorCount; k++) {
        final size = c.colorStart[k + 1] - c.colorStart[k];
        if (size > 0) recorder.dispatch('ClothSolve', _groups(size));
        recorder.dispatch('ClothNextColour', 1);
      }
      recorder.dispatch('ClothCollide', points);
    }
  }

  @override
  void _readBack(WorkloadRecorder recorder, int ran) {
    if (ran == _readStep) return;
    recorder.readBack('position', (ByteData bytes) {
      _points = Float32List.fromList(
        bytes.buffer.asFloat32List(
          bytes.offsetInBytes,
          pointCount * clothPointFloats,
        ),
      );
      _readStep = ran;
    });
  }

  /// The latest step's points not read yet; null when there is none. On a
  /// device, as they were last read back, a frame or two behind: a read
  /// never waits for one, whatever [wait] says.
  @override
  ClothFrame? read({bool wait = true}) {
    _checkLive();
    if (_host case final host?) return host.read(wait: wait);
    final points = _points;
    if (points == null || _readStep == _taken) return null;
    _taken = _readStep;
    return ClothFrame(step: _readStep, points: Float32List.fromList(points));
  }

  @override
  void dispose() => _disposeAll((NativeCloth host) => host.dispose());
}

// ------------------------------------------------------------------ fluid

/// A tank of fluid stepped where the hardware layer puts it: the core's
/// fluid passes on a GPU, or [NativeFluid] on the host. See the library
/// comment.
final class FluidWorkload extends _VisualWorkload<NativeFluid>
    with FluidSystem {
  /// Room for [capacity] particles, [spacing] apart at rest.
  FluidWorkload(this.capacity, this.spacing)
    : _cells = _powerOfTwoAtLeast(capacity * 2),
      super('fluid') {
    if (capacity <= 0 || capacity > 1 << 22) {
      throw ArgumentError.value(capacity, 'capacity', 'none, or too many');
    }
    if (!(spacing > 0.0) || !spacing.isFinite) {
      throw ArgumentError.value(spacing, 'spacing', 'not above nought');
    }
    final s = _f(spacing);
    final h = _f(s * 2.0);
    final h3 = _f(_f(h * h) * h);
    const pi = 3.14159265358979323846;
    _width = h;
    _poly6 = _f(315.0 / _f(_f(_f(_f(64.0 * _f(pi)) * h3) * h3) * h3));
    _spiky = _f(-45.0 / _f(_f(_f(pi) * h3) * h3));
    var rest = 0.0;
    for (var x = -2; x <= 2; x++) {
      for (var y = -2; y <= 2; y++) {
        for (var z = -2; z <= 2; z++) {
          final d = _f(_f(h * h) - _f(_f((x * x + y * y + z * z) * s) * s));
          if (d > 0.0) rest = _f(rest + _f(_f(_f(_poly6 * d) * d) * d));
        }
      }
    }
    _rest = rest;
  }

  @override
  final int capacity;

  /// How far apart the particles are at rest, in metres.
  final double spacing;

  final int _cells;
  late final double _width, _poly6, _spiky, _rest;

  int _count = 0;
  int _nextSlot = 0;

  @override
  int get count => _host?.count ?? _count;

  /// The density at rest, particles of mass one per cubic metre: the
  /// core's, worked out as the core works it out.
  @override
  double get restDensity => _host?.restDensity ?? _rest;

  @override
  String get kernelSource => fluidKernels;

  @override
  List<WorkloadBuffer> get buffers {
    final bytes = capacity * fluidParticleFloats * 4;
    return <WorkloadBuffer>[
      WorkloadBuffer('position', bytes, readable: true),
      WorkloadBuffer('predicted', bytes),
      WorkloadBuffer('velocity', bytes, readable: true),
      WorkloadBuffer('scratch', bytes),
      WorkloadBuffer('lam', bytes),
      WorkloadBuffer('head', _cells * 4),
      WorkloadBuffer('link', bytes),
      const WorkloadBuffer('params', fluidParamFloats * 4),
    ];
  }

  /// The particles and their velocities as a device last read them back,
  /// and the step they are from.
  Float32List? _positions;
  Float32List? _velocities;
  int _readStep = 0;
  int _taken = 0;

  @override
  NativeFluid _makeHost() => NativeFluid(capacity, spacing);

  @override
  NativeFluid _hostFromDevice() {
    final host = NativeFluid(capacity, spacing);
    final p = _positions, v = _velocities;
    if (p == null) return host;
    host.add(<FluidParticle>[
      for (var i = 0; i < _count; i++)
        FluidParticle(
          position: Vector3(p[i * 4], p[i * 4 + 1], p[i * 4 + 2]),
          velocity: v == null
              ? Vector3.zero()
              : Vector3(v[i * 4], v[i * 4 + 1], v[i * 4 + 2]),
        ),
    ]);
    return host;
  }

  @override
  void add(List<FluidParticle> particles) {
    final copied = List<FluidParticle>.of(particles);
    _tell((NativeFluid host) => host.add(copied), () {
      for (final p in copied) {
        final at = _nextSlot * fluidParticleFloats;
        _queue
          ..add(
            _Write(
              'position',
              at,
              Float32List.fromList(<double>[
                p.position.x,
                p.position.y,
                p.position.z,
                0.0,
              ]),
            ),
          )
          ..add(
            _Write(
              'velocity',
              at,
              Float32List.fromList(<double>[
                p.velocity.x,
                p.velocity.y,
                p.velocity.z,
                0.0,
              ]),
            ),
          );
        _nextSlot = (_nextSlot + 1) % capacity;
        if (_count < capacity) _count += 1;
      }
    });
  }

  @override
  void step(FluidSystemStep step) {
    if (!(step.dt > 0.0)) return;
    final s = step.settings;
    final dt = step.dt;
    final copied = FluidSystemStep(settings: s, dt: dt);
    _tell((NativeFluid host) => host.step(copied), () {
      if (_count == 0) return;
      final substeps = math.max(s.substeps, 1);
      final iterations = math.max(s.iterations, 1);
      final h = _f(dt / substeps);
      final margin = _f(_f(spacing) * 0.5);
      final params = Float32List(fluidParamFloats)
        ..setAll(0, <double>[
          s.gravity.x,
          s.gravity.y,
          s.gravity.z,
          h,
          _width,
          _poly6,
          _spiky,
          _rest,
          s.tankMin.x + margin,
          s.tankMin.y + margin,
          s.tankMin.z + margin,
          1.0 / _width,
          s.tankMax.x - margin,
          s.tankMax.y - margin,
          s.tankMax.z - margin,
          s.viscosity,
          s.relaxation,
          _f(spacing),
          substeps.toDouble(),
          iterations.toDouble(),
          _count.toDouble(),
          _cells.toDouble(),
          0.0,
          0.0,
          s.tankMin.x,
          s.tankMin.y,
          s.tankMin.z,
          0.0,
          s.tankMax.x,
          s.tankMax.y,
          s.tankMax.z,
        ]);
      _queue.add(_Step(params));
    });
  }

  @override
  void _dispatchSteps(
    WorkloadRecorder recorder,
    Float32List params,
    int steps,
  ) {
    final substeps = params[18].toInt(), iterations = params[19].toInt();
    final n = _groups(params[20].toInt()), cells = _groups(_cells);
    for (var s = 0; s < steps * substeps; s++) {
      recorder
        ..dispatch('FluidClearCells', cells)
        ..dispatch('FluidPredict', n);
      for (var it = 0; it < iterations; it++) {
        recorder
          ..dispatch('FluidDensity', n)
          ..dispatch('FluidSpread', n)
          ..dispatch('FluidAdoptSpread', n);
      }
      recorder
        ..dispatch('FluidVelocity', n)
        ..dispatch('FluidSmooth', n)
        ..dispatch('FluidFinish', n);
    }
  }

  @override
  void _readBack(WorkloadRecorder recorder, int ran) {
    if (ran == _readStep) return;
    final n = capacity * fluidParticleFloats;
    recorder
      ..readBack('velocity', (ByteData bytes) {
        _velocities = Float32List.fromList(
          bytes.buffer.asFloat32List(bytes.offsetInBytes, n),
        );
      })
      ..readBack('position', (ByteData bytes) {
        _positions = Float32List.fromList(
          bytes.buffer.asFloat32List(bytes.offsetInBytes, n),
        );
        _readStep = ran;
      });
  }

  /// The latest step's particles not read yet; null when there is none. On
  /// a device, as they were last read back, a frame or two behind: a read
  /// never waits for one, whatever [wait] says.
  @override
  FluidFrame? read({bool wait = true}) {
    _checkLive();
    if (_host case final host?) return host.read(wait: wait);
    final p = _positions;
    if (p == null || _readStep == _taken) return null;
    _taken = _readStep;
    return FluidFrame(
      step: _readStep,
      particles: Float32List.fromList(p.sublist(0, _count * 4)),
    );
  }

  @override
  void dispose() => _disposeAll((NativeFluid host) => host.dispose());
}
