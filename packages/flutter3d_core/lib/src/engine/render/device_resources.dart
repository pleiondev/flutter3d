/// What a renderer made on its device, each with how to make it again: the
/// registry a `DeviceLoss.restored` is answered from.
///
/// **A loss spends every handle; a restore gives back the device, empty.**
/// Before this registry the answer was a new renderer, with everything the
/// old one had learned (its steps, its settings, its history, its plugins'
/// places) carried across by hand. Here each resource is registered with a
/// recipe, and `Renderer.recoverFromLoss` runs the recipes again on the
/// device that came back: the renderer stays, and so does every
/// [DeviceResource] somebody holds, with a fresh [DeviceResource.value].
///
/// **Ids are never reused.** A resource's [DeviceResource.id] is the order
/// it was registered in, and one let go of leaves its number behind, so a
/// log line or a capture naming resource 12 names the same thing before and
/// after a restore.
///
/// Caches are not registered: a pipeline or a target the renderer makes
/// when a frame first asks for it is dropped on a restore and made again by
/// the next frame that asks. What is registered is what nothing would ask
/// for again: a fallback texture, a stage resolved once, a plugin's lookup
/// table uploaded at install.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// One resource made on a device, and how to make it again.
///
/// Held by whoever uses it, in place of the handle: [value] is the handle on
/// the device as it is now, and changes when [DeviceResources.recreate] runs.
final class DeviceResource<T extends Object> {
  DeviceResource._(this.id, this.what, this._make, this._onMade, this._value);

  /// The resource's number in its registry, in registration order and never
  /// given to another.
  final int id;

  /// What it is, as a person reads it in a log: `the white fallback`, `the
  /// stage "MeshVertex"`.
  final String what;

  final T Function(GraphicsDevice device) _make;
  final void Function(T value)? _onMade;
  T _value;
  int _generation = 0;
  bool _released = false;

  /// The handle on the device as it is now.
  T get value => _value;

  /// How many times it has been made again since it was registered: nought
  /// before the first restore.
  int get generation => _generation;

  /// Whether [DeviceResources.release] let go of it.
  bool get isReleased => _released;

  void _remake(GraphicsDevice device) {
    _value = _make(device);
    _generation++;
    _onMade?.call(_value);
  }

  @override
  String toString() => 'DeviceResource($id, $what, generation $_generation)';
}

/// What one [DeviceResources.recreate] did: how many resources it made
/// again, and the ones whose recipe threw, with what they threw.
final class DeviceRecreation {
  /// A recreation that made [recreated] resources and could not make
  /// [failed].
  const DeviceRecreation({
    required this.recreated,
    this.failed = const <DeviceRecreationFailure>[],
  });

  /// How many resources were made again.
  final int recreated;

  /// The resources whose recipe threw, in registration order. Each keeps
  /// its old, spent value.
  final List<DeviceRecreationFailure> failed;

  /// Whether every resource was made again.
  bool get isComplete => failed.isEmpty;

  @override
  String toString() =>
      'DeviceRecreation($recreated recreated, ${failed.length} failed)';
}

/// A resource [DeviceResources.recreate] could not make again.
final class DeviceRecreationFailure {
  /// [resource]'s recipe threw [error].
  const DeviceRecreationFailure(this.resource, this.error, this.stackTrace);

  /// The resource, holding its old value.
  final DeviceResource<Object> resource;

  /// What its recipe threw.
  final Object error;

  /// Where.
  final StackTrace stackTrace;

  @override
  String toString() => '${resource.what} could not be made again: $error';
}

/// The resources made on one device, each with its recipe.
///
/// `Renderer.deviceResources` is the renderer's; a plugin that uploads
/// something once at install and wants it back after a restore registers
/// it there too.
final class DeviceResources {
  final List<DeviceResource<Object>> _live = <DeviceResource<Object>>[];
  int _next = 0;

  /// The resources registered and not released, in registration order.
  List<DeviceResource<Object>> get live =>
      List<DeviceResource<Object>>.unmodifiable(_live);

  /// How many resources are registered and not released.
  int get length => _live.length;

  /// Makes [what] on [device] with [make] and registers it, calling
  /// [onMade] with the value now and after every [recreate].
  DeviceResource<T> add<T extends Object>(
    String what,
    GraphicsDevice device,
    T Function(GraphicsDevice device) make, {
    void Function(T value)? onMade,
  }) => adopt(what, make(device), make, onMade: onMade);

  /// Registers [value], already made, with [make] as how to make it again
  /// after a restore, calling [onMade] with it now and after every
  /// [recreate].
  ///
  /// For a resource somebody else handed over: a texture an application
  /// passed in can be adopted with a recipe for the engine's own stand-in,
  /// since what the application drew into it went with the device.
  DeviceResource<T> adopt<T extends Object>(
    String what,
    T value,
    T Function(GraphicsDevice device) make, {
    void Function(T value)? onMade,
  }) {
    final resource = DeviceResource<T>._(_next++, what, make, onMade, value);
    _live.add(resource);
    onMade?.call(value);
    return resource;
  }

  /// Lets go of [resource]: it is no longer made again, and its id is not
  /// given to another. The handle is the caller's to give back to the
  /// device, if the device still has it.
  void release(DeviceResource<Object> resource) {
    if (_live.remove(resource)) resource._released = true;
  }

  /// Makes every registered resource again on [device], in registration
  /// order: what answers a `DeviceLoss.restored`.
  ///
  /// The old handles are dropped, not given back: the device they were made
  /// on spent them. A recipe that throws leaves its resource holding the
  /// old value and is reported in [DeviceRecreation.failed]; the rest are
  /// made regardless.
  DeviceRecreation recreate(GraphicsDevice device) {
    final failed = <DeviceRecreationFailure>[];
    var made = 0;
    for (final resource in List<DeviceResource<Object>>.of(_live)) {
      try {
        resource._remake(device);
        made++;
      } on Object catch (error, stackTrace) {
        failed.add(DeviceRecreationFailure(resource, error, stackTrace));
      }
    }
    return DeviceRecreation(
      recreated: made,
      failed: List<DeviceRecreationFailure>.unmodifiable(failed),
    );
  }
}
