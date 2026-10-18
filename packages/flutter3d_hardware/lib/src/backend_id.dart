/// The one name a backend is matched by: [BackendId].
library;

/// A backend's id: the short, lower-case name a material compiler, a plugin
/// manifest, a shader section and a conformance report match a device by,
/// compared exactly.
///
/// **A string with its spellings written down.** An extension type over
/// `String` that implements it, so a `BackendId` passes wherever a `String`
/// is taken, compares equal to the same string, and costs nothing at run
/// time. The constants are the engine's own five; an outside backend makes
/// its own with `const BackendId('vulkan')`, and that name is fixed for good
/// once the backend ships, because every compiler and manifest written for
/// it matches it.
extension type const BackendId(String name) implements String {
  /// The software rasteriser of `flutter3d_cpu`.
  static const BackendId cpu = BackendId('cpu');

  /// Flutter GPU on Impeller, `flutter3d_impeller`.
  static const BackendId impeller = BackendId('impeller');

  /// WebGL2 in a browser, `flutter3d_webgl`.
  static const BackendId webgl = BackendId('webgl');

  /// WebGPU in a browser, `flutter3d_webgpu`.
  static const BackendId webgpu = BackendId('webgpu');

  /// wgpu-native through the sidecar library, `flutter3d_wgpu`.
  static const BackendId wgpu = BackendId('wgpu');

  /// The engine's own backends, in the order above. An outside backend is
  /// not among them and needs not be: any name is a backend's id.
  static const List<BackendId> values = <BackendId>[
    cpu,
    impeller,
    webgl,
    webgpu,
    wgpu,
  ];
}
