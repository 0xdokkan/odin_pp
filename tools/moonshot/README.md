# Misure riproducibili del moonshot — Fase 0

Prerequisiti: Odin disponibile nel PATH, Python 3.9 o successivo, sessione grafica per i benchmark.
Il runner usa solo la libreria standard Python; su macOS e Linux legge anche RSS dal comando di sistema
`/usr/bin/time`. Su Windows registra RSS come non disponibile. Nessun accesso al profilo del giocatore:
la prova grafica usa `--smoke-expedition`, quella headless non scrive salvataggi.

Eseguire dalla radice del repository, sostituendo `python3` con `python` su Windows se necessario:

```sh
python3 tools/moonshot/benchmark.py prepare
python3 tools/moonshot/benchmark.py build
python3 tools/moonshot/benchmark.py run --group headless
python3 tools/moonshot/benchmark.py run --group graphics
python3 tools/moonshot/benchmark.py report
```

Output predefinito: `build/moonshot-fase0/`. `prepare` rifiuta una destinazione già esistente:
per una nuova sessione usare `--output build/moonshot-fase0-seconda`. Gli altri comandi ricevono lo stesso
percorso. Le copie sono sacrificabili; il solo cambiamento di gioco nelle copie è il moltiplicatore di
`map_size`. I guardrail di salvataggi, IA e geometria restano attivi. Nessuna patch della scala entra in `src/`.
Il manifest conserva hash dei sorgenti e degli asset copiati, commit, versione Odin e piattaforma; i file
`build-*.json` conservano comandi e hash dei binari. Non vengono raccolte variabili d'ambiente personali.
Prima di compilare, `build` verifica che le copie e la versione Odin coincidano con il manifest.

## Matrice e limiti

- `headless-{1,2,4,8}-{none,speed}`: Cyber, Snow, Space, seed 42; tre esecuzioni separate, una misura per
  bioma. Generazione senza ritocchi manuali, stanza, capture, memoria e primo consiglio IA con budget
  di 128 unità di lavoro o 5000 ms controllato fra nodi. Un nodo non è interrompibile: timeout esterno.
- `baseline-none`, `baseline-speed`: scala 1, stage 0/25/26/39/40/63/88/195/196/197. Ingresso, cammino,
  ingaggio, officine Cyber/West, rilievo Cyber, interno grotta Snow, sei nemici e due tratti di gameplay.
- `scale-{2,4,8}-speed`: ingresso e due tratti 25/26. Non certifica ogni bioma o scena di combattimento.

Grafica: canvas fisico 1920×1080, vsync e limite FPS disabilitati, 60 frame di warmup e 600 misurati;
25/26 usano 240 campioni nella baseline, 1200 nelle prove di scala (20 s simulati più warmup).
Il passo del driver è 1/60 s; i tempi dei frame restano quelli reali. I tasti dello script sono gli stessi,
ma un aumento del lato cambia i luoghi: non attribuire ogni differenza di costo alla sola dimensione.
Neppure 1200 aggiornamenti garantiscono una lunga traversata: i CSV mostrano se un ostacolo ferma il personaggio.

`--cases baseline-speed` seleziona un caso; più ID si separano con virgole. `--repetitions 1` è utile
soltanto per una verifica funzionale, non sostituisce le tre ripetizioni. L'ordine dei casi viene invertito
alla seconda ripetizione. Nessuna compilazione si sovrappone alle misure. `--timeout` è in secondi,
predefinito 240: timeout ed exit code nonzero sono risultati conservati, non esclusioni dalle tabelle.
`run` conserva le corse già registrate e non le sovrascrive; per ritentare un fallimento usare un nuovo output.
Una sandbox macOS può impedire la lettura RSS (`sysctl kern.clockrate`) o l'apertura della finestra:
conservare quel tentativo come fallito e usare una nuova sessione nativa con gli stessi sorgenti verificati.

## Dati e interpretazione

`logs/*.log` sono l'output completo. `logs/*-r*.json` includono comando, directory, tempo totale del processo,
esito e RSS massima quando disponibile. `report` estrae i CSV dei frame (anche warmup) e `results.json`.
I/O CSV soltanto a fine stage, mai durante la raccolta. Ogni riga contiene posizione, piano, fase, camera,
tempo simulato e contatori delle cache; l'hash del tracciato permette di confrontare le ripetizioni.
I tempi CPU annidati non sono tempi GPU. Il primo intervallo comprende anche il lavoro di ingresso allo
stage: non equivale al solo tempo di generazione o al caricamento dall'avvio del processo.

