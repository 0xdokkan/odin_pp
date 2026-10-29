"""Add the hand-made rows to the card icon atlas.

    python tools/art/build_card_icons.py

(Any Python 3 will do, Blender's included: the script uses only the standard
library.)

assets/gothic/card-icons-pixel.png holds the 16 painted icons
(assets/gothic/generation-prompts.md) in four rows of four. This script keeps
those rows byte for byte and appends a fifth, a sixth, a seventh and an eighth row of the same
cells, painted here as coarse pixel art in the atlas's style (24-28 square
pixel units, a few flat colours, a thick near-black outline):

    cell 16  Movimento Ombra: the ivory hooded Viandante, his face a dark void
             with two pale blue eyes, sinking into a violet pool of shadow.
    cell 17  Pozza di Veleno: a glass vial tipped over, pouring its green
             poison into a bubbling puddle.
    cell 18  Incendio: a fire on a charred cross of floor, a flame at the
             end of each arm (it grows as a plus).
    cell 19  Deflect: a steel buckler with a gold boss, a bolt flying back
             off its rim in a spark, blue strokes of where it came and went.
    cell 20  Feretro: an upright coffin of dark wood with a gold cross,
             three arrows standing up out of its head.
    cell 21  Dado del Destino: a bone d20 with a 20 on its lit face, in a
             violet ring of fate and sparks of gold.
    cell 22  Lama Velenosa: a dagger with a gold guard, its lower edge
             coated green and dripping poison.
    cell 23  Lazzo: a noose of twisted hemp thrown open, its rope running
             down from the knot to a coil and a frayed end.
    cell 24  Canna da Pesca: a wooden rod with a cork grip and a steel reel,
             its line hanging from the tip to a red and white bobber that
             floats on a blue pond, ripples round it.
    cell 25  Pinball: a big chrome ball lit from the upper left striking a
             pop bumper (a red cap with a pale highlight on its crown, in a
             gold ring), a spark where they meet.
    cell 26  First Person Shooter: an AK side on (a wooden stock, grip and
             handguard, a steel receiver and banana magazine), its muzzle
             flashing and three brass casings flying back, inside the red
             ring of a crosshair.
    cell 27  Bomb Marley: a mirrored disco ball that is also a bomb, a cap
             and a sputtering fuse on top, red, yellow and green mirror
             tiles in its mosaic, sparkles round it.
    cell 28  Inondazione: a blue wave curling over a dark hollow, foam along
             its lip, a sea of light dashes below, three drops flung up.

The PNG is read and written here with zlib and struct, never through Blender
or an image library, so the painted pixels are never resampled or recoloured:
their scanlines are copied as they are, filter bytes included. The other
chunks of the original (its content credentials too) are kept unchanged; they
describe the painted sheet, so their image hash no longer matches. The same
atlas in gives the same bytes out, and running the script again rebuilds the
added rows from scratch. Every added row keeps the fifth row's pitch (314
pixels), so the icons painted before the sixth, the seventh and the eighth rows keep
their pixels too.

Phase 6 adds four more cells (the last three of the eighth row and the first
of a ninth), painted the same way with a few more palette letters:

    cell 29  Cannone: a small black cannon on a raised stepped stand of grey
             steel, its barrel pointing up and to the right, a flash at the
             muzzle.
    cell 30  Cannone laser: the same stand, a black barrel ringed with cyan
             coils, a glowing magenta emitter and a straight beam.
    cell 31  Buco nero: a black disc in a thin bright ring, an accretion disc
             of violet, orange and white-hot light across it, streaks of
             matter curling in.
    cell 32  Dinosauro: a cheerful green cartoon dinosaur head with an orange
             crest, a bone d4 showing a 4 beside it.

docs/piano-prima-persona.md adds one more, in the Neon style of its Fase 3:

    cell 33  First Person Brawler: a violet boxing glove thrown up and to the
             right with a cyan rim of light, its thumb along its side, a dark
             cuff under a magenta band, laced in magenta, three strokes of
             speed behind it.
    cell 34  First Person Fencer (its Fase 5): the Neon zweihänder across the
             cell from the lower left: a steel blade with a cyan fuller, the
             parrying hooks and a dark ricasso, a broad magenta cross guard lit
             cyan at its ends, a long violet grip ringed in magenta, a magenta
             pommel with a cyan core.

Options:
    --check        exit 1 if the atlas is not what this script would write
    --preview DIR  also write each added cell on a dark ground,
                   DIR/card-icon-<cell>.png
    --no-write     leave the atlas as it is
"""
import argparse
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ATLAS = os.path.join(ROOT, "assets", "gothic", "card-icons-pixel.png")

COLUMNS = 4
PAINTED_ROWS = 4
ROWS = 9
# One pixel unit of the icon, in atlas pixels (the painted icons' own size).
SCALE = 10
SIGNATURE = b"\x89PNG\r\n\x1a\n"

