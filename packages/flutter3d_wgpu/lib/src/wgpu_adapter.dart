/// What the sidecar's adapter runs on, and how a caller asks for one.
///
/// Plain Dart, so the browser's stub names the same types it refuses with.
library;

/// The graphics API under the sidecar's adapter.
///
/// **An open set**, a class with constants as every growing set in the
/// engine is: a backend wgpu-native adds later is a constant, not a broken
/// `switch`. [name] is what a report writes and [byName] reads back.
final class WgpuBackend {
  const WgpuBackend._(this.name);

  /// Direct3D 12: the first choice on Windows.
  static const WgpuBackend dx12 = WgpuBackend._('dx12');

  /// Vulkan: Windows after Direct3D 12, and the first choice on Linux and
  /// Android.
  static const WgpuBackend vulkan = WgpuBackend._('vulkan');

  /// Metal: the only choice on Apple platforms.
  static const WgpuBackend metal = WgpuBackend._('metal');

  /// OpenGL or OpenGL ES: Linux and Android after Vulkan.
  static const WgpuBackend gl = WgpuBackend._('gl');

  /// Anything else wgpu-native reports; never asked for.
  static const WgpuBackend other = WgpuBackend._('other');

  /// Every backend this version names, in declaration order. A later
  /// version appends.
  static const List<WgpuBackend> values = <WgpuBackend>[
    dx12,
    vulkan,
    metal,
    gl,
    other,
  ];

  /// The backend called [name], or null for one this version does not know.
  static WgpuBackend? byName(String name) {
    for (final backend in values) {
      if (backend.name == name) return backend;
    }
    return null;
  }

  /// The stable name, and the wire name.
  final String name;

  @override
  String toString() => 'WgpuBackend.$name';
}

/// The adapter the sidecar opened: what it is called, the [backend] it
/// runs on, and whether it is a software one.
final class WgpuAdapterInfo {
  /// An adapter called [name] on [backend].
  const WgpuAdapterInfo({
    required this.name,
    required this.backend,
    required this.isFallback,
  });

  /// The adapter as it names itself.
  final String name;

  /// The graphics API it runs on: decided by the sidecar, never left to
  /// wgpu's own pick among every backend.
  final WgpuBackend backend;

  /// Whether it is a CPU adapter (WARP on Direct3D 12, llvmpipe or
  /// SwiftShader on Vulkan): what a machine without a GPU, such as a CI
  /// runner, computes on.
  final bool isFallback;

  @override
  bool operator ==(Object other) =>
      other is WgpuAdapterInfo &&
      other.name == name &&
      other.backend == backend &&
      other.isFallback == isFallback;

  @override
  int get hashCode => Object.hash(name, backend, isFallback);

  @override
  String toString() =>
      'WgpuAdapterInfo($name on ${backend.name}'
      '${isFallback ? ', software' : ''})';
}