Le statistiche escludono il warmup; percentili per rango più vicino, con massimo e conteggio oltre 16,67 ms
sempre separati. Nessuna media dei p95 viene chiamata percentile aggregato. Una corsa è completa solo se
ha exit 0 e tutti gli stage/campioni richiesti (o i tre record headless senza errore).

Heap/temp tracciati, arene IA e RSS misurano cose diverse. Heap/temp escludono le tabelle interne dei
tracker e le allocazioni dirette non intercettate; il costo temporale del tracking è invece incluso.
Le arene IA dichiarano occupato, riservato e impegnato al termine della ricerca, non il picco fra nodi.
RSS include il processo intero e overhead; non è la sola mappa.
La variabilità dei gruppi/HP è registrata: il test IA misura il caso generato, non identici scontri fra scale.
Un consiglio assente entro il budget non diventa un tempo zero di risposta.

Se la scena viene distrutta prima dell'ultimo stage (per esempio alla sconfitta), il driver stampa
`EXPEDITION BENCHMARK INCOMPLETE`, stato finale e CSV parziale, esegue la distruzione della scena e termina
con codice 2. `report` mantiene la corsa incompleta. Non vengono alterati vita, nemici o regole per finire
il percorso. Le prime misure Fase 0 precedono questa correzione diagnostica: la loro copia congelata resta
identificata dai propri hash e il timeout osservato non viene convertito retroattivamente in uscita corretta.

`first_advice_ms` somma snapshot, radice e ricerca sincrona; esclude preparazione incontro/contesto,
inizializzazione, thread, pubblicazione e UI. Il worker vero usa tre snapshot, il probe uno: non è la
latenza completa della carta live né la memoria del worker. Il budget di 5000 ms riguarda soltanto la
ricerca e può essere superato da un nodo indivisibile. `capture` avviene prima dell'incontro e verifica
lo snapshot in memoria: non prova ripristino, serializzazione JSON o I/O del salvataggio.

Verifiche dello strumento:

```sh
python3 -m unittest discover -s tools/moonshot -p 'test_*.py'
odin check tools/moonshot/probe -vet -strict-style
odin check src -vet -strict-style
```

La documentazione dei risultati pubblicati vive in `docs/riferimenti/moonshot/`; i binari e le copie restano
in `build/`. Le fasi di gameplay e grafica non vengono avviate da questo runner.


## Fase 1 — Laboratorio della pagina

Dalla radice del repository:

```sh
odin build src -o:none -out:build/odin-page-lab
build/odin-page-lab --page-lab
build/odin-page-lab --smoke-page-lab
python3 tools/moonshot/page_lab_gallery.py --captures build/captures --output-dir build/moonshot/capacity-cardboard/gallery
```

Il menu contiene lo stesso laboratorio. Lo smoke aggiornato termina dopo 25 viste e tre sequenze di 12 immagini;
sono catture native senza ridimensionamenti o sostituzioni. La galleria locale copia e mostra i PNG originali,
con sequenze a 3 immagini/s, zoom e cursore. Non riproduce i frame intermedi.

Per misurare il campione, compilare una volta e poi eseguire separatamente tre volte, senza altre build:

```sh
odin build tools/moonshot/page_lab -o:speed -define:PAGE_LAB_BENCHMARK=true -out:build/page-lab-benchmark
/usr/bin/time -l build/page-lab-benchmark > build/moonshot/fase1/bench-r1.log 2>&1
/usr/bin/time -l build/page-lab-benchmark > build/moonshot/fase1/bench-r2.log 2>&1
/usr/bin/time -l build/page-lab-benchmark > build/moonshot/fase1/bench-r3.log 2>&1
python3 tools/moonshot/summarize_page_lab.py build/moonshot/fase1/bench-r1.log build/moonshot/fase1/bench-r2.log build/moonshot/fase1/bench-r3.log --output-dir build/moonshot/fase1
```

