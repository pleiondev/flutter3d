/// A fourth genre, and the first one that is not about a protagonist.
///
/// **What makes this genre worth having is not the genre.** A shooter, a
/// platformer and a racer all move one body under a camera bolted to it, and
/// three of them agreeing about what an engine owes a game says less than it
/// looks: they agree because they are the same shape. A strategy is the other
/// shape — a camera over a map, orders given to a selection, and a crowd rather
/// than a hero — and it exercises three things the engine had built and no game
/// had ever used: `InstancedMeshNode`, the picking pass, and the flow fields in
/// `flutter3d_sim`'s navigation.
///
/// ## What the measurement decided before the code was written
///
/// Two probes ran first, and both moved the design. The crowd is cheap: ten
/// thousand agents descending a field, shoving each other apart and writing
/// their transforms cost under a millisecond a step. The drawing is cheaper
/// still: fifty thousand instanced units held the display's refresh rate, and
/// what gave way first at four hundred thousand was the processor encoding the
/// frame — about 0.07 microseconds an instance — rather than the device drawing
/// it.
///
/// So neither the number of units nor the number of draws is the constraint
/// this package designs against, and two things follow. Separation applies to
/// **everybody**, because limiting it to what a camera can see saves 717
/// microseconds and costs a run that replays the same way twice. And the
/// navigation grid is **coarse** — two metres, against the quarter-metre a
/// shooter bakes for its corridors — because a field on a fine lattice costs
/// half a frame to build and a field on a coarse one costs half a
/// millisecond, while the units walking it cannot tell the difference.
///
/// ## What is here and what is not
///
/// Units, orders and the step that moves them. No economy, no production, no
/// fight and no fog: those are the phases after this one, and a package that
/// grew them before it could carry a crowd across a hill would have been
/// guessing about the part that was actually uncertain.
library;

export 'src/building.dart';
export 'src/economy.dart';
export 'src/formation.dart';
export 'src/map_camera.dart';
export 'src/selection.dart';
export 'src/simulation.dart';
export 'src/unit.dart';
