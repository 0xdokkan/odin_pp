# Moonshot — Esito locale della Fase 0

4 novembre 2026, ramo `piano-moonshot`, base `ddc6b186942d4c78597dc0f3f06c1a73483b716e`.
**La Fase 0 ha prodotto strumenti, misure e limiti verificabili sul Mac. Le fasi di gameplay e grafica
restano da eseguire, una alla volta su comando dell'utente.** Nessun commit o push effettuato.

## Che cosa è stato implementato

**FATTO:** il driver grafico può selezionare stage, registrare tutti i frame e usare un orologio simulato
fisso; il cronometro del frame resta reale. Il CSV contiene anche camera, posizione, fase e contatori delle
cache. Le statistiche separano warmup, p95, p99, massimo e frame oltre 16,67 ms. La geometria residente
include le strutture. Implementazione: `src/application/campaign_smoke.odin:88` (opzioni), `:260` (statistiche), `:277`
(campioni), `:334` (geometria) e `:352` (CSV).

**FATTO:** `tools/moonshot/benchmark.py:43` crea copie isolate; `:122` verifica hash/toolchain prima delle build;
`:163` esegue le misure, `:95` limita la durata dei processi e `:250` conserva gli esiti incompleti. Il probe
`tools/moonshot/probe/main.odin:143` misura il primo consiglio della IA; `:188` misura generazione,
stanza e checkpoint; `:226` registra allocazioni e distruzione. Nessuna modifica alle dimensioni o alle
regole del gioco distribuito, nessuna nuova meccanica o tabella IA: la IA esistente è stata misurata.

Protocollo e comandi: [README dello strumento](../../../tools/moonshot/README.md).
Riconciliazione di ricerca, contraddizioni e diagnosi statica:
[fase0-riconciliazione.md](fase0-riconciliazione.md).

## Provenienza delle misure

- MacBookAir10,1, Apple M1, 8 GiB, alimentazione collegata al rilievo iniziale; macOS 26.6.2 arm64.
  Toolchain Odin `dev-2026-10:84bc3fc21`. Nessun dato Windows o RTX 3060 Laptop.
- Seed 42, 13 binari compilati prima delle misure. Controllati 5.004 hash delle copie, senza divergenze;
  la versione Odin coincide con quella della preparazione. Il manifest identifica anche i sorgenti
  strumentati: questi binari non sono il puro eseguibile storico del commit di base.
- `-o:none` e `-o:speed` indicano ottimizzazione, non implicano `-debug` o assert disabilitati.
  Canvas effettivo 1920×1080, FPS illimitati, vsync hint disabilitato, passo simulato 1/60 s.
  60 frame di warmup; 600 misurati per le statiche e gli stage 196/197; cammino 25/26 da 240 nella baseline,
  da 1200 nelle copie ingrandite. I campioni sono stampati alla fine dello stage, fuori dalla raccolta.
- Sessione utile `build/moonshot-fase0-native`. Il primo tentativo sandbox è conservato separatamente:
  il probe finiva, ma `/usr/bin/time` falliva leggendo `kern.clockrate`. I suoi tempi non sono aggregati.
- Dopo la prima passata grafica il timeout 4× ha portato a non eseguire le ripetizioni 2 e 3 dello
  stesso caso/protocollo. Gli altri quattro casi hanno tre ripetizioni. Un avvio interrotto della seconda 8× è
  conservato separatamente, escluso e ripetuto con lo stesso binario. La scelta è in `repetition-policy.json`.

L'ordine alternato delle ripetizioni e tutti i comandi, limiti di tempo, esiti, hash e dati grezzi sono
nell'[archivio delle prove](fase0-prove.zip). L'archivio contiene percorsi relativi `build/...`; per consultare
anche i link ai log dei rapporti in un clone nuovo, estrarlo nella radice del repository. Non contiene binari,
profili o asset scaricati. [Checksum SHA-256](fase0-prove.sha256).
I risultati riassunti sono anche in [fase0-results.json](fase0-results.json).

## Risultati e conseguenze

**MISURA — mondo e IA:** 24 processi headless riusciti, 72 record. Generazione riuscita a tutte le scale;
18 checkpoint validi a 1×, 54 rifiutati alle scale superiori. Tutti i 72 primi consigli sono validi ed
eseguibili, con profondità 1: questo non certifica la ricerca completa né tutte le regole del gioco.
Tabelle e fonti puntuali: [rapporto headless](fase0-headless.md).

La mediana di generazione Cyber ottimizzata passa da 8,807 ms a 1× a 344,015 ms a 8×. Il primo consiglio API
passa da 83,970 a 147,249 ms; in Space 8× arriva a 328,521 ms. Il confronto non isola il solo numero di celle:
cambiano geografia e salute degli incontri. Questa è latenza sincrona snapshot+radice+ricerca, senza
thread, pubblicazione e UI della carta. Il probe usa uno snapshot, mentre il worker ne usa tre.

**FATTO — limite di stato:** `src/expedition/snapshot.odin:7` fissa 224² celle e `:86` rifiuta una mappa
più grande. La prova conferma il limite; non lo aggira. Generare e disegnare una mappa non dimostra che
possa essere salvata e ripristinata. La capture precede l'incontro e non include JSON, restore o I/O.

**MISURA — grafica:** 13 corse, di cui 12 complete e una in timeout; 56.280 righe di fotogrammi
conservate, comprese warmup e le due finestre complete del caso fallito. Il massimo RSS grafico rilevato
è 1.454,9375 MiB, un picco di processo, non una somma di memoria CPU/GPU. Vedere [rapporto dei fotogrammi](fase0-grafica.md) per ogni stage e ogni ripetizione,
intervalli di medie/p95, p99, massimi, scatti e contatori. Nessun confronto con la vecchia baseline viene
presentato come un guadagno del gioco: codice, protocollo, stato e ambiente vanno allineati prima.

