/// A bundle loaded from bytes on WebGL2: the browser compiles the GLSL ES
/// text in the bundle's `webgl` section, on first use, as the engine's own
/// library does.
///
/// **No SDK check here, and that is not an omission.** The section is source
/// text and the compiler is the browser the application is running in, so
/// there is no ahead-of-time artefact for a Flutter version to have moved.
/// What this backend refuses is a bundle with no section for it, and a
/// section that is not the document `webgl_bundle_section.dart` describes.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:web/web.dart' as web;

import 'webgl_bundle_section.dart';
import 'webgl_shaders.dart';

/// A [LoadedShaderLibrary] over sources a bundle carried.
///
/// Handles keep their identity across [reload] the only way GL allows: the
/// compiled object behind each handle already handed out is replaced, and
/// every program linked from the old one is forgotten through the device's
/// library so the next link uses the new code. See `WebGlShader.shader`.
final class WebGlLoadedShaderLibrary implements LoadedShaderLibrary {
  WebGlLoadedShaderLibrary._(this._gl, this._linker, this._name, this._sources);

  /// Builds the library, or refuses the bundle by name.
  ///
  /// [linker] is the device's own library, which links every pair on this
  /// backend whichever library answered the names; it is what a reload tells
  /// to forget the programs it invalidates.
  static WebGlLoadedShaderLibrary load(
    web.WebGL2RenderingContext gl,
    WebGlShaderLibrary linker,
    ByteData bytes,
  ) {
    final bundle = ShaderBundle.decode(bytes);
    return WebGlLoadedShaderLibrary._(
      gl,
      linker,
      bundle.name,
      _sourcesOf(bundle),
    );
  }

  static ShaderSources _sourcesOf(ShaderBundle bundle) {
    final section = bundle.section(ShaderBundle.webglSection);
    if (section == null) {
      throw ShaderBundleRefused(
        name: bundle.name,
        reason:
            'it has no "${ShaderBundle.webglSection}" section, so there is '
            'no GLSL for this backend to compile. Pack the bundle with the '
            'translated sources beside its other sections.',
      );
    }
    try {
      final decoded = decodeWebGlSection(section);
      return ShaderSources(decoded.vertex, decoded.fragment);
    } on FormatException catch (error) {
      throw ShaderBundleRefused(
        name: bundle.name,
        reason:
            'its "${ShaderBundle.webglSection}" section is not the JSON '
            'document this backend reads: ${error.message}',
      );
    }
  }

  final web.WebGL2RenderingContext _gl;
  final WebGlShaderLibrary _linker;
  String _name;
  ShaderSources _sources;
  final Map<String, ShaderHandle?> _handles = <String, ShaderHandle?>{};

  @override
  String get name => _name;

  @override
  ShaderHandle? operator [](String name) =>
      _handles.putIfAbsent(name, () => _compile(name));

  ShaderHandle? _compile(String name) {
    final isVertex = _sources.vertex.containsKey(name);
    final source = isVertex ? _sources.vertex[name] : _sources.fragment[name];
    if (source == null) return null;
    final shader = compileWebGlShader(_gl, name, source, isVertex: isVertex);
    return ShaderHandle(backend: WebGlShader(shader, isVertex), name: name);
  }

  @override
  void reload(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    final sources = _sourcesOf(bundle);

    // Every stage already handed out is compiled from the new text *before*
    // anything is swapped, so a stage that no longer compiles — or that the
    // new bundle dropped — refuses the whole reload and leaves the library
    // drawing what it drew. An editor rebuilding a bundle wrongly keeps its
    // picture rather than losing it.
    final fresh = <ShaderHandle, web.WebGLShader>{};
    try {
      for (final handle in _handles.values.nonNulls) {
        final stage = handle.backend as WebGlShader;
        final source = stage.isVertex
            ? sources.vertex[handle.name]
            : sources.fragment[handle.name];
        if (source == null) {
          throw ShaderBundleRefused(
            name: bundle.name,
            reason:
                'it no longer has the ${stage.isVertex ? 'vertex' : 'fragment'}'
                ' stage "${handle.name}", which is already in use',
          );
        }
        fresh[handle] = compileWebGlShader(
          _gl,
          handle.name,
          source,
          isVertex: stage.isVertex,
        );
      }
    } on StateError catch (error) {
      for (final shader in fresh.values) {
        _gl.deleteShader(shader);
      }
      throw ShaderBundleRefused(name: bundle.name, reason: error.message);
    } on ShaderBundleRefused {
      for (final shader in fresh.values) {
        _gl.deleteShader(shader);
      }
      rethrow;
    }

    // The swap. Programs first, because a program still names the old shader
    // object until it is deleted, and a deleted-while-attached shader lingers.
    _linker.forgetPrograms(fresh.keys);
    for (final entry in fresh.entries) {
      final stage = entry.key.backend as WebGlShader;
      _gl.deleteShader(stage.shader);
      stage.shader = entry.value;
    }
    // Nulls were answers about the old bundle.
    _handles.removeWhere((_, ShaderHandle? handle) => handle == null);
    _sources = sources;
    _name = bundle.name;
  }

  /// Compiled stages currently held, for the device's own count.
  int get debugTrackedResourceCount => _handles.values.nonNulls.length;

  /// Deletes every compiled stage and the programs linked from them.
  void dispose() {
    final held = _handles.values.nonNulls.toList();
    _linker.forgetPrograms(held);
    for (final handle in held) {
      _gl.deleteShader((handle.backend as WebGlShader).shader);
    }
    _handles.clear();
  }
}
