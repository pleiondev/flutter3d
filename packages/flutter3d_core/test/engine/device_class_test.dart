/// `N7`: which assets a device reads — the selector is a function of what the
/// device says and one measurement, and the answer is remembered.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

const DeviceTraits _desktopGpu = DeviceTraits(
  web: false,
  samplesBc: true,
  samplesMobileBlocks: false,
);
const DeviceTraits _appleLaptop = DeviceTraits(
  web: false,
  samplesBc: true,
  samplesMobileBlocks: true,
);
const DeviceTraits _phoneGpu = DeviceTraits(
  web: false,
  samplesBc: false,
  samplesMobileBlocks: true,
);
const DeviceTraits _browser = DeviceTraits(
  web: true,
  samplesBc: true,
  samplesMobileBlocks: false,
);

void main() {
  group('DeviceClass.parse', () {
    test('reads every class by its name', () {
      for (final c in DeviceClass.values) {
        expect(DeviceClass.parse(c.name), same(c));
        expect(DeviceClass.tryParse(c.name), same(c));
      }
    });

    // A name that is not a class is a mistake in the text read, and says so
    // with the names that would have done; `tryParse` is the lookup that
    // answers null.
    test('refuses a name that is not a class, naming the ones that are', () {
      expect(
        () => DeviceClass.parse('console'),
        throwsA(
          isA<UnknownDeviceClassException>()
              .having((e) => e.text, 'text', 'console')
              .having((e) => e.message, 'message', contains('phone, web')),
        ),
      );
      expect(DeviceClass.tryParse('console'), isNull);
    });
  });

  group('deviceClassPath', () {
    test('puts the class before the extension', () {
      expect(
        deviceClassPath(
          'flutter3d_generated/props/chair.f3d',
          DeviceClass.phone,
        ),
        'flutter3d_generated/props/chair.phone.f3d',
      );
      expect(
        deviceClassPath('levels/crypt.json', DeviceClass.desktop),
        'levels/crypt.desktop.json',
      );
    });

    test('a dot in a directory name is not an extension', () {
      expect(deviceClassPath('v1.2/chair', DeviceClass.web), 'v1.2/chair.web');
    });
  });

  group('DeviceClassSelector', () {
    const selector = DeviceClassSelector();

    test('the selector is deterministic for a given capability set and '
        'measurement', () {
      for (final traits in <DeviceTraits>[
        _desktopGpu,
        _appleLaptop,
        _phoneGpu,
        _browser,
      ]) {
        for (final micros in <int?>[null, 1000, 8000, 8001, 40000]) {
          final first = selector.choose(traits, measuredMicros: micros);
          for (var i = 0; i < 3; i++) {
            expect(
              selector.choose(traits, measuredMicros: micros),
              same(first),
              reason: '$traits at $micros us',
            );
          }
        }
      }
    });

    test('a browser is web whatever it samples and however fast it is', () {
      expect(selector.choose(_browser), DeviceClass.web);
      expect(selector.choose(_browser, measuredMicros: 1), DeviceClass.web);
      expect(
        selector.choose(_browser, measuredMicros: 100000),
        DeviceClass.web,
      );
    });

    test('a GPU that samples BC is a desktop, a fast one stays one', () {
      expect(selector.choose(_desktopGpu), DeviceClass.desktop);
      expect(selector.choose(_appleLaptop), DeviceClass.desktop);
      expect(
        selector.choose(_desktopGpu, measuredMicros: 8000),
        DeviceClass.desktop,
      );
    });

    test('the desktop limit is a Duration the caller sets', () {
      // Mutation: compare against the default instead of `desktopLimit`, and
      // the stricter selector keeps the 5 ms part a desktop.
      const strict = DeviceClassSelector(
        desktopLimit: Duration(milliseconds: 4),
      );
      expect(
        strict.choose(_desktopGpu, measuredMicros: 4000),
        DeviceClass.desktop,
      );
      expect(
        strict.choose(_desktopGpu, measuredMicros: 5000),
        DeviceClass.phone,
      );
      expect(
        const DeviceClassSelector().desktopLimit,
        const Duration(microseconds: 8000),
      );
    });

    test('a slow desktop part reads the phone files', () {
      expect(
        selector.choose(_desktopGpu, measuredMicros: 8001),
        DeviceClass.phone,
      );
    });

    test('a fast phone is still a phone: the measurement only demotes', () {
      expect(selector.choose(_phoneGpu), DeviceClass.phone);
      expect(selector.choose(_phoneGpu, measuredMicros: 1), DeviceClass.phone);
    });

    test('traits are read off the device', () {
      final noBc = FakeBackend(
        unsupportedFormats: const <TextureFormat>{
          TextureFormat.bc1RGBAUNormInt,
          TextureFormat.bc7RGBAUNormInt,
        },
      );
      final traits = DeviceTraits.of(noBc, web: false);
      expect(traits, _phoneGpu);
      expect(selector.choose(traits), DeviceClass.phone);
      expect(
        selector.choose(DeviceTraits.of(FakeBackend(), web: false)),
        DeviceClass.desktop,
      );
    });
  });

  group('DeviceClassPicker', () {
    test('measures once, then remembers', () async {
      final memory = InMemoryDeviceClassMemory();
      var measured = 0;
      Future<int> slow() async {
        measured++;
        return 20000;
      }

      final picker = DeviceClassPicker(traits: _desktopGpu, memory: memory);
      expect(await picker.pick(measure: slow), DeviceClass.phone);
      expect(await picker.pick(measure: slow), DeviceClass.phone);
      expect(measured, 1);

      // A new launch with the same memory reads the answer back.
      final again = DeviceClassPicker(traits: _desktopGpu, memory: memory);
      expect(await again.pick(measure: slow), DeviceClass.phone);
      expect(measured, 1);
      expect(await again.overridden, isFalse);
    });

    test('the player overrides it, and clearing the override measures '
        'again', () async {
      final memory = InMemoryDeviceClassMemory();
      final picker = DeviceClassPicker(traits: _desktopGpu, memory: memory);
      expect(await picker.pick(measure: () async => 20000), DeviceClass.phone);

      await picker.override(DeviceClass.desktop);
      expect(await picker.overridden, isTrue);
      expect(
        await picker.pick(measure: () async => 20000),
        DeviceClass.desktop,
      );

      await picker.override(null);
      expect(await picker.pick(measure: () async => 100), DeviceClass.desktop);
      expect(await picker.overridden, isFalse);
    });

    test('a class this device cannot read is refused as an override and '
        'forgotten when remembered', () async {
      final picker = DeviceClassPicker(
        traits: _browser,
        memory: InMemoryDeviceClassMemory('chosen:phone'),
      );
      expect(picker.choices, <DeviceClass>[DeviceClass.web]);
      expect(await picker.pick(), DeviceClass.web);
      expect(() => picker.override(DeviceClass.phone), throwsArgumentError);
    });

    test('an unreadable memory is a first launch', () async {
      final memory = InMemoryDeviceClassMemory('chosen:console');
      final picker = DeviceClassPicker(traits: _phoneGpu, memory: memory);
      expect(await picker.pick(), DeviceClass.phone);
      expect(await memory.read(), 'measured:phone');
    });
  });

  test('measureFrameMicros takes the median after the warm-up', () async {
    var calls = 0;
    final micros = await measureFrameMicros(
      () => calls++,
      warmUp: 2,
      frames: 5,
    );
    expect(calls, 7);
    expect(micros, greaterThanOrEqualTo(0));
  });
}
