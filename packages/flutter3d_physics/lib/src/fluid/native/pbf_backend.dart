// The native kernels where `dart:ffi` is, none where it is not.
export 'pbf_none.dart' if (dart.library.ffi) 'pbf_native.dart';
