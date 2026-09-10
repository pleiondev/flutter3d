/// The transform gizmo as geometry: arrows to move by, rings to turn by and
/// boxes to scale by, written into a [MeshOverlay].
///
/// **`transform_gizmo.dart` decides and this draws, and neither does the
/// other's job.** That file opens by saying the half it refuses to have is the
/// half that turns a [GizmoHandle] into something on screen, and this is that
/// half. It hit-tests nothing. The arm under the pointer arrives as a
/// [GizmoAxis] the caller already has from [GizmoHit.nearest], because a hit
/// test written a second time here would be a second answer to "which arm is
/// that", and the day the two answers part company the gizmo lights one arm and
/// drags another — which reads to a person as the mouse being broken rather
/// than as a program being wrong.
///
/// **The arms are drawn out of the [GizmoHandle]s rather than worked out
/// again.** [gizmoHandles] already places a shaft, a head and the box a ray is
/// traced against, all from one length; recomputing that length here from the
/// overlay's own camera would give two lengths that agree until the frame one
/// of the two cameras is set a moment later than the other, and the failure
/// then is an arrow drawn past the end of the box that can be grabbed. So the
/// caller passes the handles it hit-tested with and this draws exactly those.
/// The one number taken from the overlay instead is the radius of the turn
/// rings, which no handle carries.
///
/// **Everything is sized in logical pixels, through [MeshOverlay.ribbon],
/// [MeshOverlay.point] and [MeshOverlay.worldSize].** A gizmo measured in
/// metres fills the window when the camera comes in to look at a bevel and is a
/// few pixels of unhittable clutter when it pulls back to see the whole model.
/// The handles the overlay already draws for vertices are sized this way for
/// the same reason, and a gizmo that disagreed with them would be a second rule
/// for one question.
///
/// **Nothing here is a cone, and that is deliberate.** [MeshOverlay] draws
/// lines, camera-facing squares and camera-facing bands; a proper arrowhead
/// would mean writing triangles into the batch by hand, which means repeating
/// the overlay's nudge towards the eye out here — the one number that has to
/// agree with everything else drawn on the surface. `ground_grid.dart` turned
/// the same corner down for the same reason. A square at the point of the arrow
/// reads as a head at every size the gizmo is ever drawn at, and costs six
/// vertices.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

import 'transform_gizmo.dart';
import 'transform_modal.dart';

/// The colour of the box in the middle, the one that scales every axis at once,
/// as `0xRRGGBB`.
///
/// **No axis, so no tint.** [kGizmoTintX] and its two rotations each say a
/// direction, and a uniform scale is the one handle that says none of them;
/// borrowing one of the three would put a red box in the middle of a gizmo
/// whose red arm points elsewhere. A pale grey is what is left that still reads
/// as something to take hold of.
///
/// It is a grey of its own, which is one more colour than this file would like
/// to add. The greys already on screen are the wireframe's `#8C9399` and an
/// unselected vertex handle's `#B8C2C7`, and a middle box painted in either of
/// them is a handle a person has to pick out of the mesh it is standing on.
/// This one is a step lighter than both, so it reads as sitting in front of the
/// model; going the other way and darkening it would put the box in the range
/// the shadowed side of a lit model occupies. The test holds the gap rather
/// than the hex: what matters is that the middle box is lighter than anything
/// the overlay draws underneath it.
const int kGizmoTintUniform = 0xC8CFD2;

/// How far towards white the handle under the pointer is mixed.
///
/// **Brighter rather than another colour, and brighter rather than bigger.** A
/// highlight that changed the hue would take the arm's meaning away at the
/// moment a person is deciding whether it is the arm they want; one that
/// changed the size would move the paint out from under the pointer that is
/// hovering it, and on a narrow arm that is a highlight which switches itself
/// off. Mixing towards white keeps the arm the axis's colour, in the same
/// place, and visibly picked out against the two beside it.
const double kGizmoHotMix = 0.45;

/// Draws the gizmo's handles into an overlay.
///
/// One value with the sizes on it rather than a function with eight arguments,
/// so a caller that wants a chunkier gizmo on a touch screen changes a field
/// rather than every call site — and so the numbers below are all in one place
/// to be read against the design.
final class GizmoDrawing {
  const GizmoDrawing({
    this.shaftPixels = 3.0,
    this.headPixels = 13.0,
    this.boxPixels = 11.0,
    this.turnPixels = 82.0,
    this.hotMix = kGizmoHotMix,
  });

  /// How wide the shaft of an arrow, and the arm of a scale handle, is drawn.
  ///
  /// A band rather than a line, because a one-pixel line is a thing a person
  /// cannot see the colour of and cannot tell from the wireframe behind it.
  final double shaftPixels;

