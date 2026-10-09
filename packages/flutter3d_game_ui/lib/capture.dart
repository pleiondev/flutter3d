/// Recording and sharing what was played: a game filmed frame by frame for
/// a reel or a clip ([Reel], [ReelShot]), and the strip a finished run is
/// shared from and somebody else's is opened from ([ShareStrip]).
///
/// A library rather than a plugin. A reel steps the game itself, from its
/// own entry point, and sharing is a button on the game's own screen; there
/// is nothing for either to register in a loop.
library;

export 'src/capture/reel.dart';
export 'src/capture/share_strip.dart';
