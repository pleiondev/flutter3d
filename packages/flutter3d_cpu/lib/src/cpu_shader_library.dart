/// A library of Dart stages, by the names the engine asks for, and a linked
/// pair.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
// The generated uniform tables are shared by the engine and its backends,
// released together, and are nobody else's API since 1.0.
import 'package:flutter3d_shaders/internal.dart';
import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// A library of Dart stages, by the names the engine asks for.
final class CpuShaderLibrary with ShaderLibrary {
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
      () => wrapShader(
        backend: stage,
        name: name,
        kept: stageBindings[name],
        layouts: uniformBlocks[name],
        release: (ShaderHandle h) => forgetShader(_handles, h),
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
final class CpuLoadedShaderLibrary with ShaderLibrary, LoadedShaderLibrary {
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
      final CpuStage stage;
      try {
        stage = compiler(name, source);
      } on Object catch (error) {
        throw ShaderBundleException(
          name: bundle.name,
          reason: 'its material "$name" does not compile here: $error',
        );
      }
      compiled[name] = _MaterialStage(source, stage);
    }
    if (missing.isNotEmpty) {
      throw ShaderBundleException(
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

  /// The material sources [bundle] carries. A payload that is not one is
  /// already a [ShaderBundleException] naming the bundle, thrown by
  /// [decodeMaterialSection] itself, so it passes through as it is.
  static Map<String, String> _sources(ShaderBundle bundle) =>
      decodeMaterialSection(bundle);

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
            () => wrapShader(
              // A compiled stage that is a vertex stage too — a material's
              // `vertex` block, version 2 — is handed out as one.
              backend: material.inner.vertex != null
                  ? CpuStage.vertex(_MaterialVertexStage(material))
                  : CpuStage.fragment(material),
              name: name,
              release: (ShaderHandle h) {
                forgetShader(_materialHandles, h);
                _handedOut.remove(h.name);
              },
            ),
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
      throw ShaderBundleException(
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
///
/// **A vertex stage too — 1.0, the language's `vertex` block.** A compiled
/// `CpuStage.vertex` is handed out as a vertex stage (a material's `vertex`
/// block), and a `CpuStage.fragment` as a fragment stage.
typedef CpuMaterialCompiler = CpuStage Function(String stage, String source);

/// A compiled material stage a reload can point at new code under the handle
/// already handed out.
final class _MaterialStage extends CpuFragmentShader {
  _MaterialStage(this.source, this.inner);

  String source;

  /// What the compiler made: a fragment stage, or a vertex stage for a
  /// material's `vertex` block.
  CpuStage inner;

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      switch (inner.fragment) {
        final CpuFragmentShader fragment => fragment.run(v, bindings, c),
        null => throw StateError('this material stage is a vertex stage'),
      };
}

/// A compiled material's vertex stage, through the same reloadable holder:
/// a reload that points [_MaterialStage.inner] at new code moves the vertex
/// stage already handed out.
final class _MaterialVertexStage extends CpuVertexShaderByIndex {
  _MaterialVertexStage(this._material);

  final _MaterialStage _material;

  CpuVertexShader get _inner => _material.inner.vertex!;

  @override
  int get varyingCount => _inner.varyingCount;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List varyings) =>
      _inner.run(a, bindings, varyings);

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings bindings,
    Float32List varyings,
  ) => switch (_inner) {
    final CpuVertexShaderByIndex byIndex => byIndex.runAt(
      vertexIndex,
      instanceIndex,
      a,
      bindings,
      varyings,
    ),
    final plain => plain.run(a, bindings, varyings),
  };
}

/// A vertex and a fragment stage, paired.
final class CpuPipeline {
  const CpuPipeline(this.vertex, this.fragment, this.layout);
  final CpuVertexShader vertex;
  final CpuFragmentShader fragment;

  /// Where the vertex stage's inputs come from, or null to read one
  /// interleaved buffer in shader order — see `CpuEncoder._drawOnce`.
  final VertexLayoutDescriptor? layout;
}
