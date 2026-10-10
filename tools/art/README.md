# Pipeline grafica (Blender)

Gli script di questa cartella girano dentro il Python di Blender 3.5+ (che include
numpy); non servono altri pacchetti. Tutti i risultati sono deterministici.

## Cartoncini animati (flipbook)

```bash
blender -b --factory-startup --python tools/art/build_sprites.py
```

Legge `assets/gothic/figures-v2.png` e scrive:

- `assets/gothic/flipbook/<nome>.png`: i disegni del personaggio, una riga per azione;
- `assets/gothic/flipbook/<nome>-paper.png`: per ogni disegno, il campo di distanza dalla sua sagoma;
- `src/engine/gfx/flipbook_data.odin`: le tabelle dei fotogrammi (file generato, non modificarlo).

Come funziona:

1. Ogni figura dipinta viene convertita in pixel art vera: blocchi di 3 px, 15
   colori per figura più l'inchiostro condiviso, pulizia dei pixel isolati che
   risparmia occhi e gemme.
2. `characters.py` divide ogni figura in ossa (regioni poligonali con un perno).
   Le giunture vicine al perno si piegano invece di strapparsi; le parti marcate
   `back` lasciano dietro una piastra riempita quando si spostano.
3. Ogni fotogramma è una posa chiave scritta a mano, renderizzata con 8x8
   sottocampioni per pixel su una tela 4x e ridotta a voto di maggioranza: compaiono
   solo i colori originali, quindi resta pixel art pulita. Il contorno viene rifatto
   a ogni posa.
4. La carta non è un ritaglio fisso: ogni disegno ha il suo campo di distanza esatto
   dalla sagoma e lo shader della carta (`src/engine/gfx/flipbook.odin`) taglia il
   cartoncino poco oltre la figura. Quando la stampa cambia disegno, la carta passa
   dal campo vecchio al nuovo in 90 ms: si allunga dove un braccio si estende e
   rientra quando torna. Spessore, inchiostro e taglio visibile sono impostati in
   testa a `build_sprites.py` e arrivano allo shader come costanti.

Il nucleo (dati, tempi, shader, `Flipbook_Player`, disegno a billboard 3D e 2D) vive
in `src/engine/gfx/flipbook.odin`, così lo usano sia il tabellone sia i minigiochi:
oggi Platform 3D (il Viandante e i ghoul sentinella) e l'FPS (ghoul, spettri e
cultisti, guidati dagli stati dei nemici).

Opzioni utili:

```bash
# anteprime (stampa sul cartoncino) senza toccare assets/ e src/
blender -b --factory-startup --python tools/art/build_sprites.py -- --preview C:/tmp/anteprime --no-write
# griglie con coordinate per posizionare ossa e regioni
blender -b --factory-startup --python tools/art/build_sprites.py -- --sheets C:/tmp/griglie --no-write
```

### Azioni

| Azione | Modo | Quando |
|---|---|---|
| `idle` | loop | sempre, sotto le altre |
| `walk` | loop | durante le cue `Move` |
| `windup` | loop | nemico con intento in carica |
| `stunned` | loop | stato `Stagger` o intento `Recover` |
| `attack` | una volta, dal disegno d'impatto | sorgente di `Damage` / `Attack_Missed` |
| `cast` | una volta | `Card_Played`, `Spell_Launched`; per i nemici `Object_Spawned` e `Status_Applied` su un alleato |
| `hurt` | una volta | bersaglio di `Damage` |
| `block` | una volta | `Damage_Absorbed`, `Move_Blocked` |
| `dodge` | una volta | `Attack_Missed` sul giocatore, o scatto di due celle |
| `interact` | una volta | `Loot` |
| `death` | una volta, poi il cartoncino cade | `Defeat` |

Un personaggio senza una clip usa la più vicina (`cast`→`attack`, `block`→`hurt`,
`dodge`→`walk`, il resto→`idle`). Le clip non bloccano mai il gioco: quando la cue
finisce, la clip completa i suoi disegni con il proprio orologio.

Per aggiungere un'azione: aggiungila ad `ACTION_ORDER` in `build_sprites.py`,
scrivi le pose in `characters.py`, rigenera e collega la cue in
`flipbook_cue_action` (`src/render/flipbook_actor.odin`).

## Mura gotiche

```bash
blender -b --factory-startup --python tools/art/build_walls.py -- --preview C:/tmp/mura
```

Modella con bmesh il kit delle mura e scrive `assets/models/gothic-walls.odm`
(lista di triangoli con colori per vertice; il formato è descritto in testa allo
script). Ogni pezzo è in unità di cella, con l'origine alla base del centro della
cella, ed è rivolto verso +Z (griglia +y); il renderer lo ruota verso ogni lato.

| Pezzo | Uso |
|---|---|
| `core` | il nucleo 0,8 x 0,8 di ogni muro |
| `link` | verso un muro vicino o oltre il bordo: massa continua |
| `face_ashlar`, `face_lancet`, `face_buttress`, `face_rose` | verso una cella calpestabile visibile, scelta deterministica per lato |
| `post`, `pilaster` | angoli: pieno, o colonna a fascio sugli spigoli convessi |
| `merlons`, `cap`, `cut_cap` | merlatura e cappello; `cut_cap` è la sezione dei muri vicini ritratti |
| `sconce` | lanterna a muro, centrata sulla luce della lampada |

`src/render/diorama_kit.odin` legge il file (senza GL, quindi anche nei test) e
invia i triangoli con lo stesso shader resin dei blocchi: luce, nebbia, ritiro
verso la telecamera (taglio all'altezza del muro) e trasparenza dei muri interni
restano quelli di prima. Se il kit non si carica, torna il disegno procedurale.
Ogni decorazione resta dentro il volume della cella e sotto il raggio di culling
di 1,8 (lo verifica `test_diorama_kit_pieces_fit_their_cell`).

## Viandante 3D (scheda personaggio)

```bash
blender -b --factory-startup --python tools/art/build_pilgrim.py -- --preview C:/tmp/viandante
```

Scolpisce il Viandante a partire dallo sprite del tabellone: mantello avorio
aperto con pieghe, cappuccio con il volto in ombra e occhi azzurri, tunica con la
croce cremisi, cintura, stivali e la lanterna a gabbia alzata. Il mantello e il
cappuccio usano la suddivisione; l'esportazione è nello stesso formato ODM del
kit (`assets/models/pilgrim.odm`). La scheda lo mette su un piedistallo in una
piccola cappella costruita con i pezzi del kit, illuminato dalla sua lanterna.
`--blend FILE` salva anche la scena .blend per ritoccarla a mano.
