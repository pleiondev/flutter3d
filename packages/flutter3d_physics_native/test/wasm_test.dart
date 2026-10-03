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
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import '../tool/build_wasm.dart';

/// The scenario both builds run: five bodies, thrown at awkward speeds under
/// tilted gravity, six hundred steps of a sixtieth of a second.
const List<List<double>> _bodies = <List<double>>[
  // position xyz, velocity xyz
  <double>[0.0, 20.0, 0.0, 0.0, 0.0, 0.0],
  <double>[-3.0, 5.0, 2.0, 4.1, 6.3, -1.7],
  <double>[1.25, 0.5, -7.5, -0.3, 11.9, 0.01],
  <double>[100.0, -2.0, 3.3, 0.7, 0.2, -9.9],
  <double>[0.001, 0.002, 0.003, 1e-3, -2e-4, 3e-5],
];
const List<double> _gravity = <double>[0.3, -9.81, -0.07];
const int _steps = 600;
const double _dt = 1.0 / 60.0;

const String _runner = r'''
const fs = require('fs');
const [wasmPath, scenarioJson] = process.argv.slice(2);
const { bodies, gravity, steps, dt } = JSON.parse(scenarioJson);
const { instance } = { instance: new WebAssembly.Instance(
  new WebAssembly.Module(fs.readFileSync(wasmPath)), {}) };
const f = instance.exports;
const world = f.f3d_world_create();
f.f3d_world_set_gravity(world, gravity[0], gravity[1], gravity[2]);
const handles = [];
for (const b of bodies) {
  const h = f.f3d_body_create(world, 0, b[0], b[1], b[2], 1.0);
  f.f3d_body_set_velocity(world, h, b[3], b[4], b[5]);
  handles.push(h);
}
for (let i = 0; i < steps; i++) f.f3d_world_step(world, dt);
const count = f.f3d_world_body_count(world);
const ptr = f.f3d_buffer_alloc(count * 7 * 4);
const written = f.f3d_world_read_transforms(world, ptr, 0, count);
const view = new Uint32Array(f.memory.buffer, ptr, written * 7);
console.log(JSON.stringify(Array.from(view)));
f.f3d_buffer_free(ptr);
f.f3d_world_destroy(world);
''';

bool _available(String executable, List<String> args) {
  try {
    return Process.runSync(executable, args).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final missing = <String>[
    if (!_available('node', <String>['--version'])) 'node',
    if (!_available('clang', <String>['--version'])) 'clang',
    if (findWasmLinker() == null) 'a wasm linker',
  ];

  test('the module and the native library step to the same bits', () {
    // Mutation: drop -ffp-contract=off from `hook/build.dart` — clang fuses
    // the position update's multiply and add into one rounding on arm64,
    // which WebAssembly has no scalar instruction for, and the bits part.
    final scratch = Directory.systemTemp.createTempSync('f3d_wasm_test');
    addTearDown(() => scratch.deleteSync(recursive: true));
    final wasm = '${scratch.path}/f3d.wasm';
    buildWasm(root: Directory.current.path, out: wasm);
    final module = File(wasm).readAsBytesSync();
    expect(module, isNotEmpty);

    final runner = File('${scratch.path}/run.js')..writeAsStringSync(_runner);
    final ran = Process.runSync('node', <String>[
      runner.path,
      wasm,
      jsonEncode(<String, Object>{
        'bodies': _bodies,
        'gravity': _gravity,
        'steps': _steps,
        'dt': _dt,
      }),
    ]);
    expect(ran.exitCode, 0, reason: '${ran.stderr}');
    final fromWasm = (jsonDecode('${ran.stdout}'.trim()) as List<dynamic>)
        .cast<int>();

    final world = NativeWorld();
    addTearDown(world.dispose);
    world.gravity = Vector3(_gravity[0], _gravity[1], _gravity[2]);
    for (final b in _bodies) {
      final body = world.addBody(position: Vector3(b[0], b[1], b[2]));
      world.setVelocity(body, Vector3(b[3], b[4], b[5]));
    }
    for (var i = 0; i < _steps; i++) {
      world.step(_dt);
    }
    final fromNative = Uint32List.sublistView(
      world.readTransforms().transforms,
    );

    expect(fromWasm, hasLength(_bodies.length * 7));
    expect(fromWasm, orderedEquals(fromNative));
  }, skip: missing.isEmpty ? false : 'no ${missing.join(', ')}');

  test('the module imports nothing and exports the API', () {
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
    expect((answer['exports'] as List<dynamic>).toSet(), <Object>{
      'memory',
      ...declared,
    });
  }, skip: missing.isEmpty ? false : 'no ${missing.join(', ')}');
}
