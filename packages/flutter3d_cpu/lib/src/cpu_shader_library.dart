/// A library of Dart stages, by the names the engine asks for, and a linked
/// pair.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/stage_bindings.dart';
import 'package:flutter3d_shaders/uniform_blocks.dart' show uniformBlocks;
import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// A library of Dart stages, by the names the engine asks for.
final class CpuShaderLibrary implements ShaderLibrary {
  CpuShaderLibrary(Map<String, CpuStage> stages)
    : stages = Map<String, CpuStage>.unmodifiable(stages);

  final Map<String, CpuStage> stages;

  /// Cached per name so that a handle keeps its identity — the promise a
  /// [LoadedShaderLibrary] makes rests on it, and there is no reason the
  /// device's own library should answer differently.
  final Map<String, ShaderHandle> _handles = <String, ShaderHandle>{};

  @override
  ShaderHandle? operator [](String name) {
    final stage = stages[name];
    if (stage == null) return null;
    return _handles.putIfAbsent(
      name,
      // The table is the GLSL stage's, and the Dart stage standing in for it
      // is held to the same bindings, so a draw binds the same slots here as
      // on the GPU.
      () => ShaderHandle(
        backend: stage,
        name: name,
        kept: stageBindings[name],
        layouts: uniformBlocks[name],
      ),
    );
  }
}

/// A bundle loaded from bytes, on the backend that compiles nothing.
///
/// **The built-in stages, the material language, and a refusal by name for
/// anything else.** A bundle carries compiled sections for the hardware
/// backends and nothing this rasteriser could run; what it does carry is the
/// list of names it claims and, for a stage written in the engine's material
/// language, that stage's source — `P8`. So a loaded library here answers
/// each name with the Dart stage the device already has, or with what the
/// device's [CpuMaterialCompiler] makes of the source, which is what lets the
/// same application code load a bundle on every backend. A bundle naming a
/// stage neither can answer is refused at load, naming the stages, rather
/// than accepted and answered with nothing. An application that wants its
/// own look here in anything but the language writes it in Dart and hands it
/// to `CpuDevice.shaders`; see `test/custom_material_test.dart`.
final class CpuLoadedShaderLibrary implements LoadedShaderLibrary {
  CpuLoadedShaderLibrary._(this._own, this._bundle, this._compiler);

  /// Builds the library, or refuses the bundle by name.
  static CpuLoadedShaderLibrary load(
    ShaderLibrary own,
    ByteData bytes, {
    CpuMaterialCompiler? compiler,
  }) {
    final bundle = ShaderBundle.decode(bytes);
    final library = CpuLoadedShaderLibrary._(own, bundle, compiler);
    library._materials.addAll(
      library._compile(bundle, const <String, _MaterialStage>{}),
    );
    return library;
  }

  /// The material stages [bundle] needs that the device has no Dart for,
  /// compiled — a stage of [kept] whose source did not change is kept as it
  /// is — or a refusal naming every stage nothing can answer. Nothing is
  /// replaced here, so a refused reload leaves the library as it was.
  Map<String, _MaterialStage> _compile(
    ShaderBundle bundle,
    Map<String, _MaterialStage> kept,
  ) {
    final sources = _sources(bundle);
    final compiler = _compiler;
    final compiled = <String, _MaterialStage>{};
    final missing = <String>[];
    for (final name in bundle.names) {
      if (_own[name] != null) continue;
      final source = sources[name];
      if (source == null || compiler == null) {
        missing.add(name);
        continue;
      }
      final previous = kept[name];
      if (previous != null && previous.source == source) {
        compiled[name] = previous;
        continue;
      }
      final CpuFragmentShader stage;
      try {
        stage = compiler(name, source);
      } on Object catch (error) {
        throw ShaderBundleRefused(
          name: bundle.name,
          reason: 'its material "$name" does not compile here: $error',
        );
      }
      compiled[name] = _MaterialStage(source, stage);
    }
    if (missing.isNotEmpty) {
      throw ShaderBundleRefused(
        name: bundle.name,
        reason:
            'the software rasteriser runs Dart stages only and has none for '
            '${missing.join(', ')}. Hand a Dart stage of that name to '
            'CpuDevice.shaders, write the stage in the material language and '
            'give the device a materialCompiler, or leave this backend out of '
            'the bundle.',
      );
    }
    return compiled;
  }

