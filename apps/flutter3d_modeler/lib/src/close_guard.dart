/// What a close attempt should do about unsaved work — `ui-24`'s own decision
/// behind `PopScope`, `beforeunload` and the title-bar marker alike, so the
/// same rule holds on every platform that offers a chance to ask.
///
/// **Mirrors `apps/flutter3d_editor`'s own `_askBeforeLeaving`, factored out
/// rather than inlined.** That screen already earns the same three answers —
/// keep editing, close without saving, save and close — and already re-reads
/// `isDirty` after a save rather than assuming it landed; this file is that
/// same shape, kept apart from the dialog and the write it wraps so it can be
/// asked about without a `BuildContext`.
library;

/// The three answers a person can give when a close finds unsaved work.
enum UnsavedChoice {
  /// Nothing happens: the document stays open, exactly as it was.
  keepEditing,

  /// The document closes with today's changes gone.
  discard,

  /// Write first, and only close if that landed.
  save,
}

/// Whether a close attempt should go straight through or ask first.
///
/// The whole of `ui-24`'s own "при isDirty — диалог": a document with nothing
/// unsaved has nothing a close attempt could lose, so there is nothing to ask
/// about.
bool needsConfirmation({required bool isDirty}) => isDirty;

/// The window/tab title's own marker for unsaved work — `ui-24`'s own "маркер
/// в заголовке", kept a pure string function so it is testable the same way
/// as everything else in this file, without a `BuildContext` to build one in.
String windowTitleFor({required bool isDirty}) =>
    isDirty ? '• flutter3d modeller' : 'flutter3d modeller';

/// What actually closing means, once a person has answered the dialog
/// [needsConfirmation] asked for.
///
/// [write] is called only for [UnsavedChoice.save], and its own answer is the
/// only thing that decides whether this returns true — `ui-24`'s own
/// "неудачная запись не закрывает". A save that did not land has not put the
/// document in the state a person asked to leave it in, and closing anyway
/// would lose it exactly as silently as never asking would have.
Future<bool> shouldClose(
  UnsavedChoice choice, {
  required Future<bool> Function() write,
}) async {
  switch (choice) {
    case UnsavedChoice.keepEditing:
      return false;
    case UnsavedChoice.discard:
      return true;
    case UnsavedChoice.save:
      return write();
  }
}
