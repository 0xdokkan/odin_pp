[← Odin PP](../README.md)

## Verifica e smoke test

Le catture native e i report degli scenari sono in `build/captures/`, relativa
alla directory di avvio e già ignorata da Git. I nomi dei file restano stabili
per i confronti. Anche F8 usa questa directory; gli output di telemetria
specificati esplicitamente da CLI mantengono il percorso richiesto.
I test di integrazione dell'applicazione vivono in `src/integration`; il ponte
`src/integration_test.odin` li rende raggiungibili da `-all-packages` senza
introdurre dipendenze inverse nei package di produzione.

[Lo script di verifica](../scripts/check.sh) esegue controllo statico, suite di tutti
i package e link della demo, sia con assert attivi sia con `-disable-assert`.
I binari sono temporanei; `ODIN` può indicare un compilatore alternativo.

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
| `--smoke-mechanics-lab` | Prova meccaniche in 3D: mano e testi, status, intenti, colpi, pozze, incendio, cariche, Lazzo, Pinball, FPS, Inondazione, Bomb Marley, bersagli in evidenza (`odin_pp_mechanics_lab_hit_*.png`; con `ODIN_PP_LAB_ONLY=hit_marks` gira solo quell'atto), Cannone (palla e laser), Buco Nero, i quattro dinosauri e pesca; replay e screenshot `odin_pp_mechanics_lab_*.png` / `odin_pp_living_*.png` |
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
