/// The one sort behind phases, systems and plugins.
///
///     dart test test/order_test.dart
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

typedef _Item = ({String name, List<String> after, List<String> before});

_Item _item(
  String name, {
  List<String> after = const <String>[],
  List<String> before = const <String>[],
}) => (name: name, after: after, before: before);

List<String> _order(List<_Item> items) => orderByConstraints<_Item>(
  items,
  nameOf: (i) => i.name,
  after: (i) => i.after,
  before: (i) => i.before,
  what: 'systems',
).map((i) => i.name).toList();

void main() {
  test('unconstrained items keep registration order', () {
    expect(_order(<_Item>[_item('c'), _item('a'), _item('b')]), <String>[
      'c',
      'a',
      'b',
    ]);
  });

  test('before and after move only what they name', () {
    // Mutation: ignore `before`. "sweep" stays after "integrate".
    expect(
      _order(<_Item>[
        _item('integrate'),
        _item('score'),
        _item('sweep', before: <String>['integrate']),
        _item('sound', after: <String>['score']),
      ]),
      <String>['sweep', 'integrate', 'score', 'sound'],
    );
  });

  test('an unknown name goes to onUnknown and is otherwise ignored', () {
    final missing = <String>[];
    final ordered = orderByConstraints<_Item>(
      <_Item>[
        _item('a', before: <String>['fire']),
      ],
      nameOf: (i) => i.name,
      before: (i) => i.before,
      what: 'systems',
      onUnknown: (item, name) => missing.add('${item.name}:$name'),
    );
    expect(ordered.single.name, 'a');
    expect(missing, <String>['a:fire']);
  });

  test('a cycle names exactly its members, in the order they chain', () {
    // Mutation: name every unplaced item. "tail", which waits on the cycle
    // without being in it, would be blamed too.
    final error = () {
      try {
        _order(<_Item>[
          _item('x', after: <String>['z']),
          _item('y', after: <String>['x']),
          _item('z', after: <String>['y']),
          _item('tail', after: <String>['z']),
        ]);
      } on ConstraintCycleException catch (error) {
        return error;
      }
      return null;
    }();
    expect(error, isNotNull);
    expect(error!.cycle.toSet(), <String>{'x', 'y', 'z'});
    // Each member runs after the one before it: x→y→z→x.
    final at = error.cycle.indexOf('x');
    expect(error.cycle[(at + 1) % 3], 'y');
    expect('$error', contains('systems'));
  });

  test('two items of one name are refused', () {
    expect(() => _order(<_Item>[_item('a'), _item('a')]), throwsArgumentError);
  });
}
