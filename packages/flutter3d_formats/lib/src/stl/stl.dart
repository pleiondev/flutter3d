/// STL, binary and ASCII, decoded and now encoded — `fmt-20`.
///
/// Same shape as the other codecs in this package: no dependency on a
/// graphics backend, `dart:io` or `dart:ui`; the loader answers a
/// [ModelDocument] so it uploads through the same code path as glTF and OBJ,
/// and [StlWriter] takes one, the same way [ObjWriter] and [GltfWriter] do.
library;

export '../model_document.dart';
export 'stl_loader.dart';
export 'stl_writer.dart';
