/// What the tests share: a software device, a scene and a renderer to draw
/// into, and the package's compiled material.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

GraphicsDevice softwareDevice() => CpuDevice(
  width: 32,
  height: 32,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// A software device that also takes the water's bundle: the software
/// rasteriser runs Dart stages only, and draws the water's material with an
/// unlit one in its place — for tests of what the elements do, not of how
/// the water looks.
GraphicsDevice elementsDevice() => CpuDevice(
  width: 32,
  height: 32,
  shaders: CpuShaderLibrary(<String, CpuStage>{
    ...builtinCpuShaders(),
    'Liquid': cpuUnlitStage,
  }),
);

/// `assets/liquid.f3dshaders`, as an application's bundle hands it over.
ByteData waterBundle() =>
    ByteData.sublistView(File('assets/liquid.f3dshaders').readAsBytesSync());
