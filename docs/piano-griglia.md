# Piano di lavoro: bersagli, profondità e strutture sulla griglia

Scritto il 23 ottobre 2026 sul ramo `piano-griglia`, partito da
`carte-laboratorio` (commit `2ed075d`: `main` `a766d81` più le carte della
Prova meccaniche). Il ramo non contiene i 1000 crediti iniziali, che stanno su
`crediti-iniziali-casino`.

Il piano raccoglie tre richieste dell'utente, divise in fasi indipendenti:

1. **Bersagli in evidenza.** Mentre scegli una carta, la casella del raggio
   con sopra un nemico che la carta colpirebbe si accende in modo diverso, con
   un effetto che parte dalla casella sotto il nemico.
2. **Profondità della griglia.** Caselle rialzate, gradini, dirupi e caverne.
   Nelle Montagne innevate, una montagna da scalare lungo una spirale di
   gradini fino alla cima.
3. **Strutture su più caselle.** Un modo per posare sulla griglia oggetti ed
   edifici complessi.

Le fasi si eseguono **una alla volta, solo su comando dell'utente**. Le regole
per Claude sono nella sezione 1 e vanno lette prima di ogni fase.

## Stato delle fasi

| Fase | Contenuto | Dipende da | Stato | Commit |
|---|---|---|---|---|
| 1 | Bersagli in evidenza | — | Da fare | — |
| 2 | Altezze nel laboratorio: dati, regole, grafica, puntamento | — | Da fare | — |
| 3 | Altezze nelle spedizioni: renderer, mappe, salvataggi, prestazioni | 2 | Da fare | — |
| 4 | La montagna a spirale delle Montagne innevate | 2, 3 | Da fare | — |
| 5 | Caverne | 2 (3 e 4 per metterle nei biomi) | Da fare | — |
| 6 | Strutture su più caselle: edifici e oggetti complessi | — (meglio dopo la 2) | Da fare | — |
| 7 | Posa delle strutture da parte del giocatore | 6 | Facoltativa: si fa solo se l'utente la conferma | — |

L'ordine segue la richiesta dell'utente: prima l'HUD, poi la profondità, poi
le strutture. Le strutture vengono dopo le altezze perché così possono avere
piani e gradini fin dall'inizio. Se l'utente vuole un altro ordine, basta
nominare la fase: le dipendenze sono nella tabella.

## 1. Comandi per Claude

### 1.1 Come si avvia una fase

L'utente scrive uno di questi comandi:

```text
Esegui la Fase 1 di docs/piano-griglia.md
```

```text
Passa alla prossima fase di docs/piano-griglia.md
```

Ogni fase ha anche il suo comando pronto, alla fine della sua sezione.
«Prossima fase» significa la prima riga della tabella con stato `Da fare`.
Una fase `Facoltativa` si esegue solo se l'utente la nomina.

### 1.2 Regole per ogni fase

1. **Una fase sola.** Esegui solo la fase richiesta. Non iniziare, non
   preparare e non affidare ad altri (sessioni nuove, agenti in background,
   workflow) nessun'altra fase. Questa regola vale anche se la memoria dice
   di concatenare le fasi: per questo piano l'utente ha chiesto di fermarsi
   dopo ognuna.
2. **Prima di scrivere codice.**
   - `git status` deve essere pulito. Lavora sul ramo `piano-griglia`, o su
     quello che indica l'utente. Mai commit su `main`.
   - Rileggi la sezione della fase e controlla che i file e le funzioni citati
     esistano ancora: il piano descrive il codice del 23 ottobre 2026. Se
     qualcosa è cambiato, adatta il lavoro e scrivilo nell'esito della fase.
   - Fai all'utente, **tutte insieme**, le domande della voce «Da chiedere
     prima di iniziare», con la raccomandazione come prima opzione. Aspetta
     le risposte. Se una risposta cambia il progetto, aggiorna prima questo
     documento.
   - Segna la fase `In corso` nella tabella.
3. **Durante la fase** valgono le regole del progetto:
   - rispondi in italiano;
   - le meccaniche nuove si provano prima in Prova meccaniche e passano al
     gioco normale solo dove la fase lo dice;
   - suoni e disegni si creano da codice (`tools/audio`, `tools/art`), mai
     scaricati;
   - i file di prova vanno nella scratchpad, non nel repo;
   - compilatore: `C:\Users\lukeg\OneDrive\Desktop\odin-dev-2026-10\dist\odin.exe`
     (quello nel PATH è troppo vecchio);
   - dopo ogni modifica piccola: `odin check src -vet -strict-style` e i test
     del pacchetto toccato.
4. **Verifica di fine fase.** È obbligatoria; i comandi sono nella sezione
   1.4. Servono:
   - check normale e senza assert;
   - suite completa, confrontata con i fallimenti già noti (sezione 1.5):
     nessun test nuovo deve fallire;
   - build del gioco;
   - smoke del laboratorio con gli atti della fase, guardando davvero le
     catture.
5. **Chiusura.**
   - Aggiorna `CHANGELOG.md`, i documenti che la fase nomina, la tabella
     (stato `Fatta`, commit) e la voce «Esito» della fase.
   - Fai il commit sul ramo, con un messaggio in italiano che finisce con la
     riga `Co-Authored-By` di Claude. Niente push.
6. **Stop.** Scrivi il resoconto con il modello della sezione 1.3 e chiudi
   con la domanda sulla fase successiva. Poi **fermati**. Non iniziare la
   fase dopo, nemmeno in parte, finché l'utente non risponde di sì.
7. **Se qualcosa si blocca** (una decisione che manca, test che non passano,
   un'idea che non regge): fermati, spiega e chiedi. Non saltare a un'altra
   fase per guadagnare tempo.
8. **Se l'utente cambia idea:** prima aggiorna questo documento (la sezione
   della fase e la tabella), poi lavora.

### 1.3 Modello del messaggio di chiusura

```text
Fase N — <titolo>: completata (commit <hash> sul ramo piano-griglia).

Cosa è cambiato: …
Verifiche: check ok (anche senza assert); test <passati>/<totali>, con i soli
fallimenti già noti; build ok; smoke del laboratorio: atti <…>, catture <…>.
Non verificato: …
Decisioni prese: …

Vuoi che passi alla Fase N+1 — <titolo>?
```

Dopo questa domanda il turno finisce.

### 1.4 Comandi delle verifiche

Da Git Bash, nella cartella `odin_pp`. `$S` è la scratchpad della sessione.

```bash
ODIN="/c/Users/lukeg/OneDrive/Desktop/odin-dev-2026-10/dist/odin.exe"
"$ODIN" check src -vet -strict-style
"$ODIN" check src -vet -strict-style -disable-assert
"$ODIN" test src -all-packages -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FULL=false -o:none -out:"$S/tests.exe"
"$ODIN" build src -o:none -out:"$S/odin_pp.exe"
"$S/odin_pp.exe" --smoke-mechanics-lab
```

Le catture finiscono in `build/captures` (cartella ignorata da git). Lo smoke
completo del laboratorio dura più di otto minuti: durante il lavoro si
possono far girare solo gli atti della fase, ma a fine fase va completato.

### 1.5 Fallimenti già noti (Windows, 23 ottobre 2026)

Sono stati misurati su `main` pulito e non dipendono da questo piano.

