/// Copies between buffers and textures on the software rasteriser.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_resources.dart';
import 'cpu_texel_codec.dart';
import 'cpu_texture.dart';

/// A transfer pass — `GraphicsDevice.beginTransferPass`.
///
/// **Checked when recorded, run when submitted.** Every refusal — a missing
/// feature, a usage the resource was not made for, a range that does not
/// fit — is thrown by the call that asked, where the mistake is; the copies
/// themselves run at [submit], in the order recorded. That is the one place
/// this backend defers anything: a render pass draws as it is recorded, so a
/// copy recorded before a render pass but submitted after it has to wait
/// for the submit to land after that pass's draws, as it would on a queue.
final class CpuTransferEncoder extends TransferEncoder {
  CpuTransferEncoder(this._features);

  final DeviceFeatures _features;
  final List<void Function()> _copies = <void Function()>[];
  bool _submitted = false;

  void _record(void Function() copy) {
    if (_submitted) {
      throw StateError('a copy recorded after the transfer pass was submitted');
    }
    _copies.add(copy);
  }

  @override
  void copyBufferToBuffer(
    StorageBuffer source,
    int sourceOffset,
    StorageBuffer destination,
    int destinationOffset,
    int size,
  ) {
    _features.require(DeviceFeature.bufferCopy, backend: cpuBackendName);
    requireBufferUsage(source, BufferUsage.copySource, 'a copy from it');
    requireBufferUsage(
      destination,
      BufferUsage.copyDestination,
      'a copy into it',
    );
    if (size % 4 != 0) {
      throw ArgumentError.value(size, 'size', 'must be a multiple of four');
    }
    final from = rangeOf(
      source,
      offsetInBytes: sourceOffset,
      sizeInBytes: size,
    );
    final to = rangeOf(
      destination,
      offsetInBytes: destinationOffset,
      sizeInBytes: size,
    );
    if (identical(source, destination) &&
        sourceOffset < destinationOffset + size &&
        destinationOffset < sourceOffset + size) {
      throw ArgumentError(
        'a copy within one buffer may not overlap itself: $size bytes from '
        '$sourceOffset to $destinationOffset',
      );
    }
    _record(() {
      checkUnmapped(source);
      checkUnmapped(destination);
      _bytes(to).setAll(0, _bytes(from));
    });
  }

  @override
  void clearBuffer(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _features.require(DeviceFeature.bufferCopy, backend: cpuBackendName);
    requireBufferUsage(buffer, BufferUsage.copyDestination, 'a clear');
    final range = rangeOf(
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
    if (range.lengthInBytes % 4 != 0) {
      throw ArgumentError.value(
        range.lengthInBytes,
        'sizeInBytes',
        'must be a multiple of four',
      );
    }
    _record(() {
      checkUnmapped(buffer);
      _bytes(range).fillRange(0, range.lengthInBytes, 0);
    });
  }

  @override
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _features.require(DeviceFeature.textureCopy, backend: cpuBackendName);
    final a = source.texture;
    final b = destination.texture;
    requireTextureUsage(a, TextureUsage.copySource, 'a copy from it');
    requireTextureUsage(b, TextureUsage.copyDestination, 'a copy into it');
    if (_linear(a.format) != _linear(b.format) ||
        a.sampleCount != b.sampleCount) {
      throw ArgumentError(
        'a texture copy needs one format (or two differing only in sRGB) and '
        'one sample count: ${a.format.name} x${a.sampleCount} into '
        '${b.format.name} x${b.sampleCount}',
      );
    }
    final from = _box(source, width, height, depthOrArrayLayers);
    final to = _box(destination, width, height, depthOrArrayLayers);
    _record(() {
      // Read every plane first, so a copy between two regions of one
      // texture reads what was there before rather than what it just wrote.
      final read =
          <({Float32List color, Float32List? depth, Uint8List? stencil})>[
            for (final plane in from)
              _cut(plane, source.x, source.y, width, height),
          ];
      for (var z = 0; z < to.length; z++) {
        _paste(to[z], destination.x, destination.y, width, height, read[z]);
      }
    });
  }

  @override
  void copyBufferToTexture(
    StorageBuffer source,
    BufferTextureLayout layout,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _features.require(DeviceFeature.bufferTextureCopy, backend: cpuBackendName);
    requireBufferUsage(source, BufferUsage.copySource, 'a copy from it');
    final texture = destination.texture;
    requireTextureUsage(
      texture,
      TextureUsage.copyDestination,
      'a copy into it',
    );
    final planes = _box(destination, width, height, depthOrArrayLayers);
    final stride = _checkLayout(
      layout,
      source,
      texture.format,
      width,
      height,
      depthOrArrayLayers,
    );
    _record(() {
      checkUnmapped(source);
      for (var z = 0; z < planes.length; z++) {
        writeTexels(
          planes[z],
          texture.format,
          bytesOf(source),
          layout.offsetInBytes + z * stride,
          x: destination.x,
          y: destination.y,
          width: width,
          height: height,
          bytesPerRow: layout.bytesPerRow,
        );
      }
    });
  }

