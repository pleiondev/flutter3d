/// The engine's own physical materials, `f3d.*`: written once, generated
/// from their data.
///
/// **Every number here is read, never copied.** A liquid's preset
/// (`FluidMedium.water`, `NativeLiquidProperties.water`), the core's heat
/// presets (`NativeMaterial.oak`) and the C core's own defaults (the header
/// `tool/gen_materials.dart` writes from this catalogue) are views of these
/// entries, and a structure rule holds the header to them. A value changed
/// changes it everywhere, which is the point and also the warning: what a
/// recorded run, tape or golden was made under moves with it.
///
/// **Generated, from data with sources.** `materials.g.dart` is written by
/// `tool/gen_catalog.dart` from `tool/data/sources/`: the entries the
/// catalogue had before 1.0, about a hundred and twenty fluids and as many
/// solids, each value with its source, its confidence and its law where one
/// is known. Change the data and run the generator; the file says so too.
/// Values are at 20 °C and one standard atmosphere unless an entry's
/// `temperature` says otherwise: reference values for simulation, not for
/// design or safety calculations.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Unit;

import 'material_catalog.dart';
import 'material_state.dart';
import 'physical_material.dart';
import 'property_groups.dart';
import 'property_law.dart';

part 'materials.g.dart';
