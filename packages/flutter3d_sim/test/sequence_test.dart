/// Cutscenes: read from a document, played in the fixed step.
///
///     dart test test/sequence_test.dart
///
/// What a cutscene has to be to belong in a simulation that replays and
/// rewinds: its moments fall on whole steps, its signals fire once each on
/// their step, a restore carries on without firing anything twice, and a
/// skip — the rest of it stepped without drawing — ends where watching it
/// ends.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _rate = 60;

const Map<String, Object?> _scene = <String, Object?>{
  'seconds': 4,
  'camera': <String, Object?>{
    'keys': <Object?>[
      <String, Object?>{
        't': 0,
        'at': <double>[0, 2, 10],
        'look': <double>[0, 1, 0],
      },
      <String, Object?>{
        't': 2,
        'at': <double>[10, 2, 0],
        'look': <double>[0, 1, 0],
        'fov': 40,
      },
      <String, Object?>{
        't': 4,
        'at': <double>[0, 2, -10],
        'look': <double>[0, 1, 0],
        'fov': 40,
      },
    ],
  },
  'subtitles': <Object?>[
    <String, Object?>{'from': 0.5, 'to': 2, 'text': 'Who goes there?'},
    <String, Object?>{'from': 1.5, 'to': 3, 'text': 'Nobody.'},
  ],
  'fade': <Object?>[
    <String, Object?>{'t': 0, 'value': 1},
    <String, Object?>{'t': 1, 'value': 0},
  ],
  'signals': <Object?>[
    <String, Object?>{
      't': 2,
      'name': 'door',
      'data': <String, Object?>{'open': true},
    },
    <String, Object?>{'t': 0, 'name': 'music'},
    <String, Object?>{'t': 2, 'name': 'creak'},
    <String, Object?>{'t': 4, 'name': 'end'},
  ],
};

Sequence _read([Map<String, Object?> json = _scene]) {
  final read = Sequence.read(json, stepsPerSecond: _rate);
  expect(read.problems, isEmpty);
  return read.sequence!;
}

/// The signals [player] fires playing to its end, with the step each fired
/// on.
List<String> _playOut(SequencePlayer player, GameEvents events) {
  final fired = <String>[];
  while (!player.finished) {
    player.advance();
    fired.addAll(<String>[
      for (final event in events.drain()) '${player.step}:${event.name}',
    ]);
  }
  return fired;
}

