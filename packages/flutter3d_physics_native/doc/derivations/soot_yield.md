# The soot each preset's fire makes

`F3dMaterial.soot_yield` is the kilograms of soot a fire makes per kilogram
it burns. The core passes it on in `f3d_world_read_fires` as soot per joule,
*Y*<sub>s</sub>/Δ*H*<sub>c</sub>, and what draws the smoke reads light
stopped from it at 8.7 m² a gram (`flutter3d_elements/doc/smoke_plume.md`).
This says which measurement each preset takes, and derives the one no open
source gives: a tyre's (gap G2 of the research notes' soot section).

## Which measurement, and why

Soot yields measured by laser extinction — the cone calorimeter's and the
NIST hood's — are the light the smoke stopped divided by the same 8.7 m²/g
the view multiplies by, so the view gets back the darkness that was
measured. Small samples under a heater make more soot than the same fuel
burning freely: red oak in the cone gives 0.001, 0.003 and 0.011 at 25, 50
and 75 kW/m² (UL FSRI, Oak Flooring), while whole pine cribs, pallets and
Douglas-fir trees burning freely under the hood give 0.002 to 0.005 (NIST
TN 2102, table 1; TN 2327r1, table 11). A game's fire is a thing burning
freely, so a preset takes a free-burning measurement where one was made.

| Preset | *Y*<sub>s</sub> | Source |
|---|---|---|
| WOOD | 0.015 | Wood in small well-ventilated fires (Tewarson, SFPE Handbook, as the FDS User's Guide, NIST SP 1019, eq. 13.18, gives it): the generic value, kept so a fire of WOOD looks as it did |
| OAK | 0.003 | Oak flooring in the cone at 50 kW/m² (UL FSRI), inside the 0.002 to 0.005 free-burning wood measures |
| PINE | 0.0020 | Pine cribs burning freely, 0.0020 ± 0.0003 (NIST TN 2102, table 1) |
| PAPER, CARDBOARD | 0.0014 | Corrugated boxes with crinkled kraft paper burning freely, 0.0014 ± 0.0003 (NIST TN 2102, table 1) |
| THATCH | 0.00503 | Little bluestem grass under the hood (NIST TN 2314, table 7) |
| PARAFFIN | 0.04 | A paraffin pool in the cone, 0.035 to 0.045 (Hamins, Bundy and Dillon, *J. Fire Prot. Eng.* 15, 2005); a candle's flame is below its smoke point and shows no soot (idem), but at 77 W it darkens nothing anyway |
| CHARCOAL | 0 | It burns at its surface; soot forms only in a gas flame |
| RUBBER | **0.092** | Derived below |

For crude oil, which no preset is, pool fires metres across give 0.13 to
0.16 (Evans and colleagues, *J. Res. NIST* 106, 2001, §4.2.1.6).

## A tyre's soot

No open source gives a soot yield for tyre rubber; the SFPE Handbook's
table for SBR and polybutadiene is not open. What is open is the
particulate a tyre gives off burning in the open: 97.1 g a kilogram of
tyre in chunks, 10.6 % of it extracting as organic compounds (EPA,
*Air Emissions from Scrap Tire Combustion*, EPA-600/R-97-115, 1997,
table 5).

Not all of that stops light as soot does. The light a gram of combustion
aerosol stops falls with the organic share of its carbon, as Widmann and
colleagues measured,

<math display="block"><mrow><msub><mi>K</mi><mi>m</mi></msub><mo>=</mo><mn>8.6</mn><msup><mrow><mo>(</mo><mfrac><mtext>EC</mtext><mtext>TC</mtext></mfrac><mo>)</mo></mrow><mn>0.36</mn></msup><mspace width="1em"/><mtext>m²/g</mtext></mrow></math>

(*J. Aerosol Sci.* 36, 2005, eq. 4, for EC/TC 0.2 to 0.9). Taking the
non-extracted part as elemental carbon, EC/TC = 1 − 0.106 = 0.894, the
tyre's particulate stops 8.6 × 0.894<sup>0.36</sup> = 8.26 m²/g. A soot
yield is read at 8.7 m²/g, so the yield that stops as much light is

<math display="block"><mrow><msub><mi>Y</mi><mi>s</mi></msub><mo>=</mo><mn>0.0971</mn><mo>×</mo><mfrac><mn>8.26</mn><mn>8.7</mn></mfrac><mo>=</mo><mn>0.092</mn></mrow></math>

It falls inside what other open measurements bracket: polystyrene cups,
an aromatic polymer like the styrene in SBR, 0.098 to 0.109 burning freely
(NIST TN 2102, table 1); EPDM roofing, a synthetic rubber, 0.15 in the cone
(UL FSRI). Tyre shreds, which burnt slower, gave 0.0734 with 19.7 %
organic (EPA, table 5), 0.067 the same way.

## What is left out

- The metals and ash in a tyre's particulate — zinc oxide among them — are
  counted as soot.
- Smouldering: its aerosol stops about 0.58 of what flaming soot does
  (Seader and Einhorn, as NIST TN 2314 §2.6 cites them). The core's fires
  flame.
