/// Case 5 — "Borrowing a walk: retarget a clip": what both
/// `tool/make_case5_fixtures.dart` (which writes the fixtures beside this
/// file) and `tutorial_scenarios_test.dart` (which drives it against a live
/// [ModelSession]) need to agree on.
///
/// **Starts from case 4's own saved project, read the same way a person
/// reopening it would.** [case5StartingProject] reads the committed
/// `case4.f3dproj` fixture through [readProject] — the exact bytes
/// `ModelSession.open` itself would read — rather than re-running case 4's
/// own `runCase4Scenario` a second time to rebuild an equivalent project by
/// hand. This is [case3_scenario.dart]'s own "case 3 starts from case 2's
/// own saved project" shape, one case later: the plan's own row says
/// "retargeted onto case 4's character," and this is that file.
///
/// **The source clip is `RiggedFigure.glb`, not `BoxAnimated.glb`.**
/// [BoxAnimated.glb] carries no glTF skin at all (checked once by hand while
/// writing this file: `doc.skins.isEmpty`) — it only moves two plain nodes,
/// nothing a bone map has anything to name. `RiggedFigure.glb` carries a
/// real nineteen-joint skin and one clip animating all nineteen — a real
/// walk-in-place cycle a bone map can actually retarget onto a humanoid
/// rig, which is why [case5RetargetSource] reads it rather than the other
/// file the plan names as a candidate.
///
/// **`looseAutoMap` maps this file correctly — `tut-13`, closed.**
/// `RiggedFigure.glb`'s own joint names (`torso_joint_1`, `arm_joint_L_2`,
/// `leg_joint_R_3`, and so on) follow neither Mixamo's `mixamorig:`
/// convention nor 3ds Max Biped's `Bip01_` one, and their generic body words
/// (`torso`/`arm`/`leg`/`neck`) are in neither of `looseAutoMap`'s own
/// synonym tables at all — disambiguated only by a trailing numeric chain
/// index. `looseAutoMap` now reads that shape too, its own third matching
/// path (`_chainCanonicalOf` in `bone_map.dart`, `packages/flutter3d_rig`):
/// a body-part word plus a chain index, read by chain **position** —
/// `arm_joint_L_1`/`_2`/`_3` land on `leftShoulder`/`leftElbow`/`leftWrist`
/// in that order — rather than by any word lookup. [runCase5Scenario]
/// repeats the check directly: auto-map this file's own nineteen joints
/// against `RigTemplate.humanoid`'s seventeen and get back
/// [case5ExpectedAutoMap] byte-for-byte, the seventeen pairs a person would
/// once have typed in by hand plus the two toe-tip bones
/// (`leg_joint_L_5`/`leg_joint_R_5`) correctly left unmapped — neither
/// `RigTemplate.humanoid` nor this synonym table has anywhere for a toe to
/// land. `doc/modeler-tutorial-gaps.md`'s own `tut-13` row is closed.
///
/// **`lockFeet: true` (the default) — fixed, `tut-12`.** Calling
/// [RetargetClipJobRequest.run] with `lockFeet: true` against this exact
/// pair of rigs used to throw a `RangeError` inside `retarget.dart`'s own
/// `_lockFeet`. The cause: `_lockFeet`'s own `tracksByNodeId` was a
/// `Map<int, RigTrack>`, one entry per target node id, but
/// `RiggedFigure.glb`'s own clip animates *every* joint's translation,
/// rotation **and** scale, not only the root's — so building that map for
/// the hips joint (which carries all three after retargeting) overwrote the
/// retargeted *rotation* track with the *scale* one, and `_lockFeet`'s own
/// per-key indexing math then read that three-floats-per-key buffer as if
/// it held four-floats-per-key quaternions, running past its own end.
/// `_lockFeet` now keys its lookup by node **and** path, so a joint's three
/// retargeted tracks all survive — this case takes screen 14's own "Lock
/// feet" toggle at its documented default rather than working around it.
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:flutter3d_rig/flutter3d_rig.dart' show BoneMap, looseAutoMap;

/// Case 4's own finished character — the exact project
/// `test/fixtures/tutorial/case4.f3dproj` holds, read back the way opening
/// it in the app (or `ModelSession.open`) would.
Future<ModelProject> case5StartingProject({
  String case4ProjectPath = 'test/fixtures/tutorial/case4.f3dproj',
}) async {
  final bytes = File(case4ProjectPath).readAsBytesSync();
  final ModelProject started = switch (readProject(bytes)) {
    ProjectOpened(:final project) => project,
    ProjectRefused(:final because) => throw StateError(
      'case4.f3dproj would not open: $because',
    ),
  };
  if (started.skeletons.length != 1) {
    throw StateError(
      "expected case 4's own project to carry exactly one skeleton, got "
      '${started.skeletons.length}',
    );
  }
  return started;
}

/// `RiggedFigure.glb`, read as a [RetargetSource] the way screen 14's own
/// `retarget.import` action does — never merged into a project, only read
/// from for [retargetClip]. See this file's own library comment for why
/// this file over `BoxAnimated.glb`.
Future<RetargetSource> case5RetargetSource({
  String glbPath = '../flutter3d_samples/assets/RiggedFigure.glb',
}) async {
  final bytes = File(glbPath).readAsBytesSync();
  final ModelDocument document = await GltfLoader().load(bytes);
  final RetargetSource source = RetargetSource.fromDocument(
    'RiggedFigure.glb',
    document,
  );
  if (source.warning != null) {
    throw StateError(
      "expected RiggedFigure.glb's own real glTF skin to read with no "
      'warning at all, got: ${source.warning}',
    );
  }
  if (source.skeleton.joints.length != 19) {
    throw StateError(
      "expected RiggedFigure.glb's own skin to carry nineteen joints, got "
      '${source.skeleton.joints.length}',
    );
  }
  if (source.clips.length != 1) {
    throw StateError(
      'expected RiggedFigure.glb to carry exactly one clip, got '
      '${source.clips.length}',
    );
  }
  return source;
}

