/// A data plugin's render modules (`wasmRender`, ABI 3) and a remote
/// module's pin: read and written back, decoded as render modules on every
/// engine, run only where a frame is drawn and handed to the section that
/// installs render steps, kept out of the run's state; and a module from a
/// URL refused without the SHA-256 it was written against.
///
///     dart test test/data_plugin_render_test.dart
///
/// Each test names the mutation that would defeat it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_plugin_runtime/src/sha256.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

import 'support/install_refusal.dart';
import 'wasm/assemble.dart';

/// A stand-in for the core's `renderSteps`: a list of step names, each of
/// which asks the context for the program that drives it at install.
final class _Steps extends DataSection {
  _Steps();

  final Map<String, RenderProgram?> asked = <String, RenderProgram?>{};

  @override
  String get name => 'renderSteps';

  @override
  Object read(DataSectionRead step) => <String>[
    for (final entry in step.written! as List<Object?>)
      (entry! as Map<String, Object?>)['name']! as String,
  ];

  @override
  Object? write(Object section) => <Object?>[
    for (final name in section as List<String>) <String, Object?>{'name': name},
  ];

  @override
  void install(DataSectionInstall step) {
    for (final name in step.section as List<String>) {
      asked[name] = step.context.renderProgram(name);
    }
  }
}

/// A render module that sets nothing and draws.
Uint8List _drawing() {
  final m = ModuleBuilder();
  final draw = m.importOf('draw', const <int>[], const <int>[]);
  m.render(node: <int>[call, ...u32(draw)]);
  return m.build();
}

/// A step module that does nothing.
Uint8List _stepping() => (ModuleBuilder()..abi()).build();

String _document({
  List<Object?> steps = const <Object?>[],
  List<Object?> render = const <Object?>[],
  List<Object?> wasm = const <Object?>[],
  String id = 'acme',
  List<String> permissions = const <String>[],
}) => jsonEncode(<String, Object?>{
  'format': 'f3d.plugin',
  'version': 4,
  'manifest': <String, Object?>{
    'id': id,
    'apiVersion': '1.0',
    'touches': wasm.isEmpty ? 'view' : 'simulation',
    if (permissions.isNotEmpty) 'permissions': permissions,
  },
  if (wasm.isNotEmpty) ...<String, Object?>{
    'phases': <Object?>[
      <String, Object?>{'name': 'weather'},
    ],
    'wasm': wasm,
  },
  if (steps.isNotEmpty) 'renderSteps': steps,
  if (render.isNotEmpty) 'wasmRender': render,
});

Map<String, Object?> _beat({String module = 'beat.wasm', String? sha256}) =>
    <String, Object?>{
      'module': module,
      'step': 'beat',
      'parameters': <Object?>['strength'],
      'sha256': ?sha256,
    };

