/// Wavefront OBJ, both ways.
///
/// Same shape as the glTF layer: no dependency on a graphics backend, `dart:io` or
/// `dart:ui`, sibling files arrive through an [AssetUriResolver], and the output
/// is a [ModelDocument] so both formats upload through one code path.
///
/// [ObjWriter] joined this barrel on 2026-09-10 having been written, tested and
/// unreachable from outside the package for a while — which is a writer nobody
/// can use however good it is. Its dialect is deliberately the one [ObjLoader]
/// reads, so the pair round-trips.
library;

export '../asset_resolver.dart';
export '../model_document.dart';
export 'obj_document.dart';
export 'obj_loader.dart';
export 'obj_writer.dart';
