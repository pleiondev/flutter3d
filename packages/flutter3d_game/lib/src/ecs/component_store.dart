/// One component type: where its values live and how they are written down.
///
/// An implementation detail of [EcsWorld], kept in its own file because it is
/// a data structure the world leans on rather than part of what an entity or a
/// component is.
final class ComponentStore {
  ComponentStore();

  /// Entity index to component. The generation is checked against the world's
  /// table rather than stored here, so a despawned entity's leftovers are
  /// unreachable even before they are cleaned up.
  final Map<int, Object> values = <int, Object>{};

  String? name;
  Object? Function(Object value)? encode;

  /// Builds the component from data. For components that are values.
  ///
  /// May answer null: see [EcsWorld.register].
  Object? Function(Object? data)? decode;

  /// Writes data back into the component that is already there. For components
  /// that own something live — a body in a collision world, a brain that is
  /// code as much as data.
  void Function(Object value, Object? data)? restoreInPlace;

  /// Why this type is deliberately not saved, when it is not.
  String? excludedBecause;

  bool get isRegistered => name != null || excludedBecause != null;
}
