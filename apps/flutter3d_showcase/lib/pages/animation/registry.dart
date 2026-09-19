/// What runs on each page of the `animation` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/animation/additive_blend.dart';
import 'package:flutter3d_showcase/pages/animation/animation_layers.dart';
import 'package:flutter3d_showcase/pages/animation/clip_playback.dart';
import 'package:flutter3d_showcase/pages/animation/fabrik_ik.dart';
import 'package:flutter3d_showcase/pages/animation/instanced_morphs.dart';
import 'package:flutter3d_showcase/pages/animation/interpolation.dart';
import 'package:flutter3d_showcase/pages/animation/morph_targets.dart';
import 'package:flutter3d_showcase/pages/animation/pose_sampling.dart';
import 'package:flutter3d_showcase/pages/animation/root_motion.dart';
import 'package:flutter3d_showcase/pages/animation/skeleton_debug.dart';
import 'package:flutter3d_showcase/pages/animation/skinning.dart';
import 'package:flutter3d_showcase/pages/animation/two_bone_ik.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> animationDemos = <String, DemoBuilder>{
  'skinning': SkinningDemo.new,
  'clip-playback': ClipPlaybackDemo.new,
  'interpolation': InterpolationDemo.new,
  'morph-targets': MorphTargetsDemo.new,
  'instanced-morphs': InstancedMorphsDemo.new,
  'animation-layers': AnimationLayersDemo.new,
  'additive-blend': AdditiveBlendDemo.new,
  'root-motion': RootMotionDemo.new,
  'two-bone-ik': TwoBoneIkDemo.new,
  'fabrik-ik': FabrikIkDemo.new,
  'pose-sampling': PoseSamplingDemo.new,
  'skeleton-debug': SkeletonDebugDemo.new,
};
