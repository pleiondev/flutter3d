/// The three arrows that move what is selected, as arithmetic.
///
/// **Everything here is a pivot, a camera and a ray.** Where the arrows are,
/// which one the pointer took hold of, how far along it the thing has travelled
/// and what the undo stack is owed at the end — none of that needs a device, a
/// frame or a widget, so none of it asks for one. The half that does need a
/// device is the half this file refuses to have: turning a [GizmoHandle] into
/// cylinders and cones, giving them an unlit material and putting them in a
/// late bucket that ignores depth. That is a dozen lines of `Shape` in the
/// staging code and it is untestable without a GPU; the dozen lines that decide
/// where a click lands are the ones a person notices when they are wrong, and
/// they are all in here.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// Which way a handle points, and so which way grabbing it lets a thing go.
enum GizmoAxis {
  x,
  y,
  z;

  /// The unit vector this axis runs along.
  Vector3 get direction => switch (this) {
    GizmoAxis.x => Vector3(1.0, 0.0, 0.0),
    GizmoAxis.y => Vector3(0.0, 1.0, 0.0),
    GizmoAxis.z => Vector3(0.0, 0.0, 1.0),
  };
}

/// The colour of the arrow that moves a thing along X, as `0xRRGGBB`.
///
/// **The three tints are one triple of channel values, rotated.** X is
/// `#FF6B8A`, Y is `#8AFF6B` and Z is `#6B8AFF`: the same numbers in a
/// different order, so the three arrows have the same weight against the dark
/// viewport and no one of them reads as the important one. Picked by hand for
/// each axis instead, the greens and blues that look right beside a red are
/// darker than it, and the axis a person uses most is then the axis they can
/// see least well.
const int kGizmoTintX = 0xFF6B8A;

/// The colour of the arrow that moves a thing along Y. See [kGizmoTintX].
const int kGizmoTintY = 0x8AFF6B;

/// The colour of the arrow that moves a thing along Z. See [kGizmoTintX].
const int kGizmoTintZ = 0x6B8AFF;

/// How long an arrow is on screen, in logical pixels.
///
/// Long enough to aim a hand along and short enough not to cover the model it
/// is standing on. Not a fraction of the viewport: on a wide window that grows
/// the gizmo and on a narrow one it shrinks it, and a manipulator that changes
/// size when a panel opens is a manipulator whose feel changes with the layout.
const double kGizmoPixels = 96.0;

/// How far either side of an arrow a press still counts as grabbing it, in
/// logical pixels.
///
/// **A drawn shaft is too thin to put a mouse on.** The shaft is about two
/// pixels across, and a grab that demanded those two pixels would be a grab
/// only a very still hand could make — and impossible with a finger. Eleven
/// pixels of slack is a comfortable target on a mouse and survives a trackpad;
/// it is also comfortably under the [_shaftStart] the arrows begin at, which is
/// what keeps the three boxes from ever meeting each other.
const double kGizmoGrabPixels = 11.0;

/// How far a snapped drag travels per step, in metres.
const double kGizmoSnap = 0.25;

/// Where the arrows start, as a fraction of their length.
///
/// The pivot itself is left clear: something is being edited there, and an
/// arrow rooted in the middle of it hides the thing it is meant to move.
const double _shaftStart = 0.15;

/// Where the head starts, as a fraction of the length.
const double _headStart = 0.75;

/// How wide the head is, as a fraction of the length.
const double _headRadius = 0.09;

/// How wide the shaft is, as a fraction of the length.
const double _shaftRadius = 0.02;

/// What a screen-sized gizmo needs to know about the camera.
///
/// **The gizmo is the same size on screen however far away the thing is, and
/// that is not a preference.** A manipulator drawn a fixed number of metres
/// long is a manipulator that fills the window when the camera comes in to look
/// at a bevel and shrinks under the cursor when it pulls back to see the whole
/// model — at which point the arrows are a few pixels of clutter that cannot be
/// hit. The overlay's vertex handles are sized in pixels for exactly this
/// reason, and a gizmo that disagreed with the overlay would be a second rule
/// for the same question.
///
/// The price is that the arrows move in world space whenever the camera does,
/// so the handles have to be asked for again every frame rather than built once
/// when the selection changes. [gizmoHandles] is therefore cheap and, more
/// importantly, steady: the same pivot and the same camera give the same
/// numbers to the last bit, so a still camera draws a still gizmo.
final class GizmoView {
  const GizmoView({
    required this.eye,
    required this.pixel,
    this.perspective = true,
  });

