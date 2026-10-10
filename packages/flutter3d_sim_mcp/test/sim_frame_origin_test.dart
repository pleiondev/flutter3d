/// `SimSession.frame` draws from the eye through the scene's own origin, so
/// a level far from the world's origin is drawn as one near it is.
///
///     flutter test test/sim_frame_origin_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_mcp/kit.dart' show ProjectRoot;
import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionWorld;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show WorldPosition;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_sim_mcp/flutter3d_sim_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A run whose eye is where the test puts it, looking down -Z.
final class _Standing extends HeadlessRun {
  _Standing(this.eye);

  @override
  final WorldPosition eye;

  @override
  void step(double dt) {}

  @override
  Snapshot save() => const Snapshot(<String, Object?>{});

  @override
  RunOutcome get outcome => RunOutcome.playing;

  @override
  WorldPosition get position => eye;

  @override
  void aim(Vector3 out) => out.setValues(0, 0, -1);

  @override
  String get summary => 'standing';
}

final class _Game extends HeadlessGame {
  _Game(this.eye);

  final WorldPosition eye;

  @override
  String get name => 'standing';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{};

  @override
  EntityRegistry registry() => EntityRegistry(const <EntityKind>[]);

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) =>
      _Standing(eye);
}

/// A floor, a wall in front of the eye and a light, [x] metres east. Every
/// coordinate is a multiple of a quarter, which float32 holds exactly up to
/// four thousand kilometres, so the level itself loses nothing out there.
Map<String, Object?> _room(double x) => <String, Object?>{
  'version': 1,
  'name': 'a room at $x',
  'materials': <String, Object?>{
    'grey': <String, Object?>{
      'baseColor': <double>[0.7, 0.7, 0.7, 1.0],
    },
    'red': <String, Object?>{
      'baseColor': <double>[0.8, 0.2, 0.2, 1.0],
    },
  },
  'brushes': <Map<String, Object?>>[
    <String, Object?>{
      'at': <double>[x, -0.5, 0.0],
      'size': <double>[8.0, 1.0, 8.0],
      'material': 'grey',
    },
    <String, Object?>{
      'at': <double>[x + 1.0, 1.0, -2.0],
      'size': <double>[1.0, 2.0, 1.0],
      'material': 'red',
    },
  ],
  'lights': <Map<String, Object?>>[
    <String, Object?>{
      'type': 'point',
      'at': <double>[x, 3.0, 2.0],
      'color': <double>[1.0, 1.0, 1.0],
      'intensity': 12.0,
      'range': 20.0,
    },
  ],
  'entities': <Map<String, Object?>>[],
};

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('sim_frame_origin');
  });

  tearDown(() => project.deleteSync(recursive: true));

  Future<List<int>> frameAt(double x) async {
    File('${project.path}/room.json').writeAsStringSync(jsonEncode(_room(x)));
    final session = SimSession(
      game: _Game(WorldPosition(x + 0.4, 1.0, 4.0)),
      root: ProjectRoot(project.path),
    );
    expect(session.open('room.json').did, isTrue);
    final framed = await session.frame();
    expect(framed.did, isTrue, reason: framed.says);
    return framed.png!;
  }

  test('a room four thousand kilometres out is drawn as the same room at '
      'the origin', () async {
    // Mutation: narrow the eye against `WorldPosition.origin`, as before
    // 1.0. At 4 000 km float32 steps are a quarter of a metre, the eye's
    // 0.4 becomes 0.5, and the wall moves across the picture.
    final near = _rgba(await frameAt(0.0));
    final far = _rgba(await frameAt(4000000.0));
    expect(far, hasLength(near.length));
    // Pixels that differ by more than two levels of eight bits: a few on
    // the edges of the wall and the floor, where coverage rounds the other
    // way out there (61 of 64 000 when this was written). Without the
    // origin moved to the eye it was 4 945.
    final moved = <int>{
      for (var i = 0; i < near.length; i++)
        if ((far[i] - near[i]).abs() > 2) i ~/ 4,
    };
    expect(moved.length, lessThan(near.length ~/ 4 ~/ 100));
  });
}

/// The pixels of a PNG `encodePng` wrote: one IDAT, stored zlib, filter 0 on
/// every row, so decoding is inflating and dropping each row's filter byte.
List<int> _rgba(List<int> png) {
  final bytes = ByteData.sublistView(Uint8List.fromList(png));
  final width = bytes.getUint32(16);
  final idat = <int>[];
  var at = 8;
  while (at < png.length) {
    final length = bytes.getUint32(at);
    final type = ascii.decode(png.sublist(at + 4, at + 8));
    if (type == 'IDAT') idat.addAll(png.sublist(at + 8, at + 8 + length));
    at += 12 + length;
  }
  final raw = ZLibCodec().decode(idat);
  final row = width * 4 + 1;
  return <int>[
    for (var y = 0; y * row < raw.length; y++)
      ...raw.sublist(y * row + 1, (y + 1) * row),
  ];
}
