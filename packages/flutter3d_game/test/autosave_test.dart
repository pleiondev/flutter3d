/// When a run is written without the player asking: on the way into a pause,
/// at a checkpoint, and when the application goes to the background.
///
///     flutter test test/autosave_test.dart
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts writes, which is what these tests are about.
final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};
  int writes = 0;

  @override
  String? read(String name) => documents[name];

  @override
  bool write(String name, String contents) {
    writes++;
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

final class _Level {
  int coins = 0;
  int steps = 0;
}

final class _Game extends RunSession<_Level> {
  _Game({required super.saves}) : super(firstLevel: 'one');

  @override
  Future<_Level> open(String asset) async => _Level();

  @override
  RunOutcome outcomeOf(_Level level) => RunOutcome.playing;

  @override
  String? nextOf(_Level level) => null;

  @override
  Snapshot snapshotOf(_Level level) =>
      Snapshot(<String, Object?>{'coins': level.coins});

  @override
  void restoreInto(_Level level, Snapshot snapshot) =>
      level.coins = snapshot.data.integer('coins');

  @override
  int stepOf(_Level level) => level.steps;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Storage storage;
  late SaveFile saves;
  late _Game game;
  late Autosave autosave;

  setUp(() async {
    storage = _Storage();
    saves = SaveFile(appName: 't', storage: storage);
    game = _Game(saves: saves);
    await game.begin();
    autosave = Autosave(game);
  });

  test('a pause writes on the way in, and not on every paused frame', () {
    // Mutation: write whenever `paused` is true. Every frame behind the menu
    // is then a file write — sixty a second for as long as the menu is open.
    expect(autosave.paused(false), isFalse);
    expect(autosave.paused(true), isTrue);
    expect(storage.writes, 1);

    game.level!.coins = 3;
    autosave.paused(true);
    autosave.paused(true);
    expect(storage.writes, 1);

    autosave.paused(false);
    expect(storage.writes, 1, reason: 'leaving a pause writes nothing');
    expect(autosave.paused(true), isTrue);
    expect(storage.writes, 2);
    expect(saves.read()!.run.data['coins'], 3);
  });

  test('the same run is not written twice', () {
    // Mutation: drop the digest check in `SaveFile.writeRecord`. A player who
    // opens and closes the menu rewrites the same save each time, which on a
    // phone is flash wear for nothing.
    autosave.checkpoint();
    autosave.paused(true);
    autosave.paused(false);
    autosave.paused(true);

    expect(storage.writes, 1);
  });

  test('the step is written beside the run', () {
    // Mutation: drop `step: stepOf(...)` from `RunSession.save`. Every save is
    // then step 0, and two different runs are always the player's call.
    game.level!.steps = 4200;
    autosave.checkpoint();

    expect(saves.readRecord()!.step, 4200);
  });

  test('going to the background writes the run', () {
    // On a phone there is no pause screen between the home button and the
    // system ending the process. Mutation: write only on `paused`, which iOS
    // does not always deliver before it kills a backgrounded game.
    game.level!.coins = 7;
    autosave.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(saves.read()!.run.data['coins'], 7);

    game.level!.coins = 8;
    autosave.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(saves.read()!.run.data['coins'], 7, reason: 'coming back is not');
  });

  test('watching the lifecycle hears the binding, and stops', () {
    // Mutation: forget `removeObserver` in `dispose`. A game torn down keeps
    // writing a run that is no longer there every time the window loses focus.
    autosave.watchLifecycle();
    game.level!.coins = 5;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    expect(saves.read()!.run.data['coins'], 5);

    autosave.dispose();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    game.level!.coins = 6;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    expect(saves.read()!.run.data['coins'], 5);
  });
}
