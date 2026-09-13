/// `ui-04`'s own acceptance: mode-switch content is replaced wholesale —
/// tested directly, since `_Properties` (`main.dart`) is private to that
/// library and nothing in this app's own suite pumps the whole screen.
///
///     flutter test test/properties_sections_test.dart
library;

import 'package:flutter3d_modeler/src/ui/properties_sections.dart';
import 'package:flutter3d_modeler/src/ui/tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("ui-04's own acceptance: content replaced wholesale", () {
    test('object mode owns the object-editing sections, not mesh ones', () {
      final sections = sectionsFor(ModelerMode.object);

      expect(sections, contains(PropertiesSection.objects));
      expect(sections, contains(PropertiesSection.transform));
      expect(sections, contains(PropertiesSection.modifiers));
      // mat-04a-n's own row: phase 1 gets a material panel before the
      // phase-2 `Material` workspace exists, and object mode is where it
      // lives until then.
      expect(sections, contains(PropertiesSection.materials));
      // Mutation: leave `lastOperation`/`selection`/`mesh` in every mode
      // instead of just mesh mode's own. Object mode has no mesh element
      // selection to summarise and no per-element operation to adjust.
      expect(sections, isNot(contains(PropertiesSection.lastOperation)));
      expect(sections, isNot(contains(PropertiesSection.selection)));
      expect(sections, isNot(contains(PropertiesSection.mesh)));
    });

    test('mesh mode owns the operation/selection sections, not object ones', () {
      final sections = sectionsFor(ModelerMode.mesh);

      expect(sections, contains(PropertiesSection.lastOperation));
      expect(sections, contains(PropertiesSection.selection));
      expect(sections, contains(PropertiesSection.mesh));
      // Mutation: leave `objects`/`transform`/`modifiers` showing in mesh
      // mode too. A person editing a mesh does not need the whole scene's
      // object list scrolled past to reach the card they are actually using.
      expect(sections, isNot(contains(PropertiesSection.objects)));
      expect(sections, isNot(contains(PropertiesSection.transform)));
      expect(sections, isNot(contains(PropertiesSection.modifiers)));
      expect(sections, isNot(contains(PropertiesSection.materials)));
    });

    test('anim-07\'s own row: animation mode owns the animation section alone', () {
      final sections = sectionsFor(ModelerMode.animation);

      expect(sections, contains(PropertiesSection.animation));
      expect(sections, isNot(contains(PropertiesSection.objects)));
      expect(sections, isNot(contains(PropertiesSection.mesh)));
      expect(sections, isNot(contains(PropertiesSection.materials)));
    });

    test('display, view and budget show in every mode', () {
      for (final ModelerMode mode in ModelerMode.values) {
        final sections = sectionsFor(mode);
        expect(
          sections,
          containsAll(<PropertiesSection>[
            PropertiesSection.display,
            PropertiesSection.view,
            PropertiesSection.budget,
          ]),
          reason: '$mode dropped a cross-mode section',
        );
      }
    });
  });
}