- **Dodici test falliscono.** Quasi tutti usano percorsi `/private/tmp` che
  su Windows non esistono:
  - `application`: `test_window_focus_loss_flushes_latest_hub_state`;
  - `campaign`: `test_corrupt_save_is_preserved_and_rejection_leaks_nothing`,
    i quattro `test_save_queue_*`,
    `test_save_roundtrip_keeps_campaign_and_live_snapshot`,
    `test_three_slots_keep_independent_stakes_and_discoveries` e
    `test_version_one_checksum_survives_new_fields_and_expanded_arrays`;
  - `expedition`: `test_legacy_80_96_112_slots_resume_exact_tiles_and_keep_original_size`;
  - `render`: `test_expedition_combat_camera_keeps_near_fighters_above_hand_and_pickable`;
  - `run`: `test_running_slot_snapshot_restores_owned_room_pointers`.
- **La suite si interrompe.** Dopo
  `test_running_slot_snapshot_restores_owned_room_pointers` va in crash
  (segmentation fault, exit 139), quindi i test successivi non partono.
  - Il pacchetto `run` si completa escludendo solo quel test, con
    `-define:ODIN_TEST_NAMES=` e l'elenco degli altri test del pacchetto.
  - Gli altri pacchetti si possono lanciare uno per uno con
    `odin test src/<pacchetto>`.
- **Problemi dei pacchetti lanciati da soli:**
  - `game` da solo gira all'infinito (succede, per esempio, con
    `ODIN_TEST_RANDOM_SEED=344123742175708`);
  - `integration` e `combatdebug` da soli si chiudono con exit 127;
  - in `expedition`, da solo, fallisce anche
    `test_inferno_eruption_cracks_floor_after_warning_and_persists_lava`.

  Sono tutti uguali su `main`: questi pacchetti contano solo dentro la suite
  completa.

## 2. Fase 1 — Bersagli in evidenza

### Cosa chiede l'utente

Mentre il giocatore ha una carta in mano e deve decidere se usarla, sulla
griglia compare in blu il raggio d'azione. Oggi però è difficile capire quando
la carta colpirebbe davvero un nemico. Ogni casella del raggio con sopra un
nemico che la carta colpirebbe, o su cui avrebbe effetto, deve accendersi in
un colore molto visibile. In più serve un piccolo effetto che parte dalla
casella sotto il nemico e dice «questo lo puoi colpire».

È una correzione dell'HUD, quindi vale in tutto il gioco (spedizioni e
laboratorio). Si prova prima nella Prova meccaniche.

### Come funziona oggi

Righe del 23 ottobre 2026.

- **Il calcolo del raggio** è in `prepare_card_range_preview`
  (`src/render/card_range_light.odin:38-84`). Lo chiama `draw_tactical_world`
  una volta per frame (`src/render/tactical_renderer.odin:566`).
  - Per le carte che puntano una casella esamina un quadrato di raggio
    `min(cast_range.maximum, 12)` attorno al giocatore. Accende la casella se
    `game.evaluate_card_targeting` la accetta.
  - Per le carte su di sé accende solo la casella del giocatore; l'Onda
    Tossica aggiunge i nemici nella sua area.
  - Una seconda valutazione, sulla casella sotto il mouse, finisce in
    `preview.hover`.
- **I dati** stanno in `Card_Range_Preview` (`card_range_light.odin:16-22`):
  `cells: [25*25]bool` e `hover`, una `Card_Target_Evaluation` con le celle
  colpite, il percorso e fino a 32 `enemy_ids`.
- **Il disegno** avviene in due modi.
  - Nel laboratorio il pavimento si tinge di blu, in `card_range_floor_color`
    (`card_range_light.odin:98-126`).
  - In tutte e due le modalità c'è una luce sopra il pavimento,
    `draw_card_range_light` (`card_range_light.odin:196-241`), chiamata da
    `tactical_renderer.odin:648` prima di minacce e intenti.
  - Nelle spedizioni il pavimento è un piano con shader che non riceve
    l'anteprima (`src/render/expedition_floor.odin:383-419`), quindi lì si
    vede solo la luce.
- **I colori dell'anteprima** (`card_range_light.odin:87-93`) sono raggio blu
  `{76,164,232}`, effetto ambra `{242,183,85}`, bersaglio menta
  `{130,245,213}` e non valido rosso `{242,91,100}`. La pulsazione è
  `0.92+0.08*sin(t*2.4)`, cioè quasi ferma.
- **Quando si vede:** solo con una carta trascinata o selezionata, mai al
  solo passaggio del mouse (`src/run/gameplay_runtime.odin:29-34`).
- **Segni simili esistono già, ma solo per poche carte:**
  - il mirino del Lazzo e del Pinball (`draw_aim_reticle`,
    `src/render/player_charges.odin:243`);
  - i nemici sulla linea del Cannone (`src/render/arsenal.odin:744-757`);
  - tutti i nemici per l'Inondazione (`src/game/flood.odin:233-236`).
- **Attenzione:** un nemico in `enemy_ids` non è per forza colpito. Decide il
  bersaglio di ogni effetto: per esempio lo Scatto elenca i nemici sulla sua
  linea ma non li tocca. Il piano vero degli effetti è
  `build_card_target_plan` (`src/game/card.odin:1884-1921`), che è privato.
  Una sua copia pubblica esiste in `src/combatdebug/telemetry.odin:266-283`.

### Progetto

**Quali nemici si accendono.** Un nemico è «colpibile» se, in questo momento,
esiste almeno una giocata valida della carta che lo tocca davvero: danno,
spinta, stato o qualunque altro effetto. Lo decide il piano degli effetti,
non solo le celle. Restano spenti i nemici:
- fuori gioco;
- nascosti dalla nebbia;
- dietro un muro, per le carte con linea di vista;
- fuori raggio.

Come si comportano i vari tipi di carta:
- **Carte su una casella o su un nemico:** il nemico è su una casella del
  raggio e la giocata lì lo colpisce. È il caso che ha descritto l'utente.
- **Carte ad area, in linea o su tutta la stanza** (Bomba incendiaria,
  Cannone, Inondazione, Buco Nero…): si accendono anche i nemici che l'area
  di una giocata valida prenderebbe. Da confermare con la domanda 2.
- **Carte con esito casuale** (le colonne di Bomb Marley, il dado del
  Dinosauro): nessun segno, perché non si sa chi verrà colpito. Anche questo
  dipende dalla domanda 2.
- **Puntando il mouse su una casella**, i nemici che *quella* giocata
  colpirebbe passano allo stato «agganciato»: il segno si fa più forte e un
  anello si allarga una volta.

**Il calcolo sta nel gioco, non nel renderer.** Serve una funzione pubblica
in `src/game` (per esempio `card_hittable_enemies`), pura e testabile.
- Riusa la stessa valutazione del raggio e il piano degli effetti. Il piano
  va reso pubblico (tutto o in parte), invece di copiarlo una terza volta.
- Il renderer la chiama in `prepare_card_range_preview` e mette il risultato
  in `Card_Range_Preview`: una maschera per cella più l'elenco degli id.
- Costa al massimo 625 valutazioni per frame, quante ne fa già il raggio. Se
  servisse, il risultato si conserva finché non cambiano carta, posizioni e
  battito.

**Il colore: perché non ne basta uno solo.**
- Quattro tinte sono già prese dall'anteprima: blu (raggio), ambra
  (effetto), menta (bersaglio), rosso (non valido).
- Gli scontri si svolgono su piastrelle tinte del colore del bioma, e le
  dodici tinte (`src/expedition/world.odin:77-89`) coprono quasi tutta la
  ruota: rosso del Cyber, arancio del Far West e dell'Inferno, oro
  dell'Egitto, verde della Giungla, azzurro della Neve, magenta della City,
  viola dello Spazio, rosa del Cielo.
- Quindi qualunque tinta fissa si confonde in almeno un bioma.
- Le guide sull'accessibilità dicono di non affidare il significato al solo
  colore, ma di usare anche forma, luminosità e movimento (fonti nella
  sezione 9).

