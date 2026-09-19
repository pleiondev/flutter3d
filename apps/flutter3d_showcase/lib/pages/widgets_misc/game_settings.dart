/// What a player has changed about how the game behaves for them, and where
/// a run in progress is kept between launches.
///
/// **`flutter3d_game`'s real `GameConfig`, `SaveFile` and `SettingsPanel` are
/// not a dependency of this app.** `GameConfig` is two maps of numbers with
/// no file and no platform behind it; this page reimplements exactly that
/// shape. `SaveFile` is thinner still — underneath its own few lines it is
/// entirely the real `Storage` and `Snapshot` this app already depends on
/// through `flutter3d_app` and `flutter3d_sim`, so this page's version calls
/// those directly rather than reimplementing anything of substance.
/// `SettingsPanel` itself is a Flutter widget over a `Bindings` and a
/// gamepad's dead zone, both of which live in packages this app does not
/// have; it is described in the guide rather than built here.
///
/// Quoted by `game_settings.md` and shown whole in the Source tab.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region config
/// Everything a player has changed, as two maps of numbers: no file, no
/// path, no platform. Where the bytes go is the application's business.
final class _GameConfig {
  _GameConfig({Map<String, double>? volumes, Map<String, double>? settings})
    : volumes = <String, double>{...?volumes},
      settings = <String, double>{...?settings};

  final Map<String, double> volumes;
  final Map<String, double> settings;

  double volumeOf(String bus) => volumes[bus] ?? 1.0;
  void setVolume(String bus, double volume) =>
      volumes[bus] = volume.clamp(0.0, 1.0);
  double settingOf(String name, double fallback) => settings[name] ?? fallback;
  void setSetting(String name, double value) => settings[name] = value;
}
// #endregion config

// #region save
/// Where a run in progress is kept. Everything below the field names is the
/// real `Storage` and `Snapshot` this app already depends on.
final class _SaveFile {
  _SaveFile({required String appName}) : _storage = defaultStorage(appName);

  final Storage _storage;
  static const String _name = 'save.json';

  ({String level, Snapshot run})? read() {
    final text = _storage.read(_name);
    if (text == null) return null;
    final json = jsonDecode(text) as Map<String, Object?>;
    return (
      level: json['level']! as String,
      run: Snapshot.fromJson(json['run']! as Map<String, Object?>),
    );
  }

  bool write(String level, Snapshot run) => _storage.write(
    _name,
    jsonEncode(<String, Object?>{'level': level, 'run': run.toJson()}),
  );

  void clear() => _storage.remove(_name);
}
// #endregion save

final class GameSettingsDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'panel',
      baseColor: Vector4(0.5, 0.7, 0.5, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static String _run() {
    // #region use
    final config = _GameConfig()
      ..setVolume('music', 0.6)
      ..setSetting('a11y.cameraMotion', 0.0);
    final musicVolume = config.volumeOf('music');
    final sfxVolume = config.volumeOf('sfx');
    final cameraMotion = config.settingOf('a11y.cameraMotion', 1.0);
    // #endregion use

    final save = _SaveFile(appName: 'flutter3d-showcase-demo');
    final snapshot = Snapshot(<String, Object?>{'x': 4.5});
    save.write('levels/one.json', snapshot);
    final resumed = save.read();
    save.clear();
    final afterClear = save.read();

    return 'music volume: $musicVolume, sfx (never set): $sfxVolume\n'
        'camera motion setting: $cameraMotion\n'
        'resumed at level ${resumed?.level}, x=${resumed?.run.data['x']}\n'
        'after clearing the save: $afterClear';
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
    if (!_report.contains('music volume: 0.6, sfx (never set): 1.0')) {
      throw StateError('a bus nobody set should default to full volume');
    }
    if (!_report.contains('resumed at level levels/one.json, x=4.5')) {
      throw StateError(
        'a written save should read back with its own level '
        'and its own state',
      );
    }
    if (!_report.contains('after clearing the save: null')) {
      throw StateError('a cleared save should read back as nothing');
    }
  }
}
