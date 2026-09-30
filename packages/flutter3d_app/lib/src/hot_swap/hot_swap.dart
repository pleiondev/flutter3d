/// What a hot reload does to a running 3D world, in debug builds.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter3d/flutter3d.dart';

/// Reads the current bytes of a shader bundle an application loaded itself,
/// or null when they cannot be read now.
typedef ShaderBundleSource = Future<ByteData?> Function();

/// The renderers and shader libraries a running application has, and what to
/// do with them when its code or its shaders change under it.
///
/// **Flutter already swaps the bundle; nothing redrew with it.** The engine's
/// own bundle is loaded from an asset, and Flutter 3.47 reinitializes a
/// library loaded that way on every hot reload whose shaders changed. A
/// library keeps its handles through that, but a pipeline linked from the old
/// code keeps drawing it until it is linked again, so the new shaders reached
/// the library and never the picture. [swap] relinks every renderer this
/// knows of, which is the engine's half of the reload, and refreshes the
/// bundles an application loaded from bytes, which Flutter's half never
/// reaches.
///
/// **Relinked every time, not only when a bundle changed.** Whether Flutter
/// reinitialized the engine's bundle is not observable from here, and a
/// relink costs one link per pipeline on the next frame — the cost of the
/// first frame — once per hot reload, in a debug build.
///
/// **A bundle that does not load keeps the last one that did.** A refused
/// refresh leaves its library as it was (`LoadedShaderLibrary.refresh`
/// promises that), so a shader with a mistake in it costs a message in the
/// report, not the picture.
///
/// Debug builds only: in a profile or release build every method returns at
/// once and holds nothing. What reaches it: `SceneSurface` and the Flame
/// bridge's widget register their renderer and call [swap] from
/// `reassemble`, which is what a hot reload runs; an application registers
/// the bundles it loads itself with [registerLibrary]; and a tool reaches the
/// same thing through the VM service as `ext.flutter3d.hotSwap`.
///
/// A swap and not a reload in its names because `reload` is a weapon's here:
/// CONTRIBUTING.md keeps that word out of the packages, and the structure
/// check holds them to it.
final class HotSwap {
  /// A coordinator of its own, for a test. Everything else uses [instance].
  @visibleForTesting
  HotSwap({this.enabled = kDebugMode});

  /// The one every widget and application registers with.
  static final HotSwap instance = HotSwap();

  /// False in profile and release builds, where nothing reloads.
  final bool enabled;

  final List<WeakReference<Renderer>> _renderers = <WeakReference<Renderer>>[];
  final List<_Library> _libraries = <_Library>[];

  /// Counts the reloads that finished, for a host that draws only on demand
  /// and has to draw once more to show the new shaders.
  final ValueNotifier<int> swaps = ValueNotifier<int>(0);

  Future<HotSwapReport>? _running;
  static bool _extensionRegistered = false;

  /// Remembers [renderer] until it is garbage, to relink it on [swap].
  void registerRenderer(Renderer renderer) {
    if (!enabled) return;
    _renderers.removeWhere((WeakReference<Renderer> r) => r.target == null);
    if (_renderers.any((WeakReference<Renderer> r) => r.target == renderer)) {
      return;
    }
    _renderers.add(WeakReference<Renderer>(renderer));
    _registerExtension();
  }

  /// Remembers [library], loaded from bytes by the application, to refresh
  /// it on [swap] from whatever [read] returns then.
  ///
  /// A bundle loaded from an asset by `flutter_gpu` itself needs no
  /// registration: Flutter reinitializes those. One loaded through
  /// `GraphicsDevice.loadShaders` from bytes the application read does,
  /// because nothing else knows where the bytes came from.
  void registerLibrary(
    LoadedShaderLibrary library, {
    required ShaderBundleSource read,
    ByteData? loadedFrom,
  }) {
    if (!enabled) return;
    _libraries.removeWhere((_Library l) => l.library.target == null);
    _libraries.add(
      _Library(
        WeakReference<LoadedShaderLibrary>(library),
        read,
        loadedFrom == null ? null : _fingerprint(loadedFrom),
      ),
    );
    _registerExtension();
  }

  /// Refreshes the registered bundles whose bytes changed, then relinks every
  /// live renderer.
  ///
  /// Several surfaces reassembling in one hot reload share one run: a call
  /// while one is in flight gets that one's report.
  Future<HotSwapReport> swap() {
    if (!enabled) return Future<HotSwapReport>.value(HotSwapReport.none);
    return _running ??= _swap().whenComplete(() => _running = null);
  }

  Future<HotSwapReport> _swap() async {
    final refreshed = <String>[];
    final refused = <String>[];
    for (final entry in List<_Library>.of(_libraries)) {
      final library = entry.library.target;
      if (library == null) continue;
      final ByteData? bytes;
      try {
        bytes = await entry.read();
      } on Object catch (error) {
        refused.add('${library.name}: could not be read ($error)');
        continue;
      }
      if (bytes == null) continue;
      final fingerprint = _fingerprint(bytes);
      if (fingerprint == entry.fingerprint) continue;
      try {
        library.refresh(bytes);
        entry.fingerprint = fingerprint;
        refreshed.add(library.name);
      } on ShaderBundleRefused catch (refusal) {
        // The library is as it was; the next reload tries these bytes again
        // only if they change, since the same bytes would be refused again.
        entry.fingerprint = fingerprint;
        refused.add('${library.name}: ${refusal.reason}');
      }
    }
    _renderers.removeWhere((WeakReference<Renderer> r) => r.target == null);
    for (final renderer in _renderers) {
      renderer.target?.relinkShaders();
    }
    final report = HotSwapReport(
      renderers: _renderers.length,
      refreshed: List<String>.unmodifiable(refreshed),
      refused: List<String>.unmodifiable(refused),
    );
    for (final line in refused) {
      debugPrint('flutter3d: kept the last shaders that loaded, $line');
    }
    swaps.value++;
    return report;
  }

  void _registerExtension() {
    if (_extensionRegistered || !identical(this, instance)) return;
    _extensionRegistered = true;
    developer.registerExtension('ext.flutter3d.hotSwap', (
      String method,
      Map<String, String> parameters,
    ) async {
      final report = await instance.swap();
      return developer.ServiceExtensionResponse.result(
        jsonEncode(report.toJson()),
      );
    });
  }

  /// FNV-1a over the bundle's bytes: enough to tell a changed file from an
  /// unchanged one, which is all a reload asks.
  static int _fingerprint(ByteData bytes) {
    final data = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    var hash = 0x811c9dc5;
    for (final byte in data) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash ^ data.length;
  }
}

/// What one [HotSwap.swap] did.
@immutable
final class HotSwapReport {
  const HotSwapReport({
    required this.renderers,
    required this.refreshed,
    required this.refused,
  });

  /// What a profile or release build reports: nothing was touched.
  static const HotSwapReport none = HotSwapReport(
    renderers: 0,
    refreshed: <String>[],
    refused: <String>[],
  );

  /// How many renderers were relinked.
  final int renderers;

  /// The bundles that changed and loaded.
  final List<String> refreshed;

  /// The bundles that changed and did not load, each with the reason. Their
  /// libraries kept the last bundle that did.
  final List<String> refused;

  Map<String, Object?> toJson() => <String, Object?>{
    'renderers': renderers,
    'refreshed': refreshed,
    'refused': refused,
  };
}

final class _Library {
  _Library(this.library, this.read, this.fingerprint);

  final WeakReference<LoadedShaderLibrary> library;
  final ShaderBundleSource read;
  int? fingerprint;
}