Per questo il segno è fatto di quattro cose insieme:
1. **Luminosità:** il cuore della casella è bianco caldo, il punto più chiaro
   della scena, e pulsa in modo netto (non quasi fermo come oggi).
2. **Contorno d'inchiostro:** un bordo scuro e spesso, nello stile cartoncino
   del gioco (`src/render/comic_outline.odin`), che stacca il bianco da
   qualunque pavimento.
3. **Forma:** un mirino a quattro angoli che respira, lo stesso disegno del
   Lazzo e del Pinball (`draw_aim_reticle`). Così il segno «bersaglio» è uno
   solo in tutto il gioco.
4. **Alone di contrasto:** un alone saturo, di una tinta lontana sia da quella
   del bioma sia dai quattro colori dell'anteprima.
   - Un calcolo del 23 ottobre lo conferma: il **viola elettrico**
     `{170,90,255}` resta ad almeno 40° di tinta da tutti i colori in gioco,
     nel laboratorio e in undici biomi.
   - Nello Spazio, dove il viola è la tinta del bioma, serve il **verde
     acido** `{190,255,60}`.
   - Un test tiene questa distanza minima in tutti i biomi.

**L'effetto visivo** parte dalla casella sotto il nemico:
- la casella pulsa (cuore bianco più alone);
- una colonna di scintille sale dalla casella fino al petto del nemico e
  svanisce. È calcolata dal tempo e dalla posizione, senza stato, come i
  pulviscoli di `draw_diorama_accents` (`src/render/diorama_scene.odin:221`);
- gli angoli del mirino si stringono e si allargano piano;
- quando il mouse aggancia quel nemico, gli angoli si chiudono, la luce è
  piena e un anello si allarga una volta. Si possono riusare `marley_glow` e
  `marley_frame` (`src/render/marley.odin:120,149`).

L'animazione usa il tempo del mondo (`tactical_world_time`), così si ferma
con il mondo. Oggi la luce del raggio usa invece l'orologio degli sprite.

**Dove si disegna:** nella stessa passata della luce del raggio
(`tactical_renderer.odin:648`), subito dopo il blu.
- Così vale nel laboratorio, nelle spedizioni e nel film di Mostra effetto.
- Le scintille vanno in fusione additiva.
- Gli intenti dei nemici restano sopra e leggibili.

### Da chiedere prima di iniziare

1. **Colore.**
   - (Consigliato) Bianco con contorno d'inchiostro e alone viola elettrico,
     verde acido nello Spazio.
   - Oppure un solo colore fisso per tutto (e quale).
   - Oppure un colore che sceglie l'utente.
2. **Quali nemici.**
   - (Consigliato) Tutti quelli che una giocata valida colpirebbe con
     certezza, anche con aree, linee e carte su tutta la stanza; esclusi gli
     effetti casuali.
   - Oppure solo quelli in piedi su una casella del raggio.
   - Oppure anche quelli che una carta casuale *potrebbe* colpire, con un
     segno più tenue.
3. **Lazzo e Pinball.**
   - (Consigliato) Usano il nuovo segno al posto del loro mirino, così il
     linguaggio è uno solo.
   - Oppure tengono il loro.
4. **Anteprima al passaggio del mouse sulla carta.**
   - (Consigliato) Resta come oggi: raggio e bersagli solo con la carta
     trascinata o selezionata.
   - Oppure compaiono già al passaggio del mouse, più tenui.

### Passi

1. **Gioco:** funzione pubblica dei nemici colpibili, con il piano degli
   effetti condiviso, e i suoi test.
2. **Renderer:**
   - i risultati in `Card_Range_Preview`;
   - il segno sulla casella (cuore, contorno, mirino, alone);
   - le scintille;
   - lo stato agganciato.
3. **Colori:** tabella dei colori di contrasto per bioma e per il
   laboratorio, con il suo test.
4. **Laboratorio:** un atto nuovo dello smoke, «bersagli», con queste
   catture:
   - carta da mischia con un nemico vicino;
   - carta a distanza con un nemico dietro un muro (deve restare spento);
   - carta ad area;
   - mouse sopra un bersaglio (agganciato);
   - Cannone e Inondazione.
5. **Spedizione:** catture di uno scontro con una carta selezionata, in almeno
   tre biomi di tinte diverse (Neve, Far West, Giungla). Oggi nessuno smoke di
   spedizione tiene una carta in mano, quindi va aggiunto.
6. **Documenti:**
   - `docs/presentazione.md` (HUD);
   - `docs/regole/carte.md` (targeting);
   - `CHANGELOG.md`.

### Test e verifiche

- **Copertura:** per ogni carta del catalogo, i nemici accesi coincidono con
  il piano degli effetti. Il modello è il test di
  `src/render/card_range_light_test.odin:54`, che già confronta le celle del
  raggio con il targeting del gioco.
- **Casi singoli:**
  - nemico dietro un muro: spento per le carte con linea di vista;
  - fuori raggio, fuori gioco, nascosto dalla nebbia: spento;
  - Scatto (elenca ma non colpisce): spento;
  - Spinta (colpisce): acceso;
  - carte su di sé con area.
- **Aggancio:** lo stato agganciato coincide con `hover.enemy_ids` filtrati dal
  piano degli effetti.
- **Colore:** l'alone resta ad almeno 40° di tinta dagli altri colori in ogni
  bioma.
- **Prestazioni:** con una carta selezionata, il tempo di frame nel
  laboratorio e in spedizione non peggiora in modo visibile.

### Fatto quando

- Nel laboratorio e in spedizione, con qualunque carta selezionata:
  - ogni nemico colpibile ha la casella accesa e le scintille;
  - gli altri restano spenti;
  - puntando il mouse, il bersaglio si aggancia.
- Le catture lo mostrano in tre biomi diversi.
- Le verifiche della sezione 1.4 sono tutte a posto.

### Comando

