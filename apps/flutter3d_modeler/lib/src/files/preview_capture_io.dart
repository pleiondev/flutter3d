/// Preview capture, where there is no browser canvas to capture from.
///
/// **Never reached with a real capture to make.** `CabinetLink.
/// shouldCapturePreview` is only ever true for a build `cloud/server`'s own
/// iframe opened, and that iframe is always a browser — see
/// `preview_capture.dart`'s own doc comment. This half exists for the same
/// reason `cabinet_save_io.dart` beside it does: one function per platform,
/// so a desktop build compiles at all.
library;

/// Does nothing — there is no canvas here to capture from, and no real
/// caller ever asks this half to.
Future<void> capturePreview({
  required int modelId,
  required String sourceSha,
  required String csrf,
}) async {}
