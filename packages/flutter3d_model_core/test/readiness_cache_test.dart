/// Readiness asked every frame, computed only where the project moved.
///
///     dart test test/readiness_cache_test.dart
///
/// **What this is for is the walk count.** Every assertion about the *answer*
/// is equally true of a cache that works and of one that quietly recomputes
/// everything: both are green on the issues. The number that separates them is
/// how many objects were walked, which is why `ReadinessCache.walked` exists at
/// all — and why half this file asserts on it.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A project of [count] cubes, each six quads and twelve triangles.
ModelProject cubes(int count, {ProjectProfile? profile}) {
  var project = ModelProject(profile: profile ?? const ProjectProfile());
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'cube $id',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );
  }
  return project;
}

/// One object with no faces at all, which readiness calls an error.
ModelObject Function(int) ghost() =>
    (int id) => ModelObject(
      id: id,
      name: 'ghost',
      geometry: EditedGeometry(EditMesh.empty()),
      transform: Matrix4.identity(),
    );

/// A project of [count] objects, each two triangles that share one vertex and
/// no edge — a surface pinched at a point, which is a warning until a profile
/// asks for a manifold and an error once it does.
ModelProject pinched(int count, {ProjectProfile? profile}) {
  var project = ModelProject(profile: profile ?? const ProjectProfile());
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'pinch $id',
        geometry: EditedGeometry(
          EditMesh.fromFaces(
            <Vector3>[
              Vector3(0, 0, 0),
              Vector3(1, 0, 0),
              Vector3(0, 1, 0),
              Vector3(2, 0, 0),
              Vector3(2, 1, 0),
            ],
            <List<int>>[
              <int>[0, 1, 2],
              <int>[2, 3, 4],
            ],
          ),
        ),
        transform: Matrix4.identity(),
      ),
    );
  }
  return project;
}

