# AK della carta FPS

`first-person-ak.png` è l'asset trasparente ricavato dall'AK pixel art del riferimento
fornito dall'utente il 16 ottobre 2026 (`codex-clipboard-J3S0Ze.png`). Conserva
prospettiva, caricatore curvo, legno arancio e bordo avorio; non contiene mani,
braccia, interfaccia o ambiente. La parte inferiore e destra dell'arma rimane
tagliata come nel riferimento e continua oltre i bordi dello schermo.

Prodotto con lo strumento integrato **imagegen**, modalità edit con sfondo
trasparente. Il PNG RGBA è incorporato in `src/render/first_person.odin`;
`FIRST_PERSON_AK_TEXTURE_SIZE` e `FIRST_PERSON_AK_MUZZLE_TEXEL` descrivono
dimensioni native e bocca della canna. La larghezza logica HUD è separata dalla
risoluzione del PNG. Fiammata e tracciante seguono lo stesso punto durante
entrata e rinculo. Il precedente generatore procedurale con maniche è ritirato.

## Prompt usato

> Use case: background-extraction. Asset type: transparent pixel-art weapon sprite for a game HUD. Edit target: the attached game screenshot. Extract ONLY the large paper-cutout AK rifle visible in the lower right. This must be the SAME illustrated AK from the screenshot, not a reinterpretation: preserve its exact perspective, curved magazine, large wooden stock at the lower right, orange wood handguard, detailed cool dark steel receiver, front sight, black ink and thick warm ivory paper outline, pixelated shading and stair-stepped pixel contours. Remove every background pixel, floor, scene, interface, window border, text and enemy. No player, no hand, no arm, no glove, no sleeve. Maintain exactly this diagonal angle from front sight at upper left to stock at lower right. Keep the same crop at the bottom and right where the gun exits the screen; those two edges should meet the image's bottom/right boundary, do not invent extra stock or anatomy. Output just this gun as a tightly framed standalone sprite with actual alpha transparency around it, small transparent padding at top/left. Do not add text, shadows, checkerboard, backdrop, or change the gun artwork.
