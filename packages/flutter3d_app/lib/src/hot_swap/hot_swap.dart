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

/// Reads the current bytes of an image file, or null when they cannot be
/// read now.
typedef TextureBytesSource = Future<Uint8List?> Function();

/// Uploads an image file's bytes as a texture, or null when they do not
/// decode into one.
typedef TextureBuild = Future<TextureHandle?> Function(Uint8List bytes);

/// A prefiltered environment cube and how many levels it has below its base,
/// the two things `Scene.environment` and `Scene.environmentLevels` take.
typedef BuiltEnvironment = ({TextureHandle texture, int levels});

/// Builds an environment from a panorama file's bytes, or null when they do
/// not decode into one.
typedef EnvironmentBuild = Future<BuiltEnvironment?> Function(Uint8List bytes);

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
  final List<SwappableTexture> _textures = <SwappableTexture>[];
  final List<SwappableEnvironment> _environments = <SwappableEnvironment>[];
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

    // The file `loadModelAsset` would read: this device class's own first,
    // then the one every class shares.
    Future<Uint8List?> read() async => switch (assetDeviceClass) {
      final DeviceClass reading =>
        await _readAsset(deviceClassPath(generated, reading)) ??
            await _readAsset(generated),
      null => await _readAsset(generated),
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

  /// Uploads the image asset at [path], as a level or a material file does,
  /// and hands it back ready to be swapped when the file changes. Null when
  /// the file is not there or does not decode.
  ///
  /// **A texture of any new size.** A swap uploads the new file as a texture
  /// of its own and puts it in every slot of every material in the
  /// registered scenes that held the old one, and in a scene's environment;
  /// then the old one goes back to the device once no frame in flight can
  /// still sample it. So a texture may change size, format or mip count
  /// under a running game. What holds the texture anywhere else — a
  /// post-process look-up table, a billboard atlas — reads
  /// [SwappableTexture.texture] or listens to it.
  ///
  /// **For a game's own images**, the ones no loader reads for it: a decal,
  /// a sign, a picture on a wall set up in code. A level's maps are
  /// `LevelLoader`'s, which registers them itself through [registerTexture].
  Future<SwappableTexture?> loadTexture(
    String path, {
    required GraphicsDevice device,
    TextureSampling sampling = const TextureSampling(),
  }) async {
    Future<Uint8List?> read() => _readAsset(path);

    Future<TextureHandle?> build(Uint8List bytes) => uploadEncodedImage(
      device,
      bytes,
      decodeImage: defaultImageDecoder,
      sampling: sampling,
    );

    final bytes = await read();
    if (bytes == null) return null;
    final texture = await build(bytes);
    if (texture == null) return null;
    return registerTexture(
      path,
      texture,
      read: read,
      build: build,
      loadedFrom: bytes,
    );
  }

  /// Wraps [texture], uploaded from the file [read] reads, so that a [swap]
  /// after the file changed uploads it again with [build] and puts the new
  /// texture where the old one was — see [loadTexture].
  ///
  /// [loadedFrom] are the bytes [texture] was made from, when the caller has
  /// them; without them the first swap takes the file as it finds it as the
  /// starting point rather than as a change.
  SwappableTexture registerTexture(
    String path,
    TextureHandle texture, {
    required TextureBytesSource read,
    required TextureBuild build,
    Uint8List? loadedFrom,
  }) {
    final swappable = SwappableTexture._(
      path,
      texture,
      read,
      build,
      loadedFrom == null
          ? null
          : _fingerprint(ByteData.sublistView(loadedFrom)),
    );
    if (!enabled) return swappable;
    _textures
      ..removeWhere((SwappableTexture t) => t.path == path)
      ..add(swappable);
    _registerExtension();
    return swappable;
  }

  /// Puts [bytes] in place of the texture registered at [path], as a changed
  /// file would: what `ext.flutter3d.assets.put` does for an image. Why it
  /// did not take when it did not, or null when it did or nothing is
  /// registered there — [hasTexture] tells those two apart.
  Future<String?> putTexture(String path, Uint8List bytes) async {
    if (!enabled) return null;
    for (final texture in _textures) {
      if (texture.path == path) return _adoptTexture(texture, bytes);
    }
    return null;
  }

  /// Stops watching [texture], for its owner letting it go: a swap after
  /// that would upload a texture for nothing and release one already
  /// released.
  void forgetTexture(SwappableTexture texture) =>
      _textures.removeWhere((SwappableTexture t) => identical(t, texture));

  /// Whether a texture is registered at [path].
  bool hasTexture(String path) =>
      _textures.any((SwappableTexture t) => t.path == path);

  /// Uploads [bytes] for [texture] and puts the result everywhere the old
  /// one was. Why not, when it did not.
  Future<String?> _adoptTexture(
    SwappableTexture texture,
    Uint8List bytes,
  ) async {
    final TextureHandle? next;
    try {
      next = await texture._build(bytes);
    } on Object catch (error) {
      return '$error';
    }
    if (next == null) return 'the new bytes do not decode into an image';
    final previous = texture.texture;
    texture._handle.value = next;
    _replaceTexture(previous, next);
    _releaseAfterFrame(previous);
    return null;
  }

  /// Hands [texture] back to the device once no frame in flight can still
  /// sample it.
  void _releaseAfterFrame(TextureHandle texture) {
    _renderers.removeWhere((WeakReference<Renderer> r) => r.target == null);
    // One renderer releases it: a handle released twice is a mistake a
    // backend may refuse. With none alive nothing is drawing it either, and
    // it goes with the device.
    for (final renderer in _renderers) {
      if (renderer.target case final Renderer live) {
        live.releaseTextureAfterFrame(texture);
        break;
      }
    }
  }

  /// Builds the environment a panorama asset at [path] makes — a Radiance
  /// `.hdr` or any image Flutter decodes — and hands it back ready to be
  /// built again when the file changes. Null when the file is not there,
  /// does not decode, or the device has no cube textures.
  ///
  /// **The cube and its irradiance come back together.** The roughest level
  /// of the chain is the diffuse term (`EnvironmentMap.diffuseLevel`), so one
  /// prefilter makes both, and a swap after the file changed runs it again
  /// and puts the new cube, with its level count, on every registered scene
  /// whose environment was the old one; then the old one goes back to the
  /// device as a swapped texture does. [size] and [levels] stay as given, so
  /// the new file may be a panorama of another size.
  ///
  /// **A swap costs what the prefilter costs.** It runs where the swap runs,
  /// and `EnvironmentMap` states the cost: at the default thirty-two a
  /// fraction of a millisecond, at 512 not something to wait for on every
  /// save.
  ///
  /// **For a game that lights its world from a panorama of its own**, the
  /// call it makes in place of reading the file and calling
  /// `EnvironmentMap.fromPanorama`. Put the result on a scene with
  /// [SwappableEnvironment.applyTo]; a scene a `SceneSurface` draws is
  /// registered already, and any other has to be passed to [registerScene]
  /// for a swap to reach it.
  Future<SwappableEnvironment?> loadEnvironment(
    String path, {
    required GraphicsDevice device,
    int size = 32,
    int levels = 4,
  }) async {
    Future<Uint8List?> read() => _readAsset(path);

    Future<BuiltEnvironment?> build(Uint8List bytes) =>
        EnvironmentMap.fromEncoded(
          device,
          bytes,
          decodeImage: defaultImageDecoder,
          size: size,
          levels: levels,
        );

    final bytes = await read();
    if (bytes == null) return null;
    final built = await build(bytes);
    if (built == null) return null;
    return registerEnvironment(
      path,
      built,
      read: read,
      build: build,
      loadedFrom: bytes,
    );
  }

  /// Wraps [environment], built from the file [read] reads, so that a [swap]
  /// after the file changed builds it again with [build] and puts the result
  /// where the old one was — see [loadEnvironment].
  ///
  /// For an environment made some other way than [loadEnvironment] makes it:
  /// a size chosen per device, a decoder of the game's own. [loadedFrom] are
  /// the bytes [environment] was built from, when the caller has them;
  /// without them the first swap takes the file as it finds it as the
  /// starting point rather than as a change.
  SwappableEnvironment registerEnvironment(
    String path,
    BuiltEnvironment environment, {
    required TextureBytesSource read,
    required EnvironmentBuild build,
    Uint8List? loadedFrom,
  }) {
    final swappable = SwappableEnvironment._(
      path,
      environment,
      read,
      build,
      loadedFrom == null
          ? null
          : _fingerprint(ByteData.sublistView(loadedFrom)),
    );
    if (!enabled) return swappable;
    _environments
      ..removeWhere((SwappableEnvironment e) => e.path == path)
      ..add(swappable);
    _registerExtension();
    return swappable;
  }

  /// Builds [bytes] in place of the environment registered at [path], as a
  /// changed file would: what `ext.flutter3d.assets.put` does for a
  /// panorama. Why it did not take when it did not, or null when it did or
  /// nothing is registered there — [hasEnvironment] tells those two apart.
  Future<String?> putEnvironment(String path, Uint8List bytes) async {
    if (!enabled) return null;
    for (final environment in _environments) {
      if (environment.path == path) {
        return _adoptEnvironment(environment, bytes);
      }
    }
    return null;
  }

  /// Stops watching [environment], for a game letting it go with the level it
  /// lit: a swap after that would prefilter a sky nobody draws and release a
  /// cube already released.
  void forgetEnvironment(SwappableEnvironment environment) => _environments
      .removeWhere((SwappableEnvironment e) => identical(e, environment));

  /// Whether an environment is registered at [path].
  bool hasEnvironment(String path) =>
      _environments.any((SwappableEnvironment e) => e.path == path);

  /// Builds [bytes] for [environment] and puts the result on every
  /// registered scene that was lit by the old one. Why not, when it did not.
  Future<String?> _adoptEnvironment(
    SwappableEnvironment environment,
    Uint8List bytes,
  ) async {
    final BuiltEnvironment? next;
    try {
      next = await environment._build(bytes);
    } on Object catch (error) {
      return '$error';
    }
    if (next == null) {
      return 'the new bytes do not decode into a panorama this device can '
          'hold as a cube';
    }
    final previous = environment.built;
    environment._built.value = next;
    _scenes.removeWhere((WeakReference<Scene> s) => s.target == null);
    for (final reference in _scenes) {
      if (reference.target case final Scene scene
          when identical(scene.environment, previous.texture)) {
        // The level count with the cube: the shader reads roughness against
        // it, and a chain that changed length under the old count would
        // read the wrong lobe.
        scene
          ..environment = next.texture
          ..environmentLevels = next.levels;
      }
    }
    _releaseAfterFrame(previous.texture);
    return null;
  }

  /// Every slot of every material in the registered scenes, and every
  /// scene's environment, that held [previous] now holds [next].
  int _replaceTexture(TextureHandle previous, TextureHandle next) {
    _scenes.removeWhere((WeakReference<Scene> s) => s.target == null);
    final seen = Set<Material>.identity();
    TextureHandle? swapped(TextureHandle? slot) =>
        identical(slot, previous) ? next : slot;
    for (final reference in _scenes) {
      final scene = reference.target;
      if (scene == null) continue;
      scene.environment = swapped(scene.environment);
      scene.root.traverse((SceneNode node) {
        if (node is! MeshNode || !seen.add(node.material)) return;
        node.material
          ..albedo = swapped(node.material.albedo)
          ..normal = swapped(node.material.normal)
          ..metallicRoughness = swapped(node.material.metallicRoughness)
          ..occlusion = swapped(node.material.occlusion)
          ..emissiveTexture = swapped(node.material.emissiveTexture)
          ..lightmap = swapped(node.material.lightmap)
          ..coatMap = swapped(node.material.coatMap)
          ..sheenMap = swapped(node.material.sheenMap);
      });
    }
    return seen.length;
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
  /// A shader's own parameters are named with [parameterField] in front.
  static const Map<String, int> materialFields = <String, int>{
    'baseColor': 4,
    'emissive': 3,
    'emissiveStrength': 1,
    'roughness': 1,
    'metallic': 1,
    'normalScale': 1,
    'alphaCutoff': 1,
  };

  /// What a field of [setMaterial] starts with when it sets one of
  /// `Material.parameters` rather than a field every material has:
  /// `parameters/windStrength` is the `windStrength` a `.fmat` lists under
  /// `parameters` — the editor's own spelling of the same key.
  ///
  /// **Written into the list the material already has, and only that.** The
  /// renderer binds `Material.parameters` afresh every frame, so a number
  /// written in place is drawn on the next one with nothing rebuilt, the way
  /// `Material.polylineViewport` is. A parameter the material was not loaded
  /// with is refused rather than added: the map may be a constant, and a
  /// member the compiled block does not have makes every frame of that
  /// material throw in the encoder. A list of another length is refused for
  /// the same reason — the block's layout is the shader's, not the panel's.
  static const String parameterField = 'parameters/';

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
  /// that many numbers, or a [parameterField] name to as many numbers as
  /// that parameter of every such material has. Throws [ArgumentError]
  /// naming the field otherwise, and keeps nothing of a call it refused.
  /// Returns how many materials took the change.
  int setMaterial(String name, Map<String, Object?> fields) {
    if (!enabled) return 0;
    for (final MapEntry(key: field, :value) in fields.entries) {
      _numbers(field, value);
    }
    for (final material in _materials(only: name)) {
      for (final MapEntry(key: field, :value) in fields.entries) {
        if (field.startsWith(parameterField)) {
          _checkParameter(material, field, _numbers(field, value).length);
        }
      }
    }
    (_overrides[name] ??= <String, Object?>{}).addAll(fields);
    return _applyOverrides(only: name);
  }

  static void _checkParameter(Material material, String field, int count) {
    final parameter = field.substring(parameterField.length);
    final held = material.parameters[parameter];
    if (held == null) {
      final has = material.parameters.keys;
      throw ArgumentError.value(
        field,
        'field',
        '${material.name} has no parameter "$parameter" '
            '(${has.isEmpty ? 'it has none' : 'it has ${has.join(', ')}'}); '
            'one is added by writing it into the material file',
      );
    }
    if (held.length != count) {
      throw ArgumentError.value(
        count,
        field,
        'takes ${held.length} number${held.length == 1 ? '' : 's'}, as '
        '${material.name} was loaded with',
      );
    }
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

  /// Every named material in the registered scenes, or every one called
  /// [only], once however many nodes wear it.
  Set<Material> _materials({String? only}) {
    _scenes.removeWhere((WeakReference<Scene> s) => s.target == null);
    final seen = Set<Material>.identity();
    for (final scene in _scenes) {
      scene.target?.root.traverse((SceneNode node) {
        if (node is! MeshNode) return;
        final name = node.material.name;
        if (name == null || (only != null && name != only)) return;
        seen.add(node.material);
      });
    }
    return seen;
  }

  int _applyOverrides({String? only}) {
    final touched = <Material>[
      for (final material in _materials(only: only))
        if (_overrides.containsKey(material.name)) material,
    ];
    for (final material in touched) {
      for (final MapEntry(key: field, :value)
          in _overrides[material.name]!.entries) {
        _write(material, field, _numbers(field, value));
      }
    }
    return touched.length;
  }

  static List<double> _numbers(String field, Object? value) {
    final parameter = field.startsWith(parameterField);
    final count = materialFields[field];
    if (count == null && !parameter) {
      throw ArgumentError.value(
        field,
        'field',
        'not a material field; there are ${materialFields.keys.join(', ')}, '
            'and $parameterField<name> for a parameter of its shader',
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
    if (numbers.isEmpty ||
        (value is List<Object?> && value.length != numbers.length) ||
        (count != null && numbers.length != count)) {
      throw ArgumentError.value(
        value,
        field,
        count == null
            ? 'takes a number or a list of numbers'
            : 'takes $count number${count == 1 ? '' : 's'}',
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
      default:
        // A parameter. A swapped model whose material no longer carries it,
        // or carries it at another length, is left as the file has it; the
        // override waits for one that does.
        final held =
            material.parameters[field.substring(parameterField.length)];
        if (held != null && held.length == v.length) held.setAll(0, v);
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
      final bytes = await _changed(model, refused);
      if (bytes == null) continue;
      final report = await model._adopt(bytes);
      if (report.refused case final String reason) {
        refused.add('${model.path}: $reason');
      } else {
        models.add(report);
      }
    }
    if (models.isNotEmpty) _applyOverrides();
    final textures = <String>[];
    for (final texture in List<SwappableTexture>.of(_textures)) {
      final bytes = await _changed(texture, refused);
      if (bytes == null) continue;
      if (await _adoptTexture(texture, bytes) case final String reason) {
        refused.add('${texture.path}: $reason');
      } else {
        textures.add(texture.path);
      }
    }
    final environments = <String>[];
    for (final environment in List<SwappableEnvironment>.of(_environments)) {
      final bytes = await _changed(environment, refused);
      if (bytes == null) continue;
      if (await _adoptEnvironment(environment, bytes)
          case final String reason) {
        refused.add('${environment.path}: $reason');
      } else {
        environments.add(environment.path);
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
      models: List<ModelSwapReport>.unmodifiable(models),
      textures: List<String>.unmodifiable(textures),
      environments: List<String>.unmodifiable(environments),
    );
    for (final line in refused) {
      debugPrint('flutter3d: kept the last version that loaded, $line');
    }
    swaps.value++;
    return report;
  }

  /// [file]'s bytes when they differ from the last ones seen, or null when
  /// they do not, cannot be read now, or are the first ones seen — which are
  /// the starting point rather than a change. A read that throws goes into
  /// [refused].
  Future<Uint8List?> _changed(_Watched file, List<String> refused) async {
    final Uint8List? bytes;
    try {
      bytes = await file._read();
    } on Object catch (error) {
      refused.add('${file.path}: could not be read ($error)');
      return null;
    }
    if (bytes == null) return null;
    final fingerprint = _fingerprint(ByteData.sublistView(bytes));
    final seen = file._fingerprint;
    file._fingerprint = fingerprint;
    return seen == null || seen == fingerprint ? null : bytes;
  }

  /// An asset's bytes, or null when the bundle has no such file.
  static Future<Uint8List?> _readAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on FlutterError {
      return null;
    }
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
      final decoded = base64Decode(bytes);
      final report = await instance.put(path, decoded);
      final image = switch (report) {
        null when instance.hasTexture(path) => (
          kind: 'texture',
          put: instance.putTexture,
        ),
        null when instance.hasEnvironment(path) => (
          kind: 'environment',
          put: instance.putEnvironment,
        ),
        _ => null,
      };
      if (image != null) {
        final refused = await image.put(path, decoded);
        if (refused != null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            refused,
          );
        }
        return developer.ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'path': path, image.kind: true}),
        );
      }
      if (report == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          'no model, texture or environment is registered at $path',
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
    this.textures = const <String>[],
    this.environments = const <String>[],
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

  /// The textures whose file changed and whose new texture took the old
  /// one's place.
  final List<String> textures;

  /// The environments whose file changed and whose new cube took the old
  /// one's place.
  final List<String> environments;

  Map<String, Object?> toJson() => <String, Object?>{
    'renderers': renderers,
    'refreshed': refreshed,
    'refused': refused,
    'models': <Object?>[for (final model in models) model.toJson()],
    'textures': textures,
    'environments': environments,
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
final class SwappableModel extends _Watched {
  SwappableModel._(
    super.path,
    this._asset,
    super._read,
    this._build,
    this._device,
    super._fingerprint,
  );

  /// The version drawn now; a new one after each swap.
  ModelAsset get asset => _asset;
  ModelAsset _asset;

  final ModelBuild _build;
  final GraphicsDevice? _device;
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

/// A texture a game draws, kept so a changed image file reaches every
/// material that samples it — see [HotSwap.loadTexture].
///
/// **The handle changes; [texture] follows it.** A swap puts a new texture
/// in place of the old one rather than writing into it, because the new one
/// may be another size and because writing a level over an existing one
/// would leave its smaller mips showing the old picture.
final class SwappableTexture extends _Watched {
  SwappableTexture._(
    super.path,
    TextureHandle texture,
    super._read,
    this._build,
    super._fingerprint,
  ) : _handle = ValueNotifier<TextureHandle>(texture);

  /// The texture drawn now; a new one after each swap.
  TextureHandle get texture => _handle.value;

  /// [texture], for something that holds it outside a material and has to
  /// hear when it changes.
  ValueListenable<TextureHandle> get changes => _handle;

  final ValueNotifier<TextureHandle> _handle;
  final TextureBuild _build;
}

/// An environment a game lights with, kept so a changed panorama file is
/// prefiltered again and reaches every scene lit by it — see
/// [HotSwap.loadEnvironment].
final class SwappableEnvironment extends _Watched {
  SwappableEnvironment._(
    super.path,
    BuiltEnvironment built,
    super._read,
    this._build,
    super._fingerprint,
  ) : _built = ValueNotifier<BuiltEnvironment>(built);

  /// The cube drawn now and its level count; new ones after each swap.
  BuiltEnvironment get built => _built.value;

  /// [built], for something that holds the cube outside a scene — a
  /// weapon's own view, say — and has to hear when it changes.
  ValueListenable<BuiltEnvironment> get changes => _built;

  /// Lights [scene] with it: the cube and its level count, two fields of a
  /// scene that are only right together.
  void applyTo(Scene scene) => scene
    ..environment = built.texture
    ..environmentLevels = built.levels;

  final ValueNotifier<BuiltEnvironment> _built;
  final EnvironmentBuild _build;
}

/// A file something was built from, and what its bytes were the last time a
/// swap looked.
abstract base class _Watched {
  _Watched(this.path, this._read, this._fingerprint);

  /// The file it was loaded from, as the game named it.
  final String path;

  final Future<Uint8List?> Function() _read;
  int? _fingerprint;
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
