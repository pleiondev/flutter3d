// dart format off
// What the migration writes, compared byte for byte: not reformatted.
import 'package:flutter3d_kinds/flutter3d_kinds.dart';
import 'package:flutter3d_kinds/flutter3d_kinds.dart' as kinds show Shade;
import 'package:flutter3d_kinds/roster.dart';

part 'piece.dart';

const Object shade = Shade();

final List<Object> both = <Object>[const Shade(), KindShade()];

Table rows() => Board.table()..rows.add(2);

final LinearColor sky = srgbColor(0.2, 0.4, 0.8);
final LinearColor dusk = srgbColor(0.9, 0.5, 0.3, 0.5);

bool jumped(List<Object> events) => events.has<int>();

bool touching(Mode mode) => Mode.touch || mode.touch;

int later() {
  final total = 1 +
      oldHelperGone();
  return total + Roster.size;
}

final class MyShelf implements Shelf {
  final int held = 2;

  @override
  int count() => held;
}

/// A dial, documented over
/// two lines.
Dial dial() => Dial(
      level: 2,
      label: 'gain',
      onTurn: (int from, int to) {},
    );

Match pick(List<Match> all) => all.first;

final Object prefixed = kinds.KindShade();

int sum(KindLedger ledger) => ledger.total;

int tallied(KindLedger ledger) => ledger.count;

const Object wrench = Wrench();

Table piled(Table table) => Board.pile(table);

Pile kept(Pile pile) => Board.pile(pile);

Future<int> loaded(Store store) async {
  final n = store.load();
  final saved = store.save();
  print(saved);
  final again = await store.save();
  print(again);
  return n + store.load().bitLength;
}

int forget(Store store) {
  store.load();
  final held = store.load();
  print(held);
  return 0;
}

void refresh(Store store) {
  store.load();
}

void test(String name, Object? Function() body) => body();

void checks(Store store) {
  test('loads', () {
    print(store.load());
    print(store.load());
  });
}

int counted(Object o) => switch (o) {
  KindLedger(:final count) => count,
  _ => 0,
};

Credit credit() => (title: 't', licence: 'MIT');

String licenseOf(Credit credit) => credit.licence;

final Object prefixedOld = kinds.Shade();
