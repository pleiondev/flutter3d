/// What runs on each page of the `backends` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/backends/backend_cpu.dart';
import 'package:flutter3d_showcase/pages/backends/backend_impeller.dart';
import 'package:flutter3d_showcase/pages/backends/backend_matrix.dart';
import 'package:flutter3d_showcase/pages/backends/backend_webgl.dart';
import 'package:flutter3d_showcase/pages/backends/backend_webgpu.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// The `backends` category's pages, by the page id in the route, each with the
/// builder the host calls when the page opens.
final Map<String, DemoBuilder> backendsDemos = <String, DemoBuilder>{
  'backend-impeller': BackendImpellerDemo.new,
  'backend-webgl': BackendWebglDemo.new,
  'backend-webgpu': BackendWebgpuDemo.new,
  'backend-cpu': BackendCpuDemo.new,
  'backend-matrix': BackendMatrixDemo.new,
};
