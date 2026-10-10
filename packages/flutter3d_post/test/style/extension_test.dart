/// An addon's own settings and its own lighting model, through the kernel's
/// open slots — the two things a third-party addon adds without touching
/// `flutter3d_core`.
///
///     dart test test/extension_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_post/style.dart';
import 'package:test/test.dart';

import 'frame_stage.dart';

/// A third party's settings: a strength and a switch, with a codec.
final class FrostSettings {
  const FrostSettings({this.enabled = false, this.strength = 0.5});

  final bool enabled;
  final double strength;

  FrostSettings copyWith({bool? enabled, double? strength}) => FrostSettings(
    enabled: enabled ?? this.enabled,
    strength: strength ?? this.strength,
  );

  static Object? write(FrostSettings value) => <String, Object?>{
    'enabled': value.enabled,
    'strength': value.strength,
  };

  static FrostSettings read(Object? json) {
    final map = json! as Map<String, Object?>;
    return FrostSettings(
      enabled: map['enabled']! as bool,
      strength: (map['strength']! as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FrostSettings &&
      other.enabled == enabled &&
      other.strength == strength;

  @override
  int get hashCode => Object.hash(enabled, strength);
}

const frost = SettingsSlot<FrostSettings>(
  'acme_frost.frost',
  defaults: FrostSettings(),
  toJson: FrostSettings.write,
  fromJson: FrostSettings.read,
);

RenderSettings _frostOff(RenderSettings s) =>
    s.withExtension(frost, s.extension(frost).copyWith(enabled: false));
bool _frostOn(RenderSettings s) => s.extension(frost).enabled;

const frostStep = RenderStep('frost', switchOff: _frostOff, isOn: _frostOn);

final class FrostAddon extends RenderStepAddon {
  const FrostAddon()
    : super(
        id: 'acme_frost.frost',
        adds: const <RenderStep>[frostStep],
        provides: const <RenderStep>[frostStep],
        settings: const <SettingsSlot<Object>>[frost],
      );
}

const ink = LightingModel('Ink', 'AcmeInk', usesMetallicRoughnessMap: false);

final class InkAddon extends LightingModelAddon {
  const InkAddon()
    : super(id: 'acme_ink.ink', models: const <LightingModel>[ink]);
}

void main() {
  group('settings slots', () {
    test('a slot nobody wrote reads its defaults', () {
      expect(const RenderSettings().extension(frost), const FrostSettings());
    });

    test('written, it survives copyWith and compares by value', () {
      final on = const RenderSettings().withExtension(
        frost,
        const FrostSettings(enabled: true),
      );
      expect(on.extension(frost).enabled, isTrue);
      // Mutation: drop `extensions: extensions ?? this.extensions` from
      // copyWith, and changing the exposure takes the frost away.
      expect(on.copyWith(exposure: 2.0).extension(frost).enabled, isTrue);
      expect(
        on.extensions,
        const RenderSettings()
            .withExtension(frost, const FrostSettings(enabled: true))
            .extensions,
      );
      expect(on.extensions, isNot(const SettingsExtensions()));
    });

    test('a built-in slot is the field', () {
      final fogged = const RenderSettings().withExtension(
        SettingsSlot.fog,
        FogSettings(density: 0.25),
      );
      expect(fogged.fog.density, 0.25);
      expect(fogged.extension(SettingsSlot.fog), same(fogged.fog));
      expect(fogged.extensions.isEmpty, isTrue);
      expect(
        () => const SettingsExtensions().put(
          SettingsSlot.bloom,
          const BloomSettings(),
        ),
        throwsArgumentError,
      );
    });

    test('JSON round-trips by id, and an unknown id is kept', () {
      final settings = const RenderSettings().withExtension(
        frost,
        const FrostSettings(enabled: true, strength: 0.25),
      );
      final json = <String, Object?>{
        ...settings.extensions.toJson(),
        'someone_else.glow': <String, Object?>{'k': 1},
      };
      expect(json['acme_frost.frost'], <String, Object?>{
        'enabled': true,
        'strength': 0.25,
      });

      final known = SettingsExtensions.fromJson(
        json,
        slots: const <SettingsSlot<Object>>[frost],
      );
      expect(
        known.valueOf(frost),
        const FrostSettings(enabled: true, strength: 0.25),
      );
      // Mutation: drop the raw entries from toJson, and a level saved by an
      // editor without the glow addon loses its glow.
      expect(known.toJson(), json);

      // Read with no slots at all, and decoded on first use.
      final unread = SettingsExtensions.fromJson(json);
      expect(unread.valueOf(frost), known.valueOf(frost));
      expect(unread, known);
    });

    test('an addon brings its slot to the renderer while it is on', () {
      final stage = FrameStage();
      final host = stage.install(const <RenderStepAddon>[FrostAddon()]);
      expect(stage.renderer.renderSteps.settingsNamed(frost.id), same(frost));
      expect(
        frostStep.isOn(
          const RenderSettings().withExtension(
            frost,
            const FrostSettings(enabled: true),
          ),
        ),
        isTrue,
      );
      // A switch asked for between frames lands at the next boundary.
      host
        ..disable(const FrostAddon().id)
        ..applyPending(1);
      expect(stage.renderer.renderSteps.settingsNamed(frost.id), isNull);
    });

    test('the style family lists its built-in slots', () {
      final stage = FrameStage()..install(styleAddons);
      expect(
        stage.renderer.renderSteps.settings,
        containsAll(<SettingsSlot<Object>>[
          SettingsSlot.highContrast,
          SettingsSlot.viewportShading,
        ]),
      );
    });
  });

  group('lighting models', () {
    test('toon is the kernel constant, and stays built in', () {
      expect(toonLighting, same(LightingModel.toon));
      expect(LightingModel.builtIn, contains(toonLighting));
      expect(LightingModels.named('Toon'), same(toonLighting));
    });

    test('the toon addon registers the model the way any plugin does', () {
      final stage = FrameStage();
      final host = stage.install(const <LightingModelAddon>[
        ToonLightingAddon(),
      ]);
      expect(
        LightingModels.all.where((m) => m.shaderName == 'Toon'),
        hasLength(1),
      );
      host
        ..disable(const ToonLightingAddon().id)
        ..applyPending(1);
      // Built in for 1.x, so withdrawing the addon leaves the name.
      expect(LightingModels.named('toon'), same(toonLighting));
    });

    test("a plugin's model is named while it is on, and not after", () {
      expect(LightingModels.named('AcmeInk'), isNull);
      final stage = FrameStage();
      final host = stage.install(const <LightingModelAddon>[InkAddon()]);
      expect(LightingModels.named('AcmeInk'), same(ink));
      expect(LightingModels.all.last, same(ink));
      host
        ..disable(const InkAddon().id)
        ..applyPending(1);
      expect(LightingModels.named('AcmeInk'), isNull);
    });

    test('a built-in name is refused to anything but the built-in model', () {
      expect(
        () => LightingModels.register(const LightingModel('Mine', 'Pbr')),
        throwsArgumentError,
      );
      final again = LightingModels.register(LightingModel.pbr);
      again.cancel();
      expect(LightingModels.named('Pbr'), same(LightingModel.pbr));
    });
  });
}
