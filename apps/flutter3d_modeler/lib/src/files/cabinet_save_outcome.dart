/// The outcome of POSTing a document back to its cabinet entry, and the
/// shape of whatever sends it — `tut-20`'s own "Save to cabinet".
///
/// One type shared by `cabinet_save_io.dart` and `cabinet_save_web.dart`, and
/// by the fake `screen/files_test.dart` (or its like) hands to
/// `ModelerScreen.cabinetSourceSender` in a test — the same "one shape, real
/// implementation on one side and a fake standing in for it on the other"
/// `picked_file.dart`'s own [SaveResult] already is for `saveAs`.
library;

import 'dart:typed_data';

/// What `cloud/server`'s own `POST /api/v1/models/<id>/source` answered.
sealed class CabinetSaveOutcome {
  const CabinetSaveOutcome();
}

/// The server accepted the bytes as the model's new current source.
final class CabinetSaveWritten extends CabinetSaveOutcome {
  const CabinetSaveWritten();
}

/// The server refused, or the request never reached it. [said] is shown on
/// the status line as it is — the server's own `{'error': ...}` message when
/// there was one, or a sentence built from whatever went wrong before a
/// response came back at all.
final class CabinetSaveFailed extends CabinetSaveOutcome {
  const CabinetSaveFailed(this.said);

  final String said;
}

/// Sends [bytes] to the cabinet entry [modelId], carrying [csrf] the way
/// `cloud/server`'s own `scriptIsOurs` needs it — `X-CSRF`, matched against
/// the request's own CSRF cookie. `postSourceToCabinet` in `cabinet_save.dart`
/// is the real implementation; `ModelerScreen.cabinetSourceSender` is where a
/// test hands in a fake instead.
typedef CabinetSourceSender =
    Future<CabinetSaveOutcome> Function({
      required int modelId,
      required String csrf,
      required Uint8List bytes,
    });
