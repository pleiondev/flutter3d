/// What the hands on the input device meant the camera to do.
///
/// **Pure Dart, and no gesture recogniser.** Flutter's recognisers arbitrate in
/// an arena, which is a good answer to "who owns this drag" and a bad place to
/// keep the rule that a stylus never orbits: the rule has to hold for a pen
/// that is drawing a stroke a recogniser already lost the arena for. So the
/// mapping from device to camera lives here as a value machine that anybody can
/// feed — a widget's `Listener`, a test, or the replay of a recorded session —
/// and the widget layer above is left with nothing but the translation of
/// `PointerEvent` into the small types below.
///
/// **Intentions, not camera moves.** Nothing here holds an `OrbitController` or
/// a `Vector3`. Each call answers with a [CameraIntent], and something else
/// decides which viewport it lands in and whether the camera is even allowed to
/// move right now. That separation is what makes a second viewport, a locked
/// camera, or an undoable camera cost nothing here.
///
/// **Sensitivity is not ours.** Every delta out of this file is in logical
/// pixels of pointer travel, and [CameraIntent.zoomBy] is a bare multiplier.
/// `OrbitController` already owns `rotateSensitivity` and already scales panning
/// by distance; a second set of tuning constants here would mean two places to
/// change when a drag feels wrong, and the two would drift.
library;

import 'dart:math' as math;

/// The kind of thing that produced an event.
///
/// This is the whole reason the file exists: the same two-hundred-pixel drag
/// means orbit from a finger, pan from a trackpad and *nothing at all* from a
/// pen, so the kind has to survive all the way from the platform to the
/// decision. Flutter's own `PointerDeviceKind` has `invertedStylus`, `unknown`
/// and a trackpad that only appears on scroll events; mapping it down to these
/// four at the widget boundary keeps the rules below readable and keeps this
/// file free of a Flutter import.
enum PointerKind {
  /// A mouse, or anything the platform reports as one.
  mouse,

  /// A finger on a touch screen.
  touch,

  /// A trackpad, whose scroll and pinch arrive without a pointer being down.
  trackpad,

  /// A pen. Never moves the camera — see [OrbitGestures].
  stylus,
}

/// Which button started a drag.
///
/// A single button rather than a bitmask of the ones currently held, because
/// the only question ever asked is which button began this drag: a person who
/// presses the left button halfway through a middle-drag orbit has not asked
/// for a different camera move, and reading a live bitmask would give them one.
enum GestureButton {
  /// Left, on a right-handed mouse. Belongs to the tools, not the camera.
  primary,

  /// The wheel pressed in.
  middle,

  /// Right. Belongs to the context menu.
  secondary,
}

/// The keyboard state a gesture was started with.
///
/// **Latched at the press, never re-read.** Holding shift after a middle-drag
/// orbit has begun does not turn it into a pan; the camera would jump, because
/// the same pixels of travel mean a rotation in one mode and a translation in
/// the other, and a mode that changes under a moving hand is a mode nobody can
/// aim. So [OrbitGestures.pointerDown] takes these and [OrbitGestures.pointerMove]
/// does not.
final class GestureModifiers {
  const GestureModifiers({
    this.shift = false,
    this.control = false,
    this.alt = false,
  });

  /// Nothing held.
  static const GestureModifiers none = GestureModifiers();

  /// Shift: with the middle button, pan instead of orbit.
  final bool shift;

  /// Control: with a trackpad scroll, zoom instead of pan. This is not a
  /// preference, it is what a browser delivers a trackpad pinch as.
  final bool control;

  /// Alt. Read by nothing here yet; carried so the widget layer has one type
  /// to fill in rather than two.
  final bool alt;

  @override
  bool operator ==(Object other) =>
      other is GestureModifiers &&
      other.shift == shift &&
      other.control == control &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(shift, control, alt);
}

/// A point in a viewport, in logical pixels, y growing downward.
///
/// Its own type rather than `Offset` so this file compiles without Flutter, and
/// a record rather than a class was rejected only because a named type is what
/// makes the y-down convention documentable in one place.
final class GesturePoint {
  const GesturePoint(this.x, this.y);

  /// Distance from the left edge of the viewport.
  final double x;

  /// Distance from the top edge, growing downward, as every screen coordinate
  /// in Flutter does.
  final double y;
}

