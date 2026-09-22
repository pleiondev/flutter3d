/// USDZ, write-only — `fmt-27`. A spike: geometry alone, no decoder, since
/// nothing in this repository or its plan needs to read one back.
///
/// Same shape as the other codecs in this package where it applies:
/// [UsdzWriter] takes a [ModelDocument], the same way [ObjWriter],
/// [GltfWriter] and [StlWriter] do.
library;

export '../model_document.dart';
export 'usdz_writer.dart';
export 'usdz_zip.dart';
