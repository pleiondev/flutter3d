/// glTF 2.0 and GLB decoding.
///
/// The layer has no dependency on a graphics backend, `dart:io` or `dart:ui`: external
/// files arrive through an [AssetUriResolver] callback and images are handed back
/// still encoded. That is what makes it unit testable without a GPU or a Flutter
/// binding, and reusable from an isolate.
///
/// Output is a [ModelDocument], the abstraction shared with the OBJ decoder.
library;

export '../asset_resolver.dart';
export '../model_document.dart';
export 'glb_container.dart' show GlbContainer, decodeDataUri;
export 'gltf_accessor.dart';
export 'gltf_asset.dart';
export 'gltf_loader.dart';