/// `RiggedFigure.glb`'s own nineteen joint names, onto `RigTemplate
/// .humanoid`'s seventeen — exactly what `looseAutoMap` itself now returns
/// (`tut-13`, this file's own library comment), checked directly by
/// [runCase5Scenario] rather than assumed. The two names with no entry here,
/// `leg_joint_L_5`/`leg_joint_R_5`, are the file's own toe-tip bones —
/// `RigTemplate.humanoid` has no toe joint for either to land on, so
/// [retargetClip] simply drops their tracks, the documented behaviour for
/// "a bone the source has and the target does not."
const Map<String, String> case5ExpectedAutoMap = <String, String>{
  'torso_joint_1': 'hips',
  'torso_joint_2': 'spine',
  'torso_joint_3': 'chest',
  'neck_joint_1': 'neck',
  'neck_joint_2': 'head',
  'arm_joint_L_1': 'leftShoulder',
  'arm_joint_L_2': 'leftElbow',
  'arm_joint_L_3': 'leftWrist',
  'arm_joint_R_1': 'rightShoulder',
  'arm_joint_R_2': 'rightElbow',
  'arm_joint_R_3': 'rightWrist',
  'leg_joint_L_1': 'leftHip',
  'leg_joint_L_2': 'leftKnee',
  'leg_joint_L_3': 'leftAnkle',
  'leg_joint_R_1': 'rightHip',
  'leg_joint_R_2': 'rightKnee',
  'leg_joint_R_3': 'rightAnkle',
};

/// Every step case 5's own page (`cloud/server/content/learn/modeler/
/// 05-borrowing-a-walk.md`) walks through, run against [session] once it
/// holds [case5StartingProject]'s result.
///
/// **Async, the same shape case 4's own scenario needs** — this one awaits
/// [RetargetClipJobRequest.run] partway through, the same `Future` a live
/// app would hand to `ModelerCubit.retargetInBackground` instead (see this
/// file's own library comment for why this case calls the request directly
/// rather than through that app-layer wrapper).
Future<void> runCase5Scenario(ModelSession session) async {
  void must(Answer answer, String step) {
    if (!answer.did) throw StateError('$step refused: ${answer.says}');
  }

  final RetargetSource source = await case5RetargetSource();
  final ProjectSkeleton targetSkeleton = session.project.skeletons.single;

  final List<String> sourceNames = <String>[
    for (final int id in source.skeleton.joints) source.project[id]!.name,
  ];
  final List<String> targetNames = <String>[
    for (final int id in targetSkeleton.joints) session.project[id]!.name,
  ];

  // 1. Auto-map first, the way screen 14's own "Auto-map" button runs
  // `looseAutoMap` over both skeletons' own joint names before anything
  // else — this file's own library comment (`tut-13`, closed) explains why
  // this exact pair of rigs now maps cleanly.
  final BoneMap autoMapped = looseAutoMap(sourceNames, targetNames);
  for (final MapEntry<String, String> expected
      in case5ExpectedAutoMap.entries) {
    if (autoMapped.targetOf(expected.key) != expected.value) {
      throw StateError(
        'expected looseAutoMap to map "${expected.key}" onto '
        '"${expected.value}" (tut-13) — got '
        '"${autoMapped.targetOf(expected.key)}" instead; if '
        "looseAutoMap's own chain-index reading changed since this file "
        'was written, update this case and its gap-journal row rather '
        'than only this assertion',
      );
    }
  }
  if (autoMapped.length != case5ExpectedAutoMap.length) {
    throw StateError(
      'expected looseAutoMap to map exactly '
      '${case5ExpectedAutoMap.length} joints for this pair of rigs '
      '(tut-13) — got ${autoMapped.length} instead',
    );
  }

  // 2. The auto-mapped result, used directly — no hand correction needed
  // any more, now that `tut-13` is closed.
  final BoneMap boneMap = autoMapped;

  // 3. The real retarget, run directly rather than through `ModelerCubit
  // .retargetInBackground` (this file's own library comment) — `lockFeet`
  // left at its own default (`true`), now that `tut-12` is fixed.
  final RetargetClipJobRequest request = RetargetClipJobRequest(
    sourceProject: source.project,
    sourceSkeleton: source.skeleton,
    sourceClip: source.clips.single,
    targetProject: session.project,
    targetSkeleton: targetSkeleton,
    boneMap: boneMap,
  );
  final ProjectClip retargeted = await request.run();

  // 4. Landed through `ApplyClipResult`, `clipIndex: null` — always append,
  // the same "never replaces a clip already on the target" rule screen
  // 14's own `retarget.apply` keeps.
  must(
    session.run(ApplyClipResult(clip: retargeted, clipIndex: null)),
    'applyClipResult',
  );
  final int newClipIndex = session.project.clips.length - 1;

  // 5. Root motion, "In code": `ExtractRootMotion` on the target's own hips
  // joint — `RetargetRootMotion.inCode`'s exact command, the same one
  // `_applyRetarget`/`_setRetargetRootMotion` in `retarget_wiring.dart` run
  // for that switch position.
  must(
    session.run(
      ExtractRootMotion(
        clipIndex: newClipIndex,
        rootJoint: targetSkeleton.joints.first,
      ),
    ),
    'extractRootMotion',
  );
}
