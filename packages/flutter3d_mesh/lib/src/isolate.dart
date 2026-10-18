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
///
/// **The isolate half is chosen by platform, not only by a constant**, so a
/// browser build has no `dart:isolate` in it at all: `isolate_run.dart` is
/// what runs elsewhere, `isolate_here.dart` what runs in a browser.
library;

import 'edit_mesh.dart';

export 'isolate_run.dart' if (dart.library.js_interop) 'isolate_here.dart';

/// Work an isolate can be handed: one mesh in, one mesh out.
typedef MeshWork = EditMesh Function(EditMesh mesh);

/// Whether this is a build with no isolates in it.
///
/// A plain-Dart package cannot ask Flutter's `kIsWeb`, and this is the question
/// underneath it: whether the program was compiled to JavaScript or to
/// WebAssembly, where `Isolate.run` is a stub that throws.
const bool meshWorkStaysHere = bool.fromEnvironment('dart.library.js_interop');
