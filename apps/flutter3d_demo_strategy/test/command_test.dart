/// Who the click was for.
///
///     flutter test test/command_test.dart
///
/// **The screen this covers used to send the whole crowd.** A tap on the ground
/// ordered `Staged.mine` — the crowd the document opened with — and a move order
/// ends the job it lands on by design, so one click stopped every harvester this
/// side had. The stockpile stopped growing, the halls stopped building, and
/// nothing anywhere said so; the player had paid for a walk with their economy.
/// The first two tests below are that bug, written down both ways round.
///
/// Nothing here draws. The match comes out of the document, which is the half of
/// staging that needs no device — so a match can be played for a simulated
/// minute in a few milliseconds and the click can be measured against what it
/// did to the score.
library;

import 'dart:io';

import 'package:flutter3d_demo_strategy/src/command.dart';
import 'package:flutter3d_demo_strategy/src/level_document.dart';
import 'package:flutter3d_demo_strategy/src/staging.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The document, read off the disk rather than out of the bundle, so these are
/// about the map that is committed.
StrategyMap _map() =>
    StrategyMap.parse(File('assets/levels/map_a.json').readAsStringSync());

/// A match with a small crowd, and the post that commands side [viewerSide].
({Match match, CommandPost command}) _open({int workers = 4}) {
  final StrategyStart start = openMatch(_map(), workers: workers);
  return (
    match: start.match,
    command: CommandPost(
      simulation: start.simulation,
      side: viewerSide,
    ),
  );
}

/// Steps [match] for [seconds] at thirty a second, the way the demo's ticker
/// would, and hands back what this side has brought home.
double _play(Match match, double seconds) {
  for (var i = 0; i < (seconds * 30).round(); i++) {
    match.step(1.0 / 30.0);
  }
  return match.simulation.delivered[viewerSide];
}

/// Straight down onto [unit], which is what a click over a worker is when the
/// camera is above the map.
({Vector3 origin, Vector3 direction}) _onto(Unit unit) => (
  origin: Vector3(unit.position.x, unit.position.y + 50.0, unit.position.z),
  direction: Vector3(0.0, -1.0, 0.0),
);

/// Somewhere on the map that is not where anybody is digging.
final Vector3 _away = Vector3(20.0, 0.0, 20.0);

