/// The holder a phone goes into, as the four numbers holders differ by.
///
/// **A pair of symmetric frustums is the wrong shape for a holder.** The lens
/// does not sit in the middle of the half of the screen it looks at: it sits
/// nearer the middle of the phone, because the two lenses are a face's width
/// apart and a phone is wider than that. So each eye sees further towards the
/// outside of its half than towards the inside, and drawing both halves with
/// the same centred frustum puts the picture off the lens axis by that
/// difference. The eyes then disagree about where a thing is, and a viewer who
/// cannot say why reports it as eye strain.
///
/// The numbers here are the ones a viewer profile states, and they are the ones
/// that differ between a folded box and a moulded holder: how far apart the
/// lenses are, how far the screen is from them, how high above the tray they
/// sit, and how wide the lens lets the eye see. Everything else is arithmetic.
///
/// **Lens distortion is not corrected, and this is the file that has to say
/// so.** A lens bends straight lines outward, and undoing that means drawing
/// the frame into a texture and sampling it back through the inverse curve —
/// a post-processing pass, in four backends' shader dialects. Until that
/// exists, a wide-angle holder shows straight edges bowed near the rim of the
/// picture; the geometry below is still right, and the rim is still wrong.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'stereo_rig.dart';

const double _degree = math.pi / 180.0;

/// The smallest tangent a frustum edge is allowed to have.
///
/// A screen narrower than the lenses are apart, or a tray height taller than
/// the screen, would otherwise produce a zero-width frustum and a matrix full
/// of infinities. Numbers that silly are a misconfigured profile rather than a
/// case to support, so they are clamped into something that still draws.
const double _smallestTangent = 0.01;

/// The size of the screen the lenses look at, in metres.
///
/// Metres because every other number in a viewer profile is in metres, and
/// because the arithmetic is a ratio between two lengths: turning one of them
/// into pixels would only mean turning it back.
final class StereoScreen {
  const StereoScreen({required this.width, required this.height});

  /// The screen's size estimated from Flutter's logical pixels.
  ///
  /// **An estimate, and named one.** A logical pixel is a device-independent
  /// unit whose relation to a millimetre is a convention rather than a
  /// measurement: 160 per inch is Android's, and iOS is close enough to it that
  /// the error is smaller than the difference between two holders of the same
  /// model. An application that knows the real figure should pass it, and one
  /// that knows the physical size should use the other constructor.
  factory StereoScreen.fromLogicalPixels({
    required double width,
    required double height,
    double dotsPerInch = 160.0,
  }) {
    const double inch = 0.0254;
    return StereoScreen(
      width: width / dotsPerInch * inch,
      height: height / dotsPerInch * inch,
    );
  }

  /// The long side, the one the two eyes divide between them.
  final double width;

  /// The short side, the one the tray height is measured along.
  final double height;

  @override
  String toString() =>
      'StereoScreen(${(width * 1000).round()} × ${(height * 1000).round()} mm)';
}

/// A holder's own numbers.
///
/// The defaults are the Cardboard v2 profile, which is what most folded
/// holders sold since have copied. A holder that states its own figures should
/// be written out rather than approximated by a preset: the whole point of
/// these four numbers is that they are the ones that differ.
final class StereoViewer {
  const StereoViewer({
    this.interLensDistance = 0.064,
    this.screenToLensDistance = 0.039,
    this.trayToLensHeight = 0.035,
    this.outerFieldOfView = 60 * _degree,
    this.innerFieldOfView = 60 * _degree,
    this.topFieldOfView = 60 * _degree,
    this.bottomFieldOfView = 60 * _degree,
  });

  /// The 2014 folded viewer: narrower lenses, further from the screen, and a
  /// much smaller window through them.
  static const StereoViewer cardboardV1 = StereoViewer(
    interLensDistance: 0.060,
    screenToLensDistance: 0.042,
    trayToLensHeight: 0.035,
    outerFieldOfView: 40 * _degree,
    innerFieldOfView: 40 * _degree,
    topFieldOfView: 40 * _degree,
    bottomFieldOfView: 40 * _degree,
  );

  /// The 2015 viewer, and the defaults of this class.
  static const StereoViewer cardboardV2 = StereoViewer();

  /// How far apart the lenses are. This is what separates the eyes, in place
  /// of an interpupillary distance: a viewer's own eyes look through wherever
  /// the lenses are, and being 2 mm wider than the holder does not move them.
  final double interLensDistance;

