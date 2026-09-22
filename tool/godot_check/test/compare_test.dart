/// What `compareReadings` notices, each rule broken on purpose.
///
///     dart test
///
/// The Godot half cannot run here — it wants a 250 MB engine binary and four
/// seconds — so this drives the comparison with readings written by hand.
/// That is the half where a rule can be wrong quietly: a check that pairs
/// surfaces badly, or forgives a bound it should not, passes every committed
/// fixture and says nothing about the next one.
library;

import 'package:godot_check/godot_check.dart';
import 'package:test/test.dart';

SurfaceReading _surface({
  String material = 'oak',
  int triangles = 12,
  bool skinned = false,
  double size = 1.0,
  double at = 0.0,
}) => SurfaceReading(
  material: material,
  triangles: triangles,
  skinned: skinned,
  min: <double>[at - size, at - size, at - size],
  max: <double>[at + size, at + size, at + size],
);

FileReading _file(List<SurfaceReading> surfaces) =>
    FileReading(surfaces: surfaces);

void main() {
  test('two readings that agree say nothing', () {
    final reading = _file(<SurfaceReading>[
      _surface(),
      _surface(material: 'pine', triangles: 40, at: 3.0),
    ]);
    expect(compareReadings('a.glb', reading, reading), isEmpty);
  });

  test('a surface Godot did not build is named', () {
    // Mutation: drop one surface from Godot's side. This is the shape a
    // dropped primitive takes — a file that draws four legs here and three
    // there — and it is why the count check comes before everything else.
    final ours = _file(<SurfaceReading>[_surface(), _surface(at: 3.0)]);
    final theirs = _file(<SurfaceReading>[_surface()]);
    expect(compareReadings('a.glb', ours, theirs), <Matcher>[
      contains('surfaces: 2 in the document, 1 in Godot'),
    ]);
  });

  test('a triangle count that moved is named', () {
    final ours = _file(<SurfaceReading>[_surface(triangles: 12)]);
    final theirs = _file(<SurfaceReading>[_surface(triangles: 11)]);
    final problems = compareReadings('a.glb', ours, theirs);
    expect(problems.first, contains('triangles: 12 in the document, 11'));
    // And the group check says it a second way: the pairing key carries the
    // triangle count, so a surface with a different one finds no partner.
    expect(problems.length, greaterThan(1));
  });

  test('a material Godot named differently is named', () {
    final ours = _file(<SurfaceReading>[_surface(material: 'oak')]);
    final theirs = _file(<SurfaceReading>[_surface(material: 'Oak')]);
    expect(
      compareReadings('a.glb', ours, theirs).single,
      contains('materials'),
    );
  });

  test('bounds Godot cut into are geometry lost', () {
    // Mutation: pull Godot's box in by a thousandth. Containment is the only
    // rule a skinned surface gets, so if this passed, a skinned mesh could
    // lose geometry and nothing here would say so.
    final ours = _file(<SurfaceReading>[_surface(size: 1.0)]);
    final theirs = _file(<SurfaceReading>[_surface(size: 0.999)]);
    expect(
      compareReadings('a.glb', ours, theirs).single,
      contains('cut into ours'),
    );
  });

  test('a float32 rounding down is not', () {
    // The measured worst across the seven committed fixtures is 1.9e-9, so a
    // containment rule with no slack in it would fail on files that are fine.
    final ours = _file(<SurfaceReading>[_surface(size: 1.0)]);
    final theirs = _file(<SurfaceReading>[_surface(size: 1.0 - 1e-9)]);
    expect(compareReadings('a.glb', ours, theirs), isEmpty);
  });

  test('a box Godot grew is a fault on an unskinned surface', () {
    // The other half of the bound rule. Containment alone would forgive a
    // surface a hundred times too small, because a bigger box contains it.
    final ours = _file(<SurfaceReading>[_surface(size: 1.0)]);
    final theirs = _file(<SurfaceReading>[_surface(size: 2.6)]);
    expect(
      compareReadings('a.glb', ours, theirs).single,
      contains('bounds differ by'),
    );
  });

  test('and is not one on a skinned surface', () {
    // Godot pads a skinned mesh's AABB to cover where the skeleton can take
    // it — 2.6× the real box on `hero.glb`'s twenty-triangle eye patch — so
    // the tight rule cannot apply there. Mutation: set `skinned: false` on
    // both sides of this pair and the test above is what happens.
    final ours = _file(<SurfaceReading>[_surface(size: 1.0, skinned: true)]);
    final theirs = _file(<SurfaceReading>[_surface(size: 2.6, skinned: true)]);
    expect(compareReadings('a.glb', ours, theirs), isEmpty);
  });

  test('surfaces pair by what they are, not by where they came in', () {
    // `case4.glb` is why. Godot emits its nineteen surfaces in a different
    // order from the file's and renames `Foot.L` to `Foot_L2`; pairing by
    // index reported fifteen of the nineteen as changed when nothing had.
    // Mutation: pair by index instead and this test goes red.
    final ours = _file(<SurfaceReading>[
      _surface(material: 'oak', at: 0.0),
      _surface(material: 'oak', at: 3.0),
      _surface(material: 'pine', triangles: 40, at: 6.0),
    ]);
    final theirs = _file(<SurfaceReading>[
      _surface(material: 'pine', triangles: 40, at: 6.0),
      _surface(material: 'oak', at: 3.0),
      _surface(material: 'oak', at: 0.0),
    ]);
    expect(compareReadings('a.glb', ours, theirs), isEmpty);
  });

  test('two surfaces alike in everything but place still pair', () {
    // The ambiguous case the group ordering exists for: same material, same
    // triangle count, different places. Both sides sort a group by where its
    // members sit, so the pairing is the same on both — and a member that
    // actually moved falls out of it.
    final ours = _file(<SurfaceReading>[_surface(at: 0.0), _surface(at: 5.0)]);
    expect(
      compareReadings(
        'a.glb',
        ours,
        _file(<SurfaceReading>[_surface(at: 5.0), _surface(at: 0.0)]),
      ),
      isEmpty,
    );
    expect(
      compareReadings(
        'a.glb',
        ours,
        _file(<SurfaceReading>[_surface(at: 5.0), _surface(at: 0.5)]),
      ),
      isNotEmpty,
    );
  });

  test('a file Godot could not read at all says only that', () {
    final ours = _file(<SurfaceReading>[_surface()]);
    const theirs = FileReading(
      error: 'Godot could not load the imported scene',
      surfaces: <SurfaceReading>[],
    );
    expect(compareReadings('a.glb', ours, theirs), <Matcher>[
      contains('could not load'),
    ]);
  });
}
