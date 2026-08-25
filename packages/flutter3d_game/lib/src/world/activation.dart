import 'package:flutter3d_physics/flutter3d_physics.dart';

/// Who is switching something on, and what they are carrying.
///
/// Passed by value down the whole chain — a trigger volume hands it to the lift
/// it calls, which hands it to whatever that lift relays to — so a locked door
/// three relays away still knows whose keys to check.
final class Activation {
  const Activation({
    this.by,
    this.keys = const <String>{},
  });

  /// The body that did it, when there was one. Null for a mechanism switched
  /// on by another mechanism rather than by somebody walking into it.
  final Collider? by;

  /// What that body is carrying. A door reads it; nothing else does yet.
  final Set<String> keys;
}
