# Gothic visual assets

Generated with the built-in imagegen tool for this project, except the card atlas's hand-made fifth and sixth rows (below). Source PNGs retain transparent alpha. The renderer samples the figure sheet as a 4×4 atlas and the card sheet as four columns by six rows, with nearest-neighbour filtering; the latest figure sheet has explicit region boundaries documented below. The user's references establish the palette and layout; screenshots are not substituted for gameplay.

## Coarse pixel card atlas revision — 2026-10-09

Saved output: `assets/gothic/card-icons-pixel.png` (the atlas embedded by the current renderer).
Mode: built-in imagegen edit, transparent background, using `assets/gothic/card-icons.png` as the reference. The original is preserved for comparison. Character sprites retain the existing figure atlas; environmental props in M7 are now procedural 3D blocks.

Exact edit prompt:

Edit this game icon atlas. Keep EXACTLY the same 16 subjects in exactly the same 4x4 row-major order, one centered isolated icon per equal cell, transparent background. Repaint EVERYTHING in genuinely coarse low-resolution pixel art, like a hand drawn 24x24-pixel icon enlarged with nearest neighbour. Each complete icon must have no more than 24 to 28 square pixel units across its silhouette. Huge crisp square pixel clusters, only 4 to 6 flat colors per icon, thick stair-step near-black outlines, extremely simplified shapes, no fine texture, no tiny strokes, no dithering, no gradients, no soft light, no antialiasing. For example the sword should have a blade just 3 pixels wide, the shield should have a simple 3-pixel cross and a few broad red blocks, the green poison skull should have 2 large black eye holes and a simple cloud silhouette. Keep dark fantasy palette: ivory bone, charcoal, crimson, moss green, muted violet, ochre, dull steel. Remove ornamental detail so these read perfectly at 28 pixels. Preserve the subject order: row1 sword/shield/green poison/skel hand pushing arrow; row2 violet lightning/dashing hooded silhouette/firebomb/thorn armor; row3 eye rune/book/anvil spark/hook; row4 hammer/two dice/chain lightning/cleansing shield. Strict 4x4 uniform layout. Leave at least 16% transparent padding in each cell. No text, borders or grid. The visual priority is big obvious square pixels and simple bold silhouettes, NOT detailed illustration.

## Card atlas prompt

Use case: stylized-concept. Asset type: production pixel-art game ICON ATLAS, not a mockup.
Create one square 1024x1024 transparent PNG containing exactly 16 isolated dark-fantasy spell/item illustrations in a strict 4 by 4 grid of equal 256x256 cells. Each icon is centered within its cell with at least 28 px transparent margin. All icons at the same apparent scale, chunky hand-drawn pixel art, about 48x48 logical pixels per icon enlarged with hard square pixels, NO antialiasing, NO text, NO numbers, NO labels, NO borders, NO cards, NO background, NO drop shadows outside cells.
Style: sinister medieval dark fantasy, worn ivory bone and steel, deep charcoal outlines, blood-red details, muted moss green poison, dusty violet lightning, ochre gold. Like ornate inventory art in a pixelated gothic dungeon card game, clear expressive silhouettes and restrained 5-tone pixel clusters. Transparent empty background is essential.
Exact grid order, left to right:
Row 1: chipped steel sword slashing; battered iron shield with torn red cloth; swirling green toxic skull-shaped cloud; skeletal hand pushing a golden arrow.
Row 2: forked jagged violet lightning bolt; black hooded rogue dashing right with blue-gray afterimages; red-orange flaming iron bomb; thorny crimson vine curling around armor.
Row 3: occult eye inside an ivory diamond rune; open ancient spellbook with red ribbon; blacksmith anvil forging a golden magical spark; hooked iron chain curling upward.
Row 4: massive brutal stone warhammer; two ivory six-sided dice with black pips; purple chain lightning linking three tiny sparks; pale blue cleansing flame around a small shield.
No scenery or UI. Keep each icon isolated in its exact cell.

## Figure atlas prompt

