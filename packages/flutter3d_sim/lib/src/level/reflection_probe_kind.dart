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
///  * `near`, `far` — where each face's view begins and ends.
final class ReflectionProbeKind extends EntityKind {
  const ReflectionProbeKind() : super(EntityTypes.reflectionProbe);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    void refuse(String message) => out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        message,
        where: scope.describe(entity),
      ),
    );

    final radius = entity.number('radius');
    if (radius != null && radius < 0.0) {
      refuse(
        'has a radius of $radius; zero reaches everything, and nothing is '
        'nearer than that',
      );
    }
    final intensity = entity.number('intensity');
    if (intensity != null && intensity < 0.0) {
      refuse('has an intensity of $intensity, which would take light away');
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
    final near = entity.number('near');
    final far = entity.number('far');
    if (near != null && near <= 0.0) {
      refuse('has a near plane of $near, which has to be in front of it');
    }
    if (far != null && far <= (near ?? 0.0)) {
      refuse('has a far plane of $far, which is not beyond its near plane');
    }
  }
}
