# The igniters' flames

An `Igniter` holds a flame to a body: a flux over an area, from gas at a
temperature, for a time. The core lights the spot when a thick solid would
have reached its ignition temperature under the flux less what the surface
loses there, *t* = (π/4)·*kρc*·(Δ*T*/*q*''<sub>net</sub>)², and never if
the gas is cooler than it catches at. These are the numbers each preset
takes, and how the ones no source prints were had (gap G9 of the research
notes).

| Preset | Flux | Area | Gas | Time |
|---|---|---|---|---|
| `match` | 19 kW/m² | 3.0 cm² | 1930 K | 20 s |
| `lighter` | 63 kW/m² | 3.5 cm² | 1930 K | 20 s |
| `propaneTorch` | 105.6 kW/m² | 161 cm² | 1366.5 K | 300 s |
| `pilot` | 19 kW/m² | 2.7 cm² | 1116.5 K | 300 s |

## A match

A wooden match laid on a surface: 80 W, a flame 30 mm tall and 14 mm wide,
18 to 20 kW/m² at most on what it touches, burning 20 to 30 s
(Babrauskas and Krasny, *Fire Behavior of Upholstered Furniture*, NBS
Monograph 173, 1985, table 6A), over an area "approximately 10 × 30 mm"
(§4.2.1). The flux is the middle of the range, the time its least.

No open source gives a match flame's temperature. The standard flame that
stands in for a match, BS 5852's source 1, is butane at 45 mL/min burning
as a diffusion flame 35 mm tall for 20 s (Monograph 173, table 3): about
the match's heat, 83 W. A cigarette lighter's flame is that, a butane
diffusion flame of 75 W and 20 mm, and its gas was measured, radiation
corrected, at 1930 K at its hottest (Williamson, MS thesis, University of
Maryland, 2003, table 2). The match takes it.

## A lighter

The same diffusion flame of Williamson's: 63 kW/m² on a plate above it,
falling to half that 10.5 mm off its axis at 4 cm (figure 20), so it heats
π × 0.0105² = 3.5 cm² at more than half its peak. A lighter is held as long
as its user holds it; it takes BS 5852's 20 s.

## A propane torch

The burner the FAA certifies engine parts fire-resistant with: a flame of
2000 °F, 1366.5 K, within a quarter inch of the part, laying at least 9.3
Btu/(ft² s), 105.6 kW/m², over an area of about 5 × 5 inches, 161 cm², for
the 5 minutes "fire resistant" means (FAA AC 20-135, change 1, 2018, §4.d,
§5.d, §6.b and §6.d). Propane torches were among the burners it accepted
(AC 20-135, 1990, §6.c), and the FAA's propane torch for firewall
connectors burns 33,000 to 37,000 Btu/h, 9.7 to 10.8 kW, at the same
2000 °F (DOT/FAA/AR-00/12, §13.3.2 and §13.5.2).

## A pilot flame

The lower pilot of the OSU heat release apparatus burns 120 cm³/min of
methane premixed with air, on through the test's 5 minutes
(DOT/FAA/AR-00/12, §5.3.8.1 and §5.7.8): 8.9 × 10⁻⁵ mol/s at 802.7 kJ/mol,
72 W. No flux or area was measured for it. Monograph 173 (§4.2.1) found the
small ignition sources it measured alike in the flux they lay, 15 to 42
kW/m², and unlike in the area they lay it over, which grows with their
heat. The pilot takes the match's flux and the match's area in proportion
to its heat, 3.0 × 72/80 = 2.7 cm². Its gas is the least the FAA asks of a
premixed burner's flame, 1550 °F, 1116.5 K (DOT/FAA/AR-00/12, chapter 1):
no open measurement of a pilot's.

## How they compare on oak

Dry red oak, *kρc* 0.360 (kW/m² K)² s, catching at 588 K and radiating
5.7 kW/m² there at an emissivity of 0.9: a match reaches it in

<math display="block"><mrow><mi>t</mi><mo>=</mo><mfrac><mi>π</mi><mn>4</mn></mfrac><mo>×</mo><mn>0.360</mn><mo>×</mo><msup><mn>10</mn><mn>6</mn></msup><mo>×</mo><msup><mrow><mo>(</mo><mfrac><mn>295</mn><mrow><mn>19</mn><mspace width="0.2em"/><mtext>k</mtext><mo>−</mo><mn>5.7</mn><mspace width="0.2em"/><mtext>k</mtext></mrow></mfrac><mo>)</mo></mrow><mn>2</mn></msup><mo>≈</mo><mn>140</mn><mspace width="0.2em"/><mtext>s</mtext></mrow></math>

long after it has burnt out, as a match will not light a block of oak; a
lighter in about 8 s, a torch in under 3.