PALETTE = {
    "K": (6, 5, 9, 255),        # outline, near black
    "I": (236, 226, 200, 255),  # ivory cloak
    "i": (190, 178, 152, 255),  # ivory in shade
    "D": (24, 20, 34, 255),     # the face's void
    "E": (150, 222, 255, 255),  # pale blue eyes
    "T": (44, 46, 58, 255),     # the tunic under the open cloak
    "R": (178, 34, 38, 255),    # its crimson cross
    "S": (30, 8, 56, 255),      # the pool's depth
    "V": (70, 24, 118, 255),    # the pool
    "v": (128, 72, 186, 255),   # the pool's lit rim and ripple, rising wisps
    "G": (30, 88, 52, 255),     # poison in shade
    "g": (70, 156, 72, 255),    # poison
    "L": (166, 226, 112, 255),  # poison's light, its bubbles
    "W": (206, 230, 226, 255),  # the vial's glass
    "w": (140, 176, 182, 255),  # glass in shade
    "U": (255, 244, 196, 255),  # a highlight; the flame's white heart
    "A": (58, 26, 26, 255),     # the charred floor
    "F": (186, 34, 30, 255),    # flame's red edge
    "O": (240, 120, 32, 255),   # flame
    "Y": (255, 206, 76, 255),   # flame's yellow
    "M": (138, 146, 160, 255),  # steel
    "m": (78, 84, 100, 255),    # steel in shade
    "H": (214, 222, 232, 255),  # steel's light
    "N": (82, 52, 34, 255),     # dark wood
    "n": (128, 84, 50, 255),    # wood
    "B": (172, 120, 64, 255),   # light wood: a shaft, a lit plank
    "e": (88, 150, 200, 255),   # the deflection's blue in shade
    "Q": (176, 120, 30, 255),   # gold in shade
    "h": (196, 158, 96, 255),   # hemp rope
    "j": (128, 92, 48, 255),    # rope in shade, its twist
    "k": (232, 208, 154, 255),  # rope in the light; a cork grip
    "C": (30, 70, 136, 255),    # water's depth
    "c": (52, 120, 196, 255),   # water
    "u": (150, 206, 244, 255),  # water's light, its ripples
    "Z": (48, 52, 70, 255),     # black iron
    "z": (80, 86, 110, 255),    # black iron in the light
    "b": (24, 26, 38, 255),     # black iron in shade
    "X": (80, 240, 255, 255),   # energy cyan
    "P": (236, 70, 210, 255),   # energy magenta
    "y": (214, 252, 255, 255),  # a beam's white core
}

# Movimento Ombra, 28x28 units, as the Viandante of the figure atlas: his hood
# and his cloak open on the crossed tunic stand out of the pool; its near half
# runs in front of him, so the rest of him is under it.
SHADOW_STEP = (
    "............................",
    ".............KK.............",
    "............KIIK............",
    "...........KIIIiK...........",
    "..........KIIIIIiK..........",
    ".........KIIIIIIIiK.........",
    ".........KIIKKKKIiK.........",
    "........KIIKDDDDKIiK........",
    "........KIKDDDDDDKiK........",
    ".......KIIKDEDDEDKiiK.......",
    ".......KIIKDDDDDDKiiK.......",
    ".......KIIIKDDDDKIiiK.......",
    "......KIIIIIKKKKIIiiiK...K..",
    "..K..KIIIIIKTTTTKIiiiiK.KvK.",
    ".KvK.KIIIIIKTRRTKIiiiiK.KvK.",
    "KvK..KIIIiIKRRRRKIIiiiiK.KvK",
    "KvK.KIIIIiIKTRRTKIIiiiiK.KvK",
    ".KvKKIIIIiIKTRRTKIIIiiiiKvK.",
    ".KvKKIIIIiIKTTTTKIIIiiiiKvK.",
    "..KVVvvvvSSSSSSSSSSvvvvVVK..",
    ".KVVVVSSSSvvvvvvvvSSSSVVVVK.",
    "KVVVVSSSSSSSSSSSSSSSSSSVVVVK",
    ".KVVVSSSSSSSSSSSSSSSSSSVVVK.",
    "..KVVVSSSSSSSSSSSSSSSSVVVK..",
    "...KVVVVVVVSSSSSSVVVVVVVK...",
    "....KKKKVVVVVVVVVVVVKKKK....",
    "........KKKKKKKKKKKK........",
    "............................",
)

POISON_POOL = (
    ".................KKKKKK.....",
    "................KKWWWWKK....",
    "...............KKWWWWWWKK...",
    "..............KKggWUUWWWKK..",
    "..............KgggUWWWWWWK..",
    "..............KGggggWWWWWK..",
    "..............KGGggggWWWWK..",
    ".............KKGGGggggWWWK..",
    "............KKWGGGGggggWWK..",
    "...........KKWKWGGGGggggKK..",
    "..........KKWKgKwGGGGggKK...",
    "........KKKWKgKwKKGGGGKK....",
    "........KwWKgKwKKKKKKKK.....",
    "........KKwgKwKK............",
    ".........KKwwKK.............",
    ".......KKKgLwK..............",
    "......KKgKggKKKKKKKKK.......",
    "...KKKKGGggLggggggGGKKKK....",
    ".KKKGggLLLggLLLLLLggggGKKK..",
    "KKGggLLLLLgLLLLLLLLLggggGKK.",
    "KGgggggggggggggggLgggggggGK.",
    "KGGgggLgggggggggggggggggGGK.",
    "KGGGgggggGggggggggggLggGGGK.",
    "KKGGGGgggggggggggggggGGGGKK.",
    ".KKKGGGGGGGGGGGGGGGGGGGKKK..",
    "...KKKKKGGGGGGGGGGGKKKKK....",
    ".......KKKKKKKKKKKKK........",
    "............................",
)

