/// A model editor offered to an agent, over MCP on stdin and stdout.
///
/// **One project per process, for the reason `flutter3d_editor_mcp` opens one
/// level and offers no tool to change it:** the document is the state, and an
/// agent that could swap it halfway through would be left holding a history of
/// changes to a file it is no longer editing, every one of which would apply
/// cleanly. A host that wants two projects starts two processes.
///
/// What it will hold is `ModelSession` — listing, select, run, undo, redo,
/// check, save, export, import, journal — and `ModelMcpServer`, whose tools are
/// generated from the command names in `flutter3d_model_core` rather than
/// written out a second time here.
///
/// Empty today apart from the entry point's usage line: the package is
/// registered before it is filled, so the container check that a `dart run`
/// with no Flutter SDK can start it runs from the first commit. See
/// `doc/model-editor-plan.md` §2.2.
library;
