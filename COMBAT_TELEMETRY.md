# Combat Telemetry

`src/combatdebug` contiene strumenti deterministici per osservare il combat loop
senza rendere la simulazione dipendente da UI, renderer o log testuali. Il
package importa `game` e `grid`; `game` non importa mai `combatdebug`.

## Confine di osservazione

Ogni comando viene osservato in tre passaggi, nello stesso dispatcher usato da
input diretto e bufferizzato:

1. `capture_command_snapshot` registra pulse, vita, energia, posizione, distanza
   minima e opportunita melee prima dell'esecuzione; per una carta,
   `capture_card_descriptor` congela identita, costo, target previsti e movimento;
2. il chiamante esegue la normale API autorevole di `game`;
3. `observe_command_detailed` riceve tipo risolto, descrittore, esito committed e
   `Room` finale, quindi produce un `Command_Sample` e aggrega soltanto
   `Room.recent_events`.

Il tipo e esplicito per non dedurlo dagli effetti. In particolare un input di
movimento contro un nemico e classificato `Bump_Attack` prima dell'esecuzione:
se uccide l'ultimo bersaglio, `try_move_player` restituisce `Combat_Ended`, ma la
natura del comando non viene persa.

Un comando rifiutato incrementa attempted e rejected e conserva i dati
pre-comando, senza leggere il log che potrebbe appartenere al comando precedente.
Un comando committed registra gli eventi persi e verifica che i marker
`Pulse_Advanced` siano compatibili con il delta autorevole di `Room.pulse_count`.
Drop o mismatch rendono il sample incompleto invece di inventare dati mancanti.

Il perimetro di una carta va dal suo `Card_Played` al `Card_Moved` che la porta
fuori da `Resolving`. In questo modo il danno diretto della carta resta distinto
da Poison, reazioni, trappole e risposta nemica che avvengono nello stesso
comando. I tick da status portano `has_status_cause/status_cause`: anche un tick
assorbito interamente da Shield resta attribuibile senza dedurlo da `System`.

## Metriche

`Combat_Metrics` usa soltanto interi e array fissi. Conserva:

- attempted, committed e rejected per `Move`, `Bump_Attack`, `Wait`, `Ability`,
  `Play_Card` e `Refocus`;
- pulse, eventi osservati o persi e mismatch di integrita;
- movimento del player e dei nemici, carte giocate, Refocus e attacchi mancati;
- danno diretto del player, danno indiretto, danno subito e assorbito;
- energia spesa, recuperata e sprecata al cap;
- utilizzo e rendimento delle singole definizioni di carta, con target pianificati
  e realmente coinvolti;
- applicazioni e tick di Poison, danno potenziale, assorbito ed effettivo;
- celle percorse, spostamenti forzati, trigger e danni da trappola;
- `object_hazard_triggers_on_player/enemies` e
  `object_hazard_damage_to_player/enemies`; oggi misurano `Fire`, ma il contratto
  resta valido per altri grid object pericolosi;
- carte retained, discarded o exhausted da Refocus;
- scelte bump / `Strike` / `Heavy Blow` nei soli turni in cui tutte sono opzioni;
- serie senza danni e serie di movimenti che mantengono invariata la distanza
  minima dal nemico.

Le principali quantita sono disponibili anche per tipo di comando. Il payload
`Pulse_Advanced` espone `energy_restored` ed `energy_wasted`: l'observer non deve
ricostruire la rigenerazione da costo della carta e snapshot, una deduzione che
diventerebbe falsa con costi dinamici.

## Sessioni e report JSON

`Playtest_Session` apre una stanza solo in `Combat`, registra ogni sample con il
suo `room_index` e la finalizza una sola volta quando il fight esce da quella
fase. Il giro di loot non puo quindi contaminare pulse, danni o distanza del
combattimento. Le metriche della run sono la somma delle stanze; massimi e range
vengono fusi con regole dedicate.

Il report ha `schema_version = 1` e contiene:

- seed e outcome della run, completezza globale e riepiloghi di stanza;
- metadata stabili del nodo: ID, tipo, depth e room seed;
- righe di comando e carta in ordine di enum, con nomi espliciti;
- sample in ordine di esecuzione, tutti basati su interi e booleani.

Non contiene timestamp, mappe hash o dati del renderer: a parita di seed e
sequenza di comandi, la serializzazione e byte-per-byte deterministica.

## Scenario di kiting

`run_max_distance_scenario` esegue una policy headless con tie-break interamente
deterministici. Per ogni candidato `North`, `East`, `South`, `West` e `Wait`:

1. preferisce celle non minacciate dagli intenti committed;
2. massimizza la distanza minima dalle posizioni nemiche previste;
3. massimizza la somma delle distanze;
4. conserva la direzione precedente;
5. usa l'ordine fisso dei candidati.

Lo scenario termina per budget, fine combattimento, sconfitta o comando
rifiutato e restituisce stato iniziale/finale insieme alle metriche. Il test ad
anello caratterizza il treadmill del `Chaser`: due stanze identiche producono lo
stesso report intero lungo venti pulse.

## Verifica

Per registrare una run giocata normalmente:

```sh
odin run src -- --playtest-report
```

Il report viene scritto come `odin_pp_playtest_<seed>.json` alla conclusione,
al restart o alla chiusura. Per esercitare lo stesso lifecycle senza aprire una
finestra:

```sh
odin run src -- --smoke-playtest
```

Lo scenario deterministico produce `odin_pp_playtest_smoke.json`.

```sh
odin test src/combatdebug -all-packages -define:ODIN_TEST_THREADS=1 -vet -strict-style
```

I test separano bump e carta, coprono il bump terminale, Refocus, miss degli
arcieri, log stale sui rifiuti, Poison parzialmente assorbito, AoE, movimento su
trappola, `Fire` assorbito o applicato, aggregazione exactly-once e
serializzazione deterministica.

Il primo tuning misurato mantiene il bump a 2 danni e porta `Strike` a 3: le due
azioni consumano entrambe un pulse, mentre la carta spende una energia per il
danno aggiuntivo e il ciclo del deck.
