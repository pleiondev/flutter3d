/// A scene binding as data: how a `.f3dplugin`'s `bindings:` section writes
/// one, read back whole (D37).
///
///     dart test test/scene_binding_test.dart
///
/// Mutation: drop `extra` from `toJson` and the round trip loses the key a
/// later version wrote.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

void main() {
  test('a binding reads, writes and keeps what it does not know', () {
    final json = <String, Object?>{
      'component': 'acme_forge.heat',
      'node': 'f3d.mesh',
      'material': 'glow.fmat',
      'parameters': <String, Object?>{'temperature': 'glowStrength'},
      'interpolation': 'step',
      'lifetime': 'entity',
      'priority': 3,
    };
    final spec = SceneBindingSpec.fromJson(json);
    expect(spec.component, 'acme_forge.heat');
    expect(spec.nodeKind, 'f3d.mesh');
    expect(spec.parameters, <String, String>{'temperature': 'glowStrength'});
    expect(spec.interpolation, BindingInterpolation.step);
    expect(spec.lifetime, BindingLifetime.entity);
    expect(spec.extra, <String, Object?>{'priority': 3});
    expect(spec.toJson(), json);
  });

  test('the defaults are written as nothing', () {
    const spec = SceneBindingSpec(component: 'acme.c', nodeKind: 'acme.k');
    expect(spec.toJson(), <String, Object?>{
      'component': 'acme.c',
      'node': 'acme.k',
    });
  });

  test('a binding that is not one is refused with what is wrong', () {
    expect(
      () => SceneBindingSpec.fromJson(<String, Object?>{'node': 'f3d.mesh'}),
      throwsA(
        isA<DocumentFormatException>().having(
          (e) => e.message,
          'message',
          contains('"component"'),
        ),
      ),
    );
    expect(
      () => SceneBindingSpec.fromJson(<String, Object?>{
        'component': 'acme.c',
        'node': 'acme.k',
        'interpolation': 'cubic',
      }),
      throwsA(
        isA<DocumentFormatException>().having(
          (e) => e.message,
          'message',
          contains('"cubic"'),
        ),
      ),
    );
  });
}
