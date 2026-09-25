/// Assets per device class — `N7`.
///
/// **One model, three files, one of them read.** `flutter3d_build` can write
/// `chair.phone.f3d`, `chair.web.f3d` and `chair.desktop.f3d` from one source,
/// each cut to its own budget: a shorter level-of-detail chain and smaller
/// textures for a phone, the full chain for a desktop. What is here is the
/// other half — the name each file goes by, and which of them this device
/// reads.
///
/// **Chosen once, not every frame.** A class decides which files a level
/// loads, and a file already loaded cannot be swapped for a cheaper one
/// without loading it again. So the choice is made on the loading screen,
/// from what the device says it samples plus a short measurement of what it
/// actually draws, and then remembered: the next launch reads the answer
/// rather than measuring again, and a player who disagrees overrides it.
/// Adapting to the frame as it goes is `AdaptiveQuality`'s job (or `AdaptiveScale`'s), not this one's.
///
/// Off unless asked for: nothing reads a class until an application picks one
/// and hands it to the loader, and a project whose build names no classes has
/// only the single `.f3d` it always had.
library;

import 'dart:async';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// A kind of device a build writes its own assets for.
///
/// A `final class` with const instances rather than an `enum`: a published
/// enum cannot grow a value without breaking every exhaustive `switch` over
/// it, and a fourth class (a console, a headset) is a thing a later build may
/// well want.
final class DeviceClass {
  const DeviceClass._(this.name);

  /// The class's own word — the one in a file name and in a manifest.
  final String name;

  /// A phone or tablet GPU: tile-based, block formats ASTC and ETC2, a
  /// thermal budget that a desktop never meets.
  static const DeviceClass phone = DeviceClass._('phone');

  /// A browser. Whatever machine it runs on, it reads only the web files,
  /// because those are the only ones a web build bundles.
  static const DeviceClass web = DeviceClass._('web');

  /// A desktop or laptop GPU: samples BC, and has the memory for full
  /// textures and the full level-of-detail chain.
  static const DeviceClass desktop = DeviceClass._('desktop');

  /// Every class, cheapest first.
  static const List<DeviceClass> values = <DeviceClass>[phone, web, desktop];

  /// The class named [text], or null when no class is called that.
  static DeviceClass? parse(String text) {
    for (final value in values) {
      if (value.name == text) return value;
    }
    return null;
  }

  /// The classes a native build carries or a web build carries: a browser
  /// reads only [web], and a native application never does.
  static List<DeviceClass> availableOn({required bool web}) => web
      ? const <DeviceClass>[DeviceClass.web]
      : const <DeviceClass>[phone, desktop];

  @override
  String toString() => name;
}

/// [path] with [deviceClass] put before its extension: `chair.f3d` becomes
/// `chair.phone.f3d`, `crypt.json` becomes `crypt.phone.json`.
///
/// The one spelling both sides use — the build writes this name and the
/// loader asks for it — so it lives in one function rather than in two
/// packages that would have to agree.
String deviceClassPath(String path, DeviceClass deviceClass) {
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  return dot > slash
      ? '${path.substring(0, dot)}.${deviceClass.name}${path.substring(dot)}'
      : '$path.${deviceClass.name}';
}

/// What a device says about itself that bears on its class.
///
/// Plain values rather than the device itself, so the choice made from them
/// is a function a test can hold: the same traits and the same measurement
/// always pick the same class.
final class DeviceTraits {
  const DeviceTraits({
    required this.web,
    required this.samplesBc,
    required this.samplesMobileBlocks,
  });

  /// [device]'s own answers. [web] is the one thing a device cannot say — the
  /// hardware layer names no platform — so the caller says it (`kIsWeb`).
  factory DeviceTraits.of(GraphicsDevice device, {required bool web}) =>
      DeviceTraits(
        web: web,
        samplesBc:
            device.supportsTextureFormat(TextureFormat.bc1RGBAUNormInt) ||
            device.supportsTextureFormat(TextureFormat.bc7RGBAUNormInt),
        samplesMobileBlocks:
            device.supportsTextureFormat(TextureFormat.astc4x4LDR) ||
            device.supportsTextureFormat(TextureFormat.etc2RGB8UNormInt),
      );

  /// Whether this is a browser.
  final bool web;

  /// Whether the GPU samples a BC format. Every desktop GPU does and almost
  /// no phone GPU does, which makes it the most honest single flag there is
  /// for "this is a desktop part": it is a property of the silicon, not a
  /// setting, and it cannot be switched off by a power saver.
  final bool samplesBc;

  /// Whether the GPU samples ASTC or ETC2 — what a phone's does. An Apple
  /// laptop answers yes here and to [samplesBc] as well, and is a desktop.
  final bool samplesMobileBlocks;

  @override
  bool operator ==(Object other) =>
      other is DeviceTraits &&
      other.web == web &&
      other.samplesBc == samplesBc &&
      other.samplesMobileBlocks == samplesMobileBlocks;

  @override
  int get hashCode => Object.hash(web, samplesBc, samplesMobileBlocks);

  @override
  String toString() =>
      'DeviceTraits(web: $web, bc: $samplesBc, astc/etc2: '
      '$samplesMobileBlocks)';
}

/// Which class a device is, from its [DeviceTraits] and one measurement.
///
/// **The flags decide the kind, the measurement only ever demotes.** A GPU
/// that samples BC is a desktop part, but a desktop part can be a ten-year-old
/// integrated one that draws the loading screen's probe no faster than a
/// phone; the measurement catches that and gives it the phone's files. The
/// other direction is never taken: a phone that measures fast on a cool
/// loading screen is still a phone ten minutes later, hot, and the desktop's
/// textures would not fit its memory then either.
final class DeviceClassSelector {
  const DeviceClassSelector({this.desktopMicros = 8000});

