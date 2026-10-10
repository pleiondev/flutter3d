/// Images decoded by the browser, copied into a texture, and given a chain
/// drawn on the GPU — `A4.16`.
///
/// **The decode never touches Dart.** `createImageBitmap` runs the browser's
/// decoder (off the main thread where the engine has one) and
/// `copyExternalImageToTexture` puts the bitmap into level zero. The CPU path
/// this replaces on the web decoded in `dart:ui`, read the pixels back,
/// halved them level by level in Dart and wrote every level.
///
/// **WebGPU has no `generateMipmap`, so the chain is a draw per level.** Each
/// level is a full-screen triangle sampling the one above with a linear
/// filter; at the centre of a destination texel that filter is the average of
/// the 2×2 block beneath it — the box `MipChain.build` computes on the CPU.
/// One pipeline, made on the first image and kept for the device's life.
///
/// The bitmap half declares its own few lines of interop rather than take
/// `package:web` for three names, for the reason `webgpu_interop.dart` gives
/// about its flag constants.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart';
import 'webgpu_interop.dart';
import 'webgpu_types.dart';

// ------------------------------------------------------- the browser decode

extension type _ImageBitmap._(JSObject _) implements JSObject {
  external int get width;
  external int get height;
  external void close();
}

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobOptions options);
}

extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

extension type _BitmapOptions._(JSObject _) implements JSObject {
  external factory _BitmapOptions({
    String premultiplyAlpha,
    String colorSpaceConversion,
  });

  external factory _BitmapOptions.resized({
    String premultiplyAlpha,
    String colorSpaceConversion,
    int resizeWidth,
    int resizeHeight,
    String resizeQuality,
  });
}

@JS('createImageBitmap')
external JSPromise<_ImageBitmap> _createImageBitmap(
  JSObject source,
  _BitmapOptions options,
);

String _mime(Uint8List bytes) {
  if (bytes.length < 12) return '';
  if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
  if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'image/gif';
  if (bytes[0] == 0x52 && bytes[8] == 0x57) return 'image/webp';
  return '';
}

_BitmapOptions _options({int? width, int? height}) =>
    width == null || height == null
    ? _BitmapOptions(premultiplyAlpha: 'none', colorSpaceConversion: 'none')
    : _BitmapOptions.resized(
        premultiplyAlpha: 'none',
        colorSpaceConversion: 'none',
        resizeWidth: width,
        resizeHeight: height,
        resizeQuality: 'high',
      );

/// [encoded] decoded by the browser and scaled to fit [maxDimension] while
/// it is decoded, or null when the browser refuses it. The same steps as the
/// WebGL2 backend's `decodeImageBitmap`.
Future<_ImageBitmap?> _decode(Uint8List encoded, int? maxDimension) async {
  final blob = _Blob(
    <JSAny>[encoded.toJS].toJS,
    _BlobOptions(type: _mime(encoded)),
  );
  try {
    final stated = encodedImageSize(encoded);
    if (stated != null) {
      final target = cappedImageSize(
        stated.width,
        stated.height,
        maxDimension: maxDimension,
      );
      final scaled =
          target.width != stated.width || target.height != stated.height;
      return await _createImageBitmap(
        blob,
        scaled
            ? _options(width: target.width, height: target.height)
            : _options(),
      ).toDart;
    }
    final full = await _createImageBitmap(blob, _options()).toDart;
    final target = cappedImageSize(
      full.width,
      full.height,
      maxDimension: maxDimension,
    );
    if (target.width == full.width && target.height == full.height) {
      return full;
    }
    try {
      return await _createImageBitmap(
        full,
        _options(width: target.width, height: target.height),
      ).toDart;
    } finally {
      full.close();
    }
  } catch (_) {
    // Not an image this browser decodes; the caller falls back to the CPU.
    return null;
  }
}

// ------------------------------------------------------------ the mip pass

const String _mipWgsl = '''
@group(0) @binding(0) var source: texture_2d<f32>;
@group(0) @binding(1) var linearClamp: sampler;

struct Varyings {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

@vertex
fn vertexMain(@builtin(vertex_index) index: u32) -> Varyings {
  let corner = vec2f(f32((index << 1u) & 2u), f32(index & 2u));
  var out: Varyings;
  out.position = vec4f(corner * 2.0 - 1.0, 0.0, 1.0);
  out.uv = vec2f(corner.x, 1.0 - corner.y);
  return out;
}

@fragment
fn fragmentMain(in: Varyings) -> @location(0) vec4f {
  return textureSampleLevel(source, linearClamp, in.uv, 0.0);
}
''';

/// The one pipeline and sampler the mip pass needs, per device.
final class WebGpuMipBuilder {
  WebGpuMipBuilder(this._gpu);

  final GPUDevice _gpu;

  late final GPURenderPipeline _pipeline = () {
    final module = _gpu.createShaderModule(
      GPUShaderModuleDescriptor(code: _mipWgsl, label: 'mip chain'),
    );
    return _gpu.createRenderPipeline(
      GPURenderPipelineDescriptor.withoutDepth(
        layout: 'auto'.toJS,
        vertex: GPUVertexState(
          module: module,
          entryPoint: 'vertexMain',
          buffers: <GPUVertexBufferLayout>[].toJS,
        ),
        fragment: GPUFragmentState(
          module: module,
          entryPoint: 'fragmentMain',
          targets: <GPUColorTargetState>[
            GPUColorTargetState.opaque(format: 'rgba8unorm'),
          ].toJS,
        ),
        primitive: GPUPrimitiveState(topology: 'triangle-list'),
        label: 'mip chain',
      ),
    );
  }();

