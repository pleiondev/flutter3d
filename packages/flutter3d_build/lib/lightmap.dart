/// Baking a level's lightmap: [LightmapBaker], what `dart run
/// flutter3d_build:bake_lightmap` runs over each level before it ships.
///
/// **Its own library, with no `dart:io` behind it,** so a page that bakes a
/// small room as it is shown (the showcase's) compiles for the web; the
/// command reads and writes the files. The map it bakes, `Lightmap`, and
/// its layout stay in `flutter3d_sim` beside the level, where the loader
/// reads them.
library;

export 'src/lightmap_bake.dart';
