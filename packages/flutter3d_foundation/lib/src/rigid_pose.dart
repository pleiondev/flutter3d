/// Where a rigid thing is and which way it is turned.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show DocumentFormatException;
import 'package:vector_math/vector_math.dart';

import 'formats.dart' show DocumentFormatException;

/// Where a rigid thing is and which way it is turned: a position in metres
/// and an orientation, in whatever space the one who hands it over states.
///
/// **One pose for the engine.** A tracked head, an XR controller, a bone a
/// native ragdoll writes and an element's body were five shapes of the same
/// two numbers; each is this now, so a pose read from one place is handed to
/// another as it is. The shape both XR runtimes hand over (OpenXR's
/// `XrPosef`, WebXR's `XRRigidTransform`).
///
/// Immutable: the vectors are copied in and out, so a pose kept is never
/// changed by whoever made it.
final class RigidPose {
  /// [position] in metres, turned by [orientation].
  RigidPose({required Vector3 position, required Quaternion orientation})
    : _position = position.clone(),
      _orientation = orientation.clone();

  /// At the space's origin, turned nowhere.
  RigidPose.identity()
    : _position = Vector3.zero(),
      _orientation = Quaternion.identity();

  /// The pose [components] wrote: the position, then the quaternion as x,
  /// y, z, w. Throws a [DocumentFormatException] for a list that is not
  /// seven numbers.
  factory RigidPose.fromComponents(List<double> components) {
    if (components.length != 7) {
      throw DocumentFormatException(
        'a pose is seven numbers (a position and a quaternion), not '
        '${components.length}',
      );
    }
    return RigidPose(
      position: Vector3(components[0], components[1], components[2]),
      orientation: Quaternion(
        components[3],
        components[4],
        components[5],
        components[6],
      ),
    );
  }

  final Vector3 _position;
  final Quaternion _orientation;

  /// Where it is, in metres.
  Vector3 get position => _position.clone();

  /// Which way it is turned, a unit quaternion.
  Quaternion get orientation => _orientation.clone();

  /// The seven numbers it is: the position in metres, then the quaternion
  /// as x, y, z, w.
  List<double> get components => <double>[
    _position.x,
    _position.y,
    _position.z,
    _orientation.x,
    _orientation.y,
    _orientation.z,
    _orientation.w,
  ];

  @override
  bool operator ==(Object other) =>
      other is RigidPose &&
      other._position == _position &&
      other._orientation.x == _orientation.x &&
      other._orientation.y == _orientation.y &&
      other._orientation.z == _orientation.z &&
      other._orientation.w == _orientation.w;

  @override
  int get hashCode => Object.hash(
    _position.x,
    _position.y,
    _position.z,
    _orientation.x,
    _orientation.y,
    _orientation.z,
    _orientation.w,
  );

  @override
  String toString() => 'RigidPose($_position, $_orientation)';
}
