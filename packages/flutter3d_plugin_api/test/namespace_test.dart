/// Every name a plugin registers is in its namespace, and a registry brings
/// the registries that come with it (D23, D43).
///
///     dart test test/namespace_test.dart
///
/// Mutation: drop the length check from `nameProblem` and `acme.` alone
/// passes; drop the reserved check and a plugin called `f3d.x` claims the
/// engine's namespace; look up registries without their companions and the
/// last test finds no `_Lights`.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

PluginManifest _manifest(String id) =>
    PluginManifest(id: id, apiVersion: PluginApiVersion.current);

final class _Lights extends PluginRegistry {
  _Lights([this.scope]);

  final PluginScope? scope;

  @override
  _Lights forPlugin(PluginScope scope) => _Lights(scope);
}

final class _Steps extends PluginRegistry {
  _Steps(this.lights);

  final _Lights lights;

  @override
  _Steps forPlugin(PluginScope scope) => this;

  @override
  Iterable<PluginRegistry> get companions => <PluginRegistry>[lights];
}

final class _Asks extends Flutter3dPlugin {
  _Asks();

  _Lights? found;

  @override
  PluginManifest get manifest => PluginManifest(
    id: 'acme_lamps.flicker',
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.view,
  );

  @override
  void install(PluginHost host) => found = host.registry<_Lights>();
}

final class _Loop extends LoopRegistry {
  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  LoopRegistry forPlugin(PluginScope scope) => this;
}

final class _Events extends EventRegistry {
  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  void publish(BusEvent event) {}

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}

void main() {
  test('a plugin id names its namespace, up to the first dot', () {
    expect(_manifest('acme_frost.frost').namespace, 'acme_frost');
    expect(_manifest('trails').namespace, 'trails');
  });

  test('a name in the namespace passes; one outside is refused by name', () {
    final frost = _manifest('acme_frost.frost');
    expect(frost.nameProblem('acme_frost.haze', what: 'a step'), isNull);
    expect(frost.nameProblem('acme_frost.', what: 'a step'), isNotNull);
    final outside = frost.nameProblem('frost', what: 'a render step');
    expect(outside, contains('"frost"'));
    expect(outside, contains('acme_frost.<name>'));
    // Case-sensitive, like every name the engine compares.
    expect(frost.nameProblem('Acme_frost.haze', what: 'a step'), isNotNull);
  });

  test('a name is qualified into the namespace, or refused outside it', () {
    final editor = _manifest('acme_frost.editor');
    // Mutation: prefix a bare name with the whole id. The editor half of a
    // package would publish `acme_frost.editor.stoke` beside its runtime
    // half's `acme_frost.haze`, two namespaces for one package.
    expect(editor.qualify('stoke', what: 'the command'), 'acme_frost.stoke');
    expect(
      editor.qualify('acme_frost.stoke', what: 'the command'),
      'acme_frost.stoke',
    );
    // Mutation: accept any dotted name as given. A plugin could publish a
    // command under another package's namespace.
    expect(
      () => editor.qualify('acme_lamps.stoke', what: 'the command'),
      throwsA(
        isA<PluginException>().having(
          (e) => e.message,
          'message',
          allOf(contains('"acme_lamps.stoke"'), contains('the command')),
        ),
      ),
    );
    expect(
      () => _manifest('f3d.lamps').qualify('lamp', what: 'the gizmo'),
      throwsA(isA<PluginException>()),
    );
    expect(
      () => editor.qualify('', what: 'the command'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('the engine\'s own packages register the engine\'s names', () {
    final sky = _manifest('flutter3d_addon_atmosphere.sky');
    expect(sky.isEngine, isTrue);
    expect(sky.nameProblem('sky', what: 'a render step'), isNull);
  });

  test('no plugin from outside takes the engine\'s namespace', () {
    final squatter = _manifest('f3d.lamps');
    expect(squatter.isEngine, isFalse);
    expect(
      squatter.nameProblem('f3d.lamp', what: 'a light type'),
      contains('engine'),
    );
  });

  test('a registry\'s companions are found as if handed in', () {
    final lights = _Lights();
    final plugin = _Asks();
    PluginManager(
      loop: _Loop(),
      events: _Events(),
      registries: <PluginRegistry>[_Steps(lights)],
    ).installAll(<Flutter3dPlugin>[plugin]);
    expect(plugin.found, isNotNull);
    expect(plugin.found!.scope?.manifest.id, 'acme_lamps.flicker');
  });
}
