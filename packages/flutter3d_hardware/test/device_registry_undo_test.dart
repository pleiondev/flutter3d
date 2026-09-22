/// Taking a backend or a presenter back off the registry.
///
///     dart test test/device_registry_undo_test.dart
///
/// **The defect this exists for is a green test, not a crash.** `very_good
/// test` runs a package's whole suite in one process, so a backend registered
/// by one test file is still registered for every file after it. A fake that
/// draws nothing — registered to keep a widget test off the software
/// rasteriser — then becomes the backend a later test's *picture* is drawn
/// with, and an empty frame compares equal to another empty frame. Nothing
/// fails; the assertion simply stops meaning anything.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

/// A named opener that answers with a fake, so two of them can be told apart
/// by which instance came back.
({BackendOpener open, FakeBackend device}) opener() {
  final device = FakeBackend();
  return (
    open: ({required int width, required int height}) async => device,
    device: device,
  );
}

void main() {
  group('a backend registration', () {
    test(
      'is gone after undo, and what was there before answers again',
      () async {
        final first = opener();
        final firstRegistration = registerBackendOpener('first', first.open);
        addTearDown(firstRegistration.undo);

        final second = opener();
        final secondRegistration = registerBackendOpener('second', second.open);

        // Last registered is tried first.
        expect(
          identical(
            await openRegisteredDevice(width: 4, height: 4),
            second.device,
          ),
          isTrue,
        );

        secondRegistration.undo();

        expect(
          identical(
            await openRegisteredDevice(width: 4, height: 4),
            first.device,
          ),
          isTrue,
          reason:
              'undoing the newer registration must uncover the older one, '
              'not empty the registry',
        );
      },
    );

    test('undo twice removes one registration, not two', () async {
      final first = opener();
      final a = registerBackendOpener('same name', first.open);
      addTearDown(a.undo);
      final second = opener();
      final b = registerBackendOpener('same name', second.open);

      b.undo();
      b.undo();

      expect(
        identical(
          await openRegisteredDevice(width: 4, height: 4),
          first.device,
        ),
        isTrue,
        reason:
            'the second undo must not reach past its own registration and '
            'take the one underneath',
      );
    });

    test('a fallback puts back the fallback it displaced', () async {
      // The one state `openRegisteredDevice` cannot recover from is having no
      // fallback at all, so a test that registers one must not be able to
      // leave the build without one.
      final original = opener();
      final originalRegistration = registerBackendOpener(
        'original fallback',
        original.open,
        asFallback: true,
      );
      addTearDown(originalRegistration.undo);

      final replacement = opener();
      final replacementRegistration = registerBackendOpener(
        'replacement fallback',
        replacement.open,
        asFallback: true,
      );

      expect(
        identical(
          await openRegisteredDevice(width: 4, height: 4),
          replacement.device,
        ),
        isTrue,
      );

      replacementRegistration.undo();

      expect(
        identical(
          await openRegisteredDevice(width: 4, height: 4),
          original.device,
        ),
        isTrue,
        reason:
            'undoing a fallback must restore the one it replaced, because '
            'there is only ever one slot and an empty one throws',
      );
    });
  });

  group('a presenter registration', () {
    test('is gone after undo, and an earlier one comes back', () {
      final device = FakeBackend();
      const first = 'first presenter';
      const second = 'second presenter';

      final firstRegistration = registerDevicePresenter<FakeBackend>(first);
      addTearDown(firstRegistration.undo);
      expect(lookUpDevicePresenter(device), first);

      final secondRegistration = registerDevicePresenter<FakeBackend>(second);
      expect(lookUpDevicePresenter(device), second);

      secondRegistration.undo();
      expect(lookUpDevicePresenter(device), first);
    });

    test(
      'undoing the only registration leaves nothing, not an empty string',
      () {
        final device = FakeBackend();
        final registration = registerDevicePresenter<FakeBackend>('only');
        registration.undo();

        expect(
          lookUpDevicePresenter(device),
          isNull,
          reason:
              'a type that never had a presenter and one whose presenter was '
              'undone have to look the same, or the caller cannot tell whether '
              'to register one',
        );
      },
    );

    test('undo does nothing once something else has replaced it', () {
      final device = FakeBackend();
      final mine = registerDevicePresenter<FakeBackend>('mine');
      final theirs = registerDevicePresenter<FakeBackend>('theirs');
      addTearDown(theirs.undo);

      mine.undo();

      expect(
        lookUpDevicePresenter(device),
        'theirs',
        reason:
            'a cleanup that overwrites a newer registration is not a '
            'cleanup; it is a second bug in the shape of one',
      );
    });
  });
}
