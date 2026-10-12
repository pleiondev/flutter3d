import 'package:flutter3d_kinds/flutter3d_kinds.dart';
import 'package:flutter3d_kinds/flutter3d_kinds.dart' as kinds show KindShade;
// TODO(flutter3d-1.0): The roster was one game's; copy it into your own code. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-roster
import 'package:flutter3d_kinds/roster.dart';
import 'package:flutter3d_kinds/tools.dart';

part 'piece.dart';

const Object shade = KindShade();

final List<Object> both = <Object>[const KindShade(), KindShade()];

Table rows() => Board.fill(Table())..rows.add(2);

final LinearColor sky = LinearColor.fromSrgb(0.2, 0.4, 0.8);
final LinearColor dusk = LinearColor.fromSrgb(0.9, 0.5, 0.3, 0.5);

bool jumped(List<Object> events) => events.whereType<int>().isNotEmpty;

bool touching(Mode mode) => Mode.ofPlatform().touch || mode.touch;

int later() {
  final total = 1 +
      // TODO(flutter3d-1.0): `oldHelperGone` is gone; count by hand. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-oldHelperGone
      oldHelperGone();
  // TODO(flutter3d-1.0): The roster was one game's; copy it into your own code. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-roster
  return total + Roster.size;
}

// TODO(flutter3d-1.0): Only code that implements `Shelf` has anything to do: `count` answers a `Future<int>`. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Shelf
final class MyShelf implements Shelf {
  final int held = 2;

  // TODO(flutter3d-1.0): Only code that implements `Shelf` has anything to do: `count` answers a `Future<int>`. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Shelf
  @override
  int count() => held;
}

// TODO(flutter3d-1.0): `label` is gone: a dial shows its level alone. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Dial-constructor
/// A dial, documented over
/// two lines.
Dial dial() => Dial(
      level: 2,
      // TODO(flutter3d-1.0): `label` is gone: a dial shows its level alone. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Dial-constructor
      label: 'gain',
      // TODO(flutter3d-1.0): `label` is gone: a dial shows its level alone. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Dial-constructor
      onTurn: (int from, int to) {},
    );

KindMatch pick(List<KindMatch> all) => all.first;

final Object prefixed = kinds.KindShade();

int sum(KindLedger ledger) => ledger.sum;

int tallied(KindLedger ledger) => ledger.tally;

const Object wrench = Wrench();

Table piled(Table table) => Board.pile(Pile(table)).table;

Pile kept(Pile pile) => Board.pile(pile);

Future<int> loaded(Store store) async {
  final n = await store.load();
  // TODO(flutter3d-1.0): `load` is asynchronous: await it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Store-load
  final saved = await store.save();
  // TODO(flutter3d-1.0): `load` is asynchronous: await it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Store-load
  print(saved);
  return n + (await store.load()).bitLength;
}

int forget(Store store) {
  // TODO(flutter3d-1.0): `load` is asynchronous: await it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Store-load
  store.load();
  // TODO(flutter3d-1.0): `load` is asynchronous: await it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Store-load
  final held = store.load();
  // TODO(flutter3d-1.0): `load` is asynchronous: await it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Store-load
  print(held);
  return 0;
}

void refresh(Store store) async {
  // TODO(flutter3d-1.0): `load` is asynchronous: await it. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Store-load
  await store.load();
}

void test(String name, Object? Function() body) => body();

void checks(Store store) {
  test('loads', () async {
    print(await store.load());
    print(await store.load());
  });
}

int counted(Object o) => switch (o) {
  KindLedger(tally: final count) => count,
  _ => 0,
};

Credit credit() => (title: 't', license: 'MIT');

String licenseOf(Credit credit) => credit.license;

final Object prefixedOld = kinds.KindShade();
