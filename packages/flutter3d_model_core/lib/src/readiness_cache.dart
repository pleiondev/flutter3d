/// [ExportReadiness], asked every frame without being computed every frame.
///
/// **The check is not cheap and the status bar asks for it constantly.**
/// `ExportReadiness.check` walks every object, builds `MeshChecks` over each
/// half-edge mesh and asks it about manifoldness, degenerate faces and inverted
/// shells; the budget on top of that walks every face of every mesh to count
/// triangles, because `EditedGeometry.triangleCount` is a pass over the face
/// slots and not a stored number. On a project of one cube that is free. On a
/// project of two hundred objects it is a frame.
///
/// **What makes a cache correct here is already on the object.**
/// `ModelObject.version` moves on every change and cannot move without one —
/// `copyWith` is the only way to make a changed object, and it bumps. So an
/// object whose version has not moved has the answer it had last time, and the
/// cache is a map from id to (version, answer) rather than a comparison of
/// anything. This is the same bargain `SceneSync` strikes for uploads, and for
/// the same reason: comparing two meshes to find out whether they differ costs
/// more than recomputing the thing the comparison would save.
///
/// **A stale answer is worse than a slow one**, which is why the version is the
/// key rather than a timer or a dirty flag somebody has to remember to set. A
/// bar that says a model is ready after the edit that broke it is a bar that
/// gets somebody to press Export on a file that will not load.
library;

import 'project.dart';
import 'readiness.dart';

/// Readiness for a project, recomputed only where the project moved.
final class ReadinessCache {
  ReadinessCache();

  final Map<int, _Cached> _byObject = <int, _Cached>{};

  /// What [trianglesOnly] and `requireManifold` resolved to last time.
  /// Changing either changes every answer — a quad is a warning to a format
  /// that holds triangles and nothing at all to one that does not, and a
  /// pinched vertex is a warning or a refusal depending on which — so the
  /// whole cache goes rather than being kept under a second key nobody would
  /// think to vary.
  bool? _lastTrianglesOnly;
  bool? _lastRequireManifold;

  /// How many objects have actually been walked, over the life of this cache.
  ///
  /// The number a test asserts on, and the only way to tell a cache that works
  /// from one that returns the right answer by recomputing it: both are green
  /// on the result. It counts objects rather than calls, so "one edit walked
  /// one object" is expressible.
  int get walked => _walked;
  int _walked = 0;

