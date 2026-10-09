/// Four machines playing one game over a late, lossy wire, each rolling back
/// when a guess about another turns out wrong, and a fifth that only watches
/// the steps they have settled.
///
/// **All five are in this process.** `LoopbackParty` is the wire a test
/// gives a party: messages arrive a few steps late, some never, the same
/// ones for the same seed. Over a network the same objects sit on
/// `PeerWire.party` over a relay's party room instead.
///
/// Quoted by `parties.md` and shown whole in the Source tab.
library;

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show StateDigest;

const int _players = 4;

// #region game
/// The whole game: how far round the track each player is, in centimetres.
/// Each step moves every player by its own frame, and drags the first one
/// by the last one's position, so a wrong guess about anybody moves
/// somebody else too.
List<int> _step(List<int> at, Map<int, Map<String, Object?>> frames) {
  final next = List<int>.of(at);
  for (final MapEntry(:key, :value) in frames.entries) {
    next[key] += (value['dx'] as int?) ?? 0;
  }
  next[0] += next.last % 3;
  return next;
}

/// What machine [slot] presses at its [n]th step: changing often, so that
/// guessing it from the last one is often wrong.
int _press(int slot, int n) => 2 + (n * 7 + slot * 13) % 5;
// #endregion game

/// Everything on one wire: the four players' machines, the host's tape for
/// spectators, and a spectator.
final class _Party {
  // #region machines
  _Party({required int delay, required double loss, required int seed})
    : wire = LoopbackParty(
        _players + 1,
        delaySteps: delay,
        lossRate: loss,
        seed: seed,
      ) {
    tape = PartyTape<List<int>>(wire: wire.wire(0), encode: (s) => s);
    for (var slot = 0; slot < _players; slot++) {
      var captures = 0;
      machines.add(
        RollbackSession<List<int>>(
          wire: wire.wire(slot),
          players: _players,
          inputDelay: 2,
          maxRollbackFrames: 12,
          captureLocalFrame: () => <String, Object?>{
            'dx': pressing ? _press(slot, captures++) : 0,
          },
          applyAndStep: (frames) => states[slot] = _step(states[slot], frames),
          save: () => List<int>.of(states[slot]),
          restore: (state) => states[slot] = List<int>.of(state),
          // The host hands what settles to the tape, and hears who watches.
          onSettled: (step, after, frames) {
            settled[slot][step + 1] = after;
            if (slot == 0) tape.settled(step, after, frames);
          },
          onMessage: slot == 0 ? tape.hear : null,
        ),
      );
    }
    // The fifth slot plays no part in the rollback: it only watches.
    watcher = PartyTapeWatcher<List<int>>(
      wire: wire.wire(_players),
      decode: (encoded) => List<int>.of(encoded! as List<int>),
      restore: (state) => watched = state,
      applyAndStep: (frames) => watched = _step(watched, frames),
    );
  }
  // #endregion machines

  final LoopbackParty wire;
  late final PartyTape<List<int>> tape;
  late final PartyTapeWatcher<List<int>> watcher;
  final List<RollbackSession<List<int>>> machines =
      <RollbackSession<List<int>>>[];

  /// What each machine thinks the game is now, guesses and all.
  final List<List<int>> states = List<List<int>>.generate(
    _players,
    (_) => List<int>.filled(_players, 0),
  );

  /// The states each machine settled, by step.
  final List<Map<int, List<int>>> settled = List<Map<int, List<int>>>.generate(
    _players,
    (_) => <int, List<int>>{},
  );

  List<int> watched = List<int>.filled(_players, 0);
  bool pressing = true;
  int ticks = 0;

  // #region tick
  /// One step on every machine, the spectator's turn after a while, and
  /// then whatever the wire has due arrives.
  void tick() {
    for (final machine in machines) {
      machine.advance();
    }
    if (ticks >= 40) {
      watcher
        ..ask()
        ..advance();
    }
    wire.tick();
    ticks++;
  }
  // #endregion tick
}

final class PartiesDemo extends ShowcaseDemo {
  double delay = 4;
  late _Party _party;

