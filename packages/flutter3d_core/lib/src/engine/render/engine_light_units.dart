/// The renderer's own light scale, and the conversions into it.
///
/// **Not exported.** Every light value the API takes is photometric — lux,
/// candela or nits, `docs/CONTRACTS.md` — and this is the one place they are
/// turned into the number a shader multiplies by. That number is the scale the
/// engine was tuned in before 1.0: one unit of scene luminance is 1843.2 nits,
/// which the reference camera (`PhysicalCamera`, f/4, 1/60 s, ISO 100, at the
/// default exposure of 1.6) draws at 1.6, its white being 1152 nits, and one
/// unit of illuminance is π times that. An application never sees it; the
/// defaults it meets (`LightNode.defaultIntensity`,
/// `RenderMaterial.defaultEmissiveStrength`) are one unit each, so a
/// default-made scene draws as it always did.
library;

/// Nits in one unit of the renderer's scene luminance: `1.6 × 1.2 × 960`.
const double nitsPerEngineUnit = 1843.2;

/// Lux (or, for a point light, candela) in one unit of the renderer's scene
/// illuminance: π × [nitsPerEngineUnit].
const double luxPerEngineUnit = 5790.583578;

/// [lux] of illuminance, or candela of intensity, as the renderer's number.
double luxToEngine(double lux) => lux / luxPerEngineUnit;

/// [nits] of luminance as the renderer's number.
double nitsToEngine(double nits) => nits / nitsPerEngineUnit;
