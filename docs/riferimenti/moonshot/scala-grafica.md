# Supplemento: benchmark grafico riuscito fuori sandbox

4 novembre 2026. Questo supplemento aggiorna l'esito grafico del rapporto `/tmp/odin-moonshot-scale-backend.md`: il primo avvio nella sandbox falliva; il tentativo successivo, autorizzato dalla revisione automatica fuori sandbox, è riuscito. Nessun ulteriore cambiamento al codice oltre al moltiplicatore di scala della copia `/tmp/odin-moonshot-scale`. Il rapporto originale non è stato modificato perché già in integrazione.

**MISURA:** quattro esecuzioni concluse con exit 0, una per lato 1×/2×/4×/8×, ciascuna con timeout di 35 secondi non raggiunto. Runtime: raylib 6.0, GLFW, renderer Apple M1, versione OpenGL `4.1 Metal - 90.5`, GLSL `4.10`. Il modello M1 è dunque ora verificato nel log, non soltanto riportato dall'utente.

Configurazione: `-o:none`, `EXPEDITION_BENCHMARK=true`, stage 0 iniziale del Cyber, canvas fisico 1920×1080, `target_fps=0`, `vsync_hint=false`, 20 frame di warmup e 120 campioni; nessuna cattura né readback GPU nel benchmark. Stessa procedura di avvio `--smoke-expedition`, dalla copia temporanea. Nessuna scrittura al profilo reale, nessun asset scaricato.

| Scala lato | Mappa Cyber | Media ms | Mediana ms | p95 ms | Massimo ms | CPU view media ms | Chunk residenti | Payload mesh byte |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1× | 160×160 | 10,549 | 10,595 | 12,464 | 14,318 | 0,181 | 41 | 1.412.856 |
| 2× | 320×320 | 10,112 | 10,289 | 13,232 | 16,529 | 0,447 | 40 | 1.960.848 |
| 4× | 640×640 | 10,127 | 10,294 | 13,277 | 14,520 | 1,601 | 40 | 1.610.280 |
| 8× | 1280×1280 | 10,346 | 9,799 | 13,664 | 14,512 | 6,411 | 40 | 1.875.528 |

In tutte e quattro le esecuzioni gli incrementi di rebuild/upload DURANTE i campioni sono zero. I payload sono quelli stampati dal benchmark: escludono overhead driver e copia CPU di raylib. Non sono misura della VRAM totale.

**Limite decisivo:** stage 0 è una scena ferma di ingresso, non una partita né il combattimento con sei nemici. Il percorso del driver aggiorna atmosfera e timeline; la simulazione completa è attivata in altri stage (`src/application/campaign_smoke.odin:419–449`). Questi numeri non smentiscono i 18,2/14,6/26 ms riportati in altre scene del redesign e non dimostrano il raggiungimento dei 60 FPS nel gioco completo. Sono una misura iniziale dell'effetto della taglia sulla vista statica.

**Limite del confronto:** il giocatore nasce a y=lato/2 (`src/expedition/world.odin:178`), quindi il contenuto locale intorno alla camera cambia fra scale anche con lo stesso procedimento. I diversi conteggi dei vertici lo confermano. Non è un benchmark a geometria visibile identica, non basta una singola esecuzione per scala per concludere equivalenza di prestazioni.

**INFERENZA:** il culling/caricamento locale mantiene limitata la geometria residente in questa vista iniziale, mentre il costo CPU `view_ms` aumenta fino a 6,411 ms a 8×. L'aumento è un segnale da profilare, non una diagnosi già conclusa. Il costo `world_ms` cambia in senso opposto (4,856/8,290/7,198/2,615 ms), perciò una media totale quasi costante maschera differenze di lavoro. Restano obbligatorie lunga percorrenza, rebuild dopo modifiche, rendering nel centro/architettura, combattimento e IA, `-o:speed`, altri biomi e Windows.

**Restano valide le rotture logiche:** nella prova headless tutte le capture da 2× sono rifiutate, il limite delle pozze di presentazione è ancora 224² e il numero di siti/gruppi non cresce. Far partire lo smoke grafico non le corregge.

Log integrali da conservare:

- `/tmp/odin-moonshot-scale/graphics-1-unsandboxed.log`
- `/tmp/odin-moonshot-scale/graphics-2-unsandboxed.log`
- `/tmp/odin-moonshot-scale/graphics-4-unsandboxed.log`
- `/tmp/odin-moonshot-scale/graphics-8-unsandboxed.log`

Compilazione di ciascun N (1,2,4,8):

```sh
odin build /tmp/odin-moonshot-scale/src -o:none -out:/tmp/odin-moonshot-scale/graphics-N -define:MOONSHOT_SCALE=N -define:EXPEDITION_BENCHMARK=true -define:EXPEDITION_BENCHMARK_FIRST=0 -define:EXPEDITION_BENCHMARK_LAST=0 -define:EXPEDITION_BENCHMARK_WARMUP=20 -define:EXPEDITION_BENCHMARK_SAMPLES=120
```

Esecuzione con directory `/tmp/odin-moonshot-scale`, subprocess della forma `[graphics-N, "--smoke-expedition"]`, stdout/stderr nel log, timeout35s e `sandbox_permissions=require_escalated`, approvato automaticamente. Tutte le esecuzioni grafiche sono state sequenziali; le compilazioni di questa serie erano concluse prima di misurare le scale successive.
