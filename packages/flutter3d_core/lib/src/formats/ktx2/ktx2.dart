/// The KTX2 container: a compressed texture's format and mip levels, read
/// without a GPU and without the Flutter SDK. See `ktx2_format.dart` for
/// the layout, and `ktx2_loader.dart`'s own doc comment for why this reads
/// `vkFormat` rather than an engine's `TextureFormat` — `ap-01` in
/// `doc/asset-pipeline-plan.md`.
library;

export 'ktx2_format.dart';
export 'ktx2_loader.dart';
