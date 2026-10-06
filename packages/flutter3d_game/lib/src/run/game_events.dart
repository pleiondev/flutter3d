import 'dart:developer' as developer;

/// Posts what happened in a game, to whoever watches it from outside.
///
/// The type of [postGameEvent], which a test replaces.
typedef GameEventPoster = void Function(String kind, Map<String, Object?> data);

/// What every kind a game posts is prefixed with on the VM service.
const String gameEventPrefix = 'flutter3d.';

/// Tells a tool listening on the game's VM service — the editor's Play
/// panel, an agent's `play_events` — that something happened: a level is
/// up, the player died, a pickup was taken.
///
/// Posted as `developer.postEvent('flutter3d.<kind>', data)` on the VM
/// service's `Extension` stream, which is where `flutter3d_editor_play`
/// listens, keeping only the kinds with [gameEventPrefix]. [kind] is written
/// without it, dotted from the general to the particular — `level.loaded`,
/// `player.died` — and [data] has to be JSON: strings, numbers, booleans,
/// null, and lists and maps of those.
///
/// **Not a second event system.** A step's `GameEvent`s are for the game
/// itself and are drained sixty times a second; this is for the handful of
/// moments somebody watching the game from outside wants to hear about, and
/// it costs nothing when nobody is listening: `postEvent` with no VM service
/// to send it to, which is every release build, goes nowhere.
///
/// A variable rather than a function, the way `debugPrint` is, so a test puts
/// its own in to see what the game posted and puts this one back after.
GameEventPoster postGameEvent = postGameEventToVmService;

/// [postGameEvent]'s own: the event on the VM service's `Extension` stream.
void postGameEventToVmService(String kind, Map<String, Object?> data) =>
    developer.postEvent('$gameEventPrefix$kind', data);