```text
Esegui la Fase 1 di docs/piano-griglia.md (Bersagli in evidenza). Segui le
regole della sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

*(da compilare a fine fase)*

## 3. Fase 2 — Altezze nel laboratorio

### Cosa chiede l'utente, ed è possibile?

L'utente chiede se la griglia può diventare tridimensionale: non più solo
X e Y ma anche la profondità, con caselle rialzate, caverne in cui entrare e,
nelle Montagne innevate, una montagna da scalare lungo una spirale di
gradini.

**Sì, è possibile**, ma è il lavoro più profondo del piano, perché oggi il
gioco è piatto in ogni sua parte:
- le posizioni hanno due numeri;
- il pavimento è a quota zero;
- il mouse sceglie la casella colpendo il piano a quota zero;
- luci e riflessi delle spedizioni sono pensati per un piano.

Si può fare per gradi senza rompere niente. Ogni casella riceve un'altezza in
**gradini**, e 0 significa «come oggi». Con altezza 0 ovunque il gioco resta
identico, quindi tutti i test esistenti devono continuare a passare senza
modifiche.

Il lavoro è diviso in quattro fasi:
- **Fase 2:** dati, regole, grafica e mouse, nel laboratorio;
- **Fase 3:** le spedizioni;
- **Fase 4:** la montagna;
- **Fase 5:** le caverne.

Un 3D a più piani sovrapposti, cioè passare *sotto* un ponte su cui cammina
qualcun altro, non fa parte di questo piano: vedi la Fase 5.

### Come funziona oggi

- **Dati:**
  - `level.Tile` contiene solo il tipo; `Level` è in
    `src/level/level.odin:7-29`.
  - `set_tile` alza `geometry_revision`, che fa ricostruire la geometria
    delle spedizioni.
  - Esistono già altezze, ma solo disegnate: `Site_Cell.slab_height` e
    `wall_height` (`src/expedition/site_layout.odin:16-17`), con il commento
    «gli attori restano a terra».
- **Spostamenti:** passano tutti da una sola pipeline.
  - `query_entity_movement` e `query_movement_from` chiamano
    `movement_path_blocker`, che vede ogni coppia di caselle (precedente,
    successiva) (`src/game/movement.odin:102-243`).
  - Poi `apply_movement_effect` chiama `trigger_cell_entry` (righe 270-327).
  - La usano Spinta, Scatto, Rampino, le spinte dei nemici, l'Inondazione, il
    Buco Nero, la gravità, il vento, il Lazzo, il Pinball, il Movimento Ombra
    e il Dinosauro.
- **Passo del giocatore:**
  - `try_move_player` (`src/game/room.odin:817-907`);
  - la diagonale (`src/game/tactical_beat.odin:175-214`);
  - la schivata (`src/game/tactical_dodge.odin:26-38`).
- **IA dei nemici:**
  - la ricerca del percorso `rebuild_tactical_enemy_distances`
    (`src/game/enemy_tactical_ai.odin:127-181`) guarda le caselle, non i
    salti tra una e l'altra;
  - `planned_cell_is_available` (`src/game/enemy_intent.odin:108`);
  - `enemy_can_move_to` (`src/game/room.odin:802`).
- **Linea di vista:**
  - `trace_targeting_line` e `targeting_path_blocker`
    (`src/game/targeting.odin:207-271`);
  - `tactical_line_visible` (`src/game/tactical.odin:377-395`);
  - la linea dell'arciere (`src/game/enemy_intent.odin:144`) e il tiro a
    parabola (`src/game/enemy_tactical_ai.odin:66`);
  - una copia nel renderer, `tactical_presentation_opaque`
    (`src/render/tactical_renderer.odin:231-242`);
  - il colpo del First Person Shooter, che segue il pavimento a quota 0
    (`src/game/first_person.odin:322-374`).
- **Grafica del laboratorio:**
  - pavimento in `draw_tactical_tile` (`src/render/diorama_scene.odin:152-189`);
  - muri in `draw_diorama_wall` (righe 118-149) o con il kit
    (`src/render/diorama_kit.odin:177-221`);
  - personaggi a terra più un sollevamento (`src/render/living_card.odin:200-223`);
  - muri interni trasparenti e ordinati per profondità
    (`src/render/tactical_translucency.odin:110-172`);
  - bordo tagliato verso la telecamera (`diorama_scene.odin:27-47`).
- **Mouse:** un raggio contro il piano a quota 0
  (`tactical_renderer.odin:339-349`); personaggi e oggetti hanno la
  precedenza (righe 535-559).
- **Telecamera del laboratorio:** già ruota (trascinando col tasto centrale) e
  fa zoom con la rotella (`src/run/roguelike_scene.odin:260-263`). È utile per
  guardare le altezze.
- **Arena del laboratorio:** è 23×17, scritta a caratteri
  (`src/run/mechanics_practice.odin:32-48`). Il test
  `src/integration/mechanics_lab_test.odin:27-33` la vuole tutta piana e
  calpestabile, quindi le altezze vanno in una seconda arena.

### Regole proposte

- **Gradino.** È l'unità di altezza, disegnata alta 0,12 (una cella misura 1).
  - Regola di disegno dei livelli: dislivelli di 2 o 3 gradini sarebbero
    troppo bassi per leggersi come pareti, quindi le pareti si disegnano
    sempre da almeno 4 gradini (mezza cella).
- **Passo.** Tra due caselle vicine si passa se il dislivello è al massimo
  1 gradino, in salita o in discesa.
  - Da 2 gradini in su c'è una parete, che blocca il passo come un muro.
  - Una scala è una fila di caselle che salgono di 1.
- **Diagonale.** Si passa solo se anche le due caselle d'angolo rispettano il
  passo, così non si tagliano gli spigoli dei dirupi.
- **Spinte e tirate.**
  - Verso una casella più alta di 2 o più gradini, ci si ferma prima, come
    contro un muro (con l'eventuale danno d'urto che il gioco già dà).
  - Verso una casella più bassa di 2 o più gradini, si cade. Danno di caduta
    proposto: dislivello − 1, al massimo 10 (domanda 3).
  - Spingere giù un nemico da un'altura diventa una tattica, come in Triangle
    Strategy.
- **Linea di vista.**
  - Gli occhi sono a 0,7 sopra la propria casella, il bersaglio a 0,5 sopra la
    sua.
  - Una casella intermedia blocca se la sua cima supera la retta tra i due.
  - Dall'alto si vede in basso; dietro un dirupo non si vede.
- **Gittata.** Non cambia: resta Chebyshev o Manhattan sul piano. Un bonus
  d'altura (più gittata o più danno dall'alto, come nei giochi tattici
  citati) si aggiunge solo se l'utente lo vuole (domanda 4).
- **Nemici.** La ricerca del percorso usa la stessa regola di passo. All'inizio
  della fase va controllato quali nemici volano o attraversano (per esempio
  gli spettri gotici).
- **Dati.** Un'altezza per casella (`u8`, da 0 a 255 gradini) in
  `level.Level`.
  - Proposta: una griglia separata accanto alle tessere, con `height_at` e
    `set_height` che alzano `geometry_revision`.
  - In alternativa un campo in `level.Tile`. La griglia separata pesa meno nel
    salvataggio JSON (Fase 3).
  - Una sola funzione del passo, usata da tutti i punti elencati sopra.

### Grafica e mouse nel laboratorio

- **Caselle:** ognuna è disegnata alla sua quota, con facce laterali dove la
  vicina è più bassa, nello stile diorama e con gli stessi contorni. Muri e
  oggetti stanno sopra la casella.
- **Personaggi:** alla quota della loro casella, con salite e discese morbide
  (si riusa il sollevamento).
- **Anteprime:** raggio, bersagli della Fase 1, intenti e minacce si
  disegnano alla quota della casella.
- **Mouse:** il raggio dello schermo attraversa le colonne di caselle passo
  per passo sulla griglia e prende la prima cima o faccia che incontra.
  - È una funzione pura, testabile senza finestra.
  - Oggetti e personaggi continuano ad avere la precedenza.
- **Davanti ai personaggi:** i blocchi alti tra la telecamera e i personaggi
  diventano trasparenti, come i muri interni di oggi.

### Arena di prova

- È una seconda arena della Prova meccaniche, «Altezze», scelta con un tasto
  libero.
  - Il laboratorio usa già F4, F5, F6, F7, F8 e F10; F9 è dell'host e F11
    della finestra. F12 risulta libero, ma va controllato.
- Contiene:
  - un altopiano di 4 gradini con una scala di 4;
  - un dirupo senza scala;
  - una fossa;
  - un pilastro alto per provare la vista;
  - una piccola spirale di prova;
  - nemici su tutti e due i livelli.
- L'arena piatta di oggi resta com'è.

### Da chiedere prima di iniziare

1. **Altezza di un gradino disegnato.** 0,12 è il valore consigliato.
2. **Scendere da un dirupo camminando.**
   - (Consigliato) No, solo con una spinta.
   - Oppure sì, con danno di caduta.
3. **Danno di caduta.**
   - (Consigliato) Dislivello − 1, al massimo 10, uguale per robot e nemici.
   - Oppure un'altra formula.
4. **Bonus d'altura.**
   - (Consigliato) Nessuno per ora.
   - Oppure +1 gittata alle carte a distanza da 4 o più gradini più in alto.
   - Oppure +1 danno dall'alto.
5. **First Person Shooter dove ci sono altezze.**
   - (Consigliato) Adattato alle altezze.
   - Oppure disattivato dove il terreno non è piano.

### Passi

1. Dati delle altezze in `level`, funzioni e regola del passo, con test puri.
2. Movimento, con test:
   - passo, diagonale e schivata;
   - pipeline degli spostamenti: spinte, tirate e cadute con danno;
   - IA: percorso e intenzioni.
3. Linea di vista 3D in tutti i punti elencati, compresa la copia del
   renderer, e nebbia. Con test.
4. Grafica del laboratorio: caselle, facce, personaggi, anteprime e
   trasparenze.
5. Mouse con le altezze, con il test della funzione pura.
6. Arena «Altezze» e atto dello smoke, con catture di:
   - salita e discesa;
   - spinta giù da un'altura;
   - vista bloccata;
   - mouse su una casella alta davanti a una bassa.
7. Documenti:
   - `docs/regole/combattimento.md` (movimento, vista, cadute);
   - `docs/presentazione.md`;
   - `docs/avvio.md` (l'arena);
   - `CHANGELOG.md`.

### Test

- Passo: su e giù di 1 si passa, di 2 no; le diagonali non tagliano gli
  spigoli.
- Spinte: contro una parete ci si ferma; giù da un'altura si cade e il danno è
  quello giusto.
- I nemici usano la scala e girano attorno al dirupo.
- Linea di vista: sopra un gradino sì, dietro un dirupo no, dall'alto in basso
  sì.
- Mouse: una casella alta davanti a una bassa viene scelta per prima.
- Con tutto piatto il comportamento è identico: la suite passa senza toccare i
  test esistenti.

### Fatto quando

- Nell'arena «Altezze» il robot sale e scende le scale.
- Le pareti fermano robot e nemici; le spinte fanno cadere con danno.
- La vista tiene conto dei dislivelli e il mouse sceglie la casella giusta.
- Le anteprime e i bersagli stanno alla quota corretta.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 2 di docs/piano-griglia.md (Altezze nel laboratorio). Segui le
regole della sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

*(da compilare a fine fase)*

## 4. Fase 3 — Altezze nelle spedizioni

### Cosa cambia rispetto alla Fase 2

Le regole della Fase 2 valgono già per gli scontri, che in spedizione si
svolgono sulla stessa mappa (`begin_expedition_encounter`,
`src/game/expedition_combat.odin:47-57`). Restano da fare le parti proprie
delle spedizioni:

- **Esplorazione.** Il robot cammina in modo continuo, non a caselle
  (`roam_step`, `roam_resolve` e `roam_blocked` in
  `src/expedition/roam.odin:49-146`).
  - Le pareti devono fermarlo.
  - L'altezza del robot segue i gradini in modo morbido.
  - Anche il mount deve rispettare le stesse regole.
- **Pattuglie.** Le ricerche di percorso delle pattuglie usano la regola di
  passo: `patrol_move_toward` (`src/expedition/patrol_lure.odin:47-88`) e
  `move_sleeping_group` (`src/expedition/world.odin:338`).
- **Vista.** L'avvistamento usa la linea di vista 3D (`can_see`,
  `src/expedition/world.odin:419-431`).
- **Generatore.** Le altezze si scrivono in `world.generate`
  (`src/expedition/world.odin:138-182`), con geografia fissa.
  - Il test `test_expedition_geography_is_seed_independent_and_all_sites_reachable`
    (`src/expedition/world_test.odin:21`) confronta le altezze tra semi
    diversi.
  - Lo stesso test controlla la raggiungibilità con la regola di passo.
- **Salvataggi.** Le altezze entrano nello `Snapshot`
  (`src/expedition/snapshot.odin`) come una tabella `[MAX_CELLS]` in più,
  controllata da `valid_snapshot`.
  - Nei salvataggi vecchi la chiave manca e vale zero: le spedizioni salvate
    prima restano piatte, coerente con la regola «le spedizioni già salvate
    conservano le celle».
  - Il test di migrazione (`src/expedition/snapshot_migration_test.odin`)
    deve continuare a passare.
  - Il limite del salvataggio è 128 MB: va misurata la crescita del JSON.
- **Pavimento.** Oggi è un piano a quota −0,01 con una texture per cella i cui
  bit sono tutti occupati (`src/render/expedition_floor_data.odin:9-15`), quindi
  le altezze non ci stanno.
  - Proposta: le caselle rialzate diventano terrazze (cima più fianchi),
    cotte nei blocchi di mesh 8×8 che il renderer già ricostruisce quando
    cambia `geometry_revision` (`src/render/expedition_geometry.odin`).
  - Le cime usano lo stesso shader del pavimento, così griglia, terreni e
    avvisi si vedono anche lassù.
  - Le caselle a quota 0 restano sul piano di oggi.
- **Riflessi e luci.**
  - Il riflesso è uno specchio sul piano a quota 0
    (`src/render/expedition_post.odin:186-210`): le terrazze si riflettono
    come l'architettura, ma le loro cime non sono specchi.
  - Le luci dei personaggi sono a quota fissa 0,65
    (`src/render/expedition_lighting.odin:141-235`) e devono seguire
    l'altezza.
- **Retino davanti ai personaggi.** Lo shader che dirada i solidi davanti
  agli attori agisce oggi su tutto ciò che sta sopra quota 0,1
  (`src/render/expedition_material.odin:80-111`). Deve diradare solo ciò che
  sta tra la telecamera e il personaggio, mai la terrazza su cui il
  personaggio sta.
- **Telecamera.** Resta fissa, come vogliono la direzione del gioco e
  l'implementazione di `main`. Deve però:
  - seguire in modo morbido l'altezza del robot, anche nella camera di
    scontro (`src/render/expedition_camera.odin:10-67`);
  - allargare la sfera di taglio (`src/render/tactical_framing.odin:31-44`).
- **Ologramma.** I rilievi si vedono nell'ologramma
  (`src/run/expedition_hologram.odin`).
- **Prestazioni.** Va misurato il benchmark descritto in
  `docs/direzione-implementazione.md` prima e dopo.
  - Obiettivo: nessuna perdita misurabile nei biomi piatti e al massimo il 5%
    in Neve.

### Da chiedere prima di iniziare

1. **Quali biomi hanno rilievi.**
   - (Consigliato) Solo le Montagne innevate per ora: altopiani e scale, più
     lo spazio per la montagna della Fase 4.
   - Oppure anche altri (quali).
2. **Il mount sulle scale.**
   - (Consigliato) Sì.
   - Oppure il robot scende dal mount ai piedi delle scale.
3. **Rilievi nell'ologramma.**
   - (Consigliato) Ombreggiatura per livello.
   - Oppure curve di livello.
4. **Spedizioni salvate prima della fase.**
   - (Consigliato) Restano piatte.
   - Oppure una migrazione che aggiunge i rilievi.

### Passi

1. Altezze nel generatore della Neve, nello `Snapshot` e nei controlli, con i
   test di geografia fissa, raggiungibilità e salvataggio.
2. Esplorazione continua, mount e pattuglie con le altezze.
3. Renderer delle spedizioni:
   - terrazze;
   - personaggi, ombre e luci in quota;
   - retino corretto;
   - telecamera e mouse.
4. Ologramma.
5. Benchmark prima e dopo, con il risultato scritto nell'esito.
6. Catture di esplorazione e di scontro in Neve, compreso uno scontro su due
   livelli.
7. Documenti: `docs/direzione-implementazione.md` (biomi e renderer),
   `docs/presentazione.md`, `CHANGELOG.md`.

### Fatto quando

- In una spedizione nuova delle Montagne innevate ci sono rilievi
  percorribili, in esplorazione e in scontro.
- Le spedizioni salvate prima si caricano piatte e senza errori.
- Le prestazioni rispettano l'obiettivo.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 3 di docs/piano-griglia.md (Altezze nelle spedizioni). Segui le
regole della sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

*(da compilare a fine fase)*

## 5. Fase 4 — La montagna a spirale delle Montagne innevate

### Cosa chiede l'utente

Nel bioma innevato c'è una montagna. Si scala lungo una spirale di gradini
che fa il giro della montagna: il giocatore la percorre tutta e a ogni passo
sale di un gradino, fino alla cima.

### È possibile?

Sì, dopo le Fasi 2 e 3.
- La spirale è un sentiero di caselle, e ogni casella è un gradino più alta
  della precedente.
- Tra un giro e l'altro c'è la roccia della montagna, con un dislivello di
  decine di gradini, quindi i giri non si possono tagliare.
- Nel codice il bioma è `Biome.Snow` (boss «Il Re della Valanga», mount
  Motoslitta). La sua mappa è 192×192 nelle spedizioni nuove (96×96 in quelle
  vecchie).

### Forma proposta

- **Pianta tonda.** Il centro è fisso nella mappa della Neve e deve stare
  lontano da:
  - i 16 siti;
  - la fascia centrale sempre libera (|y − metà| ≤ 3);
  - la striscia d'ingresso (x ≤ 12);
  - tutte posizioni definite in `src/expedition/world.odin:138-182`.

  La posizione esatta si sceglie all'inizio della fase, con una cattura
  dell'ologramma.
- **Misure.** Raggio esterno circa 11 caselle, cima piana di raggio 2 (5×5),
  sentiero largo 2 caselle, 2 giri.
- **Costruzione.**
  - Si segue una spirale in cui il raggio cala in modo uniforme con l'angolo,
    e si traccia il sentiero casella per casella con passi tra caselle che
    si toccano per un lato (mai solo in diagonale).
  - Così ogni gradino tocca il precedente per un lato.
  - Le due caselle affiancate dello stesso gradino hanno la stessa altezza.
- **Altezze.** La base è a 0 e ogni casella del sentiero aggiunge 1.
  - Con 2 giri sono circa 90 gradini, cioè circa 11 di altezza disegnata.
  - Con 1,5 giri sono circa 65.
- **Roccia tra i giri.** Sono caselle non calpestabili, alte quanto il giro di
  sopra più qualche gradino, con l'aspetto dei picchi delle Montagne
  (`src/render/expedition_ascent.odin`).
- **Bordo esterno.** È un dirupo verso il giro di sotto: chi viene spinto
  fuori cade sul giro inferiore, con il danno di caduta della Fase 2. In alcuni
  tratti si può mettere un parapetto (domanda 5).
- **Terreno.** Oggi nel bioma il ghiaccio fa scivolare (`low_gravity_movement`,
  `src/game/movement.odin:40-49`) e la neve dimezza la velocità
  (`src/game/expedition_terrain.odin:70-79`). Il terreno è una funzione pura
  di bioma e posizione, quindi la montagna deve imporre il proprio terreno al
  sentiero (domanda 3).
- **Visibilità.** La telecamera è fissa, e quando il robot è dietro la
  montagna:
  - la roccia tra telecamera e robot si dirada con il retino della Fase 3;
  - il robot resta sempre visibile.

  Si controlla con catture in otto punti del giro. Se il retino non bastasse,
  la rotazione della telecamera a scatti di 90° sarebbe una decisione
  dell'utente: oggi la direzione del gioco vuole la telecamera fissa.
- **Scontri.** Si svolgono sulla stessa mappa: i nemici stanno sul sentiero e
  l'IA lo segue.

### Prima nel laboratorio

- Un'arena «Montagna» della Prova meccaniche, circa 31×31.
- Poi la montagna entra nella mappa del bioma.

### Da chiedere prima di iniziare

1. **Dimensione.**
   - Giri: 1,5, 2 (consigliato) o 3.
   - Larghezza del sentiero: 1 o 2 (consigliato).
2. **In cima.**
   - (Consigliato) Una ricompensa o un segreto.
   - Oppure un POI esistente spostato lassù.
   - Oppure il covo del boss.
3. **Terreno del sentiero.**
   - (Consigliato) Neve battuta a velocità normale.
   - Oppure con tratti di ghiaccio, più rischiosi.
4. **Nemici sulla montagna.**
   - (Consigliato) Una pattuglia a metà salita.
   - Oppure nessuno.
5. **Bordo esterno.**
   - (Consigliato) Libero, con qualche tratto di parapetto.
   - Oppure tutto libero.
   - Oppure tutto protetto.

### Passi

1. **Generatore puro della montagna** (centro, raggi, giri, larghezza), che
   produce altezze e roccia. Test:
   - i gradini consecutivi si toccano e salgono di 1;
   - non ci sono scorciatoie;
   - la cima si raggiunge solo dalla spirale;
   - la forma è uguale a ogni run.
2. **Arena «Montagna»** nel laboratorio, con un atto dello smoke: salita
   completa, spinta giù, robot dietro la montagna.
3. **Montagna nella mappa della Neve** (geografia fissa), senza toccare siti e
   percorsi, con il test di raggiungibilità esistente esteso.
4. **Finiture:** terreno del sentiero, aspetto (picchi, neve, parapetti) e
   ologramma.
5. **Prestazioni** in Neve.
6. **Documenti:** `docs/direzione-implementazione.md`,
   `docs/regole/combattimento.md` e `CHANGELOG.md`.

### Fatto quando

- In una spedizione nuova delle Montagne innevate si sale dalla base alla cima
  lungo la spirale, un gradino a ogni passo, in esplorazione e in scontro.
- Il robot è visibile in ogni punto del giro.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 4 di docs/piano-griglia.md (La montagna a spirale). Segui le
regole della sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

*(da compilare a fine fase)*

## 6. Fase 5 — Caverne

### Cosa chiede l'utente, ed è possibile?

L'utente vuole poter entrare in delle caverne. Si può fare in tre modi, molto
diversi per costo.

- **A. Grotte con volta (consigliato).**
  - Le caselle della grotta sono caselle normali della griglia, scavate sotto
    la roccia (per esempio alla base della montagna), con una volta disegnata
    sopra.
  - Quando il robot entra, la volta si dirada o sparisce, come i piani alti
    degli edifici in XCOM.
  - Sopra la grotta non cammina nessuno, quindi resta valida la regola «una
    casella per posizione» e tutte le regole delle Fasi 2 e 3 funzionano.
  - Costo: medio.
- **B. Interni separati.**
  - L'ingresso porta, con una dissolvenza, in una piccola mappa a parte: la
    grotta, o l'interno di un edificio della Fase 6. Si esce dallo stesso
    ingresso.
  - Oggi una spedizione è una sola mappa e una sola stanza, quindi servono
    più mappe, il salvataggio di ognuna e il passaggio dall'una all'altra.
  - La cosa più vicina che esiste è il Tunnel del Vietnam, che sposta da un
    punto all'altro della stessa mappa (`tunnel_destination`,
    `src/expedition/world.odin:496-508`).
  - Costo: alto.
- **C. Più piani sovrapposti** (gallerie sotto i sentieri, ponti sopra altri
  passaggi).
  - Andrebbero rifatti tutti i sistemi: posizioni a due numeri, salvataggi,
    IA, mouse e renderer.
  - Sconsigliato.

### Progetto, se si sceglie A

- **Dati:** per ogni casella, l'altezza della volta (0 = cielo aperto),
  accanto alle altezze.
- **Vista:** chi è fuori e più in alto non vede dentro, perché la volta blocca
  la linea di vista dall'alto. Dentro si vede come sempre.
- **Grafica:**
  - una volta di roccia sopra le caselle coperte;
  - dissolvenza quando il robot è dentro o sulla soglia;
  - dentro, luce più scura, con le luci dei personaggi;
  - ingresso ad arco.
- **Generatore:** una grotta alla base della montagna della Neve (se la Fase 4
  è fatta) che entra nel nucleo, con qualcosa dentro. Altri biomi solo su
  richiesta.
- **Ologramma:** il contorno delle grotte tratteggiato.

### Da chiedere prima di iniziare

1. **Tipo di grotte.**
   - (Consigliato) A.
   - Oppure B.
   - Oppure A adesso e B più avanti per gli interni degli edifici.
2. **Cosa c'è dentro.**
   - (Consigliato) Un segreto con ricompensa.
   - Oppure nemici.
   - Oppure una scorciatoia.
3. **Dove.**
   - (Consigliato) Solo nella montagna della Neve per ora.
   - Oppure anche altri biomi (quali).

### Passi

1. Dati della volta e linea di vista dall'alto, con test.
2. Grotta di prova nell'arena «Altezze» o «Montagna» del laboratorio, con un
   atto dello smoke (entrata, interno, uscita).
3. Grafica della volta e della dissolvenza, e luce interna.
4. Grotta nella mappa della Neve e nell'ologramma, con salvataggio e
   raggiungibilità.
5. Documenti e `CHANGELOG.md`.

### Fatto quando

- Si entra e si esce dalla grotta: la volta si apre quando il robot è dentro e
  si richiude quando esce.
- Le regole di vista funzionano.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 5 di docs/piano-griglia.md (Caverne). Segui le regole della
sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

*(da compilare a fine fase)*

## 7. Fase 6 — Strutture su più caselle: edifici e oggetti complessi

### Cosa chiede l'utente, ed è possibile?

Un modo per posare sulla griglia oggetti o edifici complessi. **Sì.** Il gioco
ha già edifici su più caselle, i POI delle spedizioni:
- `Site` (`src/expedition/world.odin:20-29`) ha un centro e un orientamento
  da 0 a 3;
- la pianta si calcola casella per casella in `site_cell`
  (`src/expedition/site_layout.odin:86-155`);
- `stamp_site` scrive muri e pavimenti nella griglia (righe 174-180).

Mancano però quattro cose:
- **un modo generico:** ogni pianta oggi è una funzione scritta a mano per
  tipo di POI, e non c'è un catalogo;
- **un controllo di sovrapposizione:** i POI vengono stampati sopra il resto
  senza verifica (`world.odin:157-172`);
- **un tipo di casella intermedio:** `level.Tile` ha solo il tipo (vuoto,
  pavimento, muro, porta, partenza, uscita), quindi non esiste una casella
  che blocchi il passo ma non la vista;
- **un contenitore adatto:** gli oggetti normali della griglia (`Grid_Object`)
  sono al massimo 32 per stanza, e in spedizione tutta la mappa è una stanza
  sola, quindi non vanno bene per gli edifici.

### Progetto

- **Pianta disegnata a caratteri,** sul modello delle «vault» di Dungeon Crawl
  Stone Soup: righe di testo con una legenda, più indicazioni su rotazione e
  specchio (fonti nella sezione 9). Legenda proposta:
  - `#` muro pieno: blocca passo e vista;
  - `=` muretto o recinto: blocca il passo, non la vista;
  - `.` pavimento della struttura;
  - `+` porta o ingresso, che deve stare sul bordo e restare collegato
    all'esterno;
  - `*` punto d'uso: si usa dalle caselle vicine, come i servizi di oggi;
  - spazio: fuori dall'impronta, il terreno resta com'è;
  - `1`…`9`: altezza del pavimento in gradini, se la Fase 2 è fatta.