  /// The readiness of [project].
  ///
  /// Objects whose version has not moved keep their issues and their triangle
  /// count; everything else is walked. Objects the project no longer holds are
  /// forgotten, so a cache does not grow across a session of deletes.
  ExportReadiness of(
    ModelProject project, {
    bool? trianglesOnly,
    bool? requireManifold,
  }) {
    final resolvedTrianglesOnly =
        trianglesOnly ?? project.profile.requireTriangles;
    final resolvedRequireManifold =
        requireManifold ?? project.profile.requireManifold;
    if (_lastTrianglesOnly != resolvedTrianglesOnly ||
        _lastRequireManifold != resolvedRequireManifold) {
      _byObject.clear();
      _lastTrianglesOnly = resolvedTrianglesOnly;
      _lastRequireManifold = resolvedRequireManifold;
    }

    final live = <int>{};
    var triangles = 0;
    final perObject = <ExportIssue>[];

    for (final ModelObject object in project.objects) {
      live.add(object.id);
      final _Cached? had = _byObject[object.id];
      final _Cached now;
      if (had != null && had.version == object.version) {
        now = had;
      } else {
        _walked++;
        now = _Cached(
          object.version,
          ExportReadiness.check(
            // One object at a time, so the answer can be kept per object. The
            // profile comes along because a single-object check must not
            // report the budget — that is the project's question and is asked
            // once below, out here where the total is known. `materials` and
            // `images` come along too, whole rather than trimmed to what this
            // one object uses: `object.materialSlots` and every
            // `TextureBinding.imageIndex` are indices into the *project's*
            // tables, and a trimmed copy would have to remap both rather than
            // just pass them — `doc-35n`'s texel-density rule reads exactly
            // this path, and silently found nothing here until this line
            // existed, the same shape of gap `mesh-48`'s own cache had.
            ModelProject(
              objects: <ModelObject>[object],
              profile: _noBudget(project.profile),
              materials: project.materials,
              images: project.images,
            ),
            trianglesOnly: resolvedTrianglesOnly,
            requireManifold: resolvedRequireManifold,
          ).issues
              // Filtered to object-scoped issues only, for the same reason
              // the budget is excluded above: `materialIssues(project)`
              // runs *inside* `ExportReadiness.check` too, over the whole
              // `materials` table just passed in, and every one of its
              // issues has `object: null` (see `_singleMaterialIssues`) —
              // without this filter every material issue would be counted
              // once per object sharing it rather than once, the moment
              // `materials` stopped being an empty list here.
              .where((ExportIssue i) => i.object != null)
              .toList(growable: false),
          object.geometry.triangleCount,
        );
        _byObject[object.id] = now;
      }
      triangles += now.triangles;
      perObject.addAll(now.issues);
    }

    _byObject.removeWhere((int id, _Cached _) => !live.contains(id));

    return ExportReadiness.of(<ExportIssue>[
      // The budget first, ahead of the objects, keeping the order
      // `ExportReadiness.check` puts them in: it is the one fault that is
      // true of all of them at once.
      ?_budgetIssue(project, triangles),
      // Materials next, the same order `ExportReadiness.check` keeps them
      // in — and, unlike the budget, no separate cache-path version to
      // maintain: `materialIssues` reads `project.materials` directly and
      // needs no per-object aggregation redone for it.
      ...materialIssues(project),
      // The texture budget, same reasoning and same order as materials —
      // `textureBudgetIssues` reads `project.images` directly, once, the
      // way `materialIssues` reads `project.materials`.
      ...textureBudgetIssues(project),
      ...perObject,
    ]);
  }

  /// Forgets everything, for a project that has been replaced wholesale.
  ///
  /// Not needed for correctness — ids are never reused, so a new project's
  /// objects miss the cache on their own — and worth having for the case that
  /// is not about correctness: a file closed and another opened should not
  /// leave two hundred entries alive for the length of the session.
  void forget() {
    _byObject.clear();
    _lastTrianglesOnly = null;
    _lastRequireManifold = null;
  }
}

/// [real] with its triangle budget lifted, so a per-object check never
/// reports the budget.
///
/// The budget belongs to the project and is computed once from the summed
/// triangle counts; asking it of one object at a time would report it once per
/// object, each with the wrong number in the sentence. Everything else about
/// [real] carries through unchanged — `maxTextureSize` in particular, which
/// the morph-target check reads per object and would otherwise silently fall
/// back to this profile's own default rather than the project's actual one.
ProjectProfile _noBudget(ProjectProfile real) => ProjectProfile(
  name: 'per-object',
  target: real.target,
  maxTriangles: 0x7FFFFFFF,
  maxJoints: real.maxJoints,
  maxInfluences: real.maxInfluences,
  maxTextureSize: real.maxTextureSize,
  maxTextureBytes: real.maxTextureBytes,
  requireTriangles: real.requireTriangles,
  requireManifold: real.requireManifold,
  texelsPerMeter: real.texelsPerMeter,
);

ExportIssue? _budgetIssue(ModelProject project, int triangles) {
  final allowed = project.profile.maxTriangles;
  return triangles <= allowed
      ? null
      : ExportIssue(
          ExportSeverity.warning,
          'the project draws $triangles triangles and the '
          '${project.profile.name} profile allows $allowed; it will load and '
          'it will cost frames',
        );
}

final class _Cached {
  const _Cached(this.version, this.issues, this.triangles);

  final int version;
  final List<ExportIssue> issues;
  final int triangles;
}