  /// A camera with a vertical field of view of [fovYRadians] looking at a
  /// viewport [viewportHeight] logical pixels tall.
  ///
  /// The same conversion `MeshOverlay.lookFrom` documents, written out here
  /// rather than reached for through the renderer: a caller that had to build
  /// an overlay to find out how big a pixel is would be a caller that cannot
  /// test a drag without a device.
  factory GizmoView.perspective({
    required Vector3 eye,
    required double fovYRadians,
    required double viewportHeight,
  }) => GizmoView(
    eye: eye,
    pixel: 2.0 * math.tan(fovYRadians / 2.0) / viewportHeight,
  );

  /// An orthographic camera showing [height] metres over a viewport
  /// [viewportHeight] logical pixels tall.
  factory GizmoView.orthographic({
    required Vector3 eye,
    required double height,
    required double viewportHeight,
  }) => GizmoView(eye: eye, pixel: height / viewportHeight, perspective: false);

  /// Where the camera stands.
  final Vector3 eye;

  /// The world size of one logical pixel: at one unit of distance for a
  /// perspective camera, and everywhere for an orthographic one.
  final double pixel;

  /// Whether distance makes things smaller. An orthographic view is the one
  /// case where the depth of the pivot does not enter into it at all, and a
  /// gizmo that multiplied by distance anyway would grow as the camera backed
  /// away from a picture that did not change.
  final bool perspective;

  /// The world size of [pixels] logical pixels at [at].
  double worldSize(double pixels, Vector3 at) =>
      pixels * pixel * (perspective ? (at - eye).length : 1.0);
}

/// One arrow of the gizmo: where it is drawn and where it may be grabbed.
///
/// **The box and the arrow come out of the same call**, which is the whole
/// reason this type exists rather than two lists. Built separately they would
/// agree until the day one of them was tidied, and the failure that day is an
/// arrow drawn in one place and grabbable in another — which reads to a person
/// as the mouse being broken rather than as a gizmo being wrong.
final class GizmoHandle {
  const GizmoHandle({
    required this.axis,
    required this.base,
    required this.headBase,
    required this.tip,
    required this.shaftRadius,
    required this.headRadius,
    required this.min,
    required this.max,
    required this.tint,
  });

  /// Which way this arrow points.
  final GizmoAxis axis;

  /// Where the shaft starts, a little way out from the pivot.
  final Vector3 base;

  /// Where the shaft ends and the head begins.
  final Vector3 headBase;

  /// The point of the arrow.
  final Vector3 tip;

  final double shaftRadius;
  final double headRadius;

  /// The box a ray is traced against, fattened by [kGizmoGrabPixels].
  final Vector3 min;

  /// The far corner of that box.
  final Vector3 max;

  /// The arrow's colour as `0xRRGGBB` — one of [kGizmoTintX] and its rotations.
  final int tint;

  /// The same colour as the linear-ish triple a `Material` wants.
  Vector3 get colour => Vector3(
    ((tint >> 16) & 0xFF) / 255.0,
    ((tint >> 8) & 0xFF) / 255.0,
    (tint & 0xFF) / 255.0,
  );
}

/// The three arrows for a thing at [pivot], seen from [view].
///
/// **One length for all three, measured at the pivot.** The obvious
/// alternative is to size each arrow by the depth of its own tip, which sounds
/// more correct and is circular: the tip's depth is what the length decides.
/// Solved by iterating it, the arrow pointing towards the camera grows and the
/// one pointing away shrinks, so a gizmo that should read as three equal arms
/// reads as a perspective drawing of one — and the arm nearest the camera then
/// covers the model. One length, taken where the thing being moved actually is,
/// is both steadier and what a person expects to see.
List<GizmoHandle> gizmoHandles(Vector3 pivot, GizmoView view) {
  final length = view.worldSize(kGizmoPixels, pivot);
  // The head is wider than the slack when the camera is close, and a head that
  // stuck out of its own grab box would be an arrow whose point cannot be
  // clicked — which is the part of it a hand aims at.
  final slack = math.max(
    view.worldSize(kGizmoGrabPixels, pivot),
    length * _headRadius,
  );

  return <GizmoHandle>[
    for (final axis in GizmoAxis.values)
      () {
        final direction = axis.direction;
        final base = pivot + direction * (length * _shaftStart);
        final tip = pivot + direction * length;
        // **Sideways only.** A hand aims across a thin line rather than past
        // its ends, so the slack goes on the two axes the arrow does not run
        // along. Fattened at the ends as well, all three boxes would swallow
        // the pivot — and a click on the thing being edited would then take
        // hold of whichever arm happened to be listed first.
        final sideways = Vector3.all(slack) - direction * slack;
        return GizmoHandle(
          axis: axis,
          base: base,
          headBase: pivot + direction * (length * _headStart),
          tip: tip,
          shaftRadius: length * _shaftRadius,
          headRadius: length * _headRadius,
          min: _minOf(base, tip) - sideways,
          max: _maxOf(base, tip) + sideways,
          tint: switch (axis) {
            GizmoAxis.x => kGizmoTintX,
            GizmoAxis.y => kGizmoTintY,
            GizmoAxis.z => kGizmoTintZ,
          },
        );
      }(),
  ];
}