- **Definizione.** `Structure_Definition` contiene:
  - nome e pianta;
  - rotazioni e specchio ammessi;
  - biomi;
  - stile di disegno;
  - punti d'uso.

  Il catalogo sta nel codice. La parte generica (leggere la pianta, ruotarla,
  controllarla, posarla) va in `src/level`; il catalogo e le istanze vanno
  dove si usano (laboratorio e spedizioni).
- **Istanza.** È fatta da definizione, origine, rotazione e specchio, e sta in
  un elenco della mappa (per esempio `World.structures` con il suo contatore),
  salvato come `World.sites`. Non usa i `Grid_Object`.
- **Effetto sulla griglia.** La posa scrive le caselle (muro, pavimento,
  porta) come fa `stamp_site`.
  - Così passo, vista, IA e anteprime funzionano senza regole nuove.
  - `set_tile` alza `geometry_revision`, e il renderer delle spedizioni
    ricostruisce i blocchi 8×8 toccati.
  - I muretti richiedono un nuovo tipo di casella (domanda 5).
- **Rotazione e specchio.** Una sola funzione testata, a quarti di giro come
  `item_shape` dell'inventario (`src/campaign/inventory.odin:118-150`) e
  `site_rotate` (`site_layout.odin:60-68`).
- **Validità della posa.** La struttura deve:
  - stare dentro la mappa;
  - non sovrapporsi ad altre strutture, POI, ingresso, uscita o servizi;
  - lasciare ogni ingresso raggiungibile;
  - non chiudere sacche di pavimento (si riusa la visita a onde di
    `src/expedition/world_test.odin:21`);
  - con le altezze, poggiare su terreno piano o portare i propri gradini.
