/// Interpreted Dart behind `ScriptRuntime`: no runtime ships, and a script
/// brought by a data plugin is held to the rules a Wasm module is.
///
///     dart test test/script_runtime_test.dart
///
/// The runtime here is a stand-in whose "programs" are Dart closures picked
/// by the script's text, which is enough to check everything the engine
/// owns: the refusal without a runtime, the fields a script may reach, the
/// events it may publish and the state it saves. Each test names the
/// mutation that would defeat it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A runtime whose programs are closures, looked up by the script's text.
final class _Closures extends ScriptRuntime {
  const _Closures(this.programs);

  final Map<String, void Function(ScriptContext context, List<int> state)>
  programs;

  @override
  String get name => 'closures';

  @override
  ScriptProgram compile(String source, {required String from}) {
    final body = programs[source.trim()];
    if (body == null) throw ScriptException('$from: no such program');
    return _Program(body);
  }
}

final class _Program extends ScriptProgram {
  _Program(this.body);

  final void Function(ScriptContext context, List<int> state) body;
  final List<int> state = <int>[0];

  @override
  void step(ScriptContext context) => body(context, state);

  @override
  Object? save() => List<int>.of(state);

  @override
  void restore(Object? saved) => state.setAll(0, saved! as List<int>);
}

Future<DataPlugin> _plugin(
  String program, {
  List<String> reads = const <String>[],
  List<String> writes = const <String>[],
  String touches = 'simulation',
}) => const DataPluginLoader().load(
  jsonEncode(<String, Object?>{
    'f3dplugin': 1,
    'manifest': <String, Object?>{
      'id': 'tides',
      'apiVersion': '1.0',
      'touches': touches,
    },
    'events': <Object?>[
      <String, Object?>{'name': 'high'},
    ],
    'scripts': <Object?>[
      <String, Object?>{
        'source': 'tides.dart',
        'system': 'turn',
        'phase': 'rules',
        'reads': reads,
        'writes': writes,
        'events': <String>['high'],
      },
    ],
  }),
  MemoryPluginSource(<String, Uint8List>{
    'tides.dart': Uint8List.fromList(utf8.encode(program)),
  }),
);

void main() {
  late Float64List sea;
  late WorldFields fields;
  const runtime = _Closures(<String, void Function(ScriptContext, List<int>)>{
    'rise': _rise,
    'sneak': _sneak,
    'shout': _shout,
  });

  setUp(() {
    sea = Float64List.fromList(<double>[1.0, 2.0]);
    fields = WorldFields(<WorldField>[ListWorldField('sea', sea)]);
  });

  test('with no runtime a script is refused, by name', () async {
    // Mutation: install the plugin without its script. A level script that
    // never runs is a level that silently plays differently.
    final plugin = await _plugin('rise', writes: <String>['sea']);
    expect(
      () => EngineLoop(
        input: InputState(),
        registries: <PluginRegistry>[fields],
        plugins: <Flutter3dPlugin>[plugin],
      ),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          allOf(contains('tides.dart'), contains('ScriptRuntime')),
        ),
      ),
    );
  });

  test('a script steps the world it declared, and publishes', () async {
    // Mutation: hand the script every field. One that declared nothing
    // could write the world's water.
    final plugin = await _plugin('rise', writes: <String>['sea']);
    final heard = <List<int>>[];
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[fields, runtime],
      plugins: <Flutter3dPlugin>[plugin],
    );
    loop.events.onStep<PluginDataEvent>('heard', (d) {
      heard.add(d.event.values);
    });
    loop.runSteps(3);
    expect(loop.systemsIn(LoopPhase.rules), <String>['tides.turn']);
    expect(sea[0], 4.0);
    expect(heard, <List<int>>[
      <int>[0],
      <int>[1],
      <int>[2],
    ]);
    expect(
      loop.events.declared.where((d) => d.declaredBy == 'tides').single.name,
      'tides.high',
    );
    expect(plugin.save(), <String, Object?>{
      'tides.turn': <int>[3],
    });
    plugin.restore(<String, Object?>{
      'tides.turn': <int>[1],
    });
    expect(plugin.save(), <String, Object?>{
      'tides.turn': <int>[1],
    });
  });

  test('a field read-only or undeclared is refused at the write', () async {
    // Mutation: check only that the field exists. A script that declared
    // `sea` as something it reads would write it.
    final plugin = await _plugin('sneak', reads: <String>['sea']);
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[fields, runtime],
      plugins: <Flutter3dPlugin>[plugin],
    );
    expect(
      () => loop.runSteps(1),
      throwsA(
        isA<ScriptException>().having(
          (e) => e.message,
          'message',
          contains('read-only'),
        ),
      ),
    );
  });

  test('an event the plugin did not declare is refused', () async {
    // Mutation: publish whatever name a script gives. Two plugins could
    // claim one event and nobody would be told.
    final plugin = await _plugin('shout');
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[fields, runtime],
      plugins: <Flutter3dPlugin>[plugin],
    );
    expect(() => loop.runSteps(1), throwsA(isA<ScriptException>()));
  });

  test(
    'a view plugin may not write the world, and a missing field is named',
    () async {
      // Mutation: drop the touches check. A view plugin's script would write
      // the simulation while its switches promise a replay nothing changed.
      final view = await _plugin(
        'rise',
        writes: <String>['sea'],
        touches: 'view',
      );
      expect(
        () => EngineLoop(
          input: InputState(),
          registries: <PluginRegistry>[fields, runtime],
          plugins: <Flutter3dPlugin>[view],
        ),
        throwsA(isA<PluginException>()),
      );
      final lost = await _plugin('rise', reads: <String>['moon']);
      expect(
        () => EngineLoop(
          input: InputState(),
          registries: <PluginRegistry>[fields, runtime],
          plugins: <Flutter3dPlugin>[lost],
        ),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"moon"'), contains('sea')),
          ),
        ),
      );
    },
  );
}

/// Raises the sea by one each step, and says so with the step's number.
void _rise(ScriptContext context, List<int> state) {
  context.write('sea', 0, context.read('sea', 0) + 1.0);
  context.publish('high', <int>[context.step]);
  state[0] += 1;
}

/// Writes a field it declared only for reading.
void _sneak(ScriptContext context, List<int> state) =>
    context.write('sea', 0, 0.0);

/// Publishes an event its plugin never declared.
void _shout(ScriptContext context, List<int> state) =>
    context.publish('storm', const <int>[]);
