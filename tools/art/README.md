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
   a ogni posa, dopo aver cancellato i frammenti che la posa stacca dal corpo (un
   angolo di veste o una scheggia di pastorale rimasti su un osso fermo): è `mend`
   di `pixel_rig.py`, lo stesso dei cartoncini vivi, e il log della build elenca
   ciò che cancella (`MENDED`).
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

## Cartoncini vivi

```bash
blender -b --factory-startup --python tools/art/build_living.py
```

I personaggi del tavolo 3D: stesse figure e stessi rig dei cartoncini classici
(che restano ai minigiochi), ma la figura è un disegno animato su un cartoncino
fermo. Scrive:

- `assets/gothic/flipbook/living/<nome>.png`: i disegni, 16 per riga, una clip dopo l'altra;
- `assets/gothic/flipbook/living/<nome>-paper.png`: il campo del cartoncino, uno solo per personaggio;
- `src/engine/gfx/living_data.odin`: le tabelle delle clip (file generato, non modificarlo).

Cosa cambia rispetto al flipbook classico:

1. **Il cartoncino non si muove e non cambia forma.** È l'unione (anche
   specchiata) delle sagome a riposo, allargata di 1/0,89 attorno ai piedi: la
   figura è stampata all'89% e ha un po' di spazio per muoversi. Ciò che esce dalla carta
   viene tagliato dal bordo, come un disegno che esce dal foglio. Linea
   d'inchiostro e taglio hanno lo spessore dei cartoncini classici.
2. **Le clip sono chiavi nel tempo**, scritte in `living_actions.py` (ms, con
   easing), non disegni singoli. Il generatore le campiona a 12 disegni al
   secondo, a 24 negli intervalli `ones` (i momenti più rapidi), e unisce i
   disegni uguali in una pausa più lunga. Il canale `root` sposta, ruota e
   schiaccia la figura intera dentro la carta.
3. **Principi dell'animazione a mano**: anticipo prima di ogni sforzo,
   schiacciamento e allungamento in base alla velocità, archi, pause sui disegni
   più forti, follow-through con molle sulle parti morbide (mantelli, orli,
   lanterne). Linea viva: a ogni disegno qualche pixel d'inchiostro del bordo
   cambia. Segni a matita piccoli (polvere, urto, velocità) e la traccia leggera
   del disegno precedente quando la figura scatta. I frammenti che una posa
   stacca dal corpo (un angolo di veste su un osso rimasto fermo, la punta di
   un bastone tagliata dal bordo) vengono cancellati (`mend`); il log della
   build elenca, azione per azione, le dimensioni di ciò che ha cancellato.
4. **Il cartoncino scivola rigido, spinto dal personaggio.** Ogni clip di
   movimento dice quando e come la carta passa alla casella successiva
   (`travel`: `shove`, `run`, `stomp`, `hop`, `glide`, `dash`, `float`). Il
   runtime (`src/render/living_card.odin`) usa le stesse curve.

Ogni personaggio si muove a modo suo: il Viandante dà una spallata (o un calcio,
o un balzo) alla sua carta; il ghoul corre a quattro zampe; il balestriere scatta
basso; il bruto pesta due volte; il bombarolo saltella; il custode levita e
spinge la carta con il pastorale; l'arcimago fluttua.

| Azione | Quando |
|---|---|
| `idle`, `windup`, `stunned`, `channel` | loop sotto le altre; `channel` è il Viandante durante un cast |
| `move_side`, `move_up`, `move_down` | cue `Move`, secondo la direzione sullo schermo |
| `dodge` | scatto di due celle del giocatore |
| `attack`, `cast` | come nei cartoncini classici |
| `hurt`, `hurt_back` | colpo dal lato verso cui guarda, o da dietro; `hurt_back` anche quando viene spinto (la carta scivola via) |
| `block`, `interact`, `death` | come nei cartoncini classici |

Anteprime (un PNG animato per azione e fogli di contatto) senza toccare assets/ e src/:

```bash
blender -b --factory-startup --python tools/art/build_living.py -- --preview C:/tmp/vivi --no-write
# solo alcuni personaggi (non riscrive le tabelle)
blender -b --factory-startup --python tools/art/build_living.py -- --only ghoul,brute --preview C:/tmp/vivi --no-write
```

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

## Icone delle carte fatte a mano

```bash
python tools/art/build_card_icons.py
```

Aggiunge ad `assets/gothic/card-icons-pixel.png` una quinta riga di celle in pixel
art disegnate nello script (una griglia di 28x28 lettere di palette per icona; oggi
la cella 16, Movimento Ombra) e lascia identiche, byte per byte, le 16 icone dipinte.
Usa solo la libreria standard di Python (va bene anche quello di Blender) e non passa
mai l'atlante da Blender né da altre librerie d'immagine. `--check` dice se l'atlante
è aggiornato; `--preview C:/tmp/icone --no-write` scrive le celle aggiunte senza
toccarlo. I dettagli sono in `assets/gothic/generation-prompts.md`.

## Armi e colpi di carta

```bash
python tools/art/build_attack_props.py
```

Le armi che i cartoncini vivi menano sul tavolo e quello che lanciano
(`src/render/attack_fx.odin`): la lanterna di ferro del Viandante, le due armi
M8 (Mannaia di ferro e Picca della tempesta), gli artigli del ghoul, la mannaia
del bruto, il pastorale del custode, il bastone dell'arcimago, il dardo della
balestra, la bomba, la brace in due disegni che si alternano, e i pezzi di un
impatto: la scia di carta di un fendente, la stella del colpo (stampata in
bianco e colorata dal colpo: rossa, blu se lo scudo para, oro se critico), i
graffi del ghoul e i pezzetti di carta che volano dalle caselle vuote.

Ogni pezzo è pixel art scritta nello script come righe di lettere di palette,
nei colori delle figure; lo script aggiunge il contorno d'inchiostro (ogni pixel
vuoto che tocca la figura, anche in diagonale) e chiude i buchi di un pixel o
due. La carta è il campo di distanza esatto dalla stampa, tagliato dallo stesso
shader dei cartoncini (`FLIPBOOK_PAPER_FRAGMENT`) sul loro foglio più bianco: il
campo è salvato stirato, così i 5,5 px di carta dello shader diventano una carta
più sottile, larga quanto dice ogni pezzo. Scrive, con lo stesso impaccamento:

- `assets/gothic/attack-props.png`: le stampe (mai filtrate);
- `assets/gothic/attack-props-paper.png`: i loro campi, un canale;
- `src/engine/gfx/attack_props_data.odin`: la tabella (file generato, non modificarlo).

Usa solo la libreria standard di Python (va bene anche quello di Blender); lo
stesso script dà gli stessi byte. `--check` dice se i tre file sono aggiornati;
`--preview C:/tmp/armi --no-write` scrive, senza toccarli, ogni pezzo sulla sua
carta ingrandito e una prova di volo e di fendente che imita lo shader, con il
taglio sempre in basso a destra come lo tiene il gioco.
