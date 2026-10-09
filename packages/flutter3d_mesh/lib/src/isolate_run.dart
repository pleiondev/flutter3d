/// `editInIsolate` where there are isolates — see `isolate.dart`.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'edit_mesh.dart';
import 'isolate.dart' show MeshWork, meshWorkStaysHere;

/// Runs [work] on [mesh] in another isolate and brings the result back.
///
/// [work] must be a top-level or static function — a closure would carry
/// whatever it captured across, which is the copy the byte format is here to
/// avoid, and a closure over anything the sending isolate keeps alive would not
/// cross at all.
///
/// On a build without isolates the work happens on this thread instead, so a
/// caller gets the answer everywhere and a frozen frame in one of the two
/// places. See the library note for what the web should do about that.
Future<EditMesh> editInIsolate(EditMesh mesh, MeshWork work) async {
  if (meshWorkStaysHere) return work(mesh);
  final sent = TransferableTypedData.fromList(<Uint8List>[mesh.toBytes()]);
  final back = await Isolate.run(() => _apply(sent, work));
  return EditMesh.fromBytes(back.materialize().asUint8List());
}

/// The other side: rebuild, work, write back.
///
/// Top-level, so the closure `Isolate.run` carries holds two sendable values
/// and nothing else.
TransferableTypedData _apply(TransferableTypedData sent, MeshWork work) {
  final mesh = EditMesh.fromBytes(sent.materialize().asUint8List());
  return TransferableTypedData.fromList(<Uint8List>[work(mesh).toBytes()]);
}
