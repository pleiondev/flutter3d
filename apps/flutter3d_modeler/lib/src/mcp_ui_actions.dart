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

  /// Presses the rail button `id` stands for — `ux-25`.
  ///
  /// **The difference from [setTool] is the difference between arming and
  /// doing.** `setTool` lights a button and waits for a pointer, which is
  /// what a transform tool wants; this runs the thing, which is what
  /// "Triangulate" or "Duplicate" means and what a person choosing it out of
  /// the command palette gets. One door, so an agent asking for a command by
  /// name lands exactly where a person clicking it does.
  UiAnswer runCommand(String id);

  /// Every id [runCommand] would take, with its label and the mode it
  /// belongs to — the palette's own list, for an agent that has no palette
  /// to look at.
  List<({String id, String label, String mode})> commands();

  /// What has been said this session, since [since] — `ux-26`.
  ///
  /// **The same log the person's own console panel draws, not a second one
  /// kept for agents.** A shared document has two parties working in it, and
  /// the whole point of the row is that each can find out what the other has
  /// been doing; two logs would be two accounts of one session that could
  /// disagree.
  UiAnswer console({DateTime? since});

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

  /// The window as a picture — `ux-44`.
  ///
  /// **What the person sees, which `render` cannot show.** `render` draws
  /// the project through a software rasteriser: the model, framed, with no
  /// panels, no rail, no selection highlight and no dialog. That is the
  /// right picture for "is the shape right" and the wrong one for "did the
  /// export dialog open", "is the modifier stack showing what I added", or
  /// anything an agent writing a tutorial has to catch. This is the window
  /// itself.
  ///
  /// Refuses cleanly when there is no window to capture — the headless
  /// document server has none, and neither does a screen that has not laid
  /// out yet.
  Future<UiPicture> screenshot();
}

/// [UiAnswer] with the picture beside it, for the one action that draws.
typedef UiPicture = ({bool did, String says, List<int>? png});
