/// What runs on each page of the `formats` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/formats/export_validate.dart';
import 'package:flutter3d_showcase/pages/formats/gltf_cameras_lights.dart';
import 'package:flutter3d_showcase/pages/formats/gltf_load.dart';
import 'package:flutter3d_showcase/pages/formats/gltf_write.dart';
import 'package:flutter3d_showcase/pages/formats/obj.dart';
import 'package:flutter3d_showcase/pages/formats/stl.dart';
import 'package:flutter3d_showcase/pages/formats/f3d.dart';
import 'package:flutter3d_showcase/pages/formats/draco.dart';
import 'package:flutter3d_showcase/pages/formats/ktx2.dart';
import 'package:flutter3d_showcase/pages/formats/texture_compression.dart';
import 'package:flutter3d_showcase/pages/formats/usdz.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final Map<String, DemoBuilder> formatsDemos = <String, DemoBuilder>{
  'gltf-load': GltfLoadDemo.new,
  'gltf-cameras-lights': GltfCamerasLightsDemo.new,
  'gltf-write': GltfWriteDemo.new,
  'export-validate': ExportValidateDemo.new,
  'obj': ObjDemo.new,
  'stl': StlDemo.new,
  'usdz': UsdzDemo.new,
  'f3d': F3dDemo.new,
  'ktx2': Ktx2Demo.new,
  'texture-compression': TextureCompressionDemo.new,
  'draco': DracoDemo.new,
};