  static Map<String, String> _sources(ShaderBundle bundle) {
    try {
      return decodeMaterialSection(bundle);
    } on FormatException catch (error) {
      throw ShaderBundleRefused(name: bundle.name, reason: error.message);
    }
  }

  final ShaderLibrary _own;
  ShaderBundle _bundle;
  final CpuMaterialCompiler? _compiler;

  /// The material stages, by name. A reload replaces what each runs, not the
  /// stage itself, so a handle already handed out runs the new source.
  final Map<String, _MaterialStage> _materials = <String, _MaterialStage>{};
  final Map<String, ShaderHandle> _materialHandles = <String, ShaderHandle>{};

  /// Every name answered with a handle so far — what a reload may not drop.
  ///
  /// Kept here rather than read off `_own`, because the device's library
  /// answers every built-in name whether or not this bundle ever did: what
  /// the contract protects is a handle *this* library handed out.
  final Set<String> _handedOut = <String>{};

  @override
  String get name => _bundle.name;

  /// The device's own handle for a built-in name the bundle claims, so
  /// identity is shared with the built-in library and survives any reload
  /// for free; and for a material stage, one handle for the library's life.
  @override
  ShaderHandle? operator [](String name) {
    if (!_bundle.names.contains(name)) return null;
    final material = _materials[name];
    final handle = material == null
        ? _own[name]
        : _materialHandles.putIfAbsent(
            name,
            () =>
                ShaderHandle(backend: CpuStage.fragment(material), name: name),
          );
    if (handle != null) _handedOut.add(name);
    return handle;
  }

  @override
  void refresh(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    // Both checked before anything is replaced: a refused reload leaves the
    // library as it was, which is the contract.
    final compiled = _compile(bundle, _materials);
    final dropped = _handedOut
        .where((String n) => !bundle.names.contains(n))
        .toList();
    if (dropped.isNotEmpty) {
      throw ShaderBundleRefused(
        name: bundle.name,
        reason:
            'it no longer has the stage${dropped.length == 1 ? '' : 's'} '
            '${dropped.map((String n) => '"$n"').join(', ')}, which '
            '${dropped.length == 1 ? 'is' : 'are'} already in use',
      );
    }
    _bundle = bundle;
    for (final MapEntry(key: name, value: stage) in compiled.entries) {
      final existing = _materials[name];
      if (existing == null) {
        _materials[name] = stage;
      } else if (!identical(existing, stage)) {
        existing
          ..source = stage.source
          ..inner = stage.inner;
      }
    }
  }
}

/// Turns a stage written in the engine's material language into a Dart stage
/// — `P8`: [stage] is its name in the bundle, [source] its text from the
/// bundle's `ShaderBundle.materialSection`.
///
/// Handed in rather than built in, because the language lives in
/// `flutter3d_core` and this package does not depend on it;
/// `flutter3d_testing`'s `materialLanguageCompiler` is one that does. Throws
/// to refuse a source, and the throw becomes the bundle's refusal.
typedef CpuMaterialCompiler =
    CpuFragmentShader Function(String stage, String source);

/// A compiled material stage a reload can point at new code under the handle
/// already handed out.
final class _MaterialStage implements CpuFragmentShader {
  _MaterialStage(this.source, this.inner);

  String source;
  CpuFragmentShader inner;

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      inner.run(v, bindings, c);
}

/// A vertex and a fragment stage, paired.
final class CpuPipeline {
  const CpuPipeline(this.vertex, this.fragment, this.layout);
  final CpuVertexShader vertex;
  final CpuFragmentShader fragment;

  /// Where the vertex stage's inputs come from, or null to read one
  /// interleaved buffer in shader order — see `CpuEncoder._drawOnce`.
  final VertexLayoutSpec? layout;
}
