/// `writeEngineUserSkills` on its own — `par-03`'s own row.
///
///     dart test test/skills_writer_test.dart
library;

import 'dart:io';

import 'package:skills/skills.dart';
import 'package:test/test.dart';

void main() {
  test('writes one SKILL.md per skill, at the path a skill loader expects', () {
    final dir = Directory.systemTemp.createTempSync('flutter3d_skills_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final written = writeEngineUserSkills(dir);

    expect(written, hasLength(engineUserSkills.length));
    for (final skill in engineUserSkills) {
      final file = File('${dir.path}/.claude/skills/${skill.slug}/SKILL.md');
      expect(
        file.existsSync(),
        isTrue,
        reason: '${skill.slug} was not written',
      );
      expect(file.readAsStringSync(), skill.body);
    }
  });

  test(
    'every SKILL.md starts with name/description frontmatter naming itself',
    () {
      for (final skill in engineUserSkills) {
        expect(skill.body, startsWith('---\nname: ${skill.slug}\n'));
        expect(skill.body, contains('\ndescription: '));
      }
    },
  );

  test(
    'a repeat run produces byte-identical files — the acceptance line itself',
    () {
      final dir = Directory.systemTemp.createTempSync('flutter3d_skills_');
      addTearDown(() => dir.deleteSync(recursive: true));

      writeEngineUserSkills(dir);
      final before = <String, List<int>>{
        for (final skill in engineUserSkills)
          skill.slug: File(
            '${dir.path}/.claude/skills/${skill.slug}/SKILL.md',
          ).readAsBytesSync(),
      };

      // A second call, against a directory that already has every file —
      // the exact case `par-03`'s "repeat run — empty diff" line describes.
      writeEngineUserSkills(dir);
      for (final skill in engineUserSkills) {
        final after = File(
          '${dir.path}/.claude/skills/${skill.slug}/SKILL.md',
        ).readAsBytesSync();
        expect(after, equals(before[skill.slug]), reason: skill.slug);
      }
    },
  );

  test(
    'writing into a project that already has unrelated skills leaves them alone',
    () {
      final dir = Directory.systemTemp.createTempSync('flutter3d_skills_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ownSkill = File('${dir.path}/.claude/skills/my-own-thing/SKILL.md')
        ..createSync(recursive: true);
      ownSkill.writeAsStringSync('---\nname: my-own-thing\n---\nmine.\n');

      writeEngineUserSkills(dir);

      expect(
        ownSkill.readAsStringSync(),
        '---\nname: my-own-thing\n---\nmine.\n',
      );
    },
  );

  group(
    'the idioms/pitfalls skill names facts that still exist in the engine',
    () {
      late String source;
      setUpAll(() {
        source = File(
          '../../packages/flutter3d_core/lib/src/engine/scene/lod_group.dart',
        ).readAsStringSync();
      });

      String skillBody() => engineUserSkills
          .firstWhere(
            (skill) => skill.slug == 'flutter3d-user-idioms-and-pitfalls',
          )
          .body;

      test(
        'LodGroup.select is still the method the skill tells someone to call',
        () {
          expect(source, contains('int select('));
        },
      );

      test('the skill names the exact method it is describing', () {
        expect(skillBody(), contains('select(camera)'));
      });
    },
  );

  group(
    'the lighting/post skill names fields that still exist on RenderSettings',
    () {
      late String source;
      setUpAll(() {
        source = File(
          '../../packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
        ).readAsStringSync();
      });

      String skillBody() => engineUserSkills
          .firstWhere(
            (skill) => skill.slug == 'flutter3d-user-lighting-and-post',
          )
          .body;

      test('tonemap still defaults to true', () {
        expect(source, contains('this.tonemap = true,'));
        expect(skillBody(), contains('`tonemap` — **on**'));
      });

      test(
        'bloom is still on by default and reflections/AO/sky/xray still off',
        () {
          expect(source, contains('this.bloom = const BloomSettings(),'));
          expect(
            source,
            contains('this.reflections = const ReflectionSettings(),'),
          );
          expect(
            source,
            contains(
              'this.ambientOcclusion = const AmbientOcclusionSettings(),',
            ),
          );
          expect(source, contains('this.sky = const SkySettings(),'));
          expect(source, contains('this.xray = const XraySettings(),'));
        },
      );

      test('forStereo still exists, for the stereo note', () {
        expect(source, contains('RenderSettings forStereo()'));
        expect(skillBody(), contains('forStereo()'));
      });
    },
  );

  group('the performance skill names fields that still exist', () {
    test('LodGroup.select still takes an explicit field of view', () {
      final source = File(
        '../../packages/flutter3d_core/lib/src/engine/scene/lod_group.dart',
      ).readAsStringSync();
      expect(source, contains('verticalFieldOfView'));
      expect(source, contains('orthographicHeight'));
    });

    test('BloomSettings.levels is still the chain-length field', () {
      final source = File(
        '../../packages/flutter3d_core/lib/src/engine/render/render_settings.dart',
      ).readAsStringSync();
      expect(source, contains('final int levels;'));
    });
  });

  group('the playtests/network skill names an API that still exists', () {
    test('Demo still requires levelHash, buildStamp and checkpoints', () {
      final source = File(
        '../../packages/flutter3d_sim/lib/src/save/demo.dart',
      ).readAsStringSync();
      expect(source, contains('required this.levelHash'));
      expect(source, contains('required this.buildStamp'));
      expect(source, contains('required this.checkpoints'));
    });

    test(
      'NetSession still has inputDelay, maxRollbackFrames, redundancy and onSettled',
      () {
        final source = File(
          '../../packages/flutter3d_net/lib/src/net_session.dart',
        ).readAsStringSync();
        expect(source, contains('this.inputDelay = 2,'));
        expect(source, contains('this.maxRollbackFrames = 8,'));
        expect(source, contains('this.redundancy = 8,'));
        expect(source, contains('this.onSettled,'));
        expect(source, contains('int droppedCorrections = 0;'));
      },
    );
  });
}