Use case: stylized-concept. Asset type: production dark-fantasy pixel-art CHARACTER AND PROP ATLAS.
Create one square transparent PNG with exactly 16 isolated sprites in a precise 4x4 grid, each equal square cell 25% of canvas width and height. NO visible grid. Each subject centered, wholly contained within its own cell with 18% transparent margin on all four sides, feet/base aligned at 82% of cell height. No text, UI, labels, numbers, backgrounds or cast shadows outside the subject. Each sprite roughly 40x52 logical pixels rendered as hard-edged chunky square pixel clusters; no smooth gradients or antialiasing. Front-facing, slight three-quarter overhead dungeon game view. Detailed but immediately readable at 48px tall. Palette near black, bone ivory, blood crimson, dirty gray, with minimal gold. Sinister medieval tower ruled by a corrupted wizard. Strong silhouettes like tiny tabletop dark fantasy figures. True transparent alpha background.
Exact cell order left to right:
Row 1: player pilgrim in an ivory hooded cloak, shadow-black face with two tiny eyes, black tunic with crimson cross; hunched crimson ghoul with long arms; crimson hooded mage holding thin staff with red glowing orb; bulky black-red armored undead brute with ivory skull.
Row 2: ragged red bomber carrying round iron bomb; black-robed crimson-trimmed guardian bishop with bone staff; corrupted archmage boss in black robes, red stole, ivory broken halo behind head and staff; pointed gothic ivory stone doorway, black empty inside.
Row 3: cracked pale icy-blue crystal block; small crimson-orange flame with blackened coals; weathered dark oak barrel with iron bands and red occult rune; small spherical black iron bomb with short lit fuse.
Row 4: same ivory pilgrim casting with one raised arm and small red glyph; same ivory pilgrim recoiling, cloak flared; gothic dark wood treasure chest with ivory metal trim; low stone altar with a single red crystal.
Keep consistent pixel scale, isolated silhouettes, transparent gaps, exactly 4 columns and 4 rows.

## Gothic diorama figure revision — 2026-10-09

Saved output: `assets/gothic/figures-v2.png` (1254×1254 RGBA, embedded by the current renderer). The original `figures.png` remains unchanged.

Method: two built-in imagegen edits with transparent backgrounds. The first uses `assets/gothic/figures.png`; the second uses the first generated result. The original generated files remain in the imagegen output directory. No bitmap post-processing was applied. Because the generated gutters are uneven, the renderer uses explicit atlas region boundaries before cropping each alpha silhouette: columns `[0, 320, 640, 940, 1254]`, rows `[0, 350, 675, 923, 1254]`. All sixteen regions were checked for transparent separation. Nearest-neighbour sampling and custom sprite overrides remain supported. Environmental props are still 3D meshes.

### Exact first edit prompt

Use case: style-transfer.
Asset type: production dark fantasy pixel-art character atlas for an actual 3D dungeon game.
Edit target: the supplied transparent 4x4 atlas. Repaint the sprites as a cohesive premium pixel-art cast, retaining EXACTLY 16 equal grid cells, their row-major subjects and transparent background. Keep the pilgrim recognizable, but give every archetype a stronger distinct silhouette and cleaner, larger pixel clusters. Each sprite should read as roughly 48x64 logical pixels, hard square edges, 6-8 deliberate flat tones, no soft antialiasing or photoreal detail. More character and expressive pose, not extra tiny texture. Front three-quarter view from slightly above, matching a tabletop dungeon. Consistent cool steel-blue rim light top-left and strong charcoal outline, ivory bone, desaturated crimson cloth, small icy cyan lights. No background, text, frames, grid, shadow disks or loose particles between cells. Every sprite wholly inside its equal cell with 14% transparent margin; feet at 84% of cell height.

Exact grid subjects, left to right:
Row1: same ivory hooded pilgrim, dark void face, tiny pale blue eyes, blue-gray tunic, crimson belt seal, small silver lantern in one hand; hunched crimson ghoul with ivory skull face and long claw arms; ragged crimson-hooded skeletal ARCHER carrying a clearly visible large bone crossbow (replace the ambiguous caster silhouette); towering broad black-steel undead BRUTE with massive ivory shoulder plates and a blunt cleaver.
Row2: bent hooded BOMBER holding a round black iron bomb with small golden fuse and two bomb satchels; tall gaunt CUSTODIAN bishop in black robes, ivory mitre and cyan crystal staff; imposing corrupted archmage boss with broken ivory halo, black/crimson cape and deep red staff; carved blue-black gothic doorway with ivory trim.
Row3: fractured pale-blue ice block; compact crimson/gold fire; dark oak barrel with blue-steel hoops and red seal; black iron bomb with small hot fuse.
Row4: THE SAME ivory pilgrim casting, raised hand with compact cyan diamond rune; THE SAME pilgrim recoiling, cloak flaring sideways; black wooden treasure chest with ivory metal ribs and one gold lock; dark sculpted altar with floating crimson crystal.
Keep these EXACT cell identities because code directly indexes them. Premium handcrafted pixel art, powerful silhouettes, consistent scale, genuinely transparent alpha.