WILDFIRE = (
    ".........KKKKKKKKKK.........",
    ".........KAAAAAAAAK.........",
    ".........KAAAFFAAAK.........",
    ".........KAAOOFAAAK.........",
    ".........KAAFYOFAAK.........",
    ".........KAAOYYOAAK.........",
    ".........KAAOYYOOAK.........",
    ".........KAAFYYAAAK.........",
    ".........KAAAAFAAAK.........",
    "KKKKKKKKKKAAAAFAAAKKKKKKKKKK",
    "KAAAAAAAAAAAAFFAAAAAAAAAAAAK",
    "KAAAFAAAAAAAAFOFAAAAOAAFAAAK",
    "KAAAOFAAAAAAFOOFAAAAAAFOAAAK",
    "KAAFOOFAAAAFFOYOFAAAAFOOFAAK",
    "KAAOYYFAAAAFOYYOFFAAAFYYOAAK",
    "KAAOYYOAAAFOOYUOOFAAAOYYOAAK",
    "KAAFYYFOAFFOYUUYOFFAAFYYFAAK",
    "KAAAAAAAAFOOYUUYOOFAAAAAAAAK",
    "KKKKKKKKKKFOYUUYOFKKKKKKKKKK",
    ".........KFOYUUYOFK.........",
    ".........KAFOUUOFAK.........",
    ".........KAOAFFAAAK.........",
    ".........KAAAFFAAAK.........",
    ".........KAAFOOAAAK.........",
    ".........KAAOYYFAAK.........",
    ".........KAAOYYOAAK.........",
    ".........KAAFYYAAAK.........",
    ".........KKKKKKKKKK.........",
)


# The player's charges (Phase 2): Deflect, Feretro, Dado del Destino and Lama
# Velenosa.
DEFLECT = (
    "...................K...KKKK.",
    "..................KeK.KmmmmK",
    ".............K....KeeK.KmmHK",
    "............KEK....KeKKBBmmK",
    ".............KEK...KeKBBBKmK",
    "..............KEK...KBBBK.K.",
    ".........KKK...KEK.KBBBK....",
    "......KKKmmmKKK.K.KBBBK.....",
    ".....KmmHHHHHmmK.KRBBK......",
    "....KmHMMMMMMMHmKRRBK.......",
    "...KmMMMMMMMMMMRRRRK...KKK..",
    "..KmMMMMHHHHHMMMRYK..KKEEEK.",
    ".KmHMMMHMMMMMHMMYUYKKEEEKK..",
    ".KmMMMHMMMMMMMHMMYmK.KKKKKK.",
    ".KHMMHMMMYYYMMMHMMHK..KKeeeK",
    "KmHMMHMMYUYYYMMHMMHmKKeeeKK.",
    "KmHMMHMMYYYYYMMHMMHmK.KKK...",
    "KmHMMHMMYYYYYMMHMmHmK.......",
    ".KHMMHMMMYYYMMMHmmHK........",
    ".KmMMMHMMMMMMMHmmmmK........",
    ".KmHMMMHMMMMMHmmmHmK........",
    "..KmMMMMHHHHHmmmmmK.........",
    "...KmMMMMMMMmmmmmK..........",
    "....KmHMMMMmmmHmK...........",
    ".....KmmHHHHHmmK............",
    "......KKKmmmKKK.............",
    ".........KKK................",
    "............................",
)
COFFIN = (
    ".............KmK............",
    "..........K..KmK..K.........",
    ".........KmKKmHmKKmK........",
    ".........KmKmmmmmKmK........",
    "........KmHmKKIKKmHmK.......",
    ".......KmmmmmKIKmmmmmK......",
    "........KKIKKKIKKKIKK.......",
    ".........KIKKRIRKKIK........",
    ".........KIKKRIRKKIK........",
    "........KRIRKKIKKRIRK.......",
    ".......KNNNNNNNNNNNNK.......",
    "......KNNBDDDDDDDDDNNK......",
    ".....KNNBBnnnnnnnnnnNNK.....",
    ".....KNNBBnnnnnnnnnnNNK.....",
    ".....KNBBBnnnnUQnnnnnNK.....",
    ".....KNBBBnnnnYQnnnnnNK.....",
    ".....KNNBBnnnnYQnnnnNNK.....",
    ".....KNNBBnYYYYYYYYnNNK.....",
    "......KNBBnnnnYQnnnnNK......",
    "......KNNBnnnnYQnnnNNK......",
    "......KNNBnnnnYQnnnNNK......",
    ".......KNBnnnnYQnnnNK.......",
    ".......KNBnnnnYQnnnNK.......",
    ".......KNNnnnnYQnnNNK.......",
    ".......KNNnnnnnnnnNNK.......",
    "........KNnnnnnnnnNK........",
    "........KNNNNNNNNNNK........",
    "........KNNNNNNNNNNK........",
)
FATE_DICE = (
    ".........KKKKKKKKKK.........",
    ".......KKVVVVVVVVVVKK.......",
    "......KVVVvvvvvvvvVVVK..K...",
    "...K.KVVvvKKKKKKKKvvVVKKYK..",
    "..KYKVvvKKKKiiDiKKKKvvVKK...",
    "...KVvKK.KiiiiDiiiK.KKvVK...",
    "..KVvK.KKiiiiiDiiiiKK.KvVK..",
    ".KVVvKKiiiiiiDDDiiiiiKKvVVK.",
    ".KVvKiiiiiiiIDIDiiiiiiiKvVK.",
    "KVVvKiiiiiiiDIIIDiiiiiiKvVVK",
    "KVvKKiiiiiiDDIIIDDiiiiiKKvVK",
    "KVvKKiiiiiiDIIIIIDiiiiiKKvVK",
    "KVvKKiiiiiRRRIIRRRDiiiiKKvVK",
    "KVvKKiiiiDDIRIIRIRDDiiiKKvVK",
    "KVvKKiiiiDRRRIIRIRIDiiiKKvVK",
    "KVvKKiiiDIRIIIIRIRIIDiiKKvVK",
    "KVvKKiiDDIRRRIIRRRIIDDiKKvVK",
    "KVvKKiiDIIIIIIIIIIIIIDiKKvVK",
    "KVVvKiDDIIIIIIIIIIIIIDDKvVVK",
    ".KVvKiDDDDDDDDDDDDDDDDDKvVK.",
    ".KVVvDKiiiiiiiiiiiiiiKKDVVK.",
    "..KVvK.KKiiiiiiiiiiKK.KvVK..",
    ".KYKVvKK.KiiiiiiiiK.KKvVK...",
    "..K.KVvvKKKKiiiiKKKKvvVK.K..",
    ".....KVVvvKKKKKKKKvvVVK.KYK.",
    "......KVVVvvvvvvvvVVVK...K..",
    ".......KKVVVVVVVVVVKK.......",
    ".........KKKKKKKKKK.........",
)
VENOM_BLADE = (
    "..........................K.",
    "........................KKMK",
    "......................KKMHK.",
    "....................KKMMHHK.",
    "...................KMMHHHK..",
    "....................KHHMMK..",
    "...................KMHMMK...",
    "..................KMHMMMK...",
    ".................KMHMMmK....",
    "................KMHMMgK.....",
    "...............KMHMMmgGK....",
    "..............KMHMMggKK.....",
    ".............KMHMMmgGgK.....",
    "....KK......KMHMMggKKgK.....",
    "...KQYKK...KMHMMmgGKKLK.....",
    "...KYYYYK.KMHMMggKgK.K......",
    "....KYYYYKMHMMmgGKgKKgK.....",
    ".....KYYYYHMMggKKKgK.K......",
    "......KYYYYMmgGK.KgK........",
    ".......KnnYYgKgK.KLK........",
    "......KnnnYYgKgK..K.........",
    "...KKKnnnKYYQKgK.KgK........",
    "..KYYnnnK.KYYKLK..K.........",
    ".KYYYYnK...KK.K.............",
    ".KYQYYnK.....KgK............",
    "..KYYKK.......K.............",
    "...KK.......................",
    "............................",
)


