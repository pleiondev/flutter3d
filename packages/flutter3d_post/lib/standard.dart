/// The `standard` preset of post-processing: all six addon families, which
/// is every effect the frame drew before the effects were addons.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   registries: <PluginRegistry>[renderer.renderSteps],
///   plugins: standardAddons,
/// );
/// ```
///
/// **It changes nothing about the frame, and that is what it promises.** An
/// addon provides a step the kernel already draws; while every provider is
/// on, the renderer draws exactly what it drew with no addon installed, pass
/// for pass. What the preset buys is the switches: from here
/// `loop.plugins.disable(const BloomAddon().id)` takes the bloom out of every
/// frame, and enabling it puts it back.
///
/// **A renderer without the preset keeps today's defaults too.** In 1.0 a
/// step nobody provides is drawn as its settings say, so an application that
/// never heard of addons sees no change. See `RendererSteps.provide`.
library;

import 'package:flutter3d_core/flutter3d_core.dart' show RenderStepAddon;
import 'package:flutter3d_post/atmosphere.dart';
import 'package:flutter3d_post/light.dart';
import 'package:flutter3d_post/motion.dart';
import 'package:flutter3d_post/reflections.dart';
import 'package:flutter3d_post/shading.dart';
import 'package:flutter3d_post/style.dart';

export 'package:flutter3d_post/atmosphere.dart';
export 'package:flutter3d_post/light.dart';
export 'package:flutter3d_post/motion.dart';
export 'package:flutter3d_post/reflections.dart';
export 'package:flutter3d_post/shading.dart';
export 'package:flutter3d_post/style.dart';

/// Every effect of the six families, in the order the frame meets them:
/// the captures, the scene's air, the light and shadow on the lit picture,
/// the lens, the sensor, and the looks laid over the end.
///
/// The order is the plugins' install order and their rank among
/// registrations; the frame itself is ordered by the anchors and is the same
/// in any order these are installed.
const List<RenderStepAddon> standardAddons = <RenderStepAddon>[
  ...reflectionsAddons,
  ...atmosphereAddons,
  ...shadingAddons,
  ...motionAddons,
  ...lightAddons,
  ...styleAddons,
];
