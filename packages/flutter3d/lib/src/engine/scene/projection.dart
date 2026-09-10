import 'dart:math' as math;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

/// How a camera maps eye space onto clip space.
///
/// The matrix maths lives inside each implementation rather than in free
/// functions the implementations call: the depth convention is the thing most
/// easily got wrong, and keeping it in one polymorphic place means there is no
/// second copy to drift.
///
/// Every implementation targets a `[0, 1]` NDC depth range, which is the Metal
/// and Vulkan convention rather than OpenGL's `[-1, 1]`. Feeding an OpenGL-style
/// matrix to a device expecting this one puts roughly half the view volume
/// behind the near plane, so the model looks half-eaten or vanishes — with no
/// error reported.
///
/// The device is asked which it wants; see [toDepthRange] and
/// `GraphicsDevice.depthRange`.
///
/// Y is deliberately not flipped. Metal NDC has +Y up while its framebuffer
/// origin is top-left, which already places row 0 at the top of the texture.
/// Negating Y would mirror the image and, because mirroring reverses triangle
/// orientation on screen, make backface culling discard exactly the faces meant
/// to be visible.
///
/// **Open, and it was sealed for no reason this file could name.** A sealed type
/// is a promise that the engine has the full list, which is worth making when
/// something switches over it — nothing here ever did, because the matrix maths
/// is polymorphic and that was the whole design. What sealing bought was a
/// closed set; what it cost was that nobody outside this package could write a
/// projection. A skewed one for a portal is the case that made the point.
///
/// A subclass owes [toMatrix], [near] and [far], and owes them in this file's
/// depth convention: `[0, 1]`, +Y up, Y not flipped. Everything above is the
/// contract, not a description of the two below.
/// `base` rather than merely open: extend it, do not implement it, so that a
/// member added here later is inherited rather than missing. See [Shape].
abstract base class Projection {
  const Projection();

  /// Builds the projection matrix for a given viewport aspect ratio.
  Matrix4 toMatrix(double aspect);

  double get near;
  double get far;

  /// The vertical angle this projection sees, in radians, or null for one that
  /// has no such angle.
  ///
  /// Asked by whatever sizes an object against the frame — `LodGroup` is the
  /// only thing that does — and answered by the projection rather than found
  /// out with an `is` check at the call site. That check was there, it named
  /// [PerspectiveProjection], and everything else fell through to a hardcoded
  /// 45 degrees. A camera whose field of view is dictated by a headset's
  /// runtime would have chosen its levels off a number nobody set, and chosen
  /// them wrongly in the direction that costs: a wider view than 45 degrees
  /// means every object covers less of the frame than the fallback thinks.
  ///
  /// Null where the question does not apply. An orthographic object's size on
  /// screen does not depend on how far away it is, so there is no angle to
  /// give, and a caller that gets null is expected to have handled that case
  /// on its own terms rather than to substitute a number.
  double? get verticalFieldOfView => null;

  /// Projects an eye-space point to NDC.
  ///
  /// The only honest way to assert what a projection actually does, which is why
  /// it lives on the abstraction rather than in test-only code.
  Vector3 projectToNdc(Vector3 eyePosition, {double aspect = 1.0}) {
    final clip = toMatrix(
      aspect,
    ).transform(Vector4(eyePosition.x, eyePosition.y, eyePosition.z, 1.0));
    if (clip.w == 0.0) {
      throw ArgumentError('Point projects onto the camera plane (w == 0).');
    }
    return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);
  }
}

final class PerspectiveProjection extends Projection {
  const PerspectiveProjection({
    this.fovYRadians = math.pi / 4,
    this.near = 0.1,
    this.far = 1000.0,
  }) : assert(
         fovYRadians > 0.0 && fovYRadians < math.pi,
         'fovYRadians is in radians, and a field of view of 180 degrees or '
         'more has no projection. A value like 60 or 90 here is degrees: '
         'multiply by pi / 180.',
       );

  /// Vertical field of view. Vertical rather than horizontal so that widening the
  /// viewport reveals more scene instead of squashing it.
  final double fovYRadians;

  @override
  double? get verticalFieldOfView => fovYRadians;

  @override
  final double near;

  @override
  final double far;

  @override
  Matrix4 toMatrix(double aspect) {
    if (aspect <= 0.0) {
      throw ArgumentError('aspect must be > 0, got $aspect.');
    }
    if (near <= 0.0 || far <= near) {
      throw ArgumentError('Expected 0 < near < far, got near=$near far=$far.');
    }

    final f = 1.0 / math.tan(fovYRadians / 2.0);
    final m = Matrix4.zero();

    // setEntry takes (row, column). The two depth terms below sit in different
    // rows and are easy to transpose by accident; swapping them yields a matrix
    // that maps everything outside the clip volume, i.e. a black viewport with no
    // error anywhere. projection_test.dart pins the mapping.
    m.setEntry(0, 0, f / aspect);
    m.setEntry(1, 1, f);
    m.setEntry(2, 2, far / (near - far));
    m.setEntry(2, 3, (near * far) / (near - far));
    m.setEntry(3, 2, -1.0);

    return m;
  }

