// Where there is no `dart:ffi` (the web): no native kernels.
import 'dart:typed_data';

import '../pbf_kernels.dart';

/// Always false here.
const bool nativePbfAvailable = false;

/// None here.
PbfKernels? nativePbfKernels(PbfConstants k) => null;

/// No native code here: -1.
int nativeSurfaceLanczos(
  int n,
  Int32List start,
  Int32List adjacent,
  double cell2,
  int band,
  int steps,
  Float64List q0,
  Float64List basis,
  Float64List alpha,
  Float64List beta,
) => -1;

/// No native code here: null.
({double apexCurvature, List<double> r, List<double> z})? nativeMeniscus(
  double radius,
  double bond,
  double contactAngle,
  int samples,
) => null;