  late final GPUSampler _sampler = _gpu.createSampler(
    GPUSamplerDescriptor(
      addressModeU: 'clamp-to-edge',
      addressModeV: 'clamp-to-edge',
      addressModeW: 'clamp-to-edge',
      magFilter: 'linear',
      minFilter: 'linear',
      mipmapFilter: 'nearest',
      label: 'mip chain',
    ),
  );

  /// Fills levels 1 to [levels] − 1 of [texture] from level zero, one draw a
  /// level, in one submission.
  void build(GPUTexture texture, int levels) {
    if (levels < 2) return;
    final encoder = _gpu.createCommandEncoder();
    final layout = _pipeline.getBindGroupLayout(0);
    for (var level = 1; level < levels; level++) {
      final source = texture.createView(
        GPUTextureViewDescriptor(
          dimension: '2d',
          baseMipLevel: level - 1,
          mipLevelCount: 1,
        ),
      );
      final target = texture.createView(
        GPUTextureViewDescriptor(
          dimension: '2d',
          baseMipLevel: level,
          mipLevelCount: 1,
        ),
      );
      final group = _gpu.createBindGroup(
        GPUBindGroupDescriptor(
          layout: layout,
          entries: <GPUBindGroupEntry>[
            GPUBindGroupEntry.textureView(binding: 0, resource: source),
            GPUBindGroupEntry.sampler(binding: 1, resource: _sampler),
          ].toJS,
        ),
      );
      final pass =
          encoder.beginRenderPass(
              GPURenderPassDescriptor(
                colorAttachments: <GPURenderPassColorAttachment>[
                  GPURenderPassColorAttachment(
                    view: target,
                    clearValue: GPUColorDict(r: 0, g: 0, b: 0, a: 0),
                    loadOp: 'clear',
                    storeOp: 'store',
                  ),
                ].toJS,
                label: 'mip $level',
              ),
            )
            ..setPipeline(_pipeline)
            ..setBindGroup(0, group)
            ..draw(3);
      pass.end();
    }
    _gpu.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);
  }
}

/// [encoded] decoded by the browser into a new `rgba8unorm` texture, with a
/// GPU-built chain when [mipmaps] — `EncodedImageUpload` on this backend.
/// Null when the browser will not decode it.
///
/// [guard] is the device's validation scope, opened around the GPU half only
/// — the texture, the copy and the mip pass, which run synchronously once
/// the decode has settled. A scope held open across the asynchronous decode
/// would catch whatever the frame drawn meanwhile did wrong and report it
/// against this image.
Future<TextureHandle?> webgpuCreateTextureFromEncodedImage(
  GPUDevice gpu,
  List<WebGpuTexture> tracked,
  WebGpuMipBuilder mips,
  Uint8List encoded, {
  required bool mipmaps,
  required T Function<T>(String what, T Function() body) guard,
  int? maxDimension,
}) async {
  final bitmap = await _decode(encoded, maxDimension);
  if (bitmap == null) return null;
  try {
    return guard<TextureHandle>(
      'a browser-decoded ${bitmap.width}x${bitmap.height} image',
      () => _upload(gpu, tracked, mips, bitmap, mipmaps: mipmaps),
    );
  } finally {
    bitmap.close();
  }
}

TextureHandle _upload(
  GPUDevice gpu,
  List<WebGpuTexture> tracked,
  WebGpuMipBuilder mips,
  _ImageBitmap bitmap, {
  required bool mipmaps,
}) {
  final width = bitmap.width;
  final height = bitmap.height;
  final levels = mipmaps ? MipChain.levelsFor(width, height) + 1 : 1;
  final texture = gpu.createTexture(
    GPUTextureDescriptor(
      size: GPUExtent3DDict(
        width: width,
        height: height,
        depthOrArrayLayers: 1,
      ),
      format: 'rgba8unorm',
      // RENDER_ATTACHMENT twice over: the external copy may be a draw on
      // the browser's side, and every level below the base is one here.
      usage:
          GpuTextureUsage.textureBinding |
          GpuTextureUsage.copyDst |
          GpuTextureUsage.copySrc |
          GpuTextureUsage.renderAttachment,
      sampleCount: 1,
      mipLevelCount: levels,
      dimension: '2d',
      label: 'decoded image ${width}x$height',
    ),
  );
  gpu.queue.copyExternalImageToTexture(
    GPUCopyExternalImageSourceInfo(source: bitmap, flipY: false),
    GPUCopyExternalImageDestInfo(
      texture: texture,
      mipLevel: 0,
      premultipliedAlpha: false,
    ),
    GPUExtent3DDict(width: width, height: height, depthOrArrayLayers: 1),
  );
  mips.build(texture, levels);

  final backend = WebGpuTexture(
    texture: texture,
    dimension: WebGpuTextureDimension.twoDimensional,
    sampleable: true,
  );
  tracked.add(backend);
  return wrapTexture(
    backend: backend,
    width: width,
    height: height,
    format: TextureFormat.r8g8b8a8UNormInt,
  );
}
