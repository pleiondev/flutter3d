/// Gaussian splats — `gfx-80n`: the fitted cloud a capture produces, read out
/// of the PLY it ships in, with the arithmetic that turns its stored parameters
/// into what a renderer needs.
///
/// See `splat_cloud.dart` for what a splat is and why everything is a flat
/// array, and `splat_ply.dart` for the three conventions the file's own header
/// does not mention.
library;

export 'splat_cloud.dart';
export 'splat_ply.dart';