void main() {
  group('a render module of a data plugin', () {
    test('is handed to the section that installs its step, on an engine '
        'that draws', () async {
      // Mutation: build the context without `renderProgram`. The step would
      // draw every frame with its defaults and the module never run.
      final steps = _Steps();
      final plugin =
          await DataPluginLoader(
            sections: DataSections(<DataSection>[steps]),
          ).load(
            _document(
              steps: <Object?>[
                <String, Object?>{'name': 'beat'},
              ],
              render: <Object?>[_beat()],
            ),
            MemoryPluginSource(<String, Uint8List>{'beat.wasm': _drawing()}),
          );
      EngineLoop(
        input: InputState(),
        backend: 'cpu',
        plugins: <Flutter3dPlugin>[plugin],
      );
      final program = steps.asked['beat'];
      expect(program, isA<WasmRenderNode>());
      expect(program!.parameters, <String>['strength']);
      expect(plugin.renderNodes.keys, <String>['beat']);
    });

    test('is in no save and no digest', () async {
      // Mutation: add the render nodes to `save`. A client that draws and a
      // server that does not would write two different snapshots of one run.
      final plugin =
          await DataPluginLoader(
            sections: DataSections(<DataSection>[_Steps()]),
          ).load(
            _document(
              steps: <Object?>[
                <String, Object?>{'name': 'beat'},
              ],
              render: <Object?>[_beat()],
            ),
            MemoryPluginSource(<String, Uint8List>{'beat.wasm': _drawing()}),
          );
      EngineLoop(
        input: InputState(),
        backend: 'cpu',
        plugins: <Flutter3dPlugin>[plugin],
      );
      expect(plugin.save(), isEmpty);
    });

    test('is decoded as a render module even where nothing draws, and run '
        'only where something does', () async {
      // Mutation: decode render modules only on an engine that draws. A
      // server would accept a document a client then refuses.
      final loader = DataPluginLoader(
        sections: DataSections(<DataSection>[_Steps()]),
      );
      final document = _document(
        steps: <Object?>[
          <String, Object?>{'name': 'beat'},
        ],
        render: <Object?>[_beat()],
      );
      await expectLater(
        loader.load(
          document,
          MemoryPluginSource(<String, Uint8List>{'beat.wasm': _stepping()}),
        ),
        throwsA(isA<WasmException>()),
      );
      final plugin = await loader.load(
        document,
        MemoryPluginSource(<String, Uint8List>{'beat.wasm': _drawing()}),
      );
      EngineLoop(input: InputState(), plugins: <Flutter3dPlugin>[plugin]);
      expect(plugin.renderNodes, isEmpty);
      expect(plugin.notes, contains(contains('draws nothing')));
    });

    test('driving a step its document does not have switches the plugin '
        'off, saying so', () async {
      // Mutation: skip the check. The module would be instantiated and
      // never run, and the author would not learn the step's name is wrong.
      final plugin =
          await DataPluginLoader(
            sections: DataSections(<DataSection>[_Steps()]),
          ).load(
            _document(
              steps: <Object?>[
                <String, Object?>{'name': 'other'},
              ],
              render: <Object?>[_beat()],
            ),
            MemoryPluginSource(<String, Uint8List>{'beat.wasm': _drawing()}),
          );
      final loop = EngineLoop(
        input: InputState(),
        backend: 'cpu',
        plugins: <Flutter3dPlugin>[plugin],
      );
      expect(
        installRefusal(loop.plugins),
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          contains('"beat"'),
        ),
      );
    });

    test('one module is one kind, and one step has one driver', () {
      // Mutation: let a module be declared under both sections. One
      // instance would then be stepped and drawn, and its memory part of
      // the digest on one machine and not on another.
      expect(
        () => DataPluginDocument.parse(
          _document(
            render: <Object?>[_beat(module: 'both.wasm')],
            wasm: <Object?>[
              <String, Object?>{
                'module': 'both.wasm',
                'system': 'blow',
                'phase': 'weather',
              },
            ],
          ),
        ),
        throwsA(isA<DataPluginFormatException>()),
      );
      expect(
        () => DataPluginDocument.parse(
          _document(
            render: <Object?>[
              _beat(),
              _beat(module: 'two.wasm'),
            ],
          ),
        ),
        throwsA(isA<DataPluginFormatException>()),
      );
    });

    test('reads and writes back under wasmRender', () {
      // Mutation: leave `wasmRender` out of toJson. A tool saving the
      // document would drop the module that drives its step.
      final document = DataPluginDocument.parse(
        _document(render: <Object?>[_beat()]),
      );
      expect(document.wasmRender.single.step, 'beat');
      expect(document.resources, <String>['beat.wasm']);
      final written = document.toJson();
      expect(
        (written['wasmRender']! as List<Object?>).single,
        containsPair('step', 'beat'),
      );
      expect(DataSections.runtimeKeys, contains('wasmRender'));
    });
  });

  group('a module from a URL', () {
    final bytes = _stepping();
    final hash = sha256Hex(bytes);
    const url = 'https://mods.example/blow.wasm';
    final loader = DataPluginLoader(
      grants: PluginGrants(<PluginPermission>[PluginPermission.network]),
      fetch: (Uri at) async => bytes,
    );
    String remote({String? sha256, String module = url}) => _document(
      permissions: const <String>['network'],
      wasm: <Object?>[
        <String, Object?>{
          'module': module,
          'system': 'blow',
          'phase': 'weather',
          'sha256': ?sha256,
        },
      ],
    );

    test('runs as the bytes its declaration pins', () async {
      // Mutation: compare against a hash of something else.
      final plugin = await loader.load(
        remote(sha256: hash),
        MemoryPluginSource(const <String, Uint8List>{}),
      );
      expect(plugin.document.wasm.single.sha256, hash);
    });

    test('is refused without a sha256, or with one the bytes do not hash '
        'to', () async {
      // Mutation: skip the check for a module whose declaration gives no
      // hash. The server could hand the game other code after the grant.
      await expectLater(
        loader.load(remote(), MemoryPluginSource(const <String, Uint8List>{})),
        throwsA(
          isA<WasmException>().having(
            (e) => e.message,
            'message',
            contains('names no "sha256"'),
          ),
        ),
      );
      await expectLater(
        loader.load(
          remote(sha256: 'a' * 64),
          MemoryPluginSource(const <String, Uint8List>{}),
        ),
        throwsA(
          isA<WasmException>().having(
            (e) => e.message,
            'message',
            allOf(contains(hash), contains('a' * 64)),
          ),
        ),
      );
    });

    test('a module of the plugin\'s own is not checked', () async {
      // Mutation: check every module. A plugin unpacked with its modules
      // would have to carry a hash of each for nothing.
      final plugin = await const DataPluginLoader().load(
        _document(
          wasm: <Object?>[
            <String, Object?>{
              'module': 'blow.wasm',
              'system': 'blow',
              'phase': 'weather',
              'sha256': 'b' * 64,
            },
          ],
        ),
        MemoryPluginSource(<String, Uint8List>{'blow.wasm': bytes}),
      );
      expect(plugin.document.wasm.single.module, 'blow.wasm');
    });

    test('a sha256 that is not 64 lowercase hex digits does not read', () {
      // Mutation: accept any string. A typo would refuse the module at
      // every load with a hash nobody can match.
      expect(
        () => WasmSystemSpec.fromJson(const <String, Object?>{
          'module': url,
          'system': 'blow',
          'phase': 'weather',
          'sha256': 'ABC',
        }),
        throwsA(isA<WasmFormatException>()),
      );
    });

    test('the hash is SHA-256', () {
      // Mutation: any change to the rounds; these are the standard's
      // vectors.
      expect(
        sha256Hex(Uint8List(0)),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha256Hex(Uint8List.fromList('abc'.codeUnits)),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256Hex(Uint8List.fromList(('a' * 1000).codeUnits)),
        '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3',
      );
    });
  });
}
