/// `anim-03`: `ProjectSkeleton`, `ProjectClip` — round-tripped through
/// `fromModelDocument`/`toModelDocument` against the row's own three named
/// samples, and checked on their own for the tables-must-not-silently-drop
/// contract every other project table already keeps.
///
///     dart test test/project_animation_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

/// [skin]'s own inverse bind matrices, keyed by joint name rather than by
/// index — node numbering is not guaranteed identical between [doc] and
/// whatever `toModelDocument` produces from a project built out of it, so
/// comparing by index would be comparing the wrong two joints the moment
/// numbering drifted for a reason that has nothing to do with the skin.
Map<String, Matrix4> _inverseBindByJointName(
  ModelDocument doc,
  ModelSkin skin,
) {
  final result = <String, Matrix4>{};
  for (var j = 0; j < skin.joints.length; j++) {
    final name = doc.nodes[skin.joints[j]].name ?? 'joint $j';
    result[name] = skin.inverseBindMatrices[j];
  }
  return result;
}

void _expectMatrixClose(Matrix4 a, Matrix4 b, {String? reason}) {
  for (var e = 0; e < 16; e++) {
    expect(
      a.storage[e],
      closeTo(b.storage[e], 1e-6),
      reason: '$reason, element $e',
    );
  }
}

/// Every track of every clip in [source], matched onto the same track in
/// [rewritten] by (joint/object *name*, path) rather than by node index,
/// for the identical reason [_inverseBindByJointName] does.
void _expectClipsMatch(ModelDocument source, ModelDocument rewritten) {
  expect(rewritten.animations, hasLength(source.animations.length));

  Map<(String, AnimationPath), AnimationTrack> byNamedTarget(
    ModelDocument doc,
    AnimationClip clip,
  ) => <(String, AnimationPath), AnimationTrack>{
    for (final track in clip.tracks)
      (
        doc.nodes[track.nodeIndex].name ?? 'node ${track.nodeIndex}',
        track.path,
      ): track,
  };

  for (var c = 0; c < source.animations.length; c++) {
    final sourceClip = source.animations[c];
    final rewrittenClip = rewritten.animations[c];
    final sourceByTarget = byNamedTarget(source, sourceClip);
    final rewrittenByTarget = byNamedTarget(rewritten, rewrittenClip);

    expect(rewrittenByTarget.keys.toSet(), sourceByTarget.keys.toSet());

    for (final key in sourceByTarget.keys) {
      final a = sourceByTarget[key]!;
      final b = rewrittenByTarget[key]!;
      // Mutation: sample the track at a fixed time and compare the sampled
      // value instead of the raw keyframes — this would pass even with a
      // dropped keyframe between two identical endpoints, which byte
      // equality on the whole array does not let through.
      expect(b.times, orderedEquals(a.times), reason: '$key times');
      expect(b.values, orderedEquals(a.values), reason: '$key values');
      expect(b.interpolation, a.interpolation, reason: '$key interpolation');
      expect(b.componentCount, a.componentCount, reason: '$key componentCount');
    }
  }
}

