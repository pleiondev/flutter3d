import 'entity_def.dart';
import 'entity_kind.dart';
import 'level_issue.dart';

/// What the three kinds below share: pure data to the simulation, built
/// into scene nodes by the renderer's side of the bridge — `LevelScene` in
/// `flutter3d_editor_core`, which the game's loader and the editor's
/// viewport both build from — and each naming a material of the level the
/// way a brush does, so a document says what it shows with the words it
/// already has.
///
/// **Kinds, not words the loader knows on its own**, for the reason
/// `ReflectionProbeKind` gives: a game whose vocabulary has none reads a
/// document with one as an unknown type, which is right — a mirror is a
/// thing a game asks for.
abstract base class _SurfaceKind extends EntityKind {
  const _SurfaceKind(super.type);

  void _material(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final material = entity.string('material');
    if (material == null) {
      out.add(_error(entity, scope, 'names no material to show'));
    } else if (!scope.level.materials.containsKey(material)) {
      out.add(
        _error(
          entity,
          scope,
          'names the material "$material", which the '
          'level does not have',
        ),
      );
    }
  }

  void _positive(
    EntityDef entity,
    LevelScope scope,
    List<LevelIssue> out,
    String key,
  ) {
    final value = entity.number(key);
    if (value != null && !(value > 0.0)) {
      out.add(_error(entity, scope, 'has a $key that is not more than nought'));
    }
  }

  void _fraction(
    EntityDef entity,
    LevelScope scope,
    List<LevelIssue> out,
    String key,
  ) {
    final value = entity.number(key);
    if (value != null && !(value >= 0.0 && value <= 1.0)) {
      out.add(_error(entity, scope, 'has a $key outside nought to one'));
    }
  }

  static LevelIssue _error(EntityDef e, LevelScope scope, String message) =>
      LevelIssue(LevelIssueSeverity.error, message, where: scope.describe(e));
}

/// A picture projected onto whatever stands in a box: a scorch, a stain, a
/// painted sign.
///
///  * `material` — the level material whose picture and colour it paints.
///  * `size` — the box: width, depth into the surface, length; a metre each
///    by default. The entity's `at` is its middle.
///  * `pitch` — degrees the box is tipped from lying flat; ninety stands it
///    on a wall, facing the way the entity's `yaw` says.
///  * `order` — which of two overlapping decals is on top.
///
/// Drawn where the game turns decals on (`RenderSettings.decals`).
final class DecalKind extends _SurfaceKind {
  const DecalKind() : super(EntityTypes.decal);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _material(entity, scope, out);
    final size = entity.vector('size');
    if (size != null && !(size.x > 0.0 && size.y > 0.0 && size.z > 0.0)) {
      out.add(
        _SurfaceKind._error(entity, scope, 'has a size with a side of nought'),
      );
    }
  }
}

/// A plane that mirrors the room above it: still water, a polished floor.
///
///  * `material` — the level material whose surfaces mirror; every brush
///    face of it, so a pool is one material and not a list of faces.
///  * The entity's `at` is a point on the plane, which faces up.
///  * `reflectance` — how much a surface seen straight on reflects, nought
///    to one; one.
///  * `strength` — a multiplier on the reflection; one.
///  * `resolution` — a fraction of the view the reflection is drawn at;
///    half.
final class ReflectorKind extends _SurfaceKind {
  const ReflectorKind() : super(EntityTypes.reflector);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _material(entity, scope, out);
    _fraction(entity, scope, out, 'reflectance');
    _fraction(entity, scope, out, 'resolution');
    final strength = entity.number('strength');
    if (strength != null && strength < 0.0) {
      out.add(
        _SurfaceKind._error(
          entity,
          scope,
          'has a negative strength, which would take light away',
        ),
      );
    }
  }
}

/// A camera whose picture shows on a material: a monitor, a scrying pool.
///
///  * The entity's `at` is the camera; `look` the point it looks at.
///  * `material` — the level material whose surfaces show the picture, as
///    light they give off.
///  * `width`, `height` — the picture in pixels; 256 by 144.
///  * `fov` — vertical degrees; sixty.
///  * `once` — true to take the picture once rather than every frame.
final class CameraScreenKind extends _SurfaceKind {
  const CameraScreenKind() : super(EntityTypes.cameraScreen);

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    _material(entity, scope, out);
    if (entity.vector('look') == null) {
      out.add(
        _SurfaceKind._error(entity, scope, 'has no `look`: where it points'),
      );
    }
    for (final key in <String>['width', 'height']) {
      final value = entity.integer(key);
      if (value != null && (value < 1 || value > 2048)) {
        out.add(
          _SurfaceKind._error(entity, scope, 'has a $key outside 1 to 2048'),
        );
      }
    }
    _positive(entity, scope, out, 'fov');
  }
}
