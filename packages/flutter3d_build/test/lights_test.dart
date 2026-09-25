/// `dart run flutter3d_build:lights --optimize`: the light optimizer from a
/// command line, around the core the editor calls.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_build/src/lights.dart';
import 'package:test/test.dart';

/// A closed room with three lamps hanging in one place and a spawn in a
/// corner looking in.
Map<String, Object?> _room() {
  Map<String, Object?> box(List<double> at, List<double> size) =>
      <String, Object?>{'at': at, 'size': size, 'material': 'stone'};
  final lamp = <String, Object?>{
    'type': 'point',
    'at': <double>[0.0, 2.2, 0.0],
    'intensity': 2.0,
    'range': 8.0,
  };
  return <String, Object?>{
    'version': 1,
    'materials': <String, Object?>{
      'stone': <String, Object?>{
        'baseColor': <double>[0.6, 0.6, 0.6, 1.0],
      },
    },
    'brushes': <Object?>[
      box(<double>[0.0, -0.25, 0.0], <double>[5.0, 0.5, 5.0]),
      box(<double>[0.0, 2.75, 0.0], <double>[5.0, 0.5, 5.0]),
      box(<double>[-2.25, 1.25, 0.0], <double>[0.5, 2.5, 4.0]),
      box(<double>[2.25, 1.25, 0.0], <double>[0.5, 2.5, 4.0]),
      box(<double>[0.0, 1.25, -2.25], <double>[4.0, 2.5, 0.5]),
      box(<double>[0.0, 1.25, 2.25], <double>[4.0, 2.5, 0.5]),
    ],
    'lights': <Object?>[lamp, lamp, lamp],
    'entities': <Object?>[
      <String, Object?>{
        'type': 'player_spawn',
        'at': <double>[1.5, 0.0, 1.5],
        'yaw': 0.785,
      },
    ],
  };
}