/// What the camera should do, as plain numbers.
///
/// **One value carries all three axes, because one gesture can mean all three.**
/// Two fingers pinching while they slide is not a zoom that a pan interrupts —
/// it is a single motion whose scale part and centroid part happen at once, and
/// a caller that had to choose between a `ZoomIntent` and a `PanIntent` would
/// drop half of it. So every method returns one of these and the fields that
/// did not happen are at rest.
///
/// **Signs are up-positive, and the applier negates.** [deltaPitch] and [panUp]
/// are positive when the hand moved toward the top of the screen, whereas
/// screen y and `OrbitController`'s own arguments grow downward. Naming a field
/// `panUp` and having it mean "down" was the alternative, and it is the kind of
/// thing that is read wrongly once and then debugged for an hour.
final class CameraIntent {
  const CameraIntent({
    this.deltaYaw = 0.0,
    this.deltaPitch = 0.0,
    this.panRight = 0.0,
    this.panUp = 0.0,
    this.zoomBy = 1.0,
  });

  /// The camera stays where it is.
  static const CameraIntent none = CameraIntent();

  /// Pixels of horizontal travel to orbit by, positive to the right.
  final double deltaYaw;

  /// Pixels of vertical travel to orbit by, positive upward.
  final double deltaPitch;

  /// Pixels the grabbed content should slide right by.
  final double panRight;

  /// Pixels the grabbed content should slide up by.
  final double panUp;

  /// Multiplier on the orbit distance. Below one moves closer, one is at rest.
  ///
  /// Multiplicative rather than a number of pixels, because a notch of wheel has
  /// to mean the same thing framing a whole building and framing one of its
  /// bolts, and only a ratio does.
  final double zoomBy;

  /// Whether applying this would move the camera at all.
  ///
  /// Worth having so a viewport can skip marking itself dirty on the events
  /// that meant nothing — a stylus stroke is a flood of moves, and every one of
  /// them answers [none] here.
  bool get movesCamera =>
      deltaYaw != 0.0 ||
      deltaPitch != 0.0 ||
      panRight != 0.0 ||
      panUp != 0.0 ||
      zoomBy != 1.0;
}

/// Turns a stream of pointer and scroll events into camera intentions.
///
/// The rules it exists to hold, and why each one is the way it is:
///
/// **A stylus never moves the camera.** A pen is for drawing on the model, and
/// a model that swings away under the nib is a sculpting tool nobody can use:
/// the stroke lands somewhere other than where it was aimed, and the person
/// undoes it and tries again with a hand they have to hold stiller than the
/// camera. The obvious alternative — let the pen orbit when no tool is armed —
/// fails on the case that matters, because "no tool armed" is exactly the state
/// somebody is in the moment before they arm one, and the camera has already
/// moved by then. So the pen is refused here, unconditionally, rather than
/// asked about later.
///
/// **Two fingers is one gesture with two outputs.** Fingers spreading while
/// they slide across the glass is a single hand movement, and answering it with
/// only the pinch leaves the model drifting off under the fingers that were
/// plainly dragging it. So a two-finger move reports both the distance change,
/// from how the spread between them changed, and the pan, from how their
/// midpoint moved — in one [CameraIntent].
///
/// **A trackpad's two-finger scroll pans; a pinch zooms.** Wiring the scroll to
/// zoom is the single most complained-about thing in 3D applications, because
/// the same two fingers scroll a document everywhere else on the machine and
/// the hand has already learnt what they do. The pinch is the gesture that
/// means "bigger" on every photo anybody has ever looked at, so it is the one
/// that changes the distance. Note that a browser delivers a trackpad pinch as
/// a scroll with control held, which is why [GestureModifiers.control] on a
/// trackpad scroll zooms rather than pans.
///
/// **A mouse orbits on the middle button, pans on shift and the middle button,
/// and zooms on the wheel.** The left button is left alone on purpose: it is
/// what clicks a vertex, drags a gizmo and paints a weight, and a camera that
/// also took it would be a camera that fought every tool in the application.
///
/// Feed it whole: [pointerDown], [pointerMove] and [pointerUp] for pointers,
/// [scroll] for wheels and trackpad scrolls, [pinchStart]/[pinchUpdate] for a
/// trackpad's scale gesture. It keeps only what it needs to compute a delta,
/// so dropping it on the floor mid-drag costs nothing.
final class OrbitGestures {
  OrbitGestures({this.zoomPerScrollPixel = 0.0015});

