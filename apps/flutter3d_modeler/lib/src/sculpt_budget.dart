/// `pro-sc-09`: what a browser may be asked to sculpt, and a tree built in
/// pieces so the page keeps drawing while it goes up.
///
/// **The web is one thread and no way to ask for a second.** The same Dart
/// runs there through wasm, so nothing about the arithmetic changes; what
/// changes is that every millisecond spent building a BVH is a millisecond
/// the page is not painting in, and a build that takes a second takes the
/// whole second at once. A desktop hides that behind an isolate. A browser
/// has nowhere to hide it.
///
/// So two things live here. The ceiling — `ProjectProfile
/// .sculptTriangleLimitWeb`, a measured number rather than a guess — and
/// [YieldingBuild], which spends a stated budget per frame and hands the
/// frame back, whatever it has managed.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;

/// How long one frame's share of a background build may take.
///
/// **Six milliseconds of a sixteen-millisecond frame.** The rest is what
/// the page needs to lay out, paint and composite; a build that took ten
/// would hold the frame even while "yielding", which is the failure this
/// class exists to make impossible rather than unlikely.
const Duration kBuildSliceOnWeb = Duration(milliseconds: 6);

/// The same, off the web: a desktop frame has the room, and a build split
/// into more pieces than it needs is a build that finishes later.
const Duration kBuildSliceOnDesktop = Duration(milliseconds: 12);

/// Whether [triangles] is more than [profile] allows to be sculpted here.
///
/// **Only ever true in a browser.** A desktop's own ceiling is what the
/// machine can hold; `sculptTriangleLimitWeb` is about a frame's budget in
/// a single-threaded runtime, and applying it to a desktop build would
/// refuse a mesh that machine sculpts comfortably.
bool overSculptLimit(
  ProjectProfile profile,
  int triangles, {
  bool onWeb = kIsWeb,
}) => onWeb && triangles > profile.sculptTriangleLimitWeb;

/// What to tell somebody whose mesh is over the ceiling — a sentence with
/// both numbers in it, because "too big" is not something a person can act
/// on and "310 000 of 300 000" is.
String sculptLimitRefusal(ProjectProfile profile, int triangles) =>
    'this mesh is $triangles triangles and a browser sculpts up to '
    '${profile.sculptTriangleLimitWeb}; decimate it, or open it on the '
    'desktop build';

/// A piece of work done a slice at a time, giving the frame back between
/// slices.
///
/// **A generator of steps rather than a `Future`.** An `await` hands the
/// frame back at a point the scheduler picks; this hands it back at a point
/// the work picks, after a whole step, so a step is never left half done
/// and nothing has to be re-entrant. The caller runs [advance] once per
/// frame and stops when it answers true.
final class YieldingBuild {
  YieldingBuild({
    required this.steps,
    required this.step,
    Duration? slice,
    bool onWeb = kIsWeb,
  }) : slice = slice ?? (onWeb ? kBuildSliceOnWeb : kBuildSliceOnDesktop);

  /// How many steps the whole job is.
  final int steps;

  /// One step, by index. Called at most once per index, in order.
  final void Function(int step) step;

  /// How much of a frame one call to [advance] may spend.
  final Duration slice;

  int _done = 0;

  /// How many steps have run.
  int get done => _done;

  /// Whether every step has run.
  bool get finished => _done >= steps;

  /// How far along, from nought to one — what a progress bar draws.
  double get fraction => steps == 0 ? 1 : _done / steps;

  /// Runs steps until [slice] is spent or the work is done, and answers
  /// whether it is done.
  ///
  /// **The clock is checked after a step, never before one.** A step that
  /// overruns the slice on its own still runs to completion — leaving it
  /// half done would mean every step had to be resumable, which is a cost
  /// paid by every step to protect against the one that is too big. The
  /// answer to a step that is too big is a smaller step.
  bool advance() {
    if (finished) return true;
    final watch = Stopwatch()..start();
    do {
      step(_done);
      _done++;
    } while (!finished && watch.elapsed < slice);
    return finished;
  }
}

/// A [SculptMeshBvh] built over several frames.
///
/// The tree itself is built in one call — `TriangleBvh.fromArrays` is not
/// resumable and making it so is `pro-sc-02`'s package, not this one — so
/// what this splits is the part that is genuinely per chunk: reading a
/// million vertices out of the chunked, copy-on-write store into the flat
/// array the tree sorts over. On a mesh at the web's own ceiling that read
/// is the larger half, and it is the half that can stop between chunks
/// without leaving anything inconsistent.
YieldingBuild readChunksForBvh(
  SculptMesh mesh,
  List<double> into, {
  bool onWeb = kIsWeb,
}) => YieldingBuild(
  steps: mesh.chunkCount,
  onWeb: onWeb,
  step: (int chunk) {
    final positions = mesh.chunkPositions(chunk);
    final int at = chunk * SculptMesh.chunkSize * 3;
    for (var i = 0; i < positions.length && at + i < into.length; i++) {
      into[at + i] = positions[i];
    }
  },
);