- **Disegno.**
  - Nelle spedizioni, muri e pavimenti come quelli dei POI
    (`src/render/expedition_architecture.odin`), cotti nei blocchi 8×8, più
    dettagli propri per tipo (porte, tetti, insegne) costruiti da codice con
    le forme «ink» che già esistono.
  - Nel laboratorio, con i muri del diorama.
  - Il retino davanti al robot vale anche per le strutture alte.
- **Generatore.** Le strutture fanno parte della geografia fissa del bioma:
  le posizioni vengono dal bioma, non dal seme della run.
- **Salvataggi.** Le caselle sono già salvate con la mappa. L'elenco delle
  strutture è un campo nuovo che vale vuoto nei salvataggi vecchi.

### Da chiedere prima di iniziare

1. **Chi posa le strutture.**
   - (Consigliato) Per ora solo il generatore delle mappe.
   - Oppure anche il giocatore: quella è la Fase 7.
2. **Le prime strutture.** Proposta:
   - casetta 4×3 con porta;
   - torre 2×2;
   - recinto;
   - rovina a L;
   - tempietto 7×7 con cortile.
3. **Dove, dopo il laboratorio.**
   - (Consigliato) Un solo bioma di prova, scelto dall'utente.
   - Oppure tutti.
4. **Strutture distruttibili.**
   - (Consigliato) No per ora.
