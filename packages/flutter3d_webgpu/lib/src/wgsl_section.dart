/// What a packer writes into a bundle's `webgpu` section, as text.
///
/// The reading half of this document is `lib/src/webgpu_bundle_section.dart`,
/// and that file says its own most valuable line out loud: no `package:web`
/// here and no `dart:js_interop`, so that the packer on the VM and the device
/// in the browser read one document rather than two transcriptions of it.
///
/// **This is the writing half, and it could not be that same file.** The codec
/// there reaches `flutter3d_hardware`'s barrel for `VertexFormat`, the barrel
/// reaches `package:flutter`, and a bundle is packed by a `dart run` script
/// with no `dart:ui` under it — `flutter3d_webgl/tool/pack_shaders.dart` is one
/// and `tool/pack_wgsl_section.dart` beside this file is its sibling. Importing
/// the codec from either is a compile error naming `dart:ui`, which is the
/// measurement that put these twenty lines of `jsonEncode` here rather than in
/// the codec.
///
/// What holds the two halves together instead is `test/wgsl_section_test.dart`,
/// which writes a document with every field populated and reads it back with
/// `decodeWebGpuSection`, field for field. A writer nobody read back would be
/// the real duplication — the JSON would be right about the shape and wrong
/// about a spelling, and the first thing to notice would be a bundle refused on
/// somebody's machine.
///
/// **Under `lib/src/` and not under `tool/`**, which reads oddly for a file only
/// a build script calls, and is the same decision `glsl_to_wgsl.dart`,
/// `wgsl_compiler.dart` and `source_package.dart` all record: the browser test
/// runner serves this package from `test/` and cannot read a sibling directory,
/// so a build-time file under `tool/` is a build-time file no test can measure.
/// It was written there first and the whole Chrome pass failed to compile on
/// the import, which is as clear a measurement of that rule as it gets. Nothing
/// this package exports reaches this file, so nothing a consumer builds carries
/// it; and it imports `dart:convert` and the translator alone, so the round trip
/// above runs in a browser as readily as on the VM.
///
/// One spelling in particular is why that test earns its keep.
/// [PreparedSampler.dimension] carries a `WebGpuTextureDimension`'s *Dart* name
/// — `twoDimensional` — and the document carries its `gpuName`, `2d`, because
/// that string goes straight into a bind group layout. The two differ for
/// exactly one of the two values, which is the kind of difference that survives
/// a careful reading and not a round trip.
library;

import 'dart:convert';

import 'glsl_to_wgsl.dart';

/// The shape of the document this writer produces.
///
/// The reader is `WebGpuLoadedShaderLibrary.sectionVersion`, and the two are
/// held equal by `test/wgsl_section_test.dart` — the constant cannot simply be
/// imported from there for the reason this library's header gives.
///
/// **Written out, although `encodeWebGpuSection` writes no version at all.**
/// That codec serves the engine's own table, which is generated beside the
/// reader it feeds and can never be older than it. A bundle can: it is a file
/// on disk that outlives the build that made it. A document that says nothing
/// is read as whatever the reader's own version is, so the day the shape
/// changes, a bundle packed today would be read as one packed tomorrow — the
/// gate would pass and the reflection would be misread. Saying the number is
/// what makes the refusal possible.
const int kSectionVersion = 1;

/// Raised when a prepared stage cannot be turned into a section entry.
final class WgslSectionError implements Exception {
  const WgslSectionError(this.message);

  final String message;

  @override
  String toString() => 'WgslSectionError: $message';
}

/// One finished stage: the WGSL the two compilers made, and the reflection the
/// preparation handed out.
///
/// Named here rather than in either program because both build it —
/// `tool/generate_shaders.dart` prints these as Dart source for the engine's
/// built-in table, `tool/pack_wgsl_section.dart` encodes them as JSON for a
/// loadable bundle — and the two must mean the same pair by it.
typedef PackedStage = ({String wgsl, PreparedStage prepared});

