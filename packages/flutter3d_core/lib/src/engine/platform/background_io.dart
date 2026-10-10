import 'dart:async';
import 'dart:isolate';

/// [work] on an isolate of its own, as `Isolate.run`.
Future<R> runInBackground<R>(FutureOr<R> Function() work) => Isolate.run(work);
