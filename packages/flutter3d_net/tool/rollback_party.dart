/// Rollback between N machines in one process, over a loopback party as
/// late and as lossy as asked, each machine timing the steps it runs again:
/// the rehearsal of P4's eight phones, and the harness that keeps the
/// resimulation timer honest.
///
///     dart run tool/rollback_party.dart --players 8 --rtt-ms 50 \
///       --seconds 600 --out <dir> --fail-on dropped=0.5,p99=8
///
/// Every machine plays the same small world: [_World.bodies] balls pushing
/// one another apart, each player's hand pushing one of them, the hands
/// rolled from a seed per player and changed every few steps, so most
/// guesses about another machine are wrong and roll back. A step costs what
/// the pairs cost (`--bodies` sets it), which is what the timer measures.
///
/// **Time is steps.** The party is ticked once a step and a message takes
/// half the round trip, rounded to whole sixtieths of a second, to arrive:
/// `--rtt-ms 50` is a two-step delay each way. `--loss` drops that share of
/// the unreliable messages. The run is as fast as the machine steps, not
/// held to sixty a second: the times are a step's own cost.
///
/// Writes one `machine-<slot>.json` per machine into `--out` (the shape
/// `tool/rollback_report.dart` reads, the same a phone writes) and
/// `report.md` beside them, and exits non-zero when a threshold fails.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'rollback_report.dart' as report;

/// One machine's copy of the game: positions and velocities of the balls,
/// flat.
final class _World {
  _World(this.bodies) : state = Float64List(bodies * 4) {
    for (var i = 0; i < bodies; i++) {
      state[i * 4] = (i % 8) * 1.5;
      state[i * 4 + 1] = (i ~/ 8) * 1.5;
    }
  }

  final int bodies;
  Float64List state;