  PerspectiveProjection copyWith({
    double? fovYRadians,
    double? near,
    double? far,
  }) => PerspectiveProjection(
    fovYRadians: fovYRadians ?? this.fovYRadians,
    near: near ?? this.near,
    far: far ?? this.far,
  );
}

final class OrthographicProjection extends Projection {
  const OrthographicProjection({
    this.height = 2.0,
    this.near = 0.1,
    this.far = 1000.0,
  });

  /// Vertical extent of the view volume in world units; width follows the aspect.
  final double height;

  @override
  final double near;

  @override
  final double far;

  @override
  Matrix4 toMatrix(double aspect) {
    if (aspect <= 0.0) {
      throw ArgumentError('aspect must be > 0, got $aspect.');
    }
    if (height <= 0.0 || near == far) {
      throw ArgumentError(
        'Degenerate orthographic volume: height=$height near=$near far=$far.',
      );
    }

    final halfHeight = height * 0.5;
    final halfWidth = halfHeight * aspect;

    final m = Matrix4.zero();
    m.setEntry(0, 0, 1.0 / halfWidth);
    m.setEntry(1, 1, 1.0 / halfHeight);
    // Depth maps near -> 0 and far -> 1 for an eye space looking down -Z.
    m.setEntry(2, 2, 1.0 / (near - far));
    m.setEntry(2, 3, near / (near - far));
    m.setEntry(3, 3, 1.0);
    return m;
  }

  OrthographicProjection copyWith({
    double? height,
    double? near,
    double? far,
  }) => OrthographicProjection(
    height: height ?? this.height,
    near: near ?? this.near,
    far: far ?? this.far,
  );
}

/// A frustum whose four sides are given separately, so the axis need not be in
/// the middle of it.
///
/// **What it exists for is a headset.** A perspective projection has one angle
/// and a viewport aspect, and from those the frustum is symmetric by
/// construction. An eye is not: the lens sits off the centre of its half of the
/// display, the two eyes are mirror images of each other, and the runtime hands
/// over four angles per eye that no single field of view can reproduce. Feeding
/// their average to [PerspectiveProjection] gets a picture that looks right on
/// a monitor and, in a headset, disagrees with the other eye by a degree or so
/// — which is not a subtle artefact but the thing that makes people take the
/// device off.
///
/// The four values are **tangents of the angles from the view axis**, which is
/// what `XrFovf` gives after `tan` and what the matrix needs anyway. [tanLeft]
/// and [tanDown] are negative for a frustum that contains its own axis.
///
/// **[toMatrix] ignores its aspect argument, and that is deliberate.** The
/// shape of this frustum is already stated by the four tangents, and the
/// viewport it will be drawn into was chosen to match them; there is nothing
/// left for an aspect ratio to decide. Dividing by one here — which is what the
/// signature invites — would squash the image by the ratio between the eye's
/// own aspect and the viewport's, and a fraction of a degree of that is enough
/// for the two eyes to fight.
final class OffAxisProjection extends Projection {
  const OffAxisProjection({
    required this.tanLeft,
    required this.tanRight,
    required this.tanDown,
    required this.tanUp,
    this.near = 0.1,
    this.far = 1000.0,
  });

  /// From the four angles a runtime states, in radians, as `XrFovf` does.
  factory OffAxisProjection.fromAngles({
    required double left,
    required double right,
    required double down,
    required double up,
    double near = 0.1,
    double far = 1000.0,
  }) => OffAxisProjection(
    tanLeft: math.tan(left),
    tanRight: math.tan(right),
    tanDown: math.tan(down),
    tanUp: math.tan(up),
    near: near,
    far: far,
  );

  /// The frustum a [PerspectiveProjection] of this shape would have, for
  /// comparing the two and for a stereo pair that wants a symmetric fallback.
  factory OffAxisProjection.symmetric({
    double fovYRadians = math.pi / 4,
    double aspect = 1.0,
    double near = 0.1,
    double far = 1000.0,
  }) {
    final up = math.tan(fovYRadians / 2.0);
    final right = up * aspect;
    return OffAxisProjection(
      tanLeft: -right,
      tanRight: right,
      tanDown: -up,
      tanUp: up,
      near: near,
      far: far,
    );
  }

  final double tanLeft;
  final double tanRight;
  final double tanDown;
  final double tanUp;

  @override
  final double near;

  @override
  final double far;

  /// The symmetric angle covering the same vertical extent.
  ///
  /// The view volume is `(tanUp - tanDown) * distance` tall wherever it is cut,
  /// so this is the angle whose half-tangent is half of that — the number a
  /// caller sizing an object against the frame is actually asking for. It is
  /// not the sum of the two angles unless the frustum happens to be symmetric.
  @override
  double? get verticalFieldOfView => 2.0 * math.atan((tanUp - tanDown) / 2.0);

