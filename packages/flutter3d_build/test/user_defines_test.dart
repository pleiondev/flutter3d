import 'package:flutter3d_build/convert.dart' show TextureFamily;
import 'package:flutter3d_build/src/user_defines.dart';
import 'package:flutter3d_core/flutter3d_core.dart' show DeviceClass;
import 'package:test/test.dart';

/// The hook's `user_defines` are read strictly: a value that is not one of
/// the choices fails the build naming them, and a key the hook does not
/// read is warned about.
///
/// `textures: bx` used to fall back to the platform's family and
/// `fullShader: true` was never read, both in silence, while the manifest
/// beside them refused an unknown key with its line.
void main() {
  test('a texture family is read, and anything else names the choices', () {
    expect(texturesDefine(null), isNull);
    expect(texturesDefine('bc'), TextureFamily.bc);
    // Mutation: fall back to the platform's family again.
    for (final wrong in <Object>['bx', 3, true]) {
      expect(
        () => texturesDefine(wrong),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            allOf(
              contains('$wrong'),
              contains('auto, bc, etc2, universal, none'),
            ),
          ),
        ),
        reason: '$wrong',
      );
    }
  });

  test('device classes are read, and a class there is not names them', () {
    expect(deviceClassesDefine(null), isNull);
    expect(deviceClassesDefine(<Object?>['web']), <DeviceClass>[
      DeviceClass.web,
    ]);
    expect(deviceClassesDefine('phone,desktop'), <DeviceClass>[
      DeviceClass.phone,
      DeviceClass.desktop,
    ]);
    expect(
      () => deviceClassesDefine('phone,tablet'),
      throwsA(
        isA<FormatException>().having(
          (FormatException e) => e.message,
          'message',
          contains('phone, web, desktop'),
        ),
      ),
    );
  });

  test('a key the hook does not read is a warning naming it', () {
    // Mutation: read only the keys asked for, and `fullShader: true` is a
    // setting nobody is told changes nothing.
    final warnings = unknownUserDefineWarnings('''
name: game
hooks:
  user_defines:
    game:
      textures: bc
      fullShader: true
    other_package:
      anything: 1
''', package: 'game');
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('"fullShader"'));
    expect(warnings.single, contains('fullShaders'));
    expect(unknownUserDefineWarnings('name: game\n', package: 'game'), isEmpty);
    expect(unknownUserDefineWarnings(': not yaml [', package: 'game'), isEmpty);
  });
}
