/// Heads-up display pieces for a game on flutter3d: the panel and its lines,
/// tallies and banners, a speedometer, a minimap of a course, the automap of
/// what a player has walked, hints said at the moment they are true, a beacon that makes an objective findable in the dark,
/// and the same HUD on a stereo surface.
///
/// **Widgets over the picture, not geometry in it.** The engine hands back a
/// texture and Flutter composites over it, so a HUD costs no draw calls and
/// gets text layout, scaling and accessibility for nothing. Every piece here
/// takes values and draws them; none steps a simulation.
///
/// [MiniMap] and [AutomapView] are two maps for two jobs: the first fits a
/// course's outline into a corner with a dot for everything on it, the
/// second draws the cells an `Automap` has revealed, centred on the player
/// and turned the way they face.
///
/// **No plugin.** Nothing here is installed into a loop: a HUD is a widget a
/// game puts in its tree, and the beacon is one call when a level is built.
library;

export 'src/hud/automap_view.dart';
export 'src/hud/hud_pieces.dart';
export 'src/hud/mini_map.dart';
export 'src/hud/moment_hints.dart';
export 'src/hud/objective_beacon.dart';
export 'src/hud/stereo_hud_panel.dart';
