/// What runs on each page of the `shadows` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/shadows/cascaded_shadows.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> shadowsDemos = <String, DemoBuilder>{
  'cascaded-shadows': CascadedShadowsDemo.new,
};
