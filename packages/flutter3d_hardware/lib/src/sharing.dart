/// Textures, buffers and fences seen by two devices at once: a compute
/// device beside the one that draws, or a native API beside the engine.
///
/// **The shape in the contract before the path exists.** Zero-copy sharing
/// needs both sides: the producer exports its memory as a [NativeHandle]
/// (an `MTLTexture` or an IOSurface on Apple platforms, an
/// `AHardwareBuffer` on Android, Vulkan external memory elsewhere) and the
/// consumer imports it. wgpu-native can export a Metal texture; flutter_gpu
/// cannot import anything yet, so a texture the compute sidecar writes
/// reaches Impeller through host memory today. [SharedTexture] and
/// [SharedBuffer] choose between the two paths, so a caller writes against
/// one type and the copy disappears on the day both halves exist.
///
/// **The copy is the path conformance runs**, because it is the one every
/// device has: the producer reads its texture back and the consumer
/// overwrites its own. The zero-copy path is refused, by name and with the
/// reason, where it is demanded and missing.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show CapabilityException;
import 'package:meta/meta.dart';

import 'capabilities.dart';
import 'compute.dart';
import 'graphics_device.dart';
import 'resources.dart';
import 'texture.dart';

/// What a [NativeHandle] holds.
///
/// **An open set**: a class with constants, so a kind a later minor adds
/// (a Direct3D shared handle, a dma-buf) does not break a `switch` written
/// against this one. [name] is what a report writes and [byName] reads.
@immutable
final class NativeHandleKind {
  const NativeHandleKind._(this.name);

  /// An `id<MTLTexture>`, as a pointer.
  static const NativeHandleKind metalTexture = NativeHandleKind._(
    'metalTexture',
  );

  /// An `id<MTLBuffer>`, as a pointer.
  static const NativeHandleKind metalBuffer = NativeHandleKind._('metalBuffer');

  /// An `IOSurfaceRef`, which two Metal devices, or Metal and OpenGL, can
  /// each make a texture over.
  static const NativeHandleKind ioSurface = NativeHandleKind._('ioSurface');

  /// An `id<MTLSharedEvent>`, as a pointer: a fence on Apple platforms.
  static const NativeHandleKind metalSharedEvent = NativeHandleKind._(
    'metalSharedEvent',
  );

  /// An `AHardwareBuffer*`, which Vulkan and GLES on Android both import.
  static const NativeHandleKind androidHardwareBuffer = NativeHandleKind._(
    'androidHardwareBuffer',
  );

  /// Vulkan device memory exported as a POSIX file descriptor
  /// (`VK_KHR_external_memory_fd`).
  static const NativeHandleKind vulkanMemoryFd = NativeHandleKind._(
    'vulkanMemoryFd',
  );

  /// Vulkan device memory exported as a Win32 handle
  /// (`VK_KHR_external_memory_win32`).
  static const NativeHandleKind vulkanMemoryWin32 = NativeHandleKind._(
    'vulkanMemoryWin32',
  );

  /// A Vulkan semaphore exported as a POSIX file descriptor
  /// (`VK_KHR_external_semaphore_fd`).
  static const NativeHandleKind vulkanSemaphoreFd = NativeHandleKind._(
    'vulkanSemaphoreFd',
  );

  /// A Vulkan semaphore exported as a Win32 handle
  /// (`VK_KHR_external_semaphore_win32`).
  static const NativeHandleKind vulkanSemaphoreWin32 = NativeHandleKind._(
    'vulkanSemaphoreWin32',
  );

  /// Every kind this version names, in declaration order. A later version
  /// appends.
  static const List<NativeHandleKind> values = <NativeHandleKind>[
    metalTexture,
    metalBuffer,
    ioSurface,
    metalSharedEvent,
    androidHardwareBuffer,
    vulkanMemoryFd,
    vulkanMemoryWin32,
    vulkanSemaphoreFd,
    vulkanSemaphoreWin32,
  ];

  /// The kind called [name], or null for one this version does not know.
  static NativeHandleKind? byName(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'NativeHandleKind.$name';
}

/// A native object one device hands another, by [kind] and [address].
///
/// **Borrowed, never owned.** The device that exported it keeps the object
/// alive for as long as the texture, buffer or fence it came from; an
/// importer holds a reference of its own through the API it imported with.
/// Nothing here frees it.
@immutable
final class NativeHandle {
  const NativeHandle(this.kind, this.address);

