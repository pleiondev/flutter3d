// A material's parameters by typed key or by name, checked against what
// the material declares, and overridden per node.
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const _source = '''
material water {
  uniform float waveHeight = 0.25;
  uniform vec3 tint = vec3(1.0, 0.5, 0.25);
  param float rim = 2.0;

  fragment {
    return vec4(tint * waveHeight * rim, 1.0);
  }
}
''';

const waveHeight = ParameterKey<double>(
  'waveHeight',
  ParameterType.float,
  unit: Unit.meter,
);
const tint = ParameterKey<LinearColor>('tint', ParameterType.color);
const rim = ParameterKey<double>('rim', ParameterType.float);

MaterialParameterSchema _schema() => parseMaterial(_source).schema;

void main() {
  group('the schema from a .f3dmat', () {
    test('lists each parameter with its width, default and kind', () {
      final schema = _schema();
      expect(schema.names, <String>['waveHeight', 'tint', 'rim']);
      final wave = schema['waveHeight']!;
      expect(wave.components, 1);
      expect(wave.defaultValue, <double>[0.25]);
      expect(wave.isUniform, isTrue);
      expect(schema['tint']!.components, 3);
      // A `param` is folded into the shader when it is compiled; it is in
      // the schema, but not something a draw can set.
      expect(schema['rim']!.isUniform, isFalse);
    });

    test('starts the values at the declared defaults', () {
      final values = MaterialParameters(schema: _schema());
      expect(values.valueOf(waveHeight), 0.25);
      expect(values.valueOf(tint), const LinearColor(1.0, 0.5, 0.25));
      expect(values.uniforms.keys, <String>['waveHeight', 'tint']);
    });
  });

  group('set and get by key', () {
    test('a value goes in as the floats the block reads', () {
      final values = MaterialParameters(schema: _schema())
        ..set(waveHeight, 0.75)
        ..set(tint, const LinearColor(0.1, 0.2, 0.3));
      expect(
        values.uniforms['waveHeight'],
        Float32List.fromList(<double>[0.75]),
      );
      expect(
        values.uniforms['tint'],
        Float32List.fromList(<double>[0.1, 0.2, 0.3]),
      );
      expect(values.valueOf(waveHeight), 0.75);
    });

    test('a key in another unit is converted into the declared one', () {
      // Mutation: write the number as it is, and 40 centimeters is 40
      // meters.
      final schema = MaterialParameterSchema(<ParameterDeclaration>[
        const ParameterDeclaration(
          'waveHeight',
          components: 1,
          defaultValue: <double>[0.25],
          unit: Unit.meter,
        ),
      ]);
      const inCentimeters = ParameterKey<double>(
        'waveHeight',
        ParameterType.float,
        unit: Unit.centimeter,
      );
      final values = MaterialParameters(schema: schema)
        ..set(inCentimeters, 40.0);
      expect(values.valueOf(waveHeight), closeTo(0.4, 1e-6));
      expect(values.valueOf(inCentimeters), closeTo(40.0, 1e-4));
    });

    test('a parameter the material does not declare is refused', () {
      final values = MaterialParameters(schema: _schema());
      expect(
        () => values.set(
          const ParameterKey<double>('wavHeight', ParameterType.float),
          1.0,
        ),
        throwsA(isA<MaterialParameterException>()),
      );
    });

    test('a value of the wrong width is refused', () {
      final values = MaterialParameters(schema: _schema());
      expect(
        () => values.set(
          const ParameterKey<Vector2>('waveHeight', ParameterType.vec2),
          Vector2(1, 2),
        ),
        throwsA(isA<MaterialParameterException>()),
      );
    });

    test('a param folded at compile time cannot be set on a draw', () {
      final values = MaterialParameters(schema: _schema());
      expect(
        () => values.set(rim, 3.0),
        throwsA(isA<MaterialParameterException>()),
      );
    });

    test('without a schema anything goes, as the raw map did', () {
      final values = MaterialParameters()..set(rim, 3.0);
      expect(values.valueOf(rim), 3.0);
    });
  });

  group('setNamed, for data', () {
    // The wave in meters, as a schema that knows its units says; a source
    // says no unit yet.
    MaterialParameterSchema withUnits() =>
        MaterialParameterSchema(<ParameterDeclaration>[
          const ParameterDeclaration(
            'waveHeight',
            components: 1,
            defaultValue: <double>[0.25],
            unit: Unit.meter,
          ),
          const ParameterDeclaration(
            'tint',
            components: 3,
            defaultValue: <double>[1, 1, 1],
          ),
        ]);

    test('takes a number, a list, a vector, a color or a quantity', () {
      final values = MaterialParameters(schema: withUnits())
        ..setNamed('waveHeight', 1)
        ..setNamed('tint', <num>[0, 1, 0]);
      expect(values.valueOf(waveHeight), 1.0);
      expect(values.valueOf(tint), const LinearColor(0.0, 1.0, 0.0));
      values
        ..setNamed('tint', Vector3(0.5, 0.5, 0.5))
        ..setNamed('waveHeight', const Quantity(50, Unit.centimeter));
      expect(values.valueOf(tint), const LinearColor(0.5, 0.5, 0.5));
      expect(values.valueOf(waveHeight), closeTo(0.5, 1e-6));
    });

    test('refuses a quantity of another dimension', () {
      final values = MaterialParameters(schema: withUnits());
      expect(
        () => values.setNamed('waveHeight', const Quantity(2, Unit.second)),
        throwsA(isA<UnitMismatchException>()),
      );
    });

    test('refuses a name and a shape it does not know', () {
      final values = MaterialParameters(schema: withUnits());
      expect(
        () => values.setNamed('nope', 1.0),
        throwsA(isA<MaterialParameterException>()),
      );
      expect(
        () => values.setNamed('tint', 'red'),
        throwsA(isA<MaterialParameterException>()),
      );
    });
  });

  group('a node overrides its material', () {
    test("the node's values win over its material's, for that node only", () {
      final material = RenderMaterial(
        parameters: MaterialParameters.over(<String, Float32List>{
          'waveHeight': Float32List.fromList(<double>[0.25]),
          'tint': Float32List.fromList(<double>[1, 1, 1]),
        }),
      );
      final node = MeshNode(_mesh(), material)
        ..parameters = (MaterialParameters()..set(waveHeight, 2.0));
      final other = MeshNode(_mesh(), material);
      final merged = node.parametersFor(material);
      expect(merged['waveHeight'], Float32List.fromList(<double>[2.0]));
      expect(merged['tint'], Float32List.fromList(<double>[1, 1, 1]));
      // Mutation: write the override into the material's own map, and the
      // other node draws with it too.
      expect(other.parametersFor(material)['waveHeight'], <double>[0.25]);
      expect(material.parameters['waveHeight'], <double>[0.25]);
    });

    test('a node without overrides reads its material as it is', () {
      final material = RenderMaterial()..parameters['waveHeight'] = <double>[1];
      final node = MeshNode(_mesh(), material);
      // The material's own floats, not a merged copy of them.
      expect(
        node.parametersFor(material)['waveHeight'],
        same(material.parameters['waveHeight']),
      );
    });
  });

  test('a material made over a map edits what the encoder binds', () {
    final held = <String, Float32List>{};
    final material = RenderMaterial(parameters: MaterialParameters.over(held));
    material.parameters.set(waveHeight, 1.5);
    expect(held['waveHeight'], <double>[1.5]);
    expect(material.parameters.uniforms['waveHeight'], <double>[1.5]);
  });
}

CpuMesh _mesh() => CpuMesh(const PlaneShape().build());
