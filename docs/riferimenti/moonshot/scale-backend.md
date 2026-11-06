# Rapporto indipendente: scala reale e back-end

> Aggiornamento: il successivo [supplemento grafico](scala-grafica.md) contiene le misure riuscite fuori sandbox. Il fallimento iniziale sotto resta parte della cronologia, non lo stato finale della ricerca.

4 novembre 2026. Repository letto: `ddc6b186942d4c78597dc0f3f06c1a73483b716e`, discendente della base richiesta `d71b83a`. Nessun file del repository modificato. La copia sacrificabile è `/tmp/odin-moonshot-scale`; il solo cambiamento di gioco in quella copia moltiplica `map_size` per `#config(MOONSHOT_SCALE,1)`. Non è una fase implementata né una proposta di patch da unire.

## Esito della prova

**MISURA:** la generazione e la creazione della stanza riescono a 1×, 2×, 4× e 8× di lato per Cyber, Snow e Space, seed 42, tre ripetizioni per combinazione. La cattura per il salvataggio riesce a 1× e fallisce per TUTTE le prove da 2× in su. Dunque «riesce a generare 1792×1792» non significa «il gioco supporta quel mondo».

**MISURA:** il benchmark grafico è stato compilato, ma non ha prodotto neppure un campione: l'avvio GLFW ha scritto errori di connessione `com.apple.hiservices-xpcservice` e `LSNotification`; il processo è stato terminato dal timeout dopo 35 secondi. Non è possibile ricavare frame time da questa prova. La causa precisa del blocco non è stata diagnosticata: non chiamarla regressione del gioco né prova che la scala rompa il renderer.

Ambiente osservato: macOS 26.6.2 (25G83), `arm64`, Odin `dev-2026-10:84bc3fc21`, raylib 6.0 annunciata dal runtime. L'identificazione come M1 viene dal contesto utente; `sysctl` hardware non è permesso nell'ambiente. Nessuna misura Windows/RTX 3060. Nessun asset scaricato, nessuna dipendenza installata. Gli asset locali esistenti sono stati collegati alla copia per compilare.

Il programma di prova usa `time.tick_now`/`tick_since` e `mem.Tracking_Allocator`. Misura `expedition.generate(...,42,false)` (ritocchi esclusi), poi `game.create_room`, `configure_expedition_combat`, `expedition.prepare_room`, allocazione di `Snapshot` e `capture`, infine distrugge tutto. Tre campioni non sostituiscono un benchmark statistico. Alcune compilazioni indipendenti avvenivano durante la prima serie: sono misure esplorative, non confronto prestazionale certificato. La mediana attenua i primi campioni più lenti; conservare tutti i log.

**Attenzione alla memoria:** i byte riportati sono quelli tracciati da `context.allocator`, non RSS, non memoria GPU, non scratch in `context.temp_allocator`, non stack o overhead del tracker. Il picco include stanza e snapshot fisso di 1.814.672 byte, senza renderer e senza ricerca IA. Le 36 prove hanno restituito zero byte tracciati residui e zero bad free dopo la distruzione; questo non prova l'assenza di perdite negli allocatori esclusi.

| Scala lato | Bioma | Lato | Generazione mediana, ms (`-o:none`) | Heap dopo generazione, byte | Picco heap osservato, byte | Capture |
|---|---|---:|---:|---:|---:|---|
| 1× | Cyber | 160 | 58,382 | 157.632 | 3.308.384 | sì |
| 1× | Snow | 192 | 12,947 | 222.016 | 3.913.440 | sì |
| 1× | Space | 224 | 23,579 | 251.712 | 4.582.112 | sì |
| 2× | Cyber | 320 | 210,563 | 618.432 | 7.455.584 | no |
| 2× | Snow | 384 | 56,797 | 885.568 | 9.885.408 | no |
| 2× | Space | 448 | 183,665 | 1.004.352 | 12.560.096 | no |
| 4× | Cyber | 640 | 974,483 | 2.461.632 | 24.044.384 | no |
| 4× | Snow | 768 | 234,029 | 3.539.776 | 33.773.280 | no |
| 4× | Space | 896 | 427,746 | 4.014.912 | 44.472.032 | no |
| 8× | Cyber | 1280 | 1994,378 | 9.834.432 | 90.399.584 | no |
| 8× | Snow | 1536 | 942,227 | 14.156.608 | 129.324.768 | no |
| 8× | Space | 1792 | 1721,736 | 16.057.152 | 172.119.776 | no |

