/// Doing work to a mesh somewhere other than the thread drawing it.
///
/// **What has to be true for a mesh to cross, and it is not "be sendable".** An
/// isolate can be handed almost any object, and handing it an `EditMesh` would
/// deep-copy nine typed arrays and every layer on the way there and again on
/// the way back. So a mesh crosses as the bytes [EditMesh.toBytes] writes,
/// inside a `TransferableTypedData` — which moves the buffer rather than
/// copying it, and is the reason the byte format exists at all.
///
/// **The work is a named function, not a closure.** `Isolate.run` carries what
/// its closure captures, and a closure over the mesh itself is the copy this
/// exists to avoid. A top-level or static function taking a mesh and giving one
/// back is what crosses; anything it needs beyond that goes with it as plain
/// values.
///
/// **On the web there are no isolates, and this says so by doing the work
/// here.** `dart:isolate` compiles for the web — it is a stub — so the failure
/// would otherwise arrive at run time, several seconds into an operation, as
/// an unsupported `ReceivePort`. The engine's model loader made the same call
/// for the same reason. What the web should do instead is chunk the work and
/// yield between the chunks, or run it in a worker; that is `ui-34d`, and it
/// belongs to whoever owns the frame rather than to the mesh.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'edit_mesh.dart';

/// Work an isolate can be handed: one mesh in, one mesh out.
typedef MeshWork = EditMesh Function(EditMesh mesh);

/// Whether this is a build with no isolates in it.
///
/// A plain-Dart package cannot ask Flutter's `kIsWeb`, and this is the question
/// underneath it: whether the program was compiled to JavaScript or to
/// WebAssembly, where `Isolate.run` is a stub that throws.
const bool meshWorkStaysHere = bool.fromEnvironment('dart.library.js_interop');

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
