/// Every capability the showcase has a page for, in the order the tree shows
/// them.
///
/// **Written once and then left alone.** The pages of a category are added to
/// that category's own file under `lib/catalog/`; this file only joins the
/// twelve, so adding a page never edits it and a dozen people adding pages
/// never conflict here.
library;

import 'package:flutter3d_showcase/catalog/animation.dart';
import 'package:flutter3d_showcase/catalog/backends.dart';
import 'package:flutter3d_showcase/catalog/environment.dart';
import 'package:flutter3d_showcase/catalog/formats.dart';
import 'package:flutter3d_showcase/catalog/physics_particles.dart';
import 'package:flutter3d_showcase/catalog/post.dart';
import 'package:flutter3d_showcase/catalog/scene.dart';
import 'package:flutter3d_showcase/catalog/shading.dart';
import 'package:flutter3d_showcase/catalog/shadows.dart';
import 'package:flutter3d_showcase/catalog/sim_audio_xr.dart';
import 'package:flutter3d_showcase/catalog/view_input.dart';
import 'package:flutter3d_showcase/catalog/widgets_misc.dart';
import 'package:flutter3d_showcase/src/catalog/feature.dart';

const List<Feature> kCatalog = <Feature>[
  ...shadingFeatures,
  ...environmentFeatures,
  ...shadowsFeatures,
  ...postFeatures,
  ...sceneFeatures,
  ...animationFeatures,
  ...viewInputFeatures,
  ...formatsFeatures,
  ...backendsFeatures,
  ...physicsParticlesFeatures,
  ...simAudioXrFeatures,
  ...widgetsMiscFeatures,
];

/// The feature with [id], or null.
Feature? featureNamed(String id) {
  for (final Feature feature in kCatalog) {
    if (feature.id == id) return feature;
  }
  return null;
}

/// The features of [category], in catalog order.
List<Feature> featuresOf(Category category) => <Feature>[
  for (final Feature feature in kCatalog)
    if (feature.category == category) feature,
];
