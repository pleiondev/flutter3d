/// Typed uniform blocks: a Dart class per block a stage declares, generated
/// from the compiler's own reflection of the stage, and checked against it
/// at build time.
///
/// **A member named by hand fails silently.** `bindUniformBlock` takes a
/// map of member names, and a name the stage does not have is refused at
/// draw time with a `false` nobody reads: the draw goes on with the block
/// unbound and the picture is wrong or empty. A class generated from the
/// reflection has a field per member, so a misspelt member is a Dart
/// compile error; and a class committed earlier is compared with a fresh
/// reflection here, so a member renamed in the shader fails the build by
/// name instead of drawing nothing.
///
/// **Two layouts are held to the compiler's.** The material language lays
/// out each block it emits by the std140 rules itself
/// (`MaterialSlotTable`), and the engine fills `MaterialParams` from
/// `RenderMaterial.parameters` by those offsets; [uniformBlockProblems]
/// holds that arithmetic to what `impellerc` reports. And a generated file
/// read back ([uniformBlocksInSource]) is held to the same reflection.
///
/// The first stage it runs on is the fragment stage of every material a
/// project builds, from `runMaterialBuild`, which writes
/// `lib/uniform_blocks.g.dart` beside `lib/materials.g.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_build_hooks/flutter3d_build_hooks.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show UniformMemberLayout;
import 'package:flutter3d_shaders/compile.dart' show ShaderSet;

/// Uniform blocks by name, each its members by name in declaration order.
typedef UniformBlockLayouts = Map<String, Map<String, UniformMemberLayout>>;

/// The uniform blocks of one stage as `impellerc --reflection-json` reports
/// them: each block's members with their offset, byte length, element count
/// and type, `impellerc`'s own std140 padding members left out.
UniformBlockLayouts uniformBlocksFromReflection(
  Map<String, Object?> reflection,
) => <String, Map<String, UniformMemberLayout>>{
  for (final raw in (reflection['buffers'] as List<Object?>?) ?? const [])
    if (raw case final Map<String, Object?> buffer)
      buffer['name']! as String: <String, UniformMemberLayout>{
        for (final member
            in ((buffer['type']! as Map<String, Object?>)['members']
                    as List<Object?>?) ??
                const [])
          if (member case final Map<String, Object?> m
              when !(m['name']! as String).startsWith('_PADDING'))
            m['name']! as String: UniformMemberLayout(
              offset: m['offset']! as int,
              byteLength: m['byte_length']! as int,
              elements: switch (m['array_elements']) {
                final int n when n > 0 => n,
                _ => 1,
              },
              type: m['type']! as String,
            ),
      },
};

/// Compiles [glsl] with [compilers]' `impellerc` and reads its reflection:
/// the stage's uniform blocks as the compiler lays them out, or null when
/// the compiler wrote no reflection (a stub, in a test of what else the
/// build does).
///
/// [name] names the stage in the scratch files under [scratch] and in a
/// refusal. Throws [MaterialBuildException] when `impellerc` refuses the
/// stage, naming [source].
UniformBlockLayouts? reflectStageBlocks(
  String glsl, {
  required String name,
  required bool fragment,
  required String source,
  required MaterialCompilers compilers,
  required ShaderSet engine,
  required Directory scratch,
}) {
  final directory = Directory('${scratch.path}/reflect')
    ..createSync(recursive: true);
  final input = File('${directory.path}/$name.${fragment ? 'frag' : 'vert'}')
    ..writeAsStringSync(glsl);
  final reflection = File('${directory.path}/$name.json');
  if (reflection.existsSync()) reflection.deleteSync();
  final ProcessResult result;
  try {
    result = Process.runSync(compilers.impellerc, <String>[
      '--metal-desktop',
      '--input=${input.path}',
      '--sl=${directory.path}/$name.metal',
      '--spirv=${directory.path}/$name.spv',
      '--reflection-json=${reflection.path}',
      '--input-type=${fragment ? 'frag' : 'vert'}',
      '--include=${engine.root}',
      for (final include in compilers.impellerIncludes) '--include=$include',
    ], workingDirectory: directory.path);
  } on ProcessException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      MaterialBuildException(
        'impellerc could not be run to reflect $name: ${error.message}',
        source: source,
      ),
      stackTrace,
    );
  }
  if (result.exitCode != 0) {
    throw MaterialBuildException(
      'impellerc refused $name while reflecting its uniform blocks, kept at '
      '${input.path} (exit ${result.exitCode}):\n'
      '${result.stdout}${result.stderr}',
      source: source,
    );
  }
  if (!reflection.existsSync()) return null;
  final blocks = uniformBlocksFromReflection(
    (jsonDecode(reflection.readAsStringSync()) as Map).cast<String, Object?>(),
  );
  directory.deleteSync(recursive: true);
  return blocks;
}

