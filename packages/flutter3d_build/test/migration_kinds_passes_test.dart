// What `flutter3d migrate` does that one run of the migrator does not: it
// runs the migrator several times, and a rule that matches what it wrote
// itself, or half wrote, migrates it again.
import 'package:test/test.dart';

import 'migration_kinds_support.dart';

void main() {
  test('a second pass changes nothing the first one wrote', () async {
    // Mutation: let a callback rule wrap a function that already has the
    // parameter's shape, and the second pass wraps `onRing` twice; let the
    // rename inside a hook's parameters win over the parameters rewritten
    // whole, and the first pass reads the context in a body whose method
    // does not take it, which the second pass migrates over again; rename a
    // class only where `dart:core` shadows its old name, and the board's
    // `Unit`, which another engine package's `Unit` shadows now, stays;
    // rewrite a call of a function-typed field only where it is a method
    // call, or rewrite one with fewer arguments than the template reads,
    // and `tool.run(1, 2)` keeps a TODO while 1.0's `tool.run(shift)` gets
    // one.
    final report = await migrateKindFixture('passes', passes: 2);
    expect(manualOf(report), isEmpty);
  });
}