  /// What [address] is.
  final NativeHandleKind kind;

  /// The pointer, or the file descriptor or Win32 handle, as an integer.
  final int address;

  @override
  bool operator ==(Object other) =>
      other is NativeHandle && other.kind == kind && other.address == address;

  @override
  int get hashCode => Object.hash(kind, address);

  @override
  String toString() =>
      'NativeHandle(${kind.name}, 0x${address.toRadixString(16)})';
}

/// A timeline fence: one device signals a value when the work submitted
/// before it is done, and another waits for that value before the work
/// submitted after it starts — `DeviceFeature.sharedFences`.
///
/// [backend] is the backend's own object, as for every handle.
final class GpuFence {
  GpuFence._(this._release, {required this.backend});

  final void Function(GpuFence)? _release;

  /// The backend's own fence: an `MTLSharedEvent`, a Vulkan timeline
  /// semaphore.
  final Object backend;

  /// Gives this back to the device that made it, once, as every handle's
  /// `dispose` does.
  void dispose() {
    assert(
      !_disposed || _release == null,
      '$this was disposed twice. A handle has one owner, and only the owner '
      'disposes it.',
    );
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;
}

/// A [GpuFence] over a backend's own [backend] fence, for a backend; see
/// `wrapStorageBuffer`.
GpuFence wrapFence({required Object backend, GraphicsDevice? owner}) =>
    GpuFence._(owner?.releaseFence, backend: backend);

/// How a [SharedTexture] or [SharedBuffer] gets the producer's bytes to the
/// consumer.
///
/// **An open set**, as every set that may grow is here.
@immutable
final class SharingMode {
  const SharingMode._(this.name);

  /// One allocation both devices see: the producer exports it, the
  /// consumer imports it, and a [GpuFence] orders their work.
  static const SharingMode zeroCopy = SharingMode._('zeroCopy');

  /// Two allocations, one on each device, and the bytes carried between
  /// them through host memory on [SharedTexture.publish]. The path every
  /// pair of devices has.
  static const SharingMode hostCopy = SharingMode._('hostCopy');

  /// Every mode this version names. A later version appends.
  static const List<SharingMode> values = <SharingMode>[zeroCopy, hostCopy];

  /// The mode called [name], or null for one this version does not know.
  static SharingMode? byName(String name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'SharingMode.$name';
}

/// A [SharedTexture] or [SharedBuffer] that could not be made in the mode
/// it was asked for: zero copy demanded between two devices that have no
/// [NativeHandleKind] in common.
///
/// **A refusal, and only where a caller demanded the mode.** Without a
/// demand the share falls back to [SharingMode.hostCopy], which every pair
/// of devices has, and nothing is thrown.
final class SharingException extends CapabilityException {
  const SharingException({
    required this.mode,
    required this.producer,
    required this.consumer,
    required this.reason,
  });

  /// What was demanded.
  final SharingMode mode;

  /// The producing device's backend, as a person names it.
  final String producer;

  /// The consuming device's backend.
  final String consumer;

  /// Why the two cannot share that way: which half is missing.
  final String reason;

  @override
  String get message =>
      'sharing from $producer to $consumer by ${mode.name} is refused: '
      '$reason';

  @override
  String toString() => 'SharingException: $message';
}

/// The kind both devices can share a texture (or buffer) through without a
/// copy: one [producer] exports and [consumer] imports, or null when there
/// is none.
NativeHandleKind? _commonKind(
  GraphicsDevice producer,
  GraphicsDevice consumer,
  DeviceFeature feature,
) {
  if (!producer.features.has(feature) || !consumer.features.has(feature)) {
    return null;
  }
  final theirs = consumer.shareableKinds;
  for (final kind in producer.shareableKinds) {
    if (theirs.contains(kind)) return kind;
  }
  return null;
}

String _whyNot(
  GraphicsDevice producer,
  GraphicsDevice consumer,
  DeviceFeature feature,
) {
  final halves = <String>[
    if (!producer.features.has(feature))
      '${producer.backendName} cannot export one (no ${feature.name})',
    if (!consumer.features.has(feature))
      '${consumer.backendName} cannot import one (no ${feature.name})',
  ];
  if (halves.isNotEmpty) return halves.join(', and ');
  return 'they have no native handle kind in common: '
      '${producer.backendName} shares '
      '${producer.shareableKinds.map((k) => k.name).join(', ')}, '
      '${consumer.backendName} '
      '${consumer.shareableKinds.map((k) => k.name).join(', ')}';
}

/// A texture one device writes and another reads: the same memory where
/// both can share it ([SharingMode.zeroCopy]), a copy through host memory
/// where they cannot ([SharingMode.hostCopy]).
///
/// The producer draws or dispatches into [producerTexture]; [publish] makes
/// what it wrote visible in [consumerTexture], which the consumer samples.
/// Zero copy, [publish] signals the fence on the producer's queue and waits
/// on the consumer's; with the copy, it reads the producer's texture back
/// and overwrites the consumer's, so both must be RGBA8 (`readbackFormats`)
/// and only the base level travels.
final class SharedTexture {
  SharedTexture._({
    required this.producer,
    required this.consumer,
    required this.producerTexture,
    required this.consumerTexture,
    required this.mode,
    this.fence,
    this.consumerFence,
  });

