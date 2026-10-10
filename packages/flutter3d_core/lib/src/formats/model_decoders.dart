/// The formats' side of the plugin host: [ModelDecoders], which fills the
/// `DecoderRegistry` slot, and [AssetSources], the table that turns a path
/// with a scheme into an [AssetSource].
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'model_loader.dart';

/// Makes the [AssetSource] for [path] — the path with its scheme taken off.
typedef AssetSourceFactory = AssetSource Function(String path);

/// Which [AssetSource] a path names, by its scheme.
///
/// **[AssetSource] was already open; what was closed is the path.** A level
/// names `models/crate.glb`, and the loader that reads it decides — the
/// asset bundle, the checkout on disk — with nothing in between a game could
/// add to. A path with a scheme, `pak:models/crate.glb`, now goes to whatever
/// was registered for `pak`: an archive, a network cache, a database. A path
/// without one goes where it always went, to the fallback the caller names.
///
/// **A table rather than a registry the isolate reads**, and that is why it
/// works where a registry of sources would not: the source is made here, on
/// the calling isolate, and what crosses to the one that decodes is the
/// source itself — sendable, as [AssetSource] says it must be.
///
/// A scheme is two or more of lower-case letters, digits, `+`, `-` and `.`,
/// starting with a letter, so a Windows drive (`C:`) is a path and not a
/// scheme.
final class AssetSources {
  /// A table holding [schemes].
  AssetSources([Map<String, AssetSourceFactory> schemes = const {}]) {
    schemes.forEach(add);
  }

  final Map<String, AssetSourceFactory> _byScheme =
      <String, AssetSourceFactory>{};

  static final RegExp _scheme = RegExp(r'^([a-z][a-z0-9+.\-]+):');

  /// The schemes known, in the order they were added.
  List<String> get schemes => List<String>.unmodifiable(_byScheme.keys);

  /// The scheme of [path], or null when it has none.
  static String? schemeOf(String path) => _scheme.firstMatch(path)?.group(1);

  /// Makes [make] answer for [scheme]. Throws an [ArgumentError] for a
  /// scheme that is not one, and for one already taken.
  void add(String scheme, AssetSourceFactory make) {
    if (schemeOf('$scheme:') != scheme) {
      throw ArgumentError.value(
        scheme,
        'scheme',
        'a scheme is two or more lower-case letters, digits, "+", "-" and '
            '".", starting with a letter',
      );
    }
    if (_byScheme.containsKey(scheme)) {
      throw ArgumentError.value(scheme, 'scheme', 'already has a source');
    }
    _byScheme[scheme] = make;
  }

  /// Takes [scheme] out again. Nothing for a scheme nobody added.
  void remove(String scheme) => _byScheme.remove(scheme);

  /// Whether [path]'s scheme has a source here.
  bool handles(String path) => _byScheme.containsKey(schemeOf(path));

  /// The source for [path]: its scheme's, given the path after `scheme:`,
  /// or [fallback]'s, given the whole path, when it has no scheme known
  /// here.
  ///
  /// **An unknown scheme goes to [fallback] rather than throwing**, because
  /// `https:` is a scheme too and the fallback may know it; a fallback that
  /// does not will say so when it reads.
  AssetSource resolve(String path, {required AssetSourceFactory fallback}) {
    final scheme = schemeOf(path);
    final make = scheme == null ? null : _byScheme[scheme];
    return make == null
        ? fallback(path)
        : make(path.substring(scheme!.length + 1));
  }
}

/// Model and material decoders, and the schemes a path names a source by:
/// the slot a plugin that reads a format fills.
///
/// Filled the way `RenderStepRegistry` is, by a type that knows the formats:
/// [ModelDecoders] here (model decoders and asset-source schemes) and
/// `Decoders` in `flutter3d`, which adds material decoders. A plugin asks for
/// `host.registry<ModelDecoders>()` or `host.registry<Decoders>()`.
///
/// **Declared by the package that fills it.** It was a marker in
/// `flutter3d_plugin_api` until 1.0.0-rc.1, which named a slot nothing in
/// the contract used.
abstract base class DecoderRegistry extends PluginRegistry {
  const DecoderRegistry();
}

