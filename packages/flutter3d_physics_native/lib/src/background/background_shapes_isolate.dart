/// The native [BackgroundShapeSolver]: a long-lived isolate the shapes not
/// met before are sent to, while the vessels carry on without them.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter3d_physics/flutter3d_physics.dart';

/// A liquid's menisci and its surfaces' modes worked out on another
/// isolate, so a cross-section or a meniscus not met before does not stop
/// a frame.
///
/// **The same numbers, later.** An answer is the same solve the frame
/// would have made (`solveSurfaceModes`, `solveMeniscus`), checked to the
/// bit by this package's tests; only when it arrives differs. Until it
/// does, a surface rings on the grid it had and a vessel goes without its
/// meniscus. Answers are kept in `LiquidShapeCache.shared`, where every
/// solver finds them.
///
/// **Not for a world that must replay to the bit**: when an answer arrives
/// is the machine's, so `FluidWorld` refuses it under a bit-exact profile.
/// In the browser, which has no isolate here, it answers at once.
final class BackgroundShapeSolver extends LiquidShapeSolver {
  /// A solver whose isolate starts at once and runs until [dispose].
  BackgroundShapeSolver() {
    _replies.listen(_receive);
    unawaited(
      Isolate.spawn<SendPort>(_serve, _replies.sendPort).then((isolate) {
        if (_disposed) {
          isolate.kill();
        } else {
          _isolate = isolate;
        }
      }),
    );
  }

  /// Whether answers are worked out off the frame here: natively, yes.
  static bool get isAvailable => true;

  final ReceivePort _replies = ReceivePort();
  final Completer<SendPort> _requests = Completer<SendPort>();
  Isolate? _isolate;
  bool _disposed = false;

  /// What has been sent and has not come back, by request.
  final Set<Object> _pending = <Object>{};

  @override
  bool get answersAtOnce => false;

  @override
  SurfaceModes? surfaceModes(SurfaceModesRequest request) =>
      LiquidShapeCache.shared.surfaceModes(request) ?? _ask(request);

  @override
  TubeMeniscus? meniscus(MeniscusRequest request) =>
      LiquidShapeCache.shared.meniscus(request) ?? _ask(request);

  /// How many answers are on their way: for a test that waits for them.
  int get pending => _pending.length;

  /// Completes once nothing sent is still on its way.
  Future<void> settled() async {
    while (_pending.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Null _ask(Object request) {
    if (_disposed || !_pending.add(request)) return null;
    unawaited(_requests.future.then((port) => port.send(request)));
    return null;
  }

  void _receive(Object? message) {
    switch (message) {
      case final SendPort port:
        _requests.complete(port);
      case (final SurfaceModesRequest request, final SurfaceModes modes):
        LiquidShapeCache.shared.keepSurfaceModes(request, modes);
        _pending.remove(request);
      case (final MeniscusRequest request, final TubeMeniscus meniscus):
        LiquidShapeCache.shared.keepMeniscus(request, meniscus);
        _pending.remove(request);
    }
  }

  /// Stops the isolate; whatever is still on its way is not waited for.
  void dispose() {
    _disposed = true;
    _isolate?.kill();
    _replies.close();
    _pending.clear();
  }

  static void _serve(SendPort replies) {
    final requests = ReceivePort();
    replies.send(requests.sendPort);
    requests.listen((Object? message) {
      switch (message) {
        case final SurfaceModesRequest request:
          replies.send((request, solveSurfaceModes(request)));
        case final MeniscusRequest request:
          replies.send((request, solveMeniscus(request)));
      }
    });
  }
}