  @override
  void copyTextureToBuffer(
    TextureCopyLocation source,
    StorageBuffer destination,
    BufferTextureLayout layout, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _features.require(DeviceFeature.bufferTextureCopy, backend: cpuBackendName);
    requireBufferUsage(
      destination,
      BufferUsage.copyDestination,
      'a copy into it',
    );
    final texture = source.texture;
    requireTextureUsage(texture, TextureUsage.copySource, 'a copy from it');
    final planes = _box(source, width, height, depthOrArrayLayers);
    final stride = _checkLayout(
      layout,
      destination,
      texture.format,
      width,
      height,
      depthOrArrayLayers,
    );
    _record(() {
      checkUnmapped(destination);
      for (var z = 0; z < planes.length; z++) {
        readTexels(
          planes[z],
          texture.format,
          bytesOf(destination),
          layout.offsetInBytes + z * stride,
          x: source.x,
          y: source.y,
          width: width,
          height: height,
          bytesPerRow: layout.bytesPerRow,
        );
      }
    });
  }

  // TODO(cpu): resolving a multisampled texture — this rasteriser draws one
  // sample a pixel, so there is never a multisampled texture to resolve;
  // sample storage per pixel in `CpuTexture` would unblock it.
  @override
  void resolveTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination,
  ) => _features.require(
    DeviceFeature.offscreenMultisample,
    backend: cpuBackendName,
    reason: 'it draws one sample a pixel, so there is nothing to resolve',
  );

  @override
  void submit() {
    if (_submitted) throw StateError('a transfer pass submitted twice');
    _submitted = true;
    for (final copy in _copies) {
      copy();
    }
    _copies.clear();
  }

  static Uint8List _bytes(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  /// [format] with its sRGB-ness taken away: two formats a texture copy
  /// treats as one.
  static TextureFormat _linear(TextureFormat format) => switch (format) {
    TextureFormat.r8g8b8a8UNormIntSRGB => TextureFormat.r8g8b8a8UNormInt,
    TextureFormat.b8g8r8a8UNormIntSRGB => TextureFormat.b8g8r8a8UNormInt,
    _ => format,
  };

  /// The planes a copy box of [depth] layers or slices from [location]
  /// reaches, each checked to hold the [width] × [height] rectangle.
  static List<CpuTexture> _box(
    TextureCopyLocation location,
    int width,
    int height,
    int depth,
  ) {
    final texture = location.texture.backend as CpuTexture;
    final planes = <CpuTexture>[
      for (var z = location.z; z < location.z + depth; z++)
        texture.plane(mipLevel: location.mipLevel, z: z),
    ];
    final first = planes.isEmpty ? null : planes.first;
    if (first != null &&
        (location.x < 0 ||
            location.y < 0 ||
            location.x + width > first.width ||
            location.y + height > first.height)) {
      throw RangeError(
        'a ${width}x$height box at (${location.x}, ${location.y}) does not '
        'fit in a ${first.width}x${first.height} level',
      );
    }
    return planes;
  }

  /// Bytes from one layer to the next of [layout], after checking the copy
  /// fits in [buffer].
  static int _checkLayout(
    BufferTextureLayout layout,
    StorageBuffer buffer,
    TextureFormat format,
    int width,
    int height,
    int depth,
  ) {
    if (format.isCompressed) {
      throw ArgumentError.value(
        format,
        'format',
        'is block-compressed, which this backend never holds',
      );
    }
    final planes = depthStencilPlanes(format);
    if (planes != null && planes.depth && planes.stencil) {
      throw ArgumentError.value(
        format,
        'format',
        'is a combined depth-stencil format, whose bytes have no single '
            'layout to copy',
      );
    }
    final row = width * format.bytesPerTexel;
    if (layout.bytesPerRow < row) {
      throw ArgumentError.value(
        layout.bytesPerRow,
        'bytesPerRow',
        'is shorter than one row of $width texels ($row bytes)',
      );
    }
    final rows = layout.rowsPerImage ?? height;
    if (rows < height) {
      throw ArgumentError.value(rows, 'rowsPerImage', 'is less than $height');
    }
    final stride = layout.bytesPerRow * rows;
    final needed = depth == 0 || height == 0
        ? 0
        : layout.offsetInBytes +
              (depth - 1) * stride +
              (height - 1) * layout.bytesPerRow +
              row;
    if (layout.offsetInBytes < 0 || needed > buffer.lengthInBytes) {
      throw RangeError(
        'the copy reaches byte $needed of a ${buffer.lengthInBytes}-byte '
        'buffer',
      );
    }
    return stride;
  }

  static ({Float32List color, Float32List? depth, Uint8List? stencil}) _cut(
    CpuTexture plane,
    int x,
    int y,
    int width,
    int height,
  ) {
    final color = Float32List(width * height * 4);
    final depth = plane.depth == null ? null : Float32List(width * height);
    final stencil = plane.stencil == null ? null : Uint8List(width * height);
    for (var row = 0; row < height; row++) {
      final from = (y + row) * plane.width + x;
      color.setRange(
        row * width * 4,
        (row + 1) * width * 4,
        plane.pixels,
        from * 4,
      );
      depth?.setRange(row * width, (row + 1) * width, plane.depth!, from);
      stencil?.setRange(row * width, (row + 1) * width, plane.stencil!, from);
    }
    return (color: color, depth: depth, stencil: stencil);
  }

  static void _paste(
    CpuTexture plane,
    int x,
    int y,
    int width,
    int height,
    ({Float32List color, Float32List? depth, Uint8List? stencil}) block,
  ) {
    for (var row = 0; row < height; row++) {
      final to = (y + row) * plane.width + x;
      plane.pixels.setRange(
        to * 4,
        (to + width) * 4,
        block.color,
        row * width * 4,
      );
      final depth = block.depth;
      if (depth != null) {
        plane.depthBuffer().setRange(to, to + width, depth, row * width);
      }
      final stencil = block.stencil;
      if (stencil != null) {
        plane.stencilBuffer().setRange(to, to + width, stencil, row * width);
      }
    }
  }
}
