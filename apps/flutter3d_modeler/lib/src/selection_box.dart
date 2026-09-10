/// The rectangle a person drags across the viewport, and what letting go of it
/// does to the selection.
///
/// **`pickElementsIn` has been written and tested since view-10 and has never
/// had a caller, because the arithmetic it needs is not the hard part.** Given a
/// rectangle it hands back everything of one level inside the frustum that
/// rectangle cuts. What was missing is the gesture around it: where the
/// rectangle came from, whether the person meant a rectangle at all, and what
/// the ids that came back are supposed to do to the ids that were already
/// selected. That is this file, and it is three questions rather than one
/// because each of them is answered wrong by an obvious guess.
///
/// **Nothing here is a widget and nothing here draws.** A drag is two points, a
/// pointer kind and a modifier, so a test can ask what letting go at (410, 88)
/// selects without a window, a gesture recogniser or a frame — the same bargain
/// `element_picking.dart` struck for clicks. The overlay that shows the
/// rectangle while it is being dragged is the widget's half, and it reads
/// [SelectionBox.rect] like everybody else.
library;

import 'dart:ui' show Offset, PointerDeviceKind, Rect;

/// How far a mouse, a trackpad or a stylus has to travel before the drag is a
/// rectangle rather than a click, in logical pixels.
///
/// **Half the pick slack, and half for a reason.** `cursorPickSlack` is eight
/// logical pixels because that is how far a person's aim is uncertain by when
/// they click; a rectangle does not have to be big enough to *hit* anything, it
/// only has to be big enough to have been *meant*, and a hand that pulled a
/// pressed mouse four pixels across the screen pulled it deliberately.
///
/// Flutter's own recogniser would let a much smaller drag through —
/// `kPrecisePointerPanSlop` is two logical pixels, against the `kPanSlop` of
/// thirty-six a coarse pointer has to clear — but the viewport listens to raw
/// pointer events rather than owning a pan recogniser, so no recogniser slop is
/// applied to this gesture at all and the number below is the only one there
/// is.
const double cursorBoxSlop = 4.0;

/// The same distance for a fingertip, which is three times as much.
///
/// The three is the ratio `element_picking.dart` measured and argued: a cursor
/// puts a visible hotspot where the person aimed, and a fingertip presses eight
/// to ten millimetres of glass and hides all of it, so the same deliberate
/// press carries about three times the doubt. Setting one number for both fails
/// in whichever direction it is set — four everywhere turns the roll of a
/// thumb into a rectangle that wipes the selection out, and twelve everywhere
/// makes a small deliberate box with a mouse do nothing at all.
const double fingerBoxSlop = 12.0;

/// The travel [pointer] has to cover before a drag is a rectangle.
///
/// An unknown device is treated as a finger, matching `pickSlackFor`: reading a
/// deliberate small box as a click costs one repeated gesture, and reading a
/// wobble as a box in replace mode throws the selection away.
double boxSlopFor(PointerDeviceKind pointer) => switch (pointer) {
  PointerDeviceKind.touch || PointerDeviceKind.unknown => fingerBoxSlop,
  _ => cursorBoxSlop,
};

/// What a released rectangle does to the selection it found.
///
/// **Three modes rather than a `bool extend`, and that is the difference
/// between a box and a click.** `applyPick` takes one flag because a click has
/// exactly one spare modifier: shift on an object already selected has to
/// remove it, since otherwise nothing can ever be dropped out of a selection of
/// thirty without building twenty-nine of it again. A rectangle has a second
/// modifier free, so it can say "take these away" outright — and once it can,
/// making shift toggle as well would be actively wrong. A click toggles one
/// element the person is looking at; a rectangle covers a region whose contents
/// the person cannot fully see, often including things they selected a gesture
/// ago, and a toggle there silently drops exactly the overlap they were trying
/// to keep. Symmetric difference was the alternative and this is why it was not
/// taken: shift means "amend without discarding" in both files, and the click's
/// removal is shift standing in for the subtract gesture a click has not got.
enum SelectionBoxMode {
  /// The rectangle's catch, and nothing else. What a bare drag means, and the
  /// only mode that can end with fewer things selected than were caught.
  replace,

  /// Shift: everything already selected, plus the catch.
  add,

  /// Control, or command on a Mac: everything already selected, less the catch.
  subtract;

  /// The mode the modifiers being held down ask for.
  ///
  /// Subtract wins when both are down. Refusing to choose would leave
  /// [replace], which discards the whole selection — the one answer somebody
  /// holding two amending modifiers certainly did not ask for. Between the two,
  /// control is the more deliberate reach: shift is often still down from the
  /// gesture before.
  static SelectionBoxMode forModifiers({
    required bool extend,
    required bool subtract,
  }) => switch ((extend, subtract)) {
    (_, true) => SelectionBoxMode.subtract,
    (true, _) => SelectionBoxMode.add,
    _ => SelectionBoxMode.replace,
  };
}