  /// How much of a zoom a pixel of scroll is worth, before exponentiation.
  ///
  /// Exposed because a wheel notch is a hundred pixels on one platform and
  /// three lines on another, and the widget layer is the only thing that knows
  /// which. At the default, one notch of a hundred is about sixteen per cent.
  final double zoomPerScrollPixel;

  /// Live pointers, in the order they went down — a plain map literal, which
  /// Dart specifies as insertion-ordered, and that order is what makes "the two
  /// fingers" a well-defined pair when a third arrives.
  final Map<int, _Pointer> _active = <int, _Pointer>{};

  /// The midpoint and spread of the two fingers as of the last event, or null
  /// when there are not exactly two down.
  GesturePoint? _touchCentre;
  double _touchSpread = 0.0;

  /// The cumulative scale of the trackpad pinch in progress, so [pinchUpdate]
  /// can report the step rather than the total.
  double _pinchScale = 1.0;

  /// Whether any pointer that could move the camera is down.
  ///
  /// A viewport reads this to decide whether to keep a hover highlight alive.
  bool get isDragging =>
      _active.values.any((_Pointer p) => p.role != _Role.idle);

  /// How many fingers are on the glass. A stylus is not one of them.
  int get fingerCount => _fingers.length;

  Iterable<_Pointer> get _fingers =>
      _active.values.where((_Pointer p) => p.kind == PointerKind.touch);

  /// Registers a pointer going down, and decides then and there what it means.
  ///
  /// A press never moves the camera by itself, so this always answers
  /// [CameraIntent.none]; it returns one anyway so a caller can treat all four
  /// entry points alike rather than remembering which of them are void.
  CameraIntent pointerDown(
    int pointer, {
    required PointerKind kind,
    required GesturePoint at,
    GestureButton button = GestureButton.primary,
    GestureModifiers modifiers = GestureModifiers.none,
  }) {
    _active[pointer] = _Pointer(
      kind: kind,
      at: at,
      role: _roleFor(kind: kind, button: button, modifiers: modifiers),
    );
    // A finger arriving or leaving changes what the pair is, and the pair's
    // baseline has to be the positions as of now. Carrying the old midpoint
    // across would answer the next move with the whole distance between the
    // old pair and the new one, which reads as the model being flung.
    _resyncTouch();
    return CameraIntent.none;
  }

  /// Reports where a pointer has moved to, and what that means for the camera.
  ///
  /// Takes a position rather than a delta because the platform's own deltas are
  /// not trustworthy across a pointer being added or removed, and because two
  /// fingers need absolute positions to have a midpoint and a spread at all.
  CameraIntent pointerMove(int pointer, GesturePoint to) {
    final _Pointer? tracked = _active[pointer];
    if (tracked == null) return CameraIntent.none;

    final GesturePoint from = tracked.at;
    tracked.at = to;

    final double dx = to.x - from.x;
    final double dy = to.y - from.y;

    if (tracked.kind == PointerKind.touch && _fingers.length != 1) {
      return _touchMove();
    }
    if (tracked.role == _Role.idle) return CameraIntent.none;

    return switch (tracked.role) {
      _Role.orbit => CameraIntent(deltaYaw: dx, deltaPitch: -dy),
      _Role.pan => CameraIntent(panRight: dx, panUp: -dy),
      _Role.idle => CameraIntent.none,
    };
  }

  /// Forgets a pointer. Also used for a cancelled one: a drag the platform took
  /// away and a drag that ended leave exactly the same state behind.
  CameraIntent pointerUp(int pointer) {
    _active.remove(pointer);
    _resyncTouch();
    return CameraIntent.none;
  }

