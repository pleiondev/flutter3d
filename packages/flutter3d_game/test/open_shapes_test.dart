/// A binding shape and a timeline command the engine does not know.
///
///     flutter test test/open_shapes_test.dart
///
/// Both sets grow in a minor release (a new device shape, a new command in
/// the history), so neither is sealed: a shape from outside the package
/// compiles, sits in a map beside the five, and reads as nothing; a command
/// from outside is shown by its text. This file does not compile while
/// either type is sealed.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const AxisAction _tilt = AxisAction('test.tilt');

/// A shape no build of the engine has: a phone's tilt as one axis.
final class _TiltBinding extends ActionBinding {
  const _TiltBinding(this.source);

  final InputSource source;

  @override
  AxisAction get action => _tilt;

  @override
  List<InputSource> get sources => <InputSource>[source];

  @override
  InputSource sourceAt(CompositePart? part) => source;

  @override
  _TiltBinding withSource(InputSource source, CompositePart? part) =>
      _TiltBinding(source);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'test.tilt',
    'action': _tilt.name,
    'source': source.id,
  };
}

/// A command a later minor might add to the history.
final class _TimelineMarked extends TimelineCommand {
  const _TimelineMarked();

  @override
  String toString() => 'marked';
}

void main() {
  test('a shape of its own sits in a map beside the five', () {
    const tilt = _TiltBinding(InputSource('test.gyro'));
    final map = ActionMap(actions: ActionSet.common)..bind(tilt);

    expect(map.axisBindings, contains(tilt));
    expect(map.bindingsFor(_tilt), <ActionBinding>[tilt]);
    expect(map.routes(const InputSource('test.gyro')), isTrue);

    map.unbind(tilt);
    expect(map.axisBindings, isNot(contains(tilt)));
  });

  test('a shape the devices do not know reads as nothing', () {
    const gyro = InputSource('test.gyro');
    final state = InputState();
    final input = ActionInput(
      state: state,
      map: ActionMap(actions: ActionSet.common)..bind(const _TiltBinding(gyro)),
    );

    input.sourceValue(gyro, 0.8);

    expect(state.axis(_tilt), 0.0);
  });

  test('a command of its own is a TimelineCommand', () {
    const TimelineCommand marked = _TimelineMarked();
    expect('$marked', 'marked');
  });
}
