/// Every texture shape 1.0 names, written, copied and sampled on the
/// software rasteriser — and the sampler state that came with it.
///
/// Each fixture is a texture of one or two texels a side, so the answer is a
/// number that can be checked by eye: the layer a write landed in, the slice
/// a coordinate reads, the cube a direction meets.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_cpu/src/cpu_texel_codec.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

CpuDevice _device({
  Map<String, CpuStage> stages = const <String, CpuStage>{},
}) => CpuDevice(width: 4, height: 4, shaders: CpuShaderLibrary(stages));

ByteData _floats(List<double> values) =>
    ByteData.sublistView(Float32List.fromList(values));

/// Writes one storage texel of 0.3 red, as a compute stage would.
final class _StoreOnce extends CpuComputeShader {
  const _StoreOnce();

  @override
  (int, int, int) get workgroupSize => (1, 1, 1);

  @override
  void runWorkgroup((int, int, int) group, CpuComputeBindings bindings) =>
      bindings.storageTextures['Image']!.store(0, 0, Vector4(0.3, 0, 0, 1));
}

void main() {
  test('a 2D array is written, drawn into and sampled layer by layer', () {
    // Mutation: `CpuTexture.subresource` ignoring `layer`, so the write and
    // the pass both land in layer zero.
    final d = _device();
    final array = d.createTexture(
      const TextureDescriptor(
        width: 1,
        height: 1,
        depthOrArrayLayers: 3,
        dimension: TextureDimension.d2Array,
        format: TextureFormat.r32g32b32a32Float,
      ),
    );
    d.writeTexture(
      array,
      _floats(<double>[1, 0, 0, 1]),
      region: const TextureRegion(z: 1, width: 1, height: 1),
    );
    d
        .beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(
                texture: array,
                layer: 2,
                clearValue: Vector4(0, 0, 1, 1),
              ),
            ],
          ),
        )
        .submit();
    final bound = BoundTexture(
      array.backend as CpuTexture,
      SamplerDescriptor.nearestClamp,
    );
    expect(bound.sampleLayer(0.5, 0.5, 0).storage, <double>[0, 0, 0, 0]);
    expect(bound.sampleLayer(0.5, 0.5, 1).storage, <double>[1, 0, 0, 1]);
    expect(bound.sampleLayer(0.5, 0.5, 2).storage, <double>[0, 0, 1, 1]);
    // Rounded and clamped, as every API specifies.
    expect(bound.sampleLayer(0.5, 0.5, 9).storage, <double>[0, 0, 1, 1]);
  });

  test('a 3D texture filters between slices along its depth', () {
    // Mutation: `_sampleVolume` taking the nearest slice under a linear
    // filter, which answers 1 or 2 rather than their mean.
    final d = _device();
    final volume = d.createTexture(
      const TextureDescriptor(
        width: 1,
        height: 1,
        depthOrArrayLayers: 4,
        dimension: TextureDimension.d3,
        format: TextureFormat.r32Float,
      ),
    );
    d.writeTexture(volume, _floats(<double>[0, 1, 2, 3]));
    final linear = BoundTexture(
      volume.backend as CpuTexture,
      SamplerDescriptor.linearClamp,
    );
    expect(linear.sample3D(0.5, 0.5, 0.5).x, closeTo(1.5, 1e-6));
    final nearest = BoundTexture(
      volume.backend as CpuTexture,
      SamplerDescriptor.nearestClamp,
    );
    expect(nearest.sample3D(0.5, 0.5, 0.9).x, 3);
  });

  test('a cube array addresses layer × 6 + face', () {
    // Mutation: `CpuTexture.plane` reading z as the face of cube zero, so
    // plane seven lands nowhere a direction finds it.
    final d = _device();
    final cubes = d.createTexture(
      const TextureDescriptor(
        width: 1,
        height: 1,
        depthOrArrayLayers: 12,
        dimension: TextureDimension.cubeArray,
        format: TextureFormat.r32g32b32a32Float,
      ),
    );
    expect(cubes.type, TextureType.textureCube);
    d.writeTexture(
      cubes,
      _floats(<double>[0, 1, 0, 1]),
      region: const TextureRegion(z: 7, width: 1, height: 1),
    );
    final bound = BoundTexture(
      cubes.backend as CpuTexture,
      SamplerDescriptor.nearestClamp,
    );
    expect(bound.sampleCubeLayer(-1, 0, 0, 1).y, 1);
    expect(bound.sampleCubeLayer(-1, 0, 0, 0).y, 0);
    expect(bound.sampleCubeLayer(1, 0, 0, 1).y, 0);
  });

  test('a buffer copied into a half-float texture and back is the same '
      'bytes', () async {
    // Mutation: the codec reading `r16Float` as eight-bit unorm, as the
    // pre-1.0 upload path did for every format it did not list.
    final d = _device();
    final texture = d.createTexture(
      const TextureDescriptor(
        width: 2,
        height: 1,
        format: TextureFormat.r16Float,
      ),
    );
    final halves = ByteData(4)
      ..setUint16(0, doubleToHalf(0.5), Endian.little)
      ..setUint16(2, doubleToHalf(-2), Endian.little);
    final source = d.createBuffer(
      const BufferDescriptor(lengthInBytes: 4, usage: BufferUsage.copySource),
      contents: halves,
    );
    final back = d.createBuffer(
      BufferDescriptor(
        lengthInBytes: 4,
        usage: BufferUsage.copyDestination | BufferUsage.hostReadable,
      ),
    );
    d.beginTransferPass()
      ..copyBufferToTexture(
        source,
        const BufferTextureLayout(bytesPerRow: 4),
        TextureCopyLocation(texture),
        width: 2,
        height: 1,
      )
      ..copyTextureToBuffer(
        TextureCopyLocation(texture),
        back,
        const BufferTextureLayout(bytesPerRow: 4),
        width: 2,
        height: 1,
      )
      ..submit();
    final stored = (texture.backend as CpuTexture).pixels;
    expect(stored[0], 0.5);
    expect(stored[4], -2);
    expect(
      Uint8List.sublistView(await d.readBuffer(back)),
      Uint8List.sublistView(halves),
    );
  });

  test('the packed formats survive their own encoding', () {
    // Mutation: a wrong shift or bias in the half, 11/11/10 or shared-
    // exponent encoders, any of which moves one of these values.
    expect(doubleToHalf(1), 0x3C00);
    expect(doubleToHalf(65504), 0x7BFF);
    expect(doubleToHalf(1e6), 0x7C00);
    expect(halfToDouble(doubleToHalf(-0.375)), -0.375);
    final bytes = ByteData(4);
    final out = Float32List(4);
    void roundTrip(TextureFormat format, List<double> rgba) {
      encodeTexel(format, Float32List.fromList(rgba), 0, bytes, 0);
      decodeTexel(format, bytes, 0, out, 0);
    }

    roundTrip(TextureFormat.r11g11b10UFloat, <double>[1, 2, 0.5, 1]);
    expect(out.sublist(0, 3), <double>[1, 2, 0.5]);
    roundTrip(TextureFormat.r9g9b9e5UFloat, <double>[1, 0.5, 0.25, 1]);
    expect(out.sublist(0, 3), <double>[1, 0.5, 0.25]);
    roundTrip(TextureFormat.r10g10b10a2UNormInt, <double>[0, 1, 0.5, 1]);
    expect(out[0], 0);
    expect(out[1], 1);
    expect(out[2], closeTo(0.5, 1 / 1023));
    expect(out[3], 1);
  });

  test('a comparison sampler compares against the depth a write stored', () {
    // Mutation: `sampleCompare` reading the colour plane of a depth
    // texture, which is nought, so every comparison answers the same.
    final d = _device();
    final depth = d.createTexture(
      const TextureDescriptor(
        width: 2,
        height: 1,
        format: TextureFormat.d32Float,
      ),
    );
    d.writeTexture(depth, _floats(<double>[0.2, 0.8]));
    final bound = BoundTexture(
      depth.backend as CpuTexture,
      const SamplerDescriptor(compare: CompareFunction.less),
    );
    expect(bound.sampleCompare(0.25, 0.5, 0.5), 0);
    expect(bound.sampleCompare(0.75, 0.5, 0.5), 1);
  });

  test('a level-of-detail clamp holds the sampler off the base level', () {
    // Mutation: `sample` skipping `_sampleClamped`, so a sampler clamped to
    // level one still reads the base when it is given no derivatives.
    final d = _device();
    final texture = d.createTextureFromPixels(
      width: 2,
      height: 2,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(
        Uint8List.fromList(<int>[
          for (var i = 0; i < 4; i++) ...<int>[255, 0, 0, 255],
        ]),
      ),
      mipLevels: <ByteData>[
        ByteData.sublistView(Uint8List.fromList(<int>[0, 255, 0, 255])),
      ],
    );
    final cpu = texture.backend as CpuTexture;
    expect(
      BoundTexture(cpu, SamplerDescriptor.nearestClamp).sample(0.5, 0.5).x,
      1,
    );
    final clamped = BoundTexture(cpu, const SamplerDescriptor(lodMinClamp: 1));
    expect(clamped.sample(0.5, 0.5).y, 1);
    expect(clamped.sample(0.5, 0.5).x, 0);
  });

  test('a border colour is read outside the texture and nowhere else', () {
    // Mutation: `_sampleLevel` ignoring `borderColor`, clamping to the edge
    // texel as a sampler without one does.
    final d = _device();
    final texture = d.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData.sublistView(Uint8List.fromList(<int>[255, 0, 0, 255])),
    );
    final cpu = texture.backend as CpuTexture;
    final bordered = BoundTexture(
      cpu,
      const SamplerDescriptor(borderColor: SamplerBorderColor.opaqueWhite),
    );
    expect(bordered.sample(1.5, 0.5).storage, <double>[1, 1, 1, 1]);
    expect(bordered.sample(0.5, 0.5).storage, <double>[1, 0, 0, 1]);
    expect(
      BoundTexture(cpu, SamplerDescriptor.nearestClamp).sample(1.5, 0.5).x,
      1,
    );
  });

  test('a storage store lands on a step the format can hold', () {
    // Mutation: `CpuStorageTexture.store` skipping `settleTexel`, so an
    // eight-bit texture keeps 0.3 exactly.
    final d = _device(
      stages: <String, CpuStage>{
        'StoreOnce': const CpuStage.compute(_StoreOnce()),
      },
    );
    final stage = d.shaders['StoreOnce']!;
    final image = d.createTexture(
      TextureDescriptor(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
        usage: TextureUsage.storage | TextureUsage.copySource,
      ),
    );
    d.beginComputePass()
      ..bindPipeline(d.createComputePipeline(stage))
      ..bindStorageTexture(stage, 'Image', image)
      ..dispatch(1)
      ..submit();
    expect((image.backend as CpuTexture).pixels[0], closeTo(77 / 255, 1e-6));
    final plain = d.createTexture(
      const RenderTargetDescriptor(
        width: 1,
        height: 1,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    expect(
      () => d.beginComputePass().bindStorageTexture(stage, 'Image', plain),
      throwsArgumentError,
    );
  });
}
