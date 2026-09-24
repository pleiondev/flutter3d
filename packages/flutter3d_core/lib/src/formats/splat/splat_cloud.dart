/// A cloud of 3D Gaussians — `gfx-80n`.
///
/// **What a splat is, in one paragraph, because the name hides it.** A Gaussian
/// splat is not a point and not a sprite: it is an ellipsoid of fading opacity,
/// described by where its centre is, how far it reaches along three axes, which
/// way those axes point, what colour it is and how opaque its middle is. A
/// capture of a real place is a few million of them, fitted so that the sum of
/// what they cover, blended back to front, is the photographs it was fitted to.
/// Nothing about it is a mesh, which is why none of the engine's mesh path
/// applies.
///
/// **Flat arrays, not a list of objects.** A million splats is a million
/// allocations the moment each one is a class, and the sort below touches every
/// centre on every camera move. Everything here is `Float32List` in the layout
/// the draw wants, so loading is a copy and sorting is a permutation of indices
/// rather than of records.
///
/// This file is the data and the arithmetic that turns the stored parameters
/// into what a renderer needs. Nothing here draws.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// The spherical-harmonic normalisation the 3D Gaussian Splatting papers and
/// every exporter after them use for the zeroth band.
///
/// Copied rather than derived, the choice `inflate.dart` makes for RFC 1951's
/// tables: it is `0.5 * sqrt(1 / pi)`, and a version worked out here would be a
/// second answer to a question the file format has already answered.
const double kSplatShC0 = 0.28209479177387814;

/// A fitted cloud, in the units the file stored.
final class SplatCloud {
  SplatCloud({
    required this.centres,
    required this.colours,
    required this.scales,
    required this.rotations,
    this.shDegree = 0,
    Float32List? shRest,
  }) : count = centres.length ~/ 3,
       shRest = shRest ?? Float32List(0) {
    if (colours.length != count * 4 ||
        scales.length != count * 3 ||
        rotations.length != count * 4) {
      throw ArgumentError(
        'A cloud of $count splats needs ${count * 3} centre floats, '
        '${count * 4} colour floats, ${count * 3} scale floats and '
        '${count * 4} rotation floats; got ${centres.length}, '
        '${colours.length}, ${scales.length} and ${rotations.length}.',
      );
    }
    if (shDegree < 0 || shDegree > 3) {
      throw ArgumentError('shDegree is $shDegree; a cloud carries 0 to 3.');
    }
    if (this.shRest.length != count * shRestFloatsPerSplat) {
      throw ArgumentError(
        'A cloud of $count splats at spherical-harmonic degree $shDegree '
        'needs ${count * shRestFloatsPerSplat} higher-band floats; got '
        '${this.shRest.length}.',
      );
    }
  }

  /// How many splats. Every array below is this long times its own stride.
  final int count;

  /// `xyz` per splat, in world units.
  final Float32List centres;

  /// Linear RGB and alpha per splat, already through the sigmoid and the
  /// spherical-harmonic constant — the file stores neither.
  final Float32List colours;

  /// The ellipsoid's reach along its own three axes, in world units, already
  /// through the exponential the file stores it under.
  final Float32List scales;

  /// `xyzw`, normalised. The file's own order is `w` first; this is not, so
  /// that it matches every other quaternion in this engine.
  final Float32List rotations;

  /// The highest spherical-harmonic band the source carried, 0 to 3.
  ///
  /// **Carried, not drawn.** [colours] is band 0 alone, which is the colour a
  /// splat has from every direction; the higher bands are what makes it
  /// change with the viewing angle, and nothing in the draw evaluates them
  /// yet. They are kept rather than dropped so that the stage which does
  /// evaluate them finds them already loaded, from any file that had them.
  final int shDegree;

  /// Bands 1 to [shDegree], [shRestFloatsPerSplat] floats a splat: each
  /// coefficient's `rgb` in the order the band lists them (lowest `m`
  /// first), band 1 before band 2. Empty at degree 0.
  final Float32List shRest;

