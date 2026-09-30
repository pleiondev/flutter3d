/// What a hot reload does to a running 3D world, in debug builds.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';

/// Reads the current bytes of a shader bundle an application loaded itself,
/// or null when they cannot be read now.
typedef ShaderBundleSource = Future<ByteData?> Function();

/// Reads the current bytes of a model file, or null when they cannot be read
/// now.
typedef ModelBytesSource = Future<Uint8List?> Function();

/// Builds a model from a file's bytes, on the device the game draws with.
typedef ModelBuild = Future<ModelAsset> Function(Uint8List bytes);

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
  final List<SwappableModel> _models = <SwappableModel>[];
  final List<WeakReference<Scene>> _scenes = <WeakReference<Scene>>[];
  final Map<String, Map<String, Object?>> _overrides =
      <String, Map<String, Object?>>{};

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

  /// Loads the model the build hook converted [sourcePath] into, as
  /// `loadModelAsset` does, and hands it back ready to be swapped when the
  /// file changes.
  ///
  /// **The one call a game makes.** Instantiate through the result, and a
  /// hot reload after the model was edited draws the edit in the nodes the
  /// game already holds; see [ModelInstance.adopt] for what follows and what
  /// needs the model instantiated again. Outside a debug build this is
  /// `loadModelAsset` and nothing is watched.
  Future<SwappableModel> loadModel(
    String sourcePath, {
    required GraphicsDevice device,
  }) async {
    final generated = generatedAssetPathFor(sourcePath);
    Future<Uint8List?> load(String path) async {
      try {
        final data = await rootBundle.load(path);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } on FlutterError {
        return null;
      }
    }

    // The file `loadModelAsset` would read: this device class's own first,
    // then the one every class shares.
    Future<Uint8List?> read() async => switch (assetDeviceClass) {
      final DeviceClass reading =>
        await load(deviceClassPath(generated, reading)) ??
            await load(generated),
      null => await load(generated),
    };

    Future<ModelAsset> build(Uint8List bytes) async => ModelAsset.fromDocument(
      await decodeModelInIsolate(
        ModelLoadRequest(source: _MemorySource(generated, bytes)),
      ),
      device: device,
    );

    // Read once and built from what was read, so the bytes the swap compares
    // against are the ones on screen. A project with no converted file yet
    // goes through `loadModelAsset`, which decodes the source, and its first
    // swap takes the converted file as it finds it as the starting point.
    final bytes = enabled ? await read() : null;
    final asset = bytes != null
        ? await build(bytes)
        : await ModelAsset.fromDocument(
            await loadModelAsset(sourcePath),
            device: device,
          );
    return registerModel(
      sourcePath,
      asset,
      read: read,
      build: build,
      device: device,
      loadedFrom: bytes,
    );
  }

  /// Wraps [asset], loaded from the file [read] reads, so that a [swap] after
  /// the file changed rebuilds it with [build] and every instance made
  /// through the result adopts it.
  ///
  /// [path] names it for `ext.flutter3d.assets.put` and in the report.
  /// [loadedFrom] are the bytes [asset] was built from, when the caller has
  /// them; without them the first swap reads the file and takes it as the
  /// starting point rather than as a change. [device] is what an old asset is
  /// released from once nothing draws it.
  SwappableModel registerModel(
    String path,
    ModelAsset asset, {
    required ModelBytesSource read,
    required ModelBuild build,
    GraphicsDevice? device,
    Uint8List? loadedFrom,
  }) {
    final model = SwappableModel._(
      path,
      asset,
      read,
      build,
      device,
      loadedFrom == null
          ? null
          : _fingerprint(ByteData.sublistView(loadedFrom)),
    );
    if (!enabled) return model;
    _models
      ..removeWhere((SwappableModel m) => m.path == path)
      ..add(model);
    _registerExtension();
    return model;
  }

  /// Draws [bytes] as the model registered at [path] in every instance of it,
  /// without the file on disk changing: what `ext.flutter3d.assets.put`
  /// does for a tool on another machine, a phone that has no disk the
  /// editor can write.
  ///
  /// The file's own bytes win again the next time they change. Null when no
  /// model is registered at [path].
  Future<ModelSwapReport?> put(String path, Uint8List bytes) async {
    if (!enabled) return null;
    for (final model in _models) {
      if (model.path == path) {
        final report = await model._adopt(bytes);
        _applyOverrides();
        return report;
      }
    }
    return null;
  }

  /// Remembers [scene] until it is garbage, for [setMaterial] to find
  /// materials in. `SceneSurface` registers the scene it draws.
  void registerScene(Scene scene) {
    if (!enabled) return;
    _scenes.removeWhere((WeakReference<Scene> s) => s.target == null);
    if (_scenes.any((WeakReference<Scene> s) => identical(s.target, scene))) {
      return;
    }
    _scenes.add(WeakReference<Scene>(scene));
    _registerExtension();
  }

  /// The fields [setMaterial] understands, and how many numbers each takes.
  static const Map<String, int> materialFields = <String, int>{
    'baseColor': 4,
    'emissive': 3,
    'emissiveStrength': 1,
    'roughness': 1,
    'metallic': 1,
    'normalScale': 1,
    'alphaCutoff': 1,
  };

  /// Sets [fields] on every material called [name] in the registered
  /// scenes, from the next frame on, and keeps them as overrides.
  ///
  /// **For an inspector dragging a slider.** Nothing is saved and nothing is
  /// reloaded; the material the frame is drawn with changes. What the
  /// simulation reads is not a material's business, so nothing here goes
  /// near the tape — a tunable is the door for that.
  ///
  /// **The overrides outlive the file.** A model swapped after the drag
  /// brings its materials as the file has them, which is the value before
  /// the drag; every swap puts the overrides back on, so the colour somebody
  /// is still dragging does not snap back each time the model is saved.
  /// [clearMaterial] drops them.
  ///
  /// [fields] maps a name from [materialFields] to a number or a list of
  /// that many numbers. Throws [ArgumentError] naming the field otherwise.
  /// Returns how many materials took the change.
  int setMaterial(String name, Map<String, Object?> fields) {
    if (!enabled) return 0;
    for (final MapEntry(key: field, :value) in fields.entries) {
      _numbers(field, value);
    }
    (_overrides[name] ??= <String, Object?>{}).addAll(fields);
    return _applyOverrides(only: name);
  }

  /// Forgets the overrides for [name], or for every material when null. The
  /// materials keep what they were set to until their file is loaded again.
  void clearMaterial([String? name]) {
    if (name == null) {
      _overrides.clear();
    } else {
      _overrides.remove(name);
    }
  }

  int _applyOverrides({String? only}) {
    _scenes.removeWhere((WeakReference<Scene> s) => s.target == null);
    final seen = Set<Material>.identity();
    for (final scene in _scenes) {
      scene.target?.root.traverse((SceneNode node) {
        if (node is! MeshNode) return;
        final material = node.material;
        final name = material.name;
        if (name == null || (only != null && name != only)) return;
        final fields = _overrides[name];
        if (fields == null || !seen.add(material)) return;
        for (final MapEntry(key: field, :value) in fields.entries) {
          _write(material, field, _numbers(field, value));
        }
      });
    }
    return seen.length;
  }

  static List<double> _numbers(String field, Object? value) {
    final count = materialFields[field];
    if (count == null) {
      throw ArgumentError.value(
        field,
        'field',
        'not a material field; there are ${materialFields.keys.join(', ')}',
      );
    }
    final numbers = switch (value) {
      final num one => <double>[one.toDouble()],
      final List<Object?> many => <double>[
        for (final item in many)
          if (item is num) item.toDouble(),
      ],
      _ => const <double>[],
    };
    if (numbers.length != count ||
        (value is List<Object?> && value.length != count)) {
      throw ArgumentError.value(
        value,
        field,
        'takes $count number${count == 1 ? '' : 's'}',
      );
    }
    return numbers;
  }

  static void _write(Material material, String field, List<double> v) {
    switch (field) {
      case 'baseColor':
        material.baseColor.setValues(v[0], v[1], v[2], v[3]);
      case 'emissive':
        material.emissive.setValues(v[0], v[1], v[2]);
      case 'emissiveStrength':
        material.emissiveStrength = v[0];
      case 'roughness':
        material.roughness = v[0];
      case 'metallic':
        material.metallic = v[0];
      case 'normalScale':
        material.normalScale = v[0];
      case 'alphaCutoff':
        material.alphaCutoff = v[0];
    }
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
    final models = <ModelSwapReport>[];
    for (final model in List<SwappableModel>.of(_models)) {
      final Uint8List? bytes;
      try {
        bytes = await model._read();
      } on Object catch (error) {
        refused.add('${model.path}: could not be read ($error)');
        continue;
      }
      if (bytes == null) continue;
      final fingerprint = _fingerprint(ByteData.sublistView(bytes));
      if (model._fingerprint == null || fingerprint == model._fingerprint) {
        model._fingerprint = fingerprint;
        continue;
      }
      model._fingerprint = fingerprint;
      final report = await model._adopt(bytes);
      if (report.refused case final String reason) {
        refused.add('${model.path}: $reason');
      } else {
        models.add(report);
      }
    }
    if (models.isNotEmpty) _applyOverrides();
    _renderers.removeWhere((WeakReference<Renderer> r) => r.target == null);
    for (final renderer in _renderers) {
      renderer.target?.relinkShaders();
    }
    final report = HotSwapReport(
      renderers: _renderers.length,
      refreshed: List<String>.unmodifiable(refreshed),
      refused: List<String>.unmodifiable(refused),
      models: List<ModelSwapReport>.unmodifiable(models),
    );
    for (final line in refused) {
      debugPrint('flutter3d: kept the last version that loaded, $line');
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
    developer.registerExtension('ext.flutter3d.material.set', (
      String method,
      Map<String, String> parameters,
    ) async {
      final name = parameters['name'];
      final fields = parameters['fields'];
      if (name == null || fields == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          'material.set takes a name and its fields as JSON',
        );
      }
      try {
        final touched = instance.setMaterial(
          name,
          jsonDecode(fields) as Map<String, Object?>,
        );
        return developer.ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'materials': touched}),
        );
      } on Object catch (error) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          '$error',
        );
      }
    });
    developer.registerExtension('ext.flutter3d.assets.put', (
      String method,
      Map<String, String> parameters,
    ) async {
      final path = parameters['path'];
      final bytes = parameters['bytes'];
      if (path == null || bytes == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          'assets.put takes a path and its bytes in base64',
        );
      }
      final report = await instance.put(path, base64Decode(bytes));
      if (report == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          'no model is registered at $path',
        );
      }
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
    this.models = const <ModelSwapReport>[],
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

  /// The bundles and models that changed and did not load, each with the
  /// reason. They kept the last version that did.
  final List<String> refused;

  /// The models that changed and were adopted.
  final List<ModelSwapReport> models;

  Map<String, Object?> toJson() => <String, Object?>{
    'renderers': renderers,
    'refreshed': refreshed,
    'refused': refused,
    'models': <Object?>[for (final model in models) model.toJson()],
  };
}

