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
| 0 | Base: unire le correzioni di `gioco-piu-veloce`, provare il cammino tenuto, misure di partenza | — | Da fare | |
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