  /// How many floats of [shRest] each splat owns: `3 × ((d + 1)² − 1)`, so
  /// 9, 24 or 45 for degrees 1, 2 and 3.
  int get shRestFloatsPerSplat => 3 * ((shDegree + 1) * (shDegree + 1) - 1);

  /// The 3×3 covariance of splat [index], written into [out] as six floats:
  /// `xx, xy, xz, yy, yz, zz`.
  ///
  /// **Six rather than nine, because it is symmetric**, and a renderer that
  /// uploaded nine would be sending three numbers it could have computed. The
  /// matrix is `R S Sᵀ Rᵀ`: scale the unit sphere into an ellipsoid, then turn
  /// it. Writing it out this way rather than multiplying two 3×3s is the same
  /// arithmetic with the zeros of the diagonal `S` taken out.
  void covarianceOf(int index, Float32List out, [int at = 0]) {
    final r = Quaternion(
      rotations[index * 4],
      rotations[index * 4 + 1],
      rotations[index * 4 + 2],
      rotations[index * 4 + 3],
    ).asRotationMatrix();
    final sx = scales[index * 3];
    final sy = scales[index * 3 + 1];
    final sz = scales[index * 3 + 2];

    // Columns of `R S`: each column of R scaled by the matching extent.
    final ax = r.entry(0, 0) * sx, ay = r.entry(1, 0) * sx;
    final az = r.entry(2, 0) * sx;
    final bx = r.entry(0, 1) * sy, by = r.entry(1, 1) * sy;
    final bz = r.entry(2, 1) * sy;
    final cx = r.entry(0, 2) * sz, cy = r.entry(1, 2) * sz;
    final cz = r.entry(2, 2) * sz;

    out[at] = ax * ax + bx * bx + cx * cx;
    out[at + 1] = ax * ay + bx * by + cx * cy;
    out[at + 2] = ax * az + bx * bz + cx * cz;
    out[at + 3] = ay * ay + by * by + cy * cy;
    out[at + 4] = ay * az + by * bz + cy * cz;
    out[at + 5] = az * az + bz * bz + cz * cz;
  }

  /// The indices of every splat, ordered far to near along [forward] from
  /// [eye], which is the order alpha blending has to draw them in.
  ///
  /// **Back to front and not a depth test, which is the whole of why this
  /// exists.** A Gaussian is translucent everywhere, so two of them overlapping
  /// give a different colour depending on which was drawn first; a depth buffer
  /// answers "which is in front" and blending needs "which is behind". Getting
  /// it backwards does not look like an ordering bug, it looks like the wrong
  /// colours.
  ///
  /// Writes into [into] when one long enough is given, so a frame that sorts
  /// every time the camera moves allocates nothing.
  Int32List sortedBackToFront(
    Vector3 eye,
    Vector3 forward, {
    Int32List? into,
    Float32List? depths,
  }) {
    final order = (into != null && into.length >= count)
        ? into
        : Int32List(count);
    final keys = (depths != null && depths.length >= count)
        ? depths
        : Float32List(count);

    for (var i = 0; i < count; i++) {
      order[i] = i;
      keys[i] =
          (centres[i * 3] - eye.x) * forward.x +
          (centres[i * 3 + 1] - eye.y) * forward.y +
          (centres[i * 3 + 2] - eye.z) * forward.z;
    }

    // Along the view axis rather than by true distance: the two disagree only
    // off to the sides of the frame, where the difference is smaller than the
    // splats are, and one multiply-add per splat beats a square root on a
    // million of them every time the camera turns.
    final view = order.sublist(0, count)
      ..sort((a, b) => keys[b].compareTo(keys[a]));
    order.setRange(0, count, view);
    return order;
  }
}

/// [logit] through the logistic function, which is how a file stores opacity.
double splatOpacity(double logit) => 1.0 / (1.0 + math.exp(-logit));

/// A zeroth-band spherical-harmonic coefficient as a colour channel.
///
/// Not clamped: a fitted cloud can hold a coefficient that lands outside
/// `[0, 1]`, the engine renders in linear HDR, and clamping here would be this
/// file deciding what the tone curve is for.
double splatChannel(double coefficient) => 0.5 + kSplatShC0 * coefficient;
