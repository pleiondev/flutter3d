/// What a `ui.*` MCP tool (`mcp-16d`) can ask this screen to do — the seam
/// between `flutter3d_model_mcp`'s tool table (`dart:io` behind it, through
/// `ModelHttpServer`) and this screen's live `ModelerCubit`, stage and
/// dialogs.
///
/// **A standalone library, not a `part of 'main.dart'`, and importing
/// nothing.** `main.dart` is compiled for the web build too, and
/// `flutter3d_model_mcp`'s own barrel export reaches `dart:io` through
/// `ModelHttpServer` — a web build can never see the inside of that import.
/// `mcp_ui_tools.dart`, which turns a [UiActions] into the real tools
/// `dart_mcp`'s `Tool` type describes, is imported only from
/// `mcp_bootstrap_io.dart`, the file already excluded from a web build by
/// `mcp_bootstrap.dart`'s conditional export; this file is the one both
/// sides can import without either pulling the other's platform in.
library;

/// did/says, the same shape `flutter3d_mcp_kit`'s own `Answer` is — a record,
/// so nothing here needs to import that package to agree with it.
typedef UiAnswer = ({bool did, String says});

/// The seven actions `mcp-16d` offers over MCP, each already a button, a
/// keyboard shortcut or a dialog this screen opens some other way —
/// `_ScreenUiActions` (`screen/mcp_ui.dart`) is the one implementation,
/// wired to this screen's own `ModelerCubit` and stage.
///
/// **Every method takes a plain name, not this app's own enum.** The tool
/// definitions in `mcp_ui_tools.dart` live in a package that has no business
/// knowing `ModelerMode` or `MeshSubmode`, and [setSubmode] in particular has
/// to keep working the day a later track adds a submode enum for a mode
/// besides mesh (`ui-40d`'s `AnimationSubmode`) — this interface's shape does
/// not change either day, only which names [setSubmode]'s own implementation
/// accepts.
abstract interface class UiActions {
  /// Switches to `mode` — one of the mode switcher's own names, lowercase
  /// (`ModelerMode.name`). Refuses cleanly, changing nothing, for anything
  /// else.
  UiAnswer setMode(String mode);

  /// Changes the element level `submode` names, carrying the selection
  /// across the same way picking it by hand does. Refuses cleanly for a name
  /// the open mode's own submode does not have.
  UiAnswer setSubmode(String submode);

  /// Lights the tool rail's `id`, or clears it back to none when `id` is
  /// null — exactly `ModelerCubit.tool`, offered a second way in.
  UiAnswer setTool(String? id);

  /// Points the camera at one of the app's own six standard views. Refuses
  /// cleanly for anything else.
  UiAnswer standardView(String view);

  /// Frames the current subject, the same framing a fresh open already
  /// gives it.
  UiAnswer frameSubject();

  /// Opens one of the app's own dialogs by name, without waiting for it to
  /// close — a screenshot script wants the dialog on screen, not whatever a
  /// person would have chosen in it. Refuses cleanly, both for a name this
  /// app has never heard of and for one it recognises but has not wired a
  /// dialog to yet.
  UiAnswer openDialog(String dialog);

  /// Puts `text` on the status line, marked important so it survives a
  /// routine clear — for a screenshot script to caption the step it is
  /// about to catch.
  UiAnswer say(String text);
}
