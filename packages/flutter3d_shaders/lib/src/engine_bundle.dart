/// What the engine's own bundle carries besides its compiled sections: the
/// toolchain it was built with, and which stages it holds.
///
/// **The SDK token in the bundle's header is not enough on its own.** It is
/// the Dart version, which is what a running application can read about
/// itself and what `impellerc`'s output is refused against at load. A build
/// wants more: the engine revision, which moves on a Flutter hotfix while
/// the Dart version stays, and the needs the bundle was written for, so a
/// cache knows when to write it again and `doctor` can say what a project
/// carries. That goes into a section of its own, [section], which a backend
/// that does not read it skips like any other.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/shader_bundle.dart';

/// The stamp a project's engine bundle carries, in its [section].
final class EngineBundleStamp {
  const EngineBundleStamp({
    required this.dart,
    required this.engine,
    this.needs = const <String>[],
    this.full = false,
    this.stages = 0,
  });

  /// The section name. Namespaced, so it can never be a backend's.
  static const String section = 'flutter3d.stamp';

  /// Where `flutter3d_build`'s hook writes a project's engine bundle, as the
  /// asset key the backends load it by: inside `flutter3d_generated/`, which a
  /// project bundles whole.
  static const String projectAsset =
      'flutter3d_generated/shaders/flutter3d.f3dshaders';

  /// Where the hook keeps the bundle it wrote before this one, for a running
  /// application that hot-reloads across the rebuild. Older ones are removed.
  static const String previousProjectAsset =
      'flutter3d_generated/shaders/flutter3d.previous.f3dshaders';

  /// The directory both live in, and every plugin material the hook compiles
  /// (D19): the line a project's `flutter: assets:` lists, since Flutter
  /// bundles a directory's files and not its subdirectories.
  static const String projectDirectory = 'flutter3d_generated/shaders/';

  /// Where the hook writes the bundle of the plugin material named
  /// [material] — the name its `material` line gives it — compiled for the
  /// SDK the project builds with. A plugin's own loader asks for this key
  /// before any bundle the plugin ships.
  static String projectMaterialAsset(String material) =>
      '$projectDirectory$material.f3dshaders';

  /// The engine's bundle: [stages] and [sections] under the name `flutter3d`,
  /// with [dart] in the header and this stamp in [section].
  ShaderBundle bundle({
    required List<ShaderBundleStage> stages,
    required Map<String, ByteData> sections,
  }) => ShaderBundle(
    name: 'flutter3d',
    sdk: dart,
    stages: stages,
    sections: <String, ByteData>{...sections, section: encode()},
  );

  /// The Dart that ran the build: the token the header's `sdk` carries.
  final String dart;

  /// The Flutter engine revision the compiled section was made with, as the
  /// SDK's `bin/cache/engine.stamp` writes it; empty when unknown.
  final String engine;

  /// The needs the bundle was written for, by name, [full] aside.
  final List<String> needs;

  /// Whether the bundle holds every stage, as `--full-shaders` asks.
  final bool full;

  /// How many stages it holds.
  final int stages;

  ByteData encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'dart': dart,
        'engine': engine,
        'needs': needs,
        'full': full,
        'stages': stages,
      }),
    ),
  ).buffer.asByteData();

  /// [bytes] read back, or null for bytes that are not a stamp: a bundle
  /// without one was not written by a build that stamps.
  static EngineBundleStamp? decode(ByteData? bytes) {
    if (bytes == null) return null;
    try {
      return switch (jsonDecode(
        utf8.decode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        ),
      )) {
        {
          'dart': final String dart,
          'engine': final String engine,
          'needs': final List<Object?> needs,
          'full': final bool full,
          'stages': final int stages,
        } =>
          EngineBundleStamp(
            dart: dart,
            engine: engine,
            needs: <String>[for (final need in needs) '$need'],
            full: full,
            stages: stages,
          ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() =>
      'Dart $dart, engine ${engine.isEmpty ? 'unknown' : engine}, '
      '$stages stages${full ? ' (every one)' : ''}';
}
