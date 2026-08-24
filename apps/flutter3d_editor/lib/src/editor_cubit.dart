import 'package:flutter_bloc/flutter_bloc.dart';

import 'editing.dart';
import 'editor_state.dart';
import 'looks.dart';
import 'palette_items.dart';
import 'scaffold.dart';

export 'editor_state.dart';

/// The screen's answers to what the document is doing.
///
/// **A thin layer over `Editing`, `Documents` and `Looks`, not a rewrite of
/// any of them.** Reading a file, parsing a level and deciding whether a save
/// is allowed already live in classes that need no window and are already
/// tested that way — see `documents_test.dart` and `editing_test.dart`. What
/// this adds is the part those do not answer: which screen a person sees, and
/// what the strip along the bottom says about the last thing that happened.
/// Every method here is a state transition somebody could write down as a
/// sentence, which is what makes it reachable from a plain `test()` — see
/// `test/editor_cubit_test.dart`.
///
/// The states themselves are in `editor_state.dart` and re-exported here, the
/// way `run_session.dart` holds `RunStatus` and `run_cubit.dart` holds the
/// wrapper: what a document is doing and how a screen watches it are two
/// different questions, and this file only answers the second one.
final class EditorCubit extends Cubit<EditorState> {
  EditorCubit() : super(const EditorOpening());

  /// Nothing is at [path] yet — here are the templates on offer instead.
  void nothingFound(List<Template> templates, {required String path}) =>
      emit(EditorChoosing(templates, said: 'nothing at $path yet'));

  /// A document opened, and this is what it opened to.
  ///
  /// The message matches what the editor has always said on opening: how many
  /// brushes, and who owns the file if this editor may not save over it.
  void opened(Editing editing, {String? assetRoot, required Looks looks}) =>
      emit(EditorReady(
        editing: editing,
        assetRoot: assetRoot,
        looks: looks,
        said: 'opened ${editing.level.brushes.length} brushes'
            '${editing.mayOverwrite ? '' : ' — written by ${editing.generatedBy}'}',
      ));

  /// Nothing could be opened at all — a device that would not start, or a
  /// document that would not parse.
  void failed(Object error) => emit(EditorFailed(error));

  /// Something in the chooser is worth saying, without leaving it — the
  /// project directory was not empty, or the disk refused to write.
  void choosingSaid(String said) {
    final current = state;
    if (current is EditorChoosing) {
      emit(EditorChoosing(current.templates, said: said));
    }
  }

  /// After a change to the open document — a nudge, a delete, a save — what
  /// happened, for the strip along the bottom.
  ///
  /// The one method most key presses and mouse clicks end in. Named the same
  /// as the render loop's own `_stale = true`, which a caller sets alongside
  /// this and which this does not: whether the scene needs rebuilding is the
  /// render loop's question, not this cubit's — see `_EditorScreenState`.
  void say(String said) => _updateReady((EditorReady it) => it.copyWith(said: said));

  /// Which axis `−`/`=` and the arrow keys resize along.
  void setAxis(EditorAxis axis) =>
      _updateReady((EditorReady it) => it.copyWith(axis: axis));

  /// Flips the editor's own lamp and says so. Returns the new value so the
  /// caller can push it onto the light node it owns.
  bool toggleLamp() {
    final current = state;
    if (current is! EditorReady) return true;
    final on = !current.lampOn;
    emit(current.copyWith(
      lampOn: on,
      said: on
          ? "the editor's lamp is on"
          : "the editor's lamp is off — this is the level's own light",
    ));
    return on;
  }

  /// Shows or hides everything of [type], and says which.
  void toggleHidden(String type, {required String label}) {
    final current = state;
    if (current is! EditorReady) return;
    final hidden = Set<String>.of(current.hidden);
    final hiding = !hidden.remove(type);
    if (hiding) hidden.add(type);
    emit(current.copyWith(
      hidden: hidden,
      said: hiding
          ? '$label hidden — alt-click again to show'
          : '$label shown',
    ));
  }

  /// Arms or disarms the palette. Null puts nothing down; a row arms the next
  /// click to place it.
  void setPlacing(Placeable? placing) {
    final current = state;
    if (current is! EditorReady) return;
    emit(current.copyWith(
      placing: placing,
      said: placing == null
          ? 'nothing to place'
          : 'click in the level to place a ${placing.label}',
    ));
  }

  void _updateReady(EditorReady Function(EditorReady) f) {
    final current = state;
    if (current is EditorReady) emit(f(current));
  }
}
