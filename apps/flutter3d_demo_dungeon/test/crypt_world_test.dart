/// The crypt's fire, water and loose wood as part of the run: the vault's
/// water holds the player back by what wading is measured to cost, a fire
/// hurts by the heat it sends them, and a restore or a replay puts the
/// crates, the flames and the water back bit for bit.
///
///     flutter test test/crypt_world_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_content/crypt.dart';
import 'package:flutter3d_demo_content/shooter_sample.dart';
import 'package:flutter3d_demo_dungeon/src/run_cubit.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

import 'heard_events.dart';

const double _dt = 1.0 / 60.0;

final class _Storage extends Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  Future<String?> read(String name) async => documents[name];
  @override
  Future<void> write(String name, String contents) async {
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);
}

/// The first crypt, opened the way the game opens it.
Future<({LevelReady level, InputState input})> _crypt() async {
  final it = cpuTestDevice(width: 16, height: 16);
  final input = InputState();
  final run = RunCubit(
    DungeonRun(
      firstLevel: 'assets/levels/crypt.json',
      registry: sampleRegistry(extra: const <EntityKind>[WidgetSurfaceKind()]),
      input: input,
      inventory: startingInventory(),
      saves: SaveFile(appName: 'dungeon', storage: _Storage()),
      device: it.device,
    ),
  );
  await run.begin();
  return (level: (run.state as RunPlaying<LevelReady>).level, input: input);
}

void _step(LevelReady level, InputState input) {
  level.staged.sim.step(_dt);
  input.endStep();
}

/// The first crate, set down a metre in front of the player where they
/// stand at the start and set alight: hot through, as a crate thrown out of
/// a fire would be.
CryptWood _burningCrateBy(LevelReady level) {
  final crypt = level.crypt!;
  final crate = crypt.wood.firstWhere((w) => w.kind == WoodKind.crate);
  final player = level.staged.player.body;
  final feet = player.position.y - player.halfExtents.y;
  crypt.world
    ..setPosition(
      crate.body,
      Vector3(player.position.x, feet + 0.4, player.position.z - 1.0),
    )
    ..setVelocity(crate.body, Vector3.zero())
    ..setTemperature(crate.body, 900.0);
  return crate;
}

