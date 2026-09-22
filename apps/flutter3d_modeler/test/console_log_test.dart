/// `ux-26`'s own log, and the hints that go beside it in the strip.
///
///     flutter test test/console_log_test.dart
///
/// Both halves are values with no Flutter in them, which is the point: what
/// ten commands leave behind, and what the three buttons mean, are questions
/// a test can ask without a window.
library;

import 'package:flutter3d_modeler/src/console_log.dart';
import 'package:flutter3d_modeler/src/mouse_hints.dart';
import 'package:flutter3d_modeler/src/settings.dart' show NavigationScheme;
import 'package:flutter_test/flutter_test.dart';

/// A clock that ticks one second per call, so an order can be asserted
/// rather than raced.
DateTime Function() _clock() {
  var at = DateTime.utc(2026, 9, 16, 14);
  return () => at = at.add(const Duration(seconds: 1));
}

void main() {
  group('ux-26: what a session leaves behind', () {
    test('ten things said are ten entries, in order', () {
      final ConsoleLog log = ConsoleLog();
      final DateTime Function() clock = _clock();
      for (var each = 0; each < 10; each++) {
        log.add(
          ConsoleEntry(
            at: clock(),
            text: 'command $each',
            author: ConsoleAuthor.person,
          ),
        );
      }

      // The acceptance this row states.
      expect(log.length, 10);
      expect(log.entries.first.text, 'command 0');
      expect(log.entries.last.text, 'command 9');
    });

    test('and a refusal is marked as one', () {
      final ConsoleLog log = ConsoleLog();
      final DateTime Function() clock = _clock();
      log.add(
        ConsoleEntry(
          at: clock(),
          text: 'extruded',
          author: ConsoleAuthor.person,
        ),
      );
      log.add(
        ConsoleEntry(
          at: clock(),
          text: 'nothing is selected to extrude',
          author: ConsoleAuthor.person,
          kind: ConsoleKind.refusal,
        ),
      );

      // Mutation: keep the sentence and drop the level. The console is then
      // a wall of identical grey lines, which is what the status line was
      // before `ux-17` and for the same reason nobody read it.
      expect(log.entries.last.kind, ConsoleKind.refusal);
      expect(log.entries.first.kind, ConsoleKind.report);
    });

    test('the oldest go when the log is full', () {
      final ConsoleLog log = ConsoleLog(limit: 3);
      final DateTime Function() clock = _clock();
      for (final String each in <String>['a', 'b', 'c', 'd', 'e']) {
        log.add(
          ConsoleEntry(at: clock(), text: each, author: ConsoleAuthor.person),
        );
      }

      // Mutation: let it grow. A session left open all day keeps every
      // sentence a drag produced, and `get_console` answers with a
      // transcript instead of a log.
      expect(log.length, 3);
      expect(log.entries.map((ConsoleEntry it) => it.text), <String>[
        'c',
        'd',
        'e',
      ]);
    });
  });

  group('ux-26: reading it back', () {
    ConsoleLog filled() {
      final ConsoleLog log = ConsoleLog();
      final DateTime Function() clock = _clock();
      log.add(
        ConsoleEntry(at: clock(), text: 'opened', author: ConsoleAuthor.person),
      );
      log.add(
        ConsoleEntry(
          at: clock(),
          text: 'added a box',
          author: ConsoleAuthor.agent,
          tool: 'addPrimitive',
        ),
      );
      log.add(
        ConsoleEntry(at: clock(), text: 'saved', author: ConsoleAuthor.person),
      );
      return log;
    }

    test(
      'since answers with what happened after a stamp, not including it',
      () {
        final ConsoleLog log = filled();
        final DateTime second = log.entries[1].at;

        // Mutation: use `!isBefore` rather than `isAfter`. An agent polling
        // with the `at` of the last entry it saw gets that entry again on
        // every call, for ever.
        expect(log.since(second).map((ConsoleEntry it) => it.text), <String>[
          'saved',
        ]);
        expect(log.since(null), hasLength(3));
      },
    );

    test('and the filter is who said it', () {
      final ConsoleLog log = filled();

      expect(log.by(ConsoleAuthor.agent), hasLength(1));
      expect(log.by(ConsoleAuthor.person), hasLength(2));
      expect(log.by(null), hasLength(3));
    });

    test('an entry carries the tool that caused it', () {
      final ConsoleLog log = filled();
      final Map<String, Object?> json = log.entries[1].toJson();

      expect(json['author'], 'agent');
      expect(json['tool'], 'addPrimitive');
      expect(json['text'], 'added a box');
      // Reports carry no `kind` noise for a reader — they carry the name
      // anyway, because an agent parsing this should not have to know which
      // value is the default.
      expect(json['kind'], 'report');
      // Absent rather than null where there is no tool: an agent reading
      // this should not have to tell "no tool" from "a tool called null".
      expect(log.entries.first.toJson().containsKey('tool'), isFalse);
    });
  });

  group('ux-26: what the three buttons do', () {
    test('with nothing armed, under each scheme', () {
      final MouseHints middle = mouseHintsFor(
        scheme: NavigationScheme.middleMouseOrbit,
      );
      final MouseHints left = mouseHintsFor(
        scheme: NavigationScheme.leftDragOrbit,
      );

      // Mutation: write one set of hints for both schemes. Half the people
      // using this application are then told that the middle button orbits
      // when a left drag does, which is worse than saying nothing.
      expect(middle.right, 'Menu');
      expect(left.right, 'Hold to look');
      expect(middle.left, contains('boxes'));
      expect(left.left, contains('orbits'));
    });

    test('and they change when a tool is armed', () {
      const NavigationScheme scheme = NavigationScheme.middleMouseOrbit;
      final MouseHints idle = mouseHintsFor(scheme: scheme);
      final MouseHints moving = mouseHintsFor(
        scheme: scheme,
        tool: 'mesh.move',
      );

      // The acceptance this row states.
      expect(moving.left, isNot(idle.left));
      expect(moving.left, contains('transform'));
    });

    test('the lasso says so, since it is a drag that is not a box', () {
      expect(
        mouseHintsFor(
          scheme: NavigationScheme.middleMouseOrbit,
          tool: 'mesh.lasso',
        ).left,
        'Lasso',
      );
    });

    test('and a free-look answers for all three while it is held', () {
      final MouseHints looking = mouseHintsFor(
        scheme: NavigationScheme.leftDragOrbit,
        tool: 'mesh.move',
        lookingAround: true,
      );

      // Mutation: leave the armed tool's hint standing. The strip then says
      // "drag to transform" while the left button is doing nothing of the
      // sort, at the one moment somebody is most likely to look at it.
      expect(looking.left, 'Look');
      expect(looking.right, contains('WASD'));
    });

    test('the line reads as one sentence', () {
      expect(
        mouseHintLine((left: 'Select', middle: 'Orbit', right: 'Menu')),
        'L Select · M Orbit · R Menu',
      );
    });
  });
}
