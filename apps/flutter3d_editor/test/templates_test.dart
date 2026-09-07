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

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_game_strategy/bridge.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

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

/// Every word the strategy demo's own map is written in.
///
/// **Read off the document rather than typed here**, for the same reason the
/// two sets above are read off their packages: the words `camp`, `worker`,
/// `resource_node`, `stockpile` and `producer` belong to
/// `apps/flutter3d_demo_strategy`, which is an application and not a package
/// this one may depend on. What it *can* do is read the map that application
/// plays, which is the same document `tool/make_templates.py` builds the
/// template out of — so a word offered by the template and used by no map is a
/// word somebody invented here.
Set<String> _strategyWords() =>
    _playedMap().entities.map((EntityDef it) => it.type).toSet();

/// The map the strategy demo plays, which is what its template starts from.
Level _playedMap() => Level.fromJson(
  jsonDecode(
        File(
          '../flutter3d_demo_strategy/assets/levels/map_a.json',
        ).readAsStringSync(),
      )
      as Map<String, Object?>,
);

/// A kind that accepts anything, for a genre whose validator this application
/// cannot reach.
///
/// The strategy rules live in the demo application beside its map, so what is
/// checked here is everything a registry does *not* answer — the geometry, the
/// lighting, the brush materials, the names that have to be unique — plus the
/// one thing a registry always answers, which is that no entity in the level
/// uses a word the vocabulary does not offer.
final class _AnyKind extends EntityKind {
  const _AnyKind(super.type);
}

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
    // The registry `apps/flutter3d_demo_racing/lib/main.dart` loads a circuit
    // with: empty rather than absent, because the loader validates against it
    // and an empty one is the statement that nothing is expected.
    _Template(
      'racing',
      EntityRegistry(const <EntityKind>[]),
      const <LevelRule>[],
      const <String>{},
    ),
    _Template(
      'strategy',
      EntityRegistry(<EntityKind>[
        for (final String word in _strategyWords()) _AnyKind(word),
      ]),
      const <LevelRule>[],
      _strategyWords(),
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

  test('and one for every genre this repository has', () {
    // **The acceptance the track is measured by**: a level of each of the four
    // genres can be started from nothing. A fifth genre with no template is a
    // genre somebody has to write a first document for by hand, which is the
    // state all four were in.
    expect(
      (jsonDecode(
                File('assets/templates/index.json').readAsStringSync(),
              )
              as Map<String, Object?>)['templates'],
      templates.map((_Template it) => it.genre).toList()..sort(),
    );
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

      test('and the application would actually ship it', () {
        // **The one failure in this file that compiles perfectly.** A bundle
        // cannot be listed and an `assets:` directory entry is not recursive,
        // so a template directory with no line of its own in `pubspec.yaml` is
        // a `rootBundle` exception in front of somebody creating a project —
        // with nothing said about it until then.
        expect(
          File('pubspec.yaml').readAsLinesSync().map((String it) => it.trim()),
          contains('- ${template.where}/'),
          reason: 'add ${template.where}/ to the editor\'s assets',
        );
      });
    });
  }

  group('racing', () {
    // **Half a circuit, and the half a level can be.** A track is points,
    // widths, banks, barriers, checkpoints and a starting grid, in a second
    // document read by `TrackDocument`; a level is the ground under it. Only
    // the second is something this editor knows how to open, so only the
    // second is what the template gives.
    final _Template racing = templates.firstWhere(
      (_Template it) => it.genre == 'racing',
    );

    test('places nothing, because a circuit does not', () {
      // The scenery is brushes and everything that is really an object belongs
      // to the track document, which is why the demo loads a circuit with an
      // empty registry. A word offered here would be one no racing game reads.
      expect(racing.read('editor.json'), isEmpty);
      expect(racing.level.entities, isEmpty);
      expect(racing.level.brushes, isNotEmpty);
    });

    test('and ships no track beside the level, deliberately', () {
      // If this ever fails, the thing to check is not the manifest: it is
      // whether something now edits a circuit. Nothing does.
      final files = (racing.read('index.json')['files']! as Map<String, Object?>)
          .values
          .cast<String>();

      expect(files.where((String it) => it.contains('track')), isEmpty);
    });

    test('and its air is a preset the racing package holds', () {
      // **The sky, the sun and the haze are one decision.** The reason the far
      // side of a circuit does not end in a visible band is that the fog and
      // the sky are the same arithmetic, and the only way to keep that true is
      // to make it impossible to author them apart — so the template's numbers
      // are `SkyPresets.morning`, checked here rather than trusted.
      final SkyPreset morning = SkyPresets.morning;
      final LevelLight sun = racing.level.lights.single;

      expect(sun.type, LevelLightType.directional);
      expect(sun.intensity, morning.sunIntensity);
      _closeTo(sun.color, morning.sunColor, 0.001);
      _closeTo(sun.direction, morning.sunDirection, 0.001);
      _closeTo(racing.level.fogColor, morning.horizonFogColour, 0.001);
      expect(racing.level.fogDensity, morning.fogDensity);
    });
  });

  group('strategy', () {
    // **A map, not a room.** Its ground is a heightfield and its opening is an
    // economy, and neither is something `make_templates.py` could invent and
    // still call playable — so the template is the map the demo is played on,
    // read out of that application rather than written twice.
    final _Template strategy = templates.firstWhere(
      (_Template it) => it.genre == 'strategy',
    );

    test('starts a project on the map the game is played on', () {
      final Level played = _playedMap();
      final Level start = strategy.level;

      expect(
        start.entities.map((EntityDef it) => it.toJson()),
        played.entities.map((EntityDef it) => it.toJson()),
      );
      expect(start.heightfield, isNotNull);
      expect(start.heightfield!.columns, played.heightfield!.columns);
      expect(start.heightfield!.rows, played.heightfield!.rows);
      expect(start.heightfield!.cellSize, played.heightfield!.cellSize);
    });

    test('and keeps the finishing line the format does not know', () {
      // `goal` is not a level's idea — a match is won by having brought home
      // more than the other side, which is a fact about the match and not
      // about a place — and `writeThrough` is what carries it through a save
      // by an editor that has no idea what it is.
      final document = strategy.read('level.first.json');

      expect(document['goal'], isNotNull);
      expect(Editing.parse(jsonEncode(document), path: 'x').write(), isNotEmpty);
    });

    test('and offers exactly the words that map is written in', () {
      // Equality rather than containment, in both directions: a word the
      // template offers and no map uses is one somebody invented here, and a
      // word the map uses and the template does not offer is a thing a new
      // project can delete and never put back.
      expect(strategy.read('editor.json').keys.toSet(), _strategyWords());
    });

    test('and draws each of them at the size the game builds it', () {
      // **Read off the package, not typed beside it.** A hall in play is
      // `Building.width` by `Building.depth` and stands as high as the bridge
      // raises it; a worker is one unit. The editor drawing either at some
      // other size is somebody placing a hall that turns out not to fit.
      final Looks looks = strategy.looks;
      const UnitSize unit = UnitSize();
      final Building hall = Building(
        centre: Vector3.zero(),
        width: 12.0,
        depth: 10.0,
        name: 'hall',
      );

      // `closeTo` and not equality: a `Look`'s size is a `Vector3`, which is
      // single precision, so the 1.2 this file writes comes back as the double
      // nearest the float — a different number denoting the same stored one.
      final Vector3? camp = looks.sizeFor(EntityDef(type: 'camp'));
      expect(camp, isNotNull);
      expect(camp!.x, closeTo(hall.width, 1e-6));
      expect(camp.y, closeTo(unit.height * 2.5, 1e-6));
      expect(camp.z, closeTo(hall.depth, 1e-6));

      final Vector3? worker = looks.sizeFor(EntityDef(type: 'worker'));
      expect(worker, isNotNull);
      expect(
        worker!.x,
        closeTo(Unit(position: Vector3.zero()).radius * 2.0, 1e-6),
      );
      expect(worker.y, closeTo(unit.height, 1e-6));
    });

    test('and asks a producer for what a producer costs', () {
      // The defaults a placed entity carries are the ones `Producer` itself
      // holds and `openMatch` falls back to; three copies of 25 and 4 in three
      // files is three chances for a new project to be quietly cheaper to play
      // than the game it was started from.
      final producer = Producer(
        building: Building(
          centre: Vector3.zero(),
          width: 1.0,
          depth: 1.0,
          name: 'hall',
        ),
      );
      final described =
          strategy.read('editor.json')['producer']! as Map<String, Object?>;
      final defaults = described['defaults']! as Map<String, Object?>;

      expect(defaults['cost'], producer.cost);
      expect(defaults['seconds'], producer.seconds);
    });
  });
}

/// Reports [a] and [b] as the same direction or colour, component by
/// component — a `Vector3` has no matcher of its own and `closeTo` takes a
/// number.
void _closeTo(Vector3 a, Vector3 b, double slack) {
  expect(a.x, closeTo(b.x, slack));
  expect(a.y, closeTo(b.y, slack));
  expect(a.z, closeTo(b.z, slack));
}
