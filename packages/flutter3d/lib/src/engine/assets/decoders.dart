import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginScope;

import 'material_loader.dart';

/// [ModelDecoders] with material decoders beside the model ones: the
/// `DecoderRegistry` an application that draws hands the plugin host.
///
/// **One registry for every reader a plugin brings.** A plugin with a model
/// format and a material format asks for this type,
/// `host.registry<Decoders>()`; one with only a model format may ask for
/// `ModelDecoders`, and finds this. Everything added through either is
/// withdrawn when the plugin is switched off.
///
/// ```dart
/// void install(PluginHost host) {
///   host.registry<Decoders>()
///     ..addModelDecoder(const PlyDecoder())
///     ..addMaterialDecoder(const StudioMaterialDecoder());
/// }
/// ```
///
/// **The per-call lists still come first.** [withMaterialDecoders] puts a
/// call's own decoders before the registered ones, as
/// [ModelDecoders.withDecoders] does for a model request, so a loader that
/// passes `decoders:` today reads exactly what it read.
final class Decoders extends ModelDecoders {
  /// An empty registry, for the application to add to and hand the host.
  Decoders() : _materials = <_Material>[], _sequence = <int>[0];

  Decoders._scoped(Decoders super.root, super.scope)
    : _materials = root._materials,
      _sequence = root._sequence,
      super.scoped();

  final List<_Material> _materials;

  /// The next sequence number, shared by every view of one registry.
  final List<int> _sequence;

  /// The registered material decoders, the application's first, then each
  /// plugin's in install order.
  List<MaterialDecoder> get materialDecoders =>
      List<MaterialDecoder>.unmodifiable(<MaterialDecoder>[
        for (final m in List<_Material>.of(_materials)..sort(_Material.compare))
          m.decoder,
      ]);

  /// Adds [decoder], asked after a call's own and before the built-in
  /// `.fmat` reader.
  Registration addMaterialDecoder(MaterialDecoder decoder) {
    final entry = _Material(decoder, scope, _sequence[0]++);
    _materials.add(entry);
    final registration = Registration(() => _materials.remove(entry));
    scope?.track(registration);
    return registration;
  }

  /// [decoders] — one call's own — with the registered ones after them:
  /// what to pass to `loadMaterial` and `loadMaterialDocument`.
  List<MaterialDecoder> withMaterialDecoders([
    List<MaterialDecoder> decoders = const <MaterialDecoder>[],
  ]) => List<MaterialDecoder>.unmodifiable(<MaterialDecoder>[
    ...decoders,
    ...materialDecoders,
  ]);

  @override
  Decoders forPlugin(PluginScope scope) => Decoders._scoped(this, scope);
}

final class _Material {
  _Material(this.decoder, this.scope, this.sequence);

  final MaterialDecoder decoder;
  final PluginScope? scope;
  final int sequence;

  int get rank => scope?.rank ?? -1;

  static int compare(_Material a, _Material b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}
