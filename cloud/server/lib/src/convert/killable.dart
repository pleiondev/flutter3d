/// One piece of work in an isolate of its own, killed when its time is up.
///
/// **Killed, not abandoned.** `Isolate.run` with a timeout stops the wait and
/// leaves the work running, which on a server is a core lost for as long as a
/// hostile file can keep it busy. Converting an upload (`converter.dart`) and
/// writing a stored model in another format (`exporter.dart`) both go through
/// here, so both stop at their deadline the same way.
library;

import 'dart:async';
import 'dart:isolate';

/// How a run in its own isolate ended.
sealed class IsolateAnswer {
  const IsolateAnswer();
}

/// The isolate sent [message] back.
final class Answered extends IsolateAnswer {
  const Answered(this.message);

  final Object? message;
}

/// The deadline passed; the isolate was killed.
final class TimedOut extends IsolateAnswer {
  const TimedOut();
}

/// The isolate ended without answering: an uncaught error, or an exit with
/// nothing sent.
final class Stopped extends IsolateAnswer {
  const Stopped();
}

/// Spawns [entry] with the message [job] builds around the port it should
/// answer on, and waits at most [deadline] for that answer.
///
/// [entry] must be a top-level or static function, and should end with
/// `Isolate.exit(reply, answer)` so the answer is handed over rather than
/// copied. The answer must not be null: null is how the exit notice arrives.
Future<IsolateAnswer> runKillable<J>(
  void Function(J job) entry,
  J Function(SendPort reply) job, {
  required Duration deadline,
  String? debugName,
}) async {
  final result = Completer<Object?>();
  final exited = Completer<void>();
  // One port for the answer and for the exit notice, so they arrive in the
  // order they were sent: an isolate that dies before answering is seen as
  // the null `onExit` sends, never as a wait that runs to the deadline.
  final port = RawReceivePort((Object? message) {
    if (message == null) {
      if (!exited.isCompleted) exited.complete();
      if (!result.isCompleted) result.complete(null);
    } else if (!result.isCompleted) {
      result.complete(message);
    }
  });
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn<J>(
      entry,
      job(port.sendPort),
      onExit: port.sendPort,
      errorsAreFatal: true,
      debugName: debugName,
    );
    final answer = await result.future.timeout(deadline);
    return answer == null ? const Stopped() : Answered(answer);
  } on TimeoutException {
    isolate?.kill(priority: Isolate.immediate);
    await exited.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    return const TimedOut();
  } finally {
    port.close();
  }
}

/// [d] as a person would say it: `2 minutes`, `30 seconds`.
String describeDuration(Duration d) => d.inSeconds % 60 == 0
    ? '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'}'
    : '${d.inSeconds} seconds';
