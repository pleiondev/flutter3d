/// `anim-25`'s own row: the three `RigJob` kinds whose underlying functions
/// live in this package — `bakeIk`, `bakeDrivers`, `bakeRootMotion` — run
/// through `rig_job.dart`'s request/run shape and applied through
/// `ApplyClipResult`. `bindWeights` and `retargetClip`, the two kinds that run
/// the rig algorithms in `lib/src/rig/`, are tested in
/// `test/rig_job_retarget_and_bind_test.dart`.
///
///     dart test test/rig_job_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A joint with no mesh of its own — the same fixture shape
/// `ik_constraint_test.dart` already uses.
ModelObject _joint(int id, {int? parent, required Vector3 localOffset}) =>
    ModelObject(
      id: id,
      name: 'joint$id',
      geometry: const SocketGeometry(),
      transform: Matrix4.translation(localOffset),
      parent: parent,
    );

/// A straight two-bone chain along +X: root at the origin, mid one unit
/// out, the effector one further unit past it.
ModelProject _straightChain() => ModelProject(
  objects: <ModelObject>[
    _joint(1, localOffset: Vector3.zero()),
    _joint(2, parent: 1, localOffset: Vector3(1, 0, 0)),
    _joint(3, parent: 2, localOffset: Vector3(1, 0, 0)),
  ],
);

IkConstraint _chainConstraint() => IkConstraint(
  rootJointId: 1,
  midJointId: 2,
  effectorJointId: 3,
  target: Vector3.zero(),
  pole: Vector3.zero(),
);

/// [times]/[values] as a rotation-only [AnimationTrack] for [objectId] —
/// two identity keys, enough for `bakeIk` to have a duration to bake over
/// without asserting anything about the shape of the bend itself (that is
/// `ik_constraint_test.dart`'s own job).
ProjectTrack _identityRotationTrack(int objectId) {
  final identity = Quaternion.identity();
  return ProjectTrack(
    objectId: objectId,
    track: AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.rotation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0, 1]),
      values: Float32List.fromList(<double>[
        identity.x,
        identity.y,
        identity.z,
        identity.w,
        identity.x,
        identity.y,
        identity.z,
        identity.w,
      ]),
      componentCount: 4,
    ),
  );
}

ModelProject _projectWithClip(ProjectClip clip) =>
    _straightChain().copyWith(clips: <ProjectClip>[clip]);

void _expectTracksEqual(AnimationTrack a, AnimationTrack b) {
  expect(a.nodeIndex, b.nodeIndex);
  expect(a.path, b.path);
  expect(a.interpolation, b.interpolation);
  expect(a.times, b.times);
  expect(a.values, b.values);
  expect(a.componentCount, b.componentCount);
}

void _expectClipsEqual(ProjectClip a, ProjectClip b) {
  expect(a.name, b.name);
  expect(a.tracks, hasLength(b.tracks.length));
  for (var i = 0; i < a.tracks.length; i++) {
    expect(a.tracks[i].objectId, b.tracks[i].objectId);
    _expectTracksEqual(a.tracks[i].track, b.tracks[i].track);
  }
}