# Phase 3: the Lazzo, a noose of twisted hemp thrown open, its rope running
# down from the knot to a coil and a frayed end.
LASSO = (
    "............................",
    ".......KKKKKKKKKKK..........",
    ".....KKKjkkkjkkkjKKK........",
    "...KKKjkkkjkkkjkkkjKKK......",
    "..KKjkkkKKKKKKKKKkkkjKK.....",
    "..KkkkKKK.......KKKkkkK.....",
    ".KKhjKK...........KKjhKK....",
    ".KjhhK.............KhhjK....",
    ".KhhKK.............KKhhK....",
    ".KjhK...............KhjK....",
    ".KhhKK.............KKhhK....",
    ".KjhhK.............KhhjK....",
    ".KKhjKK..........KKKjhKK....",
    "..KhhhKKK.......KKjhjhK.....",
    "..KKjhhhKKKKKKKKKhhjhKK.....",
    "...KKKjhhhjhhhjhhhjhjKK.....",
    ".....KKKjhhhjhhhjKKhjhKK....",
    ".......KKKKKKKKKKKKKhhjK....",
    "...................KKhhKK...",
    ".................KKKKhjhK...",
    "................KKhhjhhhKK..",
    "...............KKhjhhhjhhK..",
    "...............KjhhKKKhhjK..",
    "...............KhhjKKKKhhK..",
    "...............KKhhhjhhhjK..",
    "................KKjhhhjKjKK.",
    ".................KKKKKKjKjK.",
    "......................KKKKK.",
)


# Phase 3: the Canna da Pesca, the first cell of the seventh row: a wooden
# rod, its cork grip and steel reel low on the left, its line hanging from the
# tip to a red and white bobber floating on a blue pond, ripples round it.
FISHING_ROD = (
    "............................",
    "............................",
    "....................KKKK....",
    "...................KKnBKK...",
    "..................KKnBKWK...",
    ".................KKnnKKWK...",
    ".................KnnKKKWK...",
    "................KKnKK.KWK...",
    "...............KKnKK..KWK...",
    "..............KKnKK...KWK...",
    ".............KKnBK....KWK...",
    "............KKnBKK....KWK...",
    "...........KKnBKK.....KWK...",
    "..........KKnBKK......KWK...",
    ".........KKnBKK.......KWK...",
    "........KKnnBK........KWK...",
    "....KKKKKnnBKK........KWKK..",
    "....KHHMnnBKK........KKRRKK.",
    "....KHKMmBKK.KKKKKKKKKRFRRK.",
    "....KKmmBKKKKKcccccuccRRRRK.",
    "...KKjjkKKKKccccccuccuIIIIKK",
    "..KKjjkkK.KcccccccucuccIIcuK",
    ".KKjjkkKK.KcccccccuccuucuucK",
    ".KjjkkKK..KCCccccccccccccCCK",
    ".KjkkKK...KKCCccccccccccCCKK",
    ".KKkKK.....KKKCCCCccCCCCKKK.",
    "..KKK........KKKKKKKKKKKK...",
    "............................",
)


# Phase 4: the Pinball, a chrome ball lit from the upper left striking a pop
# bumper at the upper right (a red cap with a pale highlight on its crown, in
# a gold ring), a spark in the gap where they meet.
PINBALL = (
    "....................KKKK....",
    "...................KYYYYK...",
    "..................KYYRRYYK..",
    ".................KYYRRRRYYK.",
    ".................KYRRUURRYK.",
    ".................KQRRUURRQK.",
    ".................KQFFUUFFQK.",
    ".................OQQFFFFQQK.",
    ".......KKKKKK...KYKQQFFQQK..",
    ".....KKHHHHHMKKOYUYOQQQQK...",
    "....KHHHHHHHHMMKKYK.KKKK....",
    "...KHHHHHHHHHMMMKO..........",
    "..KHHHHHHHHHMMMMmK..........",
    "..KHHUUUHHHHMMMMmK..........",
    ".KHHHUUUHHHMMMMMmmK.........",
    ".KHHHHUHHHHMMMMMmmK.........",
    ".KHHHHHHHHMMMMMmmmK.........",
    ".KHHHHHHMMMMMMMmmmK.........",
    ".KHHHHHMMMMMMMmmmmK.........",
    ".KMMMMMMMMMMMmmmMMK.........",
    ".KMMMMMMMMMMmmmmMMK.........",
    "..KMMMMMMMmmmmmMMK..........",
    "..KMMMMMmmmmmmmMMK..........",
    "...KmmmmmmmmmMMMK...........",
    "....KmmmmmMMMMMK............",
    ".....KKmmmMMMKK.............",
    ".......KKKKKK...............",
    "............................",
)


