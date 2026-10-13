/// The compute sidecar natively: a [GraphicsDevice] that computes and draws
/// nothing, over wgpu-native through `dart:ffi`.
///
/// **A device in every sense the contract cares about for compute**: it
/// makes storage buffers and RGBA8 textures, loads a bundle's kernel
/// section, makes compute pipelines and opens compute passes, and reads
/// back, so a step encodes its work here exactly as on WebGPU or the
/// software rasteriser. Everything that draws is refused by name: there is
/// no surface and no render pipeline, by design.
///
/// **Synchronous where the C side is.** Every readback waits on the queue
/// in the calling turn (wgpu's poll), so [readBuffer] completes at once and
/// the device also reads synchronously, which is what `SharedBuffer`'s copy
/// to the drawing device costs a frame.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/kernel.dart';

import 'wgpu_bindings.dart' as w;

/// How a refusal from the sidecar names it.
const String wgpuBackendName = 'the wgpu sidecar';

final class _Buffer {
  _Buffer(this.pointer, this.length);
  Pointer<w.F3dWgpuBuffer> pointer;
  final int length;
}

final class _Texture {
  _Texture(this.pointer, this.width, this.height);
  Pointer<w.F3dWgpuTexture> pointer;
  final int width;
  final int height;
}

/// A loaded kernel: its compiled pipeline, replaced under the handle on a
/// reload.
final class _Kernel {
  _Kernel(this.kernel, this.pointer);
  ComputeKernel kernel;
  Pointer<w.F3dWgpuKernel> pointer;
}

/// Opens the sidecar, or throws [DeviceUnavailableException] saying why: no
/// library in this build, a library of another ABI, or no adapter.
WgpuComputeDevice openWgpuComputeDevice() {
  final int abi;
  try {
    abi = w.f3d_wgpu_abi_version();
  } on ArgumentError {
    throw const DeviceUnavailableException(
      'there is no wgpu sidecar in this build: wgpu-native was not fetched '
      'for this target, so compute runs on the device or the CPU',
      backend: wgpuBackendName,
    );
  }
  if (abi != w.wgpuAbiVersion) {
    throw DeviceUnavailableException(
      'the sidecar library speaks ABI $abi and this build '
      '${w.wgpuAbiVersion}',
      backend: wgpuBackendName,
    );
  }
  final gpu = w.f3d_wgpu_open();
  if (gpu == nullptr) {
    throw const DeviceUnavailableException(
      'wgpu-native found no adapter it can use on this machine',
      backend: wgpuBackendName,
    );
  }
  return WgpuComputeDevice._(gpu);
}

