/// A body's material state as a component: every quantity kept through a
/// save, a snapshot and the wire to a view, the ones this build cannot
/// read included.
///
///     dart test test/material_state_component_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A state as a plugin left it: the engine's temperature and wetness, a
/// plugin's charring, a ripeness in a unit nobody here has heard of, and a
/// later version's spectrum and field.
Map<String, Object?> _fixture() =>
    jsonDecode(
          File('test/fixtures/plugin_material_state.json').readAsStringSync(),
        )
        as Map<String, Object?>;

final ComponentCodec<MaterialStateComponent> _codec =
    MaterialStateComponent.codec;

MaterialStateComponent _read(Object? json) =>
    _codec.decode(json, _codec.version)!;

void main() {
  test('every quantity is kept, the ones it cannot read as they were '
      'written', () {
    // Mutation: read the state whole with MatterState.fromJson — one
    // unit nobody knows refuses the lot; or drop what it cannot read — the
    // plugin's ripeness and the later version's spectrum are gone.
    final component = _read(_fixture());
    expect(component.state.temperature, 412.5);
    expect(component.state['acme.charring'], const Quantity(0.25, Unit.one));
    expect(component.state.phase, MaterialPhase.solid);
    expect(component.unread.keys, <String>['acme.ripeness', 'later.spectrum']);
    expect(_codec.encode(component), _fixture());
  });

  test('through a save written to disk and read back, untouched', () {
    final loop = EngineLoop(input: InputState());
    final plank = loop.world.spawn();
    loop.world.set(plank, _read(_fixture()));
    final onDisk = jsonDecode(jsonEncode(loop.world.save()));

    final again = EngineLoop(input: InputState());
    again.world.restore((onDisk as Map).cast<String, Object?>());
    expect(
      _codec.encode(again.world.get<MaterialStateComponent>(plank)!),
      _fixture(),
    );
  });

  test('through a snapshot and a rewind, untouched', () {
    final loop = EngineLoop(input: InputState());
    final plank = loop.world.spawn();
    loop.world.set(plank, _read(_fixture()));
    final before = loop.capture();
    loop.world.set(plank, const MaterialStateComponent(MatterState.standard));
    loop.restore(before);
    expect(
      _codec.encode(loop.world.get<MaterialStateComponent>(plank)!),
      _fixture(),
    );
  });

  test('through the wire to a view, untouched', () {
    // Mutation: register it unpublished — the view reads nothing.
    final loop = EngineLoop(input: InputState());
    final plank = loop.world.spawn();
    loop.world.set(plank, _read(_fixture()));
    loop.runSteps(1);
    final view = PublishedState.fromWire(loop.published.toWire());
    expect(_codec.encode(view.read(_codec, plank)!), _fixture());
  });

  test('a value given to an id it could not read replaces what it kept', () {
    final component = _read(_fixture());
    final ripe = component.withState(
      component.state.withQuantity(
        'acme.ripeness',
        const Quantity(2.0, Unit.one),
      ),
    );
    expect(ripe.unread.keys, <String>['later.spectrum']);
    final written = _codec.encode(ripe)! as Map<String, Object?>;
    expect(
      (written['quantities']! as Map<String, Object?>)['acme.ripeness'],
      <String, Object?>{'value': 2.0, 'unit': '1'},
    );
    expect(written['since'], 7);
  });

  test('a document that is not a state is not read', () {
    expect(_codec.decode('warm', 1), isNull);
    expect(
      _codec.decode(<String, Object?>{
        'quantities': <String, Object?>{
          'charring': <String, Object?>{'value': 1, 'unit': '1'},
        },
      }, 1),
      isNull,
      reason: 'an id that is not <namespace>.<name>',
    );
  });
}
