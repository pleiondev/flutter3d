/// What a click in the viewport does to the selection.
///
/// **Pulled out of `main.dart` for the reason `transform_dispatch.dart`
/// was.** `_picked` needs the widget for the two things this cannot know —
/// what the renderer's own leaf maps to and whether shift was down — but once
/// those are read out as plain values, deciding the next set of selected ids
/// is arithmetic on a list, checkable without a window.
library;

/// The next set of selected object ids after a click, or null when nothing
/// should change — the caller can then skip the `setState` a repaint would
/// otherwise cost.
///
/// [id] is the document id the click resolved to, already read out of
/// `SceneSync`; null means the click missed every object. [isService] is
/// whether the click landed on the viewport's own furniture — a gizmo's
/// handle, say — rather than on the document or the background: a click
/// there must not clear a selection out from under a drag that is about to
/// start, so it changes nothing even with nothing held. [current] is the
/// selection's own object list before the click; [extend] is whether shift
/// was down.
List<int>? nextSelection({
  required int? id,
  required bool isService,
  required List<int> current,
  required bool extend,
}) {
  final List<int> next;
  if (id == null) {
    if (isService) return null;
    next = extend ? current : const <int>[];
  } else if (!extend) {
    next = <int>[id];
  } else if (current.contains(id)) {
    next = <int>[
      for (final int each in current)
        if (each != id) each,
    ];
  } else {
    next = <int>[...current, id];
  }

  // Compared before returning, because a click on the background with
  // nothing selected is the commonest click there is and it changes
  // nothing: a frame rebuilt for it is a frame spent on an answer of "still
  // nothing".
  if (next.length == current.length && next.every(current.contains)) {
    return null;
  }
  return next;
}

/// What a click inside a mesh is asking for — `ux-28`.
///
/// **Four instructions on one button, told apart by modifiers, because that
/// is what every modeller's hands already know.** The alternative was four
/// rail tools, and it fails the gesture this is for: a loop is chosen by
/// aiming at one edge among hundreds, and a person who has to put the
/// pointer down, cross the window to a button and come back has lost the
/// edge they were aiming at.
enum ElementPickIntent {
  /// A bare click: whatever is under the pointer, and only that.
  replace,

  /// Shift: the element under the pointer goes in, or comes back out if it
  /// was already in — `_pickedElement`'s own long-standing rule.
  toggle,

  /// Alt: the edge loop running through the edge under the pointer.
  loop,

  /// Ctrl+Alt, or ⌘+Alt: the edge ring across it.
  ring;

  /// The instruction the modifiers being held ask for.
  ///
  /// **Alt decides first, and the ring beats the loop.** Alt is the reach
  /// that means "not this element, the run it belongs to", so nothing about
  /// shift can change what kind of answer comes back; adding control on top
  /// turns the run through the edge into the run across it, which is the
  /// pairing the field has settled on and the one a hand learns as "the
  /// other walk". Shift is then left meaning what it means everywhere else
  /// in this application, and it is deliberately not offered as a way to
  /// add a loop to a selection: `SelectEdgeLoop` replaces, as every
  /// selection command in `flutter3d_model_core` does, and pretending
  /// otherwise here would put a second answer to "what does shift mean" in
  /// a second place.
  static ElementPickIntent forModifiers({
    required bool extend,
    required bool alternate,
    required bool control,
  }) => switch ((alternate, control, extend)) {
    (true, true, _) => ElementPickIntent.ring,
    (true, false, _) => ElementPickIntent.loop,
    (false, _, true) => ElementPickIntent.toggle,
    _ => ElementPickIntent.replace,
  };

  /// Whether this one is a walk over the mesh rather than a pick of what is
  /// under the pointer — which is the half that needs an edge to start from,
  /// whatever level the sub-mode is in.
  bool get isWalk =>
      this == ElementPickIntent.loop || this == ElementPickIntent.ring;
}
