# How much of falling water goes up as mist

`LiquidView` raises a puff of mist where falling water comes down on
water, holding a share of the water that landed as droplets that hang. No
open source measures that share at a plunge pool: flood-spray studies
measure rain in mm/h at points, and waterfall studies count ions (gap G11
of the research notes). This derives it from what is measured, as a law of
the speed the water lands at, so a game no longer sets it by hand.

## What is measured

- **Water falling freely onto a floor.** The airborne release fraction of
  125 to 1000 mL of water (uranine solution) poured from 1 and 3 m: 4 ×
  10⁻⁶ to 2 × 10⁻⁴, median 4 × 10⁻⁵ (DOE-HDBK-3010-94, vol. 1, §3.2.3.1
  and table 3-6, after Sutter, Johnston and Mishima, 1981). The handbook
  fits all its spills by the Archimedes number of the fall,

  <math display="block"><mrow><mtext>ARF</mtext><mo>=</mo><mn>8.9</mn><mo>×</mo><msup><mn>10</mn><mrow><mo>−</mo><mn>10</mn></mrow></msup><msup><mtext>Ar</mtext><mn>0.55</mn></msup><mo>,</mo><mspace width="1em"/><mtext>Ar</mtext><mo>=</mo><mfrac><mrow><msubsup><mi>ρ</mi><mi>a</mi><mn>2</mn></msubsup><mi>g</mi><msup><mi>H</mi><mn>3</mn></msup></mrow><msup><mi>μ</mi><mn>2</mn></msup></mfrac></mrow></math>

  ρ<sub>a</sub> the air's density, *H* the height of the fall and μ the
  liquid's viscosity (eq. 3-13), and says that for watery solutions it
  falls short of the data, which it bounds by three times it.
- The drops that spill throws into the air: lognormal, 27.1 µm by mass,
  geometric spread 3.0 (table 3-7, after Ballinger and colleagues, 1988).
- **A nappe plunging into a pool.** Sun and colleagues measured the rain
  around a weir's sheet falling 5.5 m into a pool (*Front. Environ. Sci.*
  11, 1096960, 2023, §3.2): integrated over the field they mapped, what
  lands at least half a metre from where the sheet strikes, at 9.9 m/s, is
  about 4 × 10⁻⁴ of the flow, within a factor of two or three (the
  research notes' integration of their table of profiles).
- **A jet into a pool.** What one collector plate caught below a jet at
  10.7 to 11.8 m/s was up to 3 × 10⁻⁴ of the flow (Liu and colleagues,
  *Water* 12, 397, 2020, eq. 6 and §3.2): a floor on the whole.
- **The most.** The flood-spray model of Lian and colleagues turns an
  outer strip of a jet wholly to spray, κ/2 of its thickness, κ calibrated
  to prototypes at 0.005 to 0.03 (*IJERPH* 16, 316, 2019, §2.2.1).

## The derivation

A free fall lands at *v* from *H* = *v*²/2*g*, so the handbook's fit, as a
law of the landing speed, is

<math display="block"><mrow><mi>s</mi><mo>(</mo><mi>v</mi><mo>)</mo><mo>=</mo><mn>3</mn><mo>×</mo><mn>8.9</mn><mo>×</mo><msup><mn>10</mn><mrow><mo>−</mo><mn>10</mn></mrow></msup><msup><mrow><mo>(</mo><mfrac><mrow><msubsup><mi>ρ</mi><mi>a</mi><mn>2</mn></msubsup><mi>g</mi></mrow><msup><mi>μ</mi><mn>2</mn></msup></mfrac><msup><mrow><mo>(</mo><mfrac><msup><mi>v</mi><mn>2</mn></msup><mrow><mn>2</mn><mi>g</mi></mrow></mfrac><mo>)</mo></mrow><mn>3</mn></msup><mo>)</mo></mrow><mn>0.55</mn></msup><mo>∝</mo><msup><mi>v</mi><mn>3.3</mn></msup></mrow></math>

with ρ<sub>a</sub> = 1.2 kg/m³ and water's μ = 1.0 mPa s, as the handbook
evaluates it (Ar is the same number in SI as in its cgs), and the factor
of three it gives watery spills. Where it can be checked against water
plunging into water:

| *v* | *s* | Measured |
|---|---|---|
| 9.9 m/s | 3.2 × 10⁻⁴ | Sun: 4 × 10⁻⁴, within ×2–3 |
| 11.3 m/s | 5.0 × 10⁻⁴ | Liu: at least 3 × 10⁻⁴ |
| 7.7 m/s (3 m) | 1.4 × 10⁻⁴ | DOE: up to 2 × 10⁻⁴ at 3 m |

It is capped at **0.015**, the most of a jet Lian's κ turns to spray. That
cap is reached at 32 m/s, a fall of about 50 m.

The spill's droplets stop light as their Sauter mean diameter, the one
whose surface to volume is the cloud's. For a lognormal of mass median
*d*<sub>m</sub> and spread σ<sub>g</sub>,

<math display="block"><mrow><msub><mi>d</mi><mn>32</mn></msub><mo>=</mo><msub><mi>d</mi><mi>m</mi></msub><msup><mi>e</mi><mrow><mo>−</mo><mfrac><mn>1</mn><mn>2</mn></mfrac><msup><mi>ln</mi><mn>2</mn></msup><msub><mi>σ</mi><mi>g</mi></msub></mrow></msup><mo>=</mo><mn>27.1</mn><mo>×</mo><msup><mi>e</mi><mrow><mo>−</mo><mn>0.603</mn></mrow></msup><mo>=</mo><mn>14.8</mn><mspace width="0.2em"/><mtext>µm</mtext></mrow></math>

`MistSettings.droplet`'s default.

## What it rests on, and what is left out

- The spills were a litre at most, onto a floor, from 3 m at most: the law
  is theirs carried to taller falls and onto water, checked against the
  two plunge measurements above.
- Sun's and Liu's numbers count rain, drops from a quarter of a millimetre
  to centimetres, landing clear of the plunge; the mist here hangs as
  15 µm droplets. The two agree in amount at 10 m/s; whether the hanging
  part is all of the rain or less of it, neither says.
- A deeper pool rains less (Sun, §3.2.2), and so does a narrower sheet per
  metre of it; the law sees only the speed.
