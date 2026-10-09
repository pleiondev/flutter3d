/// The WebAssembly module steps to the bits the native library steps to —
/// P9.
///
///     dart test test/wasm_test.dart
///
/// The deterministic mode's promise, held across the two builds a game
/// ships: the module `tool/build_wasm.dart` makes, run in node, and the
/// library the hook makes, run through `dart:ffi`, given the same bodies and
/// the same steps, must agree to the last bit of every float — not to a
/// tolerance. Skipped where there is no node, no clang with the wasm32
/// target, or no wasm linker.
@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_physics_native/src/core/layout.g.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import '../tool/build_wasm.dart';

/// The scenario both builds run: five bodies, thrown at awkward speeds
/// under tilted gravity, six hundred steps of a sixtieth of a second. Each
/// gets a shape, a spin and wood to be made of; the second is lit and the
/// fourth wet, and a wind grid blows through them all, so the comparison
/// reaches the turn, the drag, the heat and the fire.
const List<List<double>> _bodies = <List<double>>[
  // position xyz, velocity xyz, shape kind, size a b c, spin xyz, kelvin,
  // water
  <double>[0.0, 20.0, 0.0, 0.0, 0.0, 0.0, 1, 0.2, 0, 0, 0, 0, 0, 293.15, 0],
  <double>[
    -3.0,
    5.0,
    2.0,
    4.1,
    6.3,
    -1.7,
    2,
    0.1,
    0.3,
    0.5,
    2,
    0.5,
    0.25,
    690,
    0,
  ],
  <double>[
    1.25,
    0.5,
    -7.5,
    -0.3,
    11.9,
    0.01,
    3,
    0.1,
    0.4,
    0,
    -1,
    3,
    0.1,
    293.15,
    0,
  ],
  <double>[
    100.0,
    -2.0,
    3.3,
    0.7,
    0.2,
    -9.9,
    2,
    0.05,
    0.05,
    0.05,
    0,
    0,
    7,
    500,
    0.02,
  ],
  <double>[
    0.001,
    0.002,
    0.003,
    1e-3,
    -2e-4,
    3e-5,
    4,
    0.2,
    0.3,
    0,
    0.5,
    0,
    0,
    293.15,
    0,
  ],
];
const List<double> _gravity = <double>[0.3, -9.81, -0.07];
const List<double> _wind = <double>[1.5, 0.0, -0.5];

/// Two by one by two samples, five metres apart, from (−5, 0, −5).
const List<double> _grid = <double>[1, 0, 0, 0, 0, 2, -1, 0.5, 0, 0, 3, 0];
const int _steps = 600;
const double _dt = 1.0 / 60.0;

