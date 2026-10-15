/// The input tapes an older build wrote, opened by this one.
///
///     dart test test/input_tape_fixture_test.dart
///
/// `test/fixtures/v<N>/input.tape.json` is minted once at each version and
/// never re-minted: when this goes red, the tape on somebody's disk has
/// stopped replaying.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

InputTape _tape(int version) => InputTape.fromJson(
  jsonDecode(File('test/fixtures/v$version/input.tape.json').readAsStringSync())
      as Map<String, Object?>,
);

void main() {
  test('the version 1 tape reads, every frame in its place', () {
    final tape = _tape(1);
    // Mutation: drop the move or look axes from `InputFrame.fromJson`, and
    // the second frame reads as standing still.
    expect(tape.seed, 3);
    expect(tape.frames, hasLength(4));
    expect(tape.frames[1].toJson(), containsPair('sx', 0.5));
    expect(tape.frames[1].toJson(), containsPair('lx', 4.0));
  });

  test('the version 2 tape keeps its axes and its dual axes', () {
    final tape = _tape(2);
    // Mutation: read version 2 as 1, and the crane's neck stays still.
    expect(tape.seed, 3);
    expect(tape.frames, hasLength(4));
    final second = tape.frames[1].toJson();
    expect(second['axes'], <String, Object?>{'lift': 1.0});
    expect(second['dual'], <String, Object?>{
      'aim': <double>[0.5, -0.25],
    });
  });
}
