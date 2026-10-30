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
- **The ground** (Pozza di Veleno, Incendio): the pool's landing plays
  `world_pool_splash`, the fire's `world_fire`; an enemy whose card steps
  into a pool splashes (`world_pool_splash`, panned to it) and into a fire
  makes it flare (`world_fire`); when a fire's arms reach further at a new
  window `world_fire_spread` plays once (a fire just lit is its card's
  landing), and when one goes out at its fifth `world_fire_out`.
- **The player's charges** (Deflect, Feretro, Dado del Destino, Lama
  Velenosa): each card plays `card_<id>` and its charge, as it is loaded,
  `ui_status_<charge>` (`deflect`, `arrows`, `fate`, `venom_blade`). A blow
  RIFLESSO turns back plays `pilgrim_deflect` as it reaches him (a bolt's
  flight first); FERETRO's arrow is his attack clip, so it plays
  `pilgrim_shoot` instead of `pilgrim_attack`; a loaded bump's die plays
  `ui_fate_die` at the struck foe as it shows.
- **The rope** (Lazzo): `card_lasso` when the card is played; as its throw
  starts to show (the Lasso_Caught cue, about 1.5 s of the card's 2 s cast)
  `pilgrim_lasso_throw` at the player (the throw is his cast clip, silent of
  its own: never `pilgrim_attack`), and `world_lasso_wrap` at the foe when
  the loop reaches it (0.35 of that cue: the rope jerks taut in it as the
  card is lifted, 0.3 s later); once it spins, `world_lasso_whirr` at each
  full turn, played higher as the spin speeds up (pitch 0.85, +0.05 a turn,
  up to 1.55 at the fourteenth; up to eight a second); each hit on a foe
  `world_lasso_hit` and each smash on a wall `world_lasso_smash` (the
  Lasso_Struck cue), at the swung card; `world_lasso_release` when the rope
  lets a living foe go, as the board shows what moved the player (his dodge
  at once, a push once its blow lands), with its MOLLATO and its card's fall
  (it lands 0.28 s later). A foe that dies on the rope falls with its own
  death.
- **The rod** (Canna da Pesca), at the player: it is never played, so
  `card_fishing_rod` sounds as it is cast (the Fish_Cast cue, 0.62 s: the
  bobber lands at its end); `world_bobber_plop` as the bite's cue starts
  (the water shows) and `world_fish_bite` as the bobber dips (0.64 of that
  cue); `pilgrim_reel` as the catch's cue starts, placed so that its splash
  (0.10) is where the catch breaks the water; then `pilgrim_catch` as food
  reaches his hand (its d4 and `pilgrim_heal` follow) or `ui_fish_card` as a
  caught card reaches him. His card's clips (his cast as the rod is cast, its
  hold while the catch is reeled in) sound nothing of their own: never
  `pilgrim_attack`, `pilgrim_interact` or `pilgrim_cast`.
