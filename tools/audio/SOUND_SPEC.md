# Sound specification — the mechanics lab (PROVA MECCANICHE)

Every sound here is **made from code** (tools/audio/dsp.py): no recordings, no
sample libraries, no downloaded assets. That keeps the game free of licences
and the build reproducible. Sounds play only in the mechanics lab.

## The world they live in

A gothic tower climbed by a lone pilgrim (the Viandante: hooded ivory cloak,
leather boots, an iron lantern with a blue flame). Every character is a
**paper standee on a stone diorama**: a pixel-art figure drawn on a paper card
that stands on a small iron base, on stone floors, in torch-lit stone halls.
The fight is tactical and timed (a 20-second window, one world beat a second).

So every sound is three things at once:
1. **the material truth of the action** — cloth, leather, iron, wood, bone,
   stone, glass, flame, electricity;
2. **a touch of paper** — the signature of the game: a card that is pushed
   slides with a dry papery scrape on stone; a hit crumples paper a little; a
   death folds and topples a card. Light, never comic;
3. **the stone hall** — the build adds a dark stone reverb (`wet`, `rt60`):
   make the recipes **dry**, the room is added for you.

Tone: dark fantasy, grounded, a little theatrical (a paper theatre). Not
chiptune, not sci-fi, not cartoon. Avoid bare oscillators for physical
actions: use filtered noise, modal resonances (metal, wood, stone, glass),
Karplus-Strong strings, granular bursts. Tonal elements (magic, wards, UI)
stay in one harmonic world: **D Phrygian** (D, Eb, F, G, A, Bb, C; D3 =
146.83 Hz, D4 = 293.66 Hz). **No voices and no words**: creatures growl,
snarl and gasp through formant-filtered noise and low growl oscillators.

## Technical rules

- Each family is one module, `tools/audio/sfx_<family>.py`, which imports
  `from dsp import *` and `from registry import sound`, and registers one
  function per sound name listed below (exact names). A function takes
  `seed` and returns a **dry mono numpy float array** at `SR` (44100).
- Derive all randomness from `seed` (seed, seed+1...): builds are identical.
- Sound starts at t = 0 when its trigger fires. Key events must land on the
  listed **marks** (seconds from the start): those are the moments the
  animation shows (an impact, a footfall, the card starting to slide). Pass
  them as `marks=` so previews draw them.