  /// A texture shaped like [descriptor] that [producer] writes and
  /// [consumer] reads.
  ///
  /// Zero copy when both devices have `DeviceFeature.sharedTextures` and a
  /// [NativeHandleKind] in common, and `sharedFences` to order them; the
  /// copy through host memory otherwise. [demand] insists on one mode and
  /// throws [SharingException], saying which half is missing, where it does
  /// not fit.
  static SharedTexture create({
    required GraphicsDevice producer,
    required GraphicsDevice consumer,
    required TextureDescriptor descriptor,
    SharingMode? demand,
  }) {
    final kind = _commonKind(producer, consumer, DeviceFeature.sharedTextures);
    final fenced =
        producer.features.has(DeviceFeature.sharedFences) &&
        consumer.features.has(DeviceFeature.sharedFences);
    final zeroCopy = kind != null && fenced;
    if (demand == SharingMode.zeroCopy && !zeroCopy) {
      throw SharingException(
        mode: SharingMode.zeroCopy,
        producer: producer.backendName,
        consumer: consumer.backendName,
        reason: kind == null
            ? _whyNot(producer, consumer, DeviceFeature.sharedTextures)
            : 'one of them cannot share a fence (no shared-fences)',
      );
    }
    if (demand != null &&
        demand != SharingMode.zeroCopy &&
        demand != SharingMode.hostCopy) {
      throw SharingException(
        mode: demand,
        producer: producer.backendName,
        consumer: consumer.backendName,
        reason: 'this version shares by zeroCopy or hostCopy only',
      );
    }
    final made = producer.createTexture(descriptor);
    if (zeroCopy && demand != SharingMode.hostCopy) {
      final handle = producer.exportTexture(made, kind: kind);
      final fence = producer.createFence();
      return SharedTexture._(
        producer: producer,
        consumer: consumer,
        producerTexture: made,
        consumerTexture: consumer.importTexture(handle, descriptor),
        mode: SharingMode.zeroCopy,
        fence: fence,
        consumerFence: consumer.importFence(producer.exportFence(fence)),
      );
    }
    return SharedTexture._(
      producer: producer,
      consumer: consumer,
      producerTexture: made,
      consumerTexture: consumer.createTexture(descriptor),
      mode: SharingMode.hostCopy,
    );
  }

  /// The device that writes.
  final GraphicsDevice producer;

  /// The device that reads.
  final GraphicsDevice consumer;

  /// The texture as [producer] sees it.
  final TextureHandle producerTexture;

  /// The texture as [consumer] sees it: the same memory zero copy, its own
  /// allocation with the copy.
  final TextureHandle consumerTexture;

  /// Which path this share took.
  final SharingMode mode;

  /// The fence on [producer]'s side, zero copy; null with the copy.
  final GpuFence? fence;

  /// The same fence as [consumer] imported it; null with the copy.
  final GpuFence? consumerFence;

  int _published = 0;

  /// How many times [publish] has run: the fence value the last one
  /// signalled.
  int get published => _published;

  /// Makes what [producer] has submitted into [producerTexture] so far
  /// visible to [consumer]'s next pass.
  ///
  /// Zero copy, this signals the next value on [producer]'s queue and has
  /// [consumer]'s queue wait for it, and completes at once. With the copy,
  /// it completes when the bytes are in [consumerTexture].
  Future<void> publish() async {
    _published += 1;
    if (mode == SharingMode.zeroCopy) {
      producer.signalFence(fence!, _published);
      consumer.waitFence(consumerFence!, _published);
      return;
    }
    final ByteData rgba = await producer.readback(producerTexture);
    await consumer.overwriteTexture(consumerTexture, rgba);
  }