/// Every number [handles] is made of, in one array.
///
/// **For asking whether two frames drew the same gizmo.** A still camera over a
/// still selection has to produce the same picture twice; the way that fails in
/// practice is a scale eased towards its target from the last frame's value, or
/// a length quantised against a frame counter, both of which look like a gizmo
/// that shivers when nothing is happening. Comparing the bytes of this catches
/// that at the point where it can still be explained, rather than as two
/// renders that differ by a pixel somewhere.
Float64List gizmoGeometry(List<GizmoHandle> handles) {
  final out = Float64List(handles.length * 17);
  var at = 0;
  void put(Vector3 v) {
    out[at++] = v.x;
    out[at++] = v.y;
    out[at++] = v.z;
  }

  for (final handle in handles) {
    put(handle.base);
    put(handle.headBase);
    put(handle.tip);
    out[at++] = handle.shaftRadius;
    out[at++] = handle.headRadius;
    put(handle.min);
    put(handle.max);
  }
  return out;
}

/// Which arrow a ray meets first.
///
/// **Traced against boxes rather than read from a pixel**, because the decision
/// between dragging a thing and turning the camera has to be made in the
/// handler for the press. The id pass answers a frame later and may refuse
/// altogether; a press that waited for it would be a press that orbits the
/// camera and then jumps when the answer arrives.
final class GizmoHit {
  const GizmoHit({required this.handle, required this.at, required this.away});

  /// The arrow that was hit.
  final GizmoHandle handle;

  /// Where on it the ray landed, in world space.
  final Vector3 at;

  /// How far along the ray that is.
  final double away;

  GizmoAxis get axis => handle.axis;

  /// The nearest of [handles] the ray from [eye] along the unit vector [along]
  /// enters, or null when it enters none.
  ///
  /// Ties go to the earlier axis, which is X then Y then Z. With the slack the
  /// constants above choose, the three boxes do not reach each other at all, so
  /// nothing anybody can see depends on that rule today; it is written down so
  /// that a later hand widening the slack changes a stated rule rather than an
  /// accident.
  static GizmoHit? nearest(
    List<GizmoHandle> handles,
    Vector3 eye,
    Vector3 along,
  ) {
    GizmoHandle? found;
    var nearest = double.infinity;
    for (final handle in handles) {
      final distance = _boxHit(handle.min, handle.max, eye, along);
      if (distance == null || distance >= nearest) continue;
      nearest = distance;
      found = handle;
    }
    if (found == null) return null;
    return GizmoHit(handle: found, at: eye + along * nearest, away: nearest);
  }
}

/// A thing being dragged along one arrow of the gizmo.
///
/// **A whole drag is one undo step, and this type is how that is said.** A
/// pointer reports sixty times a second, and a drag written into the history on
/// every report is sixty steps a second: the sixty-four a person has are gone
/// before the button comes up, and the change they actually wanted back went
/// with them. So this records nothing at all. It accumulates [offset] — where
/// the thing has got to relative to where it started — and the caller moves the
/// object straight to `start + offset` for the picture while the button is
/// down. When the button comes up, the caller puts the object back and applies
/// [offset] once, inside one transaction, and the stack gains a single step
/// whose snapshot is the document as it stood before anybody touched the mouse.
///
/// The alternative shape — hand the drag a document and a history and let it do
/// all this itself — was rejected because it would make the arithmetic here
/// impossible to test without building a document, and the arithmetic is the
/// part that goes wrong.
final class GizmoDrag {
  GizmoDrag._(this.axis, this.grabbed, this.step);

  /// Which way the arrow that was grabbed runs.
  final GizmoAxis axis;

  /// The point of the arrow the pointer took hold of.
  ///
  /// **The line a drag is measured along runs through here, not through the
  /// pivot.** Take hold of the tip of an arrow and the thing follows the hand;
  /// measured from the pivot instead, the first report would teleport it by the
  /// length of the arrow, because that is where the pivot would have to be for
  /// the *pivot* to be under the cursor.
  final Vector3 grabbed;

