/// Writes `flutter3d_shaders/lib/stage_bindings.dart`: what every compiled
/// stage in the bundle keeps, by name.
///
///     dart run tool/stage_bindings.dart
///
/// Compiled with the real `impellerc` for Metal and read off its reflection,
/// keeping only the blocks and samplers the Metal function actually has a slot
/// for. That is the set a draw must bind and may bind: a resource the source
/// declares and the compiler dropped is neither. `FakeBackend` takes the table
/// so a missing or misdirected bind fails a test on the VM, and
/// `stage_bindings_test.dart` holds the committed table to a fresh compile.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_impeller/src/shader_bundle_build.dart';

/// Stage name to the blocks and samplers its compiled Metal function keeps.
/// One member of a uniform block as impellerc lays it out: where it starts,
/// how many bytes it takes, how many elements if it is an array (one if not),
/// and its reflected type name (`Vector4`, `Matrix4`, `Float`, ...).
typedef ReflectedMember = ({
  int offset,
  int byteLength,
  int elements,
  String type,
});

/// Every stage's uniform blocks, by stage then by block, with their members
/// in declaration order — `H1`. Per stage and not per block name, because
/// one name can mean a wider block in one stage than in another (bloom's
/// upsample declares a tint its threshold and downsample do not), and a
/// check against the union would let the narrower stage accept a member it
/// has no room for. Filled by [reflectStages] as it goes.
final Map<String, Map<String, Map<String, ReflectedMember>>> reflectedBlocks =
    <String, Map<String, Map<String, ReflectedMember>>>{};