  /// Gives both textures, and the fence, back to their devices.
  void dispose() {
    consumerFence?.dispose();
    fence?.dispose();
    if (!identical(consumerTexture, producerTexture)) {
      consumerTexture.dispose();
    }
    producerTexture.dispose();
  }
}

/// [SharedTexture] for a buffer: one [producer] writes in a compute pass and
/// [consumer] reads, bound as storage or as vertices.
final class SharedBuffer {
  SharedBuffer._({
    required this.producer,
    required this.consumer,
    required this.producerBuffer,
    required this.consumerBuffer,
    required this.mode,
    this.fence,
    this.consumerFence,
  });

  /// A buffer described by [descriptor] that [producer] writes and
  /// [consumer] reads; see [SharedTexture.create] for how the mode is
  /// chosen. With the copy, the producer's buffer is made host-readable and
  /// the consumer's a copy destination, beside the usages asked for.
  static SharedBuffer create({
    required GraphicsDevice producer,
    required GraphicsDevice consumer,
    required BufferDescriptor descriptor,
    SharingMode? demand,
  }) {
    final kind = _commonKind(producer, consumer, DeviceFeature.sharedBuffers);
    final fenced =
        producer.features.has(DeviceFeature.sharedFences) &&
        consumer.features.has(DeviceFeature.sharedFences);
    final zeroCopy = kind != null && fenced;
    if (demand == SharingMode.zeroCopy && !zeroCopy) {
      throw SharingException(
        mode: SharingMode.zeroCopy,
        producer: producer.backendName,
        consumer: consumer.backendName,
        reason: kind == null
            ? _whyNot(producer, consumer, DeviceFeature.sharedBuffers)
            : 'one of them cannot share a fence (no shared-fences)',
      );
    }
    if (zeroCopy && demand != SharingMode.hostCopy) {
      final made = producer.createBuffer(descriptor);
      final handle = producer.exportBuffer(made, kind: kind);
      final fence = producer.createFence();
      return SharedBuffer._(
        producer: producer,
        consumer: consumer,
        producerBuffer: made,
        consumerBuffer: consumer.importBuffer(handle, descriptor),
        mode: SharingMode.zeroCopy,
        fence: fence,
        consumerFence: consumer.importFence(producer.exportFence(fence)),
      );
    }
    return SharedBuffer._(
      producer: producer,
      consumer: consumer,
      producerBuffer: producer.createBuffer(
        BufferDescriptor(
          lengthInBytes: descriptor.lengthInBytes,
          usage: descriptor.usage | BufferUsage.hostReadable,
          label: descriptor.label,
        ),
      ),
      consumerBuffer: consumer.createBuffer(
        BufferDescriptor(
          lengthInBytes: descriptor.lengthInBytes,
          usage: descriptor.usage | BufferUsage.copyDestination,
          label: descriptor.label,
        ),
      ),
      mode: SharingMode.hostCopy,
    );
  }

  /// The device that writes.
  final GraphicsDevice producer;

  /// The device that reads.
  final GraphicsDevice consumer;

  /// The buffer as [producer] sees it.
  final StorageBuffer producerBuffer;

  /// The buffer as [consumer] sees it.
  final StorageBuffer consumerBuffer;

  /// Which path this share took.
  final SharingMode mode;

  /// The fence on [producer]'s side, zero copy; null with the copy.
  final GpuFence? fence;

  /// The same fence as [consumer] imported it; null with the copy.
  final GpuFence? consumerFence;

  int _published = 0;

  /// How many times [publish] has run.
  int get published => _published;

  /// Makes what [producer] has submitted into [producerBuffer] so far
  /// visible to [consumer]'s next pass; see [SharedTexture.publish].
  Future<void> publish() async {
    _published += 1;
    if (mode == SharingMode.zeroCopy) {
      producer.signalFence(fence!, _published);
      consumer.waitFence(consumerFence!, _published);
      return;
    }
    final bytes = await producer.readBuffer(producerBuffer);
    consumer.writeBuffer(consumerBuffer, 0, bytes);
  }

  /// Gives both buffers, and the fence, back to their devices.
  void dispose() {
    consumerFence?.dispose();
    fence?.dispose();
    if (!identical(consumerBuffer, producerBuffer)) consumerBuffer.dispose();
    producerBuffer.dispose();
  }
}