void main() {
  test('an order to the whole crowd stops the whole economy', () {
    // **The bug, stated.** This is what the screen did on every click, and it
    // is not a claim about selection at all — it is what a move order costs.
    // The test is here rather than in the game package because the game package
    // is right: `Squad.moveTo` cancels the job on purpose, and the mistake was
    // in who the order was given to.
    final (:match, :command) = _open();
    final double before = _play(match, 25.0);
    expect(before, greaterThan(0.0), reason: 'nobody had started digging');

    match.simulation.orders.moveTo(command.mine, _away);

    expect(
      _play(match, 30.0),
      before,
      reason: 'somebody was still working after the whole crowd was ordered',
    );
  });

  test('and an order to the ones picked out does not', () {
    // The same match, the same click, the same half-minute — the only
    // difference is that one worker was picked out first.
    //
    // Mutation: order `command.mine` here instead of the selection, which is
    // exactly what `main.dart` used to do, and the total stops dead.
    final (:match, :command) = _open();
    final double before = _play(match, 25.0);

    expect(command.select(command.mine.first), isTrue);
    expect(command.orderTo(_away), isTrue);

    expect(
      _play(match, 30.0),
      greaterThan(before),
      reason: 'the workers nobody ordered stopped working',
    );
  });

  test('an empty selection orders nobody at all', () {
    // A click on the ground with nothing picked out is a click that does
    // nothing, and it has to leave the queue alone: an order naming no units is
    // still a line on the tape, and a tape full of them is a recording of a
    // player clicking about.
    final (:match, :command) = _open();

    expect(command.orderTo(_away), isFalse);
    expect(match.simulation.orders.waiting, isEmpty);
  });

  test('the order goes into the queue rather than onto the units', () {
    // Mutation: assign `unit.order` here. The crowd would move and the tape
    // would be empty — a match that cannot be played back, which is the one
    // thing this genre's recording is for. See `OrderQueue`.
    final (:match, :command) = _open();
    final Unit picked = command.mine.first;
    command.select(picked);
    command.orderTo(_away);

    expect(match.simulation.orders.waiting, hasLength(1));
    expect(picked.order.goal, isNull, reason: 'the order was carried out early');

    match.step(1.0 / 30.0);
    expect(picked.order.goal, isNotNull);
    expect(match.simulation.orders.waiting, isEmpty);
  });

  test('a ray picks the worker it points at', () {
    // **The pass could not answer this and never will.** The crowd is one
    // instanced batch, so `pickPixel` says "the crowd" for a cursor over any
    // worker on the map; the ray against each unit's radius is what names one.
    final (:match, :command) = _open();
    final Unit wanted = command.mine[2];
    final ray = _onto(wanted);

    expect(command.selectAt(ray.origin, ray.direction), isTrue);
    expect(command.selected, <Unit>[wanted]);
    expect(match.simulation.units, contains(wanted));
  });

  test("and a click on the other side's worker leaves the squad standing", () {
    // Where an attack order will go. There is none — a unit has no target, no
    // reach and no health, and `orders.dart` says so at length — so the honest
    // answer is to do nothing. What must not happen is the selection being
    // dropped: a click that cannot be obeyed disbanding the squad the player
    // spent a drag gathering is the worse of the two failures.
    final CommandPost command = _open().command;
    final Unit theirs = command.simulation.units.firstWhere(
      (Unit unit) => unit.side != viewerSide,
    );
    command.select(command.mine.first);
    final List<Unit> before = command.selected;

    final ray = _onto(theirs);
    expect(command.selectAt(ray.origin, ray.direction), isFalse);
    expect(command.selected, before);
  });

  test('a rectangle takes this side and leaves the other', () {
    // The whole map, so that what is being measured is the side filter rather
    // than the geometry — `Selection.unitsWithin` has its own tests for that.
    final CommandPost command = _open().command;

    final int took = command.selectWithin(
      Vector3(-1000.0, 0.0, -1000.0),
      Vector3(1000.0, 0.0, 1000.0),
    );

    expect(took, command.mine.length);
    expect(
      command.selected.every((Unit unit) => unit.side == viewerSide),
      isTrue,
      reason: "the rectangle took the other side's crowd as well",
    );
  });

  test('and only who stands inside it', () {
    final CommandPost command = _open().command;
    final Unit wanted = command.mine.first;

    // Half a metre round one worker. The document stands its crowd a metre and
    // a half apart, so this reaches nobody else.
    final int took = command.selectWithin(
      Vector3(wanted.position.x - 0.5, 0.0, wanted.position.z - 0.5),
      Vector3(wanted.position.x + 0.5, 0.0, wanted.position.z + 0.5),
    );

    expect(took, 1);
    expect(command.selected.single, wanted);
  });

  test('a worker a hall built can be ordered like any other', () {
    // **The opening crowd cannot say this.** `StrategyStart.mine` is filled
    // once, when the document is read, so a worker built during the match was
    // never in it — the click that used to move "everybody" could not move a
    // single unit this side had paid for.
    final (:match, :command) = _open();
    final int opened = command.mine.length;

    _play(match, 40.0);
    expect(
      command.mine.length,
      greaterThan(opened),
      reason: 'no hall built anybody in forty seconds',
    );

    final Unit built = command.mine.last;
    final ray = _onto(built);
    expect(command.selectAt(ray.origin, ray.direction), isTrue);
    expect(command.selected.single, built);
  });

  test('and a worker that leaves the map leaves the selection', () {
    // Nothing takes a unit off the map today — there is no fight — so this
    // takes one off by hand. The property is what matters: a selection that
    // held a unit the world had forgotten would keep counting it on the HUD and
    // keep naming it in orders, and `MoveOrder` drops names it cannot find, so
    // the symptom would be a squad that is smaller than the number on screen.
    final CommandPost command = _open().command;
    command.selectWithin(
      Vector3(-1000.0, 0.0, -1000.0),
      Vector3(1000.0, 0.0, 1000.0),
    );
    final int gathered = command.count;
    expect(gathered, greaterThan(1));

    command.simulation.units.remove(command.selected.first);
    command.prune();

    expect(command.count, gathered - 1);
  });
}
