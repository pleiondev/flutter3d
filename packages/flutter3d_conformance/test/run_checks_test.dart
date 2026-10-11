// `runDeviceConformance(checks:)`: a backend runs the tier it has reached,
// and only that.
import 'package:flutter3d_conformance/flutter3d_conformance.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

final List<String> _ran = <String>[];

void main() {
  group('a suite of two checks', () {
    // Mutation: ignore `checks` and run `conformanceChecks`, and every check
    // of the suite is registered here, the two below among them.
    runDeviceConformance(
      backend: 'fake',
      makeDevice: ({required int width, required int height}) => FakeBackend(),
      checks: <ConformanceCheck>[
        (
          name: 'the first',
          run: (GraphicsDevice device) async => _ran.add('the first'),
        ),
        (
          name: 'the second',
          run: (GraphicsDevice device) async => _ran.add('the second'),
        ),
      ],
    );
  });

  test('ran the checks it was given, and no other', () {
    expect(_ran, <String>['the first', 'the second']);
  });
}
