// A check and a backend's own section are classes that can grow, and a
// check compares by its name and its run, so one list filters another.
import 'dart:typed_data';

import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

Future<void> _nothing(GraphicsDevice device) async {}

void main() {
  test('two checks with one name and one run are equal', () {
    // Mutation: drop `==`, and a backend's `checks:` built by filtering
    // `conformanceChecks` by `shaderChecks` keeps every shader check.
    const a = ConformanceCheck(name: 'a', run: _nothing);
    const b = ConformanceCheck(name: 'a', run: _nothing);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const ConformanceCheck(name: 'b', run: _nothing)));
  });

  test('the shader-free tier leaves out exactly the shader checks', () {
    final tier = conformanceChecks
        .where((ConformanceCheck c) => !shaderChecks.contains(c))
        .toList();
    expect(tier, isNotEmpty);
    expect(tier.length, conformanceChecks.length - shaderChecks.length);
  });

  test('an own section compares by what it holds', () {
    final bytes = ByteData(4);
    expect(
      OwnShaderSection(id: 'x', bytes: bytes, sdk: '3.13.0'),
      OwnShaderSection(id: 'x', bytes: bytes, sdk: '3.13.0'),
    );
  });
}