final class _Library {
  _Library(this.library, this.read, this.fingerprint);

  final WeakReference<LoadedShaderLibrary> library;
  final ShaderBundleSource read;
  int? fingerprint;
}

/// A model a game draws, and every instance of it, kept together so a
/// changed file reaches all of them.
///
/// What [HotSwap.loadModel] and [HotSwap.registerModel] hand back. Make
/// instances through [instantiate], or hand ones made elsewhere to [track];
/// an instance the game drops is forgotten with it.
final class SwappableModel {
  SwappableModel._(
    this.path,
    this._asset,
    this._read,
    this._build,
    this._device,
    this._fingerprint,
  );

  /// The file this model was loaded from, as the game named it.
  final String path;

  /// The version drawn now; a new one after each swap.
  ModelAsset get asset => _asset;
  ModelAsset _asset;

  final ModelBytesSource _read;
  final ModelBuild _build;
  final GraphicsDevice? _device;
  int? _fingerprint;
  final List<WeakReference<ModelInstance>> _instances =
      <WeakReference<ModelInstance>>[];

  /// [asset]'s `instantiate`, remembering the instance for the next swap.
  ModelInstance instantiate(
    Scene scene, {
    SceneNode? parent,
    String? name,
    bool shareMaterials = true,
  }) => track(
    _asset.instantiate(
      scene,
      parent: parent,
      name: name,
      shareMaterials: shareMaterials,
    ),
  );

