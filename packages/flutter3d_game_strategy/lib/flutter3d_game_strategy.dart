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
/// Units of several kinds, orders and the step that moves them; ground taken
/// from the map and turned into more units; two sides, and a policy that plays
/// one of them without a mouse; a map each side has to go and look at before it
/// knows what is on it; and a fight over all of it.
///
/// **The fight came last, and that ordering is the method rather than a
/// backlog.** A package that grew one before it could carry a crowd across a
/// hill would have been guessing about the part that was actually uncertain —
/// and when it did arrive it cost no new mechanism: a kind is [UnitType], a row
/// of numbers so that a worker, a soldier and a tank differ in what they
/// measure rather than in what runs; a target is a field on the order beside
/// the goal, so the walk that already descends a field follows a retreating
/// enemy without knowing what a target is; and the shooting reuses the same
/// spatial hash the shove was already building, because the measurement this
/// package was designed against leaves no room for a pass of everybody against
/// everybody.
///
/// So there are two ways to win and neither replaces the other: bring home what
/// the match was set at, or be the only side with anything left to act with.
/// See [Match].
///
/// **And a match can be written down.** [Match.save] and
/// [StrategySimulation.save] answer the same [Snapshot] the other three genres
/// answer, which is what makes an order tape, a replay and a session possible
/// here rather than a fourth thing to invent. The crowd lives in an [EcsWorld]
/// for one reason and it is this one: production makes units while the match
/// runs, so a save describes more of them than the map it is restored into has,
/// and an entity is a handle where a list index is only a guess.
///
/// **And played back.** Every order a side gives — a policy's and a mouse's
/// alike — goes into [OrderQueue] and is carried out at the top of the step
/// that follows it, so a match is a starting [Snapshot] plus an entry per step.
/// [MatchDemo] is those two things as one file. The genre carries its own tape
/// rather than the engine's [InputTape] because a click on a hillside is not a
/// key press and a set of units is not a numbered slot; the shape is the same,
/// the fields are this game's, and the three genres that already play input
/// tapes were left alone.
///
/// **The fog is a rule, not a coat of paint.** [FogOfWar] is asked by the
/// policy that decides where to send workers, so a side that has not found a
/// seam cannot dig it and has to send somebody to look; it is also what the
/// drawing half draws, so a view belonging to a side shows that side's
/// knowledge rather than the simulation. The two uses are the same lattice, and
/// keeping them the same is the point: a fog the picture believed and the rules
/// did not would be a fog that lied to exactly one of them.
library;

export 'src/bot.dart';
export 'src/building.dart';
export 'src/economy.dart';
export 'src/fog.dart';
export 'src/formation.dart';
export 'src/map_camera.dart';
export 'src/match.dart';
export 'src/order_tape.dart';
export 'src/orders.dart';
export 'src/selection.dart';
export 'src/simulation.dart';
export 'src/unit.dart';
