import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// What every actor running a behaviour tree last decided, drawn where it
/// stands.
///
/// **Read-only, and that is the condition for having it at all.** It reads
/// the boards through `BehaviourBrain.pathOf` and `goalOf`, which never make
/// one, so switching the overlay on cannot change a snapshot — an overlay that
/// did would make a run under the debugger a different run.
///
/// Above each actor, one short upright stroke per node on the path, root
/// lowest, coloured by how the node came out: amber running, green success,
/// red failure. A line from the actor to where its running leaf is taking it.
/// Lines cannot carry words, so the names are [describe]'s, for whatever text
/// the game shows beside the picture.
///
/// Hand [draw] to `Renderer.debugLines`.
final class BehaviourOverlay {
  BehaviourOverlay(this.actors);

  final ActorSystem actors;

  /// How far apart the strokes are, and how tall, in metres.
  static const double _pitch = 0.16;
  static const double _stroke = 0.12;

  /// A new vector each call: a shared one is a colour anybody can scale.
  static Vector4 colourOf(BehaviourStatus status) => switch (status) {
    BehaviourStatus.running => Vector4(1.0, 0.75, 0.1, 1.0),
    BehaviourStatus.success => Vector4(0.3, 0.9, 0.35, 1.0),
    BehaviourStatus.failure => Vector4(0.95, 0.25, 0.2, 1.0),
  };

  void draw(DebugDraw lines) {
    for (final actor in actors.actors) {
      final body = actor.body;
      if (body == null || !actor.isAlive) continue;
      final path = BehaviourBrain.pathOf(actor);
      if (path.isEmpty) continue;
      final at = body.position;
      final top = at.y + body.halfExtents.y + 0.2;
      for (final (i, step) in path.indexed) {
        final y = top + i * _pitch;
        lines.addLine(
          Vector3(at.x, y, at.z),
          Vector3(at.x, y + _stroke, at.z),
          colourOf(step.status),
        );
      }
      final goal = BehaviourBrain.goalOf(actor, actors);
      if (goal != null) lines.addLine(at, goal, colourOf(path.last.status));
    }
  }

  /// One line per actor running a tree: who, and the path by name —
  /// `a1: utility › patrol › goTo (running)`.
  List<String> describe() => <String>[
    for (final actor in actors.actors)
      if (BehaviourBrain.pathOf(actor) case final path when path.isNotEmpty)
        [
          '${actor.name ?? '#${actor.ordinal}'}:',
          path.map((step) => step.label).join(' › '),
          '(${path.last.status.name})',
        ].join(' '),
  ];
}
