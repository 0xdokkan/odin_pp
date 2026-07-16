# Combat Telemetry

`src/combatdebug` contiene strumenti deterministici per osservare il combat loop
senza rendere la simulazione dipendente da UI, renderer o log testuali. Il
package importa `game` e `grid`; `game` non importa mai `combatdebug`.

## Confine di osservazione

Ogni comando viene osservato in tre passaggi:

1. `capture_command_snapshot` registra pulse, vita, energia, posizione e distanza
   minima dai nemici prima dell'esecuzione;
2. il chiamante esegue la normale API autorevole di `game`;
3. `observe_command` riceve tipo risolto, esito committed e `Room` finale, quindi
   aggrega soltanto `Room.recent_events`.

Il tipo e esplicito per non dedurlo dagli effetti. In particolare un input di
movimento contro un nemico e classificato `Bump_Attack` prima dell'esecuzione:
se uccide l'ultimo bersaglio, `try_move_player` restituisce `Combat_Ended`, ma la
natura del comando non viene persa.

Un comando rifiutato incrementa attempted e rejected, senza leggere il log che
potrebbe appartenere al comando precedente. Un comando committed registra gli
eventi persi e verifica che i marker `Pulse_Advanced` siano compatibili con il
delta autorevole di `Room.pulse_count`.

## Metriche

`Combat_Metrics` usa soltanto interi e array fissi. Conserva:

- attempted, committed e rejected per `Move`, `Bump_Attack`, `Wait`, `Ability`,
  `Play_Card` e `Refocus`;
- pulse, eventi osservati o persi e mismatch di integrita;
- movimento del player e dei nemici, carte giocate, Refocus e attacchi mancati;
- danno diretto del player, danno indiretto, danno subito e assorbito;
- energia spesa, recuperata e sprecata al cap;
- serie senza danni e serie di movimenti che mantengono invariata la distanza
  minima dal nemico.

Le principali quantita sono disponibili anche per tipo di comando. Il payload
`Pulse_Advanced` espone `energy_restored` ed `energy_wasted`: l'observer non deve
ricostruire la rigenerazione da costo della carta e snapshot, una deduzione che
diventerebbe falsa con costi dinamici.

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

```sh
odin test src/combatdebug -all-packages -define:ODIN_TEST_THREADS=1 -vet -strict-style
```

I test separano bump e carta, coprono il bump terminale, Refocus, miss degli
arcieri, log stale sui rifiuti, scelta deterministica e ripetibilita dello
scenario headless.

Il primo tuning misurato mantiene il bump a 2 danni e porta `Strike` a 3: le due
azioni consumano entrambe un pulse, mentre la carta spende una energia per il
danno aggiuntivo e il ciclo del deck.