**MISURA aggiuntiva:** una serie `-o:speed`, soltanto 8×, ha mediane di generazione 368,202 ms Cyber, 113,700 ms Snow, 203,602 ms Space. Stessi byte tracciati e stessi rifiuti di capture. Non trasferire questi miglioramenti ai FPS; non sono stati misurati.

**MISURA di contenuto:** il numero di siti/gruppi resta rispettivamente 16/10 (Cyber), 19/14 (Snow), 16/12 (Space) a ogni scala. **INFERENZA:** moltiplicare soltanto il lato diluisce la densità delle mete, mentre i motivi locali del terreno continuano a ripetersi. 2×, 4×, 8× di lato corrispondono aritmeticamente a 4×, 16×, 64× celle, non a 2×, 4×, 8×.

## Evidenza nel codice e rotture

- **FATTO** `src/expedition/world.odin:121–122`: taglie base 80/96/112 moltiplicate per due. `src/campaign/campaign.odin:21` ripete indipendentemente 160/192/224: modificare solo la prima funzione, come nella prova deliberatamente minimale, lascia incoerente anche questa descrizione della campagna.
- **FATTO** `src/expedition/world.odin:173–190`: generazione sincrona di una griglia intera, con ciclo su ogni cella. `:192–205`: sedici siti nominali distribuiti per percentuali, prima delle grotte; `:231–234`: quattro pattuglie. `src/expedition/structures.odin:68–76`: strutture da liste prefissate per Cyber/West, con posizioni percentuali.
- **FATTO** `src/expedition/snapshot.odin:7`: `MAX_CELLS=224*224`; `:86` rifiuta mappe più grandi; `:143–146` valida taglia e limite. È una protezione corretta, non da rimuovere per fare passare il test.
- **FATTO** `src/render/presentation_timeline.odin:18,251`: la cronologia visiva del terreno ha un bitset dimensionato da `world.MAX_CELLS`; `:425–428` scarta e conta celle delle pozze oltre il limite. Non basta aumentare il salvataggio: va aggiornato anche questo contratto, con test ai bordi e sui piani.
- **FATTO** `src/game/room.odin:527–528`: distanze nemici `[]int` e pozze `[]i32` allocate per tutta la stanza. `src/game/layers.odin:140–143`: quando ci sono piani, la quantità è moltiplicata per `level.LAYER_COUNT`. `src/level/layers.odin:7–8,19–25`: i piani allocati hanno dimensione della base. **INFERENZA:** pochi ponti possono imporre tabelle grandi su tutto il mondo: prima leva tecnica è separare regioni e campi tattici locali.
- **FATTO** `src/advisor/copy.odin:153–163`: la fotografia IA copia livello, distanze e pozze; `:183–190` costruisce la prova a partire dalla fotografia. Le arene da 8 MiB sono blocchi iniziali, non un tetto: `:143–144` usa `arena_init_growing`. **INFERENZA:** aumentare il mondo aumenta costo e memoria della IA anche a numero di nemici costante. Non basta che la GPU vada veloce.
- **FATTO** `src/render/expedition_geometry.odin:13,138–155`: esistono già chunk statici da 8×8, caricati vicino al giocatore (±26 celle), con metadata per tutta la griglia. `:238–247`: disegno con culling. `:61–74,129–175`: distruzione sull'invalidazione della cache; non c'è eviction dei chunk lontani in questo percorso. **INFERENZA:** la parte iniziale del renderer è localizzata, ma la memoria delle mesh può crescere mentre si visita il mondo; serve prova di lunga percorrenza, non solo vista ferma.
- **FATTO** `src/render/expedition_floor_data.odin:68–75,100–101`: cache pixel del pavimento intera e cicli sull'intera mappa al rebuild. **INFERENZA:** modifiche locali, nuove strutture o rivelazioni non devono imporre invalidazioni globali frequenti nel moonshot.
- **FATTO** `src/render/expedition_material.odin:110,133`, `src/render/expedition_post.odin:51,61,79,98`: shader GLSL 330; `src/render/expedition_geometry.odin:247` invia mesh raylib. La compilazione grafica di questa copia usa raylib 6.0 della toolchain locale, non una versione del vendor fissata dal repository.