### Exact spacing edit prompt

Correct this sprite atlas for game-engine use. Preserve all sixteen identities, designs, colors, transparent background, detailed pixel art and their current order. This is an exact uniform 4 by 4 grid. Every sprite MUST be entirely isolated inside its own equal rectangular cell; make ALL sprites about 22% smaller so no pixels touch or cross any cell border. Each cell must have at least 12% completely transparent padding on all four sides, including magic and flames. Align the feet/bottom of every sprite to 85% of its own cell height. Precisely equal row heights and column widths. In particular the fourth row casting rune must be wholly inside row four and must never touch the ice block in row three. The first-row brute and ghoul must never cross into the second row. No labels, no borders, no gridlines, no background, true alpha. Crisp nearest-neighbor pixel clusters. Do not add new objects or change characters. Sprite positions: row 1 pilgrim, red ghoul, red crossbow archer, armored brute; row 2 bomber, bishop, lich, door; row 3 ice, fire, barrel, bomb; row 4 casting pilgrim, recoiling pilgrim, chest, altar.

## Hand-made card icon row — 2026-10-14

Saved output: `assets/gothic/card-icons-pixel.png`, grown from 1254×1254 to 1254×1881: a fifth and a sixth row of the same cells under the 16 painted icons. Cell 16 is Movimento Ombra (`gothic_card_icon(.Shadow_Step)`), cell 17 Pozza di Veleno (`.Poison_Pool`), cell 18 Incendio (`.Wildfire`), cell 19 Deflect (`.Deflect`), cell 20 Feretro (`.Coffin`), cell 21 Dado del Destino (`.Fate_Dice`), cell 22 Lama Velenosa (`.Venom_Blade`); cell 23 is empty. Every added icon is centred on the fifth row's 314-pixel pitch, so the sixth row left the fifth row's icons on the same pixels.

Method: no image generation. `tools/art/build_card_icons.py` (plain Python 3, standard library only; Blender's Python runs it too) paints each added icon from a 28×28 grid of palette letters written in the script, every unit a 10×10 block of one flat colour, in the coarse style of the edit prompt above: thick near-black outline, a handful of flat tones, transparent ground. Movimento Ombra is the Viandante of the figure atlas (ivory hood, a dark void for a face with two pale blue eyes, the cloak open on the dark tunic with its crimson cross) sinking into a violet pool of shadow, with wisps rising from its rim. Pozza di Veleno is a round glass vial tipped over, its neck down to the left, pouring green poison into a wide bubbling puddle with a lit far rim. Incendio is a charred cross of floor with embers in its cracks, a tall flame (red edge, orange, yellow, a white heart) in the middle and a small flame at the end of each arm: the plus it grows into. Deflect is a round steel buckler (a shaded rim, a lit ring, a gold boss) with a bolt flying back off its rim in a spark of gold, pale blue strokes where it came and where it went. Feretro is an upright coffin of dark wood, its lit plank down the left and a plain gold cross, three arrows (iron heads, ivory shafts, red fletching) standing up out of its open head. Dado del Destino is a bone d20 seen as a hexagon with its top face lit and a red 20 on it, inside a violet ring of fate with sparks of gold. Lama Velenosa is a dagger pointing up to the right, a broad steel blade lit along its edge, a gold guard and pommel and a wooden grip, its lower edge coated green and poison dripping off it.

The script reads and writes the PNG itself with zlib and struct, never through Blender or an image library: the painted rows' scanlines are copied byte for byte, filter bytes included, so the 16 painted icons cannot change, and the loader still cuts them on the same pixels (1881/6 and 1254/4 rows start alike). The original's other chunks, its content credentials included, are kept as they were; they describe the generated sheet, so their image hash no longer matches the extended one. The output is deterministic and the script can be run again at will:

```bash
python tools/art/build_card_icons.py                      # rebuild the added rows in place
python tools/art/build_card_icons.py --check              # exit 1 if the atlas is out of date
python tools/art/build_card_icons.py --preview C:/tmp/icone --no-write   # each added cell on a dark ground
```

To add an icon: draw its 28×28 grid (palette letters, `.` for transparent) next to `SHADOW_STEP`, list it in `ICONS` under its cell, run the script, and return that cell from `gothic_card_icon` (`src/render/gothic_theme.odin`).