  /// The square at the point of a move arrow.
  final double headPixels;

  /// The square at the end of a scale arm, and the one in the middle.
  ///
  /// Smaller than [headPixels]: a scale handle is a box a person aims at, and
  /// an arrow is a direction they read, so the arrow wants the heavier end.
  final double boxPixels;

  /// The radius of a turn ring.
  ///
  /// Inside [kGizmoPixels], so a ring never reaches past the arrows the same
  /// gizmo would draw for a move and the two kinds of gizmo occupy the same
  /// patch of screen. A ring wider than the arrows would make switching from
  /// move to rotate look like the gizmo growing.
  final double turnPixels;

  /// How far towards white a lit handle is mixed. See [kGizmoHotMix].
  final double hotMix;

  /// How many segments a turn ring is drawn as.
  ///
  /// At the radius above, forty-eight puts the corners about eleven logical
  /// pixels apart, which sounds coarse and is the wrong measure: the ring is
  /// drawn as one-pixel lines, so what decides whether a corner can be seen is
  /// how far the chord sags away from the circle between two of them. Here that
  /// is 0.18 of a pixel — a fifth of the line's own width, which is nothing to
  /// see. Twenty-four segments would put it at 0.70 of a pixel, which is a
  /// corner, and the ring would read as a polygon.
  ///
  /// The price is ninety-six vertices per ring in a batch that already holds a
  /// wireframe, which is why this stops at the count where the sag disappears
  /// rather than going further.
  static const int _turnSegments = 48;

  /// Writes the handles for a transform of [kind] about [pivot] into [overlay].
  ///
  /// [handles] are the arms [gizmoHandles] placed for the same pivot and the
  /// same camera, and [hot] is the axis [GizmoHit.nearest] answered for the
  /// pointer, or null when the pointer is on none of them. [uniformHot] is the
  /// same question for the box in the middle, which only a scale has.
  ///
  /// The batches are not cleared first, for the reason `ground_grid.dart` does
  /// not clear them either: the gizmo is one of several things drawn into an
  /// overlay, and a builder that cleared would be a builder that has to be
  /// called first.
  void writeInto(
    MeshOverlay overlay, {
    required Vector3 pivot,
    required List<GizmoHandle> handles,
    required TransformKind kind,
    GizmoAxis? hot,
    bool uniformHot = false,
  }) {
    switch (kind) {
      case TransformKind.move:
        _arrows(overlay, handles, hot);
      case TransformKind.rotate:
        _rings(overlay, pivot, handles, hot);
      case TransformKind.scale:
        _arms(overlay, pivot, handles, hot, uniformHot);
    }
  }

  /// A shaft and a head per axis, on the [GizmoHandle]'s own points.
  ///
  /// The head is centred half way along the length the handle set aside for it
  /// rather than sitting on the tip. [gizmoHandles] traces its box from the
  /// base to the tip and fattens it sideways only, so the tip is where a ray
  /// stops answering: a thirteen-pixel square centred there would hang six and
  /// a half pixels past the end of the box, and the point of the arrow — the
  /// part a hand aims at — would be paint nothing can be grabbed by. Centred at
  /// eighty-four of the arm's ninety-six pixels it runs from 77.5 to 90.5 and
  /// stands clear of both ends of the region the handle reserved for it, 72 to
  /// 96. The last five and a half pixels of the arm therefore carry no paint,
  /// which is the price of every drawn pixel being a pixel that can be hit.
  void _arrows(MeshOverlay overlay, List<GizmoHandle> handles, GizmoAxis? hot) {
    for (final handle in handles) {
      final ink = _inkFor(handle.tint, handle.axis == hot);
      overlay.ribbon(handle.base, handle.headBase, ink, width: shaftPixels);
      overlay.point(
        (handle.headBase + handle.tip) * 0.5,
        ink,
        size: headPixels,
      );
    }
  }

  /// An arm and a box per axis, and one box in the middle.
  ///
  /// The arm runs the whole way to the tip rather than stopping short of it the
  /// way a move arrow's shaft does, because the box is the handle here and it
  /// wants a stalk that reaches it. Both ends are the handle's own, so a scale
  /// is grabbed over exactly the length it is drawn over.
  void _arms(
    MeshOverlay overlay,
    Vector3 pivot,
    List<GizmoHandle> handles,
    GizmoAxis? hot,
    bool uniformHot,
  ) {
    for (final handle in handles) {
      final ink = _inkFor(handle.tint, handle.axis == hot);
      overlay.ribbon(handle.base, handle.tip, ink, width: shaftPixels);
      overlay.point(handle.tip, ink, size: boxPixels);
    }
    overlay.point(
      pivot,
      _inkFor(kGizmoTintUniform, uniformHot),
      size: boxPixels,
    );
  }

