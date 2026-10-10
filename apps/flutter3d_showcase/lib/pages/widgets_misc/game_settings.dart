/// What a player has changed about how the game behaves for them, and where
/// a run in progress is kept between launches.
///
/// `flutter3d_game`'s `GameSettings` is a value: a volume per audio bus,
/// typed settings under namespaced keys, and the player's action map, each
/// change a copy. It is written in the format envelope as `f3d.settings`.
/// `SaveFile` is thin enough that this page calls the real `Storage` and
/// `Snapshot` under it directly. `SettingsPanel` is the widget over a
/// `GameSettingsController`, made of `SettingsSection`s; it is described in
/// the guide rather than built here.
///
/// Quoted by `game_settings.md` and shown whole in the Source tab.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart' show AudioBus;
import 'package:flutter3d_game/flutter3d_game.dart'
    show GameSettingKeys, GameSettings, SettingKey;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

// #region config
/// A setting of this game's own: typed, under its own namespace, with what it
/// is when the player has not chosen.
const SettingKey<bool> _subtitles = SettingKey<bool>(
  'showcase.subtitles',
  fallback: true,
);
// #endregion config

// #region save
/// Where a run in progress is kept. Everything below the field names is the
/// real `Storage` and `Snapshot` this app already depends on.
final class _SaveFile {
  _SaveFile({required String appName}) : _storage = defaultStorage(appName);

  final Storage _storage;
  static const String _name = 'save.json';

  Future<({String level, Snapshot run})?> read() async {
    final text = await _storage.read(_name);
    if (text == null) return null;
    final json = jsonDecode(text) as Map<String, Object?>;
    return (
      level: json['level']! as String,
      run: Snapshot.fromJson(json['run']! as Map<String, Object?>),
    );
  }

  Future<void> write(String level, Snapshot run) => _storage.write(
    _name,
    jsonEncode(<String, Object?>{'level': level, 'run': run.toJson()}),
  );

  Future<void> clear() => _storage.remove(_name);
}
// #endregion save

final class GameSettingsDemo extends ShowcaseDemo {
  late final String _report;
  late final double _musicVolume;
  late final double _sfxVolume;
  late final String? _resumedLevel;
  late final double? _resumedX;
  late final bool _clearedSaveIsGone;

  @override
  Future<void> prepare(DemoContext context) async {
    final (
      String report,
      double musicVolume,
      double sfxVolume,
      String? resumedLevel,
      double? resumedX,
      bool clearedSaveIsGone,
    ) = await _run();
    _report = report;
    _musicVolume = musicVolume;
    _sfxVolume = sfxVolume;
    _resumedLevel = resumedLevel;
    _resumedX = resumedX;
    _clearedSaveIsGone = clearedSaveIsGone;
  }

  @override
  Scene build(DemoContext context) {
    final material = RenderMaterial(
      name: 'panel',
      baseColor: LinearColor.fromSrgb(0.5, 0.7, 0.5, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static Future<(String, double, double, String?, double?, bool)> _run() async {
    // #region use
    final config = const GameSettings()
        .withVolume(AudioBus.music, 0.6)
        .withValue(GameSettingKeys.cameraMotion, 0.0)
        .withValue(_subtitles, false);
    final musicVolume = config.volumeOf(AudioBus.music);
    final sfxVolume = config.volumeOf(AudioBus.sfx);
    final cameraMotion = config.valueOf(GameSettingKeys.cameraMotion);
    // The file, in the envelope, read back.
    final read = GameSettings.fromJson(config.toJson());
    assert(!read.valueOf(_subtitles), 'a setting of its own came back');
    // #endregion use

    final save = _SaveFile(appName: 'flutter3d-showcase-demo');
    final snapshot = Snapshot(<String, Object?>{'x': 4.5});
    await save.write('levels/one.json', snapshot);
    final resumed = await save.read();
    await save.clear();
    final afterClear = await save.read();

    final resumedX = (resumed?.run.data['x'] as num?)?.toDouble();
    final report =
        'music volume: $musicVolume, sfx (never set): $sfxVolume\n'
        'camera motion setting: $cameraMotion\n'
        'resumed at level ${resumed?.level}, x=$resumedX\n'
        'after clearing the save: $afterClear';
    return (
      report,
      musicVolume,
      sfxVolume,
      resumed?.level,
      resumedX,
      afterClear == null,
    );
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the panel marker was not drawn');
    }
    // Compared as numbers, not read back out of `_report`: `sfxVolume`'s
    // default is a whole-number double, and a web backend prints one of
    // those without its trailing `.0` — a compiled `1` failing a substring
    // match against `'sfx (never set): 1.0'` would be this check catching
    // its own string, not the config.
    if (_musicVolume != 0.6 || _sfxVolume != 1.0) {
      throw StateError('a bus nobody set should default to full volume');
    }
    if (_resumedLevel != 'levels/one.json' || _resumedX != 4.5) {
      throw StateError(
        'a written save should read back with its own level '
        'and its own state',
      );
    }
    if (!_clearedSaveIsGone) {
      throw StateError('a cleared save should read back as nothing');
    }
  }
}