void main() {
  group('bakeIkJobRequestFor', () {
    test('captures the clip at its own index', () {
      final clip = ProjectClip(
        tracks: <ProjectTrack>[
          _identityRotationTrack(1),
          _identityRotationTrack(2),
        ],
      );
      final project = _projectWithClip(clip);
      final request = bakeIkJobRequestFor(
        project,
        0,
        _chainConstraint(),
        fps: 30,
      );

      expect(request, isNotNull);
      expect(request!.clipIndex, 0);
      expect(request.fps, 30);
      _expectClipsEqual(request.clip, clip);
    });

    test('null for a clip index that is not there', () {
      final project = _straightChain();
      expect(
        bakeIkJobRequestFor(project, 0, _chainConstraint(), fps: 30),
        isNull,
      );
    });
  });

  group('BakeIkJobRequest.run', () {
    test('matches calling bakeIk directly, byte for byte', () async {
      final clip = ProjectClip(
        tracks: <ProjectTrack>[
          _identityRotationTrack(1),
          _identityRotationTrack(2),
        ],
      );
      final project = _projectWithClip(clip);
      final request = bakeIkJobRequestFor(
        project,
        0,
        _chainConstraint(),
        fps: 30,
      )!;

      final direct = bakeIk(
        project: project,
        clip: clip,
        constraint: _chainConstraint(),
        fps: 30,
      );
      final throughJob = await request.run();

      _expectClipsEqual(throughJob, direct);
    });

    test('running the job never touches the project it read from', () async {
      final clip = ProjectClip(
        tracks: <ProjectTrack>[
          _identityRotationTrack(1),
          _identityRotationTrack(2),
        ],
      );
      final project = _projectWithClip(clip);
      final request = bakeIkJobRequestFor(
        project,
        0,
        _chainConstraint(),
        fps: 30,
      )!;

      await request.run();

      // Mutation: have `run` write its own answer back into `request.project`
      // (or some shared mutable state) instead of only returning it — a job
      // whose own `run` can touch the document is a job cancellation cannot
      // make safe, since the damage would already be done before anyone
      // decided whether to apply the result.
      expect(identical(project.clips.single, clip), isTrue);
      expect(project.clips, hasLength(1));
    });
  });

  group('bakeDriversJobRequestFor / BakeDriversJobRequest.run', () {
    test('matches calling bakeShapeDrivers directly, byte for byte', () async {
      final identity = Quaternion.identity();
      final bent = Quaternion.axisAngle(Vector3(1, 0, 0), _piOverTwo);
      final clip = ProjectClip(
        tracks: <ProjectTrack>[
          ProjectTrack(
            objectId: 2,
            track: AnimationTrack(
              nodeIndex: 0,
              path: AnimationPath.rotation,
              interpolation: AnimationInterpolation.linear,
              times: Float32List.fromList(<double>[0, 1]),
              values: Float32List.fromList(<double>[
                identity.x,
                identity.y,
                identity.z,
                identity.w,
                bent.x,
                bent.y,
                bent.z,
                bent.w,
              ]),
              componentCount: 4,
            ),
          ),
        ],
      );
      final drivers = <ShapeDriver>[
        const ShapeDriver(
          shapeIndex: 0,
          jointId: 2,
          axis: DriverAxis.x,
          from: 0,
          to: _piOverTwo,
        ),
      ];
      final project = _projectWithClip(clip);
      final request = bakeDriversJobRequestFor(project, 0, drivers, 9, 1)!;

      final direct = bakeShapeDrivers(
        clip: clip,
        drivers: drivers,
        shapeTargetObjectId: 9,
        shapeCount: 1,
      );
      final throughJob = await request.run();

      _expectClipsEqual(throughJob, direct);
    });

    test('null for a clip index that is not there', () {
      final project = _straightChain();
      expect(
        bakeDriversJobRequestFor(project, 0, const <ShapeDriver>[], 9, 1),
        isNull,
      );
    });

    test(
      'falls back to the shape-owning object\'s own persisted drivers when '
      'none are given, matching an explicit list byte for byte — anim-34d',
      () async {
        final identity = Quaternion.identity();
        final bent = Quaternion.axisAngle(Vector3(1, 0, 0), _piOverTwo);
        final clip = ProjectClip(
          tracks: <ProjectTrack>[
            ProjectTrack(
              objectId: 2,
              track: AnimationTrack(
                nodeIndex: 0,
                path: AnimationPath.rotation,
                interpolation: AnimationInterpolation.linear,
                times: Float32List.fromList(<double>[0, 1]),
                values: Float32List.fromList(<double>[
                  identity.x,
                  identity.y,
                  identity.z,
                  identity.w,
                  bent.x,
                  bent.y,
                  bent.z,
                  bent.w,
                ]),
                componentCount: 4,
              ),
            ),
          ],
        );
        const drivers = <ShapeDriver>[
          ShapeDriver(
            shapeIndex: 0,
            jointId: 2,
            axis: DriverAxis.x,
            from: 0,
            to: _piOverTwo,
          ),
        ];

        // Built by hand rather than through `.added`: `_straightChain()`
        // constructs its objects directly, so its own `nextId` is still the
        // default 1 — `.added` would hand back an object numbered 1 too,
        // doubling up on the first joint's own id rather than naming a
        // fourth object.
        const faceId = 9;
        final project = ModelProject(
          objects: <ModelObject>[
            ..._straightChain().objects,
            ModelObject(
              id: faceId,
              name: 'face',
              geometry: const SocketGeometry(),
              transform: Matrix4.identity(),
              shapeDrivers: drivers,
            ),
          ],
          clips: <ProjectClip>[clip],
        );

        final fromPersisted = bakeDriversJobRequestFor(
          project,
          0,
          null,
          faceId,
          1,
        )!;
        final fromExplicit = bakeDriversJobRequestFor(
          project,
          0,
          drivers,
          faceId,
          1,
        )!;

        final persistedResult = await fromPersisted.run();
        final explicitResult = await fromExplicit.run();

        expect(persistedResult.tracks, hasLength(2));
        expect(explicitResult.tracks, hasLength(2));
        final persistedTrack = persistedResult.tracks.last.track;
        final explicitTrack = explicitResult.tracks.last.track;
        final persistedOut = Float32List(1);
        final explicitOut = Float32List(1);
        for (final t in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
          persistedTrack.sample(t, persistedOut);
          explicitTrack.sample(t, explicitOut);
          expect(
            persistedOut[0],
            closeTo(explicitOut[0], 1e-5),
            reason: 't=$t',
          );
        }
      },
    );
  });

  group('BakeRootMotionJobRequest.run', () {
    test('answers with the same ExtractRootMotion a caller would build by '
        'hand', () async {
      const request = BakeRootMotionJobRequest(clipIndex: 0, rootJoint: 1);
      final command = await request.run();

      expect(command.clipIndex, 0);
      expect(command.rootJoint, 1);
    });

    test('applying it through history matches applying ExtractRootMotion '
        'directly', () async {
      ModelProject walkingRootProject() => _straightChain().copyWith(
        clips: <ProjectClip>[
          ProjectClip(
            tracks: <ProjectTrack>[
              ProjectTrack(
                objectId: 1,
                track: AnimationTrack(
                  nodeIndex: 0,
                  path: AnimationPath.translation,
                  interpolation: AnimationInterpolation.linear,
                  componentCount: 3,
                  times: Float32List.fromList(<double>[0, 0.5, 1]),
                  values: Float32List.fromList(<double>[
                    0,
                    0,
                    0,
                    1,
                    0,
                    0,
                    2,
                    0,
                    0,
                  ]),
                ),
              ),
            ],
          ),
        ],
      );

      const request = BakeRootMotionJobRequest(clipIndex: 0, rootJoint: 1);
      final throughJob = ModelHistory(walkingRootProject());
      final direct = ModelHistory(walkingRootProject());

      final command = await request.run();
      final throughJobRefusal = throughJob.run(command);
      final directRefusal = direct.run(
        const ExtractRootMotion(clipIndex: 0, rootJoint: 1),
      );

      expect(throughJobRefusal, isNull);
      expect(directRefusal, isNull);
      _expectClipsEqual(
        throughJob.project.clips.single,
        direct.project.clips.single,
      );
    });
  });

  group('ApplyClipResult', () {
    test('null clipIndex appends the clip', () {
      final project = _straightChain();
      final newClip = ProjectClip(
        name: 'new',
        tracks: <ProjectTrack>[_identityRotationTrack(1)],
      );
      final history = ModelHistory(project);

      expect(history.run(ApplyClipResult(clip: newClip)), isNull);
      expect(history.project.clips, hasLength(1));
      _expectClipsEqual(history.project.clips.single, newClip);
    });

    test('a given clipIndex replaces the clip already there', () {
      final original = ProjectClip(
        name: 'original',
        tracks: <ProjectTrack>[_identityRotationTrack(1)],
      );
      final project = _projectWithClip(original);
      final replacement = ProjectClip(
        name: 'baked',
        tracks: <ProjectTrack>[_identityRotationTrack(2)],
      );
      final history = ModelHistory(project);

      expect(
        history.run(ApplyClipResult(clip: replacement, clipIndex: 0)),
        isNull,
      );
      expect(history.project.clips, hasLength(1));
      _expectClipsEqual(history.project.clips.single, replacement);
    });

    test('refuses a clipIndex that is not there, leaving the project '
        'untouched', () {
      final project = _straightChain();
      final history = ModelHistory(project);
      final clip = ProjectClip(
        tracks: <ProjectTrack>[_identityRotationTrack(1)],
      );

      final refusal = history.run(ApplyClipResult(clip: clip, clipIndex: 0));

      expect(refusal, isNotNull);
      expect(history.project.clips, isEmpty);
    });

    test('is not in modelCommandNames — an agent tool for it is later, '
        'app-integration work, the same scope line this row leaves '
        'undrawn for a reason its own doc comment gives', () {
      expect(modelCommandNames.contains('applyClipResult'), isFalse);
    });
  });

  group('cancelling a RigJob leaves the document untouched', () {
    // The app's own `Job<T>` (`ui-25`) is what actually gates a chunk behind
    // `cancel()` before it starts — an app-layer type this package cannot
    // import. This mirrors its own one-chunk contract (`Job.run`: "if
    // `_cancelRequested`, return before `runChunk` ever starts") without
    // depending on it, so as to name the guarantee every test above already
    // leans on directly: a cancelled job never calls `run`, `run` never
    // touches the project it read from, and a result nobody applies is a
    // document nobody changed.
    Future<T?> runOneChunkUnlessCancelled<T>(
      Future<T> Function() run, {
      required bool cancelled,
    }) async {
      if (cancelled) return null;
      return run();
    }

    test(
      'cancelled before its one chunk starts: nothing is ever applied',
      () async {
        final clip = ProjectClip(
          tracks: <ProjectTrack>[
            _identityRotationTrack(1),
            _identityRotationTrack(2),
          ],
        );
        final project = _projectWithClip(clip);
        final history = ModelHistory(project);
        final request = bakeIkJobRequestFor(
          project,
          0,
          _chainConstraint(),
          fps: 30,
        )!;

        final result = await runOneChunkUnlessCancelled(
          request.run,
          cancelled: true,
        );

        expect(result, isNull);
        expect(history.canUndo, isFalse);
        _expectClipsEqual(history.project.clips.single, clip);
      },
    );

    test('not cancelled: the same request runs and answers with a result '
        'to apply', () async {
      final clip = ProjectClip(
        tracks: <ProjectTrack>[
          _identityRotationTrack(1),
          _identityRotationTrack(2),
        ],
      );
      final project = _projectWithClip(clip);
      final request = bakeIkJobRequestFor(
        project,
        0,
        _chainConstraint(),
        fps: 30,
      )!;

      final result = await runOneChunkUnlessCancelled(
        request.run,
        cancelled: false,
      );

      expect(result, isNotNull);
    });
  });
}

const double _piOverTwo = 1.5707963267948966;