const String _runner = r'''
const fs = require('fs');
const { Worker, isMainThread, workerData } = require('worker_threads');
if (!isMainThread) {
  // A worker: an instance of the threads module on the main one's memory,
  // with a stack of its own, waiting in the core for its share of a pass.
  const { module, memory, index, top } = workerData;
  const w = new WebAssembly.Instance(module, { env: { memory } });
  w.exports.__stack_pointer.value = top;
  w.exports.f3d_worker_main(index);
  return;
}
(async () => {
const [wasmPath, scenarioJson] = process.argv.slice(2);
const { bodies, gravity, wind, grid, steps, dt, threads, materialBytes } = JSON.parse(scenarioJson);
const module = new WebAssembly.Module(fs.readFileSync(wasmPath));
let memory = null;
let instance;
if (threads > 1) {
  memory = new WebAssembly.Memory({ initial: 256, maximum: 32768, shared: true });
  instance = new WebAssembly.Instance(module, { env: { memory } });
  for (let i = 0; i < threads - 1; i++) {
    const stack = instance.exports.f3d_buffer_alloc(1 << 20);
    new Worker(__filename, { workerData: { module, memory, index: i, top: stack + (1 << 20) } });
  }
  while (instance.exports.f3d_wasm_workers_ready() < threads - 1) {
    await new Promise((r) => setTimeout(r, 5));
  }
} else {
  instance = new WebAssembly.Instance(module, {});
}
const f = instance.exports;
const heap = () => (memory || f.memory).buffer;
const world = f.f3d_world_create();
if (threads > 1 && f.f3d_world_set_threads(world, threads) !== 1) throw new Error('no threads');
f.f3d_world_set_gravity(world, gravity[0], gravity[1], gravity[2]);
f.f3d_world_set_wind(world, wind[0], wind[1], wind[2]);
const gridPtr = f.f3d_buffer_alloc(grid.length * 4);
new Float32Array(heap(), gridPtr, grid.length).set(grid);
f.f3d_world_set_wind_grid(world, -5, 0, -5, 5, 2, 1, 2, gridPtr);
f.f3d_buffer_free(gridPtr);
const material = f.f3d_buffer_alloc(materialBytes);
f.f3d_material_preset(1, material);
for (const b of bodies) {
  const h = f.f3d_body_create(world, 0, b[0], b[1], b[2], 1.0);
  f.f3d_body_set_velocity(world, h, b[3], b[4], b[5]);
  f.f3d_body_set_shape(world, h, b[6], b[7], b[8], b[9]);
  f.f3d_body_set_angular_velocity(world, h, b[10], b[11], b[12]);
  f.f3d_body_set_material(world, h, material);
  f.f3d_body_set_temperature(world, h, b[13]);
  f.f3d_body_add_water(world, h, b[14]);
}
f.f3d_buffer_free(material);
const floor = f.f3d_body_create(world, 1, 0, -1, 0, 0);
f.f3d_body_set_shape(world, floor, 2, 200, 1, 200);
const meshVerts = [-20, 0, -20, 20, 0, -20, 20, 0, 20, -20, 0, 20, 0, 3, 0];
const meshTris = [0, 4, 1, 1, 4, 2, 2, 4, 3, 3, 4, 0];
const vp = f.f3d_buffer_alloc(meshVerts.length * 4);
new Float32Array(heap(), vp, meshVerts.length).set(meshVerts);
const tp = f.f3d_buffer_alloc(meshTris.length * 4);
new Uint32Array(heap(), tp, meshTris.length).set(meshTris);
const mesh = f.f3d_world_create_mesh(world, vp, 5, tp, 4);
f.f3d_buffer_free(vp);
f.f3d_buffer_free(tp);
const hill = f.f3d_body_create(world, 1, 0, 0, 0, 0);
f.f3d_body_set_mesh(world, hill, mesh);
const pivot = f.f3d_body_create(world, 1, -6, 4, 0, 0);
const bob = f.f3d_body_create(world, 0, -5, 4, 0, 1);
f.f3d_body_set_shape(world, bob, 1, 0.2, 0, 0);
const swing = f.f3d_joint_create(world, 2, pivot, bob, -6, 4, 0, 0, 0, 1);
f.f3d_joint_set_limits(world, swing, 1, -1.2, 1.2);
for (let i = 0; i < steps; i++) f.f3d_world_step(world, dt);
const size = f.f3d_world_snapshot_size(world);
const ptr = f.f3d_buffer_alloc(size);
f.f3d_world_snapshot_write(world, ptr, size);
const bytes = new Uint8Array(heap(), ptr, size);
console.log(Buffer.from(bytes).toString('base64'));
f.f3d_buffer_free(ptr);
f.f3d_world_destroy(world);
process.exit(0);
})();
''';

