/// The one shape a material's parameters have: what a renderer material, a
/// widget and a level each hold, read and written by name the way the map
/// they replaced was.
///
///     dart test test/material_parameters_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';

MaterialParameterSchema _schema() =>
    MaterialParameterSchema(const <ParameterDeclaration>[
      ParameterDeclaration('time', components: 1, defaultValue: <double>[0]),
      ParameterDeclaration(
        'tint',
        components: 3,
        defaultValue: <double>[1, 1, 1],
      ),
      ParameterDeclaration(
        'steps',
        components: 1,
        defaultValue: <double>[4],
        isUniform: false,
      ),
    ]);

void main() {
  test('indexing hands back the floats the draw binds, not a copy', () {
    // Mutation: return a copy from `[]` and the time written in place never
    // reaches the next frame.
    final parameters = MaterialParameters(schema: _schema());
    parameters['time']![0] = 2.5;
    expect(parameters.uniforms['time'], <double>[2.5]);
    expect(parameters.named('time'), <double>[2.5]);
    expect(parameters['nothing'], isNull);
  });

  test('a write by index is checked as a write by name is', () {
    final parameters = MaterialParameters(schema: _schema());
    final before = parameters.version;
    parameters['tint'] = Float32List.fromList(<double>[0.5, 0.25, 0]);
    expect(parameters['tint'], <double>[0.5, 0.25, 0]);
    expect(parameters.version, greaterThan(before));
    // Mutation: write without the schema's check and a misspelt or
    // too-short value is drawn as nought instead of refused.
    expect(
      () => parameters['tnit'] = <double>[1, 1, 1],
      throwsA(isA<MaterialParameterException>()),
    );
    expect(
      () => parameters['tint'] = <double>[1],
      throwsA(isA<MaterialParameterException>()),
    );
  });

  test('of copies numbers by name over the defaults', () {
    final source = <String, List<double>>{
      'tint': <double>[0, 1, 0],
    };
    final parameters = MaterialParameters.of(source, schema: _schema());
    expect(parameters.uniforms.keys, <String>['time', 'tint']);
    expect(parameters['tint'], <double>[0, 1, 0]);
    source['tint']![0] = 9;
    expect(parameters['tint'], <double>[0, 1, 0]);
    expect(
      () => MaterialParameters.of(const <String, List<double>>{
        'steps': <double>[8],
      }, schema: _schema()),
      throwsA(isA<MaterialParameterException>()),
    );
    // Without a schema any name and width is taken.
    expect(
      MaterialParameters.of(const <String, List<double>>{
        'anything': <double>[1, 2],
      })['anything'],
      <double>[1, 2],
    );
  });

  test('over writes into the map its caller still holds', () {
    final held = <String, Float32List>{};
    MaterialParameters.over(held)['wind'] = <double>[0.3];
    expect(held['wind'], Float32List.fromList(<double>[0.3]));
  });

  test('a copy shares no floats with its original', () {
    final original = MaterialParameters(schema: _schema());
    final copy = original.copy();
    copy['time']![0] = 1;
    expect(original['time'], <double>[0]);
    expect(copy.schema, same(original.schema));
    expect(copy.names, original.names);
  });

  test('adopting a new schema keeps what it still declares', () {
    final parameters = MaterialParameters(schema: _schema())
      ..['time'] = <double>[3]
      ..['tint'] = <double>[0.2, 0.2, 0.2];
    final holder = parameters;
    parameters.adopt(
      MaterialParameterSchema(const <ParameterDeclaration>[
        ParameterDeclaration('time', components: 1, defaultValue: <double>[0]),
        // Wider now: the old value cannot be what it means.
        ParameterDeclaration(
          'tint',
          components: 4,
          defaultValue: <double>[1, 1, 1, 1],
        ),
        ParameterDeclaration('wave', components: 1, defaultValue: <double>[7]),
      ]),
    );
    // Mutation: drop a kept value, or keep one at its old width, and a hot
    // reload either loses what the game set or binds a short member.
    expect(identical(holder, parameters), isTrue);
    expect(parameters['time'], <double>[3]);
    expect(parameters['tint'], <double>[1, 1, 1, 1]);
    expect(parameters['wave'], <double>[7]);
    expect(parameters.names, unorderedEquals(<String>['time', 'tint', 'wave']));
    expect(
      () => parameters['steps'] = <double>[1],
      throwsA(isA<MaterialParameterException>()),
    );
  });
}
