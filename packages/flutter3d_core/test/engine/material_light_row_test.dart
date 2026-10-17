/// A light type of a plugin's own reaches a lighting model written in the
/// material language: the block reads the light's code and its parameters,
/// tells its own type by name, and is handed the light the engine's stages
/// skip.
///
///     dart test test/engine/material_light_row_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LightType, MaterialParameters;
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show ShaderHandle;
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const String _hair = '''
f3dmat 3
material acme_hair_Hair {
  lighttype tube = acme.tube;
  light {
    let reach = clamp(1.0 - lightParams.x * 0.1, 0.0, 1.0);
    return albedo * nDotL * mix(1.0, reach, tube) + vec3(lightKind * 0.0);
  }
  fragment { return vec4(lit, alpha); }
}
''';

final class _Tube extends LightTypeHook {
  const _Tube();

  @override
  LightType get type =>
      const LightType.custom('acme.tube', base: LightType.point);
}

void main() {
  final program = parseMaterial(_hair);

  test('the light block reads the row, and its own type by name', () {
    // Mutation: drop `lightKind` and `lightParams` from the light inputs and
    // the CONTRACTS sentence names inputs that do not exist.
    expect(program.readsLightRow, isTrue);
    expect(program.lightTypes, <String, String>{'tube': 'acme.tube'});
    final model = describeMaterial(
      program,
    ).lightingModel(label: 'Hair', shaderName: 'acme_hair_Hair');
    expect(model.lightTypeMembers, <String, String>{
      'f3d_lighttype_tube': 'acme.tube',
    });
  });

  test("the material's loop hands a plugin's light to the block", () {
    final glsl = emitMaterialFragment(
      specializeMaterial(program, const MaterialVariant('acme_hair_Hair')),
    );
    // Mutation: gather through `AccumulateLights`, whose `SampleLight` zeroes
    // a code of 16 or more, and the model never sees its own light.
    expect(glsl, contains('vec3 MaterialLights(Surface s)'));
    expect(glsl, contains('if (f3d_light_kind > 15.5) {'));
    expect(glsl, contains('f3d_light_params = row_cone;'));
    expect(
      glsl,
      contains(
        'f3d_is_tube = abs(f3d_light_kind - '
        'material_params.f3d_lighttype_tube) < 0.5',
      ),
    );
    expect(glsl, isNot(contains('AccumulateLights(s)')));
  });

  test('an older source cannot read the row or declare a type', () {
    expect(
      () => parseMaterial(_hair.replaceFirst('f3dmat 3', 'f3dmat 2')),
      throwsA(isA<MaterialSyntaxException>()),
    );
    expect(
      () => parseMaterial(_hair.replaceFirst('acme.tube', 'tube')),
      throwsA(isA<MaterialSyntaxException>()),
      reason: 'a plugin light type is named <pluginId>.<name>',
    );
  });

  test('the renderer fills the code it gave the type', () {
    final device = FakeBackend();
    final renderer = Renderer.create(device: device);
    final camera = CameraNode()..setPosition(0.0, 3.0, 0.0);
    camera.lookAt(Vector3.zero());
    final model = describeMaterial(
      program,
    ).lightingModel(label: 'Hair', shaderName: 'acme_hair_Hair');
    final material = RenderMaterial(
      lighting: model,
      parameters: MaterialParameters(schema: program.schema),
    );
    final scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(device, const PlaneShape().build()),
          material,
        ),
      )
      ..add(camera);
    Map<String, List<double>>? bound() {
      device.passes.clear();
      renderer.render(
        width: 8,
        height: 8,
        scene: scene,
        views: <CameraView>[CameraView(camera: camera)],
      );
      bool ours(ShaderHandle? s) =>
          s?.name.startsWith('acme_hair_Hair') ?? false;
      for (final pass in device.passes) {
        for (final block in pass.commands.whereType<RecordedUniformBlock>()) {
          if (ours(block.shader) && block.block == 'MaterialParams') {
            return block.members;
          }
        }
      }
      return null;
    }

    // Mutation: bind the member as the material holds it and every model
    // reads minus one, a type no light has.
    expect(bound()!['f3d_lighttype_tube'], <double>[-1]);
    final registration = renderer.lightTypes.register(const _Tube());
    expect(
      renderer.lightTypes.codeNamed('acme.tube'),
      LightTypes.firstPluginCode,
    );
    expect(bound()!['f3d_lighttype_tube'], <double>[16]);
    registration.cancel();
    expect(renderer.lightTypes.codeNamed('acme.tube'), isNull);
  });
}
