/// What runs on each page, by page id.
///
/// The counterpart of `catalog.dart` for the half that needs Flutter: the
/// catalog says what a page is, this says how to build it. Joined here and
/// written once, like the catalog.
library;

import 'package:flutter3d_showcase/pages/animation/registry.dart';
import 'package:flutter3d_showcase/pages/backends/registry.dart';
import 'package:flutter3d_showcase/pages/environment/registry.dart';
import 'package:flutter3d_showcase/pages/formats/registry.dart';
import 'package:flutter3d_showcase/pages/physics_particles/registry.dart';
import 'package:flutter3d_showcase/pages/post/registry.dart';
import 'package:flutter3d_showcase/pages/scene/registry.dart';
import 'package:flutter3d_showcase/pages/shading/registry.dart';
import 'package:flutter3d_showcase/pages/shadows/registry.dart';
import 'package:flutter3d_showcase/pages/sim_audio_xr/registry.dart';
import 'package:flutter3d_showcase/pages/view_input/registry.dart';
import 'package:flutter3d_showcase/pages/widgets_misc/registry.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> kDemos = <String, DemoBuilder>{
  ...animationDemos,
  ...backendsDemos,
  ...viewInputDemos,
  ...environmentDemos,
  ...formatsDemos,
  ...physicsParticlesDemos,
  ...postDemos,
  ...sceneDemos,
  ...shadingDemos,
  ...shadowsDemos,
  ...simAudioXrDemos,
  ...widgetsMiscDemos,
};
