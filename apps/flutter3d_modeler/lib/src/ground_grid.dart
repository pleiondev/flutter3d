/// The floor a model stands on, and the arithmetic of the dial that snaps the
/// camera onto an axis.
///
/// **Two things in one file because they are one feature.** The grid says which
/// way is up and how big a metre is; the dial in the corner says which way is
/// north and lets a person get back there. A modeller that has one and not the
/// other leaves somebody tumbling: the grid alone gives a floor with no idea
/// which side of it you are on, and the dial alone gives a compass over empty
/// space. They are also the same shape of code — arithmetic over a yaw, a pitch
/// and an eye — and none of it needs a widget.
///
/// **Nothing here paints and nothing here holds a camera.** The grid writes
/// into a [MeshOverlay] that somebody else owns, and the dial answers where its
/// buttons sit and what yaw and pitch a press should animate towards. The
/// `CustomPainter` and the animation are wiring; keeping them out is what makes
/// every number below reachable from a test with no GPU, no widget tree and no
/// pump.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

/// The grid of the ground plane, written into an overlay's line batch.
///
/// **Why it fades.** A grid of constant colour looks fine from above and falls
/// apart the moment the camera tilts down towards the horizon: the far lines
/// converge until they are closer together than a pixel, each one lands on a
/// different sub-pixel, and the distance boils with moiré every time the camera
/// moves a hair. The cure is to have the lines gone before they converge, so
/// the far half of the picture is background rather than interference. A grid
/// of fewer lines instead would trade the moiré for a floor that ends a metre
/// from the model, which is the other way to look cheap.
///
/// **The fade is mixed into the colour, and the alpha is left alone.**
/// [MeshOverlay] draws its
/// line batch with no blend state at all — the pipeline never reads the alpha
/// channel — so a fade written as a falling alpha would come out as a grid at
/// full strength all the way to the horizon on every backend. Mixed towards
/// [backgroundColour] it is the same picture a blend would have produced,
/// against a viewport whose clear colour is a constant this application chooses,
/// and it costs neither a second pass nor a state change.
///
/// **Centred on the origin, finite, and rebuilt by whoever owns the camera.**
/// The infinite grid that stays under the camera for ever is a shader trick
/// (a full-screen quad and a ray-plane intersection), and it would mean a
/// second pipeline, a second shader in the bundle and four backends to prove it
/// on for a floor. Lines in the overlay's batch cost one draw call inside a
/// batch that is already being drawn.
final class GroundGrid {
  /// [halfLines] lines each side of the origin, [spacing] apart, with every
  /// [majorEvery]th one brighter and the two through the origin coloured as
  /// axes.
  const GroundGrid({
    this.spacing = 1.0,
    this.halfLines = 20,
    this.majorEvery = 10,
    this.minorColour = 0xFF2A3234,
    this.majorColour = 0xFF3D4A4D,
    this.axisXColour = 0xFF7A3A48,
    this.axisZColour = 0xFF35526E,
    this.backgroundColour = 0xFF0E1112,
    this.solidFraction = 0.4,
  });

  /// World units between two lines.
  final double spacing;

  /// How many lines there are each side of the origin, in each direction.
  final int halfLines;

  /// Every [majorEvery]th line away from the origin is drawn in
  /// [majorColour] — the count a person reads distance off, the same way the
  /// heavier line every ten squares on graph paper is.
  final int majorEvery;

  /// The colour of an ordinary line, `#2A3234`.
  ///
  /// Dark enough that a dark model reads against it and light enough to be a
  /// floor rather than a rumour. Held as an ARGB integer rather than a
  /// [Vector4] because a colour that is a shared `Vector4` is a colour the
  /// first caller to scale it in place changes for the whole process.
  final int minorColour;

  /// Every tenth line, brighter than [minorColour] by about as much as
  /// [minorColour] is brighter than the background.
  final int majorColour;

  /// The line along the X axis, tinted towards the red the transform gizmo's X
  /// handle uses, and dimmed hard: a floor line that shouts as loudly as a
  /// handle is a floor line a person tries to drag.
  final int axisXColour;

  /// The line along the Z axis, blue for the same reason X is red.
  final int axisZColour;

  /// What the viewport clears to, which is what a fully faded line is mixed
  /// into. Wrong here means the far lines fade towards the wrong colour and the
  /// horizon shows a haze in the shape of the grid.
  final int backgroundColour;

  /// How much of the fade radius is at full strength before the fade starts.
  ///
  /// A fade that begins at the camera is a floor that is never its own colour;
  /// a fade that is a step at the far edge is a visible ring on the floor. The
  /// plateau then the ramp gives both a grid to read near the model and no edge
  /// to see far from it.
  final double solidFraction;

