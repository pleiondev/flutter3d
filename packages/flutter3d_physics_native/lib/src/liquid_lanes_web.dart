/// The liquid's native CPU executor in the browser: there is none.
library;

import 'dart:typed_data';

import 'liquid_lanes.dart';

/// Null: the browser has no native executor, and the liquid runs its
/// kernels.
LiquidPairLoops? openLiquidLanes(Float64List constants) => null;

/// Null: there is no native executor to ask.
int? liquidLanesWidth({int? lanes}) => null;