# Phase 4: the First Person Shooter, an AK side on facing right (its wooden
# stock, grip and handguard, its steel receiver and banana magazine), the
# muzzle flashing and three brass casings flying back over it, all inside the
# red ring of a crosshair.
FIRST_PERSON = (
    "..............K.............",
    "..........KKKKRKKK..........",
    "........KKRRRRRRRRKK........",
    "......KKRRRKKKRKKRRRKK......",
    ".....KRRKKK...K..KKKRRK.....",
    "....KRRK............KRRK....",
    "...KRRK..............KRRK...",
    "...KRK.....KK.........KRK...",
    "..KRK.....KYQK.........KRK..",
    "..KRK...KK.KK.KK.......KRK..",
    ".KRK...KQYK..KYQK.......KRK.",
    ".KRK....KK....KK.....K..KRK.",
    ".KRK..........K.....KMK.KKK.",
    ".KKKKKKKKKKKKKMKKKKKKMK.KYKK",
    "KBBBBBBHHHHHHHBBBBBMMMKKMYOK",
    "KnnnnnnMmmmmMMnnnnnMMMMMUUYK",
    "KnnnnnnmmmmmmmNNNNNKKKKKMYOK",
    "KnnnnnnnnmmmmmmKKKK.....KYK.",
    "KnnnnNKKKnnKMMMK........KKK.",
    "KnnNKK..KnnKKMMMK......KRK..",
    "KMNKK..KnnK.KmMMK......KRK..",
    ".KKKRK.KnNK..KMMMK....KRK...",
    "...KRRK.KK....KMMK...KRRK...",
    "....KRRK.......KK...KRRK....",
    ".....KRRKKK...K..KKKRRK.....",
    "......KKRRRKKKRKKRRRKK......",
    "........KKRRRRRRRRKK........",
    "..........KKKKRKKK..........",
)


# Phase 5: Bomb Marley, a mirrored disco ball that is also a bomb: its cap and
# fuse sputtering a spark at the top, its facets a mosaic of mirror grey with a
# few red, yellow and green tiles (the reggae colours), sparkles round it.
BOMB_MARLEY = (
    ".................OUOY.......",
    "..............KKKKYO........",
    "..............KjjKOY........",
    ".............KjKK...........",
    ".............KjK............",
    "............KKKK............",
    "...........KMHmmK...........",
    "...........KKKKKK........Y..",
    ".........KKKmmmmKKK.....YUY.",
    "...Y....KmHmHmRmmmmK.....Y..",
    "..YUY..KmUmmmmmmmmmmK.......",
    "...Y..KHURmHHmMMmHmmmK......",
    ".....KmHmRmHHmMMmHHmYmK.....",
    ".....KmmmmmmmmmmmmmmmmK.....",
    "....KmYmHHmHHmHHHmMMmMKK....",
    "....KmYmHHmHMmHHHmMMmMKK....",
    "....KmYmHHmMMmHHMmMMmMKK....",
    "....KmmmmmmmmmmmmmmmmKKK....",
    "....KmgmMMmHHmRRRmMMKmKK....",
    "....KmgmMMmHHmRRRmMMKmKK....",
    ".....KmmmmmmmmmmmmmKKKK.Y...",
    ".....KmmmMmMMmGGmmmKmmKYUY..",
    "......KRmMmMMmGGKmmKmK..Y...",
    "......KmmmmmmmmKKKKKKK......",
    ".......KKmQmMKmmKmKKK.......",
    ".........KKKKKKKmKK.........",
    "...........KKKKKK...........",
    "............................",
)


# Phase 5: Inondazione, a flood wave: a blue crest curling over a dark hollow,
# foam along its lip and a sea of light dashes under it, three drops flung up.
FLOOD = (
    "............................",
    ".........................K..",
    "..............KKKKKK....KWK.",
    "....K.......KKWWWWWWKK..KuK.",
    "...KWK.....KWWWWWWWWWWK..K..",
    "...KuK....KWWWuuuuuuWWWK....",
    "....K....KWWuuuuuuuuuuWWK...",
    "........KWWCCCccccccuuuWWK..",
    "..K.....KWCKKKCcccccccWuWWK.",
    ".KWK...KWCKCCCKCcccccccuuWK.",
    ".KuK...KCKCCcCCKcccWccccuuK.",
    "..K...KWKCCcCcCCKCCCcccccuK.",
    "......KWCCCCcCCCKCCCCCccWcK.",
    "......KCCCCCCCcCKCCCCWCcccK.",
    ".......KCCCCCCCCKCCCCCCCccK.",
    "........KCCCCCCCKCCCCCCCCcK.",
    "..KKKKK..KCCCCCCKCCCCCCCCCK.",
    ".KWWWWWKKKCCCCCCKCCCCCCCCCK.",
    "KWWWWWWWWWKCCCCCKCCCCCCCCCK.",
    "KWWuWWuWWuWKKKKKuWWWuWWWuWWK",
    "KuccccccuuuccccccuuuccccccuK",
    "KccccccccccccccccccccccccccK",
    "KuuuccccccuuuccccccuuucccccK",
    "KccccccccccccccccccccccccccK",
    "KCCcccCCCCCCcccCCCCCCcccCCCK",
    ".KCCCCCCCCCCCCCCCCCCCCCCCCKK",
    "..KccCCCCCCcccCCCCCCcccCCK..",
    "...KKKKKKKKKKKKKKKKKKKKKK...",
)