Creare prima `build/moonshot/fase1` se assente. `/usr/bin/time -l` vale per macOS; su Windows avviare il
binario e redirigere il log senza quel wrapper: la memoria non disponibile viene indicata come tale.
Verificare anche exit code 0 del processo. Il parser verifica il protocollo nel log, non il codice d'uscita.

Il driver forza sia coordinate logiche sia texture a 1920×1080, senza profilo o audio. Quattro atti
(fermo, passo, salita, volo), 60 frame di warmup e 600 misurati, tempo simulato 1/60 s. Nessuna cattura
nel benchmark; CSV a fine atto. Un solo shader, una texture della stampa e nessuna mesh GPU posseduti dal campione; risorse condivise
del motore escluse. I contatori separati riportano picchi di geometria, invio e query delle ombre, fallback
e ultimo tempo CPU delle ombre: quest'ultimo è un campione, non una media.

Il parser ricalcola i percentili dai CSV, rifiuta valori non finiti, conteggi errati e riepiloghi incoerenti,
conserva anche le repliche incomplete ed esce con 2 se una fallisce. Tempi update/draw CPU annidati, non
sommabili e non equivalenti a misure GPU; RSS è dell'intero processo, le capacità dei buffer sono CPU.
[Resoconto locale](../../docs/riferimenti/moonshot/fase1-risultati.md).


### Cartoncino e capacità degli snapshot

La stampa animata è attiva nel laboratorio; `P` o «Stampa» mostra il supporto senza disegno. Il retro resta carta.
Le catture aggiornate hanno prefisso `odin_pp_page_cardboard_`; la galleria predefinita richiede tutti i 61 PNG.
Usare `--legacy` per le 57 catture del primo campione senza stampa. Il parser accetta entrambi i protocolli;
nel nuovo richiede una texture, un solo upload e payload costante nei quattro atti (2640 frame totali).
La morte mantiene eretta l'anatomia dello sprite: occhi animati, chiusura affidata al supporto fisico.

Prova separata di capacità, da eseguire dopo la compilazione e senza altre build durante la misura:

```sh
odin build tools/moonshot/snapshot_capacity -o:speed -out:build/snapshot-capacity
mkdir -p build/moonshot/capacity-cardboard
/usr/bin/time -l build/snapshot-capacity 448 build/moonshot/capacity-cardboard/esempio-448.json
```

Ripetere con 224, 896 e 1792 e un nome di file nuovo per ogni tentativo. Il tool rifiuta file già esistenti;
non usa gli slot del profilo. Crea un livello e una stanza reali con due quote, valori distinti del liquido
al suolo e sul piano superiore, poi cattura, salva JSON, carica, ripristina e confronta tutte le tabelle.
Il record distingue tempi di capture, I/O del salvataggio, caricamento e restore. `snapshot_bytes` misura
struct e capacità dei buffer; RSS è dell'intero processo. È una prova controllata di persistenza,
non una misura della generazione, della IA o del renderer di una spedizione popolata.
[Esiti e limitazioni](../../docs/riferimenti/moonshot/fase1-cartoncino-capacita.md).

### Parità della geometria prima di ottimizzare

```sh
odin build tools/moonshot/geometry_fingerprint -o:speed -vet -strict-style -out:build/page-lab-geometry-fingerprint
build/page-lab-geometry-fingerprint > build/page-lab-geometry.csv
```

Il probe senza finestra verifica 240 pose per ciascuno dei nove atti e le 25 pose delle catture native.
Registra ordine, conteggi, coordinate del foglio e del mondo, triangoli, superfici, colori, tagli e cerniere;
gli hash usano campi espliciti, compresi i bit delle coordinate, senza padding o memoria temporanea.
Per un confronto eseguire lo stesso driver contro entrambe le copie dei sorgenti, con lo stesso compilatore
e le stesse opzioni, e confrontare i CSV integrali. Conservare anche gli hash dei sorgenti e dei binari.
Il probe non misura FPS e non verifica i pixel o le ombre: servono lo smoke nativo e i test di clipping.

L'[ottimizzazione del laboratorio](../../docs/riferimenti/moonshot/fase1-prestazioni.md) conserva anche i log
dei tentativi falliti e le varianti intermedie. Per il confronto raster usare le stesse opzioni di compilazione
e decodificare i PNG in RGBA8: differenze di compressione non sono differenze dell'immagine.