/// A selection rectangle part-way through being dragged.
///
/// Mutable, like `TransformModal`, because a drag in progress is state: the
/// corner under the pointer moves every frame and the modifier can change under
/// the person's other hand. What is not state is [from], which is where the
/// button went down and cannot move without the gesture being a different one.
final class SelectionBox {
  /// Starts a rectangle at [from], with both corners in the same place — which
  /// is to say, as a click until it grows.
  SelectionBox({
    required this.from,
    required this.pointer,
    Offset? to,
    this.mode = SelectionBoxMode.replace,
  }) : to = to ?? from;

  /// Where the button went down, in logical pixels within the viewport.
  final Offset from;

  /// What is dragging, which sets how far it has to drag. See [boxSlopFor].
  final PointerDeviceKind pointer;

  /// Where the pointer is now, in the same coordinates.
  Offset to;

  /// What releasing here would do. See [SelectionBoxMode].
  ///
  /// A field rather than a constructor argument, because the modifier that
  /// counts is the one held when the button comes up. People reach for shift
  /// after starting to drag at least as often as before, and a mode fixed at
  /// press time makes the overlay's hint a lie for the rest of the drag.
  SelectionBoxMode mode;

  /// The rectangle the two corners make, whichever way round they were dragged.
  ///
  /// Dragging up and to the left is the same instruction as dragging down and
  /// to the right, so `Rect.fromPoints` normalises rather than anything
  /// refusing. `Rect.fromLTRB` of the two corners was the obvious spelling and
  /// it gives a rectangle of negative width, which reads as empty and quietly
  /// selects nothing for half the drags a person makes.
  Rect get rect => Rect.fromPoints(from, to);

  /// Whether this has grown into a rectangle, or is still a click that wobbled.
  ///
  /// **The whole difference between two instructions.** A click asks
  /// `pickElementAt` about the nearest surface under one point; a rectangle
  /// asks `pickElementsIn` about everything in a region, reaching through the
  /// model. A one-pixel rectangle answered as a rectangle selects whatever
  /// slice of the front face it happened to cover and then, in replace mode,
  /// throws away everything else — so a hand that shook while clicking loses
  /// the selection.
  ///
  /// The longer side rather than both sides or the diagonal: a box two pixels
  /// wide and three hundred tall is somebody selecting a column of vertices and
  /// is unmistakably meant, so requiring both sides to clear the threshold
  /// would refuse the most precise gesture in the set.
  bool get isBox => rect.longestSide >= boxSlopFor(pointer);
}

/// The selection a released rectangle leaves behind, given what it caught.
///
/// [selection] is what was selected before, [caught] is what the rectangle
/// enclosed — `pickElementsIn` for elements, the object-mode equivalent for
/// whole objects, which is why this is generic over the id rather than tied to
/// either. The bound is `Object` rather than a bare `T` so that nobody can
/// instantiate this at `int?`: a null id is a slot no picker ever returns, and
/// all three modes would carry it into the selection a tool then reads as the
/// element to transform. The analyser is what refuses it — `applyBox<int?>`
/// reads `'int?' doesn't conform to the bound 'Object'`, which no test can
/// watch fail, and dropping the bound to `Set<T> applyBox<T>(` was written,
/// run, and left the suite green at twelve tests. It is kept anyway: it costs
/// one word, and the only caller it can inconvenience is one holding a null id
/// it should not have.
///
/// The result is unmodifiable, and a copy even when nothing changed, for the
/// reason `applyPick` gives: handing [selection] or [caught] straight back
/// aliases a set the caller may still be mutating, and the sets here hold a
/// handful of ids against a bug that would be very hard to see. Replace is
/// where that matters most, being the bare drag and the mode with no modifier:
/// there [caught] arrives fresh from `pickElementsIn` today, and returning it
/// unwrapped would publish whatever the picker still holds. Insertion order
/// survives, so the last member is the most recently caught, which is what a
/// tool wanting a single id should read.
Set<T> applyBox<T extends Object>(
  Set<T> selection,
  Set<T> caught, {
  required SelectionBoxMode mode,
}) => Set<T>.unmodifiable(switch (mode) {
  SelectionBoxMode.replace => caught,
  // Already-selected ids stay where they were and the new ones land after
  // them: a person adding a second limb to a selection has not re-picked the
  // first, and moving it to the end would make the active id jump about.
  SelectionBoxMode.add => <T>{...selection, ...caught},
  // Ids in [caught] that were not selected are not an error and not an
  // instruction either. Subtracting something that was never there is what
  // dragging a subtract box across a region that is half selected does, every
  // single time, so it has to be quiet.
  SelectionBoxMode.subtract => selection.where(
    (T held) => !caught.contains(held),
  ),
});
