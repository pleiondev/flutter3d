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
