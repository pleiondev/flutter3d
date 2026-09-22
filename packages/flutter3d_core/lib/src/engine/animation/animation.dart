/// Animation: clips, tracks and a player that writes onto scene nodes.
///
/// Nothing here depends on a graphics backend or on `dart:ui`, so sampling and
/// playback are testable without a device.
library;

// `Ktx2Texture` hidden: `flutter3d.dart` re-exports this package's own thin
// wrapper of the same name from `ktx2/ktx2.dart` instead — see its doc
// comment (`ap-01`).
export 'package:flutter3d_core/formats.dart' hide Ktx2Texture;
export 'animation_layer.dart';
export 'animation_player.dart';
export 'animation_target.dart';
export 'morph_sink.dart';