/// The blocks [program] declares, laid out as the material language lays
/// them out: what the engine binds a material's values by.
UniformBlockLayouts declaredMaterialBlocks(MaterialProgram program) =>
    <String, Map<String, UniformMemberLayout>>{
      for (final block in MaterialSlotTable.of(program).blocks)
        block.name: <String, UniformMemberLayout>{
          for (final member in block.members)
            member.name: UniformMemberLayout(
              offset: member.offset,
              byteLength: member.size,
              type: '${member.type}',
            ),
        },
    };

/// What is wrong with [expected] against [reflected], the compiler's
/// layout of the same stage, one sentence each; empty when they agree.
///
/// A block or a member [expected] names that [reflected] lacks is named,
/// with the closest member the stage has when one is near enough to be a
/// misspelling; an offset or a size that differs is named with both. Only
/// the blocks [expected] names are compared, and a member it does not name
/// is not a problem: a stage may declare more than one caller fills.
/// [against] names what [expected] came from, for the sentence.
List<String> uniformBlockProblems(
  UniformBlockLayouts expected,
  UniformBlockLayouts reflected, {
  required String stage,
  required String against,
}) {
  final problems = <String>[];
  for (final MapEntry(key: block, value: members) in expected.entries) {
    final actual = reflected[block];
    if (actual == null) {
      problems.add(
        '$against names the uniform block "$block", which the compiled stage '
        '"$stage" does not have${_nearest(block, reflected.keys)}',
      );
      continue;
    }
    for (final MapEntry(key: name, value: want) in members.entries) {
      final problem = switch (actual[name]) {
        null =>
          '$against names the member "$name" of "$block", which the '
              'compiled stage "$stage" does not have'
              '${_nearest(name, actual.keys)}',
        final got when got.offset != want.offset =>
          '"$block.$name" is at byte ${want.offset} in $against and at '
              'byte ${got.offset} in the compiled stage "$stage"',
        final got when got.byteLength != want.byteLength =>
          '"$block.$name" takes ${want.byteLength} bytes in $against and '
              '${got.byteLength} in the compiled stage "$stage"',
        _ => null,
      };
      if (problem != null) problems.add(problem);
    }
  }
  return problems;
}

/// `, did you mean "x"?` for the one of [candidates] closest to [name], when
/// it is within a third of the name's length in edits; nothing otherwise.
String _nearest(String name, Iterable<String> candidates) {
  String? best;
  var bestDistance = math.max(1, name.length ~/ 3) + 1;
  for (final candidate in candidates) {
    final distance = _editDistance(name, candidate);
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best == null ? '' : ' (did you mean "$best"?)';
}

int _editDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      );
    }
    previous = current;
  }
  return previous[b.length];
}

/// The name of the class [generateUniformBlocks] writes for [block] of
/// [stage]: `<Stage><Block>Block`, with a material's `MaterialParams`
/// written `Params`, so `RimLight`'s is `RimLightParamsBlock`.
String uniformBlockClassName(String stage, String block) =>
    '${_upperFirst(_identifier(stage))}'
    '${block == 'MaterialParams' ? 'Params' : _upperFirst(_identifier(block))}'
    'Block';

