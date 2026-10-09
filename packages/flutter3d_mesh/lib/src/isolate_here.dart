/// `editInIsolate` in a browser, where there are none — see `isolate.dart`.
library;

import 'edit_mesh.dart';
import 'isolate.dart' show MeshWork;

/// Runs [work] on [mesh] on this thread: a browser build has no isolate to
/// hand it to. See `isolate.dart` for what the web should do about that.
Future<EditMesh> editInIsolate(EditMesh mesh, MeshWork work) async =>
    work(mesh);