- Lengths: keep within the listed length (the build trims the silent end and
  adds the hall's tail). Never leave a click: start and end at zero crossings
  or under a short fade; the build fades the last 6 ms.
- Loudness: set `loudness=` to the listed target (dB of the build's
  loudness measure). Leave headroom inside the recipe (peaks around 0.5–0.9).
- `wet` (reverb send) defaults per row; tight foley 0.12–0.2, big events
  0.3–0.45, magic 0.3–0.4.
- Keep each recipe fast (under ~2 s of CPU): avoid huge Python loops;
  karplus() loops per sample, so use it for short strings only.

### Checking without ears

    PY="C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe"
    cd tools/audio
    "$PY" build_sfx.py --only <family> --preview <dir> --no-write

For every sound this writes `<dir>/<name>.png` (waveform over a log-frequency
spectrogram, 30 Hz–20 kHz; green ticks are the marks; grey dotted lines are
100 Hz, 1 kHz, 10 kHz), `<dir>/<name>.wav` and `<dir>/report.json` (duration,
peak, loudness, time to peak, audible length, spectral centroid, energy share
per band, DC, clipped samples). Look at the PNGs (open them with the Read
tool) and check the numbers against what the sound should be. What a good
sound looks like:

- **footstep / thump**: attack under 5 ms, body energy 80–400 Hz, decay
  60–150 ms, a short grit layer 2–6 kHz; centroid ~400–1500 Hz.
- **whoosh** (swing, dash, throw): no hard attack; band-passed noise whose
  band and level swell then fall over 120–350 ms; a faint pitch movement.
- **metal clang / blade**: a sharp transient, then several inharmonic lines
  ringing 0.3–1.5 s, darker as they decay.
- **wooden knock**: 2–4 low modes (150–900 Hz) dying within 80–200 ms.
- **flesh / cloth hit**: low muffled thump (60–250 Hz) + a short broadband
  slap, no ringing.
- **explosion**: broadband attack, sub/low body for 0.4–1 s, debris grains
  falling for 1–2 s, long hall tail.
- **electricity**: crackle (sparse impulses, 2–10 kHz) over a buzz with mains-
  like harmonics (around 90–120 Hz and its multiples), sharp snaps.
- **fire**: low roar (brown noise under 400 Hz) + crackle grains.
- **magic / ward**: bell or FM partials in D Phrygian, a shimmer (tremolo,
  slight detune), soft attack unless it is a strike.
- **paper**: grains of band-passed noise 1.5–8 kHz, 5–30 ms each; a card
  sliding on stone is a dense gritty scrape (noise through a moving band,
  1–5 kHz) for the slide's length.

Report the problems you could not fix rather than hide them.

## Triggers (how the game plays them)

The lab plays them from what the board shows (src/render/lab_sounds.odin), so
each sound starts with the drawing it belongs to:

- **Characters**: when a living card starts a clip, its character's sound for
  that action: the pilgrim's steps by direction (side, away, toward), a dash,
  attacks, casts, hurts (front or back), a block (only a blow the ward stops;
  a blocked step bumps with `ui_move_blocked`), loot picked up, the death.
  Enemies: move, attack (the archer's is its shot, the bomber's its throw),
  hurt, death; a brute's run of two cells or more is its charge, the bishop's
  cast is its protection, the archmage's its fire. When an enemy's card falls
  into its telegraph loop: `ghoul_windup`, `archer_aim`, `brute_windup`,
  `bomber_prepare`; the pilgrim's daze plays `pilgrim_stunned`.
- **The shadow** (Movimento Ombra): `card_shadow_step` when the card is
  played; `pilgrim_shadow_sink` as his card starts going down into its
  shadow and `pilgrim_shadow_rise` as it starts climbing back out (the
  card's own cues pace both); `pilgrim_shadow_step` on every step of the
  shadow, which starts no clip on the card, so never the boots or the
  card's scrape; `ui_critical` when a diagonal lands on a beat and
  `ui_beat_tick` on the shadow's own beats.
- **Cues**: `card_<id>` when a card is played (before anything it puts on the
  board, so a Tesla card's coil is not heard twice), cards drawn dealt one
  after the other, refocus, gold (not after a Scopa card, which has its own
  coins), energy, loot drops, statuses applied and worn off, misses, blocked
  moves, heals, bombs armed, disarmed and exploding (barrels have their own),
  coils set down by any other way, one zap per discharge, shock floors, fire
  catching, hits on objects (ice cracks).
- **The room**: `ui_beat_tick` on every whole second of an open window,
  `ui_critical` when an action claims the beat, `ui_window_end`, `ui_stun`,
  `ui_defense_prompt`, `pilgrim_parry` on a parry or deflection that lands,
  `world_tesla_ring` when the square opens the Ring, `world_spawn` when an
  enemy arrives, `ui_defeat` after the fall; `amb_crypt_loop` under it all.

Each play gets a small random pitch (±4%) and volume (±1.5 dB) and is panned
by its place on the screen, so recipes need not vary. The player's effects
volume and mute apply.

## The sounds

Columns: name — when it plays — length — marks (s) — loudness — wet — what it
is. Times come from the living cards' animations (tools/art/living_actions.py).

### Family `pilgrim` — the Viandante (player)

Ivory wool cloak, leather boots, iron lantern with a blue flame (a small glass
chime and iron rattle when he moves hard). Warm, light, human scale.

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| pilgrim_move_side | step sideways | 1.0 | 0.0, 0.275, 0.28, 0.495, 0.64 | -21 | 0.18 | coil back (cloak rustle 0–0.24), shoulder shoves the paper card at 0.275 (a soft cardboard thump), the card's iron base scrapes across stone while it slides 0.275–0.495, boot lands at 0.64 |
| pilgrim_move_up | step away (up) | 1.0 | 0.205, 0.285, 0.29, 0.505, 0.5 | -21 | 0.18 | a hop: boot push-off scuff at 0.205, shoves the card at 0.285 (thump + slide to 0.505), lands at 0.5 with a cloak flutter |
| pilgrim_move_down | step toward (down) | 1.0 | 0.275, 0.28, 0.495, 0.57 | -21 | 0.18 | a kick: the boot kicks the card at 0.28 (firmer, lower thump than the shove), slide to 0.495, boot down at 0.57 |
| pilgrim_dodge | dash 2 cells / dodge | 1.0 | 0.08, 0.12, 0.34, 0.31 | -20 | 0.18 | a fast low cloak whoosh from 0.08, the card shoots across stone 0.08–0.34 (fast scrape), skid-stop at 0.31 |
| pilgrim_attack | bump attack | 1.0 | 0.07, 0.12, 0.125, 0.38, 0.61 | -18 | 0.2 | swings the lantern on its chain: whoosh from 0.07, iron-and-glass blow lands at 0.125 (blunt thud + iron clank + tiny glass chime), backflip: cloak flap, boots land at 0.38 and 0.61 |
| pilgrim_cast | plays a card (his gesture) | 0.8 | 0.17, 0.25, 0.57 | -24 | 0.25 | cloak swish as the hand rises, the lantern flame flares at 0.25 (a soft blue whoomp + glass ring), settles at 0.57; under the card's own sound, so keep it light |
| pilgrim_hurt | is hit (front) | 0.8 | 0.118 | -18 | 0.18 | thrown back: muffled body blow at 0.118 + cloth slap + paper crumple + lantern rattle, a short exhale-like noise breath (no voice) |
| pilgrim_hurt_back | is hit from behind | 0.8 | 0.118 | -18 | 0.18 | same family as hurt, pitched forward: slightly higher, sharper slap |
| pilgrim_block | blocks (shield absorbs) | 0.65 | 0.118 | -19 | 0.22 | a ward takes the blow at 0.118: dull thud through a shimmering ward (soft D-Phrygian partials), lantern chimes |
| pilgrim_parry | parries (QTE success) | 0.8 | 0.05 | -17 | 0.3 | bright steel-on-iron clang at 0.05 with a ringing tail; satisfying |
| pilgrim_stunned | stunned / staggered | 1.6 | — | -24 | 0.3 | dazed: a high thin ringing with slow wobble, faint circling tinkles of the lantern; quiet, unsettling |
| pilgrim_interact | picks up loot | 0.7 | 0.28 | -22 | 0.2 | crouches (cloth) and pockets it at 0.28: coins clink into a leather pouch |
| pilgrim_heal | is healed | 0.9 | — | -21 | 0.35 | warm rising swell, soft bell partials (D, F, A), a breath of air; comforting |
| pilgrim_death | dies | 1.2 | 0.118, 0.68 | -18 | 0.3 | struck at 0.118, the card folds and topples (paper crease + slap on stone at 0.68), the lantern rolls and its glass cracks, the blue flame gutters out |
| pilgrim_shadow_sink | sinks into his shadow (Movimento Ombra) | 0.65 | 0.0, 0.27 | -21 | 0.3 | a soft inky down-swell (a dark band falling 700 -> 110 Hz, peak 0.15) as the card goes down, the card folding under it (a cardboard creak and crease crackles, muffled as through ink), flat at 0.27 with a soft low gulp; a faint muffled chime of the lantern globe |
| pilgrim_shadow_step | one step of the shadow (one every 0.4 s at most) | 0.35 | 0.0, 0.07 | -24 | 0.2 | very short, soft, airy, ink-like: a dark swish slipping one cell, no attack, peak 0.07 where the pool glides fastest; no boots, no card scrape; must not tire |
| pilgrim_shadow_rise | rises out of his shadow (the world resumes) | 0.8 | 0.0, 0.13, 0.34 | -20 | 0.3 | an inky up-swell (120 -> 900 Hz, peak 0.12), the card unfolding as it comes out of the floor at 0.13 (a flex creak, crisp paper grains, a spring), a light thud of the card set down on stone at 0.34 (its iron base knocks, the lantern jingles), the cloak settles |

### Family `ghoul` — the Chaser

A red, skinless, feral ghoul that runs on all fours, bone claws. Wet, ragged,
fast. Non-verbal snarls (formant noise + low growl).

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| ghoul_move | moves (any direction) | 0.95 | 0.09, 0.24, 0.39, 0.54, 0.61 | -21 | 0.16 | three bounds: claws scrape and slap stone at 0.24, 0.39, 0.54; ragged panting snarl under it; the card scrapes 0.09–0.61 |
| ghoul_windup | is about to attack | 0.6 | — | -21 | 0.2 | a rising guttural growl, wet clicks |
| ghoul_attack | claws | 0.9 | 0.06, 0.118, 0.243, 0.33 | -18 | 0.18 | lunge whoosh from 0.06, first claw rake at 0.118 (bone scrape + flesh rip), second at 0.243, lands at 0.33; a snarl peaks with the first rake |
| ghoul_hurt | is hit | 0.75 | 0.118 | -18 | 0.18 | wet meaty thud at 0.118 + a sharp shriek-like snarl (formant noise, no words) |
| ghoul_death | dies | 1.1 | 0.118, 0.3, 0.62 | -18 | 0.3 | hit, collapses in two heavy wet flops (0.3, 0.62), a gurgling rattle fades |

### Family `archer` — the crossbowman

Red-hooded, light leather, heavy wooden crossbow with an iron prod and a
crank. Taut, mechanical, quick.

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| archer_move | moves | 0.9 | 0.165, 0.17, 0.405, 0.42 | -22 | 0.16 | a low dash: quick light steps, quiver bolts rattle, the card darts 0.165–0.405, heel skid at 0.42 |
| archer_aim | takes aim (MIRA) | 0.7 | — | -21 | 0.2 | cranks the crossbow: ratchet clicks speeding up, the string creaks under tension, a final lock click |
| archer_shoot | shoots | 0.75 | 0.06, 0.064 | -18 | 0.25 | release at 0.06: a hard wooden-iron thunk + string twang (karplus, low) + bolt whistle flying away (doppler down); recoil thump |
| archer_hurt | is hit | 0.75 | 0.118 | -18 | 0.18 | leather and body thud at 0.118, crossbow wood knocks, a sharp breath-like hiss |
| archer_death | dies | 1.2 | 0.118, 0.69 | -18 | 0.3 | hit, falls; the crossbow clatters on stone at 0.69 (wood + iron) |

### Family `brute` — the brute

A huge armoured brute: iron plates, chains, a heavy cleaver, a skull mask.
Slow, crushing, low.

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| brute_move | moves | 1.0 | 0.2, 0.42, 0.64 | -18 | 0.22 | two crushing armoured stomps at 0.2 and 0.42 (deep thud, plates jangle, chain swings), the card drags heavily 0.2–0.64 |
| brute_charge | charges (CARICA) | 1.0 | 0.1, 0.3, 0.5, 0.7 | -17 | 0.25 | heavy running: four stomps accelerating, armour clatter, a rushing low whoosh |
| brute_windup | prepares the blow | 0.8 | — | -20 | 0.22 | raises the cleaver: leather creak, chain drag, a low iron scrape, menace |
| brute_attack | cleaves | 1.0 | 0.08, 0.143, 0.26 | -15 | 0.3 | a huge low whoosh from 0.08, the cleaver chops at 0.143 (massive iron impact into stone, debris), chains settle |
| brute_hurt | is hit | 0.7 | 0.118 | -17 | 0.2 | blow on iron plate at 0.118: dull heavy clang, armour rattle, a deep grunt-like growl |
| brute_death | dies | 1.2 | 0.118, 0.3, 0.62 | -16 | 0.35 | hit; collapses: armour crashes at 0.3, the cleaver falls with a ring at 0.62, chains slither |

### Family `bomber` — the bomber

Red-hooded, a sling of iron bombs, a smoking fuse. Hops; clinks; sizzles.

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| bomber_move | moves (hops) | 0.85 | 0.12, 0.27, 0.44, 0.48 | -21 | 0.18 | two hops landing at 0.27 and 0.44 (light boots), iron bombs knock together on each landing, the card hops 0.12–0.48 |
| bomber_prepare | lights a bomb (PREPARA) | 0.8 | 0.1 | -20 | 0.2 | a flint strike at 0.1 (spark scratch), the fuse catches and sizzles |
| bomber_throw | throws (LANCIA) | 0.6 | 0.08, 0.12 | -19 | 0.22 | an underarm throw: cloth whoosh at 0.08, the bomb leaves at 0.12 trailing a sizzle that recedes |
| bomber_hurt | is hit | 0.75 | 0.118 | -18 | 0.18 | thud at 0.118, the bombs clank, a nervous hiss |
| bomber_death | dies | 1.2 | 0.118, 0.69 | -18 | 0.3 | hit, falls; bombs roll and clink across stone (from 0.69) |

### Family `bishop` — the custodian

A bishop in red and black robes with a mitre and a gilded crozier. He
levitates, shields his allies. Holy, hushed, golden.

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| bishop_move | moves (glides) | 1.0 | 0.26, 0.68 | -22 | 0.3 | rises in a soft airy hum (no footsteps), robe swish, the card glides 0.26–0.68 with a faint crozier knock at 0.26 |
| bishop_protect | shields an ally (PROTEGGE) | 1.0 | 0.5 | -19 | 0.4 | an invocation: a choir-like pad (formant "ah" from noise and saw, D Phrygian) swells, a bell rings out as the ward lands at 0.5 |
| bishop_attack | strikes with the crozier | 0.9 | 0.125 | -18 | 0.25 | a short swing, a wooden-and-gilt knock at 0.125 (wood modes + small metal ring) |
| bishop_hurt | is hit | 0.75 | 0.118 | -18 | 0.2 | thud at 0.118, robes slap, the crozier's ornaments tinkle, a breathy hiss |
| bishop_death | dies | 1.2 | 0.118, 0.62 | -18 | 0.35 | hit, sinks; the crozier falls and rings at 0.62, a last bell-like overtone fades |

### Family `archmage` — the demolitionist

A crowned archmage in black and red robes, a fire staff, a burning hand.
Floats. Fire and embers.

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| archmage_move | moves (floats) | 1.0 | 0.14, 0.64 | -22 | 0.3 | a low drifting drone with an ember crackle, robes flutter, glides 0.14–0.64 |
| archmage_cast | conjures fire (bombard, ignite) | 0.9 | 0.25 | -18 | 0.35 | inhale-like roar rising, a fireball flung at 0.25 (whoomp + roar + crackle) |
| archmage_attack | strikes with the staff | 0.9 | 0.125 | -18 | 0.28 | staff swing, an arcane-fire thump at 0.125 |
| archmage_hurt | is hit | 0.75 | 0.118 | -18 | 0.2 | thud, embers scatter, a hiss |
| archmage_death | dies | 1.2 | 0.118, 0.62 | -17 | 0.35 | hit, the fire goes out with a collapsing roar, the crown clatters at 0.62 |

### Family `cards_arms` — cards of steel, guard and fortune

Played when the Viandante plays the card (the card leaves the hand: begin
with a short paper flick, ~20 ms, different each time). Then the effect.
Length ~0.5–0.9 s; loudness -19 unless noted; wet 0.25.

| name | the card | what |
|---|---|---|
| card_strike | Strike: a blow, exposes | a short blade slash: whoosh + crisp cut |
| card_cross_slash | Cross Slash: damage in a cross | two crossing slashes, the second answering the first |
| card_heavy_blow | Heavy Blow: big damage, stuns | a hammer wind-up and a massive blunt impact, a stunned ring |
| card_sundering_blow | Sundering Blow: 2 dice of its level (2d4 up to 2d20), may push | dice rattle, then a stone-cracking sundering hit |
| card_fate_strike | Fate Strike: 1 die of its level + damage | a single die rolled across wood, then a fated strike (blade + bell) |
| card_guard | Guard: shield | a ward rises: a solid, hopeful bell partial + a wooden shield thump |
| card_purifying_guard | Purifying Guard: shield, cures poison | the guard's ward plus a cleansing shimmer, bright and clean |
| card_thorn_coat | Thorn Coat: thorns | bramble vines creak and tighten, thorny clicks |
| card_afterimage | Afterimage: dodge without recovery | a ghostly echoing whoosh, the sound repeats fainter (delay) |
| card_shadow_step | Movimento Ombra: 4 s in his shadow, the world stops | a dark sinking whoosh over a low glide (D3 down to D2), then a D bell struck as time stops (0.25): its shimmer slows to a standstill and the ring hangs, still |
| card_counter_rune | Counter Rune: counter-attack charges | a rune carved in stone (scratch) and lit (a low glowing hum) |
| card_battle_focus | Battle Focus: draw, see further | a deep slow breath of air and a single clear bell; time slows |
| card_calculated_risk | Calculated Risk: draw, discard | cards riffled and one flicked away |
| card_shove | Shove: push then hit | a firm two-handed shove (cloth + body thump) |
| card_dash | Dash: move far, shield first | a fast rushing whoosh with a ward click |
| card_grappling_hook | Grappling Hook: pulls an adjacent foe | a chain flung, an iron hook bites, the chain hauls taut |
| card_titan_grip | Titan Grip: damage, throw, stun | a gauntlet clenches (leather + iron), a heavy throw whoosh |
| card_sei_denari | 6 of coins (Scopa): +6 gold | a handful of coins spilled, bright |
| card_sette_denari | 7 of coins (Scopa): +7 gold | a bigger handful, with a little flourish |

### Family `cards_arcana` — cards of storm, fire, poison and devices

Same rules as `cards_arms`.

| name | the card | what |
|---|---|---|
| card_arc_bolt | Arc Bolt: a quick electric bolt | a sharp crack of lightning, a snap |
| card_chain_lightning | Chain Lightning: jumps between foes | a crackling bolt that leaps three times, each jump higher |
| card_piercing_ray | Piercing Ray: a beam in a line | a charging whine then a searing beam (sustained, bright) |
| card_spark | Spark: small damage | a tiny spark snap (loudness -23: smaller in level too) |
| card_spark_forge | Spark Forge: creates Sparks | a small forge: hammer on anvil, sparks fly |
| card_storm_crown | Storm Crown: a crown of storms | distant thunder rolls, a crackling halo builds overhead |
| card_shock_floor | Shock Floor: an electric floor trap | a metal plate set down, then an electric hum spreads across it |
| card_tesla_coil | Tesla Coil: a coil device | an iron coil set down with a clank, its capacitor whines up and arcs once |
| card_firebomb | Firebomb: fire in 3x3, lights barrels | a fuse lit and a bomb tossed (the explosion plays separately) |
| card_toxic_wave | Toxic Wave: applies poison | a wave of noxious gas: a low wet hiss spreading, bubbles |
| card_venom_needle | Venom Needle: damage + poison | a needle flicked (thin whistle), a tiny wet prick |
| card_caustic_bloom | Caustic Bloom: poison in 3x3 | an acid flower bursts open: bubbling bloom, sizzle |
| card_twin_venom | Twin Venom: 2 dice of its level, poison on a pair | two vials uncorked and splashed, the dice rattle |
| card_volatile_study | Volatile Study: creates Sparks, draws | glassware clinks, a volatile mixture fizzes and pops |
| card_prismatic_barrage | Prismatic Barrage: 3 dice of its level, crystal shots | three crystalline shots (glassy pings in D Phrygian, rising) |

### Family `world` — devices, bombs, the room's events

| name | when | length | loud | wet | what |
|---|---|---|---|---|---|
| world_tesla_deploy | a Tesla Coil appears on the board | 1.0 | -19 | 0.3 | heavy iron base set on stone, the coil charges up (rising whine + hum) |
| world_tesla_zap | a coil (or the ring) strikes a foe | 0.6 | -17 | 0.3 | an arc discharge: violent crackle + snap, a hum burst |
| world_tesla_ring | the Tesla square closes into a ring | 1.6 | -15 | 0.4 | four coils link: a surging electric chord, buzzing, crackling, rising |
| world_shock_floor | a shock floor discharges | 0.7 | -18 | 0.25 | a plate buzzes and snaps |
| world_bomb_fuse | a bomb is armed on the board | 1.4 | -22 | 0.2 | a fuse fizzing and spitting steadily |
| world_explosion | a bomb explodes | 2.0 | -12 | 0.45 | a deep blast, stone shatters, debris rains, long hall tail |
| world_barrel_explosion | a barrel explodes | 2.0 | -12 | 0.45 | wood splinters + blast + oily fire whoosh |
| world_fire | fire on a cell | 1.2 | -20 | 0.3 | flames catch and crackle |
| world_ice_crack | an ice block cracks | 0.8 | -19 | 0.3 | ice fractures: sharp glassy cracks, creak |
| world_bomb_fizzle | a bomb is disarmed | 0.7 | -21 | 0.2 | the fuse is pinched out: a hiss that dies, a little puff |
| world_object_hit | a device or object is struck | 0.5 | -19 | 0.22 | wood-and-iron knock |
| world_spawn | an enemy arrives in the lab | 1.2 | -21 | 0.4 | a card set down on stone at once (the game hears an arrival only when the enemy already stands there), a dust puff, and the dark it came from swelling behind it and sinking back |

### Family `ui` — time, criticals, defence, statuses, rewards

Quiet and clear; they must never mask the action sounds.

| name | when | length | loud | wet | what |
|---|---|---|---|---|---|
| ui_beat_tick | every whole second (the critical beat) | 0.12 | -32 | 0.1 | a soft wooden tick (like a clock escapement), very short; must not tire |
| ui_critical | an action lands on the beat | 0.7 | -20 | 0.35 | a bright golden sting: crystal ding + shimmer (D Phrygian, A-D) |
| ui_window_end | the 20 s window runs out | 1.4 | -21 | 0.45 | a single low bell toll (D2-ish), stone resonance |
| ui_stun | the window is exhausted: stunned | 1.4 | -20 | 0.4 | a dull blow and a whirling, ringing daze |
| ui_defense_prompt | a defence QTE appears | 0.5 | -20 | 0.25 | a tense sting: low pulse + rising metallic shiver |
| ui_block_absorb | a shield absorbs damage | 0.5 | -20 | 0.25 | a ward-thud |
| ui_miss | an attack misses | 0.45 | -22 | 0.2 | a swish through empty air |
| ui_move_blocked | a move is blocked | 0.35 | -22 | 0.15 | a dull bump against stone, a paper flap |
| ui_card_draw | a card is drawn | 0.25 | -27 | 0.12 | a dry paper slide-and-flick |
| ui_refocus | the hand is refocused | 0.7 | -23 | 0.15 | a deck riffled and squared |
| ui_gold | gold gained | 0.5 | -22 | 0.2 | a few bright coins |
| ui_energy | energy gained | 0.35 | -27 | 0.25 | a soft crystal ping (D5) |
| ui_loot_drop | loot drops | 0.6 | -22 | 0.2 | a small object falls on stone and rolls |
| ui_status_poison | poison applied | 0.6 | -22 | 0.2 | bubbling, a sickly descending tone |
| ui_status_shield | a shield applied | 0.6 | -22 | 0.3 | a ward hum rises and holds |
| ui_status_thorns | thorns applied | 0.5 | -22 | 0.2 | thorny bramble clicks |
| ui_status_stagger | staggered (interrupted) | 0.6 | -21 | 0.25 | a jolt and a short wobble |
| ui_status_afterimage | afterimage applied | 0.6 | -23 | 0.35 | a ghostly breath echo |
| ui_status_burn | a burn applied (Bruciatura) | 0.6 | -22 | 0.2 | the paper catches: a dry strike, a small ignition whoomph, ember pops and singeing paper over a low roar, a faint flickering D/A ember tone |
| ui_status_slow | slow applied (Rallentamento) | 0.7 | -23 | 0.3 | the clock drags: escapement ticks coming later and later and a step lower each (A5 down to D5), over a ward octave sinking D4 -> A3 as its shimmer slows; a faint trickle of sand (the hourglass) |
| ui_status_expired | a status wears off | 0.4 | -28 | 0.2 | a soft fading puff |
| ui_defeat | the Viandante falls (defeat) | 2.0 | -18 | 0.5 | a low drone sinks, paper crumples, a distant bell |

### Family `ambience` — the room

| name | when | length | loud | wet | what |
|---|---|---|---|---|---|
| amb_crypt_loop | always, under everything (loop=True) | 24.0 exact | -34 | 0.25 | a seamless loop: a low wind through stone halls, sparse water drips far away, a torch's soft crackle, rare chain creaks; the end must flow into the start |
