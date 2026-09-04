import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> document({
  Object? points,
  Map<String, Object?> extra = const <String, Object?>{},
  Map<String, Object?>? level,
}) => <String, Object?>{
  'track': <String, Object?>{
    'points':
        points ??
        <Map<String, Object?>>[
          <String, Object?>{
            'at': <double>[60.0, 0.0, 0.0],
          },
          <String, Object?>{
            'at': <double>[0.0, 0.0, 60.0],
          },
          <String, Object?>{
            'at': <double>[-60.0, 0.0, 0.0],
          },
          <String, Object?>{
            'at': <double>[0.0, 0.0, -60.0],
          },
        ],
    ...extra,
  },
  'level': ?level,
};

/// Through a real encode and decode, because that is the only way the reader is
/// ever actually called and `1` decoded from text is an `int` where `1.0` is a
/// `double`.
TrackDocument read(Map<String, Object?> json) => TrackDocument.fromJson(
  jsonDecode(jsonEncode(json)) as Map<String, Object?>,
);

void main() {
  test('a circuit with nothing but points is a working circuit', () {
    final track = read(document()).track;

    expect(track.length, greaterThan(300.0));
    expect(track.widthAt(0.0), 12.0);
    expect(track.bankAt(0.0), 0.0);
    expect(track.checkpoints, isEmpty);
  });

  test('camber is authored in degrees and read in radians', () {
    // Mutation: take the number as radians. Nine degrees of camber would become
    // nine radians — a corner tilted round one and a half times — and the only
    // symptom at load time is a track that looks wrong.
    final track = read(
      document(
        points: <Map<String, Object?>>[
          for (final angle in <double>[0.0, 90.0, 180.0, 270.0])
            <String, Object?>{
              'at': <double>[
                60 * math.cos(angle * math.pi / 180),
                0.0,
                60 * math.sin(angle * math.pi / 180),
              ],
              'bank': 9.0,
            },
        ],
      ),
    ).track;

    expect(track.bankAt(10.0), closeTo(9.0 * math.pi / 180, 1e-9));
  });

  test('an open track is refused rather than half-supported', () {
    // Point to point is a different lap counter, a different grid and a
    // different meaning for "position". Refusing now costs a line; finding out
    // later costs a circuit that loads and counts laps that cannot happen.
    expect(
      () => read(document(extra: <String, Object?>{'closed': false})),
      throwsA(isA<LevelFormatException>()),
    );
  });

  test('a document with no track at all is refused', () {
    expect(
      () => TrackDocument.fromJson(<String, Object?>{}),
      throwsA(isA<LevelFormatException>()),
    );
  });

  test('two points cannot make a circuit', () {
    expect(
      () => read(
        document(
          points: <Map<String, Object?>>[
            <String, Object?>{
              'at': <double>[0.0, 0.0, 0.0],
            },
            <String, Object?>{
              'at': <double>[10.0, 0.0, 0.0],
            },
          ],
        ),
      ),
      throwsA(isA<LevelFormatException>()),
    );
  });

  test('surfaces, barriers and checkpoints come through as authored', () {
    final track = read(
      document(
        extra: <String, Object?>{
          'shoulder': 6.0,
          'surfaces': <Map<String, Object?>>[
            <String, Object?>{
              'fromS': 0.0,
              'toS': 1000.0,
              'centre': 'asphalt',
              'shoulder': 'gravel',
            },
          ],
          'barriers': <Map<String, Object?>>[
            <String, Object?>{'fromS': 0.0, 'toS': 50.0, 'right': true},
          ],
          'checkpoints': <Map<String, Object?>>[
            <String, Object?>{'s': 90.0},
            <String, Object?>{'s': 180.0},
          ],
        },
      ),
    ).track;

    expect(track.shoulder, 6.0);
    expect(track.surfaceAt(20.0, 0.0), 'asphalt');
    expect(track.surfaceAt(20.0, 8.0), 'gravel');
    expect(track.barrierAt(20.0, left: false), isTrue);
    expect(track.barrierAt(20.0, left: true), isFalse);
    expect(track.checkpoints, <double>[90.0, 180.0]);
  });

  test('the grid is read, and a grid with no columns is refused', () {
    final track = read(
      document(
        extra: <String, Object?>{
          'grid': <String, Object?>{
            's': -20.0,
            'columns': 3,
            'rowGap': 7.0,
            'columnGap': 4.0,
          },
        },
      ),
    ).track;

    expect(track.grid.s, -20.0);
    expect(track.grid.columns, 3);
    expect(track.grid.rowGap, 7.0);
    expect(track.grid.columnGap, 4.0);

    expect(
      () => read(
        document(
          extra: <String, Object?>{
            'grid': <String, Object?>{'columns': 0},
          },
        ),
      ),
      throwsA(isA<LevelFormatException>()),
    );
  });

  test('the level beside the circuit is read by the engine that owns it', () {
    // The two halves of a track file are validated by different things on
    // purpose: brushes, materials and entities have been the engine's business
    // since the first game, and duplicating that here would mean a second
    // opinion about what a level is.
    final document = read(<String, Object?>{
      'track': <String, Object?>{
        'points': <Map<String, Object?>>[
          <String, Object?>{
            'at': <double>[60.0, 0.0, 0.0],
          },
          <String, Object?>{
            'at': <double>[0.0, 0.0, 60.0],
          },
          <String, Object?>{
            'at': <double>[-60.0, 0.0, 0.0],
          },
        ],
      },
      'level': <String, Object?>{
        'name': 'ring',
        'brushes': <Map<String, Object?>>[
          <String, Object?>{
            'at': <double>[0.0, -1.0, 0.0],
            'size': <double>[200.0, 2.0, 200.0],
          },
        ],
      },
    });

    expect(document.level, isNotNull);
    expect(document.level!.brushes, hasLength(1));
  });

  test('a circuit with no level is a circuit, not an error', () {
    // Every vehicle test builds one of these: a road and nothing else.
    expect(read(document()).level, isNull);
  });

  group('the format version', () {
    // **The generator has stamped one since the format existed and nothing
    // ever read it.** Every shipped track file carries `"version": 1`; this
    // reader took the number, ignored it, and would have read a version two
    // file as far as it could and then drawn whatever came out.

    test('a newer document is refused by both numbers', () {
      expect(
        () => read(<String, Object?>{
          ...document(),
          'version': TrackDocument.formatVersion + 1,
        }),
        throwsA(
          isA<LevelFormatException>().having(
            (LevelFormatException e) => e.toString(),
            'says which version it got and which it reads',
            allOf(
              contains('${TrackDocument.formatVersion + 1}'),
              contains('${TrackDocument.formatVersion}'),
            ),
          ),
        ),
      );
    });

    test('this version reads', () {
      final doc = read(<String, Object?>{
        ...document(),
        'version': TrackDocument.formatVersion,
      });
      expect(doc.track.length, greaterThan(300.0));
    });

    test('and a document with no version at all still reads', () {
      // Which is what every track written before the gate existed looks like
      // to this reader, and refusing them would be refusing our own files.
      final plain = document()..remove('version');
      expect(read(plain).track.length, greaterThan(300.0));
    });
  });
}