Map<String, ({Set<String> blocks, Set<String> samplers})> reflectStages({
  required String shadersRoot,
}) {
  final compiler = impellercPath();
  final shaderLib = File(compiler).parent.uri.resolve('shader_lib').path;
  final manifest =
      jsonDecode(
            File('$shadersRoot/flutter3d.shaderbundle.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final scratch = Directory.systemTemp.createTempSync('f3d_stages_');
  try {
    final stages = <String, ({Set<String> blocks, Set<String> samplers})>{};
    for (final MapEntry(key: name, value: entry) in manifest.entries) {
      final stage = entry! as Map<String, Object?>;
      final file = (stage['file']! as String).replaceFirst('shaders/', '');
      final reflection = '${scratch.path}/$name.json';
      final result = Process.runSync(compiler, <String>[
        '--metal-desktop',
        '--input=$shadersRoot/$file',
        '--sl=${scratch.path}/$name.metal',
        '--spirv=${scratch.path}/$name.spv',
        '--reflection-json=$reflection',
        '--include=$shaderLib',
        '--include=$shadersRoot',
        '--include=$shadersRoot/lib',
        '--input-type=${stage['type'] == 'vertex' ? 'vert' : 'frag'}',
      ]);
      if (result.exitCode != 0) {
        throw StateError('$name did not compile: ${result.stderr}');
      }
      final reflected =
          jsonDecode(File(reflection).readAsStringSync())
              as Map<String, Object?>;
      Set<String> kept(String kind) => <String>{
        for (final r in (reflected[kind] as List<Object?>? ?? const []))
          if ((r! as Map<String, Object?>)['ext_res_0'] != 0xFFFFFFFF)
            (r as Map<String, Object?>)['name']! as String,
      };
      stages[name] = (
        blocks: kept('buffers'),
        samplers: kept('sampled_images'),
      );
      for (final raw in (reflected['buffers'] as List<Object?>? ?? const [])) {
        final buffer = raw! as Map<String, Object?>;
        final type = buffer['type']! as Map<String, Object?>;
        final members = <String, ReflectedMember>{
          for (final m in (type['members'] as List<Object?>? ?? const []))
            // impellerc's own `_PADDING_` members fill std140 gaps; nothing
            // names them, and several in one block share the one name.
            if (m case final Map<String, Object?> member
                when !(member['name']! as String).startsWith('_PADDING'))
              member['name']! as String: (
                offset: member['offset']! as int,
                byteLength: member['byte_length']! as int,
                elements: switch (member['array_elements']) {
                  final int n => n,
                  _ => 1,
                },
                type: member['type']! as String,
              ),
        };
        (reflectedBlocks[name] ??= <String, Map<String, ReflectedMember>>{})[
          buffer['name']! as String
        ] = members;
      }
    }
    return stages;
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// [stages] as the Dart source of `stage_bindings.dart`.
/// `uniform_blocks.dart`: the layout of every block, for a backend that
/// checks a caller's member names without reflecting them itself and for the
/// typed blocks built on it.
String uniformBlocksSource(
  Map<String, Map<String, Map<String, ReflectedMember>>> stages,
) {
  final out = StringBuffer()
    ..writeln('// GENERATED by flutter3d_impeller/tool/stage_bindings.dart.')
    ..writeln('// Do not edit; run the tool after any shader edit.')
    ..writeln()
    ..writeln("/// How impellerc lays out the uniform blocks of every stage in")
    ..writeln("/// the engine's bundle: each member's byte offset, byte length,")
    ..writeln('/// element count and reflected type, in declaration order.')
    ..writeln('/// Per stage, because one block name can be wider in one stage')
    ..writeln('/// than another.')
    ..writeln('library;')
    ..writeln()
    ..writeln('/// One member of a uniform block.')
    ..writeln(
      'typedef UniformMemberLayout = '
      '({int offset, int byteLength, int elements, String type});',
    )
    ..writeln()
    ..writeln(
      'const Map<String, Map<String, Map<String, UniformMemberLayout>>> '
      'uniformBlocks = '
      '<String, Map<String, Map<String, UniformMemberLayout>>>{',
    );
  for (final stage in stages.keys.toList()..sort()) {
    out.writeln("  '$stage': <String, Map<String, UniformMemberLayout>>{");
    final blocks = stages[stage]!;
    for (final block in blocks.keys.toList()..sort()) {
      out.writeln("    '$block': <String, UniformMemberLayout>{");
      for (final MapEntry(key: name, value: m) in blocks[block]!.entries) {
        out.writeln(
          "      '$name': (offset: ${m.offset}, byteLength: ${m.byteLength}, "
          "elements: ${m.elements}, type: '${m.type}'),",
        );
      }
      out.writeln('    },');
    }
    out.writeln('  },');
  }
  out.writeln('};');
  return out.toString();
}

/// `typed_blocks.dart`: a class per uniform block name, with one
/// preallocated array per member — `H1`. Where one name is laid out wider in
/// one stage than another, the class carries the union, which is only sound
/// while every member they share sits at one offset; a disagreement is a
/// build error here rather than a wrong picture later.
String typedBlocksSource(
  Map<String, Map<String, Map<String, ReflectedMember>>> stages,
) {
  final union = <String, Map<String, ReflectedMember>>{};
  for (final MapEntry(key: stage, value: blocks) in stages.entries) {
    for (final MapEntry(key: block, value: members) in blocks.entries) {
      final seen = union[block] ??= <String, ReflectedMember>{};
      for (final MapEntry(key: name, value: m) in members.entries) {
        final before = seen[name];
        if (before != null && before != m) {
          throw StateError(
            'uniform block "$block" member "$name" is laid out as $m in '
            '$stage and as $before elsewhere; a block one name stands for '
            'has to agree on the members it shares',
          );
        }
        seen[name] = m;
      }
    }
  }
  String camel(String snake) {
    final parts = snake.split('_');
    return parts.first +
        parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
  }

  final out = StringBuffer()
    ..writeln('// GENERATED by flutter3d_impeller/tool/stage_bindings.dart.')
    ..writeln('// Do not edit; run the tool after any shader edit.')
    ..writeln()
    ..writeln("/// A class per uniform block the engine's stages declare, one")
    ..writeln('/// preallocated array per member, laid out as the compiler lays')
    ..writeln('/// it out. Filled in place and bound with')
    ..writeln('/// `PassEncoder.bindBlock`.')
    ..writeln('library;')
    ..writeln()
    ..writeln("import 'dart:typed_data';")
    ..writeln()
    ..writeln("import 'package:flutter3d_hardware/flutter3d_hardware.dart';");
  for (final block in union.keys.toList()..sort()) {
    final members = union[block]!.entries.toList()
      ..sort((a, b) => a.value.offset.compareTo(b.value.offset));
    out
      ..writeln()
      ..writeln('/// `$block`.')
      ..writeln('final class ${block}Block extends UniformBlock {')
      ..writeln("  ${block}Block() : super('$block');");
    for (final MapEntry(key: name, value: m) in members) {
      final what = m.elements > 1 ? '${m.elements} × ${m.type}' : m.type;
      out
        ..writeln()
        ..writeln('  /// `$name`: $what, at byte ${m.offset}.')
        ..writeln(
          '  final Float32List ${camel(name)} = '
          'Float32List(${m.byteLength ~/ 4});',
        );
    }
    out
      ..writeln()
      ..writeln('  @override')
      ..writeln(
        '  late final Map<String, Float32List> members = '
        '<String, Float32List>{',
      );
    for (final MapEntry(key: name) in members) {
      out.writeln("    '$name': ${camel(name)},");
    }
    out
      ..writeln('  };')
      ..writeln('}');
  }
  return out.toString();
}

String stageBindingsSource(
  Map<String, ({Set<String> blocks, Set<String> samplers})> stages,
) {
  String set(Set<String> names) => names.isEmpty
      ? '<String>{}'
      : '<String>{${(names.toList()..sort()).map((n) => "'$n'").join(', ')}}';
  final out = StringBuffer()
    ..writeln('// GENERATED by flutter3d_impeller/tool/stage_bindings.dart.')
    ..writeln('// Do not edit; run the tool after any shader edit.')
    ..writeln()
    ..writeln(
      "/// What every stage in the engine's bundle keeps once compiled:",
    )
    ..writeln('/// the uniform blocks and samplers a draw through it must bind')
    ..writeln('/// and may bind. Read off impellerc\'s Metal reflection, so a')
    ..writeln('/// resource the source declares and the compiler dropped is')
    ..writeln('/// not here. `FakeBackend(stageBindings: stageBindings)` holds')
    ..writeln('/// a renderer to it on the VM.')
    ..writeln('library;')
    ..writeln()
    ..writeln(
      'const Map<String, ({Set<String> blocks, Set<String> samplers})> '
      'stageBindings = <String, ({Set<String> blocks, Set<String> samplers})>{',
    );
  for (final name in stages.keys.toList()..sort()) {
    final stage = stages[name]!;
    out.writeln(
      "  '$name': (blocks: ${set(stage.blocks)}, "
      'samplers: ${set(stage.samplers)}),',
    );
  }
  out.writeln('};');
  return out.toString();
}

void main() {
  final shaders = Directory('../flutter3d_shaders/shaders').absolute.path;
  final target = File('../flutter3d_shaders/lib/stage_bindings.dart');
  target.writeAsStringSync(
    stageBindingsSource(reflectStages(shadersRoot: shaders)),
  );
  final blocks = File('../flutter3d_shaders/lib/uniform_blocks.dart');
  blocks.writeAsStringSync(uniformBlocksSource(reflectedBlocks));
  final typed = File('../flutter3d_shaders/lib/typed_blocks.dart');
  typed.writeAsStringSync(typedBlocksSource(reflectedBlocks));
  Process.runSync('dart', <String>[
    'format',
    target.path,
    blocks.path,
    typed.path,
  ]);
  stdout.writeln('wrote ${target.path}, ${blocks.path} and ${typed.path}');
}