  /// Every slot's hand pushes its own ball; then every pair repels inside
  /// two metres, and the balls move and slow.
  void step(Map<int, Map<String, Object?>> frames) {
    const dt = 1.0 / 60.0;
    for (final MapEntry(key: slot, value: frame) in frames.entries) {
      final i = (slot % bodies) * 4;
      state[i + 2] += ((frame['x'] as int?) ?? 0) * 0.5;
      state[i + 3] += ((frame['y'] as int?) ?? 0) * 0.5;
    }
    for (var a = 0; a < bodies; a++) {
      for (var b = a + 1; b < bodies; b++) {
        final dx = state[b * 4] - state[a * 4];
        final dy = state[b * 4 + 1] - state[a * 4 + 1];
        final d2 = dx * dx + dy * dy;
        if (d2 >= 4.0 || d2 == 0.0) continue;
        final push = (4.0 - d2) * 0.05;
        state[a * 4 + 2] -= dx * push;
        state[a * 4 + 3] -= dy * push;
        state[b * 4 + 2] += dx * push;
        state[b * 4 + 3] += dy * push;
      }
    }
    for (var i = 0; i < bodies; i++) {
      state[i * 4] += state[i * 4 + 2] * dt;
      state[i * 4 + 1] += state[i * 4 + 3] * dt;
      state[i * 4 + 2] *= 0.98;
      state[i * 4 + 3] *= 0.98;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{'state': state.toList()};
}

/// What the harness was asked for.
typedef _Options = ({
  int players,
  double rttMs,
  double loss,
  int seconds,
  int inputDelay,
  int window,
  int bodies,
  int seed,
  String? out,
  String? failOn,
});

_Options _parse(List<String> args) {
  var o = (
    players: 8,
    rttMs: 50.0,
    loss: 0.0,
    seconds: 60,
    inputDelay: 2,
    window: 8,
    bodies: 48,
    seed: 1,
    out: null as String?,
    failOn: null as String?,
  );
  for (var i = 0; i < args.length; i++) {
    final value = i + 1 < args.length ? args[i + 1] : '';
    o = switch (args[i]) {
      '--players' => _with(o, players: int.parse(value)),
      '--rtt-ms' => _with(o, rttMs: double.parse(value)),
      '--loss' => _with(o, loss: double.parse(value)),
      '--seconds' => _with(o, seconds: int.parse(value)),
      '--input-delay' => _with(o, inputDelay: int.parse(value)),
      '--window' => _with(o, window: int.parse(value)),
      '--bodies' => _with(o, bodies: int.parse(value)),
      '--seed' => _with(o, seed: int.parse(value)),
      '--out' => _with(o, out: value),
      '--fail-on' => _with(o, failOn: value),
      final other => throw FormatException('unknown argument $other'),
    };
    i++;
  }
  return o;
}

_Options _with(
  _Options o, {
  int? players,
  double? rttMs,
  double? loss,
  int? seconds,
  int? inputDelay,
  int? window,
  int? bodies,
  int? seed,
  String? out,
  String? failOn,
}) => (
  players: players ?? o.players,
  rttMs: rttMs ?? o.rttMs,
  loss: loss ?? o.loss,
  seconds: seconds ?? o.seconds,
  inputDelay: inputDelay ?? o.inputDelay,
  window: window ?? o.window,
  bodies: bodies ?? o.bodies,
  seed: seed ?? o.seed,
  out: out ?? o.out,
  failOn: failOn ?? o.failOn,
);

Future<void> main(List<String> args) async {
  final _Options o;
  final report.Thresholds thresholds;
  try {
    o = _parse(args);
    thresholds = o.failOn == null
        ? (dropped: null, p99: null)
        : report.parseFailOn(o.failOn!);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(
      'usage: dart run tool/rollback_party.dart [--players 8] [--rtt-ms 50] '
      '[--loss 0] [--seconds 60] [--input-delay 2] [--window 8] '
      '[--bodies 48] [--seed 1] [--out dir] [--fail-on dropped=0.5,p99=8]',
    );
    exit(2);
  }
  final machines = _play(o);
  final dir = Directory(
    o.out ?? Directory.systemTemp.createTempSync('rollback-party').path,
  )..createSync(recursive: true);
  for (final m in machines) {
    File(
      '${dir.path}/machine-${m['slot']}.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(m));
  }
  final page = report.render(
    machines,
    thresholds: thresholds,
    title: 'Rollback party on loopback',
    note:
        'Loopback in one process: ${o.players} machines, a round trip of '
        '${o.rttMs} ms (${_delaySteps(o.rttMs)} steps each way), '
        '${(o.loss * 100).toStringAsFixed(1)} % loss, ${o.seconds} s, '
        '${o.bodies} bodies, seed ${o.seed}. The times are this machine\'s '
        'CPU on the harness\'s world, not a phone\'s on a game.',
  );
  File('${dir.path}/report.md').writeAsStringSync(page.markdown);
  stdout
    ..write(page.markdown)
    ..writeln()
    ..writeln('wrote ${dir.path}');
  exit(page.failures.isEmpty ? 0 : 1);
}

int _delaySteps(double rttMs) => (rttMs / 2 / (1000 / 60)).round();

/// Plays the party and returns each machine's line of the report.
List<Map<String, Object?>> _play(_Options o) {
  const every = 100;
  final party = LoopbackParty(
    o.players,
    delaySteps: _delaySteps(o.rttMs),
    lossRate: o.loss,
    seed: o.seed,
  );
  final worlds = [for (var s = 0; s < o.players; s++) _World(o.bodies)];
  final traces = [
    for (var s = 0; s < o.players; s++) DigestTrace(every: every),
  ];
  final dice = [
    for (var s = 0; s < o.players; s++) GameRandom(o.seed * 31 + s),
  ];
  final held = [
    for (var s = 0; s < o.players; s++) <String, Object?>{'x': 0, 'y': 0},
  ];
  final sessions = <RollbackSession<Float64List>>[
    for (var s = 0; s < o.players; s++)
      RollbackSession<Float64List>(
        wire: party.wire(s),
        localSlot: s,
        players: o.players,
        inputDelay: o.inputDelay,
        maxRollbackFrames: o.window,
        captureLocalFrame: () {
          // A new hand one step in six, on average.
          if (dice[s].nextInt(6) == 0) {
            held[s] = <String, Object?>{
              'x': dice[s].nextInt(3) - 1,
              'y': dice[s].nextInt(3) - 1,
            };
          }
          return held[s];
        },
        applyAndStep: worlds[s].step,
        save: () => Float64List.fromList(worlds[s].state),
        restore: (saved) => worlds[s].state = Float64List.fromList(saved),
        onSettled: (step, after, _) => traces[s].observe(
          step + 1,
          <String, Object?>{'state': after.toList()},
        ),
      ),
  ];
  final steps = o.seconds * 60;
  // The window and the wire drained past the last step, so it settles.
  final tail = o.window + 2 * _delaySteps(o.rttMs) + o.inputDelay + 2;
  for (var i = 0; i < steps + tail; i++) {
    for (final session in sessions) {
      session.advance();
    }
    party.tick();
  }
  return [
    for (var s = 0; s < o.players; s++)
      <String, Object?>{
        'kind': 'rollback-run',
        'version': 1,
        'machine': 'loopback-$s',
        'device': Platform.localHostname,
        'slot': s,
        'players': o.players,
        'stepHz': 60,
        'inputDelay': o.inputDelay,
        'maxRollbackFrames': o.window,
        'rttMs': <String, Object?>{'p50': o.rttMs, 'p99': o.rttMs},
        'lastStep': sessions[s].step,
        'digestEvery': every,
        'digests': <String, Object?>{
          for (final (i, digest) in traces[s].hexDigests.indexed)
            if (traces[s].steps[i] <= steps) '${traces[s].steps[i]}': digest,
        },
        'stats': sessions[s].stats.toJson(),
        'endedBy': 'time',
      },
  ];
}
