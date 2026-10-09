import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// One component type: where its values live and how they are written down.
///
/// An implementation detail of `EcsWorld`, kept in its own file because it is
/// a data structure the world leans on rather than part of what an entity or a
/// component is.
final class ComponentStore {
  ComponentStore(this.type);

  /// The Dart type stored here, for messages.
  final Type type;

  /// Entity index to component. The generation is checked against the world's
  /// table rather than stored here, so a despawned entity's leftovers are
  /// unreachable even before they are cleaned up.
  final Map<int, Object> values = <int, Object>{};

  /// Entity index to the step its component was last set at, for
  /// `SimQuery.changed`.
  final Map<int, int> changedAt = <int, int>{};

  /// How the component is written; null while it has none.
  ComponentCodec<Object>? codec;

  /// Whether the view reads it in published state.
  bool published = false;

  /// The plugin id that registered it, or `'app'`.
  String declaredBy = 'app';

  /// Why this type is deliberately not saved, when it is not.
  String? excludedBecause;

  /// The name it is written under, when it is written.
  String? get name => codec?.id;

  /// Whether the codec writes data back into a component already there
  /// rather than building one.
  bool get inPlace => codec is InPlaceCodec<Object>;

  bool get isRegistered => codec != null || excludedBecause != null;
}
