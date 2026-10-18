/// What a catalogue of materials is held to, beyond each entry's own
/// plausibility: the shape every law, value and pair must have.
library;

import 'material_catalog.dart';
import 'physical_material.dart';
import 'property_groups.dart';
import 'property_law.dart';

/// What is wrong with the shape of [catalog], one sentence each; empty when
/// nothing is.
///
/// Every entry is held to:
///
/// * [PhysicalMaterial.problems], its numbers plausible in SI and every
///   group cited;
/// * **its laws agreeing with its numbers**: each law at the entry's
///   reference state gives its [PropertyLaw.value] exactly, a formula
///   measures its property's unit ([propertyUnits]) and reads, a table
///   rises;
/// * a confidence for every value, its own or the entry's
///   ([PhysicalMaterial.confidenceOf]);
/// * for a solid, a coefficient of friction ([MechanicalProperties.friction])
///   when [frictionForSolids] is set, as the engine's own catalogue has.
///
/// Every pair names two materials the catalogue holds.
///
/// What the conformance suite runs over a plugin's materials, and a test
/// over the engine's own (`MaterialCatalog.builtIn`).
List<String> checkMaterialCatalog(
  MaterialCatalog catalog, {
  bool frictionForSolids = false,
}) {
  final found = <String>[];
  for (final material in catalog.materials) {
    found.addAll(material.problems());
    final reference = material.referenceState;
    for (final group in material.groups) {
      for (final MapEntry(key: name, value: law) in group.laws.entries) {
        final where = '${material.id}: ${group.name}.$name';
        if (material.confidenceOf(law) == null) {
          found.add('$where says nothing of its confidence');
        }
        final double at;
        try {
          at = law.at(reference);
        } on Object catch (e) {
          found.add('$where: its law does not evaluate: $e');
          continue;
        }
        if (at != law.value) {
          found.add(
            '$where: its law gives $at at the reference state, not its '
            'value ${law.value}',
          );
        }
        if (law case final FormulaLaw formula) {
          final unit = propertyUnits['${group.name}.$name'];
          if (unit != null && formula.dimension != unit.dimension) {
            found.add(
              '$where: its formula measures ${formula.dimension}, not '
              '${unit.symbol}',
            );
          }
        }
      }
    }
    if (frictionForSolids &&
        (material.phase == MaterialPhase.solid ||
            material.phase == MaterialPhase.granular) &&
        material.mechanical?.friction == null) {
      found.add('${material.id}: a solid with no coefficient of friction');
    }
  }
  for (final pair in catalog.pairs) {
    found.addAll(pair.problems());
    for (final id in <String>[pair.first, pair.second]) {
      if (catalog.byId(id) == null) {
        found.add('${pair.key}: no material "$id" in the catalogue');
      }
    }
  }
  return found;
}
