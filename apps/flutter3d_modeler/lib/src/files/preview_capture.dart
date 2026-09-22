/// Capturing the framed subject as a picture and sending it to the cabinet
/// entry it was opened from — `tut-19`'s own preview capture.
///
/// The same conditional-export split `cabinet_save.dart` beside this file
/// already makes, and for the same reason: only a browser build has a canvas
/// to capture at all, so the desktop half in `preview_capture_io.dart` is a
/// quiet no-op rather than something that could ever be reached with a real
/// `CabinetLink.shouldCapturePreview` to act on — see that getter's own doc
/// comment in `cabinet_link.dart` for the four things that have to be true
/// first, every one of them only a cabinet's own iframe can send.
library;

export 'preview_capture_io.dart'
    if (dart.library.js_interop) 'preview_capture_web.dart';

/// Captures the viewport's current frame and POSTs it to
/// `/api/v1/models/<modelId>/preview`, carrying `csrf` and `sourceSha` the
/// way the endpoint needs them — see `cloud/server`'s own handler for what it
/// checks each against.
///
/// **Never throws, and never worth awaiting for what it returns.** A capture
/// that fails — the browser could not produce a blob, the network dropped,
/// the server refused — is logged through `debugPrint` and nothing else;
/// `main.dart`'s own call site does not need to await this for anything
/// beyond scheduling it, unlike `screen/files.dart`'s own `_saveToCabinet`,
/// because a preview is a background convenience and a save is a person's
/// own action waiting on a result.
///
/// `capturePreview` in `preview_capture_web.dart`/`preview_capture_io.dart`
/// is the real implementation this function type describes;
/// `ModelerScreen.previewCapturer` is where a test hands in a fake instead —
/// the same "one shape, real implementation on one side and a fake standing
/// in for it on the other" `CabinetSourceSender` beside it already is.
typedef PreviewCapturer =
    Future<void> Function({
      required int modelId,
      required String sourceSha,
      required String csrf,
    });
