/// A plugin written outside the engine, against its published API only.
///
/// **What it does.** Where two bodies press on each other, the contact
/// warms the air around it: every `ContactEvent` leaves heat in a field,
/// `outside.heat`, that a solver of its own spreads and cools each step,
/// and every body standing in the field takes its warmth into its material
/// state as a quantity of its own, `outside.warmth`. The frame draws the
/// field from a copy on the device, and a sound may read it from the
/// published copy.
///
/// **What it proves.** Each seam a plugin after 1.0 stands on, used the way
/// somebody else's package would: a quantity added to a body's
/// `MaterialState` (S1), the contact event heard from the bus (S2), a field
/// declared and written (S3), and a solver registered as a subsystem with
/// what it reads and writes (S4), switched on by a profile of its own, so
/// installing the plugin leaves the default simulation, its tapes and its
/// matches alone.
library;

import 'dart:collection';

import 'package:flutter3d_core/flutter3d_core.dart' show FieldUpload;
import 'package:flutter3d_fields/flutter3d_fields.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show ContactEvent, MaterialStateComponent;

/// The profile that switches the warming on: bit for bit like the default,
/// with the plugin's solver in the step.
///
/// **A profile of the plugin's own**, as a solver a minor adds would be:
/// a run under it names the solver in its `SimulationVersion`, and a run
/// under the default does not.
const SimulationProfile warmingProfile = SimulationProfile(
  'outside.warming',
  isBitExact: true,
  usesDoublePrecision: false,
  allowsAdaptiveSteps: false,
);

/// How much warmer than the air a body is, from what it pressed against:
/// kelvin above the surroundings. A quantity of the plugin's own on a
/// body's material state.
const String warmthId = 'outside.warmth';

/// The heat contacts leave in the air: kelvin above the surroundings, in a
/// grid of 8 by 4 by 8 cells half a metre across, around the origin.
const FieldDeclaration heatField = FieldDeclaration(
  id: 'outside.heat',
  quantity: warmthId,
  unit: Unit.kelvin,
  grid: FieldGrid(8, 4, 8),
  transform: FieldTransform(
    origin: WorldPosition(-1.75, 0.25, -1.75),
    cellSize: 0.5,
  ),
  writer: FieldAccess.simulation(Warming.id),
  readers: <FieldAccess>[
    FieldAccess.frame('outside.heat upload'),
    FieldAccess.audio('outside.hiss'),
  ],
);

/// The solver: spreads the heat contacts left, cools the field towards the
/// air, and hands each body in it its warmth.
///
/// Float32 values and `+`, `-`, `*` alone, so a field stepped from one
/// state on two machines holds the same bits on both.
final class Warming extends Subsystem {
  Warming();

  /// Its id, and its system's name in the loop.
  static const String id = 'outside.warming';

  /// The share of its heat a cell keeps each step: the rest goes to the
  /// air.
  static const double keeps = 0.98;

  /// Kelvin a contact leaves per newton-second of impulse.
  static const double kelvinPerImpulse = 40.0;

  @override
  SubsystemDeclaration get declaration => const SubsystemDeclaration(
    id: id,
    version: 1,
    writesFields: <String>['outside.heat'],
    readsQuantities: <String>[warmthId],
    writesQuantities: <String>[warmthId],
    switchedOnBy: <SimulationProfile>[warmingProfile],
  );

  /// The heat the last step's contacts left, by cell, waiting for this
  /// step: the bus delivers a step's events after its phases.
  final SplayTreeMap<int, double> _pending = SplayTreeMap<int, double>();

  /// Leaves the heat of [contact] in the cell it touched, for the next
  /// step. A contact outside the field leaves none.
  void heard(ContactEvent contact) {
    final at = heatField.transform.gridOf(
      WorldPosition(contact.point.x, contact.point.y, contact.point.z),
    );
    final grid = heatField.grid;
    final (x, y, z) = (at.x.round(), at.y.round(), at.z.round());
    if (x < 0 || y < 0 || z < 0) return;
    if (x >= grid.width || y >= grid.height || z >= grid.depth) return;
    final cell = (z * grid.height + y) * grid.width + x;
    _pending[cell] =
        (_pending[cell] ?? 0.0) + contact.impulse * kelvinPerImpulse;
  }

  /// [_pending] as a part of the loop's snapshots: heat heard and not yet
  /// laid down is state, which a rollback puts back with the rest.
  SnapshotPart get pendingPart => SnapshotPart.of(
    id: 'outside.pending',
    capture: () => <Object?>[
      for (final MapEntry(:key, :value) in _pending.entries)
        <Object?>[key, value],
    ],
    restore: (Object? data, int version) {
      _pending.clear();
      for (final entry in (data! as List<Object?>).cast<List<Object?>>()) {
        _pending[entry[0]! as int] = (entry[1]! as num).toDouble();
      }
    },
  );

  @override
  void step(SubsystemContext context) {
    final heat = context.field(heatField.id);
    final values = heat.values;
    for (var i = 0; i < values.length; i++) {
      values[i] *= keeps;
    }
    for (final MapEntry(:key, :value) in _pending.entries) {
      values[key] += value;
    }
    _pending.clear();
    final world = context.world;
    final bodies =
        world
            .query()
            .having<MaterialStateComponent>()
            .having<WorldPosition>()
            .entities
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    for (final body in bodies) {
      final state = world.get<MaterialStateComponent>(body)!;
      final warmth = heat.quantityAt(world.get<WorldPosition>(body)!);
      world.set(
        body,
        state.withState(state.state.withQuantity(warmthId, warmth)),
      );
    }
  }
}

/// The plugin: declares the field, registers the solver and, where the
/// profile runs it, listens to the contacts.
final class OutsidePlugin extends Flutter3dPlugin {
  OutsidePlugin();

  /// The plugin's id, and its namespace.
  static const String pluginId = 'outside';

  /// The solver this instance registers.
  final Warming warming = Warming();

  @override
  PluginManifest get manifest => const PluginManifest(
    id: pluginId,
    apiVersion: PluginApiVersion.current,
    description:
        'Contacts warm the air, a solver spreads the heat, and bodies '
        'take it into their material state.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 2000},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<FieldRegistry>().declare(heatField);
    final subsystems = host.registry<SubsystemRegistry>()..register(warming);
    // Under a profile that leaves the solver off, the contacts are not its
    // to hear: nothing would lay their heat down, and nothing heard may be
    // state the default simulation does not have.
    if (!subsystems.running.any((d) => d.id == Warming.id)) return;
    host.registry<SnapshotRegistry>().add(warming.pendingPart);
    host.events.onStep<ContactEvent>(
      '${Warming.id}.contacts',
      (Delivered<ContactEvent> delivered) => warming.heard(delivered.event),
    );
  }

  /// The node that puts the field on the device the frame draws on, as a
  /// 3D texture a volume samples, from the copy the simulation published:
  /// what an application adds to its renderer after placing it
  /// (`FieldUpload.place`) on the device's executors. Null where the field
  /// is not declared.
  static FieldUpload? upload(FieldRegistry fields) =>
      switch (fields.published(heatField.id)) {
        final HostField published => FieldUpload(published),
        null => null,
      };
}