  /// Below this the mixed colour is within half of one 8-bit level of the
  /// background, so the segment would be a line nobody can see and a pair of
  /// vertices that still costs a rasterised span.
  static const double _invisible = 0.004;

  /// Fills [overlay]'s line batch with the grid, and answers how many segments
  /// it wrote.
  ///
  /// [eye] is where the camera is; the fade is measured from it rather than
  /// from the origin, so panning across a large floor keeps the grid strong
  /// under the model being worked on rather than under the world's centre.
  /// [fadeRadius] is where the lines have gone entirely — a caller ties it to
  /// the orbit distance, so zooming out shows more floor rather than less. Zero
  /// or less means no fade at all rather than a floor that has already
  /// vanished; see [strengthAt] for why that way round.
  ///
  /// The batch is not cleared first: the grid is one of several things drawn
  /// into an overlay, and a builder that cleared would be a builder that has to
  /// be called first.
  int writeInto(
    MeshOverlay overlay, {
    required Vector3 eye,
    required double fadeRadius,
  }) {
    var segments = 0;
    for (var i = -halfLines; i <= halfLines; i++) {
      final at = i * spacing;
      // The line at x == 0 runs along Z, which makes it the Z axis; the one at
      // z == 0 runs along X.
      final alongZ = _inkFor(i, axisZColour);
      final alongX = _inkFor(i, axisXColour);
      for (var j = -halfLines; j < halfLines; j++) {
        final from = j * spacing;
        final to = from + spacing;
        if (_segment(
          overlay,
          Vector3(at, 0, from),
          Vector3(at, 0, to),
          alongZ,
          eye,
          fadeRadius,
        )) {
          segments++;
        }
        if (_segment(
          overlay,
          Vector3(from, 0, at),
          Vector3(to, 0, at),
          alongX,
          eye,
          fadeRadius,
        )) {
          segments++;
        }
      }
    }
    return segments;
  }

  int _inkFor(int index, int axis) {
    if (index == 0) return axis;
    if (majorEvery > 0 && index % majorEvery == 0) return majorColour;
    return minorColour;
  }

  /// One cell of one line, or nothing if it has faded out.
  ///
  /// **The strength is taken at the middle of the segment rather than at its
  /// ends.** [MeshOverlay.edge] gives both ends of a line one colour, and a
  /// gradient along the line would mean writing vertices into the batch by hand
  /// and repeating the overlay's depth nudge out here — a second copy of the
  /// one number that has to agree with everything else the overlay draws. A
  /// segment is one cell long, so the staircase this leaves is a fraction of an
  /// 8-bit level per cell.
  ///
  /// Going through [MeshOverlay.edge] is also what gives the grid the nudge
  /// towards the eye that the rest of the overlay has. A grid written without
  /// it fights with the first object whose underside is the ground plane, and a
  /// floor that flickers where a model touches it is the bug this whole overlay
  /// exists to avoid.
  bool _segment(
    MeshOverlay overlay,
    Vector3 from,
    Vector3 to,
    int ink,
    Vector3 eye,
    double fadeRadius,
  ) {
    final middle = (from + to) * 0.5;
    final strength = strengthAt(middle, eye: eye, fadeRadius: fadeRadius);
    if (strength <= _invisible) return false;
    overlay.edge(from, to, fadedColour(ink, strength));
    return true;
  }

  /// How much of a line's own colour survives at [point]: one near the camera,
  /// zero at [fadeRadius] and beyond.
  ///
  /// Measured in three dimensions rather than across the floor, because the
  /// distance that decides whether two lines land in the same pixel is the
  /// distance to the eye. A camera high above a floor is far from all of it,
  /// and that is exactly when the whole grid should be quiet.
  ///
  /// A [fadeRadius] of zero or less is a camera that has not told the grid how
  /// far it is looking, which is the first frame of a viewport rather than a
  /// request for an empty floor. Reading it literally — everything has faded by
  /// zero units out — draws nothing at all, and a viewport that comes up blank
  /// reads as a broken build.
  double strengthAt(
    Vector3 point, {
    required Vector3 eye,
    required double fadeRadius,
  }) {
    if (fadeRadius <= 0) return 1.0;
    final distance = point.distanceTo(eye);
    final solid = fadeRadius * solidFraction.clamp(0.0, 0.95);
    if (distance <= solid) return 1.0;
    if (distance >= fadeRadius) return 0.0;
    return (fadeRadius - distance) / (fadeRadius - solid);
  }

