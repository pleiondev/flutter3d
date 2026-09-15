/// `ux-06`: what the import screen assumes before a person changes anything,
/// and what it says about a size that cannot be right.
///
///     flutter test test/import_defaults_test.dart
///
/// **One guess applied to every format was the wrong guess where it shows
/// least.** The screen opened on metres and no welding for everything;
/// `ImportPlan` itself already said `weld = true`. An eight-millimetre teapot
/// opened at metre scale is eight metres across and framed from far enough
/// away to look ordinary, so nothing on screen says anything is wrong until
/// the model is beside something else.
library;

import 'package:flutter3d_modeler/src/import_plan.dart';
import 'package:flutter3d_modeler/src/ui/import_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the unit a format is written in', () {
    test('an STL is millimetres', () {
      // The one format with no unit in it at all, and the one a scanner and
      // a slicer both write. Mutation: answer metres for everything, which
      // is what this did — every scan then arrives a thousand times too
      // large, with nothing said.
      expect(unitForFile('teapot.stl'), ImportUnit.millimetres);
      expect(unitForFile('TEAPOT.STL'), ImportUnit.millimetres);
    });

    test('and a glTF is metres, which its own specification says', () {
      expect(unitForFile('helmet.glb'), ImportUnit.metres);
      expect(unitForFile('helmet.gltf'), ImportUnit.metres);
      expect(unitForFile('chair.obj'), ImportUnit.metres);
    });

    test(
      'a name this build cannot read a format off keeps the old default',
      () {
        expect(unitForFile(null), ImportUnit.metres);
        expect(unitForFile(''), ImportUnit.metres);
        expect(unitForFile('no-extension'), ImportUnit.metres);
      },
    );
  });

  group('whether topology gets built', () {
    test('an STL welds, because a triangle soup has no shared vertices', () {
      // Every mesh command refuses an unwelded import until something builds
      // topology for it — `BakeToMesh`'s own doc comment. Mutation: leave it
      // off, which is the contradiction this row names: `ImportPlan`'s own
      // default already said true and the screen overrode it with false.
      expect(weldForFile('scan.stl'), isTrue);
    });

    test('and a glTF does not, since it already has them', () {
      expect(weldForFile('helmet.glb'), isFalse);
      expect(weldForFile(null), isFalse);
    });
  });

  group('the plausibility hint under Bounds', () {
    test('a model of an ordinary size says nothing at all', () {
      // A bolt, a chair, a building. A hint that fired on anything unusual
      // would be a hint people learn to dismiss, which is the same as none.
      expect(plausibilityHintFor(0.02), isNull);
      expect(plausibilityHintFor(1.7), isNull);
      expect(plausibilityHintFor(40), isNull);
    });

    test('a millimetre file read as metres is named', () {
      // An eight-millimetre teapot at metre scale: eight metres across.
      final String? hint = plausibilityHintFor(8000);
      expect(hint, isNotNull);
      expect(hint, contains('mm'));
    });

    test('and a metre file read as millimetres too', () {
      final String? hint = plausibilityHintFor(0.0017);
      expect(hint, isNotNull);
      expect(hint, contains('millimetres'));
    });

    test('an empty document is not a wrong unit', () {
      // Nothing in it is nothing to be wrong about, and a hint about the
      // unit of an empty file is noise on the one screen a person is being
      // asked to make a decision on.
      expect(plausibilityHintFor(0), isNull);
    });
  });
}
