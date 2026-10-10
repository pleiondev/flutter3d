/// A plugin element in a loop: the phase it takes, between the engine's
/// `fields` and `rules`, and the events its step publishes onto the step
/// channel — with no renderer anywhere.
///
///     dart test test/install_test.dart
library;

import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Writes down when it is stepped.
final class _Probe extends ElementHook {
  _Probe(this.id, this.log);

  @override
  final String id;
  final List<String> log;

  @override
  void step(ElementStep step) => log.add('$id.step');
}

/// A loop registry that writes down what is added to it.
final class _Loop extends LoopRegistry {
  final List<(LoopPhase, List<String>, List<String>)> phases =
      <(LoopPhase, List<String>, List<String>)>[];
  final Map<String, (LoopPhase, LoopSystem)> systems =
      <String, (LoopPhase, LoopSystem)>{};

  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    final entry = (phase, after, before);
    phases.add(entry);
    return Registration(() => phases.remove(entry));
  }

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    systems[name] = (phase, system);
    return Registration(() => systems.remove(name));
  }

  @override
  LoopRegistry forPlugin(PluginScope scope) => this;
}

final class _Context extends LoopContext {
  _Context(this.phase);

  @override
  final LoopPhase phase;
  final List<BusEvent> sent = <BusEvent>[];

  @override
  int get step => 7;

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
  test('installed in a loop, an element takes its own phase', () {
    final loop = _Loop();
    final world = NativeWorld();
    addTearDown(world.dispose);
    final log = <String>[];
    final registration = installElement(
      loop,
      _Probe('frost', log),
      world: () => world,
    );
    // Mutation: order the phase only after `fields` — it then lands
    // after `publish`, past the rules that should see what it did.
    final (phase, after, before) = loop.phases.single;
    expect(phase, const LoopPhase.step('elements.frost'));
    expect(after, <String>['fields']);
    expect(before, <String>['rules']);
    final (inPhase, system) = loop.systems['elements.frost.step']!;
    expect(inPhase, phase);
    system(_Context(phase));
    expect(log, <String>['frost.step']);
    // Mutation: cancel only the system — the phase stays behind with
    // nothing in it, and a second install throws on its name.
    registration.cancel();
    expect(loop.phases, isEmpty);
    expect(loop.systems, isEmpty);
  });

  test('an element\'s published events reach the loop\'s step', () {
    final loop = _Loop();
    final world = NativeWorld();
    addTearDown(world.dispose);
    final body = world.addBody(position: Vector3.zero());
    const frozen = NativeEventKind.plugin(0x10001, 'frost.frozen');
    installElement(loop, _Freezer(body, frozen), world: () => world);
    final (phase, system) = loop.systems['elements.freezer.step']!;
    final context = _Context(phase);
    system(context);
    // Mutation: hand the hook a step with no `publish` — the event is
    // dropped and the step channel never hears it.
    final event = context.sent.single as ElementEvent;
    expect(event.kind, frozen);
    expect(event.body, body);
  });
}

final class _Freezer extends ElementHook {
  _Freezer(this.body, this.kind);

  final NativeBody body;
  final NativeEventKind kind;

  @override
  String get id => 'freezer';

  @override
  List<NativeEventKind> get eventKinds => <NativeEventKind>[kind];

  @override
  void step(ElementStep step) {
    step.fields.setTemperature(ElementBody.of(body), 250.0);
    step.publish(kind, ElementBody.of(body));
  }
}
