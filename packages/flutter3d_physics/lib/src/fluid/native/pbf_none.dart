// Where there is no `dart:ffi` (the web): no native kernels.
import '../pbf_kernels.dart';

/// Always false here.
const bool nativePbfAvailable = false;

/// None here.
PbfKernels? nativePbfKernels(PbfConstants k) => null;
