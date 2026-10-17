/// Reactions for flutter3d games: what an event looks and feels like —
/// particle bursts, smoke that lingers, the camera kicked, shaken or widened,
/// a pulse in the hand, a flash on the screen, and the sound that goes with
/// them.
///
/// A [Reaction] is a decision, not an effect: a game decides it from a step
/// or from its events, a test asserts it with no device, and the frame
/// performs it ([Reaction.showIn], [Reaction.feel]). A [ReactionTable] keeps
/// the decisions keyed by event type, and [ReactionsPlugin] hears the
/// engine's bus on its frame channel through one.
library;

export 'src/reactions/reaction.dart';
export 'src/reactions/reaction_table.dart';
export 'src/reactions/reactions_plugin.dart';
export 'src/reactions/screen_flash.dart';
