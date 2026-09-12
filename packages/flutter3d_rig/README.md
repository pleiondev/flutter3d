# flutter3d_rig

Bone-name mapping and rest-relative animation retargeting between two
skeletons, with a two-bone-IK foot lock.

**No Flutter and no renderer in it.** `BoneMap`/`autoMap` and
`retargetClip` work directly on [`flutter3d_model_core`](../flutter3d_model_core)'s
own `ProjectSkeleton`/`ProjectClip` — a project-level document, not a
runtime pose. Playing a retargeted clip is somebody else's problem.

```dart
final boneMap = autoMap(sourceNames, targetNames);
final retargeted = retargetClip(
  sourceClip: walkCycle,
  sourceProject: sourceProject,
  sourceSkeleton: sourceSkeleton,
  targetProject: targetProject,
  targetSkeleton: targetSkeleton,
  boneMap: boneMap,
);
```

## Why rest-relative

A keyframe copied straight from one skeleton to another only looks right
when both share the same rest pose and bone lengths. Expressing each key
relative to its own bone's rest rotation first, then re-applying it on top
of the *target* bone's own rest rotation, is what makes retargeting onto
the same skeleton an exact identity and retargeting onto a differently
proportioned one still land close to correct without per-bone tuning.

## Foot lock

Scaling the root/hip translation track by the ratio of the two skeletons'
own standing heights gets a differently-sized rig roughly right, but a leg
of a different proportion does not, by itself, guarantee the foot still
meets the ground. `retargetClip`'s own `lockFeet` (on by default) corrects
each keyframe's hip/knee rotation with a two-bone IK solve so the ankle
stays within tolerance of the ground plane — reimplemented on plain
positions and rotations rather than reusing `packages/flutter3d`'s own
`TwoBoneIk`, which solves against a runtime `Pose` this package has no
other reason to depend on.
