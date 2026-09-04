/// A library of Dart stages, by the names the engine asks for, and a linked
/// pair.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

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
      () => ShaderHandle(backend: stage, name: name),
    );
  }
}

/// A bundle loaded from bytes, on the backend that compiles nothing.
///
/// **Only the built-in stages, and a refusal by name for anything else.** A
/// bundle carries compiled sections for the hardware backends and nothing
/// this rasteriser could run; what it does carry is the list of names it
/// claims. So a loaded library here answers each of those names with the Dart
/// stage the device already has — which is what lets the same application
/// code load a bundle on every backend — and a bundle naming a stage this
/// backend has no Dart for is refused at load, naming the stages, rather than
/// accepted and answered with nothing. An application that wants its own look
/// here writes it in Dart and hands it to `CpuDevice.shaders`; see
/// `test/custom_material_test.dart`.
final class CpuLoadedShaderLibrary implements LoadedShaderLibrary {
  CpuLoadedShaderLibrary._(this._own, this._bundle);

  /// Builds the library, or refuses the bundle by name.
  static CpuLoadedShaderLibrary load(ShaderLibrary own, ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    _requireEveryStage(own, bundle);
    return CpuLoadedShaderLibrary._(own, bundle);
  }

  static void _requireEveryStage(ShaderLibrary own, ShaderBundle bundle) {
    final missing = bundle.names.where((String n) => own[n] == null).toList();
    if (missing.isNotEmpty) {
      throw ShaderBundleRefused(
        name: bundle.name,
        reason:
            'the software rasteriser runs Dart stages only and has none for '
            '${missing.join(', ')}. Hand a Dart stage of that name to '
            'CpuDevice.shaders, or leave this backend out of the bundle.',
      );
    }
  }

  final ShaderLibrary _own;
  ShaderBundle _bundle;

  /// Every name answered with a handle so far — what a reload may not drop.
  ///
  /// Kept here rather than read off `_own`, because the device's library
  /// answers every built-in name whether or not this bundle ever did: what
  /// the contract protects is a handle *this* library handed out.
  final Set<String> _handedOut = <String>{};

  @override
  String get name => _bundle.name;

  /// The device's own handle for a name the bundle claims, so identity is
  /// shared with the built-in library and survives any reload for free.
  @override
  ShaderHandle? operator [](String name) {
    if (!_bundle.names.contains(name)) return null;
    final handle = _own[name];
    if (handle != null) _handedOut.add(name);
    return handle;
  }

  @override
  void refresh(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    // Both checked before anything is replaced: a refused reload leaves the
    // library as it was, which is the contract.
    _requireEveryStage(_own, bundle);
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
  }
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
