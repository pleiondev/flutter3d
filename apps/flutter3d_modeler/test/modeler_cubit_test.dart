/// What the modeller is doing, asked without building a window.
///
///     flutter test test/modeler_cubit_test.dart
///
/// **This file is the reason `ModelerCubit` exists.** Before it, the only way
/// to ask "does changing the mode keep the selection" or "does the readiness
/// follow a command" was to pump a shell and press things — so nobody asked,
/// and the answer to the second one was no. Every test here is a sentence about
/// a transition, and none of them needs a frame.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/modeler_cubit.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/timeline_playback.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter3d_rig/flutter3d_rig.dart' show BoneMap, BoneSegment;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A project of [count] cubes, named `a`, `b`, …
ModelProject cubes(int count) {
  var project = const ModelProject();
  for (var i = 0; i < count; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: String.fromCharCode(97 + i),
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
      ),
    );
  }
  return project;
}

/// A single object with one enabled `MirrorModifier` on its stack — enough
/// for `jobRequestFor` to hand back a real `JobRequest`.
ModelProject withOneModifier() => const ModelProject().added(
  (int id) => ModelObject(
    id: id,
    name: 'a',
    geometry: EditedGeometry(EditMesh.cuboid()),
    transform: Matrix4.identity(),
    modifiers: <ModifierSlot>[
      ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
    ],
  ),
);

/// A two-joint rig — root and child, the child a metre up — the same
/// fixture `flutter3d_model_core`'s own
/// `rig_job_retarget_and_bind_test.dart` builds for `RetargetClipJobRequest`.
({ModelProject project, ProjectSkeleton skeleton}) twoJointRig() {
  final objects = <ModelObject>[
    ModelObject(
      id: 1,
      name: 'root',
      geometry: const SocketGeometry(),
      transform: Matrix4.identity(),
    ),
    ModelObject(
      id: 2,
      name: 'child',
      geometry: const SocketGeometry(),
      transform: Matrix4.translation(Vector3(0, 1, 0)),
      parent: 1,
    ),
  ];
  final skeleton = ProjectSkeleton(
    joints: <int>[1, 2],
    inverseBindMatrices: <Matrix4>[Matrix4.identity(), Matrix4.identity()],
  );
  return (
    project: ModelProject(
      objects: objects,
      skeletons: <ProjectSkeleton>[skeleton],
    ),
    skeleton: skeleton,
  );
}

/// One key rotating [childId] a fifth of the way round its own X axis —
/// enough for a retarget to actually carry something across.
ProjectClip poseClip(int childId) => ProjectClip(
  name: 'pose',
  tracks: <ProjectTrack>[
    ProjectTrack(
      objectId: childId,
      track: AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.rotation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0, 1]),
        values: Float32List.fromList(<double>[
          0,
          0,
          0,
          1,
          ...(() {
            final q = Quaternion.axisAngle(Vector3(1, 0, 0), 0.4)..normalize();
            return <double>[q.x, q.y, q.z, q.w];
          })(),
        ]),
        componentCount: 4,
      ),
    ),
  ],
);

/// A single cube with two bones straddling its top and bottom halves — the
/// same fixture `flutter3d_model_core`'s own
/// `rig_job_retarget_and_bind_test.dart` builds for `BindWeightsJobRequest`
/// — and one enabled `MirrorModifier`, `withOneModifier`'s own, so
/// `bakeInBackground` has something to fold on the same object at once.
({ModelProject project, List<BoneSegment> bones}) cubeWithTwoBones() => (
  project: const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'cube',
      geometry: EditedGeometry(EditMesh.cuboid()),
      transform: Matrix4.identity(),
      modifiers: <ModifierSlot>[
        ModifierSlot(modifier: MirrorModifier(normal: Vector3(1, 0, 0))),
      ],
    ),
  ),
  bones: <BoneSegment>[
    BoneSegment(Vector3(0, -1, 0), Vector3(0, -0.5, 0), name: 'lower'),
    BoneSegment(Vector3(0, 0.5, 0), Vector3(0, 1, 0), name: 'upper'),
  ],
);

