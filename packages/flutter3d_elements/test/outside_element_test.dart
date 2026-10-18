/// An element from outside the engine, brought by its own plugin: a frost
/// that reacts to heat. It installs under its package's namespace, with
/// its phase, its switch and its event in that namespace, and gets none of
/// the engine's rights.
///
///     dart test test/outside_element_test.dart
library;

import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Freezes a body when it is cold enough, and says so: the reaction an
/// outside author adds to the elements.
final class _Frost extends ElementHook {
  _Frost(this.body);

  final NativeBody body;
  static const NativeEventKind frozen = NativeEventKind.plugin(
    0x10001,
    'acme_frost.frozen',
  );

  @override
  String get id => 'frost';

  @override
  List<NativeEventKind> get eventKinds => const <NativeEventKind>[frozen];

  @override
  void step(ElementStep step) {
    step.fields.setTemperature(ElementBody.of(body), 250.0);
    step.publish(frozen, ElementBody.of(body));
  }
}

/// A loop that refuses, as the engine's does, a name outside the
/// registering plugin's namespace.
final class _Loop extends LoopRegistry {
  final Map<String, LoopPhase> phases = <String, LoopPhase>{};
  final Map<String, LoopSystem> systems = <String, LoopSystem>{};

  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    phases[phase.name] = phase;
    return Registration(() => phases.remove(phase.name));
  }

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
    List<String> reads = const <String>[],
    List<String> writes = const <String>[],
  }) {
    systems[name] = system;
    return Registration(() => systems.remove(name));
  }

  @override
  LoopRegistry forPlugin(PluginScope scope) => _ScopedLoop(this, scope);
}

final class _ScopedLoop extends LoopRegistry {
  _ScopedLoop(this._loop, this._scope);

  final _Loop _loop;
  final PluginScope _scope;

  void _refuse(String name, String what) {
    if (_scope.manifest.nameProblem(name, what: what) case final problem?) {
      throw PluginException(problem);
    }
  }

  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    _refuse(phase.name, 'the phase');
    final registration = _loop.addPhase(phase);
    _scope.track(registration);
    return registration;
  }

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
    List<String> reads = const <String>[],
    List<String> writes = const <String>[],
  }) {
    _refuse(name, 'the system');
    final registration = _loop.addSystem(name, phase, system);
    _scope.track(registration);
    return registration;
  }

  @override
  LoopRegistry forPlugin(PluginScope scope) => _loop.forPlugin(scope);
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

final class _Context extends LoopContext {
  _Context(this.phase);

  @override
  final LoopPhase phase;
  final List<BusEvent> sent = <BusEvent>[];

  @override
  int get step => 3;

  @override
  double get dt => 1 / 60;

  @override
  double get realDt => 0.0;

  @override
  double get alpha => 0.0;

  @override
  bool get isResimulated => false;

  @override
  void publish(BusEvent event) => sent.add(event);
}

void main() {
  test('an outside element installs under its own namespace, with no engine '
      'rights', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final body = world.addBody(position: Vector3.zero());
    final plugin = ElementPlugin(
      _Frost(body),
      id: 'acme_frost',
      world: () => world,
    );
    // Mutation: file it under `flutter3d_elements.` again — an outside
    // element gets the engine's right to bare names in every registry.
    expect(plugin.manifest.id, 'acme_frost');
    expect(plugin.manifest.isEngine, isFalse);
    expect(plugin.manifest.idProblem, isNull);

    final loop = _Loop();
    final switches = ElementSwitches();
    final kinds = ElementEventKinds();
    // Mutation: name the phase `elements.frost` or the switch `frost` —
    // the install is refused, since both are outside `acme_frost.`.
    PluginManager(
      loop: loop,
      events: _Events(),
      registries: <PluginRegistry>[switches, kinds],
    ).installAll(<Flutter3dPlugin>[plugin]);
    expect(loop.phases.keys, <String>['acme_frost.frost']);
    expect(loop.systems.keys, <String>['acme_frost.frost.step']);
    expect(switches['acme_frost.frost'], isNotNull);
    expect(kinds.named('acme_frost.frozen'), _Frost.frozen);

    // What the view half is handed answers to the same switch.
    expect(plugin.element.id, 'acme_frost.frost');
    expect(plugin.element.switchedBy.id, 'acme_frost.frost');
    expect(plugin.element.phase.name, 'acme_frost.frost');

    final context = _Context(loop.phases['acme_frost.frost']!);
    loop.systems['acme_frost.frost.step']!(context);
    final event = context.sent.single as ElementEvent;
    expect(event.kind, _Frost.frozen);
    expect(event.body, body);
  });

  test('a hook that names itself in the namespace keeps its names', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final plugin = ElementPlugin(
      _Named(),
      id: 'acme_frost.rime',
      world: () => world,
    );
    // Mutation: qualify every id — `acme_frost.acme_frost.rime`.
    expect(plugin.element.id, 'acme_frost.rime');
    expect(plugin.element.phase.name, 'acme_frost.rime');
    expect(plugin.element.switchedBy.onByDefault, isFalse);
  });

  test('an element plugin may not take the engine\'s namespace', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final body = world.addBody(position: Vector3.zero());
    // Mutation: drop the check — an outside element claims the engine's
    // rights by naming itself after one of its packages.
    for (final id in <String>['flutter3d_elements', 'flutter3d_effects.x']) {
      expect(
        () => ElementPlugin(_Frost(body), id: id, world: () => world),
        throwsA(isA<ArgumentError>()),
        reason: id,
      );
    }
  });
}

final class _Named extends ElementHook {
  @override
  String get id => 'acme_frost.rime';

  @override
  ElementSwitch get switchedBy => ElementSwitch(id, onByDefault: false);
}