void main() {
  group('RiggedFigure.glb: a skin round-trips', () {
    test('joint count, names and inverse bind matrices survive within '
        '1e-6', () async {
      final source = await GltfLoader().load(_sample('RiggedFigure.glb'));
      expect(source.skins, hasLength(1));

      final project = fromModelDocument(source);
      expect(project.skeletons, hasLength(1));
      // Mutation: read `document.skins` but never set `skeletonIndex` on
      // the object whose surface actually names the skin — this project
      // would still have a `ProjectSkeleton`, but no surface would end up
      // pointing at it, which the assembled-document check below catches.
      final skinnedObjects = project.objects.where(
        (o) => o.skeletonIndex != null,
      );
      expect(skinnedObjects, isNotEmpty);

      final rewritten = toModelDocument(project);
      expect(rewritten.skins, hasLength(1));

      final sourceByName = _inverseBindByJointName(source, source.skins.single);
      final rewrittenByName = _inverseBindByJointName(
        rewritten,
        rewritten.skins.single,
      );
      expect(rewrittenByName.keys.toSet(), sourceByName.keys.toSet());
      for (final name in sourceByName.keys) {
        _expectMatrixClose(
          rewrittenByName[name]!,
          sourceByName[name]!,
          reason: 'joint "$name"',
        );
      }
    });

    test(
      'a skinned surface\'s own transform stays identity on both sides',
      () async {
        // The joints place a skinned surface, not the node it hangs from —
        // baking the placement in as well would move it twice. Checked here
        // because `toModelDocument`'s own skin handling is new code, not
        // inherited from the glTF loader's already-tested version of the
        // same rule.
        final source = await GltfLoader().load(_sample('RiggedFigure.glb'));
        final project = fromModelDocument(source);
        final rewritten = toModelDocument(project);

        final skinned = rewritten.surfaces.where((s) => s.skinIndex != null);
        expect(skinned, isNotEmpty);
        for (final surface in skinned) {
          // Mutation: bake the object's own placement into the surface
          // transform regardless of whether it is skinned — this would read
          // a non-identity matrix for at least one of these.
          expect(
            surface.transform.storage,
            orderedEquals(Matrix4.identity().storage),
          );
        }
      },
    );
  });

  group('BoxAnimated.glb: a plain transform clip round-trips', () {
    test('tracks match byte for byte', () async {
      final source = await GltfLoader().load(_sample('BoxAnimated.glb'));
      expect(source.animations, isNotEmpty);
      expect(source.skins, isEmpty); // exercises the no-skin path

      final project = fromModelDocument(source);
      final rewritten = toModelDocument(project);
      _expectClipsMatch(source, rewritten);
    });
  });

  group('AnimatedMorphCube.glb: a weights clip round-trips', () {
    test('tracks match byte for byte, component count included', () async {
      final source = await GltfLoader().load(_sample('AnimatedMorphCube.glb'));
      expect(source.animations, isNotEmpty);
      final hasWeights = source.animations.any(
        (clip) => clip.tracks.any((t) => t.path == AnimationPath.weights),
      );
      expect(
        hasWeights,
        isTrue,
        reason: 'fixture should carry a weights track',
      );

      final project = fromModelDocument(source);
      final rewritten = toModelDocument(project);
      _expectClipsMatch(source, rewritten);
    });
  });

  group('ProjectSkeleton, ProjectClip on their own', () {
    test('a mismatched joint/matrix count is refused', () {
      expect(
        () => ProjectSkeleton(
          joints: <int>[1, 2],
          inverseBindMatrices: <Matrix4>[Matrix4.identity()],
        ),
        throwsArgumentError,
      );
    });
  });

  group('every project mutator preserves skeletons and clips', () {
    // A minimal skinned+animated project, built by hand rather than through
    // `fromModelDocument`, so this group tests `ModelProject`'s own methods
    // in isolation from the importer.
    ModelProject rigged() {
      final project = const ModelProject().added(
        (id) => ModelObject(
          id: id,
          name: 'joint',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );
      return project.copyWith(
        skeletons: <ProjectSkeleton>[
          ProjectSkeleton(
            joints: <int>[project.objects.single.id],
            inverseBindMatrices: <Matrix4>[Matrix4.identity()],
          ),
        ],
        clips: <ProjectClip>[
          const ProjectClip(name: 'idle', tracks: <ProjectTrack>[]),
        ],
      );
    }

    test('added() carries them through', () {
      final project = rigged().added(
        (id) => ModelObject(
          id: id,
          name: 'extra',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );
      // Mutation: construct the new `ModelProject` in `added()` without
      // naming `skeletons`/`clips` — both would silently reset to empty,
      // which is exactly the landmine this test exists to catch.
      expect(project.skeletons, hasLength(1));
      expect(project.clips, hasLength(1));
    });

    test('withObject() carries them through', () {
      final source = rigged();
      final object = source.objects.single;
      final project = source.withObject(object.copyWith(name: 'renamed'));
      expect(project.skeletons, hasLength(1));
      expect(project.clips, hasLength(1));
    });

    test('removed() carries them through', () {
      final source = rigged().added(
        (id) => ModelObject(
          id: id,
          name: 'doomed',
          geometry: const SocketGeometry(),
          transform: Matrix4.identity(),
        ),
      );
      final doomedId = source.objects.last.id;
      final project = source.removed(doomedId);
      expect(project.skeletons, hasLength(1));
      expect(project.clips, hasLength(1));
    });

    test('copyWith() with no explicit skeletons/clips keeps the existing '
        'ones', () {
      final project = rigged().copyWith(profile: ProjectProfile.mobile);
      expect(project.skeletons, hasLength(1));
      expect(project.clips, hasLength(1));
    });
  });
}
