// The cross-sections' modes and the menisci worked out on another isolate,
// for a world that need not step the same to the bit on every run.
import 'dart:isolate';
import 'dart:typed_data';

import '../capillary.dart';
import '../fluid_medium.dart';
import '../free_surface.dart';

/// A long-lived isolate that works out what a [FreeSurface] or a vessel's
/// meniscus would otherwise stop a frame for: one for the whole program,
/// started the first time it is asked for.
///
/// **What comes back is the same as what would have been worked out here**:
/// the same functions, on the same numbers. Only when it comes differs, so
/// a world stepped with it ([FluidWorld.background]) is not the same run to
/// the bit twice; one stepped without it is.
final class FluidBackground implements ModeSolver {
  FluidBackground._() {
    // Not what keeps a program running: a test or a tool that is done exits
    // with this still open.
    _port.keepIsolateAlive = false;
    _port.handler = _receive;
    Isolate.spawn(_work, _port.sendPort, debugName: 'flutter3d fluid');
  }

  static FluidBackground? _instance;

  /// The one there is, started on first use.
  static FluidBackground get instance => _instance ??= FluidBackground._();

  final RawReceivePort _port = RawReceivePort();
  SendPort? _send;
  final List<List<Object?>> _waiting = [];
  final Map<int, void Function(List<Object?>)> _replies = {};
  int _next = 0;

  /// How many requests have not come back yet.
  int get outstanding => _replies.length;

  void _receive(Object? message) {
    if (message is SendPort) {
      _send = message;
      _waiting.forEach(message.send);
      _waiting.clear();
      return;
    }
    final reply = message! as List<Object?>;
    _replies.remove(reply[0]! as int)?.call(reply);
  }

  void _post(List<Object?> request, void Function(List<Object?>) reply) {
    _replies[request[1]! as int] = reply;
    final send = _send;
    if (send == null) {
      _waiting.add(request);
    } else {
      send.send(request);
    }
  }

  @override
  void solve(
    int n,
    List<List<int>> neighbours,
    double cell2,
    int count,
    void Function((List<Float64List>, Float64List) modes) done, {
    bool native = false,
  }) {
    _post(['modes', _next++, n, neighbours, cell2, count, native], (reply) {
      done((
        [for (final m in reply[1]! as List<Object?>) m! as Float64List],
        reply[2]! as Float64List,
      ));
    });
  }

  /// Works out the meniscus of [medium] in a tube of [radius] under [g] and
  /// calls [done] with it, later, on this isolate.
  void meniscus(
    FluidMedium medium,
    double radius,
    double g,
    void Function(TubeMeniscus meniscus) done, {
    bool native = false,
  }) {
    _post(
      [
        'meniscus',
        _next++,
        medium.name,
        medium.density,
        medium.viscosity,
        medium.surfaceTension,
        medium.contactAngle,
        radius,
        g,
        native,
      ],
      (reply) {
        done(
          TubeMeniscus.solved(
            medium: medium,
            radius: radius,
            g: g,
            solution: (
              apexCurvature: reply[1]! as double,
              r: (reply[2]! as List<Object?>).cast<double>(),
              z: (reply[3]! as List<Object?>).cast<double>(),
            ),
          ),
        );
      },
    );
  }
}

/// The other isolate: answers each request with what it asks for.
void _work(SendPort back) {
  final port = ReceivePort();
  back.send(port.sendPort);
  port.listen((message) {
    final request = message as List<Object?>;
    final id = request[1]! as int;
    switch (request[0]) {
      case 'modes':
        final (modes, k2) = FreeSurface.solveModes(
          request[2]! as int,
          (request[3]! as List<Object?>).cast<List<int>>(),
          request[4]! as double,
          request[5]! as int,
          native: request[6]! as bool,
        );
        back.send([id, modes, k2]);
      case 'meniscus':
        final medium = FluidMedium(
          name: request[2]! as String,
          density: request[3]! as double,
          viscosity: request[4]! as double,
          surfaceTension: request[5]! as double,
          contactAngle: request[6]! as double,
        );
        final m = TubeMeniscus(
          medium: medium,
          radius: request[7]! as double,
          g: request[8]! as double,
          native: request[9]! as bool,
        ).solution;
        back.send([id, m.apexCurvature, m.r, m.z]);
    }
  });
}

/// The background where there are isolates.
FluidBackground? get fluidBackground => FluidBackground.instance;
