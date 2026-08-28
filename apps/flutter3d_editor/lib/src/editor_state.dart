import 'editing.dart';
import 'looks.dart';
import 'palette_items.dart';
import 'scaffold.dart';

/// What the editor's document is doing, as far as a screen is concerned.
///
/// **Everything a screen rebuilds on, and nothing a render loop reads sixty
/// times a second.** The camera, the scene, the gizmos and the selection box
/// stay plain fields on `_EditorScreenState` — see its own doc comment for why
/// a state object per frame is an allocation and a rebuild this application
/// cannot afford. What is here instead is the other half: which document is
/// open, why one is not, and what to say about the last thing that happened —
/// the same split `RunStatus` makes for a game that is *playing* a level,
/// applied to an application that is *editing* one.
///
/// This sealed class rather than `Editing` deciding to be four things at once,
/// because `Editing` already has a job — see its own doc comment — and adding
/// "and also which screen to show" to a class about undo and the grid would be
/// the mistake `EntityRegistry`'s doc records somebody already making about a
/// different class.
sealed class EditorState {
  const EditorState();
}

/// Before anything is known: the device has not opened, or the document has
/// not been looked for yet.
final class EditorOpening extends EditorState {
  const EditorOpening();
}

/// Nothing is at the path this editor was pointed at — here is what a
/// template would write there instead.
///
/// **A path that does not exist is a request to make one**, not a reason to
/// stop — see `EditorCubit.nothingFound`.
final class EditorChoosing extends EditorState {
  const EditorChoosing(this.templates, {required this.said});

  final List<Template> templates;

  /// What to say under the list of templates — usually why it is showing at
  /// all, sometimes why the last attempt to use it did not work.
  final String said;
}

/// A document is open and being edited.
///
/// Carries the live [Editing] rather than a copy of its numbers, the way
/// `RunPlaying` carries a live level: the document is mutated in place by
/// every nudge, resize and delete, and a state class that copied it would be
/// a state class that disagreed with the thing on screen the moment either one
/// changed.
final class EditorReady extends EditorState {
  const EditorReady({
    required this.editing,
    required this.assetRoot,
    required this.looks,
    required this.said,
    this.axis = EditorAxis.x,
    this.lampOn = true,
    this.hidden = const <String>{},
    this.placing,
  });

  final Editing editing;

  /// The directory this document's `assets/…` paths are relative to, if it
  /// has one. Null for a level with no application around it — see
  /// `Documents.assetRootFor`.
  final String? assetRoot;

  /// What this game says its own words look like, if it says anything.
  final Looks looks;

  /// The last thing that happened, for the strip along the bottom.
  final String said;

  /// Which axis the size keys work on.
  final EditorAxis axis;

  /// Whether the editor's own lamp is lit. The light itself is the render
  /// loop's — see `_EditorScreenState._lamp` — this is only what the legend
  /// and the next `_build` read to decide its intensity.
  final bool lampOn;

  /// Types whose marks and models are not drawn.
  final Set<String> hidden;

  /// What the next click in the scene puts down, or null to select instead.
  final Placeable? placing;

  static const Object _unset = Object();

  EditorReady copyWith({
    String? said,
    EditorAxis? axis,
    bool? lampOn,
    Set<String>? hidden,
    Object? placing = _unset,
  }) => EditorReady(
    editing: editing,
    assetRoot: assetRoot,
    looks: looks,
    said: said ?? this.said,
    axis: axis ?? this.axis,
    lampOn: lampOn ?? this.lampOn,
    hidden: hidden ?? this.hidden,
    placing: identical(placing, _unset) ? this.placing : placing as Placeable?,
  );
}

/// Nothing could be opened, and this is why.
final class EditorFailed extends EditorState {
  const EditorFailed(this.error);

  final Object error;
}

/// Which axis the size keys work on.
enum EditorAxis { x, y, z }