## Ricerca esterna letta il 4 novembre 2026

**FONTE:** la documentazione ufficiale raylib dichiara OpenGL come API principale, selezionata compilando rlgl, e avverte che macOS non supporta OpenGL 4.3. [raylib: piattaforme e grafica](https://github.com/raysan5/raylib/wiki/raylib-platforms-and-graphics).

**FONTE:** Apple indica OpenGL deprecato da macOS 10.14 e propone Metal per nuovo lavoro GPU. Questa guida è ritirata e alcune descrizioni interne si fermano a GL 3.2: non usarle per dedurre il massimo corrente. [Apple, OpenGL Programming Guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/opengl_intro/opengl_intro.html). La FAQ GLFW documenta i contesti macOS 3.3/4.1 e core forward-compatible. [GLFW FAQ, macOS](https://www.glfw.org/faq#how-do-i-create-an-opengl-30-context).

**FONTE:** Sokol espone GL/GLES/WebGL, Metal, D3D11, WebGPU e Vulkan dichiarato sperimentale; esistono binding Odin mantenuti dal progetto. `sokol_gfx` non crea la finestra e non traduce da solo gli shader; il progetto propone `sokol-shdc`. [Sokol README](https://github.com/floooh/sokol).

**FONTE:** bgfx è una libreria di rendering indipendente dall'engine con Metal, D3D11/12, Vulkan, OpenGL e altri backend; ammette integrazione con SDL/GLFW e richiede attenzione al threading delle finestre. [bgfx Overview](https://bkaradzic.github.io/bgfx/overview.html).

**FONTE:** i geometry clipmaps mantengono finestre di griglie concentriche a dettaglio diverso, aggiornandole incrementalmente mentre si muove l'osservatore. Qui interessa il principio «budget del visibile e aggiornamento incrementale», non i numeri storici del benchmark né l'adozione automatica della tecnica per ponti/grotte. [Asirvatham e Hoppe, GPU Gems 2, capitolo 2](https://developer.nvidia.com/gpugems/gpugems2/part-i-geometric-complexity/chapter-2-terrain-rendering-using-gpu-based-geometry).

**FONTE:** World Partition divide il mondo in celle caricabili, attivate da sorgenti come il giocatore; le celle possono essere pre-caricate presso una destinazione prima di un teletrasporto. [Epic, World Partition](https://dev.epicgames.com/documentation/unreal-engine/world-partition-in-unreal-engine). **INFERENZA:** adottare il principio in Odin non richiede migrare a Unreal; «pagina», «capitolo» e «regione tecnica» devono restare concetti distinti.

Ricerca architettura: trovato il paper primario CGA Shape di Müller et al.; l'abstract è disponibile nella ricerca, ma il PDF dell'autore supera il limite di lettura del tool e ACM restituisce 403. Non dichiaro letto il paper intero e non lo uso per sostenere dettagli algoritmici. Il filone architettura deve fornire una fonte primaria effettivamente leggibile prima di presentare una grammatica specifica come risultato di quel paper.

## Raccomandazione tecnica (INFERENZA / PROPOSTA)

1. Conservare raylib/OpenGL 3.3 per il prototipo di pagina e per trovare i costi reali. Il limite di OpenGL non spiega da solo il frame attuale: copie, rebuild, geometria immediata e shader sono problemi distinti.
2. Rendere la geografia indirizzabile a regioni e separare simulazione tattica attiva, stato persistente delle regioni e rappresentazione visiva distante. Definire ID persistenti, confini delle aree d'effetto, nemici che attraversano confini, ritorno su modifiche, seed e versione del generatore, snapshot e migrazione prima di promettere streaming.
3. Estrarre il contratto renderer (mesh, materiali, passaggi, texture, luci, camera) soltanto quanto serve a una scena confronto. Se il profilo mostra un limite reale di driver/API, provare Sokol/Metal su Mac e D3D11 su Windows con la stessa scena, stessa risoluzione e qualità. Sokol è il candidato più aderente a Odin, non una vittoria prestazionale dimostrata. bgfx resta alternativa se i suoi servizi giustificano build e integrazione aggiuntive. Metal puro da solo non soddisfa Windows.
4. Scegliere taglia di prodotto dopo aver misurato densità, tempo di attraversamento e costo di ritorno. La prima prova giocabile può mirare a 2× di lato; 4× è una tappa verificabile e 8× una prova estrema. Non trasformare le misure headless in promessa di mondo 8× finito.
5. Per «architettura più complessa» occorrono volumi percorribili e leggibili, non solo facciate. Anche prima di una grammatica formale, fissare contratti di ingressi, piani, passaggi, viste e stanze; scegliere moduli via regole deterministiche e validare raggiungibilità. Un ponte richiede dominio IA, superficie della pagina, collisione e visibilità coerenti.

## Prova grafica e accettazione ancora necessarie

La fase di misure deve rieseguire sulla macchina con sessione grafica disponibile e poi su Windows RTX 3060: 1×/2×/4×/8×, `-o:none` come diagnosi e `-o:speed` come obiettivo prodotto. Stessi seed e canvas fisico 1920×1080, vsync e limite frame disabilitati, scena ferma e percorso che attraversi molti chunk, combattimento a sei nemici, pozze al margine, strutture mutate, IA, salvataggio/ricarica, minimappa e viste dei diversi piani. Separare generazione, primo frame, riscaldamento e steady state; registrare media/mediana/p95/massimo, RSS, heap tracciato e payload mesh, più upload/rebuild. Ripetere più esecuzioni e non nascondere gli spike.

**FATTO** `src/application/campaign_smoke.odin:208–246`: il benchmark esistente registra intervalli reali di frame (update, submission, presentazione e stall) e distingue esplicitamente i tempi CPU di invio dai tempi GPU. `:254–261` stampa payload mesh senza overhead driver né copia CPU raylib. Queste distinzioni vanno conservate nel piano.

Budget proposto, non misura: 60 FPS significa 16,67 ms; usare p95 ≤16,67 ms sul percorso concordato a qualità e risoluzione fissate, riportando separatamente i picchi e il comportamento dell'IA. «Massima qualità» non autorizza risoluzione variabile nascosta fra macchine.

## Riproduzione e artefatti

File conservati nella copia sacrificabile:

- `probe/main.odin`: harness completo.
- `probe-1.log`, `probe-2.log`, `probe-4.log`, `probe-8.log`: campioni integrali `-o:none`.
- `probe-speed-8.log`: campioni aggiuntivi `-o:speed`.
- `graphics-1.log`: avvio fallito senza campioni di rendering.

Modifica isolata: in `src/expedition/world.odin`, sostituire `return legacy_map_size(b)*2 }` con `return legacy_map_size(b)*2*#config(MOONSHOT_SCALE,1) }`; nessun altro limite alzato, nessun controllo saltato. Compilazione, per ciascun N in 1,2,4,8:

```sh
odin build /tmp/odin-moonshot-scale/probe -o:none -out:/tmp/odin-moonshot-scale/probe-N -define:MOONSHOT_SCALE=N
/tmp/odin-moonshot-scale/probe-N
```

Per la prova grafica baseline è stato compilato con:

```sh
odin build /tmp/odin-moonshot-scale/src -o:none -out:/tmp/odin-moonshot-scale/graphics-1 -define:MOONSHOT_SCALE=1 -define:EXPEDITION_BENCHMARK=true -define:EXPEDITION_BENCHMARK_FIRST=0 -define:EXPEDITION_BENCHMARK_LAST=0 -define:EXPEDITION_BENCHMARK_WARMUP=20 -define:EXPEDITION_BENCHMARK_SAMPLES=120
```

Poi, dalla copia, `graphics-1 --smoke-expedition`, eseguito con `subprocess.run(..., timeout=35)`. Nessun salvataggio reale dell'utente toccato: modalità smoke, directory `/tmp`. Per conservare prove nel repository, copiare harness/log e questo rapporto come documentazione, senza la copia intera o i binari.