  /// [ink] mixed [strength] of the way from [backgroundColour] to itself.
  ///
  /// The alpha is the ink's own and is left alone: the line batch ignores it,
  /// and a caller reading these vertices for anything else should see the
  /// colour the grid meant rather than a fade smuggled into a channel nothing
  /// reads.
  Vector4 fadedColour(int ink, double strength) {
    final colour = _rgba(ink);
    final ground = _rgba(backgroundColour);
    final mix = strength.clamp(0.0, 1.0);
    return Vector4(
      ground.x + (colour.x - ground.x) * mix,
      ground.y + (colour.y - ground.y) * mix,
      ground.z + (colour.z - ground.z) * mix,
      colour.w,
    );
  }

  static Vector4 _rgba(int argb) => Vector4(
    ((argb >> 16) & 0xFF) / 255.0,
    ((argb >> 8) & 0xFF) / 255.0,
    (argb & 0xFF) / 255.0,
    ((argb >> 24) & 0xFF) / 255.0,
  );
}

/// One of the six buttons of the orientation dial, named by the world axis the
/// camera looks *along* when it is pressed.
///
/// **The label is the gaze, and the alternative flips every sign.** The other
/// reading — the button names the side the camera flies to — is the one most
/// tools use, and under it pressing `−X` would put the eye on the −X side and
/// give a yaw of −π/2. The acceptance this was built to says `−X` gives π/2,
/// which is the eye on +X looking back down the −X axis, so a button here says
/// which way you will be facing. Getting this backwards costs no crash and no
/// obviously wrong picture. It gives a dial where every button takes a person
/// to the opposite view from the one they asked for, and the only thing that
/// catches it is a test that names an axis and a yaw.
///
/// An enum rather than a final class of constants because this is machinery:
/// there are three axes and two ends of each, and a seventh value would be a
/// different kind of dial. The rule that refuses enums applies to published
/// packages, and an application's own closed list is closed against nobody.
enum ViewAxis {
  xPositive,
  xNegative,
  yPositive,
  yNegative,
  zPositive,
  zNegative;

  /// The unit vector this button faces the camera down.
  ///
  /// A fresh vector each time rather than a shared constant, so a caller that
  /// scales or normalises it in place changes its own copy.
  Vector3 get direction => switch (this) {
    ViewAxis.xPositive => Vector3(1, 0, 0),
    ViewAxis.xNegative => Vector3(-1, 0, 0),
    ViewAxis.yPositive => Vector3(0, 1, 0),
    ViewAxis.yNegative => Vector3(0, -1, 0),
    ViewAxis.zPositive => Vector3(0, 0, 1),
    ViewAxis.zNegative => Vector3(0, 0, -1),
  };
}

/// Where one button of the dial sits, and which way it is facing.
///
/// Screen offsets from the centre of the dial rather than absolute positions,
/// because the painter knows where it put the dial and this does not — and a
/// hit test in the same offsets is a hit test that works wherever the corner
/// the dial lives in ends up.
final class GizmoButton {
  const GizmoButton({
    required this.axis,
    required this.dx,
    required this.dy,
    required this.facing,
  });

  final ViewAxis axis;

  /// Pixels right of the dial's centre.
  final double dx;

  /// Pixels *below* the dial's centre, which is the direction Flutter's y runs
  /// and the opposite of the one the world's up does.
  final double dy;

  /// One when the axis points straight out of the screen at the viewer, minus
  /// one when it points straight away.
  ///
  /// What a painter fills a ball for and leaves another hollow, and what the
  /// hit test uses when two balls land on top of each other.
  final double facing;
}

/// The dial in the corner: where its buttons are, which one a press landed on,
/// and where the camera should go when one is pressed.
///
/// **No painter, no widget, no camera.** Every one of the three questions above
/// is arithmetic over a yaw and a pitch, and the moment they live inside a
/// `CustomPainter` the only way to ask them is to pump a widget and read
/// pixels. What is left over — a circle, six discs and a label — is a painter
/// small enough to read in one screen.
final class OrientationGizmo {
  /// [radius] is the circle the buttons sit on, so the ⌀60 dial the design asks
  /// for is a radius of about 22 with room for a ball at each end.
  const OrientationGizmo({this.radius = 22.0, this.handleRadius = 9.0});

  final double radius;

  /// How far from a button's centre a press still counts.
  ///
  /// Larger than the ball a painter draws, because a target the size of its
  /// paint is a target a trackpad misses.
  final double handleRadius;

  /// Just short of the pole, mirroring the clamp [OrbitController] applies to
  /// its own pitch. Exactly π/2 leaves the camera's up vector undetermined —
  /// the view rolls to whatever the maths falls out at, and it falls out
  /// differently either side of the top.
  static const double maxPitch = math.pi / 2 - 0.01;

