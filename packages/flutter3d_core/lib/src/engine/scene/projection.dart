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
/// contract, not a description of the ones below.
///
/// `base` rather than merely open: extend it, do not implement it, so that a
/// member added here later is inherited rather than missing — the same choice
/// the geometry layer's `Shape` makes.
abstract base class Projection {
  const Projection();

  /// Builds the projection matrix for a given viewport aspect ratio.
  Matrix4 toMatrix(double aspect);

  /// Distance from the eye to the near clip plane, in metres.
  double get near;

  /// Distance from the eye to the far clip plane, in metres.
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

/// A pinhole camera's frustum: a vertical angle, a near plane and a far one.
///
/// **The far plane may be at infinity.** `far: double.infinity` — or
/// [PerspectiveProjection.infinite] — builds the limit of the matrix as the
/// far plane recedes: everything in front of the near plane projects inside
/// the depth range, and nothing is cut off however far it is. That costs
/// nothing a finite plane would keep under the renderer's reversed depth,
/// where precision follows distance rather than being spent near the eye,
/// and it is what a planet, a sky full of ships or a flight over a valley
/// wants: no far plane to choose, and no horizon that pops in. Under the
/// ordinary convention it costs a little precision at every distance, which
/// is the trade every infinite projection makes.
///
/// What needs a number where the plane is — the shadow cascades, the light
/// clusters, the depth pyramid — takes the renderer's own stand-in for an
/// infinite one; see `withDepthPlanes`.
final class PerspectiveProjection extends Projection {
  const PerspectiveProjection({
    this.fovY = math.pi / 4,
    this.near = 0.1,
    this.far = 1000.0,
  }) : assert(
         fovY > 0.0 && fovY < math.pi,
         'fovYRadians is in radians, and a field of view of 180 degrees or '
         'more has no projection. A value like 60 or 90 here is degrees: '
         'multiply by pi / 180.',
       );

  /// A projection with no far plane: [far] is `double.infinity`.
  ///
  /// The same as passing `far: double.infinity`, named so that a reader
  /// sees the choice rather than a number that happens to be infinite.
  const PerspectiveProjection.infinite({
    this.fovY = math.pi / 4,
    this.near = 0.1,
  }) : far = double.infinity,
       assert(
         fovY > 0.0 && fovY < math.pi,
         'fovYRadians is in radians, and a field of view of 180 degrees or '
         'more has no projection. A value like 60 or 90 here is degrees: '
         'multiply by pi / 180.',
       );

  /// Vertical field of view. Vertical rather than horizontal so that widening the
  /// viewport reveals more scene instead of squashing it.
  /// In radians.
  final double fovY;

  /// [fovY], in radians.
  @override
  double? get verticalFieldOfView => fovY;

  /// Distance from the eye to the near clip plane, in metres.
  @override
  final double near;

  /// Distance from the eye to the far clip plane, in metres.
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

    final f = 1.0 / math.tan(fovY / 2.0);
    final m = Matrix4.zero();

    // setEntry takes (row, column). The two depth terms below sit in different
    // rows and are easy to transpose by accident; swapping them yields a matrix
    // that maps everything outside the clip volume, i.e. a black viewport with no
    // error anywhere. projection_test.dart pins the mapping.
    m.setEntry(0, 0, f / aspect);
    m.setEntry(1, 1, f);
    _setDepthRow(m, near, far);
    m.setEntry(3, 2, -1.0);

    return m;
  }

  PerspectiveProjection copyWith({double? fovY, double? near, double? far}) =>
      PerspectiveProjection(
        fovY: fovY ?? this.fovY,
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

  /// Distance from the eye to the near clip plane, in metres.
  @override
  final double near;

  /// Distance from the eye to the far clip plane, in metres.
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
    double fovY = math.pi / 4,
    double aspect = 1.0,
    double near = 0.1,
    double far = 1000.0,
  }) {
    final up = math.tan(fovY / 2.0);
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

  /// Tangent of the angle from the view axis to the left edge, negative to the
  /// left: offset over distance, a unitless ratio.
  final double tanLeft;

  /// Tangent of the angle from the view axis to the right edge: offset over
  /// distance, a unitless ratio.
  final double tanRight;

  /// Tangent of the angle from the view axis to the bottom edge, negative
  /// below: offset over distance, a unitless ratio.
  final double tanDown;

  /// Tangent of the angle from the view axis to the top edge: offset over
  /// distance, a unitless ratio.
  final double tanUp;

  /// Distance from the eye to the near clip plane, in metres.
  @override
  final double near;

  /// Distance from the eye to the far clip plane, in metres.
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
    // Depth, in this file's `[0, 1]` convention, and from the one function
    // `PerspectiveProjection` builds its own with: it is the same mapping and
    // must stay the same mapping. An eye whose depth ran the other way would
    // still draw, and would fight the shadow lookup rather than report
    // anything. A far plane at infinity is that function's to handle.
    _setDepthRow(m, near, far);
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

/// One tile of a larger virtual frame, out of [tilesX] × [tilesY] — `pro-
/// eng-04`'s own row: a tiled screenshot at a resolution no single render
/// target holds, stitched afterwards from tiles rendered one at a time.
///
/// **A crop of NDC space, not a narrower frustum computed from [base]'s own
/// angles.** Every [Projection] already maps its full view volume to the
/// cube `[-1, 1]³`; a tile is exactly the sub-square of that cube [tileX],
/// [tileY] names, linearly rescaled back out to fill `[-1, 1]` on its own.
/// That holds for [base] whatever concrete projection it is — perspective,
/// orthographic, already off-axis — because it never asks [base] anything
/// beyond the one matrix every [Projection] already builds; recomputing a
/// narrower field of view would have to special-case each subclass's own
/// parameters instead, and would still land on the same matrix.
///
/// [aspect] passed to [toMatrix] is the *stitched frame's* own aspect ratio,
/// not one tile's — a tile is not rendered as though it were the whole
/// picture, it is rendered as the piece of the whole picture it is, and
/// [base] has to be handed the whole picture's shape to place that piece
/// correctly. A caller rendering `tilesX × tilesY` tiles at `width ×
/// height` each passes `(width * tilesX) / (height * tilesY)` here for
/// every one of them.
final class TiledProjection extends Projection {
  const TiledProjection(
    this.base, {
    required this.tileX,
    required this.tileY,
    required this.tilesX,
    required this.tilesY,
  });

  final Projection base;

  /// Which tile this is, zero-based: `tileX` across, `tileY` down.
  final int tileX;
  final int tileY;

  /// The grid this tile is one square of.
  final int tilesX;
  final int tilesY;

  /// [base]'s near clip distance, in metres.
  @override
  double get near => base.near;

  /// [base]'s far clip distance, in metres.
  @override
  double get far => base.far;

  /// [base]'s own field of view over the whole stitched frame — a tile's own
  /// share of it is narrower, but nothing here asks for that number, and
  /// answering with it would silently disagree with what a caller measuring
  /// the whole picture already expects from [base].
  @override
  double? get verticalFieldOfView => base.verticalFieldOfView;

  @override
  Matrix4 toMatrix(double aspect) {
    // [tileX] runs the way NDC x already does — left to right — so its own
    // low corner is `-1 + 2 * tileX / tilesX` and [offsetX] solves
    // `scale * low + offset == -1` directly. [tileY] runs the other way:
    // down, the way an image's own rows do, while NDC y runs up (this
    // file's own convention: Y is never flipped). Tile row 0's own *high*
    // y-corner is `1 - 2 * tileY / tilesY`, and solving `scale * high +
    // offset == 1` for that gives [offsetY]'s own, differently-signed
    // formula. Neither needs trigonometry: both are a linear crop of a
    // cube, read in the direction each axis actually runs.
    final scaleX = tilesX.toDouble();
    final scaleY = tilesY.toDouble();
    final offsetX = (tilesX - 1 - 2 * tileX).toDouble();
    // The sign here is not [offsetX]'s own, mirrored — it is [tileY]'s own
    // direction against NDC y read the other way round. [tileY] counts down
    // the way an image's own rows do, `0` at the top; NDC y counts up, `+1`
    // at the top. The same "solve `scale * low + offset == -1`" [offsetX]
    // used, worked out for a tile whose low *row* is its high *y*, lands
    // here rather than at [offsetX]'s own formula with `tileY` swapped in.
    final offsetY = (2 * tileY - (tilesY - 1)).toDouble();

    final crop = Matrix4.identity()
      ..setEntry(0, 0, scaleX)
      ..setEntry(0, 3, offsetX)
      ..setEntry(1, 1, scaleY)
      ..setEntry(1, 3, offsetY);
    return crop * base.toMatrix(aspect);
  }
}

/// Any rectangle of a larger virtual frame — `N8`'s photo capture.
///
/// [TiledProjection]'s crop of NDC space, with the rectangle given directly
/// rather than as a square of a grid: [left], [top], [right] and [bottom] are
/// fractions of the whole frame's width and height, rows counting down from
/// the top as an image's do. They may run outside `[0, 1]`, and that is the
/// point of the class: a photo tile is drawn with a margin of the picture
/// around it on every side — past the frame's own edge, for the outer tiles —
/// so a blur reaching across a tile's edge has something real to read there,
/// and the margin is cropped away afterwards.
///
/// **The whole frame's aspect is held here, and the one [toMatrix] is handed
/// is ignored.** The renderer passes the viewport's own, which for a tile is
/// the tile's — and a tile with a margin round it is never the shape of the
/// frame. [TiledProjection] asks its caller to pass the frame's aspect
/// instead, which the renderer has no way to do.
final class CropProjection extends Projection {
  const CropProjection(
    this.base, {
    required this.frameAspect,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final Projection base;

  /// Width over height of the whole frame the rectangle is a piece of.
  final double frameAspect;

  /// The rectangle's left edge, as a fraction of the whole frame's width from
  /// its left.
  final double left;

  /// The rectangle's top edge, as a fraction of the whole frame's height from
  /// its top.
  final double top;

  /// The rectangle's right edge, as a fraction of the whole frame's width from
  /// its left.
  final double right;

  /// The rectangle's bottom edge, as a fraction of the whole frame's height
  /// from its top.
  final double bottom;

  /// [base]'s near clip distance, in metres.
  @override
  double get near => base.near;

  /// [base]'s far clip distance, in metres.
  @override
  double get far => base.far;

  /// [base]'s vertical field of view, in radians.
  @override
  double? get verticalFieldOfView => base.verticalFieldOfView;

  @override
  Matrix4 toMatrix(double aspect) {
    if (right <= left || bottom <= top) {
      throw ArgumentError(
        'Degenerate crop: left/right are $left/$right and top/bottom are '
        '$top/$bottom; a crop needs some width and some height.',
      );
    }
    // The rectangle in NDC: x runs as the fractions do, y the other way.
    final x0 = -1.0 + 2.0 * left;
    final x1 = -1.0 + 2.0 * right;
    final y0 = 1.0 - 2.0 * bottom;
    final y1 = 1.0 - 2.0 * top;
    final crop = Matrix4.identity()
      ..setEntry(0, 0, 2.0 / (x1 - x0))
      ..setEntry(0, 3, -(x1 + x0) / (x1 - x0))
      ..setEntry(1, 1, 2.0 / (y1 - y0))
      ..setEntry(1, 3, -(y1 + y0) / (y1 - y0));
    return crop * base.toMatrix(frameAspect);
  }
}

/// [base] moved a fraction of a pixel across the screen — `R1`.
///
/// The same crop of NDC space [TiledProjection] makes, with a scale of one:
/// a translation added after the projection, so every projection, off-axis
/// and orthographic included, is jittered by the same amount on screen. The
/// offset is in NDC units, where a pixel of a frame `width` wide is
/// `2 / width`; [JitteredProjection.frame] does that conversion.
final class JitteredProjection extends Projection {
  const JitteredProjection(this.base, {required this.dx, required this.dy});

  /// Frame [frame]'s offset from a Halton(2, 3) sequence of [length], for a
  /// target [width] × [height] pixels.
  factory JitteredProjection.frame(
    Projection base, {
    required int frame,
    required int length,
    required int width,
    required int height,
  }) {
    final (x, y) = jitterOffset(frame, length);
    return JitteredProjection(base, dx: 2.0 * x / width, dy: 2.0 * y / height);
  }

  final Projection base;

  /// The offset in NDC units.
  final double dx;

  /// The vertical offset in NDC units, where the frame is two high.
  final double dy;

  /// [base]'s near clip distance, in metres.
  @override
  double get near => base.near;

  /// [base]'s far clip distance, in metres.
  @override
  double get far => base.far;

  /// [base]'s vertical field of view, in radians.
  @override
  double? get verticalFieldOfView => base.verticalFieldOfView;

  @override
  Matrix4 toMatrix(double aspect) {
    final shift = Matrix4.identity()
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
    return shift * base.toMatrix(aspect);
  }
}

/// Frame [frame]'s sub-pixel offset, in pixels within `[-0.5, 0.5)`, from a
/// Halton(2, 3) sequence that repeats every [length] frames — `R1`.
///
/// Counted from one, as the sequence usually is: its first point, (0, 0), is
/// the pixel centre on both axes, and a cycle that spent a frame there would
/// weight the centre twice.
(double, double) jitterOffset(int frame, int length) {
  final index = frame % (length < 1 ? 1 : length) + 1;
  return (_halton(index, 2) - 0.5, _halton(index, 3) - 0.5);
}

double _halton(int index, int base) {
  var fraction = 1.0;
  var result = 0.0;
  for (var i = index; i > 0; i ~/= base) {
    fraction /= base;
    result += fraction * (i % base);
  }
  return result;
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

/// [projection] with its depth turned round: the near plane at one and the
/// far plane at nought — reversed depth.
///
/// `z' = w - z`, which is its own inverse: applied twice it gives back
/// [projection]. Works on any matrix in this file's `[0, 1]` convention,
/// orthographic and oblique ones included, because it touches only the
/// depth row. A pass drawn through the result clears its depth to nought
/// and keeps the *greater* of two depths; see
/// `RenderSettings.reversedDepth`.
///
/// **Why anybody would.** A perspective divide crowds depth towards the far
/// end, and a float crowds its precision towards nought. Stored the ordinary
/// way round, both pile up at the far plane and the distance is left with
/// almost nothing; reversed, one undoes the other, and depth keeps roughly
/// the same relative precision from the near plane to the horizon. That is
/// only true where clip depth is `[0, 1]` and the depth buffer is a float —
/// `DeviceFeature.reversedDepth` — and harmless elsewhere.
///
/// For a perspective matrix [withDepthPlanes] gives the same answer worked
/// out from the planes rather than by a subtraction of nearly equal numbers,
/// which is the one to prefer when the planes are known.
Matrix4 toReversedDepth(Matrix4 projection) => Matrix4.identity()
  ..setEntry(2, 2, -1.0)
  ..setEntry(2, 3, 1.0)
  ..multiply(projection);

/// [projection] with its depth row rebuilt for a [near] and a [far] plane —
/// [far] may be `double.infinity` — and turned round when [reversed]; or
/// null when [projection] is not one whose depth row can be rebuilt.
///
/// **What can be rebuilt is a perspective matrix whose depth depends on
/// depth alone**: a bottom row of `(0, 0, -1, 0)` and nothing in the depth
/// row's first two columns. [PerspectiveProjection] and [OffAxisProjection]
/// build those, and the crops and the jitter in this file keep them, since
/// they move x and y only. An orthographic matrix has another bottom row and
/// an oblique near plane — `obliqueNearPlane` — tilts the depth row, and
/// both come back null: there is no pair of planes to move.
///
/// The renderer uses it twice. Every frame it moves the near plane out to
/// the nearest thing it will draw, which costs nothing anybody can see and
/// buys depth precision everywhere behind it; and wherever a far point has
/// to be unprojected — a ray through a pixel, a frustum to cull by — it
/// stands a finite plane in for an infinite one. Neither changes the
/// projection a camera holds, which is what picking and every caller
/// outside the renderer still see.
///
/// Worked out from the planes, never by composing matrices: reversing an
/// ordinary matrix by subtraction takes one from a number a hair away from
/// one, and in single precision that hair is most of what is left.
Matrix4? withDepthPlanes(
  Matrix4 projection, {
  required double near,
  required double far,
  bool reversed = false,
}) {
  final s = projection.storage;
  // Column-major: entry (row, column) is `s[column * 4 + row]`.
  final perspective =
      s[3] == 0.0 && s[7] == 0.0 && s[11] == -1.0 && s[15] == 0.0;
  if (!perspective || s[2] != 0.0 || s[6] != 0.0) return null;
  if (!(near > 0.0) || !(far > near)) {
    throw ArgumentError('Expected 0 < near < far, got near=$near far=$far.');
  }
  final result = Matrix4.copy(projection);
  if (!reversed) {
    _setDepthRow(result, near, far);
  } else if (far.isInfinite) {
    // `w - z` of the infinite row below, which is exact: the depth is the
    // near plane over the distance, one at the near plane and nought at the
    // horizon.
    result.setEntry(2, 2, 0.0);
    result.setEntry(2, 3, near);
  } else {
    result.setEntry(2, 2, near / (far - near));
    result.setEntry(2, 3, (near * far) / (far - near));
  }
  return result;
}

/// Writes a perspective depth row for [near] and [far] in this file's
/// `[0, 1]` convention: near at nought, far at one, and a [far] at infinity
/// as the limit of that row as the plane recedes.
///
/// The finite branch is the arithmetic `PerspectiveProjection` has always
/// done, term for term, so every finite camera draws the matrix it drew.
void _setDepthRow(Matrix4 m, double near, double far) {
  if (far.isInfinite) {
    m.setEntry(2, 2, -1.0);
    m.setEntry(2, 3, -near);
    return;
  }
  m.setEntry(2, 2, far / (near - far));
  m.setEntry(2, 3, (near * far) / (near - far));
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
/// the same either way.
///
/// **A perspective matrix is read from its bottom row**, which is the view's
/// depth row negated: clip w is the distance in front of the eye, so the row
/// that makes it is the axis. That row is the one [toDepthRange],
/// [toFramebufferOrigin], [withDepthPlanes] and an oblique near plane leave
/// alone, so a reversed matrix and an infinite one give the same answer as
/// the camera's — and nothing is unprojected, so nothing divides by the
/// w = 0 of a far plane at infinity.
///
/// An orthographic matrix has nought there, and is read as the line from the
/// middle of the near plane to the middle of the far one, both of which are
/// finite: its w is one everywhere.
///
/// The surface buffer measures its depths along this — see `ViewDepth` in
/// `lib/color.glsl` — so whatever writes that buffer and whatever reads it have
/// to agree about it.
Vector3 viewAxisOf(Matrix4 viewProjection, [Vector3? out]) {
  final result = out ?? Vector3.zero();
  final m = viewProjection.storage;
  // Column-major: row 3 is `m[3], m[7], m[11]`.
  result.setValues(m[3], m[7], m[11]);
  if (!isOrthographic(viewProjection) && result.length2 > 0.0) {
    return result..normalize();
  }
  final inverse = Matrix4.copy(viewProjection)..invert();
  final near = inverse * Vector4(0.0, 0.0, 0.0, 1.0) as Vector4;
  final far = inverse * Vector4(0.0, 0.0, 1.0, 1.0) as Vector4;
  result.setValues(
    far.x / far.w - near.x / near.w,
    far.y / far.w - near.y / near.w,
    far.z / far.w - near.z / near.w,
  );
  if (result.length2 > 0.0) result.normalize();
  return result;
}

/// Whether [viewProjection] projects orthographically — `P7`.
///
/// Read out of the matrix for the reason [viewAxisOf] is: a probe face and a
/// mirrored view have no camera to ask. An orthographic projection leaves w
/// alone, so the matrix's bottom row is the view's own, nought nought nought
/// and a number; a perspective one puts the depth there. What
/// [toDepthRange] and [toFramebufferOrigin] do touches the depth and the
/// height rows and leaves that one.
bool isOrthographic(Matrix4 viewProjection) {
  final m = viewProjection.storage;
  final w = m[15].abs();
  const tiny = 1e-9;
  return w > tiny &&
      m[3].abs() <= tiny * w &&
      m[7].abs() <= tiny * w &&
      m[11].abs() <= tiny * w;
}
