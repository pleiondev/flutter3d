import 'dart:async';

/// [work] in place: the browser has no isolates.
Future<R> runInBackground<R>(FutureOr<R> Function() work) async => work();