  /// A row of four balls per machine, and a fifth row for the spectator.
  final List<List<MeshNode>> _rows = <List<MeshNode>>[];
  double _due = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 15.0
      ..pitch = 0.9
      ..yaw = 0.0;
    context.orbit.target.setValues(6.0, 0.0, 3.2);
  }

  @override
  Scene build(DemoContext context) {
    _party = _Party(delay: delay.round(), loss: 0.1, seed: 5);
    final DeviceMesh ball = DeviceMesh.upload(
      context.device,
      SphereShape(segments: 16, rings: 8, radius: 0.25).build(),
    );
    final List<Vector4> colors = <Vector4>[
      Vector4(0.9, 0.35, 0.2, 1.0),
      Vector4(0.25, 0.55, 0.9, 1.0),
      Vector4(0.95, 0.8, 0.2, 1.0),
      Vector4(0.4, 0.8, 0.45, 1.0),
    ];
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.4 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.4 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -1.0, -0.4)),
      );
    for (var row = 0; row <= _players; row++) {
      final bool spectator = row == _players;
      scene.add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(12.6, 0.1, 1.2)).build(),
          ),
          RenderMaterial(
            name: 'lane $row',
            baseColor: spectator
                ? LinearColor.fromSrgb(0.2, 0.2, 0.25, 1.0)
                : LinearColor.fromSrgb(0.36, 0.38, 0.4, 1.0),
          ),
          name: spectator ? 'spectator' : 'machine $row',
        )..setPosition(6.0, -0.05, row * 1.6),
      );
      _rows.add(<MeshNode>[
        for (var p = 0; p < _players; p++)
          MeshNode(
            ball,
            RenderMaterial(name: 'player $p', baseColor: _fromSrgb(colors[p])),
            name: 'row $row player $p',
          ),
      ]);
      _rows.last.forEach(scene.add);
    }
    _place();
    return scene;
  }

  /// Each row as its machine has the game, each player along its lane at
  /// its distance round a twelve-metre track.
  void _place() {
    for (var row = 0; row <= _players; row++) {
      final List<int> at = row == _players
          ? _party.watched
          : _party.states[row];
      for (var p = 0; p < _players; p++) {
        _rows[row][p].setPosition(
          (at[p] % 1200) / 100.0,
          0.25,
          row * 1.6 + (p - 1.5) * 0.25,
        );
      }
    }
  }

  @override
  void update(DemoContext context, double dt) {
    // Thirty steps a second, so the rollbacks can be seen as jumps.
    _due += dt;
    while (_due >= 1 / 30) {
      _due -= 1 / 30;
      _party.tick();
    }
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Steps late (${_party.machines.fold(0, (int a, m) => a + m.stepsRerun)} '
      'rerun)',
      min: 0,
      max: 10,
      divisions: 10,
      value: () => delay,
      onChanged: (double v) {
        delay = v;
        _party = _Party(delay: v.round(), loss: 0.1, seed: 5);
      },
      format: (double v) => v.round().toString(),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // Four seconds of play four steps late, a tenth of the messages lost;
    // then everybody lets go, and the wire is given time to catch up.
    final party = _Party(delay: 4, loss: 0.1, seed: 5);
    for (var i = 0; i < 240; i++) {
      party.tick();
    }
    party.pressing = false;
    for (var i = 0; i < 40; i++) {
      party.tick();
    }
    final int reruns = party.machines.fold(0, (a, m) => a + m.stepsRerun);
    if (reruns == 0) throw StateError('no guess was ever wrong');
    final Set<int> digests = <int>{
      for (final List<int> state in party.states) StateDigest.of(state),
    };
    if (digests.length != 1) {
      throw StateError('the four machines ended on $digests');
    }
    // And that one is the game played on a wire that is never late and
    // never loses anything.
    final perfect = _Party(delay: 0, loss: 0.0, seed: 5);
    for (var i = 0; i < 280; i++) {
      if (i == 240) perfect.pressing = false;
      perfect.tick();
    }
    if (StateDigest.of(perfect.states[0]) != digests.single) {
      throw StateError('the four agree on something that never happened');
    }
    // Every step any two machines settled, they settled the same.
    for (final MapEntry(key: step, value: state) in party.settled[0].entries) {
      for (var slot = 1; slot < _players; slot++) {
        final List<int>? other = party.settled[slot][step];
        if (other != null && StateDigest.of(other) != StateDigest.of(state)) {
          throw StateError('slot $slot settled step $step differently');
        }
      }
    }
    // The spectator, who came late, is where the players settled.
    final int? next = party.watcher.next;
    final List<int>? truth = next == null ? null : party.settled[0][next];
    if (truth == null ||
        StateDigest.of(party.watched) != StateDigest.of(truth)) {
      throw StateError('the spectator is not on the settled tape');
    }
    // #endregion check
    if (frame.drawCalls < 5) throw StateError('the lanes were not drawn');
  }
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
