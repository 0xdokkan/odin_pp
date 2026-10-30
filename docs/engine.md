[← Odin PP](../README.md)

## Engine e minigiochi

Il roguelike e i minigiochi girano sullo stesso engine, in
[src/engine](../src/engine): il nucleo continuo M9 e tredici package di servizi, senza dipendenze dal gameplay,
ognuno con i propri test headless. Le parti di sola logica (casualità, tempo,
fisica, layout dell'interfaccia, sintesi audio, salvataggi) non chiamano Raylib.

| Package | Contenuto |
|---|---|
| [rng](../src/engine/rng) | stream xorshift64* con derivazione splitmix per dominio, range senza bias, pesi, shuffle; lo usano anche mazzo, dadi ed economia del roguelike |
| [timing](../src/engine/timing) | accumulatore a passo fisso con limite di recupero, timer e cooldown |
| [tween](../src/engine/tween) | curve di easing, smoothing indipendente dal frame rate, tween tipizzati |
| [pool](../src/engine/pool) | pool a capacità fissa con handle generazionali |
| [physics](../src/engine/physics) | rettangoli, cerchi e raggi; tile map 2D con piattaforme attraversabili, raycast DDA e move-and-slide; controller platform (coyote time, jump buffer, salto variabile, doppio salto, wall jump, dash); mappe voxel con collisioni e raycast 3D e controller platform 3D |
| [input](../src/engine/input) | azioni logiche su tastiera, mouse e gamepad con rimappatura; fronti pressed/released calcolati da campioni puri |
| [audio](../src/engine/audio) | effetti procedurali in stile sfxr, musica chiptune generata in loop, codifica WAV; senza dispositivo audio ogni chiamata è nulla |
| [ui](../src/engine/ui) | interfaccia immediata: pulsanti, interruttori, slider, tessere, pannelli, testo a capo; comandi di disegno registrati e resi in un punto, focus da tastiera e pad, layout a tagli di rettangolo, font pixel incorporato |
| [camera](../src/engine/camera) | camera 2D con zona morta, limiti e scuotimento a "trauma"; camera in prima persona e orbitale in terza persona |
| [fx](../src/engine/fx) | particelle a pool fisso 2D/3D, popup, flash e hit stop |
| [gfx](../src/engine/gfx) | atlanti pixel art incorporati e sprite procedurali, billboard e materiale carta condiviso, shader con sole, luce puntiforme e nebbia, mesh di voxel con facce nascoste rimosse, fondali procedurali |
| [save](../src/engine/save) | JSON versionato scritto in modo atomico, percorsi per utente |
| [teststack](../src/engine/teststack) | solo per i test: su Windows porta lo stack dell'eseguibile a 32 MiB, importato con `import _` |
| [host](../src/engine/host) | finestra, ciclo dei frame, stack di scene, profilo con impostazioni e record, guscio dei minigiochi |

### Interfaccia e input condivisi

La palette semantica vive in `engine/ui.GOTHIC_PALETTE`: nero e ardesia per
le superfici, blu per interazione e focus, rosso per danni, oro per premi.
Il renderer del roguelike usa le stesse costanti; texture delle carte,
materiali 3D e ambienti mantengono le proprie variazioni artistiche.
`hud_panel`, `hud_meter`, `draw_text_fit` e `hud_columns` sono i componenti
comuni. Le prove del catalogo ordinano vita/risorse a sinistra, obiettivo al centro,
punti/progresso a destra. La run conserva pulse, carte e QTE nella propria
HUD, con gli stessi pannelli e colori.

Il menu dà priorità all’ascesa e presenta le prove in righe leggibili. Durante
Combat la barra degli oggetti mostra solo dispositivi o equipaggiamento
presenti; i controlli disabilitati visibili intercettano il mouse, quelli
nascosti non lasciano zone invisibili sulla board. Nel Loot attività e pratica
occupano un piccolo pannello in basso a destra; l’uscita resta libera al centro.
Disegno, hit test e occlusione del mouse usano lo stesso layout.

L’host concede input soltanto alla scena superiore e annulla clic e focus UI
al cambio scena. `input.Resume_Gate` è condiviso dagli adattatori delle prove, incluso il ring:
il primo campione dopo la pausa stabilisce lo stato dei tasti senza generare
nuove pressioni; il fuoco già tenuto resta bloccato fino al rilascio.
I singoli giochi possiedono ancora le code delle azioni da consegnare ai tick.
La run riceve tempo e puntatore da `host.Frame`; non tiene comandi in coda e,
quando perde l’input, pulisce selezioni, trascinamenti e il passo sul secondo
che aspetta il tasto della diagonale, preservando pulse, QTE e stato del mondo.

### Scene

Run e minigiochi del menu sono `host.Scene`: dati propri sull'heap e procedure `update`,
`draw` (canvas), `draw_window` (overlay in coordinate di finestra, come i dadi
3D), `after_present` (screenshot), `suspend` (cede l’input a una scena nuova),
`resume` (la scena sopra è stata chiusa,
con un eventuale `host.Result`) e `destroy`. Lo stack ha due regole: sotto una
scena **modal** non si aggiorna nulla, sotto una scena **opaque** non si
disegna nulla. `push`, `pop`, `replace` e `quit` sono comandi accodati e
applicati a fine frame, quindi nessuna scena viene distrutta mentre è in uso.
`suspend` viene chiamato solo per un push accettato, anche se l’overlay è
modale: i minigiochi entrano in pausa e rilasciano il cursore. Dopo la chiusura
dell’overlay richiedono una ripresa esplicita. I nomi in `resume` e
`Result.minigame` sono validi per il callback anche dopo `destroy` della scena
figlia; vanno copiati se si desidera conservarli oltre quel frame.
I widget di `ui` vanno chiamati in `update`, così stanno sopra al mondo di ogni
scena; il mondo si disegna in `draw`.

Il roguelike è la scena [roguelike_scene.odin](../src/run/roguelike_scene.odin): lo
stato che prima viveva nelle variabili locali di `main` è in
`Roguelike_Session`, sull'heap. Il setup è diviso fra `roguelike_prepare`
(run, stanza e smoke headless, senza finestra) e `roguelike_attach` (risorse
GPU sulla finestra dell'host).

### Contratto dei minigiochi

Un minigioco è un package in [src/minigames](../src/minigames) con due procedure:
`info() -> host.Minigame_Info` (id, titolo, genere, descrizione, comandi,
colore) e `create(host.Minigame_Config) -> host.Scene`. La configurazione porta
seed e il flag `challenge` per le sfide della run, che sono
più brevi e hanno un solo tentativo. Il gioco implementa `Minigame_Hooks`
(`reset`, `step`, `draw`, `score`, `destroy`, musica, cattura del mouse) e
`host.minigame_scene` aggiunge il guscio comune: scheda iniziale con i comandi,
pausa con `Esc` o quando la finestra perde il focus, risultati con stelle,
punteggio e record, riprova. La simulazione di ogni minigioco è pura, a passo
fisso e deterministica per seed e input; i test la guidano senza finestra.
Il catalogo per menu e sfide è in [minigame_registry.odin](../src/activities/minigame_registry.odin).

Tutte le prove usano un unico bilanciamento fisso, equivalente al precedente
livello Normale. Non esistono selettori di difficoltà nel menu o nella
configurazione; i vecchi flag `--easy` e `--hard` non sono più accettati.
Restano la progressione interna di livelli/ondate e la varietà data dal seed.
Le sfide della run mantengono la durata ridotta, senza modificatori legati
alla profondità o alle stanze Elite.

### I minigiochi

| Id | Titolo | Gioco | Comandi principali | Stelle |
|---|---|---|---|---|
| [platform2d](../src/minigames/platform2d) | Torre di Cenere | platform a scorrimento: livelli composti per seed da 22 blocchi verificati da un solver che usa il controller vero; nemici da schiacciare, totem che sparano, blocchi che crollano, bracieri di checkpoint | `A`/`D`, `Spazio` (doppio salto, wall jump), `Shift` scatto, `S` scende | arrivo; 60% delle braci; 90% senza ferite |
| [platform3d](../src/minigames/platform3d) | Guglie Sospese | platform 3D su isole di voxel con distanze tarate sul salto misurato; frammenti d'anima, portale, piattaforme mobili e friabili, spuntoni a tempo, sentinelle | `WASD`, `Spazio`, `Shift`, `Q`/`E` o tasto destro per la camera | portale; tutti i frammenti; senza vite perse |
| [arena](../src/minigames/arena) | Arena delle Braci | twin-stick a ondate in arene simmetriche: cinque nemici con attacchi telegrafati e il Signore delle Braci, potenziamenti, combo fino a x8 | `WASD`, mouse per mirare, clic sinistro, `Spazio` scatto | vittoria; metà vita; combo obiettivo |
| [fps](../src/minigames/fps) | Cripta delle Rune | prima persona in una cripta generata: tre nemici con IA su flow field, bastone runico a mana, rune che aprono il portale, minimappa | mouse, `WASD`, `Shift`, clic sinistro, `Tab` mappa | fuga; tempo sotto il par; vita e mira oltre il 50% |
| [puzzle](../src/minigames/puzzle) | Sigilli della Cripta | Sokoban con ghiaccio e grate a piastre; 17 livelli risolti da un BFS che ne fissa il par; undo/redo e suggerimenti | frecce/`WASD`, `Z` annulla, `Y` ripete, `R` ricomincia, `H` aiuto | entro par; entro 1,5 par; risolto |
| [ring](../src/activities/ring_minigame.odin) | Il Ring delle Ombre | duello 3D continuo contro il campione, guardia, schivata, combo e presa in quattro pose; stessa scena dal menu e dalla run | `WASD`, `1` pugno, `2` pesante, `3` presa, `Spazio` schiva, `Shift` para; pad stick/X/Y/RB/A/LB | vittoria; salute residua almeno 3; almeno 6 |

Ogni pacchetto ha un bot deterministico (`create_autoplay` o `autoplay`) usato
dai test e per le catture, e test headless su determinismo, vincibilità,
sconfitta, validità della generazione su molti seed e soak con input casuali.
`--smoke-minigame=<id>` usa il bot, ignora input live e cattura
`odin_pp_<id>.png` dopo 180 frame di gioco.
Gli avvii diretti `--minigame` e `--smoke-minigame` rispettano esattamente
`--seed`; dal menu ogni nuova partita può usare un nuovo seed.
La cattura verifica avvio e rendering, mentre i bot dei test verificano partite
complete. `--minigame=fps` e il menu avviano la Cripta delle Rune con bastone
e mana. `--fps-lab` conserva soltanto il banco di prova M9 per
raycast/caricatore: non compare nel menu.

### Modificare gli sprite incorporati

I 40 atlanti in [assets/minigames](../assets/minigames) sono i sorgenti grafici
di Arena, Cripta delle Rune, Torre di Cenere e Sigilli della Cripta.
Si modificano direttamente come PNG RGBA: una striscia orizzontale di frame
uguali, conservando ordine, margini trasparenti e alpha. Il catalogo
`SPRITE_ASSETS` nel rispettivo `sprites.odin` dichiara il numero di frame;
la larghezza deve essere divisibile per quel numero. I test controllano le
dimensioni attese. Gli asset sono incorporati con `#load`: dopo una modifica
occorre ricompilare, ma il caricamento non dipende dalla directory di avvio.

`gfx.sprite_asset_image` decodifica e valida l'immagine sulla CPU; chi la
riceve ne possiede la memoria. `gfx.sprite_load` carica la texture con filtro
POINT e libera l'immagine temporanea. Le silhouette bianche dell'Arena vengono
prodotte al caricamento mantenendo l'alpha; FPS conserva il quinto frame di
flash e le trasparenze del Wraith. Non ci sono copie testuali degli stessi
disegni né texture rigenerate per frame. I PNG riproducono esattamente i pixel
precedenti; sprite procedurali e fallback ancora utilizzati restano disponibili.

### Minigiochi nella run

I minigiochi non si aprono più alla fine della stanza: niente pulsanti nel Loot.
Nella run si sbloccano rispettando condizioni precise durante il combattimento,
e ognuno **una sola volta per piano** (`Floor_Secret` in
[tesla_ring.odin](../src/game/tesla_ring.odin); per ora la run è un solo piano).
Dal menu restano tutti giocabili liberamente.

- **Il Ring delle Ombre**: quattro Tesla sugli angoli di un quadrato con
  l'interno di almeno 2x2 caselle (Tesla escluse). Se si attiva il quadrato
  mentre uno o più nemici sono nel campo, al posto della scarica parte il ring
  (vedi [sotto](regole/dispositivi.md#il-ring-delle-ombre-e-gli-sblocchi)).
- **6 RANCH 7**: appena il 6 e il 7 di denari sono insieme in mano, accanto al
  giocatore si apre una nuvoletta di pensiero a fumetto (circa un sesto dello
  schermo) mentre la board resta ferma. Le due carte volano dalla mano
  nell'insegna del ranch, a sinistra e a destra della scritta (6 RANCH 7), le
  porte si aprono ed escono il giocatore e un cowboy a cavallo. Vista dall'alto,
  due corsie divise da una linea nera, il terreno scorre: un countdown da 5
  scocca ogni secondo e a ogni scocco la moneta va a chi preme (`Spazio`,
  `Invio` o clic) più vicino all'istante giusto. Chi arriva a 3 monete vince.
  **Vittoria**: vita piena e +10 oro. **Sconfitta**: nessuna perdita. Le carte
  finiscono negli scarti. Logica in [western.odin](../src/western/western.odin),
  disegno in [western_bubble.odin](../src/render/western_bubble.odin).

Pausa, ologramma, cast, QTE e attività M9 impediscono di aprire una seconda
attività sovrapposta.
