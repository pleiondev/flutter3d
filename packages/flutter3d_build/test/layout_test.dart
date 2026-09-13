import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() => project = Directory.systemTemp.createTempSync('f3d_layout_'));
  tearDown(() => project.deleteSync(recursive: true));

  test('an empty project — no assets_src/ at all — plans nothing', () {
    final layout = AssetLayout(projectRoot: project);
    expect(layout.plan(), isEmpty);
  });

  test('an assets_src/ with nothing recognised in it plans nothing', () {
    Directory('${project.path}/assets_src').createSync();
    File('${project.path}/assets_src/notes.txt').writeAsStringSync('hi');

    final layout = AssetLayout(projectRoot: project);
    expect(layout.plan(), isEmpty);
  });

  test(
    'without a manifest, every recognised file maps 1:1 into '
    'flutter3d_generated, extension swapped',
    () {
      Directory('${project.path}/assets_src/props').createSync(recursive: true);
      File('${project.path}/assets_src/hero.glb').writeAsStringSync('x');
      File(
        '${project.path}/assets_src/props/chair.obj',
      ).writeAsStringSync('x');

      final layout = AssetLayout(projectRoot: project);
      final plan = layout.plan();

      expect(plan, hasLength(2));
      final byName = {for (final job in plan) job.source.split('/').last: job};
      expect(
        byName['hero.glb']!.destination,
        '${project.path}/flutter3d_generated/hero.f3d',
      );
      expect(
        byName['chair.obj']!.destination,
        '${project.path}/flutter3d_generated/props/chair.f3d',
      );
      expect(byName['hero.glb']!.rule, isNull);
    },
  );

  test('a manifest rule that excludes a glob removes it from the plan', () {
    Directory('${project.path}/assets_src/ui').createSync(recursive: true);
    File('${project.path}/assets_src/hero.glb').writeAsStringSync('x');
    File('${project.path}/assets_src/ui/icon.glb').writeAsStringSync('x');
    File('${project.path}/flutter3d_assets.yaml').writeAsStringSync('''
rules:
  - glob: "ui/**"
    exclude: true
''');

    final layout = AssetLayout(projectRoot: project);
    final plan = layout.plan();

    expect(plan, hasLength(1));
    expect(plan.single.source, endsWith('hero.glb'));
  });

  test('a matching rule rides along on the plan, for the hook to read', () {
    Directory('${project.path}/assets_src').createSync(recursive: true);
    Directory('${project.path}/assets_src/props').createSync(recursive: true);
    File('${project.path}/assets_src/props/hero.glb').writeAsStringSync('x');
    File('${project.path}/flutter3d_assets.yaml').writeAsStringSync('''
rules:
  - glob: "**/*.glb"
    textures: bc
''');

    final layout = AssetLayout(projectRoot: project);
    final job = layout.plan().single;

    expect(job.rule, isNotNull);
    expect(job.rule!.textures, TextureFamily.bc);
  });

  test('a broken manifest surfaces its exception from the layout too', () {
    Directory('${project.path}/assets_src').createSync(recursive: true);
    File('${project.path}/flutter3d_assets.yaml').writeAsStringSync('typo: 1');

    expect(
      () => AssetLayout(projectRoot: project),
      throwsA(isA<ManifestFormatException>()),
    );
  });
}