void main() {
  late Directory scratch;
  late String level;
  setUp(() {
    scratch = Directory.systemTemp.createTempSync('lights_test');
    level = '${scratch.path}/room.json';
    File(level).writeAsStringSync(jsonEncode(_room()));
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  int lightsIn(String path) =>
      ((jsonDecode(File(path).readAsStringSync()) as Map)['lights'] as List)
          .length;

  test(
    'writes one lamp where three hung, and the previews beside it',
    () async {
      // Mutation: return before `writeAsStringSync` in `runLights`. The copy
      // is never written and reading it throws.
      final said = StringBuffer();
      final copy = '${scratch.path}/fewer.json';
      final code = await runLights(<String>[
        '--optimize',
        level,
        '--out',
        copy,
        '--preview',
        '${scratch.path}/preview',
      ], out: IOSink(_Into(said)));
      expect(code, 0, reason: '$said');
      expect(said.toString(), startsWith('3 → 1 lights'));
      expect(lightsIn(copy), 1);
      expect(lightsIn(level), 3, reason: 'the input was written over');
      expect(File('${scratch.path}/preview/before.png').existsSync(), isTrue);
      expect(File('${scratch.path}/preview/after.png').existsSync(), isTrue);
    },
  );

  test('a dry run says so and writes nothing', () async {
    final code = await runLights(<String>[
      '--optimize',
      level,
      '--dry-run',
    ], out: IOSink(_Into(StringBuffer())));
    expect(code, 0);
    expect(lightsIn(level), 3);
  });

  test('judges from poses a player walked when given them', () async {
    final poses = '${scratch.path}/walk.json';
    File(poses).writeAsStringSync(
      jsonEncode(<Object?>[
        <String, Object?>{
          't': 0.0,
          'p': <double>[1.5, 0.0, 1.5],
          'y': 0.785,
        },
        <String, Object?>{
          't': 1.0,
          'p': <double>[-1.5, 0.0, 1.5],
          'y': -0.785,
        },
      ]),
    );
    final code = await runLights(<String>[
      '--optimize',
      level,
      '--poses',
      poses,
    ], out: IOSink(_Into(StringBuffer())));
    expect(code, 0);
    expect(lightsIn(level), 1);
  });

  test('judges under every lighting state it is given', () async {
    // One dim lamp, and a noon sun (a bright lamp the state adds) that
    // drowns it out. Under noon alone the lamp goes; with night as well it
    // stays. Mutation: drop `states:` from the `optimize` call in
    // `runLights`. The level is judged as it is, and the lamp stays both
    // times.
    File(level).writeAsStringSync(
      jsonEncode(
        _room()
          ..['lights'] = <Object?>[
            <String, Object?>{
              'type': 'point',
              'at': <double>[1.2, 1.0, -1.2],
              'intensity': 0.6,
              'range': 4.0,
            },
          ],
      ),
    );
    final noon = '${scratch.path}/noon.json';
    final night = '${scratch.path}/night.json';
    File(noon).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'name': 'noon',
        'lights': <Object?>[
          <String, Object?>{
            'type': 'point',
            'at': <double>[0.0, 2.2, 0.0],
            'intensity': 60.0,
            'range': 8.0,
          },
        ],
      }),
    );
    File(
      night,
    ).writeAsStringSync(jsonEncode(<String, Object?>{'name': 'night'}));

    Future<int> lightsAfter(List<String> states) async {
      final copy = '${scratch.path}/out.json';
      final said = StringBuffer();
      final code = await runLights(<String>[
        '--optimize',
        level,
        for (final state in states) ...<String>['--state', state],
        '--out',
        copy,
      ], out: IOSink(_Into(said)));
      expect(code, 0, reason: '$said');
      return File(copy).existsSync() ? lightsIn(copy) : lightsIn(level);
    }

    expect(await lightsAfter(<String>[noon]), 0);
    File('${scratch.path}/out.json').deleteSync();
    expect(await lightsAfter(<String>[noon, night]), 1);
  });

  test('--classes writes a light set per device class, each to its own '
      'tolerance, and leaves the level alone', () async {
    // A ceiling lamp and a small red one low in a corner, bright enough that
    // dropping it darkens just over one per cent of the pixels: past the
    // desktop's tolerance, inside the phone's. Mutation: build every
    // class's optimizer with the default tolerance in `_perClass`, and the
    // phone keeps both lamps too.
    File(level).writeAsStringSync(
      jsonEncode(
        _room()
          ..['lights'] = <Object?>[
            <String, Object?>{
              'type': 'point',
              'at': <double>[0.0, 2.2, 0.0],
              'intensity': 2.0,
              'range': 8.0,
            },
            <String, Object?>{
              'type': 'point',
              'at': <double>[-1.8, 0.4, -1.8],
              'color': <double>[1.0, 0.3, 0.2],
              'intensity': 1.2,
              'range': 2.0,
            },
          ],
      ),
    );
    final said = StringBuffer();
    final code = await runLights(<String>[
      '--optimize',
      level,
      '--classes',
      'phone,desktop',
    ], out: IOSink(_Into(said)));
    expect(code, 0, reason: '$said');
    expect(lightsIn('${scratch.path}/room.phone.json'), 1, reason: '$said');
    expect(lightsIn('${scratch.path}/room.desktop.json'), 2, reason: '$said');
    expect(File('${scratch.path}/room.web.json').existsSync(), isFalse);
    expect(lightsIn(level), 2);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('refuses arguments it cannot read', () async {
    final err = StringBuffer();
    expect(
      await runLights(<String>['--optimise', level], err: IOSink(_Into(err))),
      2,
    );
    expect(err.toString(), contains('usage:'));
  });
}

/// A sink into a string buffer, so what the command says can be read.
final class _Into implements StreamConsumer<List<int>> {
  _Into(this.buffer);

  final StringBuffer buffer;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      buffer.write(utf8.decode(chunk));
    }
  }

  @override
  Future<void> close() async {}
}
