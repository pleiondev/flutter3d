/// A material's `compute` stage on a live WebGPU device: lowered to the
/// kernel language, it writes the bytes the same kernel written by hand
/// writes, and the bytes the CPU computes for it.
///
///     flutter test --platform chrome test/material_compute_test.dart
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/kernel.dart';
import 'package:flutter3d_webgpu/engine_shaders.dart';
import 'package:flutter3d_webgpu/flutter3d_webgpu_web.dart';
import 'package:flutter_test/flutter_test.dart';

const String _ripples = '''
f3dmat 2
compute Ripples {
  uniform vec3 tint = vec3(1.0, 0.5, 0.25);
  workgroup 8 4;
  kernel {
    let p = uv - vec2(0.5);
    let wave = 0.5 + 0.5 * (p.x * p.x + p.y * p.y) * 4.0;
    return vec4(tint * wave, 1.0);
  }
}
''';

/// [_ripples], written by hand.
const String _handWritten = '''
compute Ripples {
  workgroup 8, 4;
  image target: rgba8;
  buffer params: f32[];
  kernel {
    let x = id.x;
    let y = id.y;
    if x >= width(target) || y >= height(target) { return; }
    let size = vec2(f32(width(target)), f32(height(target)));
    let uv = (vec2(f32(x), f32(y)) + vec2(0.5, 0.5)) / size;
    let p = uv - vec2(0.5, 0.5);
    let wave = 0.5 + 0.5 * (p.x * p.x + p.y * p.y) * 4.0;
    store(target, x, y, vec4(vec3(params[0], params[1], params[2]) * wave, 1.0));
  }
}
''';

const int _width = 19;
const int _height = 13;

Future<Uint8List> _run(
  GraphicsDevice device,
  ShaderHandle stage,
  ByteData params,
  int groupsX,
  int groupsY,
) async {
  final target = device.createTexture(
    TextureDescriptor(
      width: _width,
      height: _height,
      format: TextureFormat.r8g8b8a8UNormInt,
      usage: TextureUsage.storage | TextureUsage.copySource,
    ),
  );
  final buffer = device.createBuffer(
    BufferDescriptor(
      lengthInBytes: params.lengthInBytes,
      usage: BufferUsage.standardStorage,
    ),
    contents: params,
  );
  final pass = device.beginComputePass(label: 'Ripples')
    ..bindPipeline(device.createComputePipeline(stage));
  expect(pass.bindStorageTexture(stage, 'target', target), isTrue);
  expect(pass.bindStorageBuffer(stage, 'params', buffer), isTrue);
  pass
    ..dispatch(groupsX, groupsY)
    ..submit();
  final bytes = await device.readback(target);
  device
    ..releaseTexture(target)
    ..releaseStorageBuffer(buffer);
  return Uint8List.fromList(
    bytes.buffer.asUint8List(bytes.offsetInBytes, _width * _height * 4),
  );
}

void main() {
  test('the lowered stage writes the hand-written kernel\'s bytes', () async {
    // Mutation: lower uv without its half texel, or the uniforms in
    // another order, and the GPU's bytes differ from the hand-written ones.
    final WebGpuDevice device;
    try {
      device = await WebGpuDevice.open(
        width: 4,
        height: 4,
        stages: webGpuEngineShaders,
      );
    } on DeviceUnavailableException catch (refused) {
      markTestSkipped('no WebGPU adapter here: ${refused.message}');
      return;
    }
    final lowered = lowerMaterialCompute(parseMaterial(_ripples));
    final params = lowered.parameterBytes(
      values: const <String, List<double>>{
        'tint': <double>[0.9, 0.6, 0.3],
      },
    );
    final sugar = await _run(
      device,
      await lowered.load(device),
      params,
      lowered.groupsX(_width),
      lowered.groupsY(_height),
    );
    final library = await device.loadShaders(
      kernelBundle('hand', <ComputeKernel>[
        ComputeKernel.parse(_handWritten),
      ]).encode(),
    );
    final hand = await _run(
      device,
      library['Ripples']!,
      params,
      lowered.groupsX(_width),
      lowered.groupsY(_height),
    );
    expect(sugar, hand);
    // And the CPU's bake: the arithmetic here is `+`, `-` and `*`, which
    // every placement rounds alike.
    final baked = lowered.bake(
      _width,
      _height,
      parameters: const <String, List<double>>{
        'tint': <double>[0.9, 0.6, 0.3],
      },
    );
    expect(sugar, baked.rgba);
  });
}
