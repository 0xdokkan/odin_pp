# Pipeline grafica

## Spedizione cartoon (Odin)

Il robot della spedizione e i sei nemici Cyber sono disegni procedurali in
`src/render/expedition_robot.odin` e `src/render/expedition_cartoon.odin`.
La prima creazione del materiale rasterizza le pose in un atlante nearest:
104×104 pixel per cella, 60 pixel per unità del disegno, sei pose per clip.
Gli otto pixel di padding aggiuntivi non cambiano scala o posizione degli attori.
La sagoma è l'unione della posa neutra e della sua versione specchiata,
allargata di sette pixel (due d'inchiostro e cinque avorio), troncata alle suole.
Negli ultimi tre pixel la dilatazione si restringe a un pixel, preservando
lo spazio fra i piedi invece di unirli con una striscia di carta.
La stessa maschera stabile ritaglia tutte le animazioni e governa il picking.
Cannoni, antenne, serbatoi e scudi Cyber sono accoppiati nel disegno, così la
rotazione della stampa non lascia grandi lobi vuoti sul supporto simmetrico.
Le sorgenti sono codice scritto a mano; non si modificano `living_data.odin`
o `flipbook_data.odin` per cambiare queste figure. Il robot dell'hub usa lo
stesso disegno sorgente. Gli altri biomi conservano i rig e i costumi esistenti.

I macchinari e gli oggetti speciali sono disegnati in
`expedition_fixture_art.odin`: 96 illustrazioni (sei funzioni e due arredi per
ciascuno dei dodici biomi), in due pose su celle 104×104. Le due pose condividono
una sagoma stabile allargata di otto pixel: sei avorio e due d'inchiostro.
Negli ultimi cinque pixel sopra il terreno il margine torna a un solo pixel;
non esiste carta sotto le radici. La densità resta 60 pixel per unità e il
padding protegge antenne e contorni dal bordo dell'atlante. Stampa e maschere
sono caricate una volta per materiale, senza upload durante l'animazione.

Le macchine principali Cyber e West hanno quattro pose 104×208 in
`expedition_fixture_hero.odin` e `expedition_fixture_west.odin`: pressa e sega
a telaio, ciascuna con tre gruppi secondari. Condividono `hero_print` 416×624
e `hero_paper` 416×312; non alterare le celle dell'altro bioma quando si
estende il pack. Il contorno rimane da otto pixel e il culling usa la sagoma
opaca. Il terreno delle due officine è pittura procedurale precalcolata
1024×1024, con mipmap: modificare le funzioni sorgenti Cyber/West, non PNG
generati. Tetti e arredi murali sono geometria stampata nei file
`expedition_cyber_building.odin` e `expedition_west_building.odin`.

La pipeline Blender sottostante continua a generare gli attori delle altre
viste. Il materiale carta condiviso usa meno grana e un taglio piatto;
nelle spedizioni non si disegnano più piedistalli sotto gli attori.

Pareti e oggetti condividono `EXPEDITION_BODY_GLSL`: inchiostro scuro, taglio
avorio sottile, campiture nette e dettagli registrati in coordinate mondo.
Le palette Cyber sono in `expedition_cyber.odin`; i verdi delle foglie e il
giallo dei macchinari sono pigmenti, non nuove luci. I riferimenti e la lettura
artistica sono documentati in `docs/presentazione.md`.

Il moonshot dell'ambiente usa sorgenti vettoriali native: profili concavi in
`expedition_profiles.odin`, moduli in `expedition_cyber.odin` e nelle tre famiglie
`ascent/descent/dread`, arredi in `expedition_biome_forms.odin`. Un profilo è
un poligono semplice in ordine orario (massimo 32 vertici), con radice a y=0;
la triangolazione preserva le rientranze. Le verifiche coprono area, orientamento,
quote, ingombri nelle celle e determinismo del bake. Per nuovi moduli scegliere
un profilo intenzionale, poche superfici dipinte e contorni selettivi.

`expedition_print.odin` contiene i disegni delle pareti per tutti i biomi.
Il tag UV di `ink_wall_sheet` li separa dagli oggetti: non aggiungere glifi
generici a tutte le facce. Derivate prima della ripetizione delle coordinate,
contrasto minore dei segni interni, niente texture o allocazioni per frame.
Le nuove geometrie riusano upload, cache e distruzione del materiale esistenti.

## Regolare sole, corsi e contatto del redesign

Direzione, mappe, estensione, filtro e bias sono in `expedition_sun.odin`;
tinta delle bande e neon in `expedition_lighting.odin`. Saturazione e
separazione cromatica sono in `EXPEDITION_HDR_RESOLVE`
(`expedition_post.odin`), vignetta in `tactical_surface.odin`.
Controllare geometria e caster prima di compensare un difetto con il bias.

`paperCourses` in `expedition_print.odin` regola i corsi per bioma.
`ink_wall_sheet`, `ink_wall_post` e `WALL_*` in
`expedition_architecture.odin` governano zoccolo, corpo, copertina e pilastri.
I raccordi delle facce dipendono dall'altezza; i pilastri usano invece vicini
anche ad altezze diverse. Le facce mantengono UV di stampa [0,1] o [4,5].

Le modifiche del 3 novembre sono integrate; copie e delta sono sotto
`build/redesign-sole/session-20261103/`. Renderer 477/477 con E attiva e
smoke oggetti/fallback/camminata/full passano; G è verificata in v4.
Il confronto finale e il controllo del movimento a percorso identico sono
conclusi. Il target 60 FPS non è raggiunto; variabilità e limiti residui sono
documentati in `VERIFICA_REDESIGN_SOLE.txt`.
C/D usa `expedition_structure_objects.odin` per le forme intere e
`structure_expedition.odin` per le finiture; Cyber/West conservano le
stampe dedicate. F1 regola vasca e quota foglie in `expedition_cyber.odin`.
F2 passa `post_fill` esplicito a `ink_wall_sheet`: evitare riconoscimenti
della funzione basati sul colore. G regola palette e bordo in
`paperAccumulation`, densità dei segni in `paperDetails`
(`expedition_floor.odin`); `expedition_sky_crowd` resta condiviso con l'AO.
Le scorciatoie del frammento saltano solo contributi nulli e devono mantenere
questa condivisione. F4 scala il disegno della pressa in
`cyber_press_art` del 6% in larghezza e del 2% in altezza, senza cambiare
densità, cella, atlas o quad; verificare le quattro pose e i bordi del supporto.
La selezione degli accessori in `expedition_fixture_sprites.odin` deve
restare identica fra colore e caster. Gli interni in
`expedition_cyber_building.odin` conservano arredi sulle pareti e vano
della porta libero; i budget delle stampe restano distinti dall'involucro.

E ha una sola intensità, `EXPEDITION_ACTOR_SHADOW_STRENGTH`, in
`expedition_actor_shadow.odin`: `.15`, approvata dall'utente dopo confronto
on/off, con `EXPEDITION_ACTOR_SHADOW=true` di default. Il flag false resta
disponibile per i confronti. Controllare pigmenti, carta, inchiostro e flash;
le fughe F3 non sono parte della proposta attiva.

Usare contact sheet 2×2 delle catture native senza correggerne colori o
contenuto; `index.txt` conserva l'associazione con i file originali.

## Pigmento officine P1

Il generatore `tools/art/build_workshop_stock.py` usa Python 3 con la sola
libreria standard. Per rigenerare o verificare integralmente serve anche
Odin nel `PATH`, oppure indicato dalla variabile `ODIN`. Il programma Odin
temporaneo lavora su immagini CPU e non apre una finestra o un contesto GL.

1. Modificare le routine autorevoli in `expedition_cyber_floor.odin`,
   `expedition_west_ground.odin` o `expedition_workshop_stock.odin`.
   Il generatore estrae dichiarazioni e funzioni; le formule non vanno
   duplicate in Python e i PNG non vanno ritoccati a mano.
2. Dalla radice del repository eseguire
   `python3 tools/art/build_workshop_stock.py` per rigenerare i due PNG
   1024×1024, `assets/workshop-stock/manifest.json` e
   `src/render/expedition_workshop_stock_data.odin`. Conservare insieme
   questi file e la modifica delle sorgenti che li ha prodotti.
3. Eseguire `python3 tools/art/build_workshop_stock.py --check` per il
   controllo economico di versione, sorgenti, generatore, dichiarazioni
   embedded e hash PNG. È lo stesso controllo degli script `check.sh` e
   `check.ps1`; non compila e non genera nuovi asset.
4. Eseguire `python3 tools/art/build_workshop_stock.py --verify` quando
   occorre la riproduzione integrale: rigenera in temporaneo, confronta
   manifest e hash dei 2.097.152 pixel RGBA e verifica il roundtrip PNG.
   Non sostituisce i file presenti. Completare con un caricamento reale per
   verificare decode/upload, riuso, mipmap e assenza di rigenerazione al draw.

In PowerShell usare `python` al posto di `python3`, con Python 3 nel `PATH`.
`--check` fallisce se sorgenti o generatore cambiano senza rigenerazione;
`--verify` richiede gli asset già aggiornati. Nessuno dei due misura il costo
GPU del caricamento o del pavimento. Il runtime incorpora i PNG e non
dipende da una cache scrivibile; il fallback procedurale è limitato al load.

## Pipeline Blender

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

Aggiunge ad `assets/gothic/card-icons-pixel.png` una quinta, una sesta e una settima riga di
celle in pixel art disegnate nello script (una griglia di 28x28 lettere di palette
per icona; oggi la cella 16, Movimento Ombra, la 17, Pozza di Veleno: una fiala
rovesciata nella sua pozza, la 18, Incendio: un fuoco su una croce bruciata, una
fiamma in fondo a ogni braccio, la 19, Deflect: uno scudo tondo d'acciaio da cui un
dardo rimbalza via in una scintilla, la 20, Feretro: una bara di legno scuro con la
croce d'oro e tre frecce che spuntano dalla testa, la 21, Dado del Destino: un d20
d'osso con il 20 sulla faccia illuminata in un anello viola, la 22, Lama Velenosa:
un pugnale dall'elsa d'oro con il filo verde che gocciola veleno, la 23, Lazzo:
un cappio di canapa intrecciata, aperto, con la corda che scende dal nodo a un
rotolo e a un capo sfilacciato, e la 24, la prima della settima riga, Canna da Pesca:
una canna di legno con l'impugnatura di sughero e il mulinello d'acciaio, la lenza
che scende dalla punta a un galleggiante rosso e bianco su uno stagno blu) e lascia
identiche, byte per byte, le 16 icone dipinte. Ogni riga aggiunta tiene il passo
della quinta (314 pixel), così le icone di una riga non si spostano quando se ne
aggiunge un'altra.
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
graffi del ghoul e i pezzetti di carta che volano dalle caselle vuote. Per il
pavimento (`src/render/ground_fx.odin`): le fiamme dei fuochi di Incendio (due
disegni grandi per il centro, due più piccoli per i bracci, che si alternano),
la fiala di Pozza di Veleno in volo, le gocce del suo schizzo e le faville di
una fiamma calpestata. Per la Canna da Pesca (`src/render/fishing.odin`): la
canna lunga e sottile con le sue guide, il mulinello e l'impugnatura di
sughero, il galleggiante rosso e bianco, le gocce d'acqua, il `!`
dell'abboccata e le prede: un pesce, una mela, una pagnotta, una fetta di
formaggio, una coscia di carne e il dorso di una carta, bordato d'oro. Per il
Lazzo (`src/render/lasso.odin`): due sbuffi di polvere di pietra grigia, più
chiari dove li prende la luce, che si alzano dal muro a ogni schianto. I pezzi
nuovi si aggiungono in fondo: quelli che ci sono restano dove sono, pixel per
pixel.

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
