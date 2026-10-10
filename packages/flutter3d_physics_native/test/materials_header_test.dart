/// The core reads its substances from the catalogue: its generated header
/// is current, and the Dart presets are the catalogue's entries.
///
///     dart test test/materials_header_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';

import '../tool/gen_materials.dart';

/// [value] as the core's f32 holds it.
double _f32(double value) => (Float32List(1)..[0] = value)[0];

void main() {
  test('the generated header is what the catalogue writes', () {
    // Mutation: change a number in materials.dart without running
    // `dart run tool/gen_materials.dart` and this fails.
    final onDisk = File(headerPath).readAsStringSync().replaceAll('\r\n', '\n');
    expect(onDisk, generateMaterialsHeader());
  });

  test("the liquids' presets are the catalogue's entries", () {
    void same(NativeLiquidProperties preset, PhysicalMaterial material) {
      expect(preset.density, material.density, reason: material.id);
      expect(preset.viscosity, material.fluid!.viscosity, reason: material.id);
      expect(
        preset.tension,
        material.fluid!.surfaceTension,
        reason: material.id,
      );
    }

    same(NativeLiquidProperties.water, Materials.water);
    same(NativeLiquidProperties.seawater, Materials.seawater);
    same(NativeLiquidProperties.oliveOil, Materials.oliveOil);
    same(NativeLiquidProperties.honey, Materials.honey);
    same(NativeLiquidProperties.moltenBasalt, Materials.basaltMelt);
    // Decision 3: water at 20 °C, the same on both sides.
    expect(NativeLiquidProperties.water.density, 998.2);
    final heat = NativeLiquidHeat.water();
    expect(heat.specificHeat, 4182.0);
    expect(heat.conductivity, Materials.water.thermal!.conductivity);
    expect(heat.expansion, Materials.water.thermal!.volumetricExpansion);
    expect(heat.boils, isTrue);
  });

  test("the core's heat presets are the catalogue's entries", () {
    void same(NativeMaterial preset, PhysicalMaterial material) {
      final heat = material.thermal!;
      expect(
        preset.specificHeat,
        _f32(heat.specificHeat!),
        reason: material.id,
      );
      expect(
        preset.conductivity,
        _f32(heat.conductivity!),
        reason: material.id,
      );
      if (heat.emissivity case final e?) {
        expect(preset.emissivity, _f32(e), reason: material.id);
      }
      if (heat.ignitionTemperature case final t?) {
        expect(preset.ignitionTemperature, _f32(t), reason: material.id);
      }
      if (heat.heatOfCombustion case final h?) {
        expect(preset.heatOfCombustion, _f32(h), reason: material.id);
      }
      if (heat.radiantFraction case final r?) {
        expect(preset.flameRadiant, _f32(r), reason: material.id);
      }
      if (material.mechanical?.youngsModulus case final e?) {
        expect(preset.modulus, _f32(e), reason: material.id);
      }
      // And the view of the entry is the preset, to the bit.
      final view = NativeMaterial.of(material);
      expect(view.specificHeat, preset.specificHeat, reason: material.id);
      expect(view.flameSpread, preset.flameSpread, reason: material.id);
    }

    same(NativeMaterial.wood(), Materials.wood);
    same(NativeMaterial.oak(), Materials.oak);
    same(NativeMaterial.pine(), Materials.pine);
    same(NativeMaterial.paper(), Materials.paper);
    same(NativeMaterial.cardboard(), Materials.cardboard);
    same(NativeMaterial.thatch(), Materials.thatch);
    same(NativeMaterial.charcoal(), Materials.charcoal);
    same(NativeMaterial.paraffin(), Materials.paraffin);
    same(NativeMaterial.rubber(), Materials.rubber);
    same(NativeMaterial.steel(), Materials.steel);
    same(NativeMaterial.stone(), Materials.granite);
    // The wood fire's flame is the mean gas every wood preset shares.
    expect(
      NativeMaterial.wood().flameTemperature,
      NativeMaterial.oak().flameTemperature,
    );
  });

  test("a plugin's material reaches the core through its view", () {
    const peat = PhysicalMaterial(
      id: 'bog.peat',
      name: 'peat',
      phase: MaterialPhase.solid,
      thermal: ThermalProperties(
        specificHeat: 1900.0,
        conductivity: 0.06,
        ignitionTemperature: 500.0,
        heatOfCombustion: 1.4e7,
        source: 'a test',
      ),
    );
    final view = NativeMaterial.of(peat);
    expect(view.specificHeat, _f32(1900.0));
    expect(view.ignitionTemperature, _f32(500.0));
    // What it does not say is the inert preset's.
    expect(view.emissivity, NativeMaterial.inert().emissivity);
    expect(() => NativeLiquidProperties.of(peat), throwsArgumentError);
  });

  test('σ is one number on both sides', () {
    expect(
      RegExp(
        r'#define F3D_STEFAN_BOLTZMANN F3D_R\(([^)]+)\)',
      ).firstMatch(File(headerPath).readAsStringSync())!.group(1),
      stefanBoltzmann.toString(),
    );
  });
}
