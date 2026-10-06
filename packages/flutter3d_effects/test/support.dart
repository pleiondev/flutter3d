/// What the tests share: a software device, a scene and a renderer to draw
/// into, and the package's compiled material.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';

GraphicsDevice softwareDevice() => CpuDevice(
  width: 32,
  height: 32,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// `assets/liquid.f3dshaders`, as an application's bundle hands it over.
ByteData waterBundle() =>
    ByteData.sublistView(File('assets/liquid.f3dshaders').readAsBytesSync());