void main() {
  setUpAll(() => startPhysics(asked: 'native'));
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the laws', () {
    test('wading slows as Postacchini measured, and not at all when '
        'shallow', () {
      // Knee deep, 0.35 m: 64 % of a dry walk, beside the 61 % Li and
      // colleagues measured for men at that depth.
      // Mutation: the exponent's sign turned (M^0.19) — the walker in deep
      // water goes faster than on dry floor, and the share is capped at one.
      expect(CryptHarm.wadingShare(0.35), closeTo(0.644, 0.002));
      // Mutation: drop the `min(1, …)` — a puddle hurries the walker on.
      expect(CryptHarm.wadingShare(0.05), 1.0);
      expect(CryptHarm.wadingShare(0.0), 1.0);
      // Running water pushes harder than still: v²d/g adds to the force.
      // Mutation: drop the flow term.
      expect(
        CryptHarm.wadingShare(0.3, flow: 1.5),
        lessThan(CryptHarm.wadingShare(0.3)),
      );
    });

    test('heat at or under 2.5 kW/m² does no harm; over it, as ISO 13571 '
        'gives', () {
      // Mutation: `<` for `<=` — exactly 2.5 kW/m², which §8.4 says is
      // borne however long, starts hurting.
      expect(CryptHarm.dosePerSecond(2500.0), 0.0);
      expect(CryptHarm.dosePerSecond(2600.0), greaterThan(0.0));
      // 10 kW/m²: a second-degree burn in 6.9·10^−1.56 = 0.190 minutes.
      // Mutation: minutes taken as seconds — sixty times the harm.
      expect(
        CryptHarm.dosePerSecond(10000.0),
        closeTo(1 / (0.19004 * 60), 1e-4),
      );
    });

    test('a fire sends a point source far off, and no more than its soot '
        'radiates close to', () {
      // 100 kW, a third of it radiant, its soot at 1200 K.
      double at(double far) => CryptHarm.flux(
        power: 1e5,
        radiantShare: 0.3,
        sootTemperature: 1200.0,
        far: far,
      );
      // Mutation: the sphere's 4π lost — four times the flux at range.
      expect(at(4.0), closeTo(3e4 / (4 * 3.14159265 * 16.0), 0.5));
      // In it and beside it: the soot's σT⁴, 117.6 kW/m².
      // Mutation: drop the cap — the point source runs to infinity.
      const soot = stefanBoltzmann * 1200.0 * 1200.0 * 1200.0 * 1200.0;
      expect(at(0.0), closeTo(soot, 1.0));
      expect(at(0.05), closeTo(soot, 1.0));
    });
  });

  test('wading in the vault holds the player back by the water at their '
      'feet', () async {
    final (:level, :input) = await _crypt();
    final crypt = level.crypt!;
    final player = level.staged.player;
    // In the middle of the flooded vault, standing.
    player.body.teleport(Vector3(12.0, 0.95, -6.0));
    for (var i = 0; i < 30; i++) {
      _step(level, input);
    }
    expect(player.body.isGrounded, isTrue);
    input.press(GameAction.moveForward);
    for (var i = 0; i < 20; i++) {
      _step(level, input);
    }
    // What the next step's walk is held to, from the water where the
    // player stands now.
    final (:depth, :flow) = crypt.wadingOf(
      player.body.position,
      player.body.halfExtents.y,
    );
    expect(depth, greaterThan(0.15), reason: 'a hand of water over the flags');
    final share = CryptHarm.wadingShare(depth, flow: flow);
    _step(level, input);
    final v = player.body.velocity;
    final speed = Vector2(v.x, v.z).length;
    // Mutation: `_wade` left out of the step — the player walks at 6 m/s
    // through the water as across the floor.
    expect(speed, closeTo(const MovementSettings().walkSpeed * share, 1e-5));
    expect(share, lessThan(0.8));
  });

  test('running into the water at a dry pace, the drag on the shins takes '
      'it off within a tenth of a second', () async {
    final (:level, :input) = await _crypt();
    final player = level.staged.player;
    player.body.teleport(Vector3(12.0, 0.95, -4.0));
    for (var i = 0; i < 30; i++) {
      _step(level, input);
    }
    input.press(GameAction.moveForward);
    _step(level, input);
    // As if they had come in from the floor outside at a walk.
    final dry = const MovementSettings().walkSpeed;
    player.body.velocity
      ..x = 0.0
      ..z = -dry;
    _step(level, input);
    double speed() =>
        Vector2(player.body.velocity.x, player.body.velocity.z).length;
    // Slowed on the first step, and not all at once.
    expect(speed(), lessThan(dry));
    expect(speed(), greaterThan(player.body.tuning.walkSpeed));
    for (var i = 0; i < 9; i++) {
      _step(level, input);
    }
    // Mutation: drop the drag in `_wade` — the controller never brakes a
    // body asked to go on, and they cross the vault at the floor's pace.
    expect(speed(), lessThan(dry * 0.85));
  });

  test(
    'a burning crate beside the player hurts them by the heat it sends',
    () async {
      final (:level, :input) = await _crypt();
      final crypt = level.crypt!;
      final health = level.staged.player.inventory.health;
      final before = health.current;
      _burningCrateBy(level);
      final heard = HeardEvents.of(level.staged);
      var hurt = 0;
      var hottest = 0.0;
      for (var i = 0; i < 240; i++) {
        _step(level, input);
        hottest = hottest > crypt.heatOnPlayer()
            ? hottest
            : crypt.heatOnPlayer();
        hurt += heard.take().whereType<PlayerHurt>().length;
      }
      expect(hottest, greaterThan(CryptHarm.harmless));
      // Mutation: `_burn` left off the step — the fire burns and the player
      // stands in front of it unharmed.
      expect(health.current, lessThan(before));
      expect(hurt, greaterThan(0), reason: 'and the run hears it as a hurt');
    },
  );

  test(
    'a run restored mid-burn steps on to the same crypt, bit for bit',
    () async {
      final (:level, :input) = await _crypt();
      final sim = level.staged.sim;
      final crypt = level.crypt!;
      _burningCrateBy(level);
      for (var i = 0; i < 90; i++) {
        _step(level, input);
      }
      expect(crypt.world.fires(), isNotEmpty);
      final saved = sim.save();
      String onward() {
        for (var i = 0; i < 90; i++) {
          _step(level, input);
        }
        return base64Encode(crypt.world.snapshot()) +
            jsonEncode(sim.save().toJson());
      }

      final first = onward();
      sim.restore(saved);
      // Mutation: the crypt not hung on the run's entities — the restore
      // leaves the crate burnt ninety steps further, and the run steps on
      // from a different fire.
      expect(onward(), first);
    },
  );

  test('a tape replayed on a fresh crypt lands where the run did', () async {
    final live = await _crypt();
    _burningCrateBy(live.level);
    for (var i = 0; i < 60; i++) {
      _step(live.level, live.input);
    }
    final start = live.level.staged.sim.save();
    final recorder = InputTapeRecorder(seed: start.data.integer('random'));
    for (var i = 0; i < 120; i++) {
      if (i == 10) live.input.press(GameAction.moveForward);
      if (i == 70) live.input.release(GameAction.moveForward);
      recorder.record(live.input);
      _step(live.level, live.input);
    }
    final ended = jsonEncode(live.level.staged.sim.save().toJson());

    final again = await _crypt();
    again.level.staged.sim.restore(start);
    final playback = InputTapePlayback(recorder.tape);
    while (!playback.isFinished) {
      playback.applyTo(again.input);
      _step(again.level, again.input);
    }
    // Mutation: the snapshot leaves the crypt out — the fresh one has no
    // fire, and the crate the player walks into is where the level put it.
    expect(jsonEncode(again.level.staged.sim.save().toJson()), ended);
  });
}