/// The sidecar: compute only, over wgpu-native.
final class WgpuComputeDevice extends GraphicsDevice
    with SynchronousBufferReadback {
  WgpuComputeDevice._(this._gpu);

  Pointer<w.F3dWgpu> _gpu;

  Pointer<w.F3dWgpu> get _live {
    if (_gpu == nullptr) {
      throw StateError('$wgpuBackendName was disposed');
    }
    return _gpu;
  }

  @override
  String get backendName => wgpuBackendName;

  /// Fixed for good, rather than [backendName] in lower case: the name for
  /// people may change, the id a compiler and a manifest match may not.
  @override
  String get backendId => 'wgpu';

  /// The adapter wgpu chose, as it names itself.
  String get adapterName => _text(
    (Pointer<Uint8> out, int n) => w.f3d_wgpu_adapter_name(_live, out, n),
  );

  /// The last error wgpu reported and nobody took, or empty.
  String _takeError() => _text(
    (Pointer<Uint8> out, int n) => w.f3d_wgpu_take_error(_live, out, n),
  );

  static String _text(int Function(Pointer<Uint8>, int) read) {
    final out = calloc<Uint8>(1024);
    try {
      final n = read(out, 1024);
      return utf8.decode(out.asTypedList(n < 1023 ? n : 1023));
    } finally {
      calloc.free(out);
    }
  }

  final Set<_Buffer> _buffers = <_Buffer>{};
  final Set<_Texture> _textures = <_Texture>{};
  final Set<_Kernel> _kernels = <_Kernel>{};

  // ------------------------------------------------------------ what it is

  @override
  late final DeviceFeatures features = DeviceFeatures(const <DeviceFeature>[
    DeviceFeature.compute,
    DeviceFeature.buffers,
    DeviceFeature.storageTextures,
    DeviceFeature.synchronousReadback,
  ]);

  /// WebGPU's guaranteed minimums, which are wgpu's own defaults, for what
  /// it does: buffers, textures and compute. **Nothing for drawing**: no
  /// colour attachment, one sample, no vertex buffer or attribute, nothing
  /// between stages, since the sidecar opens no pass, and a caller sizing a
  /// pass from the limits must not find room on a device that refuses it.
  @override
  final DeviceLimits limits = const DeviceLimits(
    maxColorAttachments: 0,
    maxColorAttachmentBytesPerSample: 0,
    maxSampleCount: 1,
    maxVertexBuffers: 0,
    maxVertexAttributes: 0,
    maxVertexBufferArrayStride: 0,
    maxInterStageShaderVariables: 0,
  );

  @override
  TextureFormatSupport textureFormatSupport(TextureFormat format) =>
      format == TextureFormat.r8g8b8a8UNormInt
      ? const TextureFormatSupport(
          sampled: true,
          filterable: true,
          storage: true,
        )
      : TextureFormatSupport.none;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.unknown;

  @override
  TextureFormat get hdrColorFormat => TextureFormat.unknown;

  @override
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  int get preferredSampleCount => 1;

  // ---------------------------------------------------------- what it refuses

  Never _drawsNothing(String call) => throw UnsupportedError(
    '$wgpuBackendName computes and draws nothing, so it has no $call: draw '
    'on the device the frame is drawn on, and hand it what this computed '
    'through SharedBuffer or SharedTexture',
  );

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutDescriptor? layout,
  }) => _drawsNothing('render pipeline');

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) =>
      _drawsNothing('render pass');

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) =>
      _drawsNothing('geometry; a storage buffer is createBuffer');

  @override
  void overwriteGeometry(
    GeometryBuffer target,
    int offsetInBytes,
    ByteData bytes,
  ) => _drawsNothing('geometry');

  @override
  void releaseGeometry(GeometryBuffer geometry) {}

  @override
  TextureHandle createCubeRenderTarget({
    required int size,
    required TextureFormat format,
    int mipLevels = 1,
  }) => throw refuse(
    DeviceFeature.cubeTextures,
    reason: 'the sidecar makes 2D RGBA8 textures only',
  );

  @override
  TextureHandle createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) => throw refuse(
    DeviceFeature.cubeTextures,
    reason: 'the sidecar makes 2D RGBA8 textures only',
  );

  @override
  void beginFrame() {}

  @override
  void onFrameComplete(void Function() whenDone) => whenDone();

  // --------------------------------------------------------------- textures

  _Texture _make(int width, int height, {required bool storage}) {
    final pointer = w.f3d_wgpu_texture_create(
      _live,
      width,
      height,
      storage ? 1 : 0,
    );
    if (pointer == nullptr) {
      throw refuseResource(
        'createTexture',
        'wgpu made no $width × $height texture',
      );
    }
    return _Texture(pointer, width, height);
  }

  void _refuseShape(TextureDescriptor d, String call) {
    // A shape a feature names is refused as that feature, so a caller that
    // asks `features` first is never surprised.
    final feature = switch (d.dimension) {
      TextureDimension.d2Array => DeviceFeature.textureArrays,
      TextureDimension.d3 => DeviceFeature.texture3D,
      TextureDimension.cube => DeviceFeature.cubeTextures,
      TextureDimension.cubeArray => DeviceFeature.cubeArrayTextures,
      _ when d.sampleCount > 1 => DeviceFeature.offscreenMultisample,
      _ => null,
    };
    if (feature != null) {
      throw refuse(feature, reason: 'the sidecar makes 2D RGBA8 textures');
    }
    if (d.format != TextureFormat.r8g8b8a8UNormInt ||
        d.dimension != TextureDimension.d2 ||
        d.depthOrArrayLayers != 1 ||
        d.mipLevelCount != 1) {
      throw refuseResource(
        call,
        'the sidecar makes 2D RGBA8 textures of one level and one sample; '
        '$d is not one',
      );
    }
  }

  @override
  TextureHandle createTexture(TextureDescriptor descriptor) {
    _refuseShape(descriptor, 'createTexture');
    final texture = _make(
      descriptor.width,
      descriptor.height,
      storage: descriptor.usage.contains(TextureUsage.storage),
    );
    _textures.add(texture);
    return wrapTexture(
      backend: texture,
      width: descriptor.width,
      height: descriptor.height,
      format: descriptor.format,
      usage: descriptor.usage,
      owner: this,
    );
  }

  @override
  TextureHandle createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    final handle = createTexture(
      TextureDescriptor(
        width: width,
        height: height,
        format: format,
        mipLevelCount: 1 + (mipLevels?.length ?? 0),
      ),
    );
    if (pixels.lengthInBytes != width * height * 4) {
      throw refuseResource(
        'createTextureFromPixels',
        '${pixels.lengthInBytes} bytes are not $width × $height RGBA8 texels',
      );
    }
    _upload(handle.backend as _Texture, pixels);
    return handle;
  }

  void _upload(_Texture texture, ByteData rgba) {
    final n = rgba.lengthInBytes;
    final staged = calloc<Uint8>(n);
    try {
      staged
          .asTypedList(n)
          .setAll(0, rgba.buffer.asUint8List(rgba.offsetInBytes, n));
      w.f3d_wgpu_texture_write(_live, texture.pointer, staged.cast());
    } finally {
      calloc.free(staged);
    }
  }

  ByteData _download(_Texture texture) {
    final n = texture.width * texture.height * 4;
    final out = calloc<Uint8>(n);
    try {
      if (w.f3d_wgpu_texture_read(_live, texture.pointer, out.cast()) == 0) {
        throw refuseResource('readback', 'wgpu would not map the texture');
      }
      return ByteData.sublistView(Uint8List.fromList(out.asTypedList(n)));
    } finally {
      calloc.free(out);
    }
  }

  @override
  Future<void> overwriteTexture(
    TextureHandle target,
    ByteData rgba, {
    ScreenRect? region,
    int mipLevel = 0,
  }) async {
    debugCheckLive(target, 'overwriteTexture');
    final texture = target.backend as _Texture;
    final rect = region ?? ScreenRect.of(target);
    if (mipLevel != 0) {
      throw UnsupportedError('overwriteTexture: only the base level here');
    }
    if (rect.width == texture.width && rect.height == texture.height) {
      _upload(texture, rgba);
      return;
    }
    // A region: read the level, lay the rows in, write it whole.
    final whole = _download(texture);
    for (var y = 0; y < rect.height; y++) {
      for (var i = 0; i < rect.width * 4; i++) {
        whole.setUint8(
          ((rect.y + y) * texture.width + rect.x) * 4 + i,
          rgba.getUint8(y * rect.width * 4 + i),
        );
      }
    }
    _upload(texture, whole);
  }

  @override
  Future<ByteData> readback(TextureHandle texture, {ScreenRect? region}) async {
    debugCheckLive(texture, 'readback');
    final rect = readbackRegionOf(texture, region);
    final source = texture.backend as _Texture;
    final whole = _download(source);
    if (rect.width == source.width && rect.height == source.height) {
      return whole;
    }
    final out = ByteData(rect.width * rect.height * 4);
    for (var y = 0; y < rect.height; y++) {
      for (var i = 0; i < rect.width * 4; i++) {
        out.setUint8(
          y * rect.width * 4 + i,
          whole.getUint8(((rect.y + y) * source.width + rect.x) * 4 + i),
        );
      }
    }
    return out;
  }

  @override
  void releaseTexture(TextureHandle texture) {
    final t = texture.backend;
    if (t is! _Texture || !_textures.remove(t)) return;
    w.f3d_wgpu_texture_release(t.pointer);
    t.pointer = nullptr;
  }

  /// The `MTLTexture` behind [texture] where wgpu runs on Metal, as a
  /// [NativeHandle] another Metal device could import; null elsewhere.
  ///
  /// **The sidecar's half of zero copy, and only that half.** It is not
  /// `exportTexture`: the sidecar cannot import a texture back, so it does
  /// not report `DeviceFeature.sharedTextures`, and `SharedTexture` copies.
  /// Here for the day the drawing device can import one.
  NativeHandle? metalTextureOf(TextureHandle texture) {
    debugCheckLive(texture, 'metalTextureOf');
    if (!Platform.isMacOS && !Platform.isIOS) return null;
    final address = w.f3d_wgpu_texture_native_metal(
      (texture.backend as _Texture).pointer,
    );
    return address == nullptr
        ? null
        : NativeHandle(NativeHandleKind.metalTexture, address.address);
  }

  // ---------------------------------------------------------------- buffers

  @override
  StorageBuffer createBuffer(
    BufferDescriptor descriptor, {
    ByteData? contents,
  }) {
    final pointer = w.f3d_wgpu_buffer_create(_live, descriptor.lengthInBytes);
    if (pointer == nullptr) {
      throw refuseResource(
        'createBuffer',
        'wgpu made no buffer of ${descriptor.lengthInBytes} bytes',
      );
    }
    final buffer = _Buffer(pointer, descriptor.lengthInBytes);
    _buffers.add(buffer);
    final handle = wrapStorageBuffer(
      backend: buffer,
      lengthInBytes: descriptor.lengthInBytes,
      hostReadable: descriptor.usage.contains(BufferUsage.hostReadable),
      usage: descriptor.usage,
      owner: this,
    );
    if (contents != null) writeBuffer(handle, 0, contents);
    return handle;
  }

  @override
  void writeBuffer(StorageBuffer target, int offsetInBytes, ByteData bytes) {
    debugCheckLive(target, 'writeBuffer');
    final n = bytes.lengthInBytes;
    if (offsetInBytes < 0 || offsetInBytes + n > target.lengthInBytes) {
      throw ArgumentError(
        'writeBuffer: $n bytes at $offsetInBytes do not fit in '
        '${target.lengthInBytes}',
      );
    }
    if (n == 0) return;
    final staged = calloc<Uint8>(n);
    try {
      staged
          .asTypedList(n)
          .setAll(0, bytes.buffer.asUint8List(bytes.offsetInBytes, n));
      w.f3d_wgpu_buffer_write(
        _live,
        (target.backend as _Buffer).pointer,
        offsetInBytes,
        staged.cast(),
        n,
      );
    } finally {
      calloc.free(staged);
    }
  }

  @override
  ByteData readBufferSync(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    debugCheckLive(buffer, 'readBufferSync');
    final n = sizeInBytes ?? buffer.lengthInBytes - offsetInBytes;
    if (offsetInBytes < 0 ||
        n < 0 ||
        offsetInBytes + n > buffer.lengthInBytes) {
      throw RangeError(
        'readBufferSync: $n bytes at $offsetInBytes leave a buffer of '
        '${buffer.lengthInBytes}',
      );
    }
    final out = calloc<Uint8>(n < 1 ? 1 : n);
    try {
      final ok = w.f3d_wgpu_buffer_read(
        _live,
        (buffer.backend as _Buffer).pointer,
        offsetInBytes,
        out.cast(),
        n,
      );
      if (ok == 0) {
        throw refuseResource('readBuffer', 'wgpu would not map the buffer');
      }
      return ByteData.sublistView(Uint8List.fromList(out.asTypedList(n)));
    } finally {
      calloc.free(out);
    }
  }

  @override
  Future<ByteData> readBuffer(StorageBuffer buffer) async =>
      readBufferSync(buffer);

  @override
  void releaseStorageBuffer(StorageBuffer buffer) {
    final b = buffer.backend;
    if (b is! _Buffer || !_buffers.remove(b)) return;
    w.f3d_wgpu_buffer_release(b.pointer);
    b.pointer = nullptr;
  }

  // ---------------------------------------------------------------- kernels

  @override
  final ShaderLibrary shaders = const _NoStages();

  @override
  Future<LoadedShaderLibrary> loadShaders(ByteData bytes) async {
    final bundle = ShaderBundle.decode(bytes);
    final library = _WgpuKernelLibrary(this, bundle.name);
    library._take(_compileAll(bundle, const <String, _Kernel>{}));
    return library;
  }

  /// Every kernel [bundle] carries, compiled — [kept] reused where the
  /// source did not change — or a refusal naming the bundle. A stage the
  /// bundle claims that is not a kernel is refused by name: the sidecar runs
  /// kernels and nothing else.
  Map<String, _Kernel> _compileAll(
    ShaderBundle bundle,
    Map<String, _Kernel> kept,
  ) {
    final kernels = kernelsOf(bundle);
    final others = bundle.names.where((n) => !kernels.containsKey(n)).toList();
    if (others.isNotEmpty) {
      throw ShaderBundleException(
        name: bundle.name,
        reason:
            '$wgpuBackendName runs compute kernels only, and '
            '${others.join(', ')} ${others.length == 1 ? 'is' : 'are'} not '
            'one. Load drawing stages on the device that draws.',
      );
    }
    final compiled = <String, _Kernel>{};
    try {
      for (final MapEntry(key: name, value: kernel) in kernels.entries) {
        final previous = kept[name];
        compiled[name] =
            previous != null && previous.kernel.source == kernel.source
            ? previous
            : _Kernel(kernel, _compile(bundle.name, kernel));
      }
    } on Object {
      for (final made in compiled.values) {
        if (!kept.containsValue(made)) w.f3d_wgpu_kernel_release(made.pointer);
      }
      rethrow;
    }
    _kernels.addAll(compiled.values);
    return compiled;
  }

  Pointer<w.F3dWgpuKernel> _compile(String bundle, ComputeKernel kernel) {
    final wgsl = kernel.toWgsl();
    final source = _cString(wgsl.code);
    final entry = _cString(wgsl.entryPoint);
    final kinds = calloc<Uint32>(
      wgsl.bindings.isEmpty ? 1 : wgsl.bindings.length,
    );
    final error = calloc<Uint8>(1024);
    try {
      for (final b in wgsl.bindings) {
        kinds[b.index] = switch (b.kind) {
          KernelBindingKind.buffer =>
            b.writable ? w.wgpuStorage : w.wgpuReadOnly,
          KernelBindingKind.texture => w.wgpuTexture,
          KernelBindingKind.image => w.wgpuImage,
          _ => throw ShaderBundleException(
            name: bundle,
            reason:
                'the kernel "${kernel.name}" binds a ${b.kind.name}, '
                'which this sidecar does not know',
          ),
        };
      }
      final made = w.f3d_wgpu_kernel_create(
        _live,
        source,
        entry,
        kinds,
        wgsl.bindings.length,
        error,
        1024,
      );
      if (made == nullptr) {
        final message = _cRead(error);
        throw ShaderBundleException(
          name: bundle,
          reason:
              'wgpu would not compile the kernel "${kernel.name}": $message',
        );
      }
      return made;
    } finally {
      calloc
        ..free(source)
        ..free(entry)
        ..free(kinds)
        ..free(error);
    }
  }

  static Pointer<Uint8> _cString(String text) {
    final bytes = utf8.encode(text);
    final out = calloc<Uint8>(bytes.length + 1);
    out.asTypedList(bytes.length).setAll(0, bytes);
    out[bytes.length] = 0;
    return out;
  }

  static String _cRead(Pointer<Uint8> text) {
    var n = 0;
    while (n < 1023 && text[n] != 0) {
      n += 1;
    }
    return utf8.decode(text.asTypedList(n), allowMalformed: true);
  }

  @override
  ComputePipelineHandle createComputePipeline(ShaderHandle shader) {
    debugCheckLive(shader, 'createComputePipeline');
    if (shader.backend is! _Kernel) {
      throw ArgumentError.value(
        shader.name,
        'shader',
        'is not a kernel this sidecar loaded',
      );
    }
    return wrapComputePipeline(
      backend: shader.backend,
      shader: shader,
      owner: this,
    );
  }

  @override
  ComputeEncoder beginComputePass({
    String? label,
    PassTimestampWrites? timestampWrites,
  }) {
    if (timestampWrites != null) {
      throw UnsupportedCapabilityException(
        DeviceFeature.timestampQuery,
        backend: wgpuBackendName,
      );
    }
    return _WgpuComputeEncoder(this);
  }

  /// Runs [dispatches] as one pass, or throws with what wgpu said.
  void _submit(List<_Dispatch> dispatches) {
    if (dispatches.isEmpty) return;
    final pass = w.f3d_wgpu_pass_begin(_live);
    var ok = true;
    for (final d in dispatches) {
      final n = d.resources.length;
      final resources = calloc<Pointer<Void>>(n < 1 ? 1 : n);
      final offsets = calloc<Uint64>(n < 1 ? 1 : n);
      final sizes = calloc<Uint64>(n < 1 ? 1 : n);
      try {
        for (var i = 0; i < n; i++) {
          final r = d.resources[i];
          resources[i] = switch (r.target) {
            final _Buffer b => b.pointer.cast(),
            final _Texture t => t.pointer.cast(),
            _ => nullptr,
          };
          offsets[i] = r.offset;
          sizes[i] = r.size;
        }
        ok &=
            w.f3d_wgpu_pass_dispatch(
              pass,
              d.kernel.pointer,
              resources,
              offsets,
              sizes,
              n,
              d.x,
              d.y,
              d.z,
            ) !=
            0;
      } finally {
        calloc
          ..free(resources)
          ..free(offsets)
          ..free(sizes);
      }
    }
    final submitted = w.f3d_wgpu_pass_submit(pass) != 0;
    if (!ok || !submitted) {
      throw refuseResource('submit', 'wgpu refused the pass: ${_takeError()}');
    }
  }

  @override
  void releaseComputePipeline(ComputePipelineHandle pipeline) {}

  @override
  void dispose() {
    if (_gpu == nullptr) return;
    for (final k in _kernels) {
      w.f3d_wgpu_kernel_release(k.pointer);
    }
    for (final t in _textures) {
      w.f3d_wgpu_texture_release(t.pointer);
    }
    for (final b in _buffers) {
      w.f3d_wgpu_buffer_release(b.pointer);
    }
    _kernels.clear();
    _textures.clear();
    _buffers.clear();
    w.f3d_wgpu_close(_gpu);
    _gpu = nullptr;
  }
}

