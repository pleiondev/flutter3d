/// The monsters' animation graph — N1.
///
///     flutter test test/monster_graph_test.dart
///
/// Built over the clips the crypt's own models carry: the runner moves off
/// from idle when it starts to chase, by a blend of its walk and its run,
/// stands when stopped, is struck from whatever it is doing and comes back,
/// and dies from anything; the shooter, which has no run, walks; a model
/// with no idle gets no graph and keeps naming clips.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_demo_dungeon/src/monster_graphs.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart' show Monsters;
import 'package:flutter3d_sim/flutter3d_sim.dart' hide Pose;
import 'package:flutter_test/flutter_test.dart';

/// A graph over [model]'s clips, the machine the dungeon builds for it.
Future<AnimationGraph> _graphOf(String model) async {
  final doc = await decodeModel(
    ModelLoadRequest(source: FileAssetSource('assets_src/models/$model.glb')),
  );
  final machine = MonsterGraphs().machineFor(_nobody(), doc.animations)!;
  return AnimationGraph(
    machine: machine,
    clips: doc.animations,
    pose: Pose.fromNodes(doc.nodes),
  );
}

Actor _nobody() {
  final world = CollisionWorld();
  return ActorSystem(
    world: world,
    random: GameRandom(1),
  ).spawn(body: CharacterController(world: world));
}

/// Says [state] at [speed] for [seconds], and returns where the graph is.
String _say(
  AnimationGraph graph,
  MonsterState state, {
  double speed = 0.0,
  double seconds = 0.5,
}) {
  graph.parameters
    ..setInteger('state', MonsterGraphs.stateCodes.indexOf(state))
    ..setFloat('speed', speed);
  for (var t = 0.0; t < seconds; t += 1.0 / 60.0) {
    graph.evaluate(1.0 / 60.0);
  }
  return graph.state;
}

void main() {
  test('the runner stands, moves off, is struck and back, attacks, and '
      'dies once', () async {
    final g = await _graphOf('monster_runner');
    expect(g.state, 'idle');
    expect(_say(g, MonsterState.alert), 'idle');
    expect(_say(g, MonsterState.chase, speed: 1.5), 'move');
    expect(_say(g, MonsterState.chase, speed: 5.4), 'move', reason: 'one');
    expect(_say(g, MonsterState.chase, speed: 0.0), 'idle');
    expect(_say(g, MonsterState.chase, speed: 5.4), 'move');
    expect(_say(g, MonsterState.hurt, speed: 5.4), 'hurt');
    expect(_say(g, MonsterState.chase, speed: 0.0), 'idle');
    expect(_say(g, MonsterState.attack), 'attack');
    expect(_say(g, MonsterState.dead), 'death');
    expect(_say(g, MonsterState.chase, speed: 5.4), 'death', reason: 'once');
  });

  test('the runner moves by a blend of its walk and its run', () async {
    final doc = await decodeModel(
      ModelLoadRequest(
        source: const FileAssetSource('assets_src/models/monster_runner.glb'),
      ),
    );
    final machine = MonsterGraphs().machineFor(_nobody(), doc.animations)!;
    final move = machine.states[machine.indexOfState('move')];
    expect(move.blend, isNotNull);
    expect(move.blend!.points.map((p) => p.clip), <String>['Walk', 'Run']);
  });

  test(
    'a moving monster steps twice a stride, a standing one not at all',
    () async {
      final g = await _graphOf('monster_runner');
      var steps = 0;
      void count(MonsterState state, double speed, double seconds) {
        g.parameters
          ..setInteger('state', MonsterGraphs.stateCodes.indexOf(state))
          ..setFloat('speed', speed);
        for (var t = 0.0; t < seconds; t += 1.0 / 60.0) {
          g.evaluate(1.0 / 60.0);
          steps += g.passed.where((p) => p.name == 'step').length;
        }
      }

      count(MonsterState.idle, 0.0, 2.0);
      expect(steps, 0);
      count(MonsterState.chase, 5.4, 3.0);
      // All run at 5.4: two footfalls a cycle of the Run clip, over three
      // seconds less a cycle for leaving the idle and the fade in.
      final doc = await decodeModel(
        ModelLoadRequest(
          source: const FileAssetSource('assets_src/models/monster_runner.glb'),
        ),
      );
      final run = doc.animations.firstWhere((c) => c.name == 'Run').duration;
      final cycles = 3.0 / run;
      expect(
        steps,
        inInclusiveRange((2 * (cycles - 1)).floor(), (2 * cycles).ceil()),
      );
    },
  );

  test('the shooter, with no run, walks', () async {
    final g = await _graphOf('monster_shooter');
    expect(_say(g, MonsterState.chase, speed: 3.0, seconds: 1.0), 'move');
    final move = g.machine.states[g.machine.indexOfState('move')];
    expect(move.blend, isNull);
    expect(move.clip, 'Walk');
    expect(_say(g, MonsterState.hurt), 'hurt');
    expect(_say(g, MonsterState.dead), 'death');
  });

  test('a model with no idle keeps naming its clips', () {
    expect(MonsterGraphs().machineFor(_nobody(), <AnimationClip>[]), isNull);
  });

  test('a monster says its state and how fast it goes along the floor', () {
    final actor = _nobody();
    actor.body!.velocity.setValues(3.0, -9.0, 4.0);
    final parameters = AnimationParameters(
      AnimationParameterSchema(<AnimationParameter>[
        const AnimationParameter.integer('state'),
        const AnimationParameter.float('speed'),
      ]),
    );
    MonsterGraphs.writeParameters(actor, parameters);
    expect(parameters.values, <double>[0.0, 5.0]);
    // Dead, whatever its brain said last.
    final mortal = ActorSystem(
      world: CollisionWorld(),
      random: GameRandom(1),
    ).spawn(health: Health(1.0));
    mortal.health!.damage(2.0);
    MonsterGraphs.writeParameters(mortal, parameters);
    expect(
      parameters.values.first,
      MonsterGraphs.stateCodes.indexOf(MonsterState.dead),
    );
  });

  test('a monster watches while it has seen someone, and not dead', () {
    final world = CollisionWorld();
    final system = ActorSystem(world: world, random: GameRandom(1));
    final monster = system.spawn(
      body: CharacterController(world: world),
      health: Health(10.0),
      brain: ChaseBrain(
        def: Monsters.runner,
        shot: WeaponShot(
          world: world,
          hitscan: Hitscan(world: world, random: GameRandom(1)),
          projectiles: ProjectileSystem(world: world),
        ),
      ),
    );
    final brain = monster.brain! as ChaseBrain;
    expect(brain.state, MonsterState.idle);
    expect(MonsterGraphs.shouldWatch(monster), isFalse);
    for (final state in MonsterGraphs.watching) {
      brain.state = state;
      expect(MonsterGraphs.shouldWatch(monster), isTrue, reason: '$state');
    }
    monster.health!.damage(100.0);
    expect(MonsterGraphs.shouldWatch(monster), isFalse);
  });
}
