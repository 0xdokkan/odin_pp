[← Odin PP](../README.md)

## Verifica e smoke test

La Fase 0 del [piano moonshot](piano-moonshot.md) usa il
[runner dedicato](../tools/moonshot/README.md): copie sacrificabili per la scala, compilazioni prima delle
misure, tre ripetizioni seriali e CSV dei fotogrammi con riscaldamento separato. Il passo simulato fisso
è un'opzione del benchmark; i tempi registrati sono quelli reali. Il probe misura anche snapshot e IA,
senza modificare profili o limiti del gioco. Non confrontare direttamente questi percorsi con quelli
storici a tempo variabile: verificare scene, build, durata e tracciati prima di attribuire una differenza.
L'[esito locale della Fase 0](riferimenti/moonshot/fase0-risultati.md) conserva i dati grezzi, i fallimenti
e la validazione separata della chiusura anticipata dello strumento.

Per il laboratorio della pagina, il [resoconto dell'ottimizzazione](riferimenti/moonshot/fase1-prestazioni.md)
affianca ai tempi il confronto della geometria e dei pixel nativi. Confrontare build con le stesse opzioni:
la prova ha rilevato una piccola differenza raster tra `-o:none` e `-o:speed`, assente fra le due versioni
ottimizzate. I risultati del campione a 1080p non certificano l'intera spedizione o l'altro PC.

Il resoconto della sessione del 30 ottobre 2026, con provenienza delle catture,
costi e limiti residui, è in
[`VERIFICA_MOONSHOT.txt`](riferimenti/cartoncino-cartoon/VERIFICA_MOONSHOT.txt).
La direzione complessiva dei prossimi interventi è descritta in
[`PROMPT_MOONSHOT_MONDO_ILLUSTRATO.txt`](riferimenti/cartoncino-cartoon/PROMPT_MOONSHOT_MONDO_ILLUSTRATO.txt).
La prima scena Cyber di questa direzione, con terreno, officina e rifugio,
è verificata in [`VERIFICA_SCENA_CYBER.txt`](riferimenti/cartoncino-cartoon/VERIFICA_SCENA_CYBER.txt).
La fase successiva (cache terreno, HUD e scena West) è descritta in
[`VERIFICA_MONDO_ILLUSTRATO_STEP2.txt`](riferimenti/cartoncino-cartoon/VERIFICA_MONDO_ILLUSTRATO_STEP2.txt).

Le catture native e i report degli scenari sono in `build/captures/`, relativa
alla directory di avvio e già ignorata da Git. I nomi dei file restano stabili
per i confronti. Anche F8 usa questa directory; gli output di telemetria
specificati esplicitamente da CLI mantengono il percorso richiesto.

Per la migrazione cartoon, `--smoke-expedition` conserva le 195 viste del
percorso precedente e aggiunge tre scene con tutti i ruoli Cyber, fermi e con
movimento/IA attivi. `ODIN_PP_SMOKE_ONLY=cartoon` parte da queste scene.
`ODIN_PP_SMOKE_ONLY=palette` cattura soltanto le dodici officine (stadi 39–50)
per confrontare velocemente terreno, architettura e palette, poi termina.
Restano le tre letture HDR/bloom/riflessi e i resize.
Il selettore `ODIN_PP_SMOKE_ONLY=presentation` percorre le prime 27 scene,
compresi HDR, resize e occlusione. `ODIN_PP_SMOKE_ONLY=costumes` aggiunge
33 scene: undici biomi non Cyber, sei ruoli e tre stati di movimento/IA.
Controlla inoltre che gli ID dei sei atlanti di attori, prop e officina Cyber non cambino
durante i ridimensionamenti. Produce dettagli nativi, ritagliati dal framebuffer
senza riscalatura: `odin_pp_cartoncino_robot.png`, `robot_scontro.png`,
`movimento.png` e `nemico_0.png`/`nemico_1.png` (prefisso comune
`odin_pp_cartoncino_`); `ruoli_<fase>.png` e `ruolo_<tipo>_<fase>.png` coprono
le nuove scene. I test di `expedition_cartoon_test.odin` controllano
connessione della sagoma, assenza di una placca sotto i piedi, colori discreti,
animazioni dei ruoli e accordo tra trasparenza e ray picking. Confrontare
anche officine, occlusione, terreni rialzati e biomi; la suite headless non
sostituisce l'ispezione delle catture.

`ODIN_PP_SMOKE_ONLY=cyber-scene` seleziona un percorso nativo di dodici atti:
ingresso nell'officina con WASD, interazione con E, ritorno all'ingresso,
rifugio da fuori/soglia/dentro/fuori, rilievo, combattimento con una carta
selezionata da tastiera e giocata con il mouse, officina da una seconda vista.
I cambi di posizione diretti preparano gli atti separati; i tratti di percorso
usano l'update normale, le collisioni reali e i comandi di esplorazione.
Il controllo verifica le celle raggiunte, l'interazione, il tetto nascosto
all'interno e ripristinato all'esterno, HDR e identità dei sei atlanti.
Le 26 catture `odin_pp_cyber_scene_*.png` includono 14 fotogrammi intermedi
dei tratti percorsi. Baseline e risultato sono archiviati separatamente in
`build/cyber-scene/before/` e `build/cyber-scene/after/`.

`ODIN_PP_SMOKE_ONLY=west-scene` esegue gli stessi dodici atti nel West;
il driver degli edifici sceglie waypoint percorribili, poi invia WASD tramite
l'input reale, aggirando anche i prop fra porta e punto esterno. Le catture
usano il prefisso `odin_pp_west_scene_`. Entrambi i percorsi verificano la
pittura 1024×1024 con undici livelli mip e l'ID stabile della texture.
Il percorso `presentation` controlla lo stesso ID durante i resize.
Gli archivi della seconda fase sono in `build/illustrated-world-step2/`:
`before/`, `pass1/` e `after/`. Non confondere la baseline West parziale
(senza edifici) con il percorso finale completo.

Nel controllo del terreno, verificare le campiture continue in esplorazione
e nelle grotte: nessuna trama a quadri o pannello blu decorativo. I piccoli
fulmini ocra sono la rappresentazione del terreno elettrico reale; gli altri
terreni speciali e la griglia di combattimento mantengono le loro indicazioni.
Le celle del vento Sky usano riccioli pulsanti, senza una griglia decorativa.
Controllare che il pavimento prosegua sotto le piante senza un rettangolo
schiarito, che felci e cristalli tocchino terra e che gli architravi poggino
sulle colonne. Sulle pareti, cercare cuciture puntinate durante il movimento,
cornici sovrapposte e contorni interni nei tratti continui; i motivi devono
restare aderenti alla faccia e attenuarsi quando diventano subpixel.
Confrontare le palette nelle dodici `officina_*.png`, oltre a Cyber, e aprire
anche le catture native di hub, FPS e platform 3D dopo i cambi ai materiali
condivisi.

I test di integrazione dell'applicazione vivono in `src/integration`; il ponte
`src/integration_test.odin` li rende raggiungibili da `-all-packages` senza
introdurre dipendenze inverse nei package di produzione.

[Lo script di verifica](../scripts/check.sh) esegue controllo statico, suite di tutti
i package e link della demo, sia con assert attivi sia con `-disable-assert`.
I binari sono temporanei; `ODIN` può indicare un compilatore alternativo.
Serve anche **Python 3** nel `PATH`: `check.sh` invoca `python3`, mentre
`check.ps1` invoca `python` e richiede che questo comando sia Python 3.
Entrambi verificano prima delle suite il manifest e gli hash del pigmento
officine con `tools/art/build_workshop_stock.py --check`. Il controllo usa
solo la libreria standard Python e non rigenera gli asset; se sono obsoleti,
seguire le [istruzioni del generatore](../tools/art/README.md#pigmento-officine-p1).

Il caricamento dei salvataggi decodifica le struct grandi campo per campo:
il decoder JSON della toolchain fissata accumula altrimenti sullo stack una
maschera proporzionale alla dimensione della struct per ogni chiave. I test
dell'hub e del ripristino delle spedizioni coprono le mappe a piani con lo
stack predefinito, anche su macOS.

La [CI](../.github/workflows/check.yml) esegue gli stessi script completi su
macOS ARM64 e Windows x64, per ogni pull request e push su `main`; è disponibile
anche l'avvio manuale. La toolchain è la release ufficiale Odin `dev-2026-10`
(commit `84bc3fc2100b0f7880a3af37f71bccdcda41c6f9`), con checksum degli archivi
fissati nel workflow. Windows inizializza MSVC e Windows SDK già presenti sul
runner. La CI controlla, testa e collega entrambe le configurazioni degli
assert; gli smoke nella finestra 3D restano una verifica locale separata.

```sh
sh scripts/check.sh
sh scripts/check.sh --headless
sh scripts/check.sh --quick --headless
```

La modalità **completa**, predefinita e da eseguire prima del merge, mantiene
tutti i seed delle matrici di generazione, il catalogo dei chunk platform,
le simulazioni lunghe e le due configurazioni degli assert. **`--quick`** serve
durante lo sviluppo: controlla tutti i package con assert attivi, selezionando
scenari rappresentativi nelle matrici costose. `--headless` omette le build
della demo con finestra e si può combinare con entrambi i profili, in qualunque
ordine. In PowerShell gli equivalenti sono `-Quick` e `-Headless`.

La selezione rapida conserva:

- 135 combinazioni della generazione di stanze; la completa esamina 4.096 seed
  per selezionare 432 combinazioni distinte di nodo, profondità e transizione
  fra famiglie, con copertura verificata. Restano le matrici dedicate alle
  arene progressive e agli spawn, i seed di regressione e i golden vector;
- due platform generati, uno libero e uno sfida: lo stesso grafo verifica
  raggiungibilità e completamento con il controller reale; la completa verifica
  anche tutti i chunk e conserva i cinque seed originari;
- il catalogo completo degli effetti delle carte e tutti gli upgrade; nella
  finestra che li ospita, prove 3D di Strike, Fate Strike, Tesla, Movimento
  Ombra, Canna da Pesca e First Person, al livello base e massimo;
- tutte le regressioni locali su input, softlock, pause, QTE, timeline, deck,
  salvataggi e transizioni. Solo sei simulazioni lunghe dei minigiochi e la
  risoluzione esaustiva dei chunk platform sono escluse dalla rapida.

Il flag Odin `-define:ODIN_TEST_FULL=false` seleziona gli stessi casi nei comandi
manuali. Senza flag, anche `odin test` mantiene la suite completa. Non vengono
cambiate regole del gioco, seed o generatori di produzione per velocizzare i test.

I comandi utili per una verifica mirata sono:

```sh
odin check src -vet -strict-style
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -o:none -out:/tmp/odin-pp-tests
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FULL=false -o:none -out:/tmp/odin-pp-tests-quick
odin test src/game -o:none -out:/tmp/odin-pp-game-tests
odin test src/render -o:none -out:/tmp/odin-pp-render-tests
odin test src/combatdebug -o:none -out:/tmp/odin-pp-combatdebug-tests
odin test src/engine -o:none -out:/tmp/odin-pp-engine-tests
odin test src/fight -o:none -out:/tmp/odin-pp-fight-tests
odin test src/shooter -o:none -out:/tmp/odin-pp-shooter-tests
```

Specificare sempre `-out` nei test: il runner crea e rimuove il proprio binario;
un output predefinito nella repo può interferire con una build del gioco omonima.
`-o:none` evita il lungo passaggio di ottimizzazione durante lo sviluppo.
Anche `src/engine/grid`, `src/level` e `src/engine/view` hanno test dedicati. I test del renderer
verificano la logica testabile; gli smoke con finestra verificano anche la resa
GPU. Un `libraylib.a` contenente `version https://git-lfs.github.com/spec/v1` è
un puntatore LFS, non un archivio collegabile: occorrono gli artefatti nativi
della toolchain. Era il limite dell'ambiente Linux dell'audit storico.

Gli smoke si eseguono con `odin run src -o:none -- <flag>`, uno alla volta. Quelli
grafici salvano lo screenshot nella directory di avvio e chiudono la finestra;
le immagini sono output rigenerabili, non prerequisiti del checkout.

| Flag | Screenshot / verifica |
|---|---|
| `--smoke-m9-view` | collisioni continue, vittoria contro l'IA del ring, quattro pose della presa, replay esatto, FPS con telegraph/ricarica/vittoria e ritorno; screenshot `odin_pp_m9_arena.png`, `ring.png`, `ring_grab_0.png`–`ring_grab_3.png`, `tools.png`, `fps.png` (prefisso comune `odin_pp_m9_`) |
| `--smoke-arenas-view` | quattro fasce di arene reali, combattimento, ologramma, Loot e cambio stanza; screenshot `odin_pp_arenas_*.png` |
| `--smoke-m8-view` | dispositivi con APRI IL RING, campo, tag match, ritorno Loot: `odin_pp_m8_d4.png`, `devices`, `mega_combo`, `character`, `loot`, `tag_ring`, `next_room` (tutti con prefisso `odin_pp_m8_` e suffisso `.png`) |
| `--smoke-western` | 6 RANCH 7 dalla mano al premio: `odin_pp_western_hand.png`, `cards`, `sign`, `gate`, `riders`, `ride`, `grab`, `win`, `reward` (prefisso `odin_pp_western_`) |
| `--smoke-mechanics-lab` | Prova meccaniche in 3D: mano e testi, status, intenti, colpi, pozze, incendio, cariche, Lazzo, Pinball, FPS, Inondazione, Bomb Marley, bersagli in evidenza (`odin_pp_mechanics_lab_hit_*.png`; con `ODIN_PP_LAB_ONLY=hit_marks` gira solo quell'atto), altezze (arena di F3: scala, altopiano, dirupo, gittata dall'alto e caduta, `odin_pp_mechanics_lab_heights_*.png`; `ODIN_PP_LAB_ONLY=heights`), Cannone (palla e laser), Buco Nero, i quattro dinosauri e pesca, le quattro facce di Benvenuti a Napoli e il suo bastone in terza persona (`ODIN_PP_LAB_ONLY=napoli`, `odin_pp_napoli_dice_*.png`, `odin_pp_napoli_club_*.png`); replay e screenshot `odin_pp_mechanics_lab_*.png` / `odin_pp_living_*.png` |
| `--smoke-effect-window` | Mostra effetto: ingressi da ogni menu, isolamento della run, chiusura senza click-through, testi, film delle carte e tempi dei frame. `-define:EFFECT_SMOKE_CARDS=,Strike,Pinball,` limita le carte filmate. Screenshot `odin_pp_effect_*.png` |
| `--smoke-playtest` | headless: al massimo venti decisioni, `odin_pp_playtest_smoke.json` |

Gli smoke attuali controllano anche il completamento del replay;
le preview non consumano RNG. Per i report interattivi vedere [Telemetria](#telemetria-e-playtest).
Le regressioni M9 verificano simulazione invariata a 30/60/144 FPS, collisioni
e raggi senza attraversamenti, finestre delle mosse, parata/schivata/prese,
replay esatto, input al cambio focus e transizioni fra run e attività.
[m9_transition_test.odin](../src/integration/m9_transition_test.odin) copre anche ricompense
una sola volta, isolamento della pratica e chiusura senza click-through.
[effect_window_test.odin](../src/integration/effect_window_test.odin) e
[card_demo_test.odin](../src/integration/card_demo_test.odin) fanno lo stesso per
[Mostra effetto](presentazione.md#mostra-effetto): ingressi, run ferma, rifiuti, chiusura senza
click-through e il film di ogni carta a ogni livello, che deve mostrare quello
che la carta promette.

## Telemetria e playtest

Sorgenti: [telemetry.odin](../src/combatdebug/telemetry.odin),
[session.odin](../src/combatdebug/session.odin), [report.odin](../src/combatdebug/report.odin),
[kiting.odin](../src/combatdebug/kiting.odin) e [playtest_session.odin](../src/run/playtest_session.odin).

Il dispatcher condiviso da input, controller e driver di prova cattura uno snapshot
pre-comando e un descrittore della carta, esegue l'API autorevole e passa
esito e Room finale a `observe_command_detailed`. Il tipo è esplicito:
un Move contro un nemico viene classificato Bump_Attack prima della risoluzione,
anche se il colpo termina il combattimento.

Un rifiuto incrementa attempted/rejected senza leggere un log precedente.
Per i commit si aggrega `Room.recent_events`, verificando marker Pulse_Advanced
e delta del pulse; perdite o mismatch rendono il sample incompleto.
Il perimetro della carta va da Card_Played alla sua uscita da Resolving,
separando danno diretto, reazioni, status, trappole e risposta nemica.
`has_status_cause/status_cause` attribuisce i tick anche quando Shield assorbe tutto.

Le metriche contano comandi e carte, pulse, target previsti/effettivi, danni
subiti/diretti/indiretti/assorbiti, energia spesa/recuperata/sprecata, Poison,
Refocus, movimento forzato e hazard. I campi `object_hazard_*` distinguono
trigger e danno effettivo su player e nemici. Il confronto bump/Strike/Heavy
Blow considera solo decisioni in cui tutte e tre le opzioni erano disponibili.

`Playtest_Session` apre e chiude ogni fight una volta sola; il giro Loot non
contamina i campioni. Il JSON ha `schema_version = 1`, seed, outcome Victory,
Defeat o Abandoned, completezza, metadata del nodo, aggregati e sample ordinati.
Usa interi e booleani, senza timestamp, hash map o dati del renderer: stessa
sequenza e seed producono gli stessi byte.

```sh
odin run src -o:none -- --seed=0xC0FFEE --playtest-report
odin run src -o:none -- --playtest-output=/percorso/sessione.json
odin run src -o:none -- --smoke-playtest
```

Il report interattivo viene scritto a fine run, restart o chiusura come
`odin_pp_playtest_<seed>.json`; creazione esclusiva e suffissi `_1`, `_2`, ecc.
proteggono anche sessioni concorrenti. Il percorso esplicito è una base con la
stessa protezione; la directory deve esistere. Il nome effettivo è stampato
fuori dal JSON. Lo smoke headless non inizializza Raylib e sovrascrive invece
intenzionalmente `odin_pp_playtest_smoke.json` o il file esatto scelto con output.

La policy headless considera North, East, South, West e Wait. Valida le mosse
con Movement_Query, tratta Wait separatamente, minimizza danno da hazard,
evita le celle minacciate, massimizza distanza minima e somma delle distanze,
poi preferisce la direzione precedente e l'ordine fisso dei candidati.
Lo smoke esegue al massimo venti decisioni e completa il tempo dell’ultima
azione. Osserva separatamente beat, QTE e recuperi; fine fight e sconfitta
lo concludono prima, mentre un rifiuto inatteso o la mancata progressione
sono errori espliciti.

Il report del clock `*.m7_N.json` e `odin_pp_m7_stress.json` usano invece
`schema_version = 3`: non contengono più il flag o le run Classic. Lo stress
verifica dieci preset e due run tattiche terminali, ripetuti per controllarne
il determinismo; non è una misura del bilanciamento umano.

### Domande per il bilanciamento

| Azione melee base | Danno | Energia | Durata |
|---|---:|---:|---:|
| bump attack | 2 | 0 | 1 s |
| Strike | 3, +2 su esposto | 1 | 2 s di cast |
| Heavy Blow | 4 e Stagger | 2 | 3 s di cast |

Il valore comprende danno, interruzione e tempo della finestra consumato,
oltre all’energia. Prima di aggiungere nuove primitive, confrontare
più run riproducibili e misurare:

- scelta fra bump, Strike e Heavy Blow, danno subito ed energia sprecata;
- quanti Venom Needle ottengono almeno due tick prima della morte del bersaglio;
- numero medio di nemici colpiti da Caustic Bloom;
- quante Purifying Guard rimuovono davvero Poison;
- Volatile Study giocata o exhaustata da Refocus, rispetto a Battle Focus;
- spinte/pull che attivano hazard o invalidano intenti;
- Refocus come ricerca di una risposta o semplice recupero di una mano debole.

Root, coni e costi dinamici devono rispondere a un bisogno ripetuto dei
playtest, non alla sola possibilità tecnica di aggiungerli.

### Verifica del sole e del redesign

[`VERIFICA_REDESIGN_SOLE.txt`](riferimenti/cartoncino-cartoon/VERIFICA_REDESIGN_SOLE.txt)
distingue sorgenti integrati, verifiche concluse e misure in corso. Una compilazione
Odin non sostituisce il caricamento GLSL sulla GPU.

Eseguire gli smoke in directory separate: `build/captures/` è relativo alla
directory di avvio. Creare il link agli asset solo quando non esiste:
`[ -e assets ] || ln -s /Users/dokkan/Dev/odin_pp/assets assets`.
Non usare `ln -sf` su un link esistente. Tenere attivo lo schermo durante
le catture: lo stop può impedire l'apertura della finestra.

Oltre a `palette`, `cartoon`, `costumes`, `presentation`, `cyber-scene` e
`west-scene`, eseguire lo smoke completo. Verificare uscita regolare,
`RENDER CHECK` sopra le soglie e assenza di `Expedition sun unavailable`.
Aprire grotte, complessi, ponti, rete, montagna, rilievi, edifici e scontri.
Il selettore `sun-fps` esercita la prima persona reale con il sole e il ritorno
alla vista dall'alto. La verifica A è conclusa sulla build con il fix deck;
lo smoke completo è passato anche nelle build integrate v2 ed E attiva v3.
Gli esiti appartengono agli hash dei binari nei rispettivi `run.json`;
non valgono automaticamente per modifiche successive.
L'ologramma usa una pipeline indipendente.

Controllare ombre ancorate, assenza di acne, bordo mappa sfumato e tetto
escluso dai caster all'interno. La dissolvenza alla soglia può conservare
l'ombra della copertura ancora presente; il criterio funzionale è
`roof=false` dentro e il ritorno dell'ombra fuori. Le catture ogni 30 frame
mostrano salti grandi ma non certificano il tremolio fra frame adiacenti.
Conservare anche verifiche di resize e identità degli atlanti.

Per l'A/B compilare gli stessi sorgenti con e senza
`-define:EXPEDITION_SUN=false`, separatamente in `-o:none` e `-o:speed`.
Canvas 1920×1080, vsync disattivata, 60 frame di riscaldamento, 600 campioni
per officine e scontro; i percorsi in movimento conservano 240 campioni.
Alternare A,B,B,A,A,B e pubblicare tutte le corse, media/p95/massimo,
`CPU SUBMISSION` e `CPU WORLD`. Scene 25–26, 39–40 e 195. Il target resta
p95 ≤ 16,7 ms a 1080p sul M1, da verificare con i risultati.

I sorgenti antecedenti al sole sono stati ritrovati in
`build/camera-horizon/before/sources`. Il manifest della copia strumentata
`build/redesign-sole/session-20261103/bench-sources/historical/manifest.json`
registra origine, hash e sole modifiche di misura. Confrontare storico,
attuale senza sole e attuale con sole nella stessa sessione.
`B1-RESULTS.txt` nella directory di sessione contiene le 18 corse della
baseline conservata, tutte incluse: la regressione persiste senza sole,
ma questi dati non isolano una causa e non misurano il redesign finale.
Le medie dei tre p95 non sono percentili dei campioni aggregati. I tratti
25/26 usano `dt` reale e non garantiscono traiettorie identiche fra build;
non confonderli con il diagnostico di continuità a passo fisso.
`B-FINAL-RESULTS.txt` contiene tutte le 42 corse di follow-up, incluse
le dodici del confronto integrato. Nessun p95 raggiunge 16,67 ms;
la regressione del tratto montato debug resta aperta e viene indagata con
sei corse aggiuntive a `dt` fisso, senza eliminare i risultati originali.

Per P1, `python3 tools/art/build_workshop_stock.py --check` verifica
manifest e hash; `--verify` rigenera il pigmento dalle routine Odin e
confronta integralmente pixel e roundtrip PNG. La validità del contenuto
non misura il costo di decode/upload o la pausa del primo caricamento.

Per verificare l'integrazione C–G ricontrollare celle e confini dei blocchi, ownership
delle cache, budget edifici, fioriere e angoli. Poi confronti palette,
percorsi Cyber/West e Snow/Jungle/Egypt/Inferno per gli accumuli. Provare E
anche con tinte permanenti del bioma, flash e attori parzialmente in ombra.
E al 15% è stata approvata dall'utente ed è attiva di default; il flag
`-define:EXPEDITION_ACTOR_SHADOW=false` mantiene disponibile il confronto.

`objects` confronta sei tipi × cinque biomi × due rotazioni, con originali
960×540 e nativi; `objects-fallback` forza la cache fallita sui dodici casi
Cyber. Il test degli assi verifica entrambi i tappi, anche dopo specchio.
Strict check e renderer 477/477 con E attiva passano dopo questo fix;
il quick globale 1885/1885 precede l'aggiunta del nuovo test degli assi.

`cyber-walk` percorre una sola mappa con input reali, senza teletrasporti
fra waypoint: pressa/interazione, rifugio dentro/fuori, rilievo e scontro
con passo e carta confermati. La prova v2 termina in 60,58 s simulati,
37,58 s in movimento, 89,74 s reali dopo primo present e 10,12 s d'avvio.
È una sessione continua con soste; `cyber-scene` conserva invece i quadri
con setup separati e da solo non certifica questo percorso.


## Moonshot — Fase 1, pagina continua

`odin build src -o:none -out:build/odin-page-lab`, poi `build/odin-page-lab --page-lab` per il laboratorio
o `--smoke-page-lab` per 25 viste e tre sequenze da 12 immagini nella versione con stampa. Vedere
[risultati e limiti](riferimenti/moonshot/fase1-risultati.md) e [protocollo](../tools/moonshot/README.md#fase-1--laboratorio-della-pagina).
Verificare anche `--smoke-menu`, l'accesso dal menu, pausa/cursore, tasto centrale, selezione e Osserva,
ritorno al menu e prima persona. Gli snapshot di stato delle mappe grandi sono un problema separato dalle catture.

Superati: strict check ordinario e driver con `PAGE_LAB_BENCHMARK=true`; renderer 526/526, run 25/25,
application 23/23, strumenti Python 17/17. Le immagini sono native, le sequenze campionate a 3 immagini/s;
non sostituiscono il giudizio dell'utente sul movimento dal vivo. Tre repliche M1 ottimizzate a 1920×1080
complete: budget p95 ≤16,7 ms non raggiunto stabilmente, misure Windows ancora assenti.


### Cartoncino con stampa e capacità degli snapshot

La prova aggiornata usa il prefisso `odin_pp_page_cardboard_`: 25 viste e 36 fotogrammi di sequenza.
Controllare la coppia idle A/B (stessa sagoma, occhi diversi), `P` per il supporto senza disegno, il retro,
la montata e la morte. Durante quest'ultima il disegno conserva corpo e proporzioni sul foglio: la piega
fisica porta la figura al suolo. I dati del primo campione restano come riferimento storico.

Il [resoconto aggiornato](riferimenti/moonshot/fase1-cartoncino-capacita.md) distingue prove grafiche,
roundtrip dei salvataggi e puzzle IA. Il [probe di capacità](../tools/moonshot/snapshot_capacity/main.odin)
scrive solo il percorso esplicito fornito, rifiuta file già esistenti e non apre gli slot del profilo.
I test di persistenza coprono copie autonome del job asincrono, compatibilità v1, indici oltre 65535,
budget di lettura/decodifica e rollback del ripristino; i controlli di memoria devono restare senza leak.

Esito finale dell'estensione: strict check, campaign31/31, expedition78/78 con cleanup verificato a parte,
advisor2/2, run27/27, application23/23, renderer538/538, Python21/21 e integrazione quick ottimizzata220/220.
Smoke nativo61/61 e tre repliche grafiche complete; p95 salita17,29–21,22ms, quindi budget60FPS ancora aperto.
La suite di integrazione debug interrotta resta nei log e non è conteggiata fra gli esiti positivi.


### Polish della spedizione: pausa e input accodati

Il laboratorio di gameplay A/B/C è stato rimosso su richiesta dell’utente. Il laboratorio grafico della pagina,
il cartoncino e i fix della capacità degli snapshot restano. L’effetto grafico è conservato nel proprio percorso;
questa pulizia non dichiara una sua integrazione completa nella spedizione.

Il primo fix applica alla pausa della spedizione il contratto già usato dal controller tattico:
svuotare comando pendente e movimento mantenuto. `test_expedition_pause_drops_buffered_step_before_resume`
accoda un passo nel dispatcher reale durante un’azione, entra/esce dalla pausa e verifica che il vecchio
passo non venga emesso, mentre un nuovo input funziona. Confronta anche il Player completo e la fase.
La regressione fallisce prima della modifica e passa dopo, con memoria controllata.
Log e manifest in `build/moonshot/expedition-polish/pause-before.*` e `pause-after.*`.

Prova manuale mirata nel gioco: durante uno scontro, avviare una carta, accodare un passo, premere P o Esc,
rilasciare tutto e riprendere. L’azione già avviata può concludersi, ma il passo precedente alla pausa non deve
partire. È una verifica da svolgere nella finestra della spedizione: il test automatico non finge di averla eseguita.

Verifica finale dopo la rimozione: **run 28/28, application 23/23**, strict e memoria controllata;
compilazione completa `-o:none` riuscita, smoke del menu nativo concluso con codice zero e cattura ispezionata.
Nessun riferimento al laboratorio A/B/C residuo in sorgenti o strumenti. Diciassette file del cartoncino,
degli snapshot e dei puzzle IA di capacità confrontati byte per byte con la copia precedente risultano identici.
Log in `build/moonshot/expedition-polish/`; nessuna misura di prestazioni è dedotta dalla build debug.

### Polish del 6 novembre: pannelli, focus, IA e rossore dei nemici

Il gioco verificato resta la spedizione con esplorazione libera e scontro tattico a griglia.
I pannelli consumano l’intero fotogramma di apertura/chiusura: comandi accodati, trascinamento carte,
movimento, mouse trattenuto e mira non passano al mondo. La mappa aperta e richiusa nello stesso
fotogramma segue lo stesso contratto. I tempi già previsti per zaino, mappa e scheda personaggio
restano distinti; il test del lancio in corso verifica che filtrare gli input non fermi il suo clock.
In prima persona il pannello libera il cursore e il grilletto; dopo la chiusura un clic già trattenuto
richiede rilascio e nuova pressione. La perdita del focus usa il percorso reale della scena.

**IA aggiornata:** il puzzle `test_expedition_consumable_releases_held_advice_but_input_boundaries_do_not`
usa il consumabile attraverso la UI dello zaino e verifica il ricalcolo dopo la cura. Aprire un
pannello, sospendere il focus o tentare un uso rifiutato non scarta un consiglio ancora valido.
Non sono introdotti nuovi campi nello stato simulato, nuove mosse o nuovi valori degli oggetti.

Il rossore era già collegato al countdown dell’intento: rosso per attacco/carica, viola per
bomba/protezione, picco negli ultimi 0,25 s. La correzione propaga la tinta anche alla stampa
e al bordo di carta dei costumi, che prima potevano coprirla. I test coprono countdown reale
con frazione del battito, pausa del segnale attivo, dissolvenza, palette neutra, inchiostro e alpha.

**Esiti automatici:** run **36/36**, application **23/23**, renderer pertinente **6/6**;
integrazione IA/focus **3/3**, cattura del cursore FPS **1/1**, tutti con `-vet -strict-style`
e controllo di memoria. Il puzzle IA è incluso nei 36 test run ed è passato anche isolatamente.
Build completa `-o:none` riuscita. Log in `build/moonshot/expedition-polish/`, con suffisso
`20261106` e `render-glow-tests.log`; le prime regressioni degli input fallite prima della
correzione restano nella sottocartella `20261106/`.

Prova nativa ripetibile, su campagna temporanea senza slot del profilo:

```sh
odin build src -o:none -vet -strict-style -out:build/odin-pp-polish
ODIN_PP_SMOKE_ONLY=polish-input-glow build/odin-pp-polish --smoke-expedition
```

Il percorso apre/chiude zaino, personaggio e mappa, simula la perdita del focus e cattura tre
istanti di un attacco scelto dall’IA del nemico. Il setup usa un Chaser in primo piano nel West:
nessun teletrasporto o countdown imposto durante l’attacco. Le catture native complete e di
dettaglio sono `build/captures/odin_pp_polish_glow_West_{0,1,2}[_detail].png`.
La prima corsa con sei nemici è conservata in `build/moonshot/expedition-polish/native-r1/`:
è conclusa correttamente, ma il Chaser finiva dietro al robot e rendeva poco leggibile il confronto.
La corsa finale con un solo nemico è conclusa con codice zero e catture ispezionate: a 2,466666 s,
1,5 s e 0,233333 s dal colpo, l’intensità registrata è rispettivamente 0,266406, 0,431821 e 1.
Il bordo e la stampa diventano più rossi; il log `polish-native-20261106.log` registra anche tutte
le aperture/chiusure e il focus, senza comandi pendenti. È lo stesso intento, seguito fino al picco.
Questa prova grafica non è una misura di FPS né una prova esaustiva di tutti i biomi o delle armi.

### Carte e leggibilità degli scontri: passo successivo del 6 novembre

Intervento limitato alla spedizione e alle regole tattiche esistenti. Il nuovo cartoncino resta nel
laboratorio grafico; il polish dell’esplorazione e la sua integrazione nel gioco sono passi successivi.

| Problema riprodotto | Correzione e prova |
|---|---|
| Destro annullava la selezione ma lasciava partire la carta accodata | `src/run/beat_input.odin:84`: elimina il solo `Play_Card` pendente. I test verificano carta, energia, salute e clock invariati, altri comandi preservati e nuovo input valido. |
| Cambiando carta rimaneva l’orientamento del piazzamento precedente | `src/run/gameplay_runtime.odin:39`: reset al cambio e sincronizzazione della nuova anteprima anche nei ritorni anticipati; tastiera, trascinamento e rotella coperti. |
| La mano chiedeva un bersaglio senza spiegare il rifiuto | `src/render/card_target_hint.odin:9`: motivo dalla query canonica, priorità all’energia insufficiente; conserva Pinball e spinta opzionale. |
| Inondazione orientata poteva mostrare un bersaglio diverso dal comando | `src/game/flood_card_target.odin:8`: stesso anchor per input, hint e segni sul terreno, con la logica di scelta precedente invariata. |
| Effetti e stati apparivano sotto un rilievo o sul piano sbagliato | `src/render/tactical_feedback.odin:78`, `src/render/status_tags.odin:120`: quote di attori, oggetti ed eventi; coperti anche impatti senza attore, grotte, ponti e scala prospettica dei glifi. |
| IA tratteneva un bersaglio non più legale o indicava la sua vecchia cella | `src/advisor/evaluate.odin:224`, `src/run/advisor_driver.odin:163`: query attuale e segno sull’entità; il consiglio impossibile scompare anche prima della risposta del worker. |

**IA aggiornata.** I puzzle usano ricerche reali, avversari dietro copertura, bersagli mobili e arrivi
occupati. Confrontano query dell’anteprima, comando umano, consiglio e risultato della copia con il gioco.
Annullare la carta accodata non cambia lo stato simulato e non invalida un consiglio ancora possibile.
Nessun nuovo campo dello stato, candidato, valore o voce del contesto; i controlli esaustivi restano attivi.

Regressioni mirate strict `-o:none`: carte **3/3**, IA e contratti pilot **6/6**, policy del consiglio
in attesa **1/1**, renderer **18/18**, casi grotta aggiuntivi **6/6**, ancoraggio degli stati **7/7**.
Questi gruppi includono test preesistenti e alcuni si sovrappongono: non sommarli come test distinti.
Baseline fallite conservate nei log delle carte e della validità IA. Log mirati in
`build/moonshot/expedition-polish/` e `build/moonshot/expedition-polish/20261106/cards/`.

Prova nativa ripetibile:

```sh
odin build src -o:none -vet -strict-style -out:build/odin-pp-polish
ODIN_PP_SMOKE_ONLY=polish-cards build/odin-pp-polish --smoke-expedition
ODIN_PP_SMOKE_ONLY=polish-cards-raised build/odin-pp-polish --smoke-expedition
```

Il driver prepara soltanto una campagna senza salvataggio, una mano di sette carte e un incontro.
La seconda variante prepara anche un pianoro di 20 step prima del primo fotogramma. Da quel punto
usa la scena reale: Cannone selezionato e orientato, cambio carta, Firebomb fuori portata, Guard giocata,
Thorn Coat accodata dalla tastiera e annullata col destro, attesa della ripresa, poi Firebomb lanciata
con un clic proiettato sul bersaglio. Il nemico passa da 20 a 18 punti vita, mentre Thorn Coat resta in mano.
Le catture includono il messaggio di rifiuto, il cambio carta e il colpo con lo stato Scudo attivo.
Sono input sintetici nel percorso reale, non una prova manuale o un nuovo laboratorio di gameplay.

Log nativi in `build/moonshot/cards-readability-20261106/`; immagini
`build/captures/odin_pp_polish_cards_{flat,raised}_{switched,invalid,guard,damage}.png`.
Le prime tre corse di sviluppo del driver non sono conteggiate come verifiche riuscite: la mano
casuale iniziale non garantiva il Cannone, un controllo confondeva cast e azione a tempo e il primo
tentativo di accodare una carta mirata cadeva mentre il renderer non accetta bersagli spaziali.
La variante finale accoda una carta su di sé attraverso il tasto reale; il test del dispatcher copre
separatamente l’annullamento di Firebomb. Nessuna regola di input è stata aggirata dal driver finale.

L’ispezione della prima cattura rialzata ha rilevato anche il glifo Scudo ancora proiettato a quota zero:
è stato corretto e verificato con nuove regressioni su entrambi i tipi di camera e sui livelli -1, 0 e +1.
Le due corse native finali sono concluse con codice zero; la cattura finale conferma l’anello ai piedi
del robot sul pianoro. [Bersaglio rifiutato](riferimenti/moonshot/polish-carte/bersaglio-fuori-portata.png),
[scudo e colpo sul pianoro](riferimenti/moonshot/polish-carte/scudo-e-colpo-sul-pianoro.png) e
[hash delle prove conservate](riferimenti/moonshot/polish-carte/SHA256SUMS) accompagnano i log nel repository.
Queste prove non certificano il budget FPS, tutti i biomi o una nuova esecuzione su Windows.

Il controllo globale usa il profilo quick del progetto (`ODIN_TEST_FULL=false`, un thread) con
ottimizzazione `-o:speed`, assert e tracking di memoria attivi. La corsa iniziale `-o:none` è stata
interrotta nei tornei IA con piani sovrapposti dopo circa dieci minuti: il log
`quick-global-debug-interrupted.log` conserva l’esecuzione incompleta e non è un esito positivo.
Build strict finale `-o:none` e check strict con `-disable-assert` riusciti; strumenti Python **21/21**.

**Esito globale finale: 2138/2138 test superati**, memoria controllata senza anomalie, codice di uscita zero.
La suite comprende anche gli ultimi test dell’ancoraggio degli stati. Il
[log conservato](riferimenti/moonshot/polish-carte/quick-global-speed.log) è riproducibile con:

```sh
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FULL=false -o:speed
```