  /// How far a snapped drag travels per step, in metres.
  final double step;

  final Vector3 _offset = Vector3.zero();

  /// How many reports have moved it, which is what the one step at the end is
  /// standing in for.
  int _moves = 0;

  /// Where the dragged thing has got to, relative to where it started.
  ///
  /// A copy: the caller adds this to a position it owns, and a drag whose
  /// running total could be written to from outside would be a drag that
  /// disagrees with the pointer.
  Vector3 get offset => Vector3.copy(_offset);

  /// How many pointer reports have changed [offset]. Only interesting as the
  /// number of history steps this gesture is *not* leaving behind.
  int get moves => _moves;

  /// Whether the thing ended up anywhere other than where it started.
  ///
  /// A drag that went nowhere is not a change, and an undo that has to be
  /// pressed twice because the first press does nothing visible is an undo
  /// nobody trusts.
  bool get moved => _offset.length2 > 1e-12;

  /// Takes hold of whichever of [handles] the ray from [eye] along the unit
  /// vector [along] hits, or answers null when it hits none — in which case the
  /// press belongs to the camera, which is what keeps looking around reachable
  /// without a modifier or a second button.
  static GizmoDrag? start(
    List<GizmoHandle> handles,
    Vector3 eye,
    Vector3 along, {
    double step = kGizmoSnap,
  }) {
    final hit = GizmoHit.nearest(handles, eye, along);
    if (hit == null) return null;
    return GizmoDrag._(hit.axis, Vector3.copy(hit.at), step);
  }

  /// Takes the thing to where the ray from [eye] along [along] now points, and
  /// answers whether that changed anything.
  ///
  /// The pointer is on a screen and the thing is on a line, so what is asked is
  /// where the two come closest: the point of the axis the pointer is nearest
  /// to aiming at. A ray that runs nearly along the axis has no such point
  /// worth having — a pixel of movement would be metres of travel — and that is
  /// the one case this refuses. The thing stays where it is until the camera is
  /// somewhere the drag can be aimed from, which is much better than the thing
  /// shooting off to the horizon while the hand is still.
  ///
  /// With [snap] the travel is rounded to whole [step]s. The travel and not the
  /// resulting position, which is the difference between Ctrl meaning "move by
  /// quarter metres" and Ctrl meaning "jump onto my grid". A model opened from
  /// a file has its parts where its author put them, at no round number at all,
  /// and snapping the position would tear a wheel off its axle on the first
  /// report of the pointer purely because the modifier was held.
  bool moveTo(Vector3 eye, Vector3 along, {bool snap = false}) {
    final line = axis.direction;
    final facing = line.dot(along);
    final spread = 1.0 - facing * facing;
    if (spread < 1e-3) return false;

    final between = grabbed - eye;
    final travelled =
        (facing * along.dot(between) - line.dot(between)) / spread;
    final wanted =
        line *
        (snap && step > 0.0
            ? (travelled / step).roundToDouble() * step
            : travelled);

    if ((wanted - _offset).length2 < 1e-18) return false;
    _offset.setFrom(wanted);
    _moves++;
    return true;
  }

  /// What to call the one step this gesture leaves behind.
  String get label =>
      'move by ${_offset.x.toStringAsFixed(2)}, '
      '${_offset.y.toStringAsFixed(2)}, ${_offset.z.toStringAsFixed(2)}';
}

Vector3 _minOf(Vector3 a, Vector3 b) =>
    Vector3(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z));

Vector3 _maxOf(Vector3 a, Vector3 b) =>
    Vector3(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z));

/// How far along [along] the ray from [from] enters the box [min]–[max], or
/// null if it never does.
///
/// The slab test, the same one the level editor's picker uses: clip the ray
/// against each pair of parallel faces in turn and see whether anything is
/// left. A ray that starts inside the box enters it at nought, which is how a
/// press made while the camera sits inside the gizmo still grabs an arm.
double? _boxHit(Vector3 min, Vector3 max, Vector3 from, Vector3 along) {
  var enter = 0.0;
  var leave = double.infinity;

  for (var axis = 0; axis < 3; axis++) {
    final direction = along[axis];
    final origin = from[axis];
    if (direction.abs() < 1e-9) {
      if (origin < min[axis] || origin > max[axis]) return null;
      continue;
    }
    final one = (min[axis] - origin) / direction;
    final other = (max[axis] - origin) / direction;
    enter = math.max(enter, math.min(one, other));
    leave = math.min(leave, math.max(one, other));
    if (enter > leave) return null;
  }
  return enter;
}
