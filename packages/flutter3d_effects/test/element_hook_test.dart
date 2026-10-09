/// A plugin element over the elements' world: where it steps and draws,
/// its switch, its snapshot, and the phase it takes in a loop — and fire
/// and water as two hooks of the same kind.
///
///     dart test test/element_hook_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'support.dart';

Future<Elements> _open() {
  final device = elementsDevice();
  return Elements.open(
    device: device,
    renderer: Renderer.create(device: device),
    scene: Scene(),
    load: (_) async => waterBundle(),
    quality: ElementsQuality.of(phone: true),
  );
}

/// Writes down when it is stepped and drawn, and keeps a count it saves.
final class _Probe extends ElementHook {
  _Probe(this.id, this.log, {this.onByDefault = true});

  @override
  final String id;
  final List<String> log;
  final bool onByDefault;
  int counted = 0;

  @override
  ElementSwitch get switchedBy => ElementSwitch(id, onByDefault: onByDefault);

  @override
  void step(ElementStep step) {
    counted++;
    log.add('$id.step');
  }

  @override
  void view(ElementFrame frame) => log.add('$id.view');

  @override
  Object? save() => counted;

  @override
  void restore(Object? saved) => counted = saved is int ? saved : 0;
}

void main() {
  test('fire and water are the elements every Elements starts with', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    // Mutation: add fire before water in the constructor — the waters are
    // then drawn after the fires, which is not the order they always were.
    expect(elements.elements.map((e) => e.id), <String>['water', 'fire']);
  });

  test('a plugin element steps after fire and water, then draws', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    final log = <String>[];
    elements
      ..addElement(_Probe('frost', log))
      ..addElement(_Probe('gust', log));
    elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    // Mutation: draw each element right after its step — the views come
    // before the world has stepped, and show the step before.
    expect(log, <String>['frost.step', 'gust.step', 'frost.view', 'gust.view']);
  });

  test('a switched-off element is not drawn, and still steps', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    final log = <String>[];
    final frost = _Probe('frost', log);
    elements
      ..addElement(frost)
      ..switches = ElementsSteps.all.withElement('frost', on: false);
    elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    // Mutation: skip the step with the view — the world then steps
    // differently with a switch, which a switch may never do.
    expect(log, <String>['frost.step']);
    expect(frost.counted, 1);
    // An element off by its own default stays off under `all`, and `none`
    // switches every element nobody named off.
    final quiet = <String>[];
    elements
      ..addElement(_Probe('dew', quiet, onByDefault: false))
      ..switches = ElementsSteps.all;
    elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    expect(quiet, <String>['dew.step']);
    expect(ElementsSteps.none.isOn('anything'), isFalse);
  });

  test('an element given step: false is only drawn', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    final log = <String>[];
    elements.addElement(_Probe('frost', log), step: false);
    elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    // Mutation: ignore `step` in `update` — an element a loop steps is then
    // stepped twice a step.
    expect(log, <String>['frost.view']);
  });

  test('one id is held once, fire\'s and water\'s included', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    // Mutation: drop the check in `addElement` — a second fire is added and
    // the held flames run down twice as fast.
    expect(
      () => elements.addElement(_Probe('fire', <String>[])),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('each element\'s own state is saved and put back', () async {
    final elements = await _open();
    addTearDown(elements.dispose);
    final frost = _Probe('frost', <String>[]);
    elements.addElement(frost);
    final crate = elements.addBody(
      Solid.box(
        Vector3.all(0.1),
        material: NativeMaterial.wood(),
        density: 500.0,
      ),
      at: Vector3(0.0, 0.1, 0.0),
      type: NativeBodyType.fixed,
    );
    elements.fires.ignite(crate, by: Igniter.match);
    for (var i = 0; i < 3; i++) {
      elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    }
    final saved = elements.saveElements();
    // Mutation: return null from the fire element's `save` — a run saved
    // while a match is held comes back with the match gone.
    expect(saved['fire'], isA<List<Object?>>());
    expect(saved['frost'], 3);
    for (var i = 0; i < 3; i++) {
      elements.update(1 / 30, eye: Vector3(0.0, 1.0, 3.0));
    }
    elements.restoreElements(saved);
    expect(frost.counted, 3);
    // Mutation: restore the held flames with their full time — the saved
    // `left` differs from what was put back.
    expect(elements.saveElements()['fire'], saved['fire']);
  });
}