# The hand-made cells of the added rows, by atlas cell.
ICONS = {16: SHADOW_STEP, 17: POISON_POOL, 18: WILDFIRE, 19: DEFLECT, 20: COFFIN, 21: FATE_DICE, 22: VENOM_BLADE, 23: LASSO,
         24: FISHING_ROD, 25: PINBALL, 26: FIRST_PERSON, 27: BOMB_MARLEY, 28: FLOOD}


# Phase 6: the Cannone, a small black cannon on a raised stepped stand of
# grey steel, its barrel (two proud rings, a flared lip, a round breech)
# pointing up and to the right, a flash at its muzzle.
CANNON = (
    "............................",
    "......................O.....",
    "......................O.....",
    "....................YYY.....",
    "...................YYUYYO...",
    "...............KKOOYUUUY....",
    "..............KzzDKYUUUY.OO.",
    ".............KKzzDDYYUYY....",
    "...........KKzzzzDDDYYYO....",
    "..........KzzzZZZZDDO.......",
    ".......KKKzzzZZZZbZZO.......",
    "......KzzzHZzzZZbbZZK.......",
    ".....KKzzzZZZzZbbKKK........",
    "...KKzzzzzZZZbZbK...........",
    "..KzzzzZZzzZbbZZKK..........",
    ".KzzzzZZZZZbbMMMMMK.........",
    ".KzzzZZZZbZZmmmmmmK.........",
    ".KzZZZZZbbbZHHHHHHHK........",
    ".KZZZZbbbbMMmMMMMMmK........",
    ".KZZZbbbKmmmmmmmmmmKKK......",
    "..KbbbbHHHHHHHHHHHHHHHK.....",
    "...KKKMMMmMMMMMmMMMMMmK.....",
    "...KKKmmmmmmmmmmmmmmmmKKK...",
    "..KHHHHHHHHHHHHHHHHHHHHHHK..",
    "..KMMHmMMMHMmMMMMHmMMMHMmK..",
    "..KmmmmmmmmmmmmmmmmmmmmmmK..",
    "...KKKKKKKKKKKKKKKKKKKKKK...",
    "............................",
)

# Phase 6: the Cannone laser, the same stand and barrel with cyan coils round
# it, a glowing magenta emitter at the muzzle and a straight beam off to the
# upper right.
LASER_CANNON = (
    "..........................Xy",
    "........................XXyy",
    ".......................XXyyX",
    "......................XyyXX.",
    "....................XXyyX...",
    "...............KKK.XXyXX....",
    "............KKKmmmXyyXX.....",
    "...........KzzmPPPyyX.......",
    "...........KzzPXyXPX........",
    ".........KKzzzPXyXPmK.......",
    "........KXXzZZmPXPPK........",
    "......KKzzXXZZZmPmK.........",
    ".....KXXzHZXzZbZZZK.........",
    "...KKzzXXZZzXbbKZK..........",
    "..KzzzzZXzZZXXKKKK..........",
    ".KzzzzZZzXbbbXMMMMK.........",
    ".KzzzZZZZXXbmmmmmmK.........",
    ".KzzZZZZbbXXHHHHHHHK........",
    ".KZZZZbbbbMMmMMMMMmK........",
    ".KZZZbbbKmmmmmmmmmmKKK......",
    "..KZbbbHHHHHHHHHHHHHHHK.....",
    "...KKKMMMmMMMMMmMMMMMmK.....",
    "...KKKmmmmmmmmmmmmmmmmKKK...",
    "..KHHHHHHHHHHHHHHHHHHHHHHK..",
    "..KMMHmMMMHMmMMMMHmMMMHMmK..",
    "..KmmmmmmmmmmmmmmmmmmmmmmK..",
    "...KKKKKKKKKKKKKKKKKKKKKK...",
    "............................",
)

# Phase 6: the Buco nero, a black disc inside a thin bright photon ring, the
# flat accretion disc blazing across it (violet, orange, white-hot), streaks of
# matter curling in on four spiral arms.
BLACK_HOLE = (
    "....................K.......",
    "...................KvK......",
    ".......KKKKKKK.....KvvK...U.",
    ".U...KKvvEEEEEK.....KvvK....",
    "...KKvvvKKKKKEEKK....KvK....",
    "..KvvKKK.....KKEEK....KvK...",
    ".KvvK.....KKKKKKKK....KvK...",
    "KvvK.....KYOYOYOYOK...KvvK..",
    ".KK.....KYOSKKKKKYOKKKKKvKK.",
    ".......KYOSKKKKKKKYOOOOOEvvK",
    ".....KKYOSKKKKKKKKKOYYYYOvvK",
    "....KEKOKSKKKKKKKKKKUUYYOvK.",
    "....KEKYKKKKKKKKKKKUUYOOEK..",
    "...KEKvOKKKKKKKKUUUYYOvEEK..",
    "..KEEvOYKKKKYUUUYYOOOvKEK...",
    "..KEOOYUKYUUUYYYOOKKYKEK....",
    ".KvOYYUUUUYYYOOOKKKKOKEK....",
    "KvvOYYYYOOOOKKKKKKKOYKK.....",
    "KvvEOOOOOYKKKKKKKKOYK.......",
    ".KKvKKKKKOYKKKKKKOYK.....KK.",
    "..KvvK...KOYOYOYOYK.....KvvK",
    "...KvK....KKKKKKKK.....KvvK.",
    "...KvK....KEEKK.....KKKvvK..",
    "....KvK....KKEEKKKKKvvvKK...",
    "....KvvK.....KEEEEEvvKK.....",
    "..U..KvvK.....KKKKKKK....U..",
    "......KvK...................",
    ".......K....................",
)

