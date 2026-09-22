/// How a decoded camera projects — glTF's own two, perspective and
/// orthographic, and no others: the core specification defines exactly
/// these two `camera.type` values.
///
/// **Not `Projection`, the engine's own type in `flutter3d`.** This package
/// cannot depend on the engine (formats sits below it), and the two answer
/// different questions besides: `Projection` builds a matrix for a given
/// aspect ratio at render time, while this is what the *file* said —
/// `aspectRatio` may be absent on purpose, meaning "follow the viewport",
/// which `Projection` has no way to represent since it is always handed a
/// concrete one.
sealed class ModelCameraProjection {
  const ModelCameraProjection();
}

/// `camera.perspective` — a field of view and a near plane, an aspect ratio
/// and a far plane that both may be absent.
final class ModelPerspectiveCamera extends ModelCameraProjection {
  const ModelPerspectiveCamera({
    required this.yfov,
    this.aspectRatio,
    required this.znear,
    this.zfar,
  });

  /// Vertical field of view, in radians.
  final double yfov;

  /// Absent means the camera follows the viewport's own aspect ratio,
  /// glTF's own documented meaning for the key being missing — not the
  /// same as `1.0`, which is a camera that asks for a square frame and
  /// stays one.
  final double? aspectRatio;

  final double znear;

  /// Absent means an infinite far plane, which the specification allows
  /// only for a perspective camera — an orthographic one requires both
  /// planes finite, which is why [ModelOrthographicCamera.zfar] is not
  /// nullable the way this one is.
  final double? zfar;
}

/// `camera.orthographic` — a view volume's own half-extents, both planes
/// required.
final class ModelOrthographicCamera extends ModelCameraProjection {
  const ModelOrthographicCamera({
    required this.xmag,
    required this.ymag,
    required this.znear,
    required this.zfar,
  });

  /// Half the view volume's width, in world units.
  final double xmag;

  /// Half the view volume's height.
  final double ymag;

  final double znear;
  final double zfar;
}

/// A camera decoded from glTF's own `cameras`, or held for a writer to
/// encode into it — `fmt-28`'s own row, the other half beside
/// [ModelLight].
final class ModelCamera {
  const ModelCamera({required this.projection, this.name});

  final ModelCameraProjection projection;
  final String? name;

  @override
  String toString() => 'ModelCamera(${name ?? 'unnamed'}, $projection)';
}
