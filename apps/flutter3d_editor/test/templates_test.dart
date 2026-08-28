/// What a template gives a new game, before there is a game to ask.
///
///     flutter test test/templates_test.dart
///
/// **A new game has told the editor nothing, and cannot.** The palette is built
/// from the document and a game says what its own words look like in
/// `assets/editor.json` — both of which need a game that already exists.
///
/// The rule that survives is the one `vocabulary.dart` states: **the editor's
/// code contains no genre word**. A template is data, copied into a new project
/// and read back from there by the same `Looks.parse` that reads the crypt's
/// file. The genre packages are in this application's `dev_dependencies`, not
/// its dependencies, so the words are checked here and never compiled into the
/// program.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_editor/src/editing.dart';
import 'package:flutter3d_editor/src/looks.dart';
import 'package:flutter3d_editor/src/palette_items.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// A genre's template, and what its documents mean to the game it is for.
final class _Template {
  _Template(this.genre, this.registry, this.rules, this.declared);

  final String genre;
  final EntityRegistry registry;
  final List<LevelRule> rules;

  /// Every type this genre's own packages declare, for the check that the
  /// template invented none of them.
  final Set<String> declared;

  String get where => 'assets/templates/$genre';

  Map<String, Object?> read(String name) =>
      jsonDecode(File('$where/$name').readAsStringSync())
          as Map<String, Object?>;

  Level get level => Level.fromJson(read('level.first.json'));

  Looks get looks => Looks.parse(File('$where/editor.json').readAsStringSync());
}

/// The words each genre owns, taken from the packages rather than typed here.
Set<String> _shooterWords() => <String>{
  EntityTypes.playerSpawn,
  EntityTypes.key,
  EntityTypes.door,
  EntityTypes.lift,
  EntityTypes.platform,
  EntityTypes.button,
  EntityTypes.trigger,
  EntityTypes.exit,
  ShooterEntities.monster,
  ShooterEntities.pickup,
  ShooterEntities.note,
  SampleEntities.torch,
  SampleEntities.lamp,
  SampleEntities.window,
};

Set<String> _platformerWords() => <String>{
  EntityTypes.playerSpawn,
  EntityTypes.key,
  EntityTypes.door,
  EntityTypes.lift,
  EntityTypes.platform,
  EntityTypes.button,
  EntityTypes.trigger,
  EntityTypes.exit,
  PlatformerEntities.collectible,
  PlatformerEntities.hazard,
  PlatformerEntities.checkpoint,
  PlatformerEntities.crate,
  PlatformerEntities.spring,
  PlatformerEntities.oneWay,
  PlatformerEntities.conveyor,
  PlatformerEntities.crumbling,
  PlatformerEntities.breakable,
  PlatformerEntities.climbable,
  PlatformerEntities.lamp,
  PlatformerEntities.enemy,
};

void main() {
  final templates = <_Template>[
    _Template('shooter', sampleRegistry(), sampleRules(), _shooterWords()),
    _Template(
      'platformer',
      platformerRegistry(),
      platformerRules(),
      _platformerWords(),
    ),
  ];

  test('there are templates at all', () {
    expect(templates, isNotEmpty);
    for (final template in templates) {
      expect(
        Directory(template.where).existsSync(),
        isTrue,
        reason: 'run tool/make_templates.py',
      );
    }
  });

  for (final template in templates) {
    group(template.genre, () {
      test('offers only words its own packages declare', () {
        // **The check that keeps a template honest.** A word invented here is a
        // word the game will refuse to load, and it would look to whoever
        // placed it like the editor being broken.
        final offered = template.read('editor.json').keys.toSet();

        expect(
          offered.difference(template.declared),
          isEmpty,
          reason: 'the template offers a word this genre does not have',
        );
      });

      test('and does not offer the one that would not validate', () {
        // `secret` is declared by the shooter and is **not** in
        // `sampleRegistry()`; a level containing one fails validation.
        expect(template.read('editor.json').keys, isNot(contains('secret')));
      });

      test('its first level has nothing wrong with it at all', () {
        // **Zero errors and zero warnings, and the warnings are the hard half.**
        // `LevelLoader.build` throws on an error, so an error is a game that
        // will not start — but a room built as six overlapping slabs opens with
        // a dozen z-fighting warnings, which is a new project greeting its
        // author with a list of complaints.
        final issues = LevelValidator(
          registry: template.registry,
          rules: template.rules,
        ).validate(template.level);

        expect(
          issues.map((LevelIssue it) => '${it.where}: ${it.message}'),
          isEmpty,
        );
      });

      test('and it survives being written back exactly as it is', () {
        // Otherwise the first save in a new project rewrites the whole file,
        // and the diff hides the one thing that changed.
        final text = File(
          '${template.where}/level.first.json',
        ).readAsStringSync();

        expect(Editing.parse(text, path: 'x').write(), text);
      });

      test('and every type it draws has a model that is really there', () {
        // A path with a typo draws the mark instead — which is exactly what an
        // undescribed type draws, so the template looks ignored rather than
        // wrong. The paths are written for the project the template is copied
        // into, so they are checked against the files that get copied.
        final looks = template.looks;
        final index = template.read('index.json');
        final files = (index['files']! as Map<String, Object?>).map(
          (String from, Object? to) =>
              MapEntry<String, String>(to! as String, from),
        );

        for (final type in template.read('editor.json').keys) {
          final model = looks.modelFor(EntityDef(type: type));
          if (model == null) continue;
          expect(
            files,
            contains(model),
            reason: '$type names $model, which the template does not ship',
          );
          expect(
            File('${template.where}/${files[model]}').existsSync(),
            isTrue,
          );
        }
      });

      test(
        'and the palette of its first level offers the whole vocabulary',
        () {
          // The point of a template: a level with one torch in it still offers
          // everything the genre has, so somebody can build the rest of it.
          final offered = paletteOf(
            template.level,
            declared: template.read('editor.json').keys,
          ).map((Placeable it) => it.what).toSet();

          expect(offered, containsAll(template.read('editor.json').keys));
        },
      );

      test('and what it ships is what its manifest says', () {
        // The manifest is what the scaffolder copies and what the bundle test
        // walks; a file that exists and is not listed is a file that never
        // reaches a new project.
        final listed =
            (template.read('index.json')['files']! as Map<String, Object?>).keys
                .toSet();
        final present = Directory(template.where)
            .listSync()
            .whereType<File>()
            .map((File it) => it.uri.pathSegments.last)
            .where((String it) => it != 'index.json')
            .toSet();

        expect(listed, present);
      });
    });
  }
}
