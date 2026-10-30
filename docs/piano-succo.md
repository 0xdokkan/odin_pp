[← Odin PP](../README.md)

# Piano di lavoro: combattimento più vivo (succo dei colpi e proiettili veri)

Scritto il 30 ottobre 2026 sul ramo `piano-succo`, partito da `movimento-fluido`
(commit `bfaeede`). È lo stato più nuovo del gioco: prezzi del Viandante dimezzati
(`gioco-piu-veloce`), niente timer di decisione, cammino tenuto premuto, tasto
ricordato, carte rapide (`movimento-fluido`). Nessuno dei due rami è ancora unito.

Il documento nasce dalla domanda dell'utente dello stesso giorno: rendere il gioco
sulla griglia **più dinamico e attivo**, con un combattimento più fluido, mosse
più dinamiche, movimento complesso e **proiettili 3D che viaggiano**. Fra le sei
idee proposte l'utente ha scelto, in quest'ordine:

1. **Tenere premuto per camminare e un piccolo buffer dei tasti.** È già fatto sul
   ramo `movimento-fluido` (cammino tenuto, l'ultimo tasto premuto durante
   un'azione viene ricordato ed eseguito appena si è liberi): qui si prova e si
   rifinisce soltanto (Fase 0).
2. **Il succo dei colpi:** una pausa brevissima quando un colpo va a segno, lo
   schermo che si scuote, il nemico spinto indietro, scintille di carta (Fasi
   1-2).
3. **Proiettili veri:** le frecce degli arcieri volano casella per casella e si
   evitano spostandosi; le bombe dei bombaroli volano ad arco con il cerchio
   d'impatto a terra (Fasi 3-5).

Restano per dopo, fuori da questo piano: lo scatto di due caselle con
invulnerabilità, l'interruzione dell'animazione d'attacco con un passo, le spinte
contro muri e nemici, i nemici con movimenti propri e i boss a fasi, il bonus per
le azioni concatenate.

Le fasi si eseguono **una alla volta, solo su comando dell'utente**. Prima di un
passo che chiede una scelta si fanno le domande; poi si va avanti da soli fino a
fine fase, senza fermarsi a chiedere «passo successivo?». Quando serve sapere come
si fa una cosa, o come la fa un altro gioco, **si cerca su internet**. Le
meccaniche nuove si provano prima nel **laboratorio** (PROVA MECCANICHE) e passano
al gioco vero nella Fase 6. Sono regole dell'utente e valgono per tutto il piano.

Parole del documento:
- **Succo:** gli effetti che danno peso a un colpo (in inglese *juice* o *game
  feel*): pausa sull'impatto, scuotimento, spinta, scintille, lampo.
- **Pausa sull'impatto:** il gioco si ferma per qualche centesimo di secondo
  quando un colpo va a segno (*hit-stop*).
- **Scossa:** lo scuotimento della telecamera; cresce a ogni colpo e si spegne da
  solo in fretta (il modello «trauma» di Squirrel Eiserloh).
- **Proiettile vero:** un oggetto delle regole che vola sulla griglia a una
  velocità visibile e colpisce chi si trova sulla sua strada quando arriva.
- **Battito:** il secondo del mondo, quando i nemici agiscono.

## Decisioni dell'utente (30 ottobre 2026)

| Domanda | Risposta |
|---|---|
| Quanto forte il succo | **Media**: pausa di circa 60 ms, scossa breve, più forte sui critici e sulle uccisioni; un'opzione per ridurlo |
| Su quali colpi la pausa sull'impatto | **Colpi del giocatore e critici**; i colpi nemici solo scuotono un po' lo schermo |
| Quali proiettili diventano veri | **Arcieri e bombaroli** (le carte e le frecce di Feretro del giocatore no) |
| Come ci si difende da un proiettile vero | **Spostarsi basta**: si esce dalla riga accesa; la difesa a tasti (parata, blocco) resta per i colpi corpo a corpo |

## Stato delle fasi

| Fase | Contenuto | Dipende da | Stato | Commit |
|---|---|---|---|---|
| 0 | Base: unire le correzioni di `gioco-piu-veloce`, provare il cammino tenuto, misure di partenza | — | Fatta | vedi Esito |
| 1 | Succo, motore comune: scossa, pausa sull'impatto, opzione per ridurlo | 0 | Da fare | |
| 2 | Succo sui colpi: colpi del giocatore, critici, uccisioni, colpi nemici | 1 | Da fare | |
| 3 | Frecce degli arcieri: proiettili veri nelle regole | 0 | Da fare | |
| 4 | Frecce degli arcieri: aspetto 3D, riga accesa, suoni | 3 | Da fare | |
| 5 | Bombe dei bombaroli: volo ad arco e cerchio d'impatto | 3 | Da fare | |
| 6 | Nel gioco vero: prova con l'utente, bilanciamento, chiusura | 2, 4, 5 | Da fare | |

## Come funziona oggi (punto di partenza)

- **Ritmo.** Nel gioco come si gioca i prezzi del Viandante sono la metà
  (`TACTICAL_PLAYER_PACE` = 2: passo 0,4 s, colpo 0,5 s) e le animazioni delle
  azioni durano la metà (`render/action_pace.odin`). Su `movimento-fluido` non c'è
  più il timer di decisione e le carte si lanciano in 0,15-0,6 s.
- **Succo sul tabellone.** La carta colpita trema e lampeggia
  (`render/tactical_feedback.odin`); i colpi con un'arma hanno la loro stella
  d'impatto e le schegge (`render/attack_fx.odin`). **Non ci sono** scossa della
  telecamera né pausa sull'impatto: esistono solo dietro gli occhi
  (`first_person_trauma`, `first_person_punch_shake` in `render/first_person*.odin`).
- **Tiro dell'arciere.** L'arciere mira (intento `Attack` a distanza) e sul suo
  battito il colpo si risolve **subito** (`resolve_enemy_blow` in
  `game/enemy_intent.odin`): il dardo in volo è solo disegnato (`attack_fx`).
  Contro di lui oggi ci si difende con la difesa a tasti.
- **Bomba del bombarolo.** Si carica (`Bombard` con `windup`), poi la bomba
  compare sulla casella mirata e scoppia dopo `TACTICAL_BOMB_FUSE` = 3 battiti su
  3×3 caselle: si evita già spostandosi, ma non la si vede arrivare.
- **Tempo e immagini.** Il dado lanciato è una scena «cinematica»
  (`Presentation_Time_Policy.Cinematic`, `render/cast_playback.odin`): mentre
  gira il mondo non accumula tempo. La pausa sull'impatto userà lo stesso
  meccanismo, così le regole non vedono mai la pausa.

## Fase 0 — Base e misure

**Obiettivo:** partire dallo stato giusto e sapere da dove si parte.

Passi:
1. Unire in questo ramo i due commit di `gioco-piu-veloce` che `movimento-fluido`
   non ha: `c6a7ed7` (il crash dei ponti del bioma 9) e `34372b2` (la prova del
   laboratorio al ritmo nuovo; `19c6e26` ne contiene già metà).
2. Provare con l'utente il cammino tenuto premuto e il tasto ricordato nel gioco
   vero; ritoccare i numeri se servono (domande all'utente).
3. Misure di partenza: quanto dura in media un colpo dal tasto al numero del
   danno, quanti fotogrammi al secondo nel laboratorio e in una spedizione
   pesante (per poter dire alla fine «ogni immagine costa X% in più o in meno»).

**Fatto quando:** `scripts/check.ps1` verde, prova completa del laboratorio verde,
misure scritte nell'Esito.

### Esito (30 ottobre 2026)

1. **Correzioni unite** (commit `f51ece7`): `c6a7ed7` e `34372b2` di
   `gioco-piu-veloce`, senza conflitti; l'attesa più lunga prima della carta in
   prima persona c'era già (`19c6e26`) e resta una sola.
2. **Cammino tenuto e tasto ricordato:** l'utente li ha provati nel gioco vero e
   li approva così come sono («Va bene così»); nessun numero cambia. La partita
   di prova si è chiusa senza errori.
3. **Misure di partenza.**
   - *Dal tasto al colpo* (regole della partita vera, misura senza finestra):
     colpo a urto, numero del danno al fotogramma dopo il tasto e controllo di
     nuovo dopo 0,50 s; carta Strike, danno dopo 0,15 s e controllo dopo 0,38 s;
     carta Heavy Blow, danno dopo 0,15 s e controllo dopo 0,50 s. Sul tabellone
     con le carte vive il colpo a urto aspetta in più il disegno del colpo: 41 ms
     al ritmo del giocatore.
   - *Benchmark delle spedizioni* (`-define:EXPEDITION_BENCHMARK=true`, `-o:speed`,
     `--smoke-expedition`, 195 scene, canvas 1920×1080, RTX 3060 Laptop), due
     corse che concordano (4 scene su 195 oltre il 10%): in media un'immagine si
     disegna in **1,45 ms** (circa **690 fotogrammi al secondo**); corsa e
     ingaggio (stage 25 e 26) 1,64 e 1,70 ms; le scene più pesanti (5, 20, 127,
     177, 178) intorno a 2,0 ms, cioè 500 al secondo. Scena per scena:
     appendice A.
   - Il laboratorio non ha un benchmark suo: le scene di combattimento si
     confrontano con gli stage 25 e 26 e con le catture della prova del
     laboratorio.
4. **Verifiche:** `scripts/check.ps1` verde (1830 test con e senza assert); prova completa
   del laboratorio (`--smoke-mechanics-lab`) verde nella finestra vera, 2019 catture
   e 146 suoni in 14,5 minuti.

## Fase 1 — Succo, motore comune

**Obiettivo:** gli attrezzi del succo, senza ancora usarli sui colpi.

Passi:
1. **Scossa della telecamera del tabellone** sul modello «trauma»: ogni evento
   aggiunge trauma (0-1), la scossa vale trauma², si muove con un rumore
   continuo (Perlin) e non a caso, e il trauma cala da solo (proposta: da 1 a 0
   in 0,35 s). Spostamento massimo proposto: 0,12 caselle e 0,8° di rotazione.
   Va solo sull'immagine: mira, clic sulle caselle e cartoncini restano dove sono.
2. **Pausa sull'impatto:** un fermo delle immagini di N millisecondi che usa la
   politica «cinematica» della timeline: il mondo non accumula tempo, i tasti
   premuti nel frattempo seguono le regole del tasto ricordato. Mai più di una
   pausa ogni 0,15 s, così una raffica non si inceppa.
3. **Opzione «Succo dei colpi»** nelle impostazioni (`host/profile.odin`, cursore
   nel launcher accanto a «Sensibilità mouse»): da 0 a 100%, 100% di partenza; a
   0 niente scossa e niente pausa.
4. Test: la pausa non cambia l'ordine degli effetti né il tempo del mondo; la
   scossa torna a zero; l'opzione a 0 spegne tutto.

**Fatto quando:** nel laboratorio un tasto di prova scuote e ferma l'immagine;
test verdi.

## Fase 2 — Succo sui colpi

**Obiettivo:** ogni colpo si sente. Numeri di partenza (intensità media, da
provare con l'utente):

| Colpo | Pausa | Trauma | Altro |
|---|---:|---:|---|
| Colpo del giocatore | 60 ms | 0,25 | il nemico arretra di 0,15 caselle e torna; scintille di carta; lampo bianco sulla carta colpita per 60 ms |
| Colpo critico del giocatore | 90 ms | 0,45 | scintille dorate, lampo più lungo |
| Uccisione | 100 ms | 0,55 | la carta vola un po' più lontano prima di cadere |
| Colpo nemico sul giocatore | — | 0,30 | bordo rosso dello schermo per un istante |
| Colpo nemico parato o bloccato | — | 0,15 | scintille azzurre sullo scudo |
| Esplosione (bomba, barile) | — | 0,40 | anche a distanza, più debole lontano |

Passi:
1. Collegare gli eventi delle regole (colpo, critico, morte, parata) alla scossa
   e alla pausa, con la scala dell'opzione.
2. Arretramento visivo della carta colpita (solo immagine: la casella del nemico
   non cambia).
3. Scintille e lampo, fatti da codice come il resto della grafica.
4. Suono dell'impatto un po' più pieno sui critici (generato da codice).
5. Prova nel laboratorio con l'utente; i numeri cambiano su sua richiesta.

**Fatto quando:** l'utente approva la sensazione nel laboratorio; le catture della
prova del laboratorio mostrano scossa e scintille; test verdi.

## Fase 3 — Frecce degli arcieri: proiettili veri nelle regole

**Obiettivo:** la freccia nemica è un oggetto che vola e si evita spostandosi.

Proposta di regole (da confermare all'utente all'inizio della fase):
- Sul battito del tiro l'arciere **scocca**: nasce una freccia sulla sua casella,
  diretta lungo la linea mirata.
- La freccia avanza a **8 caselle al secondo** del mondo (proposta), in linea
  retta, fino a 8 caselle o al primo muro, muretto o copertura.
- Colpisce **il primo corpo che trova quando ci arriva**: il Viandante (danno
  dell'arciere e lo stato del bioma, come oggi) oppure un altro nemico (proposta:
  sì, fa danno anche a lui, come in Into the Breach).
- **Nessuna difesa a tasti** contro la freccia: si esce dalla riga. RIFLESSO e la
  parata della spada in prima persona la rimandano indietro come oggi.
- Le caselle che attraverserà sono segnate a terra dal momento della mira, poi
  si spengono man mano che la freccia le passa.
- Regole nuove nel pacchetto `game` (un tipo nuovo, per esempio
  `Enemy_Projectile`, con posizione, direzione, velocità, danno), con test sulle
  regole: colpisce, manca se ci si sposta, si ferma ai muri, attraversa il turno
  dell'ombra senza avanzare (il mondo è fermo).

**Fatto quando:** nel laboratorio una freccia si schiva con un passo; test verdi;
le sonde di regressione (regole nude) dicono esattamente cosa è cambiato.

## Fase 4 — Frecce degli arcieri: aspetto 3D e suoni

Passi:
1. Il dardo diventa un modello 3D vero (asta, punta, penne) che vola sopra il
   tabellone, con la scia e l'ombra sul pavimento.
2. La riga accesa a terra pulsa più forte quando la freccia è vicina.
3. Suoni: lo scocco, il sibilo che passa vicino, il colpo nel legno se manca.

**Fatto quando:** l'utente approva l'aspetto nel laboratorio.

## Fase 5 — Bombe dei bombaroli: volo ad arco

Proposta di regole: la bomba **vola ad arco** per 0,6 s del mondo e poi atterra;
da lì la miccia di 3 battiti resta come oggi. Il **cerchio d'impatto** (le 3×3
caselle) è a terra da quando parte e si stringe mentre la miccia brucia.

Passi:
1. Volo nelle regole (la bomba non c'è sulla casella finché non atterra).
2. Bomba 3D che ruota in volo, ombra che cresce, cerchio che si stringe.
3. Suoni: lancio, atterraggio, miccia.

**Fatto quando:** nel laboratorio si vede la bomba arrivare e si scappa dal
cerchio; test verdi.

## Fase 6 — Nel gioco vero

Passi:
1. Accendere succo e proiettili nella run, nella spedizione e nella campagna.
2. Partita di prova con l'utente; bilanciamento della velocità delle frecce, del
   danno e del succo.
3. Misure finali (fotogrammi al secondo come nella Fase 0, spiegate in parole
   semplici), documentazione delle regole (`docs/regole/`), CHANGELOG.

**Fatto quando:** l'utente approva; `scripts/check.ps1` verde; prova completa del
laboratorio verde.

## Rischi

- **Troppo succo stanca e nasconde i colpi importanti:** per questo la pausa solo
  sui colpi del giocatore, il limite di una pausa ogni 0,15 s e l'opzione per
  ridurlo.
- **La pausa non deve cambiare le regole:** passa dal meccanismo cinematico già
  usato dai dadi, con test sull'ordine degli effetti e sul tempo del mondo.
- **Proiettili e prima persona:** dietro gli occhi la freccia vera deve restare
  parabile con la spada; la Fase 3 lo prova con un test.
- **Lavoro in parallelo:** `movimento-fluido` è un ramo dell'altra sessione; questo
  piano parte da lì e non lo modifica.

## Fonti

- [Making Hits Feel Good in UE5: Hitstop, Camera Shake, and Knockback](https://uhiyama-lab.com/en/notes/ue/game-feel-hit-feedback/)
- [Hit-stop e scossa «trauma» in Godot 4](https://forum.godotengine.org/t/tutorial-hit-stop-and-screen-shake-in-godot-4-autoload-trauma-camera-mit/145240)
- [screen-shake, basato sul talk GDC di Squirrel Eiserloh](https://www.npmjs.com/package/screen-shake)
- [Game feel checklist (hit stop, trauma shake)](https://forum.godotengine.org/t/game-feel-checklist-for-godot-4-hit-stop-trauma-shake-coyote-time-and-more/145340)
- [Where Does Game Feel Come From: flash, shake, particles](https://eastondev.com/blog/en/posts/dev/20260521-game-feedback-feel/)
- [Must-see videos for indie developers (The Art of Screenshake, Jan Willem Nijman)](https://kenney.nl/learn/must-see-videos-for-indie-developers)
- [Making Game «Feel» (sintesi del talk di Vlambeer)](https://infovore.org/?p=5275)
- [One Step From Eden (Wikipedia)](https://en.wikipedia.org/wiki/One_Step_From_Eden)
- [One Step From Eden Review – Prima Games](https://primagames.com/featured/one-step-from-eden-review-a-step-too-hard)
- [Into the Breach (Wikipedia)](https://en.wikipedia.org/wiki/Into_the_Breach)

## Appendice A — Misure di partenza, scena per scena

Benchmark delle spedizioni della Fase 0 (30 ottobre 2026), RTX 3060 Laptop, canvas 1920×1080, `-o:speed`, due corse
(A e B). Tempo di un'immagine in millisecondi: media e 95° percentile. Sotto il 10% di differenza è rumore.

| Stage | Bioma | Media A | Media B | p95 A | p95 B |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 1.43 | 1.26 | 1.63 | 1.50 |
| 1 | 0 | 1.71 | 1.69 | 2.42 | 2.26 |
| 2 | 0 | 1.23 | 1.25 | 1.45 | 1.48 |
| 3 | 0 | 1.27 | 1.28 | 1.54 | 1.55 |
| 4 | 0 | 1.27 | 1.34 | 1.52 | 1.50 |
| 5 | 0 | 1.97 | 1.97 | 2.78 | 2.77 |
| 6 | 0 | 1.65 | 1.64 | 2.41 | 2.37 |
| 7 | 0 | 1.58 | 1.61 | 1.80 | 1.79 |
| 8 | 1 | 1.59 | 1.66 | 1.71 | 1.81 |
| 9 | 2 | 1.63 | 1.65 | 2.41 | 2.46 |
| 10 | 3 | 1.63 | 1.66 | 2.38 | 2.39 |
| 11 | 4 | 1.64 | 1.69 | 2.45 | 2.46 |
| 12 | 5 | 1.14 | 1.17 | 1.33 | 1.38 |
| 13 | 6 | 1.48 | 1.52 | 1.65 | 1.67 |
| 14 | 7 | 1.65 | 1.68 | 2.41 | 2.50 |
| 15 | 8 | 1.22 | 1.24 | 1.46 | 1.54 |
| 16 | 9 | 1.54 | 1.57 | 1.67 | 1.71 |
| 17 | 10 | 1.67 | 1.71 | 2.48 | 2.60 |
| 18 | 11 | 1.65 | 1.66 | 2.40 | 2.43 |
| 19 | 11 | 1.65 | 1.66 | 2.41 | 2.47 |
| 20 | 11 | 1.98 | 2.01 | 2.60 | 2.57 |
| 21 | 11 | 1.64 | 1.69 | 2.36 | 2.48 |
| 22 | 11 | 1.49 | 1.53 | 2.19 | 2.25 |
| 23 | 11 | 1.76 | 1.78 | 2.31 | 2.31 |
| 24 | 11 | 1.60 | 1.62 | 1.77 | 1.84 |
| 25 | 11 | 1.64 | 1.65 | 2.43 | 2.44 |
| 26 | 11 | 1.69 | 1.71 | 2.38 | 2.46 |
| 27 | 0 | 1.57 | 1.59 | 2.36 | 2.36 |
| 28 | 1 | 1.67 | 1.49 | 2.44 | 1.60 |
| 29 | 2 | 1.61 | 1.44 | 2.37 | 1.50 |
| 30 | 3 | 1.85 | 1.88 | 1.99 | 2.08 |
| 31 | 4 | 1.51 | 1.52 | 1.56 | 1.60 |
| 32 | 5 | 1.24 | 1.27 | 1.82 | 1.80 |
| 33 | 6 | 1.42 | 1.45 | 1.49 | 1.51 |
| 34 | 7 | 1.27 | 1.28 | 1.41 | 1.44 |
| 35 | 8 | 1.21 | 1.21 | 1.38 | 1.39 |
| 36 | 9 | 1.24 | 1.26 | 1.37 | 1.34 |
| 37 | 10 | 1.31 | 1.35 | 1.47 | 1.50 |
| 38 | 11 | 1.24 | 1.29 | 1.38 | 1.53 |
| 39 | 0 | 1.63 | 1.66 | 1.72 | 1.73 |
| 40 | 1 | 1.49 | 1.51 | 1.58 | 1.56 |
| 41 | 2 | 1.42 | 1.45 | 1.48 | 1.51 |
| 42 | 3 | 1.76 | 1.78 | 1.83 | 1.87 |
| 43 | 4 | 1.50 | 1.52 | 1.55 | 1.57 |
| 44 | 5 | 1.21 | 1.24 | 1.75 | 1.75 |
| 45 | 6 | 1.58 | 1.62 | 1.68 | 1.70 |
| 46 | 7 | 1.64 | 1.65 | 1.70 | 1.73 |
| 47 | 8 | 1.34 | 1.37 | 1.94 | 1.98 |
| 48 | 9 | 1.44 | 1.47 | 1.53 | 1.53 |
| 49 | 10 | 1.53 | 1.55 | 1.61 | 1.63 |
| 50 | 11 | 1.50 | 1.53 | 1.55 | 1.62 |
| 51 | 6 | 1.61 | 1.79 | 1.79 | 2.12 |
| 52 | 1 | 1.57 | 1.56 | 1.84 | 1.76 |
| 53 | 2 | 1.69 | 1.64 | 1.98 | 1.86 |
| 54 | 10 | 1.61 | 1.64 | 1.78 | 1.86 |
| 55 | 0 | 1.61 | 1.64 | 1.69 | 1.73 |
| 56 | 0 | 1.58 | 1.60 | 1.65 | 1.65 |
| 57 | 0 | 1.52 | 1.51 | 1.59 | 1.63 |
| 58 | 0 | 1.43 | 1.42 | 1.55 | 1.57 |
| 59 | 0 | 1.39 | 1.42 | 1.48 | 1.49 |
| 60 | 0 | 1.47 | 1.50 | 1.55 | 1.58 |
| 61 | 0 | 1.56 | 1.58 | 1.63 | 1.63 |
| 62 | 0 | 1.24 | 1.25 | 1.32 | 1.32 |
| 63 | 0 | 1.46 | 1.48 | 1.56 | 1.63 |
| 64 | 1 | 1.47 | 1.50 | 1.55 | 1.57 |
| 65 | 2 | 1.40 | 1.42 | 1.45 | 1.47 |
| 66 | 3 | 1.59 | 1.61 | 1.76 | 1.80 |
| 67 | 4 | 1.30 | 1.33 | 1.42 | 1.38 |
| 68 | 5 | 1.09 | 1.15 | 1.36 | 1.52 |
| 69 | 6 | 1.26 | 1.29 | 1.35 | 1.38 |
| 70 | 7 | 1.45 | 1.47 | 1.54 | 1.54 |
| 71 | 8 | 1.19 | 1.20 | 1.60 | 1.87 |
| 72 | 9 | 1.39 | 1.43 | 1.52 | 1.59 |
| 73 | 10 | 1.32 | 1.34 | 1.46 | 1.50 |
| 74 | 11 | 1.40 | 1.43 | 1.54 | 1.60 |
| 75 | 4 | 1.39 | 1.43 | 1.58 | 1.67 |
| 76 | 6 | 1.35 | 1.33 | 1.52 | 1.49 |
| 77 | 9 | 1.31 | 1.33 | 1.50 | 1.57 |
| 78 | 6 | 1.70 | 1.73 | 1.83 | 1.97 |
| 79 | 6 | 1.36 | 1.40 | 1.42 | 1.46 |
| 80 | 6 | 1.31 | 1.34 | 1.40 | 1.53 |
| 81 | 6 | 1.37 | 1.36 | 1.43 | 1.41 |
| 82 | 6 | 1.24 | 1.25 | 1.34 | 1.41 |
| 83 | 6 | 1.29 | 1.31 | 1.34 | 1.41 |
| 84 | 6 | 1.25 | 1.25 | 1.41 | 1.37 |
| 85 | 6 | 1.21 | 1.21 | 1.27 | 1.28 |
| 86 | 6 | 1.19 | 1.21 | 1.30 | 1.33 |
| 87 | 6 | 1.27 | 1.29 | 1.33 | 1.36 |
| 88 | 6 | 1.23 | 1.24 | 1.30 | 1.29 |
| 89 | 6 | 1.23 | 1.25 | 1.31 | 1.30 |
| 90 | 1 | 1.37 | 1.39 | 1.43 | 1.44 |
| 91 | 1 | 1.44 | 1.46 | 1.58 | 1.54 |
| 92 | 1 | 1.45 | 1.46 | 1.56 | 1.59 |
| 93 | 4 | 1.34 | 1.36 | 1.41 | 1.46 |
| 94 | 4 | 1.32 | 1.33 | 1.44 | 1.38 |
| 95 | 4 | 1.26 | 1.26 | 1.44 | 1.36 |
| 96 | 7 | 1.36 | 1.37 | 1.49 | 1.45 |
| 97 | 7 | 1.39 | 1.41 | 1.56 | 1.57 |
| 98 | 7 | 1.39 | 1.44 | 1.55 | 1.73 |
| 99 | 4 | 1.22 | 1.23 | 1.30 | 1.36 |
| 100 | 4 | 1.22 | 1.25 | 1.30 | 1.33 |
| 101 | 4 | 1.37 | 1.40 | 1.45 | 1.48 |
| 102 | 4 | 1.25 | 1.27 | 1.33 | 1.38 |
| 103 | 6 | 1.37 | 1.42 | 1.48 | 1.62 |
| 104 | 0 | 1.40 | 1.33 | 1.86 | 1.53 |
| 105 | 0 | 1.43 | 1.44 | 1.59 | 1.57 |
| 106 | 0 | 1.41 | 1.44 | 1.54 | 1.60 |
| 107 | 0 | 1.37 | 1.40 | 1.54 | 1.56 |
| 108 | 0 | 1.34 | 1.36 | 1.45 | 1.47 |
| 109 | 0 | 1.66 | 1.69 | 1.91 | 1.86 |
| 110 | 1 | 1.49 | 1.49 | 1.57 | 1.55 |
| 111 | 1 | 1.28 | 1.31 | 1.43 | 1.49 |
| 112 | 1 | 1.23 | 1.24 | 1.34 | 1.44 |
| 113 | 1 | 1.24 | 1.24 | 1.40 | 1.35 |
| 114 | 1 | 1.21 | 1.23 | 1.32 | 1.33 |
| 115 | 1 | 1.52 | 1.58 | 1.83 | 1.74 |
| 116 | 2 | 1.41 | 1.43 | 1.47 | 1.53 |
| 117 | 2 | 1.18 | 1.19 | 1.23 | 1.28 |
| 118 | 2 | 1.15 | 1.15 | 1.24 | 1.31 |
| 119 | 2 | 1.12 | 1.14 | 1.20 | 1.23 |
| 120 | 2 | 1.24 | 1.25 | 1.81 | 1.83 |
| 121 | 2 | 1.43 | 1.44 | 1.54 | 1.68 |
| 122 | 3 | 1.69 | 1.70 | 1.77 | 1.84 |
| 123 | 3 | 1.82 | 1.83 | 1.89 | 1.95 |
| 124 | 3 | 1.78 | 1.77 | 1.84 | 1.88 |
| 125 | 3 | 1.62 | 1.63 | 1.82 | 1.82 |
| 126 | 3 | 1.60 | 1.64 | 1.78 | 1.84 |
| 127 | 3 | 2.00 | 1.98 | 2.32 | 2.19 |
| 128 | 4 | 1.12 | 1.13 | 1.36 | 1.73 |
| 129 | 4 | 1.28 | 1.28 | 1.40 | 1.41 |
| 130 | 4 | 1.32 | 1.27 | 1.56 | 1.46 |
| 131 | 4 | 1.51 | 1.54 | 1.69 | 1.83 |
| 132 | 4 | 1.32 | 1.34 | 1.42 | 1.45 |
| 133 | 4 | 1.73 | 1.77 | 1.93 | 1.93 |
| 134 | 5 | 1.08 | 1.05 | 1.31 | 1.19 |
| 135 | 5 | 1.19 | 1.17 | 1.81 | 1.81 |
| 136 | 5 | 1.16 | 1.12 | 1.69 | 1.36 |
| 137 | 5 | 1.13 | 1.19 | 1.41 | 1.60 |
| 138 | 5 | 1.09 | 1.17 | 1.28 | 1.40 |
| 139 | 5 | 1.56 | 1.58 | 1.81 | 1.77 |
| 140 | 6 | 1.51 | 1.56 | 1.67 | 1.84 |
| 141 | 6 | 1.47 | 1.47 | 1.62 | 1.62 |
| 142 | 6 | 1.45 | 1.46 | 1.58 | 1.62 |
| 143 | 6 | 1.44 | 1.47 | 1.51 | 1.66 |
| 144 | 6 | 1.43 | 1.46 | 1.59 | 1.57 |
| 145 | 6 | 1.68 | 1.68 | 1.84 | 1.88 |
| 146 | 7 | 1.65 | 1.68 | 1.73 | 1.79 |
| 147 | 7 | 1.54 | 1.56 | 1.69 | 1.69 |
| 148 | 7 | 1.56 | 1.54 | 1.94 | 1.84 |
| 149 | 7 | 1.57 | 1.61 | 1.73 | 1.95 |
| 150 | 7 | 1.65 | 1.66 | 1.72 | 1.78 |
| 151 | 7 | 1.74 | 1.75 | 1.96 | 1.96 |
| 152 | 8 | 1.42 | 1.47 | 2.19 | 2.22 |
| 153 | 8 | 1.39 | 1.36 | 2.14 | 2.14 |
| 154 | 8 | 1.41 | 1.36 | 2.15 | 2.10 |
| 155 | 8 | 1.28 | 1.30 | 1.60 | 1.55 |
| 156 | 8 | 1.26 | 1.31 | 1.42 | 1.57 |
| 157 | 8 | 1.64 | 1.66 | 1.81 | 1.80 |
| 158 | 9 | 1.32 | 1.31 | 1.52 | 1.45 |
| 159 | 9 | 1.36 | 1.34 | 1.58 | 1.48 |
| 160 | 9 | 1.37 | 1.38 | 1.49 | 1.58 |
| 161 | 9 | 1.44 | 1.36 | 1.74 | 1.52 |
| 162 | 9 | 1.35 | 1.37 | 1.55 | 1.64 |
| 163 | 9 | 1.59 | 1.60 | 1.79 | 1.77 |
| 164 | 10 | 1.44 | 1.45 | 1.58 | 1.57 |
| 165 | 10 | 1.36 | 1.36 | 1.43 | 1.41 |
| 166 | 10 | 1.44 | 1.44 | 1.57 | 1.66 |
| 167 | 10 | 1.46 | 1.47 | 1.60 | 1.75 |
| 168 | 10 | 1.47 | 1.47 | 1.59 | 1.60 |
| 169 | 10 | 1.73 | 1.74 | 1.99 | 1.88 |
| 170 | 11 | 1.65 | 1.65 | 1.76 | 1.79 |
| 171 | 11 | 1.40 | 1.39 | 1.61 | 1.49 |
| 172 | 11 | 1.32 | 1.33 | 1.49 | 1.52 |
| 173 | 11 | 1.40 | 1.40 | 1.60 | 1.54 |
| 174 | 11 | 1.32 | 1.35 | 1.44 | 1.51 |
| 175 | 11 | 1.64 | 1.75 | 1.87 | 2.12 |
| 176 | 3 | 1.80 | 1.86 | 2.04 | 2.19 |
| 177 | 3 | 2.01 | 2.01 | 2.12 | 2.09 |
| 178 | 3 | 2.00 | 2.01 | 2.25 | 2.32 |
| 179 | 4 | 1.57 | 1.56 | 1.64 | 1.64 |
| 180 | 4 | 1.48 | 1.46 | 1.58 | 1.56 |
| 181 | 4 | 1.33 | 1.33 | 1.41 | 1.42 |
| 182 | 5 | 1.21 | 1.23 | 1.32 | 1.55 |
| 183 | 5 | 1.35 | 1.33 | 1.85 | 1.61 |
| 184 | 5 | 1.30 | 1.33 | 1.48 | 1.60 |
| 185 | 8 | 1.17 | 1.21 | 1.39 | 1.71 |
| 186 | 8 | 1.32 | 1.33 | 1.57 | 1.61 |
| 187 | 8 | 1.33 | 1.33 | 1.78 | 2.02 |
| 188 | 10 | 1.43 | 1.45 | 1.64 | 1.75 |
| 189 | 10 | 1.34 | 1.34 | 1.48 | 1.44 |
| 190 | 10 | 1.49 | 1.49 | 1.79 | 1.79 |
| 191 | 3 | 1.66 | 1.63 | 1.92 | 1.79 |
| 192 | 3 | 1.52 | 1.50 | 1.73 | 1.59 |
| 193 | 3 | 1.50 | 1.53 | 1.59 | 1.61 |
| 194 | 11 | 1.47 | 1.49 | 1.60 | 1.65 |