/// The sidecar's own library: no stages, since it ships none.
final class _NoStages with ShaderLibrary {
  const _NoStages();

  @override
  ShaderHandle? operator [](String name) => null;
}

/// A bundle's kernels on the sidecar.
final class _WgpuKernelLibrary with ShaderLibrary, LoadedShaderLibrary {
  _WgpuKernelLibrary(this._device, this._name);

  final WgpuComputeDevice _device;
  String _name;
  final Map<String, _Kernel> _kernels = <String, _Kernel>{};
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  void _take(Map<String, _Kernel> kernels) => _kernels.addAll(kernels);

  @override
  String get name => _name;

  @override
  ShaderHandle? operator [](String name) {
    final kernel = _kernels[name];
    if (kernel == null) return null;
    return _handles.putIfAbsent(
      name,
      () => wrapShader(
        backend: kernel,
        name: name,
        release: (ShaderHandle h) => forgetShader(_handles, h),
      ),
    );
  }

  @override
  void refresh(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    final compiled = _device._compileAll(bundle, _kernels);
    final dropped = _handles.keys.where((n) => !compiled.containsKey(n));
    if (dropped.isNotEmpty) {
      throw ShaderBundleException(
        name: bundle.name,
        reason:
            'it no longer has the kernel "${dropped.first}", which is '
            'already in use',
      );
    }
    for (final MapEntry(key: name, value: fresh) in compiled.entries) {
      final existing = _kernels[name];
      if (existing == null) {
        _kernels[name] = fresh;
      } else if (!identical(existing, fresh)) {
        // The handle keeps its kernel object; what runs under it moves, and
        // the pipeline it ran before goes back to wgpu. Every pass is done
        // by the time this runs: a submit here waits on the queue.
        w.f3d_wgpu_kernel_release(existing.pointer);
        existing
          ..kernel = fresh.kernel
          ..pointer = fresh.pointer;
        _device._kernels.remove(fresh);
      }
    }
    _name = bundle.name;
  }
}

