/// A registry is made for one presenter type, and holds it to that type.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

/// What a backend package does: it cannot name the application's presenter
/// type, so it sees the registry as one of [Object]s.
void _registerAsABackendWould(DeviceRegistry registry, Object presenter) =>
    registry.addPresenter<FakeBackend>(presenter);

void main() {
  test('the presenter comes back as the registry\'s type, with no cast', () {
    // Mutation: `presenterFor` answering `Object?` again. This does not
    // compile: a String cannot be read from it without a cast.
    final registry = DeviceRegistry<String>()
      ..addPresenter<FakeBackend>('fake presenter');
    final String? presenter = registry.presenterFor(FakeBackend());
    expect(presenter, 'fake presenter');
  });

  test('a presenter of another type is refused when it is added', () {
    // Mutation: the list held as `Object` again — the wrong presenter is
    // accepted here and fails only when the first frame is shown, far from
    // the backend that added it.
    final registry = DeviceRegistry<String>();
    expect(
      () => _registerAsABackendWould(registry, 42),
      throwsA(isA<TypeError>()),
    );
    expect(registry.presenterFor(FakeBackend()), isNull);
  });
}
