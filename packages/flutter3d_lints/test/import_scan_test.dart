/// `scanEngineImports`: the two import rules, what fires and what stays
/// quiet, on units parsed without a resolver.
///
///     dart test test/import_scan_test.dart
///
/// Each test names the mutation that would defeat it.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutter3d_lints/flutter3d_lints.dart';
import 'package:test/test.dart';

List<ImportFinding> _scan(String source, {String? ownPackage}) =>
    scanEngineImports(
      parseString(content: source, throwIfDiagnostics: false).unit,
      ownPackage: ownPackage,
    );

List<String> _rules(String source, {String? ownPackage}) => <String>[
  for (final f in _scan(source, ownPackage: ownPackage)) f.rule,
];

/// [source] with the fix of its first finding applied.
String _fixed(String source) {
  final edit = _scan(source).first.edit!;
  return source.replaceRange(
    edit.offset,
    edit.offset + edit.length,
    edit.replacement,
  );
}

void main() {
  group('avoid_engine_internal_imports', () {
    test('internal.dart, builtin.dart and src/ fire from a game', () {
      // Mutation: drop the `src/` arm of `isEngineInternalUri` and the third
      // import, the commonest of the three, is let through.
      expect(
        _rules(
          "import 'package:flutter3d_shaders/internal.dart';\n"
          "import 'package:flutter3d_cpu/builtin.dart';\n"
          "export 'package:flutter3d_core/src/engine/scene/scene.dart';\n",
          ownPackage: 'my_game',
        ),
        List<String>.filled(3, EngineImportRules.internalImports),
      );
    });

    test('a public library, testing.dart and a third party stay quiet', () {
      // Mutation: match any library of an owned package and the facade
      // fires; add `testing.dart` and a game's own tests fire.
      expect(
        _rules(
          "import 'package:flutter3d/flutter3d.dart';\n"
          "import 'package:flutter3d_hardware/testing.dart';\n"
          "import 'package:other/src/thing.dart';\n",
          ownPackage: 'my_game',
        ),
        isEmpty,
      );
    });

    test('the engine\'s own packages are left to the structure rules', () {
      // Mutation: drop the `inside` test and every engine package that
      // shares an internal library under `restrictedLibraryUsers` fires.
      expect(
        _rules(
          "import 'package:flutter3d_shaders/internal.dart';\n",
          ownPackage: 'flutter3d_core',
        ),
        isEmpty,
      );
    });
  });

  group('hide_flutter_matrix4', () {
    const both =
        "import 'package:flutter/material.dart';\n"
        "import 'package:flutter3d/flutter3d.dart';\n"
        'void f(SceneNode n) => n.setLocalMatrix(Matrix4.identity());\n';

    test('Flutter and the engine with Matrix4 written fire on Flutter', () {
      // Mutation: report on the engine's import instead and the fix would
      // hide the one the engine takes.
      final found = _scan(both);
      expect(found.map((ImportFinding f) => f.rule), <String>[
        EngineImportRules.flutterMatrix4,
      ]);
      expect(found.single.what, 'package:flutter/material.dart');
    });

    test('the fix hides Flutter\'s, alone or on an existing hide list', () {
      // Mutation: always insert a new `hide` and the second case becomes
      // `hide Colors hide Matrix4`, which parses but reads twice.
      expect(_fixed(both), contains("material.dart' hide Matrix4;"));
      expect(
        _fixed(
          both.replaceFirst("material.dart';", "material.dart' hide Colors;"),
        ),
        contains("material.dart' hide Colors, Matrix4;"),
      );
    });

    test('a hidden, shown-without or prefixed Matrix4 stays quiet', () {
      // Mutation: ignore the combinators in `_bringsMatrix4` and every file
      // already fixed fires again.
      for (final flutter in <String>[
        "import 'package:flutter/widgets.dart' hide Matrix4;",
        "import 'package:flutter/widgets.dart' show Widget;",
        "import 'package:flutter/widgets.dart' as w;",
      ]) {
        expect(
          _rules(
            "$flutter\nimport 'package:flutter3d/flutter3d.dart';\n"
            'final m = Matrix4.identity();\n',
          ),
          isEmpty,
          reason: flutter,
        );
      }
    });

    test('a file that never writes Matrix4 stays quiet', () {
      // Mutation: drop `_writesMatrix4` and every widget file of a game
      // fires, though no two Matrix4s ever meet in it.
      expect(
        _rules(
          "import 'package:flutter/material.dart';\n"
          "import 'package:flutter3d/flutter3d.dart';\n"
          'Widget f() => const SizedBox();\n',
        ),
        isEmpty,
      );
    });

    test('the facade exports the Matrix4 the list says it does', () {
      // Mutation: take `Matrix4` out of the facade's vector_math export and
      // `engineMatrix4Libraries` names a library that no longer brings it.
      final facade = File('../flutter3d/lib/flutter3d.dart').readAsStringSync();
      final export = RegExp(
        r"export 'package:vector_math/vector_math\.dart'\s+show\s+([^;]+);",
      ).firstMatch(facade);
      expect(export, isNotNull);
      expect(
        export!.group(1)!.split(',').map((String s) => s.trim()),
        contains('Matrix4'),
      );
      expect(
        engineMatrix4Libraries,
        contains('package:flutter3d/flutter3d.dart'),
      );
    });
  });
}
