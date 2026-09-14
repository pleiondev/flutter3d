import 'package:flutter3d_sim/flutter3d_sim.dart';

/// `tpl-04`'s own twin: `spindle-temp`'s reading, with no broker behind
/// it — a smooth, deterministic signal a level can show before a real
/// factory is wired up, the same reason [SamplerDataSource]'s own doc
/// comment gives.
///
/// Named and tested on its own — `ls-i-00`'s own acceptance, "the
/// temperature on the panel follows the source," is a claim about this
/// exact formula, not about `resolveBindings`' own generic machinery
/// (`edu-05`), which a synthetic sampler already proves separately.
///
/// [Portable.sin], not `dart:math`'s: this reading can be recorded into a
/// run and compared across machines the same way `edu-04`'s own pendulum
/// is, and `dart:math`'s trig functions go through the platform's own
/// `libm`, not guaranteed to agree between them — the same rule
/// `flutter3d_lab`'s own pendulum had to fix this for.
double spindleTempAt(int step) => 60.0 + 15.0 * Portable.sin(step * 0.05);

/// [DataSourceRegistry] naming the one source `twin.json` reads —
/// `flutter3d_template_app`'s own `_GameScreenState._dataSources` and this
/// package's own tests build the identical registry, rather than each
/// hand-rolling one.
DataSourceRegistry twinDataSources() =>
    DataSourceRegistry(<String, EduDataSource>{
      'spindle-temp': SamplerDataSource(
        (step) => <String, Object?>{'value': spindleTempAt(step)},
      ),
    });
