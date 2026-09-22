/// What runs on each page of the `shadows` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/shadows/cascaded_shadows.dart';
import 'package:flutter3d_showcase/pages/shadows/contact_shadows.dart';
import 'package:flutter3d_showcase/pages/shadows/masked_shadow_casters.dart';
import 'package:flutter3d_showcase/pages/shadows/point_light_shadows.dart';
import 'package:flutter3d_showcase/pages/shadows/shadow_settings.dart';
import 'package:flutter3d_showcase/pages/shadows/soft_shadows.dart';
import 'package:flutter3d_showcase/pages/shadows/static_shadow_cache.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> shadowsDemos = <String, DemoBuilder>{
  'shadow-settings': ShadowSettingsDemo.new,
  'cascaded-shadows': CascadedShadowsDemo.new,
  'point-light-shadows': PointLightShadowsDemo.new,
  'soft-shadows': SoftShadowsDemo.new,
  'contact-shadows': ContactShadowsDemo.new,
  'static-shadow-cache': StaticShadowCacheDemo.new,
  'masked-shadow-casters': MaskedShadowCastersDemo.new,
};