  /// From the screen to the lens, along the lens axis.
  final double screenToLensDistance;

  /// From the edge the phone rests on to the lens axis, across the screen's
  /// short side.
  ///
  /// **Measured to the screen's edge, where a profile measures to the phone's.**
  /// A published figure includes the bezel below the glass, so it wants that
  /// much taken off before it is passed here. What it decides is how far the
  /// lens axis sits from the middle of the screen, and the frustum is taller on
  /// whichever side has more glass left.
  final double trayToLensHeight;

  /// How much of the world the lens lets through, towards the outside of the
  /// face, towards the nose, and up and down. Radians from the lens axis, the
  /// way the rest of this repository states an angle.
  final double outerFieldOfView;
  final double innerFieldOfView;
  final double topFieldOfView;
  final double bottomFieldOfView;

  /// The frustum [eye] sees through this holder at [screen].
  ///
  /// Each edge is the smaller of what the lens allows and what the screen
  /// actually reaches: a small phone in a wide-angle holder is limited by the
  /// glass it has, and a large phone in a narrow one is limited by the lens.
  OffAxisProjection projectionFor(
    Eye eye,
    StereoScreen screen, {
    double near = 0.05,
    double far = 500.0,
  }) {
    final double halfLenses = interLensDistance / 2.0;
    final double outer = _edge(
      limit: outerFieldOfView,
      reach: screen.width / 2.0 - halfLenses,
    );
    final double inner = _edge(limit: innerFieldOfView, reach: halfLenses);
    final double below = _edge(
      limit: bottomFieldOfView,
      reach: trayToLensHeight,
    );
    final double above = _edge(
      limit: topFieldOfView,
      reach: screen.height - trayToLensHeight,
    );

    final bool isLeft = identical(eye, Eye.left);
    return OffAxisProjection(
      // The wide side of each frustum faces away from the nose, which is the
      // whole difference between this and a centred pair.
      tanLeft: -(isLeft ? outer : inner),
      tanRight: isLeft ? inner : outer,
      tanDown: -below,
      tanUp: above,
      near: near,
      far: far,
    );
  }

  /// Where [eye] sits, relative to the head, for this holder.
  double eyeOffset(Eye eye) => identical(eye, Eye.left)
      ? -interLensDistance / 2.0
      : interLensDistance / 2.0;

  double _edge({required double limit, required double reach}) {
    final double allowed = math.tan(limit);
    final double reached = reach / screenToLensDistance;
    final double smaller = allowed < reached ? allowed : reached;
    return smaller < _smallestTangent ? _smallestTangent : smaller;
  }

  StereoViewer copyWith({
    double? interLensDistance,
    double? screenToLensDistance,
    double? trayToLensHeight,
    double? outerFieldOfView,
    double? innerFieldOfView,
    double? topFieldOfView,
    double? bottomFieldOfView,
  }) => StereoViewer(
    interLensDistance: interLensDistance ?? this.interLensDistance,
    screenToLensDistance: screenToLensDistance ?? this.screenToLensDistance,
    trayToLensHeight: trayToLensHeight ?? this.trayToLensHeight,
    outerFieldOfView: outerFieldOfView ?? this.outerFieldOfView,
    innerFieldOfView: innerFieldOfView ?? this.innerFieldOfView,
    topFieldOfView: topFieldOfView ?? this.topFieldOfView,
    bottomFieldOfView: bottomFieldOfView ?? this.bottomFieldOfView,
  );

  @override
  String toString() =>
      'StereoViewer(lenses ${(interLensDistance * 1000).round()} mm apart, '
      '${(screenToLensDistance * 1000).round()} mm from the screen)';
}

/// Aiming a rig through a holder's lenses.
///
/// An extension rather than a method on [StereoRig], so that the rig goes on
/// knowing nothing about holders: a runtime that states its own frusta calls
/// `applyEye` and never loads this file.
extension StereoRigViewer on StereoRig {
  /// Puts the eyes where the lenses are and gives each the frustum it sees
  /// through, from the rig's own near and far planes.
  ///
  /// Cheap enough to call every frame, and safe to: it builds two values and
  /// assigns them, the way `fitToViewport` does.
  void applyViewer(StereoViewer viewer, StereoScreen screen) {
    for (final Eye eye in Eye.both) {
      applyEye(
        eye,
        projection: viewer.projectionFor(eye, screen, near: near, far: far),
        offset: Vector3(viewer.eyeOffset(eye), 0.0, 0.0),
      );
    }
  }
}
