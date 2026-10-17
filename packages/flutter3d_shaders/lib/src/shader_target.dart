/// The languages a stage is compiled to, beside SPIR-V.
library;

/// What a stage's SPIR-V is translated into for a backend: WGSL for
/// WebGPU, Metal's shading language, HLSL, a GLSL dialect, or nothing — the
/// SPIR-V itself, for a backend that loads it (Vulkan).
///
/// **An open set** (S0): a class with constants rather than an enum, so a
/// target a later minor adds breaks no `switch` a backend wrote. [name] is
/// what a bundle section or a build script writes for it, and [byName]
/// reads it back.
final class ShaderTarget {
  const ShaderTarget._(this.name, this.extension);

  /// The SPIR-V alone: no text is made.
  static const ShaderTarget spirv = ShaderTarget._('spirv', null);

  /// WebGPU's language, checked by reading it back.
  static const ShaderTarget wgsl = ShaderTarget._('wgsl', 'wgsl');

  /// Metal's shading language.
  static const ShaderTarget msl = ShaderTarget._('msl', 'metal');

  /// Direct3D's language, shader model 5.1 and later.
  static const ShaderTarget hlsl = ShaderTarget._('hlsl', 'hlsl');

  /// GLSL, as the translator writes it for the stage's kind.
  static const ShaderTarget glsl = ShaderTarget._('glsl', 'glsl');

  /// Every target this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<ShaderTarget> values = <ShaderTarget>[
    spirv,
    wgsl,
    msl,
    hlsl,
    glsl,
  ];

  /// The target called [name], or null for one this version does not know.
  static ShaderTarget? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  /// The file extension the translator reads the target from, or null for
  /// [spirv], which is translated into nothing.
  final String? extension;

  @override
  String toString() => 'ShaderTarget.$name';
}