/// The [DecoderRegistry] the formats fill: the model decoders and the asset
/// sources plugins bring.
///
/// **What a plugin that reads a format is handed.** Its `install` asks for
/// this type, `host.registry<ModelDecoders>()`, and gets a view scoped to
/// it: everything added through it is withdrawn when the plugin is switched
/// off, and ordered by the plugin's place in the install order — the
/// application's own first.
///
/// ```dart
/// void install(PluginHost host) {
///   host.registry<ModelDecoders>()
///     ..addModelDecoder(const PlyDecoder())
///     ..addSource('pak', PakSource.new);
/// }
/// ```
///
/// **The request still carries the decoders.** Decoding runs on a background
/// isolate, which does not share this registry — see
/// [ModelLoadRequest.decoders]. So a loader asks [withDecoders] for the
/// request it sends: the request's own decoders first, as before, then the
/// registered ones. A decoder registered here travels with every request
/// made that way, and must be sendable for the same reason.
///
/// The engine hands it to the plugin host among its registries:
/// `EngineLoop(registries: [decoders, ...])`. `flutter3d`'s `Decoders`
/// extends this with material decoders; one engine has one of the two.
base class ModelDecoders extends DecoderRegistry {
  /// An empty registry, for the application to add to and hand the host.
  ModelDecoders() : _store = _DecoderStore(), scope = null;

  /// [root] as [scope]'s plugin sees it — what [forPlugin] returns, and what
  /// a subclass's own [forPlugin] builds its view on.
  ModelDecoders.scoped(ModelDecoders root, PluginScope this.scope)
    : _store = root._store;

  final _DecoderStore _store;

  /// The plugin this view files registrations under; null for the
  /// application's.
  final PluginScope? scope;

  /// Who registrations made through this view belong to, for a refusal.
  String get owner {
    final id = scope?.manifest.id;
    return id == null ? 'the application' : 'plugin "$id"';
  }

  /// The registered model decoders, the application's first, then each
  /// plugin's in install order.
  List<ModelDecoder> get decoders => List<ModelDecoder>.unmodifiable(
    <ModelDecoder>[for (final e in _store.ordered(_store.models)) e.value],
  );

  /// The registered sources, as one table.
  AssetSources get sources => AssetSources(<String, AssetSourceFactory>{
    for (final e in _store.ordered(_store.sources)) e.key: e.value,
  });

  /// Adds [decoder], asked after a request's own and before the built-in
  /// readers.
  Registration addModelDecoder(ModelDecoder decoder) =>
      _track(_store.models, _Entry<ModelDecoder>('', decoder, this));

  /// Makes [make] the source for paths with [scheme]. Throws an
  /// [ArgumentError] for a scheme that is not one, and for one somebody has
  /// already added, naming them.
  Registration addSource(String scheme, AssetSourceFactory make) {
    AssetSources().add(scheme, make);
    for (final entry in _store.sources) {
      if (entry.key != scheme) continue;
      throw ArgumentError.value(
        scheme,
        'scheme',
        'already has a source, added by ${entry.owner}',
      );
    }
    return _track(
      _store.sources,
      _Entry<AssetSourceFactory>(scheme, make, this),
    );
  }

  /// [request] with the registered decoders after its own: what a loader
  /// sends to the isolate that decodes.
  ModelLoadRequest withDecoders(ModelLoadRequest request) => ModelLoadRequest(
    source: request.source,
    format: request.format,
    layout: request.layout,
    objNormals: request.objNormals,
    stlNormals: request.stlNormals,
    decoders: List<ModelDecoder>.unmodifiable(<ModelDecoder>[
      ...request.decoders,
      ...decoders,
    ]),
  );

  /// The source for [path]: a registered scheme's, or [fallback]'s.
  AssetSource sourceFor(String path, {required AssetSourceFactory fallback}) =>
      sources.resolve(path, fallback: fallback);

  /// Puts [entry] in [into] and hands back the way to take it out, tracked
  /// by this view's plugin.
  Registration _track<T>(List<_Entry<T>> into, _Entry<T> entry) {
    entry.sequence = _store.sequence++;
    into.add(entry);
    final registration = Registration(() => into.remove(entry));
    scope?.track(registration);
    return registration;
  }

  @override
  ModelDecoders forPlugin(PluginScope scope) =>
      ModelDecoders.scoped(this, scope);
}

/// What a registry and all its scoped views share.
final class _DecoderStore {
  final List<_Entry<ModelDecoder>> models = <_Entry<ModelDecoder>>[];
  final List<_Entry<AssetSourceFactory>> sources =
      <_Entry<AssetSourceFactory>>[];
  int sequence = 0;

  /// [entries] the application's first, then each plugin's by rank, each
  /// in the order it was added.
  List<_Entry<T>> ordered<T>(List<_Entry<T>> entries) =>
      List<_Entry<T>>.of(entries)..sort(_Entry.compare);
}

final class _Entry<T> {
  _Entry(this.key, this.value, ModelDecoders by)
    : scope = by.scope,
      owner = by.owner;

  final String key;
  final T value;
  final PluginScope? scope;
  final String owner;
  int sequence = 0;

  int get rank => scope?.rank ?? -1;

  static int compare(_Entry<Object?> a, _Entry<Object?> b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}
