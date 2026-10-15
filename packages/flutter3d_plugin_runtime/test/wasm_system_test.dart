/// A Wasm module as a step system: the world's fields it reads and writes,
/// the events it publishes, what it is refused at install, and a trap that
/// switches it off and comes back on a rollback.
///
///     dart test test/wasm_system_test.dart
///
/// The modules are assembled by hand in `wasm/assemble.dart` and stepped
/// through a real `EngineLoop`. Each test names the mutation that would
/// defeat it.
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/src/data_event.dart';
import 'package:flutter3d_plugin_runtime/src/wasm/wasm.dart';
import 'package:flutter3d_plugin_runtime/src/world_fields.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

import 'support/install_refusal.dart';

import 'wasm/assemble.dart';

/// A module that copies heat[0] into wind[0] and publishes event 0 with
/// heat[0] and the step.
Uint8List _breeze() {
  final m = ModuleBuilder();
  final get = m.import('field_get', 2, 1);
  final set = m.import('field_set', 3, 0);
  final publish = m.import('publish', 3, 0);
  m.abi(
    step: <int>[
      ...konst(1), ...konst(0), //
      ...konst(0), ...konst(0), call, get,
      call, set,
      ...konst(0),
      ...konst(0), ...konst(0), call, get,
      localGet, 0,
      call, publish,
    ],
  );
  return m.build();
}

WasmPlugin _plugin({
  bool windWritable = true,
  PluginTouches touches = PluginTouches.simulation,
}) => WasmPlugin(
  manifest: PluginManifest(
    id: 'breeze',
    apiVersion: PluginApiVersion.current,
    touches: touches,
  ),
  spec: WasmSystemSpec(
    module: 'breeze.wasm',
    system: 'blow',
    phase: 'elements',
    fields: <WasmFieldSpec>[
      const WasmFieldSpec('heat'),
      WasmFieldSpec('wind', writable: windWritable),
    ],
    events: const <String>['gust'],
  ),
  bytes: _breeze(),
);

/// The interpreter under another name and unmetered, as the browser's
/// runtime is: what a VM test can stand in for it with.
final class _Unmetered extends WasmRuntime {
  const _Unmetered();

  @override
  String get name => 'unmetered';

  @override
  bool get isMetered => false;

  @override
  WasmInstance instantiate(WasmInstantiation request) =>
      WasmRuntime.interpreter.instantiate(request);
}

WasmPlugin _onRuntime(WasmRuntime runtime, PluginTouches touches) => WasmPlugin(
  manifest: PluginManifest(
    id: 'breeze',
    apiVersion: PluginApiVersion.current,
    touches: touches,
  ),
  spec: const WasmSystemSpec(
    module: 'breeze.wasm',
    system: 'blow',
    phase: 'elements',
    fields: <WasmFieldSpec>[WasmFieldSpec('heat')],
  ),
  bytes: _breeze(),
  runtime: runtime,
);

