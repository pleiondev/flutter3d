/// Gaussian splats — `gfx-80n`: the fitted cloud a capture produces, read out
/// of the PLY it ships in or the SPZ it is compressed to, with the arithmetic
/// that turns its stored parameters into what a renderer needs, and the tree
/// of levels of detail a large one is paged from.
///
/// See `splat_cloud.dart` for what a splat is and why everything is a flat
/// array, `splat_ply.dart` for the three conventions the file's own header
/// does not mention, and `splat_octree.dart` for the tree.
library;

export 'splat_cloud.dart';
export 'splat_octree.dart';
export 'splat_paged.dart';
export 'splat_ply.dart';
export 'splat_spz.dart';
