/// A bundle loaded from bytes on WebGPU: the browser compiles the WGSL in the
/// bundle's `webgpu` section, on first use, as the engine's own library does.
///
/// **No SDK check here, and that is not an omission.** The section is source
/// text and the compiler is the browser the application is running in, so there
/// is no ahead-of-time artefact for a Flutter version to have moved — which is
/// the reason `ShaderBundle.webgpuSection` gives for leaving `sdk` out of its
/// own story. What this backend refuses is a bundle with no section for it, a
/// section that is not the document `webgpu_bundle_section.dart` describes, and
/// a section written to a version of that document this reader does not know.
///
/// ## Why the version is the section's and not the container's
///
/// `ShaderBundle.formatVersion` is a fact about the header and the section
/// table, and the three backends already shipped read it unchanged however this
/// section grows. The reflection's shape is a fact between one packer and one
/// backend, and it will move again — a bind group index, a member size, a
/// texture dimension the enum does not yet have — while the container stands
/// still. Raising the container's version to say the reflection changed would
/// refuse every bundle in existence to Impeller, WebGL2 and the software
/// rasteriser, none of which can even see this section. So the version is
/// inside the document, this file owns it, and a mismatch refuses the bundle by
/// name and leaves the library drawing what it drew.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart';
import 'webgpu_shaders.dart';

/// A [LoadedShaderLibrary] over the WGSL a bundle carried.
///
/// Handles keep their identity across [refresh] the only way WebGPU allows: a
/// `GPUShaderModule` is compiled once from one text and cannot be edited, so
/// the code behind each handle already handed out is replaced instead. See
/// [WebGpuShader.code].
final class WebGpuLoadedShaderLibrary implements LoadedShaderLibrary {
  WebGpuLoadedShaderLibrary._(this._compiler, this._name, this._stages);

  /// The shape of the section document this reader knows.
  ///
  /// Read by whoever packs a bundle for this backend: a packer writing a
  /// different shape must say so under `"version"`, and this reader will refuse
  /// it by name rather than compile half a reflection into a pipeline that
  /// binds the right bytes to the wrong slot.
  ///
  /// **One means the shape that shipped**, which is why a document with no
  /// `"version"` at all is read as one rather than refused: the codec was
  /// written before there was a second shape to distinguish it from, and every
  /// bundle packed since says exactly what it would have said.
  static const int sectionVersion = 1;

  /// Builds the library, or refuses the bundle by name.
  ///
  /// Called by the device from `loadShaders`, which owns the [compiler] because
  /// it owns the `GPUDevice`.
  static WebGpuLoadedShaderLibrary load(
    WgslModuleCompiler compiler,
    ByteData bytes,
  ) {
    final bundle = ShaderBundle.decode(bytes);
    return WebGpuLoadedShaderLibrary._(
      compiler,
      bundle.name,
      _stagesOf(bundle),
    );
  }

  static WebGpuSectionStages _stagesOf(ShaderBundle bundle) {
    final section = bundle.section(ShaderBundle.webgpuSection);
    if (section == null) {
      throw ShaderBundleRefused(
        name: bundle.name,
        reason:
            'it has no "${ShaderBundle.webgpuSection}" section, so there is '
            'no WGSL for this backend to compile. Pack the bundle with the '
            'translated sources and their reflection beside its other '
            'sections.',
      );
    }
    _refuseUnknownVersion(bundle.name, section);
    try {
      return decodeWebGpuSection(section);
    } on FormatException catch (error) {
      throw ShaderBundleRefused(
        name: bundle.name,
        reason:
            'its "${ShaderBundle.webgpuSection}" section is not the JSON '
            'document this backend reads: ${error.message}',
      );
    }
  }