  /// A wheel notch or a trackpad's two-finger scroll.
  ///
  /// [dy] is positive scrolling down, as every platform reports it, and down
  /// means away — the wheel that scrolls a page down also pushes the model back.
  CameraIntent scroll({
    required PointerKind kind,
    double dx = 0.0,
    double dy = 0.0,
    GestureModifiers modifiers = GestureModifiers.none,
  }) {
    switch (kind) {
      case PointerKind.mouse:
        return CameraIntent(zoomBy: math.exp(dy * zoomPerScrollPixel));
      case PointerKind.trackpad:
        if (modifiers.control) {
          return CameraIntent(zoomBy: math.exp(dy * zoomPerScrollPixel));
        }
        // A scroll moves the view, not the content, which is why both signs
        // are the other way round from a drag: scrolling down takes the view
        // downward, so the model on it rises. Matching a drag instead would
        // make the trackpad disagree with every scrollable thing on the
        // machine, which is the complaint this whole arm exists to avoid.
        return CameraIntent(panRight: -dx, panUp: dy);
      case PointerKind.touch:
      case PointerKind.stylus:
        // Neither device produces a scroll of its own; anything arriving here
        // labelled as one is the platform guessing, and a camera that moved on
        // a guess would move under a pen.
        return CameraIntent.none;
    }
  }

  /// A trackpad scale gesture beginning.
  void pinchStart() => _pinchScale = 1.0;

  /// A trackpad scale gesture continuing, where [scale] is the total since
  /// [pinchStart] — which is what the platform reports and what a `ScaleUpdate`
  /// carries.
  ///
  /// Answers the step rather than the total, so a caller can apply every update
  /// as it arrives instead of tracking what it has already applied.
  CameraIntent pinchUpdate(double scale) {
    if (scale <= 0.0) return CameraIntent.none;
    final double step = _pinchScale / scale;
    _pinchScale = scale;
    return CameraIntent(zoomBy: step);
  }

  /// Decides once, at the press, what a pointer is for.
  ///
  /// The stylus refusal lives here rather than in [pointerMove] so that a pen is
  /// tracked with no role at all: it still takes part in nothing, and no later
  /// change of mind — a modifier, a mode, a second device — can give a pen a
  /// camera move it was not granted at the start.
  _Role _roleFor({
    required PointerKind kind,
    required GestureButton button,
    required GestureModifiers modifiers,
  }) {
    if (kind == PointerKind.stylus) return _Role.idle;
    if (kind == PointerKind.touch) return _Role.orbit;
    if (kind != PointerKind.mouse) return _Role.idle;
    if (button != GestureButton.middle) return _Role.idle;
    return modifiers.shift ? _Role.pan : _Role.orbit;
  }

  /// What a move means when more than one finger is down.
  ///
  /// One finger orbits from its own previous position, which [pointerMove]
  /// handles; two pinch and slide at once; three or more mean nothing, because
  /// three fingers is a system gesture on macOS and on most Android launchers
  /// and a camera that also answered it would fight the window manager. When
  /// the count drops back to two the baseline is resynced, so nothing is flung.
  CameraIntent _touchMove() {
    final List<_Pointer> fingers = _fingers.toList(growable: false);
    if (fingers.length != 2) return CameraIntent.none;

    final GesturePoint? previousCentre = _touchCentre;
    final double previousSpread = _touchSpread;
    _syncTouchPair(fingers);
    if (previousCentre == null) return CameraIntent.none;

    final GesturePoint centre = _touchCentre!;
    // Below a pixel of spread the ratio is noise — two fingers that close are
    // one contact the digitiser has not merged yet, and dividing by it throws
    // the camera to the far side of the model.
    final double zoom = previousSpread > 1.0 && _touchSpread > 1.0
        ? previousSpread / _touchSpread
        : 1.0;
    return CameraIntent(
      panRight: centre.x - previousCentre.x,
      panUp: -(centre.y - previousCentre.y),
      zoomBy: zoom,
    );
  }

  /// Rebuilds the two-finger baseline after the set of fingers changed.
  void _resyncTouch() {
    final List<_Pointer> fingers = _fingers.toList(growable: false);
    if (fingers.length != 2) {
      _touchCentre = null;
      _touchSpread = 0.0;
      return;
    }
    _syncTouchPair(fingers);
  }

  void _syncTouchPair(List<_Pointer> fingers) {
    final GesturePoint a = fingers[0].at;
    final GesturePoint b = fingers[1].at;
    _touchCentre = GesturePoint((a.x + b.x) / 2.0, (a.y + b.y) / 2.0);
    _touchSpread = math.sqrt(
      (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y),
    );
  }
}

/// What a pointer was granted at the moment it went down.
enum _Role { idle, orbit, pan }

/// One live pointer: the only mutable state in the file, and it is a position.
final class _Pointer {
  _Pointer({required this.kind, required this.at, required this.role});

  final PointerKind kind;
  final _Role role;
  GesturePoint at;
}