5. **Muretti che fermano il passo ma non la vista.**
   - (Consigliato) Sì, con un tipo di casella nuovo.
6. **Entrare negli edifici.**
   - (Consigliato) Insieme agli interni separati (opzione B della Fase 5), se
     l'utente li sceglie.
   - Altrimenti più avanti.

### Passi

1. `src/level`: tipo della pianta e sua lettura. Gli errori devono essere
   chiari, per esempio:
   - righe di lunghezza diversa;
   - caratteri sconosciuti;
   - ingressi non sul bordo.

   Poi rotazione, specchio, controllo e posa, con test puri.
2. Catalogo `Structure_Definition` con le prime strutture. Un test controlla
   ogni pianta in ogni rotazione ammessa: ingressi sul bordo e pavimento
   collegato.
3. Laboratorio: un'arena con strutture di prova, scelta con il tasto della
   Fase 2 (o con uno libero). Si verifica che i nemici le aggirino e che le
   carte con linea di vista le rispettino.
4. Disegno nel laboratorio e nelle spedizioni.
5. Generatore delle spedizioni (solo i biomi scelti), con controllo di
   sovrapposizione e raggiungibilità, e strutture nell'ologramma.
6. Salvataggio dell'elenco, con test di andata e ritorno e di uno slot vecchio.
7. Atto «strutture» dello smoke, con catture in ogni rotazione.
8. Documenti: `docs/regole/combattimento.md` (ostacoli),
   `docs/direzione-implementazione.md` e `CHANGELOG.md`.

