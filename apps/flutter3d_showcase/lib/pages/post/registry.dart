/// What runs on each page of the `post` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/post/bloom.dart';
import 'package:flutter3d_showcase/pages/post/disabled_passes.dart';
import 'package:flutter3d_showcase/pages/post/render_post.dart';
import 'package:flutter3d_showcase/pages/post/tone_mapping.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> postDemos = <String, DemoBuilder>{
  'bloom': BloomDemo.new,
  'tone-mapping': ToneMappingDemo.new,
  'render-post': RenderPostDemo.new,
  'disabled-passes': DisabledPassesDemo.new,
};