/// A cubit with a document open and a real scene behind it, drawn by the
/// software rasteriser so there is no GPU and no window anywhere.
({ModelerCubit cubit, ModelerStage stage}) opened({int count = 2}) =>
    openedWith(cubes(count));

({ModelerCubit cubit, ModelerStage stage}) openedWith(ModelProject project) {
  final it = cpuTestDevice(width: 8, height: 8);
  final history = ModelHistory(project);
  final stage = ModelerStage.fromProject(
    device: it.device,
    project: history.project,
  );
  final cubit = ModelerCubit()
    ..opened(
      history,
      renderer: Renderer.create(device: it.device),
      stage: stage,
    );
  return (cubit: cubit, stage: stage);
}

ModelerReady ready(ModelerCubit cubit) {
  expect(cubit.state, isA<ModelerReady>(), reason: '${cubit.state}');
  return cubit.state as ModelerReady;
}

void main() {
  group('opening', () {
    test('a document arrives ready, with its readiness already computed', () {
      final cubit = opened().cubit;
      final now = ready(cubit);

      expect(now.project.objects, hasLength(2));
      expect(now.mode, ModelerMode.object);
      expect(now.submode, MeshSubmode.vertex);
      // Mutation: leave `readiness` to a getter that computes on read. It works
      // and it is exactly what this replaced — a walk of every object and every
      // face, on every frame, for a value that changes when a command lands.
      expect(now.readiness.canExport, isTrue);
    });

    test('a failure is a sentence and not a half-open document', () {
      final cubit = ModelerCubit()..failed('no device');

      expect(cubit.state, isA<ModelerFailed>());
      expect((cubit.state as ModelerFailed).said, 'no device');
    });
  });

  group('a command', () {
    test('lands, moves the document and refreshes the readiness', () {
      final cubit = opened().cubit;
      final before = ready(cubit).project;

      final ok = cubit.ran(Rename(id: before.objects.first.id, to: 'torso'));

      expect(ok, isTrue);
      final now = ready(cubit);
      expect(now.project.objects.first.name, 'torso');
      expect(now.said, isNotNull);
    });

    test('the readiness follows the edit that changed the verdict', () {
      // One object with no faces at all: readiness calls that an error, because
      // some loaders refuse an empty mesh and the rest draw nothing.
      final cubit = openedWith(
        const ModelProject().added(
          (int id) => ModelObject(
            id: id,
            name: 'ghost',
            geometry: EditedGeometry(EditMesh.empty()),
            transform: Matrix4.identity(),
          ),
        ),
      ).cubit;
      expect(ready(cubit).readiness.canExport, isFalse);

      cubit
        ..ran(const SelectAll())
        ..ran(const DeleteObjects());

      // Mutation: skip `_readiness.of` after a command. The verdict stays
      // `false` and the bar goes on describing a model that is no longer there
      // — which is the same failure the other way round: a bar that says a
      // model is broken after the edit that fixed it.
      expect(ready(cubit).project.objects, isEmpty);
      expect(ready(cubit).readiness.canExport, isTrue);
    });

    test('a refusal says why and leaves the document alone', () {
      final cubit = opened().cubit;
      final before = ready(cubit).project;

      // An id no object has: the command refuses rather than throwing.
      final ok = cubit.ran(const Rename(id: 9999, to: 'ghost'));

      expect(ok, isFalse);
      final now = ready(cubit);
      expect(now.said, isNotNull);
      // Mutation: treat a refusal as a landing. The history grows a step that
      // did nothing, and ⌘Z then appears to do nothing too.
      expect(identical(now.project, before), isTrue);
      expect(now.history.undoSays, isNull);
    });

    test('the scene is brought to the project without being asked', () {
      final it = opened();
      final cubit = it.cubit;
      final sync = it.stage.sync!;

      cubit.ran(AddPrimitive(kind: AddPrimitive.primitiveKinds.first));

      // The seam this class exists for: before it, `SceneSync.apply` was a line
      // somebody had to remember beside every `history.run`, and the selection
      // commands forgot it. Mutation: drop the `apply` and the new object is in
      // the document and not on the screen.
      final added = ready(cubit).project.objects.last;
      expect(sync.nodeOf(added.id), isNotNull);
    });
  });

  group('undo and redo', () {
    test('undo takes the step back and says what it took', () {
      final cubit = opened().cubit;
      final id = ready(cubit).project.objects.first.id;
      cubit.ran(Rename(id: id, to: 'torso'));

      cubit.undo();

      final now = ready(cubit);
      expect(now.project[id]!.name, 'a');
      expect(now.said, contains('undone'));
    });

    test('undo with nothing to take back says so and changes nothing', () {
      final cubit = opened().cubit;
      final before = ready(cubit).project;

      cubit.undo();

      final now = ready(cubit);
      expect(now.said, 'nothing to undo');
      expect(identical(now.project, before), isTrue);
    });

    test('a transaction is one step, however many commands went into it', () {
      final cubit = opened().cubit;
      final now = ready(cubit);
      final ids = now.project.objects.map((ModelObject o) => o.id).toList();

      now.history.transaction(() {
        now.history.run(Rename(id: ids[0], to: 'x'));
        now.history.run(Rename(id: ids[1], to: 'y'));
      });
      cubit.documentMoved(said: 'renamed both');

      cubit.undo();

      // One ⌘Z, not two. Mutation: close the transaction per command and a
      // person who dragged nine objects presses undo nine times.
      final after = ready(cubit).project;
      expect(after[ids[0]]!.name, 'a');
      expect(after[ids[1]]!.name, 'b');
    });

    test('redo puts it back and the readiness follows', () {
      final cubit = opened().cubit;
      final id = ready(cubit).project.objects.first.id;
      cubit.ran(Rename(id: id, to: 'torso'));
      cubit.undo();

      cubit.redo();

      expect(ready(cubit).project[id]!.name, 'torso');
      expect(ready(cubit).said, 'redone');
    });
  });

  group("tut-16's own agent session", () {
    AgentToolCall call({bool did = true, String says = 'ok'}) => AgentToolCall(
      tool: 'ui.say',
      arguments: const <String, Object?>{'text': 'hi'},
      did: did,
      says: says,
      elapsed: const Duration(milliseconds: 12),
      at: DateTime(2026, 1, 1),
    );

    test('agentToolCalled appends to the feed', () {
      final cubit = opened().cubit;
      cubit.agentToolCalled(call());
      cubit.agentToolCalled(call(says: 'again'));

      expect(ready(cubit).agentCalls.map((AgentToolCall c) => c.says), <String>[
        'ok',
        'again',
      ]);
    });

    test('the feed is bounded, oldest call dropped first', () {
      final cubit = opened().cubit;
      for (var i = 0; i < 60; i++) {
        cubit.agentToolCalled(call(says: 'call $i'));
      }
      final calls = ready(cubit).agentCalls;
      // Mutation: let the feed grow without end. A long session's own state
      // would keep every call forever.
      expect(calls, hasLength(50));
      expect(calls.first.says, 'call 10');
      expect(calls.last.says, 'call 59');
    });

    test(
      'does not clobber an important sentence already on the status line',
      () {
        final cubit = opened().cubit;
        cubit.say('exported to model.glb', important: true);

        cubit.agentToolCalled(call());

        // Mutation: route this through the same `_synced` path `documentMoved`
        // uses with no `said` — that clears `said` unconditionally, which
        // would erase `ui.say`'s own important sentence the instant any other
        // tool call (this one) answers right after it.
        expect(ready(cubit).said, 'exported to model.glb');
      },
    );

    test('resyncs the scene, the same half of undo/redo that keeps the '
        'viewport honest', () {
      final cubit = opened().cubit;
      final now = ready(cubit);
      final id = now.project.objects.first.id;
      // An edit run straight against the shared history, the way
      // `ModelSession.run` (an agent's own document commands) does —
      // never through `cubit.ran`, so nothing here has told the cubit
      // to resync on its own account yet.
      now.history.run(
        Rename(id: id, to: 'agent-renamed'),
        author: StepAuthor.agent,
      );

      cubit.agentToolCalled(call());

      // Mutation: skip the resync and only append to the feed. The
      // rename above is already on `now.history`, but nothing would have
      // told the readiness (or the scene) to notice it landed.
      expect(ready(cubit).project[id]!.name, 'agent-renamed');
    });

    test('undoAgentSteps takes back the top step only when it is the '
        "agent's own", () {
      final cubit = opened().cubit;
      final id = ready(cubit).project.objects.first.id;
      ready(cubit).history.run(
        Rename(id: id, to: 'x'),
        author: StepAuthor.agent,
      );

      cubit.undoAgentSteps();

      expect(ready(cubit).project[id]!.name, 'a');
      expect(ready(cubit).said, contains('undone'));
    });

    test(
      "undoAgentSteps refuses a person's own top step, changing nothing",
      () {
        final cubit = opened().cubit;
        final id = ready(cubit).project.objects.first.id;
        cubit.ran(Rename(id: id, to: 'torso'));

        cubit.undoAgentSteps();

        expect(ready(cubit).project[id]!.name, 'torso');
        expect(ready(cubit).said, contains("agent"));
      },
    );

    test('undoAgentSteps with nothing to undo says so', () {
      final cubit = opened().cubit;

      cubit.undoAgentSteps();

      expect(ready(cubit).said, 'nothing to undo');
    });
  });

  group('the mode', () {
    test('changing it keeps the selection', () {
      final cubit = opened().cubit;
      final id = ready(cubit).project.objects.first.id;
      cubit.ran(const SelectAll());
      expect(ready(cubit).selection.objects, contains(id));

      cubit.mode(ModelerMode.mesh);

      // The small rudeness an editor is judged by: an object stays selected
      // when somebody drops into the mesh mode to work on it. Mutation: clear
      // the selection on a mode change and every trip into mesh mode starts by
      // picking the object again.
      final now = ready(cubit);
      expect(now.mode, ModelerMode.mesh);
      expect(now.selection.objects, contains(id));
    });

    test('the element level survives a trip through the object mode', () {
      final cubit = opened().cubit
        ..mode(ModelerMode.mesh)
        ..submode(MeshSubmode.face);

      cubit
        ..mode(ModelerMode.object)
        ..mode(ModelerMode.mesh);

      expect(ready(cubit).submode, MeshSubmode.face);
    });

    // `ui-40d`'s own row: `animationSubmode`'s own shape, mirroring the two
    // tests above.
    test('animationSubmode changes ModelerReady.animationSubmode', () {
      final cubit = opened().cubit;

      cubit.animationSubmode(AnimationSubmode.weights);

      expect(ready(cubit).animationSubmode, AnimationSubmode.weights);
    });

    test('the animation sub-mode survives a trip through the object mode', () {
      final cubit = opened().cubit
        ..mode(ModelerMode.animation)
        ..animationSubmode(AnimationSubmode.retarget);

      cubit
        ..mode(ModelerMode.object)
        ..mode(ModelerMode.animation);

      expect(ready(cubit).animationSubmode, AnimationSubmode.retarget);
    });

    test('setting the animation sub-mode it is already in emits nothing', () {
      final cubit = opened().cubit;
      final before = cubit.state;

      cubit.animationSubmode(AnimationSubmode.pose);

      expect(identical(cubit.state, before), isTrue);
    });

    test('setting the mode it is already in emits nothing', () {
      final cubit = opened().cubit;
      final before = cubit.state;

      cubit.mode(ModelerMode.object);

      // Mutation: emit regardless. Every press of a mode chip rebuilds the
      // whole shell for a change that did not happen.
      expect(identical(cubit.state, before), isTrue);
    });
  });

  group('playback', () {
    // `S2`'s own row: one emit per play/pause/clip/speed/loop change,
    // exactly `TimelinePlayback.onPlaybackChanged`'s own coarse half —
    // never the per-frame `ValueNotifier` `_ModelerScreenState` keeps
    // instead.
    test('playback changes ModelerReady.playback', () {
      final cubit = opened().cubit;

      cubit.playback(
        const Playback(status: PlaybackStatus.playing, clipIndex: 0),
      );

      expect(ready(cubit).playback.isPlaying, isTrue);
      expect(ready(cubit).playback.clipIndex, 0);
    });

    test('setting the same playback again emits nothing', () {
      final cubit = opened().cubit
        ..playback(const Playback(status: PlaybackStatus.paused));
      final before = cubit.state;

      cubit.playback(const Playback(status: PlaybackStatus.paused));

      // Mutation: emit regardless — a `Cubit` that emits an identical value
      // still rebuilds every `BlocBuilder` listening to it.
      expect(identical(cubit.state, before), isTrue);
    });

    test('does not clear `said`, unlike mode/submode/animationSubmode', () {
      final cubit = opened().cubit..say('something worth reading');

      cubit.playback(const Playback(status: PlaybackStatus.playing));

      expect(ready(cubit).said, 'something worth reading');
    });
  });

  group('what it says', () {
    test('a sentence from outside a command survives', () {
      final cubit = opened().cubit..say('wrote 40 bytes');

      expect(ready(cubit).said, 'wrote 40 bytes');
    });

    test('a command replaces it and a mode change clears it', () {
      final cubit = opened().cubit..say('wrote 40 bytes');
      cubit.ran(Rename(id: ready(cubit).project.objects.first.id, to: 'x'));
      expect(ready(cubit).said, isNot('wrote 40 bytes'));

      cubit.mode(ModelerMode.mesh);

      // A sentence about the last thing that happened stops being true when
      // something else happens, and a stale one is a bar that lies quietly.
      expect(ready(cubit).said, isNull);
    });

    test('a routine clear erases an ordinary sentence', () {
      // What every selection change already asked for, before `important`
      // existed: `_pickedElement`/`_picked`/`_boxed` all call `say(null)`
      // to fall the status line back to describing the selection, and a
      // sentence that was never marked important is exactly the case that
      // should still work that way.
      final cubit = opened().cubit..say('fetching model…');
      cubit.say(null);
      expect(ready(cubit).said, isNull);
    });

    test(
      'a routine clear leaves an important sentence for a person to read',
      () {
        // An intermediate UI review found this one missing: a save/open/export
        // outcome shown by `important: true` used to vanish behind the very
        // next selection change — a click, a box-select — before anyone had a
        // real chance to read it. `say(null)` is exactly what those selection
        // handlers call.
        final cubit = opened().cubit
          ..say('not saved: a mesh carries morph targets', important: true);
        cubit.say(null);
        expect(ready(cubit).said, 'not saved: a mesh carries morph targets');

        // Mutation: `if (now.saidIsImportant) return;` deleted from `say`'s
        // null branch. Run, and this line is the one that fails — the message
        // above is gone, replaced by nothing, the same silent loss the review
        // found.
      },
    );

    test(
      'a fresh sentence always replaces whatever was there, important or not',
      () {
        // Importance only changes what happens to a *clear*; a real new
        // sentence — the next save's own outcome, say — still overwrites the
        // old one immediately, important or not. Otherwise an error could
        // wedge the status line and refuse to update even when there is
        // something new and more relevant to say.
        final cubit = opened().cubit
          ..say('not saved: a mesh carries morph targets', important: true);
        cubit.say('wrote 40 bytes to model.f3dproj', important: true);
        expect(ready(cubit).said, 'wrote 40 bytes to model.f3dproj');
      },
    );

    test('importance itself does not linger past the sentence it named', () {
      // A routine sentence sent right after an important one must not
      // inherit the importance of what it replaced — otherwise the flag
      // would stick to the status line forever rather than to one message.
      final cubit = opened().cubit
        ..say('not saved: a mesh carries morph targets', important: true)
        ..say('fetching model…');
      cubit.say(null);
      expect(ready(cubit).said, isNull);
    });
  });

  group('baking a modifier stack in the background', () {
    test('lands: the object bakes, and jobs empties out afterwards', () async {
      final cubit = openedWith(withOneModifier()).cubit;
      final objectId = ready(cubit).project.objects.first.id;
      final versionBefore = ready(cubit).project.objects.first.version;

      final landed = await cubit.bakeInBackground(objectId, 0);

      expect(landed, isTrue);
      final object = ready(cubit).project[objectId]!;
      expect(object.version, greaterThan(versionBefore));
      // A mirrored cube's own baked mesh has more vertices than the plain
      // cube it started from — the modifier actually ran, not a no-op.
      expect(
        (object.geometry as EditedGeometry).mesh.vertexCount,
        greaterThan(EditMesh.cuboid().vertexCount),
      );
      expect(ready(cubit).jobs, isEmpty);
    });

    test('jobs carries the object while a bake is in flight', () async {
      final cubit = openedWith(withOneModifier()).cubit;
      final objectId = ready(cubit).project.objects.first.id;

      final future = cubit.bakeInBackground(objectId, 0);
      // The one chunk has been started (a real isolate spawned) but not
      // necessarily finished — this is the same instant `job_runner_test.dart`
      // itself reads betweeen `run()` starting and its first `await` landing.
      expect(ready(cubit).jobs, <ActiveJob>[
        ActiveJob(key: JobKey.object(objectId), progress: 0.0),
      ]);

      await future;
      expect(ready(cubit).jobs, isEmpty);
    });

    test('cancelling before the isolate call starts leaves the object '
        'untouched', () async {
      final cubit = openedWith(withOneModifier()).cubit;
      final objectId = ready(cubit).project.objects.first.id;
      final versionBefore = ready(cubit).project.objects.first.version;

      // Mutation: call `cancelBake` after awaiting the bake instead of
      // synchronously alongside it. `Job.run`'s own first thing is checking
      // `_cancelRequested` before its one chunk starts — cancelling in the
      // same synchronous stretch that starts the future is what actually
      // exercises that check; cancelling after `await`ing the result cannot,
      // since by then the one chunk has already run to completion.
      final future = cubit.bakeInBackground(objectId, 0);
      cubit.cancelBake(objectId);
      final landed = await future;

      expect(landed, isFalse);
      expect(ready(cubit).project[objectId]!.version, versionBefore);
      expect(ready(cubit).jobs, isEmpty);
    });

    test(
      'a second bake for the same object while one runs is refused',
      () async {
        final cubit = openedWith(withOneModifier()).cubit;
        final objectId = ready(cubit).project.objects.first.id;

        final first = cubit.bakeInBackground(objectId, 0);
        final second = await cubit.bakeInBackground(objectId, 0);
        expect(second, isFalse);

        await first;
      },
    );

    test('an object with no modifier stack has nothing to bake', () async {
      final cubit = opened().cubit;
      final objectId = ready(cubit).project.objects.first.id;

      final landed = await cubit.bakeInBackground(objectId, 0);
      expect(landed, isFalse);
    });
  });

  group('retargeting a clip in the background', () {
    RetargetClipJobRequest requestFor(ModelProject project) =>
        retargetClipJobRequestFor(
          sourceProject: project,
          sourceSkeletonIndex: 0,
          sourceClipIndex: 0,
          targetProject: project,
          targetSkeletonIndex: 0,
          boneMap: BoneMap(<String, String>{'root': 'root', 'child': 'child'}),
          lockFeet: false,
        )!;

    test(
      'lands: the clip is appended, and jobs empties out afterwards',
      () async {
        final rig = twoJointRig();
        final project = rig.project.copyWith(clips: <ProjectClip>[poseClip(2)]);
        final cubit = openedWith(project).cubit;

        final applied = await cubit.retargetInBackground(requestFor(project));

        expect(applied, isNotNull);
        // An append: `ApplyClipResult.clipIndex` names the clip it replaces,
        // and this replaced none.
        expect(applied!.clipIndex, isNull);
        expect(ready(cubit).project.clips, hasLength(2));
        expect(ready(cubit).jobs, isEmpty);
      },
    );

    test('jobs carries the clip key while a retarget is in flight', () async {
      final rig = twoJointRig();
      final project = rig.project.copyWith(clips: <ProjectClip>[poseClip(2)]);
      final cubit = openedWith(project).cubit;

      final future = cubit.retargetInBackground(requestFor(project));
      // The same instant `bakeInBackground`'s own analogous test reads,
      // between `run()` starting and its first `await` landing — the one
      // clip already on the project keys the append that will land after it.
      expect(ready(cubit).jobs, <ActiveJob>[
        ActiveJob(key: JobKey.clip(1), progress: 0.0),
      ]);

      await future;
      expect(ready(cubit).jobs, isEmpty);
    });

    test('cancelling before it starts leaves the document untouched', () async {
      final rig = twoJointRig();
      final project = rig.project.copyWith(clips: <ProjectClip>[poseClip(2)]);
      final cubit = openedWith(project).cubit;

      // See `bakeInBackground`'s own analogous test for why cancelling has
      // to happen in the same synchronous stretch that starts the future.
      final future = cubit.retargetInBackground(requestFor(project));
      cubit.cancelJob(JobKey.clip(1));
      final applied = await future;

      expect(applied, isNull);
      expect(ready(cubit).project.clips, hasLength(1));
      expect(ready(cubit).jobs, isEmpty);
    });

    test('a second retarget onto the same append slot while one runs is '
        'refused', () async {
      final rig = twoJointRig();
      final project = rig.project.copyWith(clips: <ProjectClip>[poseClip(2)]);
      final cubit = openedWith(project).cubit;

      final first = cubit.retargetInBackground(requestFor(project));
      final second = await cubit.retargetInBackground(requestFor(project));
      expect(second, isNull);

      await first;
    });

    test('matches RetargetClipJobRequest.run applied through ApplyClipResult '
        'directly, byte for byte', () async {
      final rig = twoJointRig();
      final project = rig.project.copyWith(clips: <ProjectClip>[poseClip(2)]);
      final request = requestFor(project);

      final direct = await request.run();

      final cubit = openedWith(project).cubit;
      final applied = await cubit.retargetInBackground(request);

      expect(applied, isNotNull);
      final throughCubit = ready(cubit).project.clips.last;
      expect(throughCubit.tracks, hasLength(direct.tracks.length));
      for (var i = 0; i < direct.tracks.length; i++) {
        expect(throughCubit.tracks[i].objectId, direct.tracks[i].objectId);
        expect(
          throughCubit.tracks[i].track.times,
          direct.tracks[i].track.times,
        );
        expect(
          throughCubit.tracks[i].track.values,
          direct.tracks[i].track.values,
        );
      }
    });
  });

  group('binding weights in the background', () {
    test(
      'lands: the object is bound, and jobs empties out afterwards',
      () async {
        final rig = cubeWithTwoBones();
        final cubit = openedWith(rig.project).cubit;
        final objectId = ready(cubit).project.objects.first.id;
        final versionBefore = ready(cubit).project.objects.first.version;
        final request = bindWeightsJobRequestFor(
          project: rig.project,
          objectId: objectId,
          bones: rig.bones,
        )!;

        final landed = await cubit.bindWeightsInBackground(request);

        expect(landed, isTrue);
        expect(
          ready(cubit).project[objectId]!.version,
          greaterThan(versionBefore),
        );
        expect(ready(cubit).jobs, isEmpty);
      },
    );

    test('jobs carries the object while a bind-weights is in flight', () async {
      final rig = cubeWithTwoBones();
      final cubit = openedWith(rig.project).cubit;
      final objectId = ready(cubit).project.objects.first.id;
      final request = bindWeightsJobRequestFor(
        project: rig.project,
        objectId: objectId,
        bones: rig.bones,
      )!;

      final future = cubit.bindWeightsInBackground(request);
      expect(ready(cubit).jobs, <ActiveJob>[
        ActiveJob(key: JobKey.rig(objectId), progress: 0.0),
      ]);

      await future;
      expect(ready(cubit).jobs, isEmpty);
    });

    test('cancelling before it starts leaves the object untouched', () async {
      final rig = cubeWithTwoBones();
      final cubit = openedWith(rig.project).cubit;
      final objectId = ready(cubit).project.objects.first.id;
      final versionBefore = ready(cubit).project.objects.first.version;
      final request = bindWeightsJobRequestFor(
        project: rig.project,
        objectId: objectId,
        bones: rig.bones,
      )!;

      final future = cubit.bindWeightsInBackground(request);
      cubit.cancelJob(JobKey.rig(objectId));
      final landed = await future;

      expect(landed, isFalse);
      expect(ready(cubit).project[objectId]!.version, versionBefore);
      expect(ready(cubit).jobs, isEmpty);
    });

    test('a bake and a bind-weights on the same object are tracked as two '
        'separate jobs, not refused as one colliding with the other', () async {
      final rig = cubeWithTwoBones();
      final cubit = openedWith(rig.project).cubit;
      final objectId = ready(cubit).project.objects.first.id;
      final request = bindWeightsJobRequestFor(
        project: rig.project,
        objectId: objectId,
        bones: rig.bones,
      )!;

      // Fired without awaiting either, the same synchronous stretch
      // `bakeInBackground`'s own "second bake refused" test relies on —
      // the old `Map<int, Job<...>>` this replaced would have keyed both
      // under the same object id and refused the second outright.
      final bake = cubit.bakeInBackground(objectId, 0);
      final bind = cubit.bindWeightsInBackground(request);
      expect(
        ready(cubit).jobs,
        unorderedEquals(<ActiveJob>[
          ActiveJob(key: JobKey.object(objectId), progress: 0.0),
          ActiveJob(key: JobKey.rig(objectId), progress: 0.0),
        ]),
      );

      await bake;
      await bind;
      expect(ready(cubit).jobs, isEmpty);
    });

    test('matches BindWeightsJobRequest.run applied through ApplyJobResult '
        'directly, byte for byte', () async {
      final rig = cubeWithTwoBones();
      final objectId = rig.project.objects.first.id;
      final request = bindWeightsJobRequestFor(
        project: rig.project,
        objectId: objectId,
        bones: rig.bones,
      )!;

      final direct = await request.run();
      final directHistory = ModelHistory(rig.project);
      expect(directHistory.run(ApplyJobResult.of(direct)), isNull);

      final cubit = openedWith(rig.project).cubit;
      final landed = await cubit.bindWeightsInBackground(request);

      expect(landed, isTrue);
      expect(
        (ready(cubit).project[objectId]!.geometry as EditedGeometry).mesh
            .toBytes(),
        equals(
          (directHistory.project[objectId]!.geometry as EditedGeometry).mesh
              .toBytes(),
        ),
      );
    });
  });

  group('nothing happens before a document', () {
    test('every verb is a no-op while opening', () {
      final cubit = ModelerCubit();

      cubit
        ..ran(const Rename(id: 1, to: 'x'))
        ..undo()
        ..redo()
        ..mode(ModelerMode.mesh)
        ..say('hello');

      // Mutation: reach for `state as ModelerReady` without checking. Every one
      // of these throws before the device is up, which is the window between
      // `runApp` and the first frame.
      expect(cubit.state, isA<ModelerOpening>());
    });
  });
}
