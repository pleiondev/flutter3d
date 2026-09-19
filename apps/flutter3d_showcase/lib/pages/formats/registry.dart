/// What runs on each page of the `formats` category.
///
/// A page id maps to a builder that makes a fresh demo every time the page is
/// opened, so a demo's own state never survives a visit.
library;

import 'package:flutter3d_showcase/pages/formats/custom_decoder.dart';
import 'package:flutter3d_showcase/pages/formats/draco.dart';
import 'package:flutter3d_showcase/pages/formats/export_validate.dart';
import 'package:flutter3d_showcase/pages/formats/f3d.dart';
import 'package:flutter3d_showcase/pages/formats/fbx_refusal.dart';
import 'package:flutter3d_showcase/pages/formats/gltf_cameras_lights.dart';
import 'package:flutter3d_showcase/pages/formats/gltf_load.dart';
import 'package:flutter3d_showcase/pages/formats/gltf_write.dart';
import 'package:flutter3d_showcase/pages/formats/image_decode.dart';
import 'package:flutter3d_showcase/pages/formats/ktx2.dart';
import 'package:flutter3d_showcase/pages/formats/meshopt.dart';
import 'package:flutter3d_showcase/pages/formats/model_asset.dart';
import 'package:flutter3d_showcase/pages/formats/obj.dart';
import 'package:flutter3d_showcase/pages/formats/stl.dart';
import 'package:flutter3d_showcase/pages/formats/texture_compression.dart';
import 'package:flutter3d_showcase/pages/formats/texture_transform.dart';
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
  'meshopt': MeshoptDemo.new,
  'fbx-refusal': FbxRefusalDemo.new,
  'image-decode': ImageDecodeDemo.new,
  'custom-decoder': CustomDecoderDemo.new,
  'model-asset': ModelAssetDemo.new,
  'texture-transform': TextureTransformDemo.new,
};
