/// Turns at putting a loaded model into a scene, taken in the order the
/// models were asked for — for the fixtures and the actors of one scene
/// together.
library;

import 'dart:async';

import 'package:flutter3d/flutter3d.dart';

/// The last turn taken in each scene. Beside the scene rather than on it:
/// the order is this package's business, not the scene's.
final Expando<Future<void>> _turns = Expando<Future<void>>('scene turns');

/// Takes the next turn at putting something loaded into [scene].
///
/// **A model goes into a scene in the order it was asked for, not the order
/// its file arrives in.** Each file is decoded on an isolate of its own, so
/// two finish in either order — and the scene's order is part of the
/// picture: the renderer's cull tree is built over the meshes in the order
/// they were registered, and the order draws are claimed in decides which
/// material sorts first and which of two equal depths wins. The Ascent's
/// replay drew one of two frames at step 120 for exactly this, its coin and
/// its key racing.
///
/// One line of turns per scene rather than one per visuals object, because
/// a level's fixtures and its actors go into the same scene, and a
/// monster's model racing a door's is the same race.
///
/// Taken when the load is started, synchronously, so the turns follow the
/// calls. The caller loads, awaits `previous`, puts its model in and then
/// completes `turn` — in a `finally`, so a load that fails still hands the
/// next one its turn. The loads still run side by side; only the step into
/// the scene waits.
({Future<void> previous, Completer<void> turn}) takeSceneTurn(Scene scene) {
  final previous = _turns[scene] ?? Future<void>.value();
  final turn = Completer<void>();
  _turns[scene] = turn.future;
  return (previous: previous, turn: turn);
}