/// One binding of a dispatch: a buffer with its range, or a texture.
final class _Bound {
  const _Bound(this.target, {this.offset = 0, this.size = 0});
  final Object? target;
  final int offset;
  final int size;
}

final class _Dispatch {
  const _Dispatch(this.kernel, this.resources, this.x, this.y, this.z);
  final _Kernel kernel;
  final List<_Bound> resources;
  final int x;
  final int y;
  final int z;
}

/// A compute pass on the sidecar: bindings by the kernel's names, each
/// dispatch kept with what was bound for it, and the whole pass run on
/// [submit].
final class _WgpuComputeEncoder extends ComputeEncoder {
  _WgpuComputeEncoder(this._device);

  final WgpuComputeDevice _device;
  _Kernel? _kernel;
  List<_Bound> _bound = const <_Bound>[];
  final List<_Dispatch> _dispatches = <_Dispatch>[];

  @override
  void bindPipeline(ComputePipelineHandle pipeline) {
    final kernel = pipeline.backend as _Kernel;
    _kernel = kernel;
    _bound = List<_Bound>.filled(
      kernel.kernel.bindings.length,
      const _Bound(null),
    );
  }

  KernelBinding? _binding(String name, KernelBindingKind kind) {
    final binding = _kernel?.kernel.binding(name);
    return binding != null && binding.kind == kind ? binding : null;
  }

