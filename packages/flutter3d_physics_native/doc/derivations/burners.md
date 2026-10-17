# The burners' flames: a candle and Gross's cribs

A `NativeBurner` burns a rate of a fuel on a body, giving off rate × Δ*H*<sub>c</sub>
with the fuel's flame. The presets take measured rates; what the flame of
paraffin hands a surface in it was not measured as the core asks for it,
and is derived here.

## A candle

Hamins, Bundy and Dillon measured a paraffin taper 21 mm across (*J. Fire
Protection Eng.* 15, 2005): 0.105 g/min, 1.75 mg/s, burnt at 43.8 MJ/kg
(cone) for 77 ± 9 W; a flame 42 ± 1 mm tall; 0.17 ± 0.01 of its heat
radiated; 145 kW/m² on a 3 mm gauge at the flame's tip; the hottest gas of
such a flame 1673 K (their table 1, after Gaydon and Wolfhard). PARAFFIN
carries these, and `NativeBurner.candle` burns 1.75 mg/s of it.

The core's flame hands a surface standing in it

<math display="block"><mrow><msup><mi>q</mi><mo>″</mo></msup><mo>=</mo><msub><mi>h</mi><mi>f</mi></msub><mo>(</mo><msub><mi>T</mi><mi>f</mi></msub><mo>−</mo><msub><mi>T</mi><mi>s</mi></msub><mo>)</mo><mo>+</mo><mi>ε</mi><mo>(</mo><mn>1</mn><mo>−</mo><msup><mi>e</mi><mrow><mo>−</mo><mi>κ</mi><mi>d</mi></mrow></msup><mo>)</mo><mi>σ</mi><msubsup><mi>T</mi><mi>f</mi><mn>4</mn></msubsup></mrow></math>

with *d* the width of what burns.

**Its absorption, κ.** A flame whose radiant share χ<sub>r</sub> of *Q*
leaves its side, π*D*·*L*, at σ*T*<sub>f</sub>⁴ has the emissivity

<math display="block"><mrow><msub><mi>ε</mi><mi>f</mi></msub><mo>=</mo><mfrac><mrow><msub><mi>χ</mi><mi>r</mi></msub><mi>Q</mi></mrow><mrow><mi>σ</mi><msubsup><mi>T</mi><mi>f</mi><mn>4</mn></msubsup><mspace width="0.2em"/><mi>π</mi><mi>D</mi><mi>L</mi></mrow></mfrac><mo>=</mo><mfrac><mrow><mn>0.17</mn><mo>×</mo><mn>77</mn></mrow><mrow><mn>444</mn><mspace width="0.2em"/><mtext>kW/m²</mtext><mo>×</mo><mi>π</mi><mo>×</mo><mn>0.021</mn><mo>×</mo><mn>0.042</mn></mrow></mfrac><mo>=</mo><mn>0.0106</mn></mrow></math>

taking the flame as wide as the candle, as the core takes a burner's flame
as wide as its body, and 1 − e<sup>−κ*D*</sup> = ε<sub>f</sub> gives
**κ = 0.51 per metre**.

**Its convection, *h*<sub>f</sub>.** The gauge at the tip, at about the
room's temperature, took 145 kW/m²; of that the flame's radiation at that
emissivity is under 5 kW/m², so nearly all of it is convection:

<math display="block"><mrow><msub><mi>h</mi><mi>f</mi></msub><mo>≈</mo><mfrac><mrow><mn>145</mn><mspace width="0.2em"/><mtext>kW/m²</mtext></mrow><mrow><mn>1673</mn><mo>−</mo><mn>293</mn><mspace width="0.2em"/><mtext>K</mtext></mrow></mfrac><mo>=</mo><mn>105</mn><mspace width="0.2em"/><mtext>W/(m² K)</mtext></mrow></math>

four times a turbulent wall flame's 25 (Quintiere, *Fundamentals of Fire
Phenomena*, §8.6), as a thin laminar flame's boundary layer is thinner.

**Where it catches.** Paraffin's fire point is not published in an open
source. It flashes at 199 °C, 472 K, and ignites by itself at 245 °C,
518 K (NOAA CAMEO Chemicals, "Waxes: paraffin", after the USCG; NIOSH
Pocket Guide, "Paraffin wax fume"). PARAFFIN takes the flash point as where
it catches: the fire point lies above it and below the autoignition point,
and a burner's fuel is never lit by it. A body of PARAFFIN holds no fuel of
its own, as wax melts and runs, which the core does not follow.

## Gross's cross piles

Gross burnt cribs of Douglas-fir sticks, *b* × 10*b* in section and ten
layers high, oven-dry density 0.428 g/cm³ at 9.2 % moisture, and measured
the most mass each lost a second (*J. Res. NBS* 66C, 1962, table 1). He
gives no heat release; the presets burn their rates as PINE, 13.9 MJ/kg
(Tran and White, *Fire and Materials* 16, 1992, table 4), the softwood the
core has:

| Preset | Pile *b*-*n*-*N* | Mass | Most lost | Flame | Heat |
|---|---|---|---|---|---|
| `kindling` | 0.32-3-10 | 4.55 g | 0.128 g/s | 0.44 m | 1.8 kW |
| `brazier` | 1.27-3-10 | 286 g | 1.24 g/s | 0.77 m | 17 kW |
| `campfire` | 2.54-5-10 | 4150 g | 5.58 g/s | — | 78 kW |
| `bonfire` | 9.15-7-10 | 262 kg | 57.5 g/s | 4.60 m | 0.80 MW |

The rate is a crib's peak; it burns its mass over longer than mass over
rate, its first catching and its last embers slower.

## Charcoal

`NativeBurner.charcoal` burns CHARCOAL's 1.02 g/(m² s) over the surface of
a brazier's coals: `charcoal_glow.md`.