  /// The six buttons for a camera at [yaw] and [pitch], furthest from the
  /// viewer first.
  ///
  /// Sorted back to front so a painter can draw the list in order and have the
  /// near balls cover the far ones without sorting it again or keeping a depth
  /// buffer for six discs.
  List<GizmoButton> buttonsAt({required double yaw, required double pitch}) {
    // The camera's own basis, spelled the way `OrbitController` spells it: the
    // eye sits along `eyeward` from the target, and these two are the screen's
    // axes. Anything else here and the dial disagrees with the picture beside
    // it, which reads as the dial being wrong by exactly one drag.
    final sinYaw = math.sin(yaw);
    final cosYaw = math.cos(yaw);
    final sinPitch = math.sin(pitch);
    final cosPitch = math.cos(pitch);
    final eyeward = Vector3(sinYaw * cosPitch, sinPitch, cosYaw * cosPitch);
    final right = Vector3(cosYaw, 0, -sinYaw);
    final up = Vector3(-sinYaw * sinPitch, cosPitch, -cosYaw * sinPitch);

    return <GizmoButton>[
      for (final axis in ViewAxis.values)
        _buttonFor(axis, right: right, up: up, eyeward: eyeward),
    ]..sort((GizmoButton a, GizmoButton b) => a.facing.compareTo(b.facing));
  }

  GizmoButton _buttonFor(
    ViewAxis axis, {
    required Vector3 right,
    required Vector3 up,
    required Vector3 eyeward,
  }) {
    final direction = axis.direction;
    return GizmoButton(
      axis: axis,
      dx: radius * direction.dot(right),
      dy: -radius * direction.dot(up),
      facing: direction.dot(eyeward),
    );
  }

  /// Which button a press at ([dx], [dy]) from the dial's centre landed on, or
  /// nothing if it landed on the dial's empty middle.
  ///
  /// **The one turned towards the viewer wins, and distance only breaks a
  /// tie.** Seen down an axis, two buttons sit exactly on top of each other, and a
  /// rule that compared distances alone would be choosing between two equal
  /// numbers — in practice, whichever the list happened to hold first, which is
  /// the far one, which is the view a person did not ask for. Distance is only
  /// the tie-break for two buttons equally turned towards the viewer.
  ViewAxis? hitTest(Iterable<GizmoButton> buttons, double dx, double dy) {
    GizmoButton? best;
    var bestDistance = double.infinity;
    for (final button in buttons) {
      final distance = math.sqrt(
        (button.dx - dx) * (button.dx - dx) +
            (button.dy - dy) * (button.dy - dy),
      );
      if (distance > handleRadius) continue;
      if (best == null ||
          button.facing > best.facing ||
          (button.facing == best.facing && distance < bestDistance)) {
        best = button;
        bestDistance = distance;
      }
    }
    return best?.axis;
  }

  /// The yaw and pitch a press on [axis] should animate towards, given the yaw
  /// the camera is at now.
  ///
  /// **[fromYaw] decides the route rather than the destination.** A yaw is an
  /// angle, and the same view has infinitely many of them; a target picked
  /// without looking at where the camera is can be 350 degrees away from a view
  /// that is 10 degrees away, and an animation obediently spins the whole model
  /// round on its way there. The answer is the turn of the destination nearest
  /// where the camera already is.
  ///
  /// At the two poles the yaw is undetermined — every yaw looks straight down —
  /// so the camera keeps the one it has. Snapping to zero instead would spin
  /// the floor under a person for no reason they can see, on the one view where
  /// they can see it best.
  ///
  /// **Two cases rather than an `asin` and an `atan2`.** The general form —
  /// pitch from the height of the eye, yaw from the two other components —
  /// reads as though it handles any direction, and six of them is all there
  /// ever are: four that leave the camera level and two that put it over the
  /// pole. Written generally, the sign of that `asin` is a line no test can
  /// reach, because every axis that would exercise it has a height of exactly
  /// zero or exactly one. Code nothing can be wrong about is better than code
  /// nothing can check.
  ({double yaw, double pitch}) viewAlong(
    ViewAxis axis, {
    required double fromYaw,
  }) {
    // Where the eye ends up is the opposite of where it will be looking.
    final eyeward = -axis.direction;
    if (eyeward.y != 0) {
      return (yaw: fromYaw, pitch: eyeward.y > 0 ? maxPitch : -maxPitch);
    }
    return (
      yaw: _nearestTurn(math.atan2(eyeward.x, eyeward.z), fromYaw),
      pitch: 0.0,
    );
  }

  /// [target] moved by whole turns until it is the one nearest [from].
  static double _nearestTurn(double target, double from) {
    const turn = 2 * math.pi;
    return target + turn * ((from - target) / turn).roundToDouble();
  }
}
