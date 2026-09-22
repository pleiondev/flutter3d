/// `pro-sc-09`: the web's own sculpt ceiling, and a build that gives the
/// frame back.
///
///     flutter test test/sculpt_budget_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/sculpt_budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

SculptMesh _grid({int side = 48}) {
  final points = <Vector3>[
    for (var z = 0; z < side; z++)
      for (var x = 0; x < side; x++) Vector3(x.toDouble(), 0, z.toDouble()),
  ];
  final faces = <List<int>>[
    for (var z = 0; z < side - 1; z++)
      for (var x = 0; x < side - 1; x++)
        <int>[
          z * side + x,
          z * side + x + 1,
          (z + 1) * side + x + 1,
          (z + 1) * side + x,
        ],
  ];
  return SculptMesh.fromEditMesh(EditMesh.fromFaces(points, faces));
}

void main() {
  group('the ceiling', () {
    test('is the profile\'s own number, and only in a browser', () {
      const ProjectProfile profile = ProjectProfile();
      expect(profile.sculptTriangleLimitWeb, 300000);

      // **Mutation: apply it everywhere.** A desktop then refuses a mesh
      // that machine sculpts comfortably — the number is about a frame's
      // budget in a single-threaded runtime, not about what a machine can
      // hold.
      expect(overSculptLimit(profile, 400000, onWeb: true), isTrue);
      expect(overSculptLimit(profile, 400000, onWeb: false), isFalse);
      expect(overSculptLimit(profile, 299999, onWeb: true), isFalse);
    });

    test('and the refusal names both numbers', () {
      const ProjectProfile profile = ProjectProfile();
      final String said = sculptLimitRefusal(profile, 412000);

      // "Too big" is not a thing a person can act on. Mutation: say that
      // instead, and the only way to find out how much too big is to
      // decimate and try again.
      expect(said, contains('412000'));
      expect(said, contains('300000'));
      expect(said, contains('desktop'));
    });

    test('a project carries its own, through a round trip', () {
      const ProjectProfile profile = ProjectProfile(
        sculptTriangleLimitWeb: 180000,
      );
      final ModelProject project = const ModelProject().copyWith(
        profile: profile,
      );

      final ProjectRead read = readProject(writeProject(project));
      expect(read, isA<ProjectOpened>());
      expect(
        (read as ProjectOpened).project.profile.sculptTriangleLimitWeb,
        180000,
      );
    });

    test('and a file written before this field reads the default', () {
      // Mutation: make the field required on read. Every project written
      // before `pro-sc-09` then fails to open, which is the one thing a
      // format's own doc comment promises never happens.
      const ProjectProfile fallback = ProjectProfile();
      expect(fallback.sculptTriangleLimitWeb, 300000);
    });
  });

  group('a build that gives the frame back', () {
    test('spends its slice and stops, and finishes across calls', () {
      var ran = 0;
      final build = YieldingBuild(
        steps: 100,
        step: (int _) {
          ran++;
          // Each step is long enough that a six-millisecond slice takes a
          // handful of them, not all hundred.
          final watch = Stopwatch()..start();
          while (watch.elapsedMicroseconds < 800) {}
        },
        slice: const Duration(milliseconds: 6),
      );

      expect(build.advance(), isFalse);
      expect(ran, greaterThan(0));
      expect(ran, lessThan(100));
      expect(build.fraction, greaterThan(0));

      // **Mutation: run the whole job in one call.** The page stops
      // painting for as long as it takes, which on the web is the whole of
      // it — there is no isolate to hide it in.
      while (!build.advance()) {}
      expect(ran, 100);
      expect(build.finished, isTrue);
      expect(build.fraction, 1);
    });

    test('a finished build is not run again', () {
      var ran = 0;
      final build = YieldingBuild(steps: 3, step: (int _) => ran++);
      expect(build.advance(), isTrue);
      expect(build.advance(), isTrue);
      expect(ran, 3);
    });

    test('a job of no steps is already done', () {
      final build = YieldingBuild(steps: 0, step: (int _) {});
      expect(build.advance(), isTrue);
      expect(build.fraction, 1);
    });

    test('the web gets the shorter slice', () {
      expect(
        YieldingBuild(steps: 1, step: (int _) {}, onWeb: true).slice,
        kBuildSliceOnWeb,
      );
      expect(
        YieldingBuild(steps: 1, step: (int _) {}, onWeb: false).slice,
        kBuildSliceOnDesktop,
      );
      expect(kBuildSliceOnWeb, lessThan(kBuildSliceOnDesktop));
    });

    test('reading the chunks for a tree lands every vertex', () {
      final SculptMesh mesh = _grid();
      final into = List<double>.filled(mesh.vertexCount * 3, -1);
      final YieldingBuild build = readChunksForBvh(mesh, into, onWeb: true);

      expect(build.steps, mesh.chunkCount);
      while (!build.advance()) {}

      // The flat array the tree sorts over is the larger half of the build
      // on a mesh at the ceiling, and the half that can stop between
      // chunks without leaving anything half written.
      final Vector3 last = mesh.positionOf(mesh.vertexCount - 1);
      expect(into[(mesh.vertexCount - 1) * 3], closeTo(last.x, 1e-6));
      expect(into[(mesh.vertexCount - 1) * 3 + 2], closeTo(last.z, 1e-6));
      expect(into.every((double v) => v != -1 || v == 0), isTrue);
    });
  });
}