  /// Remembers [instance], made from [asset] some other way —
  /// `instantiateFitted`, say — for the next swap.
  ModelInstance track(ModelInstance instance) {
    _instances
      ..removeWhere((WeakReference<ModelInstance> i) => i.target == null)
      ..add(WeakReference<ModelInstance>(instance));
    return instance;
  }

  Future<ModelSwapReport> _adopt(Uint8List bytes) async {
    final ModelAsset next;
    try {
      next = await _build(bytes);
    } on Object catch (error) {
      return ModelSwapReport(path: path, instances: 0, refused: '$error');
    }
    _instances.removeWhere(
      (WeakReference<ModelInstance> i) => i.target == null,
    );
    final swaps = <ModelSwap>[
      for (final instance in _instances)
        if (instance.target case final ModelInstance live) live.adopt(next),
    ];
    final previous = _asset;
    _asset = next;
    // Released only when no instance still draws a surface of it: a surface
    // the new file dropped stays drawn from the old asset's meshes.
    if (_device case final GraphicsDevice device
        when swaps.every((ModelSwap s) => s.kept.isEmpty)) {
      previous.release(device);
    }
    return ModelSwapReport(
      path: path,
      instances: swaps.length,
      added: <String>{for (final swap in swaps) ...swap.added}.toList(),
    );
  }
}

/// What a changed file did to one [SwappableModel].
@immutable
final class ModelSwapReport {
  const ModelSwapReport({
    required this.path,
    required this.instances,
    this.added = const <String>[],
    this.refused,
  });

  final String path;

  /// The instances that adopted the new version.
  final int instances;

  /// Surfaces the new version has that its instances could not take on
  /// (see `ModelSwap.added`); instantiate the model again to draw them.
  final List<String> added;

  /// Why the new bytes did not build, when they did not; the model is drawn
  /// as it was.
  final String? refused;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'instances': instances,
    'added': added,
    if (refused != null) 'refused': refused,
  };
}

/// A model file's bytes, already read, as the decoders read a file.
final class _MemorySource extends AssetSource {
  const _MemorySource(this.path, this.bytes);

  final String path;
  final Uint8List bytes;

  @override
  String get key => 'memory:$path';

  @override
  Future<Uint8List> read() async => bytes;

  @override
  AssetUriResolver get resolveUri =>
      (AssetRequest request) async => throw StateError(
        '$path was sent as bytes and has no files beside it',
      );
}