void main() {
  late Float64List heat;
  late Float64List wind;
  late WorldFields fields;

  setUp(() {
    heat = Float64List.fromList(<double>[2.5]);
    wind = Float64List(1);
    fields = WorldFields(<WorldField>[
      ListWorldField('heat', heat),
      ListWorldField('wind', wind),
    ]);
  });

  test('a module reads one field, writes another and publishes', () {
    // Mutation: index the fields by name order rather than by declaration;
    // `field_set(1, …)` would write heat and wind would stay nought.
    final plugin = _plugin();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[fields],
      plugins: <Flutter3dPlugin>[plugin],
    );
    final seen = <PluginDataEvent>[];
    loop.events.onStep<PluginDataEvent>('seen', (d) => seen.add(d.event));
    loop.runSteps(2);
    expect(wind[0], 2.5);
    expect(loop.systemsIn(LoopPhase.fields), contains('breeze.blow'));
    expect(seen.map((e) => e.name), <String>['breeze.gust', 'breeze.gust']);
    expect(seen.last.values, <int>[Fixed16.fromDouble(2.5), 1]);
    expect(plugin.system!.trapped, isNull);
  });

  test('a Wasm plugin is never the engine\'s, whatever id it says', () {
    // Mutation: take the manifest as given — a module that says
    // `flutter3d_post.glow` installs with the engine's rights.
    expect(
      () => WasmPlugin(
        manifest: const PluginManifest(
          id: 'flutter3d_post.glow',
          apiVersion: PluginApiVersion.current,
        ),
        spec: const WasmSystemSpec(
          module: 'glow.wasm',
          system: 'blow',
          phase: 'elements',
        ),
        bytes: _breeze(),
      ),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          contains('"flutter3d_post.glow"'),
        ),
      ),
    );
  });

  test('a write to a field declared read-only traps once and stays off', () {
    // Mutation: keep calling the module after a trap. It would trap again
    // every step and publish a second WasmTrapped.
    final plugin = _plugin(windWritable: false);
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[fields],
      plugins: <Flutter3dPlugin>[plugin],
    );
    final traps = <WasmTrapped>[];
    loop.events.onStep<WasmTrapped>('traps', (d) => traps.add(d.event));
    loop.runSteps(3);
    expect(wind[0], 0.0);
    expect(plugin.system!.trapped, contains('reads only'));
    expect(traps, hasLength(1));
    expect(traps.single.system, 'breeze.blow');
    expect(traps.single.step, 0);
  });

  test('a rollback to before the trap starts the module again', () {
    // Mutation: leave the latch out of `WasmSystem.save`. The restored
    // system would stay off, and a replay from the snapshot would part from
    // the run that took it.
    final plugin = _plugin(windWritable: false);
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[fields],
      plugins: <Flutter3dPlugin>[plugin],
    );
    final system = plugin.system!;
    final before = system.save();
    loop.runSteps(1);
    expect(system.trapped, isNotNull);
    system.restore(before);
    expect(system.trapped, isNull);
  });

  test('a plugin that touches only the view is refused a field it writes', () {
    // Mutation: drop the touches check in `installWasmSystem`; the loop
    // would refuse the step system anyway, but with a sentence about a
    // system rather than about the field written.
    expect(
      installRefusal(
        EngineLoop(
          input: InputState(),
          registries: <PluginRegistry>[fields],
          plugins: <Flutter3dPlugin>[_plugin(touches: PluginTouches.view)],
        ).plugins,
      ),
      isA<PluginException>().having(
        (e) => e.message,
        'message',
        allOf(contains('touches only the view'), contains('"wind"')),
      ),
    );
  });

  test('a field the engine does not have is refused by name', () {
    // Mutation: skip a missing field instead; field 1 would then be read as
    // whatever came next, or past the end of the list.
    final onlyHeat = WorldFields(<WorldField>[ListWorldField('heat', heat)]);
    expect(
      installRefusal(
        EngineLoop(
          input: InputState(),
          registries: <PluginRegistry>[onlyHeat],
          plugins: <Flutter3dPlugin>[_plugin()],
        ).plugins,
      ),
      isA<PluginException>().having(
        (e) => e.message,
        'message',
        allOf(contains('"wind"'), contains('it has heat')),
      ),
    );
  });

  test('a system declaration reads back as it was written', () {
    // Mutation: write `writable` under "writable" rather than "write"; the
    // field would read back read-only.
    final spec = _plugin().spec;
    final again = WasmSystemSpec.fromJson(spec.toJson());
    expect(again.toJson(), spec.toJson());
    expect(again.fields.last.writable, isTrue);
    expect(again.limits.fuelPerStep, const WasmLimits().fuelPerStep);
    expect(
      () => WasmSystemSpec.fromJson(const <String, Object?>{'module': 'a'}),
      throwsA(isA<WasmFormatException>()),
    );
  });

  test('a value crosses into a module as Q16.16 and back exactly', () {
    // Mutation: truncate instead of rounding; 0.1 would cross as 6553 and
    // come back further from 0.1 than the nearest step.
    expect(Fixed16.fromDouble(2.5), 163840);
    expect(Fixed16.fromDouble(0.1), 6554);
    expect(Fixed16.toDouble(Fixed16.fromDouble(-3.25)), -3.25);
    expect(Fixed16.fromDouble(double.nan), 0);
    expect(Fixed16.fromDouble(1e9), 0x7FFFFFFF);
    expect(Fixed16.fromDouble(-1e9), -0x80000000);
  });

  test('a simulating module on a runtime that counts no fuel is refused '
      'under a bit-exact profile', () {
    // Mutation: drop the check from `installWasmSystem`. A module that runs
    // out of fuel traps on the interpreter a server replays it on and not
    // in the browser that recorded the run, and the two part with no
    // sentence saying why.
    expect(
      installRefusal(
        EngineLoop(
          input: InputState(),
          registries: <PluginRegistry>[fields],
          plugins: <Flutter3dPlugin>[
            _onRuntime(const _Unmetered(), PluginTouches.simulation),
          ],
        ).plugins,
      ),
      isA<WasmException>().having(
        (e) => e.message,
        'message',
        allOf(contains('unmetered'), contains('deterministic')),
      ),
    );
    // Under a profile that promises no bits, and for a module that only
    // draws, it runs; its save names the runtime.
    final plugin = _onRuntime(const _Unmetered(), PluginTouches.simulation);
    EngineLoop(
      input: InputState(),
      profile: SimulationProfile.accurate,
      registries: <PluginRegistry>[fields],
      plugins: <Flutter3dPlugin>[plugin],
    ).runSteps(1);
    expect(plugin.system!.save()['runtime'], 'unmetered');
    expect(plugin.system!.digestible().containsKey('runtime'), isFalse);
  });
}