/// The section document for [vertex] and [fragment], as JSON text.
///
/// The caller writes it as UTF-8; `ShaderBundle` carries bytes and this file
/// deliberately stops at the text, so a test can read what was written.
String wgslSectionDocument({
  required Map<String, PackedStage> vertex,
  required Map<String, PackedStage> fragment,
}) => jsonEncode(<String, Object>{
  'version': kSectionVersion,
  'vertex': <String, Object>{
    for (final entry in vertex.entries) entry.key: _stageJson(entry.value),
  },
  'fragment': <String, Object>{
    for (final entry in fragment.entries) entry.key: _stageJson(entry.value),
  },
});

Map<String, Object> _stageJson(PackedStage stage) => <String, Object>{
  'wgsl': stage.wgsl,
  'attributes': <Object>[
    for (final attribute in stage.prepared.attributes)
      <String, Object>{
        'name': attribute.name,
        'location': attribute.location,
        'format': attribute.format,
      },
  ],
  'blocks': <Object>[
    for (final block in stage.prepared.blocks)
      <String, Object>{
        'name': block.name,
        'group': block.group,
        'binding': block.binding,
        'size': block.sizeInBytes,
        'members': <Object>[
          for (final member in block.members)
            <String, Object>{
              'name': member.name,
              'offset': member.offsetInBytes,
              'size': member.sizeInBytes,
            },
        ],
      },
  ],
  'samplers': <Object>[
    for (final sampler in stage.prepared.samplers)
      <String, Object>{
        'name': sampler.name,
        'group': sampler.group,
        'texture': sampler.textureBinding,
        'sampler': sampler.samplerBinding,
        'dimension': _gpuDimension(sampler),
      },
  ],
};

/// A sampler's dimension the way WebGPU spells it.
///
/// The preparation names it the way the Dart enum does, because it may not
/// import that enum; the document names it the way `GPUTextureViewDimension`
/// does, because the string ends up in a bind group layout entry. This is the
/// one place the two are joined, and an unknown name stops the build rather
/// than reaching a layout that would be refused at pipeline creation with
/// nothing here to explain it.
String _gpuDimension(PreparedSampler sampler) => switch (sampler.dimension) {
  kTwoDimensional => '2d',
  kCubeDimension => 'cube',
  _ => throw WgslSectionError(
    'the sampler "${sampler.name}" has the dimension "${sampler.dimension}", '
    'which is neither $kTwoDimensional nor $kCubeDimension',
  ),
};

/// Holds a packer's std140 arithmetic against glslang's own decorations.
///
/// Two independent answers to the same question. The packer computes offsets
/// from the GLSL because the reflection has to exist before there is any WGSL
/// to read it out of; glslang writes them into the SPIR-V because that is what
/// `std140` means. They agree here or the build stops.
///
/// **A block the listing does not mention at all is the sharper failure.** It
/// means the reflection claims a block the compiled shader does not have —
/// which happens the moment a `#ifndef` guard is read wrongly, and which the
/// engine turns into a bind of a slot that is not there. `lib/surface.glsl`
/// records what that costs on the other two backends: a native crash inside
/// Metal, and a draw discarded with nothing logged.
///
/// Shared by the two programs beside this file rather than written in the one
/// that needed it first. A bundle somebody else packs is exactly where a block
/// laid out by a rule nobody checked would land, so the loadable path wants
/// this check more than the engine's own table does — and two copies of it
/// would be two rules, one of which nobody would notice going stale.
void checkStd140Offsets(
  String name,
  PreparedStage prepared,
  Map<String, Map<String, int>> offsets,
) {
  for (final block in prepared.blocks) {
    final theirs = offsets[block.name];
    if (theirs == null) {
      throw WgslSectionError(
        '$name: the reflection has the block "${block.name}" and the compiled '
        'shader does not',
      );
    }
    for (final member in block.members) {
      final expected = theirs[member.name];
      if (expected == null) {
        throw WgslSectionError(
          '$name: "${block.name}.${member.name}" is in the reflection and not '
          'in the compiled block',
        );
      }
      if (expected != member.offsetInBytes) {
        throw WgslSectionError(
          '$name: "${block.name}.${member.name}" is at ${member.offsetInBytes} '
          'by std140 and at $expected in the SPIR-V',
        );
      }
    }
  }
}
