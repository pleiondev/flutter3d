/// Rules a game adds to a step a genre package owns.
///
///     flutter test test/step_systems_test.dart
///
/// **The plugin boundary for behaviour, and the last of three.** Reading a model
/// has `ModelDecoder`, reading a material has `MaterialDecoder`, and this is the
/// one for the simulation itself.
///
/// Almost everything here is about **order**, and that is not fastidiousness: a
/// step reaches for no clock and no loose dice (ARCHITECTURE.md §9.3), and an `InputTape`
/// replays a run exactly because of it. A system is part of the step, so a
/// registry that ran its systems in whatever order a hash map handed back would
/// undo the property the tape rests on — and would do it intermittently, which
/// is the worst way for it to be undone.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const StepPhase _afterActors = StepPhase('afterActors');

void main() {
  test('a system runs when its phase is announced, and only then', () {
    // The premise. Mutation: run every phase's systems on any announcement —
    // the second expectation fails.
    final systems = StepSystems();
    final ran = <String>[];
    systems.add(StepPhase.begin, (_) => ran.add('begin'));
    systems.add(_afterActors, (_) => ran.add('actors'));

    systems.run(StepPhase.begin, 1 / 60);
    expect(ran, <String>['begin']);

    systems.run(_afterActors, 1 / 60);
    expect(ran, <String>['begin', 'actors']);
  });

  test('and a phase nobody registered for costs nothing to announce', () {
    // A genre announces its phases unconditionally — that is what makes them
    // something to rely on — so the empty case is the common one.
    final systems = StepSystems();
    expect(systems.isEmpty, isTrue);
    expect(() => systems.run(StepPhase.end, 1 / 60), returnsNormally);
  });

  test('and is handed the step, not a wall clock', () {
    // Mutation: pass anything else — fails here. The signature is the whole
    // guard: a system that wanted elapsed real time would have to fetch it
    // itself, and the scan "a step reaches for no clock and no loose dice" in
    // `tool/structure.dart` names the file when it does.
    final systems = StepSystems();
    var seen = 0.0;
    systems.add(StepPhase.begin, (dt) => seen = dt);

    systems.run(StepPhase.begin, 1 / 60);
    expect(seen, 1 / 60);
  });

  group('the order systems run in', () {
    test('is registration, when nobody asked for anything else', () {
      // Mutation: iterate `_byPhase` values without keeping insertion order, or
      // sort by `label` — fails here. Dart does not promise a hash map hands
      // back the same order from one run to the next, so "it worked" is not
      // evidence.
      final systems = StepSystems();
      final ran = <String>[];
      for (final name in <String>['a', 'b', 'c', 'd']) {
        systems.add(StepPhase.begin, (_) => ran.add(name));
      }

      systems.run(StepPhase.begin, 1 / 60);
      expect(ran, <String>['a', 'b', 'c', 'd']);
    });

    test('and order wins over registration', () {
      // **Why `order` exists at all.** A rule that must observe what every other
      // rule did cannot be registered after code it does not know about — the
      // level that adds it does not own the list. Mutation: ignore `order` —
      // fails here.
      final systems = StepSystems();
      final ran = <String>[];
      systems.add(StepPhase.begin, (_) => ran.add('late'), order: 10);
      systems.add(StepPhase.begin, (_) => ran.add('early'), order: -10);
      systems.add(StepPhase.begin, (_) => ran.add('middle'));

      systems.run(StepPhase.begin, 1 / 60);
      expect(ran, <String>['early', 'middle', 'late']);
    });

    test('and ties keep registration order, which is what makes it stable', () {
      // Mutation: break ties by `order` alone and let the insert land anywhere
      // among equals — the run order stops being a function of the code and
      // this fails. `forPhase` is checked too, because a diagnostic overlay that
      // reported a different order than the one that runs would be worse than
      // none.
      final systems = StepSystems();
      final ran = <String>[];
      systems.add(StepPhase.begin, (_) => ran.add('a'), order: 5, label: 'a');
      systems.add(StepPhase.begin, (_) => ran.add('b'), order: 1, label: 'b');
      systems.add(StepPhase.begin, (_) => ran.add('c'), order: 5, label: 'c');
      systems.add(StepPhase.begin, (_) => ran.add('d'), order: 1, label: 'd');

      systems.run(StepPhase.begin, 1 / 60);
      expect(ran, <String>['b', 'd', 'a', 'c']);
      expect(
        <String?>[
          for (final one in systems.forPhase(StepPhase.begin)) one.label,
        ],
        <String>['b', 'd', 'a', 'c'],
      );
    });
  });

  group('a system that changes the list it is in', () {
    test('does not disturb the step it is running in', () {
      // **A rule that fires once and unregisters itself is the ordinary case**,
      // not an exotic one: a trap that springs, a scripted event, a tutorial
      // hint. Mutation: iterate the live list — this throws
      // ConcurrentModificationError instead of failing an expectation, which is
      // exactly the crash the copy prevents.
      final systems = StepSystems();
      final ran = <String>[];
      late SystemRegistration once;
      once = systems.add(StepPhase.begin, (_) {
        ran.add('once');
        systems.remove(once);
      });
      systems.add(StepPhase.begin, (_) => ran.add('always'));

      systems.run(StepPhase.begin, 1 / 60);
      systems.run(StepPhase.begin, 1 / 60);

      expect(ran, <String>['once', 'always', 'always']);
    });

    test('and one added mid-step waits for the next one', () {
      // The other half, and the one that is a choice rather than a consequence:
      // a system added while the phase is running is not run again this step. A
      // rule that spawns a rule that spawns a rule would otherwise be an
      // infinite step rather than a bug somebody can see.
      final systems = StepSystems();
      final ran = <String>[];
      systems.add(StepPhase.begin, (_) {
        ran.add('parent');
        systems.add(StepPhase.begin, (_) => ran.add('child'));
      });

      systems.run(StepPhase.begin, 1 / 60);
      expect(ran, <String>['parent']);

      ran.clear();
      systems.run(StepPhase.begin, 1 / 60);
      expect(ran, <String>['parent', 'child']);
    });

    test('and removing one twice is not an error', () {
      // A level torn down twice should not be a crash.
      final systems = StepSystems();
      final registration = systems.add(StepPhase.begin, (_) {});
      systems.remove(registration);
      expect(() => systems.remove(registration), returnsNormally);
    });
  });

  group('a phase is its name', () {
    test('so a genre can invent one, and two of them need not be one object',
        () {
      // **Why `StepPhase` wraps a string** — the same reason `GameAction` does.
      // "After the weapons fired" is a sentence about one genre; an enum here
      // would mean editing this package the day a genre wanted its own phase.
      //
      // Built at run time on purpose. Two identical `const StepPhase(…)`
      // expressions are the *same object* — Dart canonicalises them — so a
      // registry keyed on identity would pass a test written with constants and
      // fail on a phase read out of a level file.
      //
      // Mutation: key `_byPhase` on the `StepPhase` and compare by identity —
      // fails here, and would not have with constants.
      final spelling = <String>['unfold', 'The', 'Chair'];
      final systems = StepSystems();
      var ran = false;
      systems.add(StepPhase(spelling.join()), (_) => ran = true);

      systems.run(StepPhase(spelling.join()), 1 / 60);
      expect(ran, isTrue);
    });

    test('and two phases of the same name are equal', () {
      // Not used by the registry — it keys on the name — but a game comparing
      // phases is entitled to the obvious answer.
      //
      // Mutation: compare by identity — fails here.
      final spelled = StepPhase(<String>['after', 'Actors'].join());
      expect(spelled, _afterActors);
      expect(spelled.hashCode, _afterActors.hashCode);
      expect(StepPhase.begin, isNot(StepPhase.end));
    });
  });
}
