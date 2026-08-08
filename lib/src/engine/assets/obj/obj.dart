/// Wavefront OBJ decoding.
///
/// Same shape as the glTF layer: no dependency on flutter_gpu, `dart:io` or
/// `dart:ui`, sibling files arrive through an [AssetUriResolver], and the output
/// is a [ModelDocument] so both formats upload through one code path.
library;

export '../asset_resolver.dart';
export '../model_document.dart';
export 'obj_document.dart';
export 'obj_loader.dart';
