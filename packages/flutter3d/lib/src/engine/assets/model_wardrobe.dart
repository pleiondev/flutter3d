import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

import 'bundle_asset_source.dart';
import 'model_asset.dart';

/// How one model is worn: which file, and how it is fitted to the node that
/// wears it. See [ModelAssetInstantiate.instantiateFitted] for [length],
/// [axis] and [onGround].
final class ModelLook {
  const ModelLook(
    this.file, {
    required this.length,
    this.axis = 2,
    this.onGround = false,
    this.offset,
  });

  /// The asset path, read through whatever source [ModelWardrobe.load] is
  /// given.
  final String file;
  final double length;
  final int axis;
  final bool onGround;

  /// Moved by this after fitting: a ship's keel set a little under the
  /// water, a model whose pivot is not where it balances.
  final Vector3? offset;
}

/// Models loaded once by key and put on any number of nodes, including nodes
/// made before the models have arrived.
///
/// **The shape two games wrote by hand.** A game builds its craft from
/// primitives so it can play at once, loads the model files in the
/// background, and when each arrives replaces the primitives under every
/// node that plays that part, fitted to the size the game already uses. It
/// has to remember which node plays which part, including nodes made while
/// the files were still loading, and forget a node when the thing it drew is
/// gone. [dress] records a node and dresses it if its model is here;
/// [load] fetches every look and dresses every node recorded so far;
/// [forget] drops one. A model that fails to load leaves its nodes as they
/// were, which is the game still playing with its primitives.
///
/// The node dressed is the one whose children are replaced, so it should be
/// one that holds only what is drawn: a bridged component's `visual` node,
/// not the node a bridge moves.
final class ModelWardrobe<K> {
  ModelWardrobe({
    required this.device,
    required this.scene,
    required Map<K, ModelLook> looks,
    this.onDressed,
  }) : looks = Map<K, ModelLook>.unmodifiable(looks);

  final GraphicsDevice device;
  final Scene scene;
  final Map<K, ModelLook> looks;

  /// Called after each node is dressed, with the instance and the key: for
  /// what a game does to a model once it is on, recolouring a part to tell
  /// two roles apart, say.
  final void Function(ModelInstance instance, K key)? onDressed;

  final Map<K, ModelAsset> _assets = <K, ModelAsset>{};
  final Map<SceneNode, K> _worn = <SceneNode, K>{};

  /// Whether [key]'s model has arrived.
  bool has(K key) => _assets.containsKey(key);

  /// How many nodes are recorded, dressed or waiting.
  int get wearers => _worn.length;

  /// Records that [visual] plays [key], and dresses it now if the model is
  /// here. Recording the same node again changes its part.
  void dress(SceneNode visual, K key) {
    _worn[visual] = key;
    _putOn(visual, key);
  }

  /// Stops tracking [visual]; what it wears stays on it.
  void forget(SceneNode visual) => _worn.remove(visual);

  /// Adds an asset for [key] made some other way than [load], and dresses
  /// every node waiting for it: a procedural model, or a test's.
  void put(K key, ModelAsset asset) {
    _assets[key] = asset;
    for (final MapEntry(key: visual, value: wanted) in _worn.entries) {
      if (wanted == key) _putOn(visual, key);
    }
  }

  /// Loads every look that is not loaded yet, one at a time, and dresses
  /// what is waiting for each as it arrives. A file that fails is reported
  /// to [onError] and skipped.
  Future<void> load({
    AssetSource Function(String path) source = BundleAssetSource.new,
    void Function(K key, Object error)? onError,
  }) async {
    for (final MapEntry(key: key, value: look) in looks.entries) {
      if (has(key)) continue;
      try {
        final document = await decodeModelInIsolate(
          ModelLoadRequest(source: source(look.file)),
        );
        put(
          key,
          await ModelAsset.fromDocument(
            document,
            device: device,
            name: look.file,
          ),
        );
      } catch (error) {
        onError?.call(key, error);
      }
    }
  }

  void _putOn(SceneNode visual, K key) {
    final asset = _assets[key];
    final look = looks[key];
    if (asset == null || look == null) return;
    for (final child in visual.children.toList()) {
      child.removeFromParent();
    }
    final instance = asset.instantiateFitted(
      scene,
      length: look.length,
      axis: look.axis,
      onGround: look.onGround,
      parent: visual,
      name: '${visual.name ?? 'node'} model',
    );
    final offset = look.offset;
    if (offset != null) instance.root.translate(offset.x, offset.y, offset.z);
    onDressed?.call(instance, key);
  }
}