  @override
  Matrix4 toMatrix(double aspect) {
    final width = tanRight - tanLeft;
    final height = tanUp - tanDown;
    if (width <= 0.0 || height <= 0.0) {
      throw ArgumentError(
        'Degenerate frustum: left/right are $tanLeft/$tanRight and down/up are '
        '$tanDown/$tanUp, as tangents. Right must exceed left and up must '
        'exceed down.',
      );
    }
    if (near <= 0.0 || far <= near) {
      throw ArgumentError('Expected 0 < near < far, got near=$near far=$far.');
    }

    final m = Matrix4.zero();
    // The two off-centre terms in column 2 are what makes this off-axis: they
    // shear the frustum so that its axis passes through wherever the four
    // tangents put it rather than through the middle. With a symmetric pair
    // they cancel and the matrix is a perspective one — `projection_test.dart`
    // asserts exactly that, which is the cheapest guard against a sign here.
    m.setEntry(0, 0, 2.0 / width);
    m.setEntry(0, 2, (tanRight + tanLeft) / width);
    m.setEntry(1, 1, 2.0 / height);
    m.setEntry(1, 2, (tanUp + tanDown) / height);
    // Depth, in this file's `[0, 1]` convention. Copied in shape from
    // `PerspectiveProjection` because it is the same mapping and must stay the
    // same mapping: an eye whose depth ran the other way would still draw, and
    // would fight the shadow lookup rather than report anything.
    m.setEntry(2, 2, far / (near - far));
    m.setEntry(2, 3, (near * far) / (near - far));
    m.setEntry(3, 2, -1.0);
    return m;
  }

  OffAxisProjection copyWith({
    double? tanLeft,
    double? tanRight,
    double? tanDown,
    double? tanUp,
    double? near,
    double? far,
  }) => OffAxisProjection(
    tanLeft: tanLeft ?? this.tanLeft,
    tanRight: tanRight ?? this.tanRight,
    tanDown: tanDown ?? this.tanDown,
    tanUp: tanUp ?? this.tanUp,
    near: near ?? this.near,
    far: far ?? this.far,
  );
}

/// [projection] expressed for [range].
///
/// Cameras here build for [DepthRange.zeroToOne] — the Metal and Vulkan
/// convention — and this is the one place that changes. Doubling the depth row
/// and subtracting w turns near-at-0/far-at-1 into near-at-minus-one/far-at-1,
/// which is what OpenGL and WebGL clip against.
///
/// A function rather than a branch inside the renderer, so it can be checked
/// without a device. The failure it prevents is not a crash: an uncorrected
/// matrix on GL draws every object, in the right order, inside the far half of
/// the depth buffer. Half the precision, nothing reported anywhere, and
/// z-fighting on surfaces that were fine on the other backend.
Matrix4 toDepthRange(Matrix4 projection, DepthRange range) {
  if (range == DepthRange.zeroToOne) return projection;
  return Matrix4.identity()
    ..setEntry(2, 2, 2.0)
    ..setEntry(2, 3, -1.0)
    ..multiply(projection);
}

/// [projection] adjusted for where [origin] puts row zero.
///
/// For sampling a texture the engine rendered, not for drawing into one. A
/// shader that looks into a shadow map turns clip space into a uv, and that
/// conversion assumes row zero is at the top — which is true of the texture on
/// a top-left backend and false on a bottom-left one, where the same geometry
/// lands mirrored in memory.
///
/// Negating y in the matrix the *shader* is given produces the mirrored uv
/// without the shader knowing which backend it is on. Doing it here rather than
/// in GLSL keeps one shader for both and keeps the convention in the one place
/// that already knows it.
///
/// Not to be confused with negating y in a matrix used for *drawing*, which
/// would mirror the picture and reverse triangle orientation with it.
Matrix4 toFramebufferOrigin(Matrix4 projection, FramebufferOrigin origin) {
  if (origin == FramebufferOrigin.topLeft) return projection;
  return Matrix4.identity()
    ..setEntry(1, 1, -1.0)
    ..multiply(projection);
}

/// Which way [viewProjection] looks, as a unit vector in world space.
///
/// Read out of the matrix rather than asked of a camera, because the places
/// that need it do not all have one: a frame graph contributor is handed a
/// matrix, and a probe face is a matrix that belongs to no node. The answer is
/// the same either way — the line from the middle of the near plane to the
/// middle of the far one is the view axis of a perspective camera and of an
/// orthographic one alike.
///
/// Insensitive to what [toDepthRange] and [toFramebufferOrigin] did to the
/// matrix: the two points are taken at x = y = 0, where a mirrored y changes
/// nothing, and any two distinct depths along the axis give the same direction.
///
/// The surface buffer measures its depths along this — see `ViewDepth` in
/// `lib/color.glsl` — so whatever writes that buffer and whatever reads it have
/// to agree about it.
Vector3 viewAxisOf(Matrix4 viewProjection, [Vector3? out]) {
  final inverse = Matrix4.copy(viewProjection)..invert();
  final near = inverse * Vector4(0.0, 0.0, 0.0, 1.0) as Vector4;
  final far = inverse * Vector4(0.0, 0.0, 1.0, 1.0) as Vector4;
  final result = out ?? Vector3.zero();
  result.setValues(
    far.x / far.w - near.x / near.w,
    far.y / far.w - near.y / near.w,
    far.z / far.w - near.z / near.w,
  );
  if (result.length2 > 0.0) result.normalize();
  return result;
}
