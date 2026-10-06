/// `P12`'s line done, for real: an agent, from a cold session, runs the
/// dungeon and finds the draw that paints a pixel of the frame it shows —
/// `flutter run` on this machine, the game's own renderer, its own VM
/// service. Minutes, not seconds, so it runs only when asked:
///
///     FLUTTER3D_RUN_GAMES=1 dart test test/dungeon_frame_test.dart
@Timeout(Duration(minutes: 12))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_editor_mcp/flutter3d_editor_mcp.dart';
import 'package:test/test.dart';

Future<({bool did, String says})> _call(
  EditorSession session,
  String name, [
  Map<String, Object?> arguments = const <String, Object?>{},
]) async {
  final answer = await editorTools
      .firstWhere((EditorTool it) => it.name == name)
      .run(session, arguments);
  return (did: answer.did, says: answer.says);
}

void main() {
  test(
    'the dungeon run, the draw under the middle of its frame found',
    () async {
      final level = File(
        '../../apps/flutter3d_demo_dungeon/assets/levels/crypt.json',
      ).absolute.path;
      final session = EditorSession(
        Editing.parse(File(level).readAsStringSync(), path: level),
        play: PlaySession(
          levelPath: level,
          waitFor: const Duration(minutes: 8),
        ),
      );
      addTearDown(() => _call(session, 'play_stop'));

      final played = await _call(session, 'play');
      expect(played.did, isTrue, reason: played.says);

      // The game is up when its renderer answers: the first frames are a
      // level loading.
      ({bool did, String says}) passes = (did: false, says: '');
      for (var i = 0; i < 60 && !passes.did; i++) {
        passes = await _call(session, 'render_passes');
        if (!passes.did) await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(passes.did, isTrue, reason: passes.says);
      final frame = jsonDecode(passes.says) as Map<String, Object?>;
      final (width, height) = (frame['width']! as int, frame['height']! as int);

      final picked = await _call(session, 'render_pick', <String, Object?>{
        'x': width ~/ 2,
        'y': height ~/ 2,
      });
      expect(picked.did, isTrue, reason: picked.says);
      final found = jsonDecode(picked.says) as Map<String, Object?>;
      // The crypt in front of the player: something is drawn there, and
      // the frame says which draws drew it.
      expect(found['node'], isNotNull, reason: picked.says);
      final draws = (found['draws']! as List<Object?>).cast<int>();
      expect(draws, isNotEmpty, reason: picked.says);

      final opened = await _call(session, 'render_draw', <String, Object?>{
        'index': draws.first,
      });
      expect(opened.did, isTrue, reason: opened.says);
      final draw = jsonDecode(opened.says) as Map<String, Object?>;
      expect(draw['mesh'], found['node']);
      expect(draw['state'], isA<Map<String, Object?>>());
    },
    skip: Platform.environment['FLUTTER3D_RUN_GAMES'] == null
        ? 'runs the dungeon with flutter run; set FLUTTER3D_RUN_GAMES=1'
        : null,
  );
}