  @override
  bool bindStorageBuffer(
    ShaderHandle stage,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    debugCheckLive(buffer, 'bindStorageBuffer');
    final size = sizeInBytes ?? buffer.lengthInBytes - offsetInBytes;
    if (offsetInBytes < 0 ||
        size < 0 ||
        offsetInBytes + size > buffer.lengthInBytes) {
      throw RangeError(
        'bindStorageBuffer: $size bytes from $offsetInBytes leave a buffer '
        'of ${buffer.lengthInBytes}',
      );
    }
    final binding = _binding(name, KernelBindingKind.buffer);
    if (binding == null) return false;
    _bound[binding.index] = _Bound(
      buffer.backend,
      offset: offsetInBytes,
      size: sizeInBytes == null ? 0 : size,
    );
    return true;
  }

  @override
  bool bindTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    debugCheckLive(texture, 'bindTexture');
    // A kernel loads texels and samples nothing, but a sampler naming state
    // this device has no feature for is refused by it, as on every backend.
    sampler?.checkFeatures(_device.features, backend: _device.backendName);
    final binding = _binding(name, KernelBindingKind.texture);
    if (binding == null) return false;
    _bound[binding.index] = _Bound(texture.backend);
    return true;
  }

  @override
  bool bindStorageTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) {
    debugCheckLive(texture, 'bindStorageTexture');
    if (!texture.usage.contains(TextureUsage.storage)) {
      throw ArgumentError.value(
        texture.usage,
        'texture',
        'a storage texture is made with TextureUsage.storage',
      );
    }
    final binding = _binding(name, KernelBindingKind.image);
    if (binding == null) return false;
    _bound[binding.index] = _Bound(texture.backend);
    return true;
  }

  /// False: a kernel declares no uniform block in this version.
  @override
  bool bindUniformBlock(
    ShaderHandle stage,
    String block,
    Map<String, Float32List> members,
  ) => false;

  @override
  void dispatch(int x, [int y = 1, int z = 1]) {
    final kernel = _kernel;
    if (kernel == null) {
      throw StateError('dispatch before any compute pipeline was bound');
    }
    for (final b in kernel.kernel.bindings) {
      if (_bound[b.index].target == null) {
        throw StateError(
          'dispatch of "${kernel.kernel.name}" with its ${b.kind.name} '
          '"${b.name}" unbound',
        );
      }
    }
    _dispatches.add(_Dispatch(kernel, List<_Bound>.of(_bound), x, y, z));
  }

  @override
  void submit() {
    final dispatches = List<_Dispatch>.of(_dispatches);
    _dispatches.clear();
    _device._submit(dispatches);
  }
}
