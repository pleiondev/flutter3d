/// Play by process — see `play_launch.dart`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';

import 'device_picker.dart';

/// Whether this build can start a game, rather than only attach to one.
const bool kStartsGames = true;

/// Why the level at [levelPath] cannot be played, or null when it can.
String? whyCannotPlay(String levelPath) => projectRootOnDisk(levelPath) == null
    ? 'this level is not inside a Flutter project, so there is nothing to run'
    : null;

/// The game that plays [levelPath]'s project: [current] when it already is
/// that project's run, a new one otherwise. Replacing [current] is the
/// caller's business, since it is the caller who holds it.
PlayedGame gameFor(String levelPath, PlayedGame? current) {
  final root = projectRootOnDisk(levelPath)!;
  return switch (current) {
    final FlutterRun same? when same.projectRoot == root => same,
    _ => FlutterRun(projectRoot: root),
  };
}

/// The device picker for [game]'s bar, when it is a run that has a device to
/// pick.
Widget Function({required bool enabled})? devicePickerFor(PlayedGame game) =>
    switch (game) {
      final FlutterRun run => ({required bool enabled}) => DevicePicker(
        run: run,
        enabled: enabled,
      ),
      _ => null,
    };
