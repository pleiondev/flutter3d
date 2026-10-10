/// `EntityKinds`: the level format's slot in the plugin host, filled by the
/// plugins an engine installs and emptied again when they are switched off;
/// and `GenrePlugin`, the shape every genre installs through.
///
///     dart test test/entity_kinds_test.dart
///
/// Each test was written by breaking what it covers first; the mutation that
/// would defeat it is named in the test.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A plugin that adds [kinds] when installed.
final class _Kinds extends Flutter3dPlugin {
  _Kinds(this.id, this.kinds);

  final String id;
  final List<EntityKind> kinds;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) {
    host.maybeRegistry<EntityKinds>()?.addAll(kinds);
  }
}

/// A door of another genre's: the format's word, spawned differently.
final class _OtherDoor extends EntityKind {
  const _OtherDoor() : super(EntityTypes.door);
}

/// The smallest genre: a counter it steps, and the kinds it is handed.
final class _Genre extends GenrePlugin<List<double>> {
  _Genre(this.id, {super.kinds, super.replaceKinds});

  final String id;

  @override
  String get systemName => '$id.step';

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
  );

  @override
  void stepSimulation(List<double> simulation, LoopContext context) =>
      simulation.add(context.dt);

  @override
  Snapshot captureSimulation(List<double> simulation) =>
      Snapshot(<String, Object?>{'steps': List<double>.of(simulation)});

  @override
  void restoreSimulation(List<double> simulation, Snapshot state) {
    simulation
      ..clear()
      ..addAll(<double>[
        if (state.data['steps'] case final List<Object?> steps)
          for (final dt in steps)
            if (dt is num) dt.toDouble(),
      ]);
  }
}

void main() {
  test('a plugin adds its kinds, and the registry a level reads has them', () {
    final kinds = EntityKinds(<EntityKind>[const PlayerSpawnKind()]);
    EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[kinds],
      plugins: <Flutter3dPlugin>[
        _Kinds('doors', <EntityKind>[const DoorKind(), const LiftKind()]),
      ],
    );
    // Mutation: build `registry()` from the application's kinds only. The
    // plugin's door is then unknown to the level that names it.
    final registry = kinds.registry();
    expect(registry.knows(EntityTypes.door), isTrue);
    expect(registry.knows(EntityTypes.playerSpawn), isTrue);
    expect(kinds.types, <String>[
      EntityTypes.playerSpawn,
      EntityTypes.door,
      EntityTypes.lift,
    ]);
    // Mutation: file a scoped registration under 'app'. A tool asking who
    // brought the door would be told nobody did.
    expect(kinds.ownerOf(EntityTypes.door), 'doors');
    expect(kinds.ownerOf(EntityTypes.playerSpawn), 'app');
  });

  test('switching the plugin off takes its kinds out at the boundary', () {
    final kinds = EntityKinds();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[kinds],
      plugins: <Flutter3dPlugin>[
        _Kinds('doors', <EntityKind>[const DoorKind()]),
      ],
    );
    loop.plugins.disable('doors');
    loop.runSteps(1);
    // Mutation: return an untracked registration from the scoped view. The
    // door outlives the plugin that brought it.
    expect(kinds.knows(EntityTypes.door), isFalse);
    loop.plugins.enable('doors');
    loop.runSteps(1);
    expect(kinds.knows(EntityTypes.door), isTrue);
  });

  test('two plugins claiming one type with different kinds are refused, '
      'naming both', () {
    final kinds = EntityKinds();
    // Mutation: let a later kind replace an earlier one of its type. Two
    // genres would then spawn each other's doors without a word.
    expect(
      () => EngineLoop(
        input: InputState(),
        registries: <PluginRegistry>[kinds],
        plugins: <Flutter3dPlugin>[
          _Kinds('first', <EntityKind>[const DoorKind()]),
          _Kinds('second', <EntityKind>[const _OtherDoor()]),
        ],
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          allOf(contains('first'), contains('second')),
        ),
      ),
    );
  });

  test('the same kind from two plugins is shared, and stays until the last '
      'holder goes', () {
    final kinds = EntityKinds();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[kinds],
      plugins: <Flutter3dPlugin>[
        _Kinds('first', <EntityKind>[const DoorKind()]),
        _Kinds('second', <EntityKind>[const DoorKind()]),
      ],
    );
    // Mutation: refuse a second claim whatever it is. Two genres that both
    // speak the format's `door` could never be installed together.
    expect(kinds.holdersOf(EntityTypes.door), <String>['first', 'second']);
    expect(kinds.types, <String>[EntityTypes.door]);

    // Mutation: take the kind out on the first holder's cancel. The second
    // genre's levels would stop knowing what a door is.
    loop.plugins.disable('first');
    loop.runSteps(1);
    expect(kinds.knows(EntityTypes.door), isTrue);
    expect(kinds.ownerOf(EntityTypes.door), 'second');
    loop.plugins.disable('second');
    loop.runSteps(1);
    expect(kinds.knows(EntityTypes.door), isFalse);
  });

  test('a genre that replaces kinds stands over the other one while it is '
      'installed, and gives it back', () {
    final kinds = EntityKinds(<EntityKind>[const DoorKind()]);
    final steps = <double>[];
    final genre = _Genre(
      'other',
      kinds: const <EntityKind>[_OtherDoor()],
      replaceKinds: true,
    )..simulation = steps;
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[kinds],
      plugins: <Flutter3dPlugin>[genre],
    );
    // Mutation: add rather than replace when `replaceKinds` is set. The
    // install throws for the application's door.
    expect(kinds[EntityTypes.door], isA<_OtherDoor>());
    expect(kinds.ownerOf(EntityTypes.door), 'other');

    loop.runSteps(2);
    // Mutation: drop the simulation on install. A genre installed after its
    // run was set would step nothing.
    expect(steps, hasLength(2));

    // Mutation: remove the type on uninstall instead of restoring what was
    // under it. The application's door would be gone with the genre.
    loop.plugins.disable('other');
    loop.runSteps(1);
    expect(kinds[EntityTypes.door], isA<DoorKind>());
    expect(kinds.ownerOf(EntityTypes.door), 'app');
    expect(steps, hasLength(2));
  });
}
