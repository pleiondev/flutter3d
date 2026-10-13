/// A cutscene's picture: the camera's pose, the fade and the subtitle read
/// off a sequence's keys for a frame.
///
///     dart test test/sequence_view_test.dart
///
/// The camera is on each key on its step and goes round the curve between
/// them, the subtitles read the one that started last, and a frame between
/// two steps of the player is drawn between them.
library;

import 'package:flutter3d_camera/flutter3d_camera.dart';
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
};

Sequence _read([Map<String, Object?> json = _scene]) {
  final read = Sequence.read(json, stepsPerSecond: _rate);
  expect(read.problems, isEmpty);
  return read.sequence!;
}

void main() {
  late final SequenceView view;
  setUpAll(() => view = SequenceView(_read()));
  final at = Vector3.zero();
  final look = Vector3.zero();

  test('the camera is on each key on its step', () {
    for (final key in view.sequence.cameraKeys) {
      final fovY = view.cameraAt(key.step.toDouble(), at, look);
      expect(at.distanceTo(key.at), lessThan(1e-9));
      expect(look.distanceTo(key.look), lessThan(1e-9));
      expect(fovY, key.fovY);
    }
  });

  test('between two keys it goes round the curve, not across', () {
    // Halfway from (0, 10) to (10, 0), the chord passes 7.07 from the
    // middle; the curve through the three keys bows out past it, to 7.96.
    // Mutation: moving the camera in a straight line between keys.
    final fovY = view.cameraAt(60, at, look);
    expect(at.x, greaterThan(5.0));
    expect(at.z, greaterThan(5.0));
    expect(Vector2(at.x, at.z).length, greaterThan(7.5));
    // Mutation: interpolating the field of view by the next key's step
    // rather than the fraction between the two. The file says 42.5 degrees
    // halfway; the reader hands the engine radians.
    expect(fovY, closeTo(radians(42.5), 1e-9));
  });

  test('the subtitles read the one that started last', () {
    expect(view.subtitleAt(10), isNull);
    expect(view.subtitleAt(60), 'Who goes there?');
    expect(view.subtitleAt(100), 'Nobody.');
    expect(view.subtitleAt(179), 'Nobody.');
    expect(view.subtitleAt(180), isNull);
    // Listed the other way round: still the one that started last.
    // Mutation: taking the last listed of those showing.
    final listed = SequenceView(
      _read(<String, Object?>{
        'seconds': 4,
        'subtitles': <Object?>[
          <String, Object?>{'from': 1.5, 'to': 3, 'text': 'Nobody.'},
          <String, Object?>{'from': 0.5, 'to': 2, 'text': 'Who goes there?'},
        ],
      }),
    );
    expect(listed.subtitleAt(100), 'Nobody.');
  });

  test('the fade runs between its keys and holds after', () {
    expect(view.fadeAt(0), 1.0);
    expect(view.fadeAt(30), closeTo(0.5, 1e-9));
    expect(view.fadeAt(200), 0.0);
  });

  test('a frame between two steps is drawn between them', () {
    final player = SequencePlayer(view.sequence)..advance();
    // Mutation: drawing the step the player reached rather than the
    // stretch of time behind it puts every frame a step ahead.
    expect(view.fadeOf(player, alpha: 0.0), 1.0);
    expect(view.fadeOf(player, alpha: 1.0), closeTo(1.0 - 1 / 60, 1e-9));
    expect(
      view.cameraOf(player, at, look, alpha: 0.0),
      view.sequence.cameraKeys.first.fovY,
    );
    expect(view.subtitleOf(player), isNull);
  });

  test('a cutscene with no camera leaves the camera to the game', () {
    final quiet = SequenceView(_read(<String, Object?>{'seconds': 1}));
    final player = SequencePlayer(quiet.sequence)..advance();
    expect(quiet.cameraOf(player, at, look), isNull);
    expect(() => quiet.cameraAt(0, at, look), throwsStateError);
    expect(quiet.fadeOf(player), 0.0);
  });
}