# Phase 6: the Dinosauro, the first cell of the ninth row: a cheerful green
# cartoon dinosaur head in profile (an orange crest, a big eye, a wide smile),
# a bone d4 with its 4 beside it.
DINOSAUR = (
    "............................",
    "........KK.KK...............",
    ".....KKKOOKOOK..............",
    "....KOOOYOOYOOK.............",
    "...KOYOOOOOOOOK.............",
    "...KOOOOOOgOOLLKK...........",
    "...KLOOgggGGGGGLLK..........",
    "...KggggggWWWWWggK..........",
    "..KLggggggWWDUDggLK.........",
    "..KgggggggWWDDDgggK.........",
    ".KLgggggggWWDDDggGGK........",
    ".KGggggggggWWWgggggK.K......",
    ".KgggggggOOggggggggKKUK.....",
    "KgggggggggggggggggKKKUK.....",
    "KggggggggKKKUKKUKKKKKIK.....",
    "KggggggggggFFFFFFFIKUIIK....",
    "KgggggGGIIIIIIIIIIKKIIIK....",
    "KggggGGGIIIIIIIIIIKUIIIIK...",
    "KgggGGKKGiiiiiiiiKKUIIIIK...",
    "KgGGGK..KKKKKKKKK.KIIIIIK...",
    "KGGGK............KUIRIRIIK..",
    "KGKK.............KIIRIRIIK..",
    ".K..............KUIIRRRIIiK.",
    "................KUIIIIRIIiK.",
    "................KIIIIIRIIiK.",
    "...............KUIIIIIIIIIiK",
    "...............KiiiiiiiiiiiK",
    "................KKKKKKKKKKK.",
)


ICONS.update({29: CANNON, 30: LASER_CANNON, 31: BLACK_HOLE, 32: DINOSAUR})

# docs/piano-prima-persona.md, Fase 3 (the Neon style the user chose): First
# Person Brawler, a violet boxing glove thrown up and to the right (its knuckles
# lit, its shade along the bottom, a cyan rim of light down its right), the
# thumb along its left side, a dark cuff under a magenta band, laced in magenta,
# magenta and cyan speed strokes behind.
BRAWLER = (
    "............................",
    "..............KKKKKK........",
    "............KKVVVVVXKK......",
    "...........KVVVvvVVVVXK.....",
    "..........KVVvvvVVVVVVXK....",
    "..PPP.....KVVvvVVVVVVVVXK...",
    ".........KVVVVVVVVVVVVVXK...",
    ".XXXX....KVVVVVVVVVVVVVVXK..",
    "........KKVVVVVVVVVVVVVVXK..",
    "..PPP..KVVKVVVVVVVVVVVVVXK..",
    "......KVVVVKVVVVVVVVVVVVXK..",
    "......KVvvVVKVVVVVVVVVVVXK..",
    "......KVvVVVKVVVVVVVVVVSXK..",
    "......KVVVVVKVVVVVVVVVVXK...",
    ".......KVVVVKVVVVVVVVVSXK...",
    "........KVVVVKVVVVVVVSXK....",
    ".........KKVVVVVVVVSSXK.....",
    "..........KKKVVVVSSXKK......",
    ".........KPPKKKKKKKKPK......",
    "........KVVVVPVPVPVSSK......",
    ".......KVVVVPVPVPVVSSK......",
    "......KVVVVVVVVVVVSSK.......",
    ".....KVVVVVVVVVVVSSSK.......",
    ".....KSVVVVVVVVVSSSK........",
    "......KSSSSSSSSSSSK.........",
    ".......KKKKKKKKKKK..........",
    "............................",
    "............................",
)
assert all(len(row) == 28 for row in BRAWLER) and len(BRAWLER) == 28

ICONS.update({33: BRAWLER})

# docs/piano-prima-persona.md, Fase 5: First Person Fencer, the Neon zweihänder
# the user chose (a two-handed great sword, cybernetic and majestic) across the
# cell from the lower left: its steel blade lit on one side with a cyan fuller,
# the parrying hooks, the dark ricasso with a magenta ring, the broad magenta
# cross guard with a white core and cyan ends, the long grip, the pommel.
# Painted by tools: rasterised along the blade's line, outlined on four sides.
FENCER = (
    "............................",
    "............................",
    "........................K...",
    ".....................KKKmK..",
    "....................KHHMK...",
    "...................KHHXmK...",
    "..................KHHXMmK...",
    ".................KHHXMmK....",
    "................KHHXMmK.....",
    "...............KHHXMmK......",
    "..............KHHXMmK.......",
    ".............KHHXMmK........",
    "..........K.KHHXMmK.........",
    "......K..KMKHHXMmK..........",
    ".....KXK..KMHXMmK...........",
    "....KXXPK.KzmMmK............",
    ".....KPPPKPzZmK.............",
    "......KPPyzPKKmK............",
    ".......KyyyK..K.............",
    "......KVVyPPK...............",
    ".....KVPSKPPPK..............",
    "...KKPVSK.KPXXK.............",
    "..KPVVPK...KXK..............",
    ".KPPPSK.....K...............",
    ".KPXPPK.....................",
    ".KPPPK......................",
    "..KKK.......................",
    "............................",
)
assert all(len(row) == 28 for row in FENCER) and len(FENCER) == 28

