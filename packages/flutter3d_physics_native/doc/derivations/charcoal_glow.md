# How charcoal glows, in the core's terms

Charcoal has no flame. Its carbon burns at its surface as fast as oxygen
diffuses to it, and the surface glows; no open source gives that rate, or
a heat of gasification or a least burning for it (gap G8 of the research
notes). The core burns a patch at ṁ'' = *q*''<sub>net</sub>/*L* and puts
it out below ṁ''<sub>cr</sub>, so CHARCOAL needs those two, and a
temperature it catches at, in the core's own terms. This derives them.

## What is measured

- A wood ember glowing at 931 ± 6 °C, 1204 K, by colour-camera pyrometry
  (Kim and Sunderland, *Fire Safety Journal* 106, 2019).
- Charcoal's surface emissivity, 0.77 (Vanaparti, MS thesis, Auburn
  University, 2016).
- Eucalyptus charcoal pieces 35.5 mm across: conductivity 0.030 W/(m K),
  specific heat 1017 J/(kg K), density 345 kg/m³ (Santos and colleagues,
  *CERNE* 26, 2020).
- Char's heat of combustion, 29.5 to 30.5 MJ/kg (Zeng and colleagues, *Fire
  Safety Science* 11, 2014, table 2): 30 MJ/kg.
- Air: 23.3 % oxygen by mass; its properties by temperature (Incropera and
  DeWitt, *Fundamentals of Heat and Mass Transfer*, table A.4); free
  convection from a hot face looking up, Nu = 0.54 Ra<sup>1/4</sup> for
  10⁴ < Ra < 10⁷ (idem, eq. 9.30).

## The rate oxygen allows

Oxygen reaches the surface across the same boundary layer heat leaves
through, so with a Lewis number of one the mass transfer coefficient is
*h*/*c*<sub>p</sub>, and carbon burns to CO₂ at the diffusion-limited rate
(Spalding's transfer number, with B the oxygen's mass fraction over the
oxygen a kilogram of carbon takes, 32/12)

<math display="block"><mrow><msubsup><mover><mi>m</mi><mo>˙</mo></mover><mi>D</mi><mo>″</mo></msubsup><mo>=</mo><mfrac><mi>h</mi><msub><mi>c</mi><mi>p</mi></msub></mfrac><mi>ln</mi><mo>(</mo><mn>1</mn><mo>+</mo><mi>B</mi><mo>)</mo><mo>,</mo><mspace width="1em"/><mi>B</mi><mo>=</mo><mfrac><mn>0.233</mn><mrow><mn>32</mn><mo>/</mo><mn>12</mn></mrow></mfrac><mo>=</mo><mn>0.0874</mn><mo>,</mo><mspace width="1em"/><mi>ln</mi><mo>(</mo><mn>1</mn><mo>+</mo><mi>B</mi><mo>)</mo><mo>=</mo><mn>0.0838</mn></mrow></math>

For a 35.5 mm lump glowing at 1204 K, with the air's properties at the
film's 749 K, Ra = 6.4 × 10⁴, *h* = 13.3 W/(m² K), *c*<sub>p</sub> =
1087 J/(kg K):

<math display="block"><mrow><msubsup><mover><mi>m</mi><mo>˙</mo></mover><mi>D</mi><mo>″</mo></msubsup><mo>=</mo><mn>1.02</mn><mspace width="0.2em"/><mtext>g/(m² s)</mtext></mrow></math>

That surface radiates 0.77 σ (1204⁴ − 293⁴) = 91.5 kW/m² and loses
13.3 × 911 = 12.1 kW/m² to the air: **0.88** of what leaves it is
radiation, the fire's radiant share.

## Where a lump on its own holds

Alone in still air, a lump glows where the heat of the rate oxygen allows
pays for what it loses,

<math display="block"><mrow><msubsup><mover><mi>m</mi><mo>˙</mo></mover><mi>D</mi><mo>″</mo></msubsup><mo>(</mo><mi>T</mi><mo>)</mo><mspace width="0.2em"/><mi>Δ</mi><msub><mi>H</mi><mi>c</mi></msub><mo>=</mo><mi>ε</mi><mi>σ</mi><mo>(</mo><msup><mi>T</mi><mn>4</mn></msup><mo>−</mo><msubsup><mi>T</mi><mi>a</mi><mn>4</mn></msubsup><mo>)</mo><mo>+</mo><mi>h</mi><mo>(</mo><mi>T</mi><mo>−</mo><msub><mi>T</mi><mi>a</mi></msub><mo>)</mo></mrow></math>

which, by halving over *T* with *h* from the same correlation, is at
**860.8 K**, burning 1.03 g/(m² s) and radiating 23.7 kW/m². That is
CHARCOAL's ignition temperature: the coolest a glowing surface stands at
by its own oxygen.

## In the core's terms

The core's patch balance at the ignition temperature is

