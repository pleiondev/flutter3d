import 'entity_def.dart';
import 'entity_kind.dart';
import 'level_issue.dart';

/// A point the room around it is reflected from.
///
/// Pure data to the simulation: nothing spawns, nothing collides and nothing
/// is revealed as a fixture. What the entity says is *where*, and how far the
/// reflection reaches — the renderer's side of the bridge builds a probe from
/// it, the way it builds a light node from a level light. It is a kind rather
/// than a word the loader knows on its own so that a game with no probes in
/// its vocabulary reads a document with one as an unknown type, which is
/// right: a reflection is a thing a game has to ask for.
///
/// One per room is the shape a level wants — at the middle of the room, at
/// half its height — and the generators put one there. Everything else is
/// optional and has the probe's own default when the document says nothing:
///
///  * `radius` — how far a mesh may be and still reflect it; zero, the
///    default, reaches everything and the nearest probe wins.
///  * `intensity` — how strongly the captured room lights what reads it; one.
///  * `faceSize` — each face's edge in pixels; sixty-four.
///  * `levels` — roughness levels below the mirror; four.
///  * `near`, `far` — where each face's view begins and ends; five centimetres
///    and two hundred metres.
final class ReflectionProbeKind extends EntityKind {
  const ReflectionProbeKind() : super(EntityTypes.reflectionProbe);

  /// The near and far planes a document that names neither ends up with.
  ///
  /// Restated here rather than reached for, and it has to be: the numbers
  /// belong to `ReflectionProbeNode`'s constructor, in the renderer, which
  /// this package must not know exists — the bridge's `_toProbeNode` restates
  /// them for the same reason. What they buy here is the pair *after* the
  /// defaults are filled in, which is the pair the node asserts on: a document
  /// that names only a near plane still has a far one, and comparing its near
  /// against zero says nothing about whether the two make a view.
  static const double _defaultNear = 0.05;
  static const double _defaultFar = 200.0;

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    void refuse(String message) => out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        message,
        where: scope.describe(entity),
      ),
    );

    // **Written out rather than interpolated.** `'${300.0}'` is "300.0" on the
    // Dart VM and "300" in a browser, because the two disagree about how an
    // integral double prints — and this package is the half of the engine that
    // has to say the same thing on a server as in a tab. A validator whose
    // message differs by platform is a report that cannot be compared with the
    // one a player's browser produced.
    String number(double it) =>
        it == it.roundToDouble() && it.abs() < 1e15 ? '${it.toInt()}.0' : '$it';

    final radius = entity.number('radius');
    if (radius != null && radius < 0.0) {
      refuse(
        'has a radius of ${number(radius)}; zero reaches everything, and '
        'nothing is nearer than that',
      );
    }
    final intensity = entity.number('intensity');
    if (intensity != null && intensity < 0.0) {
      refuse(
        'has an intensity of ${number(intensity)}, which would take light away',
      );
    }
    final faceSize = entity.integer('faceSize');
    if (faceSize != null && faceSize < 4) {
      refuse(
        'has faces $faceSize pixels across, which leaves no room for a '
        'chain below them',
      );
    }
    final levels = entity.integer('levels');
    if (levels != null && levels < 1) {
      refuse('has $levels levels; a probe with none reflects one roughness');
    }
    // Both planes resolved before either is judged. `{"near": 300}` names one
    // number, is a perfectly ordinary-looking document, and used to validate
    // clean — the far plane it did not name is two hundred, and the node
    // asserted `0 < near < far` at load with the scene half built, which is
    // the failure this kind exists to take instead.
    final near = entity.number('near');
    final far = entity.number('far');
    final resolvedNear = near ?? _defaultNear;
    final resolvedFar = far ?? _defaultFar;
    String said(double? given, double resolved) =>
        given == null ? '${number(resolved)} by default' : number(given);
    if (resolvedNear <= 0.0) {
      refuse(
        'has a near plane of ${said(near, resolvedNear)}, which has to be in '
        'front of it',
      );
    } else if (resolvedFar <= resolvedNear) {
      refuse(
        'has a near plane of ${said(near, resolvedNear)} and a far plane of '
        '${said(far, resolvedFar)}; a face is drawn between the two, so the '
        'far one has to be beyond the near',
      );
    }
  }
}
