/// `gal-05`: what an export owes, and what it does not.
///
///     dart test test/credits_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ModelProject _withObjects(List<ModelCredit?> credits) {
  var project = const ModelProject();
  for (var i = 0; i < credits.length; i++) {
    project = project.added(
      (int id) => ModelObject(
        id: id,
        name: 'object $i',
        geometry: EditedGeometry(EditMesh.cuboid()),
        transform: Matrix4.identity(),
        credit: credits[i],
      ),
    );
  }
  return project;
}

const ModelCredit _chair = (
  title: 'Chair',
  author: 'A. Maker',
  licence: 'CC BY 4.0',
  url: 'https://creativecommons.org/licenses/by/4.0/',
);

const ModelCredit _lamp = (
  title: 'Lamp',
  author: 'B. Other',
  licence: 'CC BY 4.0',
  url: 'https://creativecommons.org/licenses/by/4.0/',
);

void main() {
  test('a project that owes nothing gets no credits file', () {
    final ModelProject project = _withObjects(<ModelCredit?>[null, null]);

    // **Null rather than an empty file.** Mutation: always write one. A
    // project built from this application's own models then ships a
    // credits file that credits nobody, which reads as an admission that
    // something in it is somebody else's.
    expect(creditsIn(project), isEmpty);
    expect(creditsFile(project), isNull);
    expect(creditsLine(project), isNull);
  });

  test('one credit per author, however many objects carry it', () {
    final ModelProject project = _withObjects(<ModelCredit?>[
      _chair,
      _chair,
      _chair,
      null,
    ]);

    // Six chairs from one maker are one obligation. Mutation: one line per
    // object — the repetition reads as padding, and the one line that
    // matters is harder to find for it.
    expect(creditsIn(project), hasLength(1));
    expect(creditsFile(project), contains('A. Maker'));
    expect('CC BY 4.0'.allMatches(creditsFile(project)!), hasLength(1));
  });

  test('and a deleted object takes its obligation with it', () {
    final ModelProject project = _withObjects(<ModelCredit?>[_chair, _lamp]);
    expect(creditsIn(project), hasLength(2));

    final int chairId = project.objects.first.id;
    final ModelProject without = project.removed(chairId);

    // **A credit is for what is in the file.** Mutation: keep a
    // project-level list of everything ever inserted, and the export goes
    // on crediting somebody whose chair nobody kept.
    expect(creditsIn(without), hasLength(1));
    expect(creditsIn(without).single.author, 'B. Other');
  });

  test('the order is stable, so two exports of one document agree', () {
    final ModelProject one = _withObjects(<ModelCredit?>[_lamp, _chair]);
    final ModelProject other = _withObjects(<ModelCredit?>[_chair, _lamp]);

    // A credits file that reordered itself would show up as a diff in
    // every commit that touched anything.
    expect(
      creditsIn(one).map((ModelCredit it) => it.author),
      creditsIn(other).map((ModelCredit it) => it.author),
    );
    expect(creditsIn(one).first.author, 'A. Maker');
  });

  test('the file names the licence and where to read it', () {
    final String? file = creditsFile(
      _withObjects(<ModelCredit?>[_chair]),
      documentName: 'kitchen.glb',
    );

    // Mutation: write the author alone. Whoever opens the exported file
    // cannot then find the original or the terms, and a credit nobody can
    // check is not a credit.
    expect(file, contains('kitchen.glb'));
    expect(file, contains('Chair'));
    expect(file, contains('CC BY 4.0'));
    expect(file, contains('creativecommons.org/licenses/by/4.0/'));
  });

  test('the one-line form names everybody and points at the file', () {
    final String? line = creditsLine(
      _withObjects(<ModelCredit?>[_chair, _lamp]),
    );

    // A single field cannot hold a URL per author legibly; what it can do
    // is name them and say where the rest is.
    expect(line, contains('A. Maker'));
    expect(line, contains('B. Other'));
    expect(line, contains('CREDITS.txt'));
  });

  test('a credit survives the file, and a half-written one does not', () {
    final ModelProject project = _withObjects(<ModelCredit?>[_chair]);

    final ProjectRead read = readProject(writeProject(project));
    expect(read, isA<ProjectOpened>());
    final ModelObject back = (read as ProjectOpened).project.objects.single;
    expect(back.credit, isNotNull);
    expect(back.credit!.author, 'A. Maker');

    // **Mutation: read a credit whose author is missing as a credit.** The
    // export then writes a line that claims to attribute and names nobody
    // — worse than writing nothing at all.
    final ModelProject nameless = _withObjects(<ModelCredit?>[
      (
        title: 'Chair',
        author: '',
        licence: 'CC BY 4.0',
        url: 'https://example.invalid/',
      ),
    ]);
    final ProjectRead again = readProject(writeProject(nameless));
    expect((again as ProjectOpened).project.objects.single.credit, isNull);
  });
}