  /// The slowest a probe frame may be, in microseconds, and still be a
  /// desktop. Half a sixty-hertz frame: the probe is a small scene, and a
  /// device that needs more than that for it will not hold the full chain
  /// at its own resolution.
  final int desktopMicros;

  /// The class for [traits], given the probe frame took [measuredMicros]
  /// (null when nothing was measured, which leaves the flags to decide
  /// alone).
  DeviceClass choose(DeviceTraits traits, {int? measuredMicros}) {
    if (traits.web) return DeviceClass.web;
    final byFlags = traits.samplesBc ? DeviceClass.desktop : DeviceClass.phone;
    final tooSlow = measuredMicros != null && measuredMicros > desktopMicros;
    return byFlags == DeviceClass.desktop && tooSlow
        ? DeviceClass.phone
        : byFlags;
  }
}

/// Times [frame] the way a loading screen can afford to: [warmUp] calls
/// thrown away (the first frames pay for pipelines and uploads, which is not
/// what is being measured), then the median of [frames] more, in
/// microseconds.
///
/// The median rather than the mean, because one frame that met a garbage
/// collection would otherwise decide a class that is kept for good.
Future<int> measureFrameMicros(
  FutureOr<void> Function() frame, {
  int warmUp = 2,
  int frames = 8,
}) async {
  assert(frames >= 1);
  for (var i = 0; i < warmUp; i++) {
    await frame();
  }
  final samples = <int>[];
  final clock = Stopwatch();
  for (var i = 0; i < frames; i++) {
    clock
      ..reset()
      ..start();
    await frame();
    clock.stop();
    samples.add(clock.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

/// Where the chosen class is kept between launches.
///
/// An interface rather than a file, because where an application keeps a
/// setting is its own business — shared preferences, a save file, a
/// `localStorage` key — and this package names none of them.
abstract interface class DeviceClassMemory {
  /// What [write] last stored, or null when nothing was.
  Future<String?> read();

  /// Keeps [value]; null forgets it.
  Future<void> write(String? value);
}

/// A [DeviceClassMemory] that lasts as long as the process — the default, and
/// what a test uses.
final class InMemoryDeviceClassMemory implements DeviceClassMemory {
  InMemoryDeviceClassMemory([this._value]);

  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String? value) async => _value = value;
}

/// The class this device reads its assets as: picked once, remembered, and
/// overridable by the player.
///
/// What is remembered says which of the two it was — `measured:phone` or
/// `chosen:desktop` — so clearing an override measures again rather than
/// keeping the override's answer as if it had been measured.
final class DeviceClassPicker {
  DeviceClassPicker({
    required this.traits,
    DeviceClassMemory? memory,
    this.selector = const DeviceClassSelector(),
  }) : memory = memory ?? InMemoryDeviceClassMemory();

  final DeviceTraits traits;
  final DeviceClassMemory memory;
  final DeviceClassSelector selector;

  static const String _measured = 'measured:';
  static const String _chosen = 'chosen:';

  /// The classes a player may choose between here — see
  /// [DeviceClass.availableOn].
  List<DeviceClass> get choices => DeviceClass.availableOn(web: traits.web);

  /// The remembered class, or — the first time — the one [measure] and the
  /// traits pick, which is then remembered. [measure] is called only when
  /// nothing usable is remembered; null picks from the traits alone.
  ///
  /// A remembered class this device cannot read (a phone's answer carried to
  /// a browser by a synced setting) is forgotten and picked again.
  Future<DeviceClass> pick({Future<int> Function()? measure}) async {
    final remembered = _parse(await memory.read());
    if (remembered != null && choices.contains(remembered.$1)) {
      return remembered.$1;
    }
    final measured = measure == null ? null : await measure();
    final picked = selector.choose(traits, measuredMicros: measured);
    await memory.write('$_measured${picked.name}');
    return picked;
  }

  /// Whether the remembered class is the player's own choice.
  Future<bool> get overridden async => _parse(await memory.read())?.$2 ?? false;

  /// Keeps [deviceClass] as the player's choice, or with null forgets any
  /// choice so the next [pick] measures again.
  ///
  /// Throws an [ArgumentError] for a class [choices] does not hold: a web
  /// build bundles only the web files, so there is nothing for a phone
  /// override to read there.
  Future<void> override(DeviceClass? deviceClass) async {
    if (deviceClass == null) {
      await memory.write(null);
      return;
    }
    if (!choices.contains(deviceClass)) {
      throw ArgumentError.value(
        deviceClass,
        'deviceClass',
        'not among the classes this device reads (${choices.join(', ')})',
      );
    }
    await memory.write('$_chosen${deviceClass.name}');
  }

  /// The class in [text] and whether it was chosen, or null when [text]
  /// holds neither form.
  static (DeviceClass, bool)? _parse(String? text) => switch (text) {
    final String t when t.startsWith(_chosen) => switch (DeviceClass.parse(
      t.substring(_chosen.length),
    )) {
      final DeviceClass c => (c, true),
      null => null,
    },
    final String t when t.startsWith(_measured) => switch (DeviceClass.parse(
      t.substring(_measured.length),
    )) {
      final DeviceClass c => (c, false),
      null => null,
    },
    _ => null,
  };
}