/// The Dart of one library with a `UniformBlock` class per block of each
/// stage in [stages], laid out as the compiler laid it out.
///
/// Each class carries its `layout` as a constant, which is what
/// [uniformBlocksInSource] reads back, and one preallocated array per
/// member, filled in place and bound with `PassEncoder.bindBlock`. [from]
/// names, per stage, the file it was compiled from, for the doc comment.
String generateUniformBlocks(
  Map<String, UniformBlockLayouts> stages, {
  Map<String, String> from = const <String, String>{},
  String header =
      '// GENERATED by flutter3d_build from the compiler\'s reflection of each '
      'stage.\n// Do not edit; change the shader and build again.',
}) {
  final out = StringBuffer()
    ..writeln(header)
    ..writeln()
    ..writeln('/// The uniform blocks of the project\'s stages, typed: a class')
    ..writeln('/// per block, a field per member, laid out as the compiler')
    ..writeln('/// laid it out.')
    ..writeln('library;')
    ..writeln()
    ..writeln("import 'dart:typed_data';")
    ..writeln()
    ..writeln("import 'package:flutter3d/flutter3d.dart'")
    ..writeln('    show UniformBlock, UniformMemberLayout;');
  for (final stage in stages.keys.toList()..sort()) {
    final blocks = stages[stage]!;
    for (final block in blocks.keys.toList()..sort()) {
      final members = blocks[block]!.entries.toList()
        ..sort((a, b) => a.value.offset.compareTo(b.value.offset));
      final type = uniformBlockClassName(stage, block);
      final source = from[stage];
      out
        ..writeln()
        ..writeln(
          '/// `$block` of the stage `$stage`'
          '${source == null ? '' : ', from `$source`'}.',
        )
        ..writeln('final class $type extends UniformBlock {')
        ..writeln('  /// The block, every member at nought.')
        ..writeln("  $type() : super('$block');")
        ..writeln()
        ..writeln('  /// The stage the block was reflected from.')
        ..writeln("  static const String stage = '$stage';")
        ..writeln()
        ..writeln('  /// Each member as the compiler laid it out.')
        ..writeln('  static const Map<String, UniformMemberLayout> layout =')
        ..writeln('      <String, UniformMemberLayout>{');
      // As `dart format` writes it, so a committed file stays formatted.
      for (final MapEntry(key: name, value: m) in members) {
        out
          ..writeln("        '$name': UniformMemberLayout(")
          ..writeln('          offset: ${m.offset},')
          ..writeln('          byteLength: ${m.byteLength},')
          ..writeln('          elements: ${m.elements},')
          ..writeln("          type: '${m.type}',")
          ..writeln('        ),');
      }
      out.writeln('      };');
      for (final MapEntry(key: name, value: m) in members) {
        final what = m.elements > 1 ? '${m.elements} × ${m.type}' : m.type;
        out
          ..writeln()
          ..writeln('  /// `$name`: $what, at byte ${m.offset}.')
          ..writeln(
            '  final Float32List ${_member(name)} = '
            'Float32List(${math.max(1, m.byteLength ~/ 4)});',
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
        out.writeln("    '$name': ${_member(name)},");
      }
      out
        ..writeln('  };')
        ..writeln('}');
    }
  }
  return out.toString();
}

/// The blocks a library [generateUniformBlocks] wrote declares, by stage:
/// each class's `stage`, its block name and its `layout`, read back so a
/// committed file can be held to a fresh reflection.
Map<String, UniformBlockLayouts> uniformBlocksInSource(String dart) {
  final found = <String, UniformBlockLayouts>{};
  final classes = RegExp(
    r"final class \w+ extends UniformBlock \{\s*(?:///[^\n]*\n\s*)*\w+\(\) : "
    r"super\('(\w+)'\);(.*?)\n\}",
    dotAll: true,
  );
  final stageOf = RegExp(r"static const String stage = '([^']+)';");
  final memberOf = RegExp(
    r"'(\w+)': UniformMemberLayout\(\s*offset: (\d+),\s*byteLength: (\d+),"
    r"\s*elements: (\d+),\s*type: '([^']*)',?\s*\)",
  );
  for (final match in classes.allMatches(dart)) {
    final body = match.group(2)!;
    final stage = stageOf.firstMatch(body)?.group(1);
    if (stage == null) continue;
    (found[stage] ??= <String, Map<String, UniformMemberLayout>>{})[match.group(
      1,
    )!] = <String, UniformMemberLayout>{
      for (final member in memberOf.allMatches(body))
        member.group(1)!: UniformMemberLayout(
          offset: int.parse(member.group(2)!),
          byteLength: int.parse(member.group(3)!),
          elements: int.parse(member.group(4)!),
          type: member.group(5)!,
        ),
    };
  }
  return found;
}

String _upperFirst(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

/// [name] as a Dart identifier: a namespaced stage (`acme__Hair`) and a
/// snake-case member (`light_color`) in camel case.
String _identifier(String name) {
  final parts = name.split(RegExp('_+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return name;
  return parts.first + parts.skip(1).map(_upperFirst).join();
}

/// A member's field name: camel case, with `Value` after a name the class
/// or Dart already has.
String _member(String name) {
  final camel = _identifier(name);
  return _taken.contains(camel) ? '${camel}Value' : camel;
}

const Set<String> _taken = <String>{
  'name', 'members', 'layout', 'stage', 'hashCode', 'runtimeType', //
  'toString', 'noSuchMethod', 'assert', 'break', 'case', 'catch', 'class',
  'const', 'continue', 'default', 'do', 'else', 'enum', 'extends', 'false',
  'final', 'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow',
  'return', 'super', 'switch', 'this', 'throw', 'true', 'try', 'var', 'void',
  'while', 'with',
};