ICONS.update({34: FENCER})


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != SIGNATURE:
        sys.exit(f"{path}: not a PNG")
    pos, header, idat, extra = 8, None, [], []
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        elif idat:
            sys.exit(f"{path}: a {kind!r} chunk after the image data is not supported")
        else:
            extra.append((kind, body))
    if header is None or not idat:
        sys.exit(f"{path}: no image")
    width, height, depth, colour, _, _, interlace = header
    if (depth, colour, interlace) != (8, 6, 0):
        sys.exit(f"{path}: expected 8-bit RGBA, not interlaced")
    return width, height, zlib.decompress(b"".join(idat)), extra


def cell_bounds(cell, width, height, rows):
    """The loader's rectangle of `cell` (render/gothic_theme.odin)."""
    left, right = cell % COLUMNS * width // COLUMNS, (cell % COLUMNS + 1) * width // COLUMNS
    top, bottom = cell // COLUMNS * height // rows, (cell // COLUMNS + 1) * height // rows
    return left, top, right, bottom


def added_pitch(painted):
    """The height of the first added row (314 pixels on the painted sheet):
    every added icon is centred on it, so a row added later never moves the
    ones painted before it."""
    return (painted * (PAINTED_ROWS + 1) + PAINTED_ROWS - 1) // PAINTED_ROWS - painted


def paint(width, painted, height):
    """The added rows' pixels (RGBA, top to bottom), from atlas row `painted`."""
    pixels = bytearray(width * (height - painted) * 4)
    pitch = added_pitch(painted)
    for cell, art in sorted(ICONS.items()):
        units = len(art)
        if any(len(line) != units for line in art):
            sys.exit(f"cell {cell}: its grid is not square")
        if any(unit != "." and unit not in PALETTE for line in art for unit in line):
            sys.exit(f"cell {cell}: a letter outside the palette")
        left, top, right, bottom = cell_bounds(cell, width, height, ROWS)
        oy = top + (pitch - units * SCALE) // 2
        if top < painted or units * SCALE > right - left or oy < top or oy + units * SCALE > bottom:
            sys.exit(f"cell {cell} does not fit an added row")
        ox = left + (right - left - units * SCALE) // 2
        oy -= painted
        for y, line in enumerate(art):
            for x, unit in enumerate(line):
                if unit == ".":
                    continue
                colour = bytes(PALETTE[unit])
                for yy in range(SCALE):
                    at = ((oy + y * SCALE + yy) * width + ox + x * SCALE) * 4
                    pixels[at:at + SCALE * 4] = colour * SCALE
    return pixels


def build(path):
    width, height, scanlines, extra = read_png(path)
    stride = width * 4 + 1
    if len(scanlines) != height * stride:
        sys.exit(f"{path}: the image data does not fill {width}x{height}")
    # The painted sheet is square: four rows of the same cells as its columns.
    painted = width
    extended = (painted * ROWS + PAINTED_ROWS - 1) // PAINTED_ROWS
    # The painted sheet, or this script's work from it with any number of added rows.
    known = {(painted * rows + PAINTED_ROWS - 1) // PAINTED_ROWS for rows in range(PAINTED_ROWS, ROWS + 1)}
    if height not in known:
        sys.exit(f"{path}: {width}x{height} is neither the painted sheet nor its extension")
    for row in range(PAINTED_ROWS + 1):
        # The added row must leave every painted cell where the loader finds it.
        if row * extended // ROWS != row * painted // PAINTED_ROWS:
            sys.exit(f"{path}: an added row would move the painted cells")
    added = paint(width, painted, extended)
    rows = bytearray(scanlines[:painted * stride])
    row_bytes = width * 4
    for y in range(extended - painted):
        line = added[y * row_bytes:(y + 1) * row_bytes]
        if y == 0:
            rows += b"\x00" + line
        else:
            above = added[(y - 1) * row_bytes:y * row_bytes]
            rows += b"\x02" + bytes((a - b) & 255 for a, b in zip(line, above))
    out = SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", width, extended, 8, 6, 0, 0, 0))
    for kind, body in extra:
        out += chunk(kind, body)
    out += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    return out, width, painted, extended, added


def write_preview(directory, width, painted, height, added):
    """Each added cell on a dark ground: DIR/card-icon-<cell>.png."""
    os.makedirs(directory, exist_ok=True)
    ground = (40, 40, 46)
    for cell in sorted(ICONS):
        left, top, right, bottom = cell_bounds(cell, width, height, ROWS)
        rows = bytearray()
        for y in range(top - painted, bottom - painted):
            rows += b"\x00"
            for x in range(left, right):
                at = (y * width + x) * 4
                r, g, b, a = added[at:at + 4]
                k = a / 255
                rows += bytes(int(c * k + q * (1 - k) + 0.5) for c, q in zip((r, g, b), ground))
        data = SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", right - left, bottom - top, 8, 2, 0, 0, 0))
        data += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
        open(os.path.join(directory, f"card-icon-{cell}.png"), "wb").write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--preview")
    parser.add_argument("--no-write", action="store_true")
    args = parser.parse_args()
    out, width, painted, height, added = build(ATLAS)
    if args.preview:
        write_preview(args.preview, width, painted, height, added)
    current = open(ATLAS, "rb").read()
    if args.check:
        print("up to date" if out == current else "out of date")
        sys.exit(0 if out == current else 1)
    if not args.no_write and out != current:
        open(ATLAS, "wb").write(out)
    print(f"{os.path.relpath(ATLAS, ROOT)}: {width}x{height}, {len(ICONS)} added icon(s)")


if __name__ == "__main__":
    main()