void main() {
  group('reading', () {
    test('turns every moment into the step it falls on', () {
      final sequence = _read();
      expect(sequence.steps, 240);
      expect(sequence.cameraKeys.map((k) => k.step), <int>[0, 120, 240]);
      expect(sequence.subtitles.first.from, 30);
      // In step order, and in the document's order on one step.
      expect(sequence.signals.map((s) => '${s.step}:${s.name}'), <String>[
        '0:music',
        '120:door',
        '120:creak',
        '240:end',
      ]);
    });

    test('refuses a document with every problem and where it is', () {
      final read = Sequence.read(<String, Object?>{
        'seconds': 2,
        'camera': <String, Object?>{
          'keys': <Object?>[
            <String, Object?>{
              't': 1,
              'at': <double>[0, 0, 0],
              'look': <double>[0, 0, 1],
            },
            <String, Object?>{
              't': 0.5,
              'at': <double>[0, 0, 0],
              'look': <double>[0, 0, 1],
            },
          ],
        },
        'subtitles': <Object?>[
          <String, Object?>{'from': 1, 'to': 0.5, 'text': 'backwards'},
        ],
        'fade': <Object?>[
          <String, Object?>{'t': 0, 'value': 2},
        ],
        'signals': <Object?>[
          'loose',
          <String, Object?>{'t': 3, 'name': 'late'},
          <String, Object?>{'t': 1},
        ],
      }, stepsPerSecond: _rate);
      expect(read.sequence, isNull);
      expect(read.problems, <Matcher>[
        contains('camera.keys[1].t'),
        contains('subtitles[0].to'),
        contains('fade[0].value'),
        contains('signals[0]'),
        contains('signals[1].t'),
        contains('signals[2].name'),
      ]);
    });
  });

  test('an actor\'s cue says what and, where it walks or looks, where', () {
    final read = Sequence.read(<String, Object?>{
      'seconds': 2,
      'actors': <Object?>[
        <String, Object?>{'t': 0, 'actor': 'guard', 'do': 'dance'},
        <String, Object?>{'t': 0, 'actor': 'guard', 'do': 'goTo'},
        <String, Object?>{'t': 1, 'do': 'stand'},
      ],
    }, stepsPerSecond: _rate);
    expect(read.problems, <Matcher>[
      allOf(contains('actors[0].do'), contains('goTo, face, stand, release')),
      contains('actors[1].at'),
      contains('actors[2].actor'),
    ]);
    final cued = _read(<String, Object?>{
      'seconds': 2,
      'actors': <Object?>[
        <String, Object?>{'t': 1, 'actor': 'guard', 'do': 'release'},
        <String, Object?>{'t': 0, 'actor': 'guard', 'do': 'stand'},
      ],
    });
    // In step order whatever the document's: the stand, then the release.
    expect(cued.cueFor('guard', 30)!.kind, ActorCueKind.stand);
    expect(cued.cueFor('guard', 60)!.kind, ActorCueKind.release);
    expect(cued.cueFor('cook', 60), isNull);
  });

  group('playing', () {
    test('fires every signal once, on the step its moment falls on', () {
      final events = GameEvents();
      final player = SequencePlayer(_read(), events: events);
      // Mutation: firing on `<` the step rather than `<=` puts each a step
      // late, and the last one never.
      expect(_playOut(player, events), <String>[
        '1:music',
        '120:door',
        '120:creak',
        '240:end',
      ]);
      expect(player.finished, isTrue);
      player.advance();
      expect(events.isEmpty, isTrue, reason: 'nothing after the end');
    });

    test('a restore carries on without firing anything twice', () {
      final events = GameEvents();
      final first = SequencePlayer(_read(), events: events);
      for (var i = 0; i < 120; i++) {
        first.advance();
      }
      events.drain();
      final saved = first.save();

      final again = GameEvents();
      final restored = SequencePlayer(_read(), events: again)..restore(saved);
      // Mutation: restoring the step and not which signals it has passed
      // fires the music and the door again.
      expect(_playOut(restored, again), <String>['240:end']);
    });

    test('a skip, the rest stepped undrawn, ends where watching ends', () {
      List<String> run({required bool skip}) {
        final events = GameEvents();
        final player = SequencePlayer(_read(), events: events);
        final fired = <String>[];
        for (var i = 0; i < 50; i++) {
          player.advance();
          fired.addAll(events.drain().map((e) => e.name));
        }
        if (skip) {
          for (var left = player.remaining; left > 0; left--) {
            player.advance();
          }
          fired.addAll(events.drain().map((e) => e.name));
        } else {
          fired.addAll(_playOut(player, events).map((e) => e.split(':')[1]));
        }
        return <String>[...fired, '${player.save()}'];
      }

      expect(run(skip: true), run(skip: false));
    });
  });

  group('the picture', () {
    late final Sequence sequence;
    setUpAll(() => sequence = _read());
    final at = Vector3.zero();
    final look = Vector3.zero();

    test('the camera is on each key on its step', () {
      for (final key in sequence.cameraKeys) {
        final fov = sequence.cameraAt(key.step.toDouble(), at, look);
        expect(at.distanceTo(key.at), lessThan(1e-9));
        expect(look.distanceTo(key.look), lessThan(1e-9));
        expect(fov, key.fov);
      }
    });

    test('between two keys it goes round the curve, not across', () {
      // Halfway from (0, 10) to (10, 0), the chord passes 7.07 from the
      // middle; the curve through the three keys bows out past it, to 7.96.
      // Mutation: moving the camera in a straight line between keys.
      final fov = sequence.cameraAt(60, at, look);
      expect(at.x, greaterThan(5.0));
      expect(at.z, greaterThan(5.0));
      expect(Vector2(at.x, at.z).length, greaterThan(7.5));
      // Mutation: interpolating the field of view by the next key's step
      // rather than the fraction between the two.
      expect(fov, closeTo(50.0, 1e-9));
    });

    test('the subtitles read the one that started last', () {
      expect(sequence.subtitleAt(10), isNull);
      expect(sequence.subtitleAt(60), 'Who goes there?');
      expect(sequence.subtitleAt(100), 'Nobody.');
      expect(sequence.subtitleAt(179), 'Nobody.');
      expect(sequence.subtitleAt(180), isNull);
      // Listed the other way round: still the one that started last.
      // Mutation: taking the last listed of those showing.
      final listed = _read(<String, Object?>{
        'seconds': 4,
        'subtitles': <Object?>[
          <String, Object?>{'from': 1.5, 'to': 3, 'text': 'Nobody.'},
          <String, Object?>{'from': 0.5, 'to': 2, 'text': 'Who goes there?'},
        ],
      });
      expect(listed.subtitleAt(100), 'Nobody.');
    });

    test('the fade runs between its keys and holds after', () {
      expect(sequence.fadeAt(0), 1.0);
      expect(sequence.fadeAt(30), closeTo(0.5, 1e-9));
      expect(sequence.fadeAt(200), 0.0);
    });

    test('a frame between two steps is drawn between them', () {
      final player = SequencePlayer(sequence)..advance();
      // Mutation: drawing the step the player reached rather than the
      // stretch of time behind it puts every frame a step ahead.
      expect(player.fade(alpha: 0.0), 1.0);
      expect(player.fade(alpha: 1.0), closeTo(1.0 - 1 / 60, 1e-9));
    });
  });
}