Nella baseline ottimizzata, il p95 delle tre corse varia fra 13,879–16,005 ms per l’officina Cyber,
15,324–17,110 ms per il West e 14,259–17,079 ms per i sei nemici fermi. Sono intervalli di tre percentili,
non un percentile aggregato. L’obiettivo di 16,67 ms non è rispettato in tutte le corse.

**MISURA — traversata:** il tratto 25 delle copie ingrandite si arresta e rimane immobile nella
coda della finestra; un ostacolo è una spiegazione compatibile, non dimostrata dal solo CSV.
Il tratto 26 percorre distanze maggiori a 2× e 8×; il caso 4× non completa la finestra.
Venti secondi simulati di input non sono una prova di cammino continuo, ritorno o stabilizzazione della
memoria. Il conteggio di geometria locale non misura da solo tutta la memoria della GPU.

**INFERENZA — priorità tecnica:** la diagnosi statica identifica una scansione completa di `ground.pool`
nel percorso di costruzione della vista, documentata con file:riga nella §7 della riconciliazione.
Le misure CPU e di geometria vanno lette insieme; una correlazione con l'area non prova che quel ciclo
spieghi tutto il costo. Non sono disponibili timer GPU. Nessuna evidenza qui giustifica da sola un cambio
di back-end; prima del prototipo occorre attribuire i costi dominanti sulla scena equivalente.

## Correzione dello strumento dopo il fallimento

La prima versione del driver stampava il CSV soltanto a fine stage. La corsa 4× si è fermata dopo gli
stage 0/25, ha distrutto risorse della scena e ha raggiunto il timeout 360 s senza produrre lo stage 26.
Il log originario non contiene salute e stato finale: la morte era un'ipotesi coerente con il codice,
non un fatto osservato in quella corsa.

**MISURA separata v2:** chiusura normale con exit 0 e tre frame CSV. Nella copia 4× diagnostica
`-o:none`, lo stage 26 termina con salute 0 e fase `Defeat` dopo 969 frame registrati (909 misurati).
Il processo esce con codice 2 in 83,773 s, senza timeout, conservando 2.889 righe totali. I tracciati
degli stage 0/25 coincidono con quelli v1. È una nuova osservazione della sconfitta; i suoi tempi non
entrano nella baseline v1. Prove: `build/moonshot-fase0-validation-v2/logs/incomplete.{log,json}`
e `normal.{log,json}`, incluse nell’archivio.

La versione consegnata aggiunge `benchmark_completed` (`src/application/campaign_smoke.odin:146`)
e `expedition_capture_destroy` (`:522`): se il benchmark
viene distrutto prima di finire, stampa salute/fase/stato e CSV parziale, distrugge la scena e termina con
codice 2. Il percorso di gioco conserva tutte le regole. I log della prima versione restano immutati e
identificati dai relativi hash; la validazione della correzione è una serie separata.

## Budget e ciò che rimane aperto

**PROPOSTE di accettazione, non risultati già raggiunti:**

| Voce | Regola |
|---|---|
| Frame | p95≤16,67 ms per percorso, con p99/massimo e numero di scatti sempre pubblicati; niente nuovo lavoro sincrono quando il margine è già negativo |
| Fine vita tracciata | Zero byte residui e zero bad free; il probe soddisfa questa condizione nel perimetro dei suoi allocatori |
| Memoria residente del processo (RSS) | Tetto provvisorio di progetto 2 GiB RSS su M1 da 8 GiB, un quarto della RAM, per lasciare margine a sistema e strumenti. Da verificare con renderer, tre slot snapshot e memoria di ricerca del worker IA contemporanei: le prove separate non si sommano e non certificano il tetto |
| Regioni | Memoria fissa + regioni residenti + staging + copie IA entro il tetto; costi misurati su regioni dense, senza collegare la residenza al lato totale del capitolo |
| Caricamento durante il movimento | Caricamento+upload+margine osservato inferiori a distanza di anticipo/velocità massima reale; nessun picco escluso perché nascosto nel warmup |
| Primo ingresso | Soglia numerica ancora aperta: manca una misura isolata processo→primo frame giocabile, con condizioni freddo/caldo definite |
| Stabilità durante il viaggio | Percorso lungo chiuso e ripetuto, con RSS e risorse campionati nel tempo; le presenti prove non lo certificano |

Il tetto 2 GiB è una scelta provvisoria di progetto, non una previsione ricavata automaticamente dal test 8×
né una garanzia contro la pressione di memoria di sistema. Deve includere la IA reale e deve essere
verificato anche sul PC Windows prima di promuovere il mondo grande.

Restano esplicitamente mancanti: i 17 rapporti originali del PC Windows (0/17 acquisiti), verifica nativa
Windows/RTX 3060, confronto CPU/GPU equivalente, caricamento completo freddo/caldo, memoria lungo un giro
ripetuto, combattimento con movimento sostenuto dopo il warmup e salvataggio/ripristino delle mappe ampliate. Questi ultimi richiedono anche il lavoro dati
della Fase 4: la Fase 0 documenta il rifiuto corrente, non finge di averlo risolto.

## Verifiche

Passati 9 test Python, 20 test del pacchetto application e controllo Odin strict nelle configurazioni
ordinaria, benchmark e benchmark senza assert. Comandi/esiti sono nelle prove allegate. Nessuna suite
completa del progetto o prova Windows viene dichiarata eseguita. Nessuna meccanica nuova è entrata nel
gioco o nel laboratorio; non è richiesto un puzzle IA nuovo per questa sola strumentazione.