### Test

- Quattro rotazioni riportano la pianta all'originale; l'impronta si
  conserva.
- La posa viene rifiutata se la struttura:
  - esce dalla mappa;
  - si sovrappone a qualcosa;
  - blocca un ingresso;
  - chiude una sacca.
- Passo e vista: il muro blocca entrambi, il muretto solo il passo, la porta
  lascia passare.
- I nemici trovano la strada attorno.
- Salvataggi: andata e ritorno; uno slot vecchio senza strutture si carica.
- Lo stesso bioma ha la stessa geografia a ogni run.

### Fatto quando

- Le strutture del catalogo si posano nel laboratorio e nel bioma scelto, in
  tutte le rotazioni.
- Funzionano con passo, vista, IA e salvataggi.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 6 di docs/piano-griglia.md (Strutture su più caselle). Segui le
regole della sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

*(da compilare a fine fase)*

## 8. Fase 7 — Posa delle strutture da parte del giocatore (facoltativa)

Si fa solo se l'utente, alla Fase 6, dice che anche il giocatore deve poter
posare strutture.

**Cosa c'è già da riusare:**
- la modalità di posa delle carte da orientare, con lo stato `placing` e
  `placement_direction` (`src/run/gameplay_runtime.odin:11-21`), la rotella
  che gira l'oggetto (`src/run/expedition_hand.odin:11-13`) e l'anteprima
  dell'oggetto con le celle valide o rosse (`draw_memory_device_ranges`,
  `src/render/memory_devices.odin:92-112`);
- il trascinamento dell'inventario, dove la rotella o R ruota l'oggetto e un
  controllo dice se ci sta (`src/campaignui/panels.odin:22-28,75-99`).

**Progetto:**
- si sceglie la struttura;
- la sua impronta segue il mouse, verde dove si può posare e rossa dove no;
- la rotella la ruota, un clic la posa, il tasto destro annulla;
- la validità è la stessa funzione della Fase 6.

**Da chiedere prima di iniziare:**
1. Con che cosa si posa: una carta «Costruisci», un oggetto dello zaino o i
   crediti.
2. Quanto dura: per uno scontro, per la spedizione o per sempre.
3. Quante se ne possono posare, e se si possono smontare.
4. Se i nemici possono distruggerle.

**Comando:**

```text
Esegui la Fase 7 di docs/piano-griglia.md (Posa da parte del giocatore). Segui
le regole della sezione 1: fammi prima le domande della fase e fermati alla
fine.
```

**Esito:** *(da compilare a fine fase)*

## 9. Fonti consultate online

Ricerche del 23 ottobre 2026, per le parti che il codice non dice.

- **Colori del raggio d'attacco nei tattici.** In Fire Emblem il blu indica
  dove ci si muove e il rosso dove si attacca; con più attacchi e aree
  servono colori in più:
  [guida Fire Emblem Awakening](https://gamerguides.com/fire-emblem-awakening/guide/intro-and-gameplay/gameplay/movement-and-battles),
  [discussione su GameDev.net](https://gamedev.net/forums/topic/688795-depicting-attackspell-ranges-before-movement/5343086/).
- **Accessibilità del colore.** Il significato non va affidato al solo
  colore, ma anche a forma, icona e movimento; la coppia blu-arancio non
  basta per tutti:
  [colorblind modes](https://www.abratabia.com/game-accessibility/colorblind-modes.php),
  [visual accessibility](https://www.abratabia.com/game-accessibility/visual-accessibility.php),
  [Color Blind Accessibility Manifesto (CACM)](https://cacm.acm.org/opinion/color-blind-accessibility-manifesto),
  [Can I Play That?](https://caniplaythat.com/?p=8897).
- **Leggibilità delle anteprime.** Into the Breach mostra ogni esito prima
  della mossa:
  [Game Developer](https://gamedeveloper.com/game-platforms/road-to-the-igf-subset-games-i-into-the-breach-i-),
  [GDC 2019 su 80.lv](https://80.lv/articles/gdc-2019-an-inside-look-at-into-the-breach).
- **Altezze nei tattici.**
  - Final Fantasy Tactics usa salto orizzontale e verticale:
    [Jump (Tactics)](https://finalfantasy.fandom.com/wiki/Jump_(Tactics)).
  - In Triangle Strategy l'altura dà più danno, e spingere giù dall'alto fa
    molto male:
    [RPGFan](https://www.rpgfan.com/2022/02/19/triangle-strategy-prologue-demo-impressions/),
    [Nintendo](https://www.nintendo.com/us/whatsnew/get-insight-and-tips-for-triangle-strategy-from-the-devs-themselves/).
  - Baldur's Gate 3 dà gittata e bonus a chi sta in alto:
    [High Ground Rules](https://bg3.wiki/wiki/High_Ground_Rules).
- **Vedere dietro gli ostacoli.**
  - Retino (dither), fori attorno al personaggio, contorni, oggetti nascosti:
    [GameDev.net](https://www.gamedev.net/tutorials/programming/general-and-gameplay-programming/hide-objects-blocking-player-view-r3215),
    [Polycount](https://polycount.com/discussion/comment/2794036),
    [Unreal Engine](https://forums.unrealengine.com/t/rafasc-see-through-occlusion-material/2833033).
  - La rotazione della telecamera aiuta ma disorienta:
    [itch.io](https://itch.io/t/225127/issue-enemies-and-terrain-obscured-by-high-elevation-areas-in-the-foreground-no-ability-to-rotate-camera-to-compensate),
    [Steam](https://steamcommunity.com/app/1593030/discussions/0/3722820527902954314).
  - XCOM 2 sceglie con la rotella il piano da guardare:
    [Twinfinite](https://twinfinite.net/guides/xcom-2-how-to-climb-up-buildings-ladders-and-onto-roofs/).
- **Strutture disegnate a caratteri.** Le «vault» di Dungeon Crawl Stone Soup
  hanno glifi, `ORIENT: float`, varianti `SUBST`/`SHUFFLE` e i divieti
  `no_rotate`/`no_hmirror`/`no_vmirror`:
  [syntax.txt](https://raw.githubusercontent.com/crawl/crawl/master/crawl-ref/docs/develop/levels/syntax.txt).
- **raylib.** Raggio dallo schermo e collisioni, utili per il mouse con le
  altezze:
  [Camera Systems in raylib](https://slicker.me/raylib/camera.html).

## 10. Rischi che valgono per tutte le fasi

- **Prestazioni.** I 60 fps costanti non sono ancora garantiti ovunque
  (`docs/direzione-implementazione.md`, «Limiti dichiarati»). Le Fasi 3–6
  misurano prima e dopo.
- **Salvataggi.** Ogni dato nuovo ha un valore predefinito che lascia validi i
  salvataggi vecchi, con test di andata e ritorno.
- **Geografia fissa.** Rilievi, montagna, grotte e strutture sono uguali a ogni
  run dello stesso bioma (il test esistente va esteso).
- **Telecamera fissa delle spedizioni.** È voluta dalla direzione del gioco.
  Il piano non la fa ruotare; se il retino non bastasse, la rotazione a scatti
  è una decisione dell'utente.
- **Test di Windows già rotti** (sezione 1.5).
- **Documento di direzione.** `docs/direzione.md` non è su questo ramo: sta su
  `carte-bomb-marley-inondazione`.
