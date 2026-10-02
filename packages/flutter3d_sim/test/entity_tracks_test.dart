/// `N4`'s per-entity tracks: a run read back as one lane per component of
/// each entity, holding only the steps at which something changed.
///
///     flutter test test/entity_tracks_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

final class _Health {
  _Health(this.hp);
  int hp;
}

EcsWorld _world() => EcsWorld()
  ..register<_Health>(
    'Health',
    encode: (h) => h.hp,
    decode: (d) => d is num ? _Health(d.toInt()) : null,
  );

void main() {
  test('reads an EcsWorld save as entity, component, value', () {
    // Mutation: key the pivot by component first — the entity is then
    // `Health` and the component `0`.
    final world = _world();
    final a = world.spawn();
    world.set(a, _Health(5));
    final entities = EntityLayout.ecs(const <String>[
      'world',
    ]).entitiesOf(Snapshot(<String, Object?>{'world': world.save()}));

    expect(entities, <String, Map<String, Object?>>{
      '${a.index}': <String, Object?>{'Health': 5},
    });
  });

  test('reads rows as entities, by index or by key', () {
    // Mutation: name list rows by their contents' `id` — a row with none
    // then disappears.
    final listed = EntityLayout.rows('monsters').entitiesOf(
      const Snapshot(<String, Object?>{
        'monsters': <Object?>[
          <String, Object?>{'hp': 3, 'x': 1.0},
          7,
        ],
      }),
    );
    expect(listed, <String, Map<String, Object?>>{
      '0': <String, Object?>{'hp': 3, 'x': 1.0},
      '1': <String, Object?>{'value': 7},
    });

    final keyed = EntityLayout.rows('doors').entitiesOf(
      const Snapshot(<String, Object?>{
        'doors': <String, Object?>{
          'crypt_door': <String, Object?>{'open': false},
        },
      }),
    );
    expect(keyed.keys, <String>['crypt_door']);
  });

  test('a lane holds the changes, and a removal closes it', () {
    // Mutation: append a sample on every observe. The lane for a value that
    // held still is then a hundred entries long.
    final world = _world();
    final hero = world.spawn();
    final crate = world.spawn();
    world
      ..set(hero, _Health(10))
      ..set(crate, _Health(1));
    final tracks = EntityTracks(EntityLayout.ecs());
    for (var step = 0; step < 100; step++) {
      if (step == 40) world.get<_Health>(hero)!.hp = 7;
      if (step == 60) world.remove<_Health>(crate);
      tracks.observe(step, Snapshot(world.save()));
    }

    final heroLane = tracks.samples('${hero.index}', 'Health');
    expect([for (final s in heroLane) (s.step, s.value)], [(0, 10), (40, 7)]);

    final crateLane = tracks.samples('${crate.index}', 'Health');
    expect(
      [for (final s in crateLane) (s.step, s.present)],
      [(0, true), (60, false)],
    );
    expect(tracks.at('${hero.index}', 'Health', 39)!.value, 10);
    expect(tracks.at('${hero.index}', 'Health', 40)!.value, 7);
    expect(tracks.at('${crate.index}', 'Health', 80)!.present, isFalse);
    expect(tracks.span, (first: 0, last: 99));
  });

  test('a step observed twice is not a second history', () {
    // Mutation: drop the guard on `step <= last`. A scrubber that asks for
    // the same window again would then double every mark.
    final tracks = EntityTracks(EntityLayout.rows('e'));
    Snapshot at(int v) => Snapshot(<String, Object?>{
      'e': <Object?>[
        <String, Object?>{'v': v},
      ],
    });
    tracks
      ..observe(0, at(1))
      ..observe(1, at(2))
      ..observe(1, at(3))
      ..observe(0, at(4));

    expect([for (final s in tracks.samples('0', 'v')) s.value], [1, 2]);
  });

  test('differences names every component that moved, in order', () {
    // Mutation: compare presence only. A changed value on both sides is
    // then no difference.
    final layout = EntityLayout.rows('e');
    final a = const Snapshot(<String, Object?>{
      'e': <Object?>[
        <String, Object?>{'hp': 1, 'x': 0},
        <String, Object?>{'hp': 1},
      ],
    });
    final b = const Snapshot(<String, Object?>{
      'e': <Object?>[
        <String, Object?>{'hp': 1, 'x': 2},
        <String, Object?>{'hp': 1, 'shield': true},
      ],
    });

    expect(layout.differences(a, b), <EntityComponent>[
      const EntityComponent('0', 'x'),
      const EntityComponent('1', 'shield'),
    ]);
  });
}