- **The ball** (Pinball), at the ball: `card_pinball` when the card is
  played (its foe's card starts to puff into the ball at about 0.25 of it,
  the Pinball_Made cue, and the ball drops out whole at 0.49);
  `world_pinball_launch` as the player's swing at the ball lands, when the
  cast ends (his card's swing is silent of its own: never `pilgrim_attack`);
  `world_pinball_ding` each time the ball glances off a wall, the room's
  edge, cover or an object (the Pinball_Bounced cue, at 0.8, several a second
  at most); `world_pinball_bong` each time it strikes a foe (Pinball_Bumped),
  played higher as its value climbs (pitch 0.9, +0.04 a point over the
  card's value, up to eight); `world_pinball_burst` when its twenty seconds
  end (Pinball_Burst). Its foe makes no sound of its own while it is the ball
  (no voice, no hurt, no death).
- **Behind his eyes** (First Person Shooter), at the player:
  `card_first_person` when the card is played; `pilgrim_fps_dive` as the
  camera starts diving into his eyes (the card's First_Person_Begun cue, 0.6
  s) and `pilgrim_fps_rise` as it starts rising back out when the seconds
  end (0.6 s); `pilgrim_ak_shot` at every shot the board shows (six a second
  while the trigger is held, at 0.8), `world_ak_hit` 0.04 s after a shot that
  wounds a foe (at 0.9; the struck foe's own hurt stays silent: its card
  starts no clip) and `world_ak_ricochet` 0.04 s after one stopped by stone,
  cover or an object (at 0.8).
- **The disco** (Bomb Marley), on the board: `card_bomb_marley` when the card is
  played; `world_marley_ball` as the mirror ball falls from above and
  `world_marley_lights` each time the lit tiles swap; `world_marley_warn` when a
  column is marked for a throw, `world_marley_bomb` as the bomb flies down it
  and `world_marley_blast` as it bursts; `world_marley_safe` for each character
  standing in the light that survives, `world_marley_bonus` when +5 seconds are
  earned and `world_marley_end` as the ball rises and the party ends. Under it
  all the reggae plays one beat a second (60 BPM) as the world's own beat:
  `world_marley_groove_a`, `world_marley_groove_b`, `a`, `b`, ... (one-drop:
  bass and kick, then rim and offbeat skank).
- **The flood** (Inondazione): `card_flood` when the card is played;
  `world_flood_wave` as the wave sweeps from one wall to the other,
  `world_flood_splash` at each enemy it pushes and `world_flood_steam` at each
  fire it puts out.
- **The room**: `ui_beat_tick` on every whole second of an open window,
  `ui_critical` when an action claims the beat, `ui_window_end`, `ui_stun`,
  `ui_defense_prompt`, `pilgrim_parry` on a parry or deflection that lands,
  `world_tesla_ring` when the square opens the Ring, `world_spawn` when an
  enemy arrives, `ui_defeat` after the fall; `amb_crypt_loop` under it all.
- **The cannons** (Cannone, Cannone laser): `card_cannon` / `card_laser_cannon`
  when the card is played; `world_cannon_place` as the stand lands on its cell;
  `world_cannon_fire` at each shot and `world_cannon_hit` at the foe it strikes
  (a laser's shot plays `world_laser_fire` and, at the foe, `world_cannon_hit`
  too); `world_cannon_break` when the cannon falls apart.
- **The black hole** (Buco nero): `card_black_hole` when the card is played;
  `world_black_hole_open` as the hole opens; `world_black_hole_hum` once a
  second while it is open (one beat, dry, made to be retriggered on the beat);
  `world_black_hole_pull` for each foe it drags a cell closer,
  `world_black_hole_swallow` for each foe it takes and
  `world_black_hole_close` as it collapses.
- **The dinosaurs** (Dinosauro): `card_dinosaur` when the card is played (the
  d4's rattle, then the roar sting); the mount's call at its arrival, one per
  kind (`world_dino_roar_raptor`, `_stego`, `_dilo`, `_giga`); its steps
  (`world_dino_step_small` for the raptor and the dilophosaurus, quiet and fast,
  `world_dino_step_heavy` for the stegosaurus, `world_dino_stomp` for the
  giant's crushing stomp), `world_dino_bite` at each bite and
  `world_dino_dismount` as it leaves the rider.
- **The bleed** (Sanguinamento): `ui_status_bleed` when it is applied and
  `world_bleed_tick` at the extra damage it deals each tick.

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
| pilgrim_deflect | RIFLESSO turns a blow back (as it reaches him) | 0.7 | 0.0 | -18 | 0.28 | the ward flashes at 0.0: a hard click, a bright steel ring over D5 A5 D6 that dies fast, the globe's chime, and the blow sent back: a bright whoosh leaving him and falling away (3.5 -> 0.8 kHz) |
| pilgrim_shoot | looses one of FERETRO's arrows (his attack clip) | 0.7 | 0.03, 0.125, 0.3 | -19 | 0.2 | the string drawn (a leather-and-wood creak from 0.03), released at 0.125 with the attack clip's hit (a thrummed twang on D3, the bow's dry knock, a snap), the arrow's whistling whoosh leaving him, the cloak settling at 0.30 |
| pilgrim_stunned | stunned / staggered | 1.6 | — | -24 | 0.3 | dazed: a high thin ringing with slow wobble, faint circling tinkles of the lantern; quiet, unsettling |
| pilgrim_interact | picks up loot | 0.7 | 0.28 | -22 | 0.2 | crouches (cloth) and pockets it at 0.28: coins clink into a leather pouch |
| pilgrim_heal | is healed | 0.9 | — | -21 | 0.35 | warm rising swell, soft bell partials (D, F, A), a breath of air; comforting |
| pilgrim_death | dies | 1.2 | 0.118, 0.68 | -18 | 0.3 | struck at 0.118, the card folds and topples (paper crease + slap on stone at 0.68), the lantern rolls and its glass cracks, the blue flame gutters out |
| pilgrim_shadow_sink | sinks into his shadow (Movimento Ombra) | 0.65 | 0.0, 0.27 | -21 | 0.3 | a soft inky down-swell (a dark band falling 700 -> 110 Hz, peak 0.15) as the card goes down, the card folding under it (a cardboard creak and crease crackles, muffled as through ink), flat at 0.27 with a soft low gulp; a faint muffled chime of the lantern globe |
| pilgrim_shadow_step | one step of the shadow (one every 0.4 s at most) | 0.35 | 0.0, 0.07 | -24 | 0.2 | very short, soft, airy, ink-like: a dark swish slipping one cell, no attack, peak 0.07 where the pool glides fastest; no boots, no card scrape; must not tire |
| pilgrim_shadow_rise | rises out of his shadow (the world resumes) | 0.8 | 0.0, 0.13, 0.34 | -20 | 0.3 | an inky up-swell (120 -> 900 Hz, peak 0.12), the card unfolding as it comes out of the floor at 0.13 (a flex creak, crisp paper grains, a spring), a light thud of the card set down on stone at 0.34 (its iron base knocks, the lantern jingles), the cloak settles |
| pilgrim_lasso_throw | throws the Lazzo (its throw starts to show) | 0.62 | 0.0, 0.04, 0.53 | -19 | 0.22 | the loop let go in a full round whoosh peaking at 0.04 (the cloak flicks, the lantern knocks once), then the rope paying out through his glove (a fibrous hemp rasp, fast, then slowing) under the loop's own whistle falling away (doppler down, darker), until it drops over the foe at 0.53 |
| pilgrim_reel | reels in the Canna da Pesca's catch | 0.7 | 0.0, 0.1, 0.45 | -20 | 0.22 | the reel cranked hard (its pawl clicking about 26 a second over the gears' dry whirr, to 0.45), the cane creaking under the load; the catch breaks the water at 0.10 (a heavy wet burst, drops raining back to 0.5), the taut line singing thin |
| pilgrim_catch | the rod's food reaches his hand | 0.45 | 0.0 | -21 | 0.2 | a soft wet slap on the leather glove at 0.0 (a muffled body under a little splat), a few drops falling off onto the stone, the cloak settling |
| pilgrim_fps_dive | the camera dives into his eyes (First Person Shooter) | 0.85 | 0.0, 0.45, 0.6 | -20 | 0.25 | the room rushing in (air through a band rising 250 Hz -> 1.6 kHz, swelling to 0.45) over a low glide D2 -> D3, his hood brushing past it (wool from 0.38) and closing round the view at 0.6 with a soft muffled thump, the lantern's globe chiming faintly |
| pilgrim_fps_rise | the camera rises back out of his eyes | 0.8 | 0.0, 0.2, 0.6 | -21 | 0.25 | the hood falling open (wool to 0.15), the room drawing away (a band falling 1.4 kHz -> 260 Hz, swelling to 0.2, gone by 0.6) over a low glide D3 -> D2, the board's view settling at 0.6 with a faint low breath of air |
| pilgrim_ak_shot | one shot of his paper AK (six a second at most) | 0.22 | 0.0, 0.022 | -20 | 0.14 (rt60 1.0) | short, dry and never harsh: the muzzle's crack at 0.0 (a broadband blast with a sharp front and a short dark boom), the rifle's paper snapping with it, the bolt cycling at 0.022 (a short steel clack); no casing, no tail |

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
| card_deflect | Deflect: RIFLESSO, the next blow goes back | the buckler snapped up (an airy rise), its iron set at 0.12 (a clank, a steel shimmer on A5), then the glance at 0.27: a crisp D6 ping and a bright whoosh turning away and falling |
| card_coffin | Feretro: three arrows | a coffin lid creaks open (0.06), drops on its hinge with a hollow knock (0.30), three arrows drawn out of it (0.42, 0.50, 0.58: a shaft's knock, an iron head's tick, a fletching's hiss) |
| card_fate_dice | Dado del Destino: three bumps that roll its die | one bone die rolled across wood (0.05 to 0.27), then fate sealed at 0.34: a low D bell struck softly, a crystal shimmer (A6) over it |
| card_venom_blade | Lama Velenosa: its die is the bumps it poisons | a dagger drawn from its sheath (a bright scrape from 0.07, the blade ringing on D6), a drop of venom at 0.26 (a tight plip and a sizzle), two small bubbles |
| card_lasso | Lazzo: a foe caught, lifted and swung round him | the coil of hemp shaken loose off his shoulder (a fibrous rasp from 0.03, the coils slapping softly at 0.04 and 0.09), the loop opened with a creak of its knot at 0.16, then whirled once overhead: a round swish peaking at 0.22 (240 -> 760 Hz, the rope's thin whistle riding it), handing on to the throw |
| card_fishing_rod | Canna da Pesca: never played, heard as it is cast | the rod drawn back over his shoulder (a dry creak of the cane, a soft swish, 0.04-0.19), whipped forward (a thin fast swish peaking at 0.27, its tip whistling), the line let go at 0.32: the reel's pawl spinning out (a purring click train slowing from 70 to 20 a second) and the line hissing off the spool until the bobber is down (0.62) |
| card_pinball | Pinball: a foe beside him made into a steel ball and struck away | a plunger drawn back from 0.04 (its rod rasping, the coil spring zinging higher as it stretches, the ratchet clicking ever faster) and caught at full draw at 0.2 (a click, the spring's short boing on D4); as the foe's card starts to puff (0.25) it is balled up like paper and squeezed shut, and the ball drops out whole at 0.49 (a solid steel tink, a soft puff of paper dust) |
| card_first_person | First Person Shooter: twenty seconds behind his eyes with a paper AK | the AK readied: the banana magazine seated at 0.05 (a hollow steel clack, its rattle), the charging handle hauled back at 0.13 (a dry scrape, the bolt's spring) and let fly at 0.19 (the bolt slams home); the dive (`pilgrim_fps_dive`) follows from about 0.27 |

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
| card_poison_pool | Pozza di Veleno: a pool of poison on a cell | a vial uncorked (the cork's pop), the poison glugging out in its flight, its splash on the stone at 0.38, the pool bubbling slower and slower |
| card_wildfire | Incendio: a fire that grows as a plus | flint struck on steel twice (0.07, 0.15: a steel ping, a spray of sparks), the floor catches with a soft whoomp (0.22), a crackle that spreads |

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
| world_fire_spread | the floor's fires grow at a new window | 0.9 | -20 | 0.3 | a rush of flame swelling to 0.15, crackle running along it, dying by 0.8 |
| world_fire_out | a floor fire goes out at its fifth window | 0.85 | -22 | 0.3 | the flames gutter and sink (the bed darkening, its crackle thinning, to 0.45), a last ember pops at 0.38, smoke hisses away with a soft puff from 0.32 |
| world_pool_splash | an enemy steps into a pool of poison (and a pool lands) | 0.55 | -20 | 0.25 | a wet slap at 0.0, the pool sucking at the card's base (0.02-0.16), a few thick bubbles breaking to 0.45 |
| world_ice_crack | an ice block cracks | 0.8 | -19 | 0.3 | ice fractures: sharp glassy cracks, creak |
| world_bomb_fizzle | a bomb is disarmed | 0.7 | -21 | 0.2 | the fuse is pinched out: a hiss that dies, a little puff |
| world_object_hit | a device or object is struck | 0.5 | -19 | 0.22 | wood-and-iron knock |
| world_spawn | an enemy arrives in the lab | 1.2 | -21 | 0.4 | a card set down on stone at once (the game hears an arrival only when the enemy already stands there), a dust puff, and the dark it came from swelling behind it and sinking back |
| world_lasso_wrap | the Lazzo's loop reaches the foe | 0.65 | -20 | 0.25 | the loop drops over the card at 0.0 (a soft slap of rope on paper), runs tight through its knot (a rising fibrous zip, 700 Hz -> 2.6 kHz, to 0.12), cinches with a creak of hemp and the card's paper squeezed, and jerks taut at 0.3 as the card is lifted (a dull thrum on D2, the knock of its base leaving the stone) |
| world_lasso_whirr | each full turn of the swung foe (pitched up with the speed) | 0.32 | -24 | 0.15 (rt60 1.0) | a round swish swelling to 0.07 and falling away by 0.3 (a band 380 -> 1250 -> 420 Hz, a dark rope hum under it), the card's paper fluttering in the wind; quiet and dry: it comes back up to eight times a second |
| world_lasso_hit | the swung foe strikes another | 0.5 | -19 | 0.25 | two cardboard bodies slammed together at 0.0 (a heavy flam, 6 ms), a body thud under them, their iron bases knocking, the paper crumpling to 0.09, the rope jolted (a dull thrum on A2) |
| world_lasso_smash | the swung foe smashes into a wall | 0.8 | -16 | 0.35 | the card smashed into stone at 0.0: a heavy stone thud and chunk, its paper crushed, its iron base clanking, grit and pebbles falling to 0.6, a puff of dust from 0.02, the rope jolted |
| world_lasso_release | the rope lets a living foe go | 0.6 | -21 | 0.25 | the tension let go in a soft falling swish of hemp (1.5 kHz -> 400 Hz), loose coils flopping (0.05, 0.12); the card lands back on the stone at 0.28 (a cardboard thump, its iron base, a short scrape, dust) |
| world_bobber_plop | the rod's bobber lands (the water shows) | 0.5 | -22 | 0.25 | a small round plop at 0.0 (a bubble ringing up from 480 Hz), a light slap of water, fine drops falling back to 0.2, the ripples lapping softly away |
| world_fish_bite | a fish takes the bait (the bobber dips) | 0.6 | -19 | 0.25 | the bobber yanked under at 0.0 (a deep gulp ringing up from 240 Hz, a smaller one after), a splash thrown up with drops raining back to 0.35, the taut line plucked high (A5), the rod's tip bending with a short creak |
| world_pinball_launch | the player's swing strikes the Pinball's ball away | 0.6 | -16 | 0.3 | a hard thwack at 0.0 (iron on steel: a sharp click, a heavy body thud, the ball ringing D5-A5, the lantern's frame clanking under it), the ball shot away in a bright whoosh falling 1.9 kHz -> 600 Hz to 0.4, a soft paper flutter in its wake |
| world_pinball_ding | the ball glances off a wall or a solid thing | 0.3 | -22 | 0.2 | very short and dry: a small hard tock of steel on stone at 0.0, the ball's bright tick, a short ring on A6 dying by 0.2, a pinch of grit; it comes back several times a second |
| world_pinball_bong | the ball strikes a foe (a pop bumper) | 0.6 | -18 | 0.25 | a hollow bong at 0.0 (a round tone on A3 dropping a little, its box), the foe's card smacked (a dry paper slap and crumple to 0.06), its iron base knocking, a bright bumper chime (D6 over A5) ringing to 0.45; played higher as the value climbs |
| world_pinball_burst | the ball bursts at the end of its twenty seconds | 0.9 | -15 | 0.35 | a paper balloon popping at 0.0 (a sharp paper crack over a low thump), shreds and confetti fluttering down 0.01-0.7 (paper grains thinning out), a soft puff of paper dust, a last small steel clink at 0.55 |
| world_ak_hit | a round of the AK wounds a foe | 0.25 | -20 | 0.2 | the foe's paper card punched through at 0.0 (a crisp tear 2-6 kHz, 10 ms), a muffled body thud under it (80-250 Hz), a few crinkles to 0.05; short, up to six a second |
| world_ak_ricochet | a round stops on stone, cover or an object | 0.5 | -21 | 0.3 | a hard chip of stone at 0.0 (a crack, a chunk, grit flying), the round whining away from 0.03 (a thin tone falling 3.2 -> 1.3 kHz with a little wobble, fading by 0.4) |

### Family `marley` — Bomb Marley and Inondazione

Module `sfx_marley.py` (it reuses the `world` family's water, blast and stone
materials). Mirror-ball sounds are glints (tiny pings on D5-D8 of D Phrygian
with a tick of noise each) and detuned shimmers; the reggae is in D minor
seventh at **60 BPM**: a drawbar organ (with a Leslie wobble), a round bass on
D2, a soft kick, a rim click and a muted guitar-and-organ skank with dub echoes.
Length is the recipe's (the build's hall adds a tail: the built length is in
brackets; every sound stays under 3.5 s).

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| card_bomb_marley | Bomb Marley is played | 2.0 (1.9) | 0.0, 0.8, 0.95, 1.1 | -19 | 0.3 (rt60 1.2) | a paper flick, a low fuse spitting while a mirror ball's glints climb D5 -> D8 over a high shimmer, then a reggae organ bubbles twice (0.8, 0.95: short D minor seventh stabs over a round bass) and holds the chord at 1.1 with its Leslie wobble |
| card_flood | Inondazione is played | 1.4 (1.6) | 0.0, 0.7 | -19 | 0.25 (rt60 0.9) | a paper flick, a surge of water rising (a wide band 200 -> 2.4 kHz over a swelling low rumble, bubbles ringing up through it), cresting and crashing at 0.7 (foam falling 6 -> 1.5 kHz) and draining away in froth and drops |
| world_marley_ball | the mirror ball falls | 1.75 (2.2) | 0.0, 1.5 | -21 | 0.3 (rt60 1.0) | a shimmer gliding down D7 -> D5 as the ball comes down its chain, tiny metal ticks of the winch slowing from 14 to 3 a second, a soft wind falling, glints scattered over it; at 1.5 the ball hangs: a lightly struck D6 chime |
| world_marley_warn | a column is warned | 0.25 (0.36) | 0.0, 0.11 | -23 | 0.1 (rt60 0.5) | a short, dry two-tone tick: two woodblock knocks, A5 then D6 (rising) |
| world_marley_bomb | a bomb is thrown down a column | 0.9 (1.2) | 0.0, 0.62 | -19 | 0.2 (rt60 0.8) | a falling whistle (2.8 kHz -> 700 Hz, swelling, a little air and fuse fizz), then at 0.62 the landing: a dull iron-and-stone thud, a short rattle of grit |
| world_marley_blast | a bomb bursts | 1.5 (1.45) | 0.004, 0.06 | -13 | 0.35 (rt60 1.1) | a heavy blast (pressure front, falling boom, stone shatter, debris to 1.3) and in it a dub bass drop: a round sine diving from 200 Hz to D2 at 0.06 and ringing on, an octave of sub under it |
| world_marley_safe | a character in the light survives | 0.45 (0.53) | 0.0, 0.045 | -22 | 0.25 (rt60 0.8) | a bright soft chime: a glockenspiel D6 with A6 a breath later, a few glints |
| world_marley_lights | the lit tiles swap | 0.65 (0.9) | 0.0, 0.5 | -22 | 0.25 (rt60 0.8) | a sparkle sweep: glints rising D5 -> D8 over a thin band sliding 2.5 -> 10 kHz, a tiny ping at 0.5 |
| world_marley_bonus | +5 seconds earned | 0.4 (0.4) | 0.0, 0.075 | -21 | 0.15 (rt60 0.6) | a coin-like ding: two bright metal strikes a fifth apart (D6, A6) |
| world_marley_end | the ball rises, the party ends | 1.3 (1.5) | 0.0, 0.18, 0.95 | -20 | 0.3 (rt60 1.0) | the ball hauled up (a soft up-swish, chain ticks) as a descending sparkle falls over a D minor chord that slows like a stopped record (speed 1 -> 0 from 0.18 to 0.93, darkening, a few crackles), a last low thump at 0.95 |
| world_marley_groove_a | beat A of the groove (every other second) | 1.0 (1.03) | 0.0, 0.72 | -22 | 0.1 (rt60 0.5) | one beat at 60 BPM: a deep round bass note on D2 with a soft kick under it on the beat, ringing on, and a quiet A2 pickup at 0.72 |
| world_marley_groove_b | beat B of the groove | 1.0 (1.07) | 0.0, 0.5, 0.73 | -23 | 0.12 (rt60 0.3) | one beat: a dry rim click on the beat, the offbeat skank at 0.5 (a muted guitar chop over an organ chop and the pick's chk), its dub echoes falling away at 0.73 and 0.96; a, b, a, b is one-drop |
| world_flood_wave | the wave sweeps the room | 2.3 (3.2) | 0.0, 1.25 | -16 | 0.25 (rt60 0.8) | a long swell of filtered noise (pink through a wide band 180 -> 700 -> 260 Hz, a low brown roll, a foam hiss 2.5 -> 5.5 -> 2.5 kHz) breathing slowly, cresting at 1.25, bubbles and drops in its wake |
| world_flood_splash | the wave hits an enemy | 0.55 (0.77) | 0.0 | -19 | 0.2 (rt60 0.8) | a heavy wet slap (a band falling 6 -> 1.4 kHz, a low whump under it, the soaked card's paper flap), bubbles bursting and a rain of drops |
| world_flood_steam | a fire is put out | 0.75 (0.94) | 0.0, 0.03 | -21 | 0.2 (rt60 0.8) | water on embers: a wet gulp, a dense sizzle thinning out, then a long turbulent hiss of steam (7 -> 3 kHz) fading with a soft puff |

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
| ui_status_deflect | RIFLESSO loaded | 0.5 | -23 | 0.3 | a polished buckler catches the light: two crystal glints (D6, A6) over the ward's thin open fifth |
| ui_status_arrows | FRECCE loaded | 0.45 | -22 | 0.2 | three arrows slid into a quiver: fletching swishes, the shafts' hardwood knocks, iron ticks |
| ui_status_fate | DESTINO loaded | 0.6 | -23 | 0.3 | a bone die ticks twice in the hand, a low D bell of fate touched under a slow violet shimmer (A5/D6) |
| ui_status_venom_blade | LAMA loaded | 0.5 | -22 | 0.2 | a blade's thin ting (Eb6), a drop of venom and two small bubbles over a sickly fall A5 -> Eb5 |
| ui_fate_die | the Dado del Destino's die at a bump | 0.4 | -22 | 0.25 | a bone die bouncing on stone, each bounce lower, landing with a soft D6 ping |
| ui_status_expired | a status wears off | 0.4 | -28 | 0.2 | a soft fading puff |
| ui_fish_card | a card caught by the Canna da Pesca reaches him (CARTA PESCATA) | 0.9 | -20 | 0.35 | the wet card shaken twice in the air (dull paper flaps at 0.0 and 0.08, drops flung off it), then the find: crystal A5, D6 and A6 rising (0.12, 0.18, 0.25) over a warm D5 and A4, a few sparkles |
| ui_defeat | the Viandante falls (defeat) | 2.0 | -18 | 0.5 | a low drone sinks, paper crumples, a distant bell |

### Family `arsenal` — the cannons, the black hole, the dinosaurs, the bleed

Module `sfx_arsenal.py` (it reuses the `world` family's iron, stone, blast and
fuse materials and the `cards_arms` family's paper flick and bone dice). The
dinosaurs' voices are a glottal source (harmonics of a moving f0, a jitter and a
growl of 20-70 Hz amplitude modulation) through two sets of formants crossfaded
as the mouth opens: high and bright for the raptor (900-1700 Hz, formants at 2.2
and 3.6 kHz), mid for the stegosaurus (120-210 Hz), noise and clicks for the
dilophosaurus, 85 -> 44 Hz and mostly chest for the giant. The black hole is a
Shepard spiral (four voices an octave apart that seem to climb, or fall, forever)
over a D2 sub and a wheeling band of noise; the laser's whine climbs D3 -> D7. No
voices of people, no words. Length is the recipe's; the built length (the hall's
tail added) is in brackets and stays inside the 0.1-3.5 s the bank test allows.

| name | when | length | marks | loud | wet | what |
|---|---|---|---|---|---|---|
| card_cannon | Cannone is played | 1.3 (1.39) | 0.0, 0.18, 0.32, 0.5 | -19 | 0.25 (rt60 1.0) | a paper flick, the cannon set on its stand: a heavy iron clunk at 0.18 (deep thud, low iron modes, a stone chunk), the barrel seated in its cradle at 0.32 (wood and iron knock), a flint struck at 0.5 and the fuse lit, hissing and spitting to 1.25 |
| card_laser_cannon | Cannone laser is played | 1.5 (1.73) | 0.0, 0.16, 1.0, 1.05 | -19 | 0.2 (rt60 0.8) | a paper flick, the emitter seated with a steel clank at 0.16, the charge-up from 0.28 (a whine climbing D3 -> D7 with an FM shimmer, the A2 hum swelling, sparks thickening), a bright lock at 1.0 (a click, D6 and A6 chimes) and a held high hum |
| card_black_hole | Buco nero is played | 1.65 (2.32) | 0.0, 0.5, 0.95, 1.15 | -19 | 0.15 (rt60 0.6) | a paper flick, the void swelling (a D2 sub, a dark rumble) under a spiral of voices rising forever and a band of noise wheeling, everything drawn inward from 0.95 (a suction falling 3 kHz -> 200 Hz) to a deep soft thump at 1.15 and a breath of the void |
| card_dinosaur | Dinosauro is played | 1.75 (2.07) | 0.0, 0.05, 0.5, 0.68 | -19 | 0.25 (rt60 0.9) | a paper flick, a bone d4 rattled in a cupped hand (four shakes, settling in ticks at 0.5), then a roar sting at 0.68: a deep growl rising into a bellow with a sub of the chest under it |
| world_cannon_place | the stand lands on its cell | 0.5 (0.63) | 0.0 | -19 | 0.25 (rt60 0.9) | a heavy thud (68 Hz falling), the stand's iron ringing low and short, a stone chunk, a puff of dust |
| world_cannon_fire | a cannon fires | 1.0 (0.81) | 0.0, 0.3, 0.55 | -18 | 0.3 (rt60 0.9) | a hard pressure front, a falling boom (110 -> 44 Hz), the barrel ringing, a flame's whoof, a puff of smoke; its echo comes back off the walls at 0.3 and again, fainter and darker, at 0.55 |
| world_cannon_hit | the ball (or a laser's shot) strikes a foe | 0.4 (0.37) | 0.0 | -19 | 0.2 (rt60 0.6) | a dull crack (a hard click and a short wooden snap), a heavy muffled thud under it, the card crumpled for a few grains |
| world_cannon_break | the cannon falls apart | 1.1 (1.06) | 0.0, 0.12, 0.34, 0.52 | -16 | 0.3 (rt60 0.9) | a sharp crack of overstrained iron, its bands springing off in pings, the barrel tumbling in heavy clanks at 0.12, 0.34 and 0.52 (each lower and softer), the stand crumbling in stone chunks and gravel |
| world_laser_fire | a laser fires | 0.5 (0.77) | 0.0, 0.1 | -17 | 0.2 (rt60 0.7) | a hard electric crack and a pew falling 5.2 kHz -> 400 Hz in 0.28 s (an FM shimmer on it), a bright beam buzz (the A2 hum with corona and crackle) held to 0.3 |
| world_black_hole_open | the hole opens | 1.05 (1.72) | 0.0, 0.3, 0.6, 0.85 | -18 | 0.15 (rt60 0.6) | the floor tears (a ripping crackle falling 6 kHz -> 800 Hz), the void swelling (D2 sub, rumble) with a spiral of voices rising round it and a wheeling band of noise, a low settling hum at 0.85 |
| world_black_hole_hum | each second the hole is open | 1.0 (1.0) | 0.0, 0.5 | -24 | 0.02 (rt60 0.3) | one beat, exactly a second and dry so beats do not smear: a sub-bass D2 falling a little with its second harmonic, a slow rumble and a whoosh of suction (a band 280 -> 1300 -> 320 Hz), swelling from silence to a crest at 0.5 and sinking to silence |
| world_black_hole_pull | a foe is dragged a cell closer | 0.38 (0.55) | 0.0, 0.22 | -21 | 0.15 (rt60 0.5) | a suction rising (a band 300 -> 2500 Hz), the card scraping on stone, a small low tug at 0.22 |
| world_black_hole_swallow | a foe is taken | 0.62 (0.77) | 0.0, 0.3 | -19 | 0.2 (rt60 0.6) | an inward whoosh (a band falling 2.4 kHz -> 200 Hz) and at 0.3 a pop (a bubble's plop falling 700 -> 90 Hz) with a soft low thump and a faint ring of the void |
| world_black_hole_close | the hole collapses | 0.95 (1.22) | 0.0, 0.38, 0.6 | -18 | 0.25 (rt60 0.8) | the spiral falling back down over a sinking sub, everything rushing into a point (a suction band falling 3.5 kHz -> 150 Hz), a sharp pop at 0.6 (a click and a dive 1.1 kHz -> 150 Hz), a thin glassy ping |
| world_dino_roar_raptor | the raptor arrives / calls | 0.6 (0.87) | 0.0, 0.07 | -17 | 0.2 (rt60 0.6) | a short high screech: f0 900 -> 1700 Hz in 0.1 s then falling to 780, a fast vibrato, bright formants (2.2, 3.6 kHz), a raspy growl, breath |
| world_dino_roar_stego | the stegosaurus calls | 0.9 (1.19) | 0.0, 0.17 | -17 | 0.22 (rt60 0.7) | a mid grunting bellow: a short grunt at 0.0 (120 -> 150 -> 95 Hz) and a longer bellow at 0.17 (140 -> 210 -> 108 Hz, a slow 24 Hz growl, mouth opening and closing), a chesty body |
| world_dino_roar_dilo | the dilophosaurus calls | 0.7 (0.9) | 0.0, 0.05, 0.26 | -19 | 0.2 (rt60 0.6) | a hissing chirp-rattle: a hiss (3-9 kHz), a chirp gliding 1.6 -> 3.4 kHz with an FM warble at 0.05, the frill's rattle at 0.26 (26 clicks a second through a 1.4 kHz resonance), a trailing hiss |
| world_dino_roar_giga | the giant calls | 1.5 (2.28) | 0.0, 0.07, 0.62 | -14 | 0.2 (rt60 0.7) | a huge deep roar: f0 85 -> 125 -> 44 Hz, a 38 -> 24 Hz growl tearing at it, low formants (250, 700, 1.4 kHz), a chest sub and a brown rumble under it, sinking away |
| world_dino_step_small | a raptor or dilophosaurus steps | 0.2 (0.27) | 0.0, 0.065, 0.1, 0.165 | -26 | 0.05 (rt60 0.3) | a light fast pitter-patter: six dry claw ticks (2.5-5 kHz) in two runs of three over a tiny pad; quiet, it must not tire |
| world_dino_step_heavy | the stegosaurus steps | 0.5 (0.57) | 0.0 | -19 | 0.25 (rt60 0.8) | a heavy stomp: a deep thud (58 Hz falling), a stone chunk, a drag of claws settling, a puff of dust |
| world_dino_stomp | the giant's crushing stomp | 0.55 (0.84) | 0.0, 0.05, 0.2 | -20 | 0.1 (rt60 0.25) | a pressure thump, a deep boom (84 -> 36 Hz), the stone shattering under the foot, the ground shaking to 0.4, grit and pebbles falling |
| world_dino_bite | the dinosaur bites | 0.4 (0.65) | 0.0, 0.03, 0.09 | -17 | 0.2 (rt60 0.6) | the jaws slam shut (a bone-on-bone clack and a wet smack), the bones crunching 0.03-0.2, a low chomp at 0.09 and a short growl in the throat |
| world_dino_dismount | the dinosaur leaves the rider | 0.65 (0.88) | 0.0, 0.05, 0.15 | -20 | 0.3 (rt60 0.8) | a puff of smoke and paper at 0.0, a soft low thump, and its call fading away (a bellow falling 190 -> 90 Hz, darkening as it goes) |
| ui_status_bleed | a bleed is applied (Sanguinamento) | 0.3 (0.5) | 0.0, 0.04, 0.18 | -22 | 0.15 (rt60 0.5) | a thin wet slice (a band sliding 7.5 -> 2.5 kHz), a drop of blood plipping at 0.04 and a smaller one at 0.18 with a wet cling |
| world_bleed_tick | the bleed's extra damage | 0.2 (0.38) | 0.0, 0.02 | -21 | 0.15 (rt60 0.5) | a sharper wet slash (a hard bright cut 2.5-9 kHz sliding down), a squelch of the wound under it at 0.02, two drops falling |

### Family `ambience` — the room

| name | when | length | loud | wet | what |
|---|---|---|---|---|---|
| amb_crypt_loop | always, under everything (loop=True) | 24.0 exact | -34 | 0.25 | a seamless loop: a low wind through stone halls, sparse water drips far away, a torch's soft crackle, rare chain creaks; the end must flow into the start |
