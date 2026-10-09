/// A bundle's stages, wrapped so nothing above names `gpu.Shader`.
library;

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
// The generated uniform tables are shared by the engine and its backends,
// released together, and are nobody else's API since 1.0.
// ignore: implementation_imports
import 'package:flutter3d_shaders/internal.dart';
// The generated uniform tables are shared by the engine and its backends,
// released together, and are nobody else's API since 1.0.
// ignore: implementation_imports
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Handles are cached per name so that two lookups of the same stage give the
/// same handle. Nothing depends on that today — unlike `TextureHandle`,
/// identity carries no contract here — but a map lookup is cheaper than an
/// allocation on a path the particle contributor takes every frame.
///
/// The engine's bundle, and any an application brought with it.
///
/// The application's are searched **first**, which is the only ordering that
/// makes them useful: a plugin shipping its own `Composite` is saying it wants
/// that one, and a lookup that found the engine's first would silently ignore
/// the file the author compiled. It is also the ordering that can go wrong
/// quietly, so it is stated here rather than left to the loop.
///
/// Why this exists at all: shaders on this backend are compiled ahead of time
/// into a bundle asset. The software rasteriser takes a Dart object and WebGL
/// takes GLSL at runtime, so on both an application can simply hand its stage
/// over — and on Impeller it could not, at all, which made "write your own post
/// effect" a thing that worked on two backends out of three.
final class GpuShaderLibrary with ShaderLibrary {
  GpuShaderLibrary(this._library, [this._extra = const <gpu.ShaderLibrary>[]]);

  final gpu.ShaderLibrary _library;
  final List<gpu.ShaderLibrary> _extra;
  final Map<String, ShaderHandle?> _handles = <String, ShaderHandle?>{};

  @override
  ShaderHandle? operator [](String name) => _handles.putIfAbsent(name, () {
    for (final library in _extra) {
      final shader = library[name];
      if (shader != null) {
        return wrapShader(backend: shader, name: name, release: _forget);
      }
    }
    final shader = _library[name];
    return shader == null
        ? null
        : wrapShader(
            backend: shader,
            name: name,
            kept: stageBindings[name],
            layouts: uniformBlocks[name],
            release: _forget,
          );
  });

  /// A disposed handle's release: the library forgets it, and flutter_gpu's
  /// library keeps the stage it owns, which the next lookup wraps again.
  void _forget(ShaderHandle handle) => forgetShader(_handles, handle);
}