  /// A closed ring per axis, in the plane the axis turns things in.
  ///
  /// **A whole ring rather than the part of it facing the viewer.** The arc
  /// most modellers draw is the half of the ring in front of the pivot, which
  /// means the ends of the arc move round the pivot as the camera orbits: the
  /// handle a person reached for a second ago is somewhere else now, and where
  /// it went depends on where they were looking rather than on anything they
  /// did. A whole ring is in the same place every frame, and the depth test the
  /// overlay draws with already lets the model in front of it hide the far half
  /// where there is a model to do the hiding.
  ///
  /// Drawn as lines rather than as bands: a ring of forty-eight bands is nearly
  /// three hundred vertices per axis to say what ninety-six say, and the ring
  /// is a thing a person aims at rather than reads a colour off.
  void _rings(
    MeshOverlay overlay,
    Vector3 pivot,
    List<GizmoHandle> handles,
    GizmoAxis? hot,
  ) {
    final radius = overlay.worldSize(turnPixels, pivot);
    for (final handle in handles) {
      final ink = _inkFor(handle.tint, handle.axis == hot);
      final (across, andAcross) = _planeOf(handle.axis);
      var from = pivot + across * radius;
      for (var i = 1; i <= _turnSegments; i++) {
        final angle = 2 * math.pi * i / _turnSegments;
        final to =
            pivot +
            (across * math.cos(angle) + andAcross * math.sin(angle)) * radius;
        overlay.edge(from, to, ink);
        from = to;
      }
    }
  }

  /// The two axes a turn about [axis] moves things along, in the order that
  /// makes the pair right-handed about it.
  ///
  /// The plane is what the ring is, and the tests hold it. The order of the two
  /// vectors is a convention nothing yet reads, and it cannot be seen in what
  /// is drawn: the forty-eight samples start at angle zero and are symmetrical
  /// about that start, so swapping the pair reflects the ring onto its own
  /// vertices and the same forty-eight chords come back in the opposite order.
  /// It is kept right-handed anyway, because the first thing to read a
  /// direction off this pair — an arc that grows the way a drag turns the model
  /// — wants the sweep to agree with a positive turn about the axis, and a
  /// convention is cheaper to keep now than to work out later from a ring that
  /// looks the same either way.
  ///
  /// Fresh vectors each time, the way [GizmoAxis.direction] hands out fresh
  /// ones: a shared constant is a constant the first caller to scale it in
  /// place changes for everybody.
  static (Vector3, Vector3) _planeOf(GizmoAxis axis) => switch (axis) {
    GizmoAxis.x => (Vector3(0, 1, 0), Vector3(0, 0, 1)),
    GizmoAxis.y => (Vector3(0, 0, 1), Vector3(1, 0, 0)),
    GizmoAxis.z => (Vector3(1, 0, 0), Vector3(0, 1, 0)),
  };

  /// [tint] as the overlay wants it, mixed towards white when [lit].
  ///
  /// The alpha is one throughout. The line batch has no blend state at all and
  /// the solid batch none either, so an alpha under one would be a fade that
  /// changes nothing on screen and misleads anything else reading these
  /// vertices — which is the trap `ground_grid.dart` keeps out of its own
  /// colours.
  Vector4 _inkFor(int tint, bool lit) {
    final ink = Vector4(
      ((tint >> 16) & 0xFF) / 255.0,
      ((tint >> 8) & 0xFF) / 255.0,
      (tint & 0xFF) / 255.0,
      1.0,
    );
    if (!lit) return ink;
    // Clamped because `hotMix` is a field a caller sets: a mix past one takes
    // the channels past white, and what a backend does with that — clamp, wrap,
    // or a NaN once it has been through a tone curve — is a thing nobody wants
    // to find out one platform at a time. A mix under zero is the same fault
    // downwards, and comes out as a handle darker than its own tint on the one
    // frame it is hovered. Both ends are held by 'a mix past the ends of the
    // range still lands on a colour' in `gizmo_handles_test.dart`, which reads
    // the raw floats: the byte the test's other helpers hand back is already
    // clamped on the way out, so a channel at 10.4 looks like white there.
    final mix = hotMix.clamp(0.0, 1.0);
    return Vector4(
      ink.x + (1.0 - ink.x) * mix,
      ink.y + (1.0 - ink.y) * mix,
      ink.z + (1.0 - ink.z) * mix,
      1.0,
    );
  }
}