<math display="block"><mrow><mi>L</mi><mspace width="0.2em"/><msup><mover><mi>m</mi><mo>˙</mo></mover><mo>″</mo></msup><mo>=</mo><msubsup><mi>q</mi><mtext>flame</mtext><mo>″</mo></msubsup><mo>+</mo><msubsup><mi>q</mi><mtext>outside</mtext><mo>″</mo></msubsup><mo>−</mo><mi>ε</mi><mi>σ</mi><mo>(</mo><msubsup><mi>T</mi><mtext>ig</mtext><mn>4</mn></msubsup><mo>−</mo><msubsup><mi>T</mi><mi>a</mi><mn>4</mn></msubsup><mo>)</mo></mrow></math>

A coal has no flame of gas standing on it — `flame_convection` and
`flame_absorption` are nought — so what keeps it burning is what reaches
it from outside, never more than its own glow's
εσ*T*<sub>f</sub>⁴, 91.7 kW/m², the most the core lets a surface take. A
coal among coals glowing at 1204 K takes that much, and there it should
burn at the rate oxygen allows:

<math display="block"><mrow><mi>L</mi><mo>=</mo><mfrac><mrow><mi>ε</mi><mi>σ</mi><msubsup><mi>T</mi><mi>f</mi><mn>4</mn></msubsup><mo>−</mo><mi>ε</mi><mi>σ</mi><mo>(</mo><msubsup><mi>T</mi><mtext>ig</mtext><mn>4</mn></msubsup><mo>−</mo><msubsup><mi>T</mi><mi>a</mi><mn>4</mn></msubsup><mo>)</mo></mrow><msubsup><mover><mi>m</mi><mo>˙</mo></mover><mi>D</mi><mo>″</mo></msubsup></mfrac><mo>=</mo><mfrac><mrow><mn>91.7</mn><mo>−</mo><mn>23.7</mn><mspace width="0.2em"/><mtext>kW/m²</mtext></mrow><mrow><mn>1.02</mn><mspace width="0.2em"/><mtext>g/(m² s)</mtext></mrow></mfrac><mo>=</mo><mn>66.6</mn><mspace width="0.2em"/><mtext>MJ/kg</mtext></mrow></math>

The least burning is the glowing surface's own firepoint: the rate whose
heat just pays for its radiation where it catches,

<math display="block"><mrow><msubsup><mover><mi>m</mi><mo>˙</mo></mover><mtext>cr</mtext><mo>″</mo></msubsup><mo>=</mo><mfrac><mrow><mi>ε</mi><mi>σ</mi><mo>(</mo><msubsup><mi>T</mi><mtext>ig</mtext><mn>4</mn></msubsup><mo>−</mo><msubsup><mi>T</mi><mi>a</mi><mn>4</mn></msubsup><mo>)</mo></mrow><mrow><mi>Δ</mi><msub><mi>H</mi><mi>c</mi></msub></mrow></mfrac><mo>=</mo><mfrac><mrow><mn>23.7</mn><mspace width="0.2em"/><mtext>kW/m²</mtext></mrow><mrow><mn>30</mn><mspace width="0.2em"/><mtext>MJ/kg</mtext></mrow></mfrac><mo>=</mo><mn>0.79</mn><mspace width="0.2em"/><mtext>g/(m² s)</mtext></mrow></math>

So a coal burns on while it is heated by at least 23.7 + 0.79 × 66.6 =
**76 kW/m²**, and goes out short of it. Against the flames that light
charcoal in practice:

| Heated by | kW/m² | Holds a coal? |
|---|---|---|
| A match (NBS Monograph 173, table 6A) | 18–20 | no |
| A newspaper fire (Ohlemiller and Villa, NISTIR 4348, p. 6) | 74 ± 13 | at the edge |
| A propane torch (FAA AC 20-135, §6) | ≥ 105.6 | yes |
| Coals around it glowing at 1204 K | 91.7 | yes |

as a chimney starter's crumpled newspaper lights charcoal slowly and a
torch quickly. CHARCOAL's `burn_rate` is the 1.02 g/(m² s) of a coal glowing at 1204 K, which
`NativeBurner.charcoal` burns over the surface of a brazier's coals.

## What is left out

- Kinetics: below about 900 K carbon's oxidation is slower than diffusion,
  which would put a lone lump out sooner than this says; no open rate law
  was found.
- A heap feeding itself. The core passes a fire's radiant share to what
  faces it, but a coal's glow reaches a neighbour as only part of 91.7
  kW/m², so a heap of CHARCOAL left alone goes out; a brazier is a
  `NativeBurner.charcoal`.
- Carbon burning to CO at the surface, with the CO burning above it in a
  faint blue flame: all of it is counted as burning to CO₂ at the surface.
- Ash, 0.5 to 5 % (Antal and Grønli, *Ind. Eng. Chem. Res.* 42, 2003): the
  share left, so 0.9725 of the mass burns.
