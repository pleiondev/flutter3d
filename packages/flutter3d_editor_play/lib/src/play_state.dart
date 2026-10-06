/// Where a game the editor plays is, and what the editor can do to it,
/// whether the editor started it or found it already running.
library;

import 'game_events.dart';
import 'watched.dart';

/// Where a run is: not yet started, starting, running with a VM service to
/// attach to, or over.
sealed class PlayState {
  const PlayState();
}

final class PlayIdle extends PlayState {
  const PlayIdle();
}

final class PlayStarting extends PlayState {
  const PlayStarting(this.message);

  /// What the tool says it is doing: "Launching lib/main.dart…".
  final String message;
}

final class PlayRunning extends PlayState {
  const PlayRunning({required this.appId, required this.vmService});

  final String appId;

  /// The game's VM service, for the timeline panel and `ext.flutter3d.*`.
  final String vmService;
}

final class PlayStopped extends PlayState {
  const PlayStopped(this.exitCode, {this.reason});

  final int exitCode;

  /// What ended it, when an exit code says nothing: an attached game has
  /// none to give, since the editor let go of it or it closed the socket.
  final String? reason;
}

/// A game the editor plays: one it started with `flutter run --machine`
/// (`FlutterRun`) or one it attached to by its VM service (`AttachedRun`).
///
/// **One panel for both.** The browser has no process to start, so there the
/// game is always one somebody else ran; what a person does to it is the
/// same — read its console, swap in new code, open its timeline, send it the
/// saved level — and a second panel would be a second place for that to
/// drift.
abstract interface class PlayedGame {
  /// What the panel's title says: the project, or the address attached to.
  String get title;

  /// Whether [stop] ends the game, or only lets go of it.
  bool get ownsTheGame;

  Watched<PlayState> get state;

  /// Every line the game has printed, oldest first, capped.
  Watched<List<String>> get console;

  /// Every event the game posted with `postGameEvent` while it was watched,
  /// oldest first, capped like [console]; [eventsSince] reads it by cursor.
  ///
  /// **Beside the console, not in it.** A line is for a person to read and
  /// is gone in two thousand more; an event is a kind and a map an agent
  /// can wait for — "the level is up", "the player died" — and numbered, so
  /// one asked for twice is not seen twice and one never asked for is not
  /// lost to a burst of printing.
  Watched<List<PostedEvent>> get events;

  /// Runs the game, or attaches to it again. Does nothing while it goes.
  Future<void> start();

  /// A hot reload: what was said about it, or null when nothing is running.
  Future<String?> hotSwap();

  /// A hot restart: what was said about it, or null when nothing is running.
  Future<String?> hotRestart();

  /// Ends the game when [ownsTheGame], and lets go of it otherwise.
  Future<void> stop();

  Future<void> dispose();
}

/// The lines of the console a session keeps, with [line] added and the
/// oldest dropped past [limit].
List<String> appendLine(List<String> lines, String line, int limit) =>
    appendCapped(lines, line, limit);

/// [items] with [item] added and the oldest dropped past [limit].
List<T> appendCapped<T>(List<T> items, T item, int limit) => <T>[
  ...items.length >= limit ? items.skip(items.length - limit + 1) : items,
  item,
];