  /// Refuses a section whose document says it is a shape this reader does not
  /// know.
  ///
  /// **Read separately from the stages, and on purpose.** The codec is one
  /// document the packer and this backend both agree about, so it decodes what
  /// the document holds; which versions of that document are acceptable is a
  /// policy, and the policy belongs to the reader that has to keep drawing when
  /// it says no. Threading a second value out of `decodeWebGpuSection` would
  /// put the reader's policy in the writer's file and change the shape of the
  /// generated table beside it for nothing. A second pass over the JSON costs a
  /// few milliseconds on a reload, which is a keystroke in an editor and never
  /// a frame.
  ///
  /// A section that is not JSON at all falls through silently: the decode below
  /// is the one that reports it, in the words that name the whole document
  /// rather than the one field this looked for.
  static void _refuseUnknownVersion(String bundleName, ByteData section) {
    final Object? document;
    try {
      document = jsonDecode(
        utf8.decode(
          section.buffer.asUint8List(
            section.offsetInBytes,
            section.lengthInBytes,
          ),
        ),
      );
    } on FormatException {
      return;
    }
    if (document is! Map<String, dynamic>) return;
    final said = document['version'] ?? sectionVersion;
    if (said != sectionVersion) {
      throw ShaderBundleRefused(
        name: bundleName,
        reason:
            'its "${ShaderBundle.webgpuSection}" section says it is version '
            '$said and this backend reads version $sectionVersion. The '
            'container is still format version ${ShaderBundle.formatVersion} '
            'because the other backends read their own sections unchanged; '
            'repack this one with a packer of the same age as this build.',
      );
    }
  }

  final WgslModuleCompiler _compiler;
  String _name;
  WebGpuSectionStages _stages;
  final Map<String, ShaderHandle?> _handles = <String, ShaderHandle?>{};

  @override
  String get name => _name;

  @override
  ShaderHandle? operator [](String name) =>
      _handles.putIfAbsent(name, () => _compile(name));

  ShaderHandle? _compile(String name) {
    final isVertex = _stages.vertex.containsKey(name);
    final stage = isVertex ? _stages.vertex[name] : _stages.fragment[name];
    if (stage == null) return null;
    return compileWebGpuStage(_compiler, name, stage, isVertex: isVertex);
  }

  @override
  void refresh(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    final stages = _stagesOf(bundle);

    // Every stage already handed out is compiled from the new text *before*
    // anything is swapped, so a stage that no longer compiles — or that the new
    // bundle dropped — refuses the whole reload and leaves the library drawing
    // what it drew. An editor rebuilding a bundle wrongly keeps its picture
    // rather than losing it. Dropped from the header's stage list or from the
    // section's sources, either one: the header is what the bundle claims, and
    // it is what the other backends hold a refresh to.
    final fresh = <ShaderHandle, WebGpuCode>{};
    try {
      for (final handle in _handles.values.nonNulls) {
        final shader = handle.backend as WebGpuShader;
        final stage = bundle.names.contains(handle.name)
            ? shader.isVertex
                  ? stages.vertex[handle.name]
                  : stages.fragment[handle.name]
            : null;
        if (stage == null) {
          throw ShaderBundleRefused(
            name: bundle.name,
            reason:
                'it no longer has the '
                '${shader.isVertex ? 'vertex' : 'fragment'} stage '
                '"${handle.name}", which is already in use',
          );
        }
        fresh[handle] = (
          stage: stage,
          module: _compiler.compileModule(handle.name, stage.wgsl),
        );
      }
    } on StateError catch (error) {
      // What a compiler throws for text the browser would not take. Nothing has
      // to be undone: the modules compiled so far are ordinary JavaScript
      // objects nobody else holds, and dropping the map is the whole of letting
      // them go — where the WebGL2 backend has to delete each shader it made by
      // hand before it rethrows.
      throw ShaderBundleRefused(name: bundle.name, reason: error.message);
    }

    // The swap. A `PipelineHandle` the renderer already holds keeps its own
    // pair of modules and goes on drawing the old code until it is rebuilt,
    // which is what the HAL promises: a frame between a refresh and
    // `Renderer.relinkShaders` is the old picture, not a missing one.
    for (final entry in fresh.entries) {
      (entry.key.backend as WebGpuShader).code = entry.value;
    }
    // Nulls were answers about the old bundle.
    _handles.removeWhere((_, ShaderHandle? handle) => handle == null);
    _stages = stages;
    _name = bundle.name;
  }

  /// How many modules this library has compiled, for tests.
  ///
  /// Read by whoever wants to know that a reload replaced the code behind the
  /// stages in use and did not quietly compile a second set beside them.
  int get debugTrackedModuleCount => _handles.values.nonNulls.length;
}