bool _available(String executable, List<String> args) {
  try {
    return Process.runSync(executable, args).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

NativeShape _shape(List<double> b) => switch (b[6].toInt()) {
  1 => NativeShape.sphere(b[7]),
  2 => NativeShape.box(Vector3(b[7], b[8], b[9])),
  3 => NativeShape.capsule(b[7], b[8]),
  4 => NativeShape.cylinder(b[7], b[8]),
  _ => NativeShape.point,
};

void main() {
  final missing = <String>[
    if (!_available('node', <String>['--version'])) 'node',
    if (!_available('clang', <String>['--version'])) 'clang',
    if (findWasmLinker() == null) 'a wasm linker',
  ];

  test('the module and the native library step to the same bits', () {
    // Not the transforms only: the whole snapshot, every body's spin,
    // temperature, fuel and water, every event, byte for byte. The layouts
    // are the same on wasm32 and a 64-bit target — no pointer lives in what
    // a snapshot copies — so the bytes have to be.
    //
    // Mutation: drop -ffp-contract=off from `hook/build.dart` — clang fuses
    // the position update's multiply and add into one rounding on arm64,
    // which WebAssembly has no scalar instruction for, and the bits part.
    final scratch = Directory.systemTemp.createTempSync('f3d_wasm_test');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final wasm = '${scratch.path}/f3d.wasm';
    buildWasm(root: Directory.current.path, out: wasm);
    _sameBits(wasm, scratch);
  }, skip: missing.isEmpty ? false : 'no ${missing.join(', ')}');

  test('the module the package ships steps to the same bits', () {
    // Hooks do not build for the browser, so `web/f3d_physics.wasm` is built
    // by hand — `dart run tool/build_wasm.dart` — and kept in the package.
    // Changing the core and not rebuilding it fails here.
    final scratch = Directory.systemTemp.createTempSync('f3d_wasm_test');
    addTearDown(() => scratch.deleteSync(recursive: true));
    _sameBits('web/f3d_physics.wasm', scratch);
  }, skip: _available('node', <String>['--version']) ? false : 'no node');

  test('the threads module steps to the same bits on four workers', () {
    // Its workers are node's, each an instance of the module on the one
    // shared memory; the world shares its passes among them, and lands on
    // the native library's bytes as on one thread.
    final scratch = Directory.systemTemp.createTempSync('f3d_wasm_test');
    addTearDown(() => scratch.deleteSync(recursive: true));
    _sameBits('web/f3d_physics_threads.wasm', scratch, threads: 4);
  }, skip: _available('node', <String>['--version']) ? false : 'no node');

  test('the module imports nothing and exports the API and the shim', () {
    final scratch = Directory.systemTemp.createTempSync('f3d_wasm_test');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final wasm = '${scratch.path}/f3d.wasm';
    buildWasm(root: Directory.current.path, out: wasm);
    final script =
        'const m = new WebAssembly.Module(require("fs").readFileSync('
        '${jsonEncode(wasm)}));'
        'console.log(JSON.stringify({imports: WebAssembly.Module.imports(m)'
        '.length, exports: WebAssembly.Module.exports(m).map(e => e.name)}))';
    final listed = Process.runSync('node', <String>['-e', script]);
    expect(listed.exitCode, 0, reason: '${listed.stderr}');
    final answer =
        jsonDecode('${listed.stdout}'.trim()) as Map<String, dynamic>;
    expect(answer['imports'], 0, reason: 'a module with no C library');
    final header = File('csrc/include/f3d_physics.h').readAsStringSync();
    final declared = RegExp(
      r'F3D_API [^;(]*?\b(f3d_\w+)\(',
    ).allMatches(header).map((m) => m.group(1)!).toSet();
    // And the shim's: each call that takes or gives a 64-bit value again,
    // in 32-bit halves, for the browser's numbers.
    final shimmed = RegExp(r'F3D_API [^;(]*?\b(f3d_\w+)\(')
        .allMatches(File('csrc/wasm/f3d_wasm_shim.c').readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    expect(shimmed, contains('f3d_wasm_high'));
    expect((answer['exports'] as List<dynamic>).toSet(), <Object>{
      'memory',
      ...declared,
      ...shimmed,
    });
  }, skip: missing.isEmpty ? false : 'no ${missing.join(', ')}');
}

/// Steps the scenario in the module at [wasm], run in node, and in the
/// native library, and holds the two snapshots to the same bytes.
void _sameBits(String wasm, Directory scratch, {int threads = 1}) {
  final module = File(wasm).readAsBytesSync();
  expect(module, isNotEmpty);

  final runner = File('${scratch.path}/run.js')..writeAsStringSync(_runner);
  final ran = Process.runSync('node', <String>[
    runner.path,
    wasm,
    jsonEncode(<String, Object>{
      'bodies': _bodies,
      'gravity': _gravity,
      'wind': _wind,
      'grid': _grid,
      'steps': _steps,
      'dt': _dt,
      'threads': threads,
      'materialBytes': F3dMaterialLayout.size,
    }),
  ]);
  expect(ran.exitCode, 0, reason: '${ran.stderr}');
  final fromWasm = base64Decode('${ran.stdout}'.trim());

  final world = NativeWorld();
  addTearDown(world.dispose);
  world
    ..gravity = Vector3(_gravity[0], _gravity[1], _gravity[2])
    ..wind = Vector3(_wind[0], _wind[1], _wind[2])
    ..setWindGrid(
      origin: Vector3(-5.0, 0.0, -5.0),
      cell: 5.0,
      nx: 2,
      ny: 1,
      nz: 2,
      velocities: Float32List.fromList(_grid),
    );
  final wood = NativeMaterial.wood();
  for (final b in _bodies) {
    final body = world.addBody(position: Vector3(b[0], b[1], b[2]));
    world
      ..setVelocity(body, Vector3(b[3], b[4], b[5]))
      ..setShape(body, _shape(b))
      ..setAngularVelocity(body, Vector3(b[10], b[11], b[12]))
      ..setMaterial(body, wood)
      ..setTemperature(body, b[13])
      ..addWater(body, b[14]);
  }
  // A floor they fall through, with no solver yet: contacts, events and
  // heat across them, all in the comparison.
  final floor = world.addBody(
    position: Vector3(0.0, -1.0, 0.0),
    type: NativeBodyType.fixed,
    mass: 0.0,
  );
  world.setShape(floor, NativeShape.box(Vector3(200.0, 1.0, 200.0)));
  // And a mesh hill on it, a pyramid of four triangles, for the bodies
  // to land on and roll off.
  final hill = world.addBody(
    position: Vector3.zero(),
    type: NativeBodyType.fixed,
    mass: 0.0,
  );
  world.setMesh(
    hill,
    world.createMesh(
      <Vector3>[
        Vector3(-20.0, 0.0, -20.0),
        Vector3(20.0, 0.0, -20.0),
        Vector3(20.0, 0.0, 20.0),
        Vector3(-20.0, 0.0, 20.0),
        Vector3(0.0, 3.0, 0.0),
      ],
      <int>[0, 4, 1, 1, 4, 2, 2, 4, 3, 3, 4, 0],
    ),
  );
  // And a hinged pendulum with limits, for the joints.
  final pivot = world.addBody(
    position: Vector3(-6.0, 4.0, 0.0),
    type: NativeBodyType.fixed,
    mass: 0.0,
  );
  final bob = world.addBody(position: Vector3(-5.0, 4.0, 0.0));
  world.setShape(bob, const NativeShape.sphere(0.2));
  final swing = world.createJoint(
    NativeJointType.revolute,
    pivot,
    bob,
    anchor: Vector3(-6.0, 4.0, 0.0),
    axis: Vector3(0.0, 0.0, 1.0),
  );
  world.setJointLimits(swing, (lower: -1.2, upper: 1.2));
  for (var i = 0; i < _steps; i++) {
    world.step(_dt);
  }
  final fromNative = world.snapshot();

  expect(fromWasm.length, fromNative.length);
  expect(fromWasm, orderedEquals(fromNative));
  // And the scenario reached what it was built to: a fire, a turn.
  expect(
    world.readEvents().map((e) => e.kind),
    containsAll(<NativeEventKind>[
      NativeEventKind.ignited,
      NativeEventKind.contactBegan,
    ]),
  );
}