void main() {
  group('what it does not walk twice', () {
    test('a second ask on the same project walks nothing', () {
      final project = cubes(5);
      final cache = ReadinessCache();

      cache.of(project);
      expect(cache.walked, 5, reason: 'the first ask has to walk them all');

      cache.of(project);
      cache.of(project);

      // Mutation: key the cache on the project's identity instead of each
      // object's version. It still answers correctly and still walks five
      // objects on every edit, which is the whole cost this exists to avoid.
      expect(cache.walked, 5);
    });

    test('one edit walks one object', () {
      final project = cubes(20);
      final cache = ReadinessCache();
      cache.of(project);
      expect(cache.walked, 20);

      final moved = project.withObject(
        project.objects[7].copyWith(
          transform: Matrix4.translationValues(1, 0, 0),
        ),
      );
      cache.of(moved);

      // Twenty-one, not forty: nineteen objects kept their answers because
      // their versions did not move. Mutation: drop the version comparison and
      // this is forty — every drag of one object walks the whole project.
      expect(cache.walked, 21);
    });

    test('the answer is the same one the full check gives', () {
      final project = cubes(3).added(ghost());
      final cache = ReadinessCache();

      final cached = cache.of(project);
      final full = ExportReadiness.check(project);

      // The cache is not allowed to be a different check that happens to be
      // faster. Same issues, same order, same verdict.
      expect(cached.issues.length, full.issues.length);
      expect(
        cached.issues.map((ExportIssue i) => i.message),
        full.issues.map((ExportIssue i) => i.message),
      );
      expect(cached.canExport, full.canExport);
      expect(cached.says, full.says);
    });

    test('an unchanged answer survives many asks unchanged', () {
      final project = cubes(2).added(ghost());
      final cache = ReadinessCache();

      final first = cache.of(project);
      final tenth = List<ExportReadiness>.generate(
        10,
        (int _) => cache.of(project),
      ).last;

      expect(tenth.issues.length, first.issues.length);
      expect(tenth.says, first.says);
      expect(cache.walked, 3);
    });
  });

  group('what it does walk', () {
    test('a new object is walked and the others are not', () {
      final project = cubes(4);
      final cache = ReadinessCache();
      cache.of(project);

      cache.of(project.added(ghost()));

      expect(cache.walked, 5);
    });

    test('changing the target format throws the whole cache away', () {
      final project = cubes(4);
      final cache = ReadinessCache();
      cache.of(project);
      expect(cache.walked, 4);

      final loose = cache.of(project, trianglesOnly: false);

      // Every answer changes when the question does — a quad is a warning to a
      // format that holds triangles and nothing at all to one that does not —
      // so keeping the old answers under the new question would report six
      // quads to a format perfectly able to write them. Mutation: ignore the
      // flag and `loose` still complains about n-gons.
      expect(cache.walked, 8);
      expect(loose.issues, isEmpty);
      expect(cache.of(project).issues, isNotEmpty);
    });

    test('changing whether a manifold is required throws the whole cache '
        'away too', () {
      final project = pinched(3);
      final cache = ReadinessCache();
      final loose = cache.of(project);
      expect(cache.walked, 3);
      expect(loose.canExport, isTrue);

      // Mutation: ignore `requireManifold` the way the cache used to ignore
      // nothing at all before this field existed. `strict` would then read
      // the three warnings cached under the loose profile instead of the
      // three errors a stricter one asks for, and a status bar built on top
      // of this cache would keep saying "exports with a warning" about a
      // model that no longer does.
      final strict = cache.of(project, requireManifold: true);
      expect(cache.walked, 6);
      expect(strict.canExport, isFalse);
      expect(cache.of(project).canExport, isTrue);
    });

    test('forget makes the next ask walk everything again', () {
      final project = cubes(6);
      final cache = ReadinessCache()..of(project);
      expect(cache.walked, 6);

      cache
        ..forget()
        ..of(project);

      expect(cache.walked, 12);
    });
  });

  group('the budget, which belongs to the project', () {
    test('it is reported once and with the total', () {
      final tight = cubes(4, profile: const ProjectProfile(maxTriangles: 10));
      final cache = ReadinessCache();

      final issues = cache.of(tight).issues;
      final budget = issues.where(
        (ExportIssue i) => i.message.contains('profile allows'),
      );

      // Mutation: ask each object about the budget rather than summing first.
      // Four sentences instead of one, each naming twelve triangles against a
      // budget of ten — and the project's real total, forty-eight, is nowhere.
      expect(budget, hasLength(1));
      expect(budget.single.message, contains('48 triangles'));
      expect(budget.single.object, isNull);
    });

    test('it is recomputed when an object changes, without walking the rest', () {
      final tight = cubes(4, profile: const ProjectProfile(maxTriangles: 100));
      final cache = ReadinessCache();
      expect(
        cache
            .of(tight)
            .issues
            .any((ExportIssue i) => i.message.contains('profile allows')),
        isFalse,
      );

      // A cube replaced by a lathe of sixty-four segments: the budget has to
      // move even though only one object was walked. Mutation: keep the cached
      // triangle count when the version moves and the total stays at 48, so a
      // model that has just gone twelve times over its budget reports nothing.
      final dense = tight.withObject(
        tight.objects.first.copyWith(
          geometry: ParametricGeometry(const ParametricCylinder(segments: 64)),
        ),
      );
      final after = cache.of(dense);

      expect(cache.walked, 5, reason: 'one object walked, three reused');
      expect(
        after.issues.any(
          (ExportIssue i) => i.message.contains('profile allows'),
        ),
        isTrue,
      );
    });

    test('a deleted object stops counting toward the budget', () {
      final tight = cubes(4, profile: const ProjectProfile(maxTriangles: 40));
      final cache = ReadinessCache();
      expect(
        cache
            .of(tight)
            .issues
            .any((ExportIssue i) => i.message.contains('profile allows')),
        isTrue,
        reason: '48 triangles against a budget of 40',
      );

      final fewer = tight.removed(tight.objects.first.id);

      // Mutation: keep entries for objects the project no longer holds. The
      // deleted cube goes on being counted, so the budget warning never clears
      // and the cache grows for the length of the session.
      expect(
        cache
            .of(fewer)
            .issues
            .any((ExportIssue i) => i.message.contains('profile allows')),
        isFalse,
        reason: '36 triangles against a budget of 40',
      );
    });
  });
}
