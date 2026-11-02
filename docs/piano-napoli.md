[← Odin PP](../README.md)

# Piano di lavoro: la carta «Benvenuti a Napoli»

Scritto il 2 novembre 2026 sul ramo `piano-napoli`, partito da `piano-succo`
(commit `99e8799`). È lo stato più nuovo del gioco: succo dei colpi, frecce
degli arcieri e bombe dei bombaroli come proiettili veri, le tre carte in prima
persona nel laboratorio. Nessuno di questi rami è ancora unito a `main`.

Il documento raccoglie la richiesta dell'utente dello stesso giorno: una carta
**«assurda», bizzarra**. Giocandola si tira un **D4** e la faccia sceglie uno
di quattro effetti:

1. **Il bastone in terza persona.** Si cambia schermata come con le carte in
   prima persona (AK, Brawler, Fencer, Archer), ma la camera sta **dietro la
   schiena** del Viandante, molto vicina. Il Viandante impugna l'**asso di
   bastoni** delle carte napoletane, in 3D con l'aspetto di carta dei guantoni
   del Brawler. Si muove **sulla griglia** e dà **mazzate dall'alto**: molto
   danno e il nemico resta **stordito**. La carta del nemico colpito si
   **schiaccia e si allarga** alla Looney Tunes, poi torna normale.
2. **La tavolata.** Arriva un **nonno napoletano** e posa una tavolata col cibo
   vicino al Viandante; mangiando si cura molta vita.
3. **Il borsellino.** Arriva lo stesso nonno con un borsellino pieno di monete:
   il Viandante guadagna molto oro.
4. **Diventi il nonno.** Il Viandante si trasforma nel nonno **per un minuto**,
   in terza persona e **libero** sulla mappa: tira fuori l'asso di bastoni
   gigante dalla tasca (un'animazione volutamente stupida) e picchia; una volta
   sola si cura e una volta sola prende le monete. Finito il minuto torna il
   Viandante e il nonno se ne va.

Le fasi si eseguono **una alla volta, solo su comando dell'utente** («Esegui la
Fase N»). All'inizio di ogni fase si fanno le domande che servono; poi si va
avanti da soli fino a fine fase, senza fermarsi a chiedere «passo successivo?».
Quando serve sapere come si fa una cosa, o come la fa un altro gioco, **si cerca
su internet**. Tutto si prova prima nel **laboratorio** (PROVA MECCANICHE) e
passa al gioco vero solo nell'ultima fase. Grafica fatta da codice; per i suoni
vale la scelta dell'utente scritta sotto. Si sceglie sempre la massima qualità e
le prestazioni migliori. Ogni cambio alla carta si annota in
[registro-carte.md](registro-carte.md). Sono regole dell'utente e valgono per
tutto il piano.

Parole del documento:
- **Faccia:** il numero uscito sul D4 (1, 2, 3 o 4).
- **Vista:** la schermata speciale delle carte in prima persona; qui la usano
  anche la terza persona dell'effetto 1 e il nonno dell'effetto 4.
- **Terza persona:** la camera dietro la schiena, un po' spostata sopra una
  spalla (in inglese *over the shoulder*).
- **Mazzata:** il colpo dall'alto con l'asso di bastoni.
- **Stordito:** lo stato `Stagger` del gioco: il nemico perde la sua mossa e
  prende +2 dai colpi; dura un numero di **battiti** (1 battito = 1 secondo del
  mondo).
- **Schiacciamento:** lo *squash and stretch* dei cartoni animati: la carta si
  abbassa e si allarga tenendo lo stesso «volume», poi torna su con un
  rimbalzo.
- **Nonno ospite:** il nonno degli effetti 2 e 3, che arriva, porta il dono e se
  ne va. **Nonno giocatore:** il Viandante trasformato dell'effetto 4.

## Decisioni dell'utente (2 novembre 2026)

| Domanda | Risposta |
|---|---|
| Danno e stordimento della mazzata | **8 danni, stordito 2 s** (2 battiti) |
| Durata dell'effetto 1 | **30 s del mondo, +2 a potenziamento** (come First Person Archer) |
| Cura della tavolata | **Metà della vita massima** (11 nella run, 16 in spedizione) |
| Oro del borsellino | **15 oro** |
| Costo e rarità | **Rara, 3 energia** (prezzo 8, peso 60 come le carte in prima persona); solo laboratorio fino all'ultima fase |
| Tasti del nonno giocatore | **Q cura, E monete**, una volta sola ciascuno |
| Il nonno giocatore si può colpire? | **Sì, ha una vita sua**: se finisce, torna subito il Viandante senza danni |
| Il nonno ospite (effetti 2 e 3) | **Intoccabile**; arriva, posa il dono e se ne va; la tavolata **resta finché non si mangia** (fino a fine combattimento) |
| Comandi dell'effetto 1 | **Come l'AK:** il mouse gira la visuale, WASD fa un passo sulla griglia rispetto alla visuale, **clic sinistro = mazzata** sulla casella davanti (una delle 8 attorno) |
| Il bastone del nonno giocatore | **Col clic sinistro** (il bastone esce dalla tasca da solo, poi colpisce il giocatore) |
| Vita del nonno giocatore e cura | **30 di vita**; Q **cura tutti e due**: il nonno di metà della sua vita, il Viandante di metà della vita massima; E dà **15 oro** |
| Aspetto di Viandante e nonno da vicino | **3D di carta, come i guantoni** del Brawler (modelli da codice, bordo d'inchiostro, taglio di carta) |
| Come si mangia alla tavolata | **Passo contro la tavola:** si cammina contro la tavolata come contro un nemico, e invece di colpire il Viandante mangia (nessun tasto nuovo) |
| Potenziamenti (il D4 resta sempre un D4) | **Tutto un po':** effetto 1 +2 s, mazzata +1 danno, tavolata +2 cura, borsellino +2 oro, nonno giocatore +5 vita (il minuto resta un minuto) |
| Schiacciamento del nemico | **Un colpo veloce:** si schiaccia e torna normale in circa mezzo secondo, con un piccolo rimbalzo; lo stordimento si vede dal segno dello stato |
| Suoni e musica | Suoni e **tarantella**: **file CC0** se se ne trovano con licenza che lascia l'uso completo e libero, anche a scopo di lucro; **altrimenti fatti da codice** |

Note sulle decisioni:
- **Tasto E.** Nella vista del nonno giocatore il movimento è libero come nei
  pugni, quindi E non fa il passo in diagonale e non c'è la difesa a tasti
  (come nel Brawler): E è libero per le monete. Da controllare nella Fase 4.
- **Suoni CC0.** Valgono solo CC0 o pubblico dominio (non «licenza Pixabay», non
  CC-BY, che chiede di citare l'autore). Ogni file si scarica solo dopo il sì
  dell'utente, e nel repository si annotano fonte e licenza (Fase 6).

## Stato delle fasi

| Fase | Contenuto | Dipende da | Stato | Commit |
|---|---|---|---|---|
| 0 | Base: la carta, il D4 e i quattro rami nel laboratorio; misure di partenza | — | Da fare | — |
| 1 | Il nonno ospite: tavolata (effetto 2) e borsellino (effetto 3), regole e prototipo | 0 | Da fare | — |
| 2 | La terza persona e la mazzata (effetto 1), regole e prototipo | 0 | Da fare | — |
| 3 | Lo schiacciamento alla Looney Tunes e il succo della mazzata | 2 | Da fare | — |
| 4 | Diventi il nonno (effetto 4), regole e prototipo | 2 | Da fare | — |
| 5 | Aspetto 3D: asso di bastoni, Viandante, nonno, tavolata, borsellino | 1, 3, 4 | Da fare | — |
| 6 | Suoni e tarantella (CC0 o da codice) | 5 | Da fare | — |
| 7 | Nel gioco vero: «Mostra effetto», offerte, salvataggi, prova con l'utente, chiusura | 6 | Da fare | — |

## Come funziona oggi (punto di partenza)

- **Un D4 che sceglie l'effetto c'è già: il Dinosauro** (`Dino_Ride`,
  [dinosaur.odin](../src/game/dinosaur.odin)). La carta ha `dice_count = 1`;
  `card_die_sides` (`game/dice.odin`) tiene il dado a 4 facce a ogni livello;
  `resolve_played_card_action` (`game/spell.odin`) la manda a
  `resolve_dinosaur_card`, che tira il dado (`roll_card_dice`), sceglie il
  dinosauro dalla faccia (`dino_for_face`), lo scrive nelle `charges`
  dell'effetto e registra il tiro (`spell_dice_event`, evento `Dice_Rolled`). Il
  tiro si vede come quello di ogni carta coi dadi: è una scena «cinematica»
  (`render/cast_playback.odin`) e il mondo resta fermo mentre il dado gira. La
  carta nuova fa lo stesso.
- **La vista delle carte in prima persona**
  ([first_person.odin](../src/game/first_person.odin)). Un'arma per carta
  (`First_Person_Weapon`: AK, Fists, Sword, Bow) scelta dalle `charges`
  dell'effetto `.First_Person`; uno stato solo (`First_Person_State`, in
  `Room.first_person`) con i secondi rimasti, e quello che serve a ogni arma in
  un `#raw_union` (`First_Person_Arms`) perché la stanza resti sotto i 9 KB. I
  secondi scorrono col mondo (`tactical_first_person_tick` in
  `tactical_advance_clock`). Mentre dura, niente carte (`tactical_policy.odin`).
  La camera non cambia schermata: `frame_first_person_camera`
  (`render/first_person.odin`) scende dal tabellone agli occhi in 0,6 s, ad
  altezza 1,05 caselle, FOV 70 (80 coi pugni). I tasti passano da
  `run/first_person_input.odin`, un'arma alla volta.
- **Griglia o movimento libero.** AK, spada e arco fanno passi sulla griglia
  rispetto alla visuale (`first_person_key_directions`). I pugni del Brawler
  hanno un corpo libero (`First_Person_Fists`: un cerchio di raggio 0,3, 5
  caselle al secondo, passi fissi di 1/240 s); attraversare il centro di una
  casella conta come un passo senza costo, e `room.player.position` è sempre la
  casella sotto il corpo. Il nonno giocatore riusa questo corpo.
- **I guantoni di carta** ([first_person_gloves.odin](../src/render/first_person_gloves.odin)):
  modelli fatti di pezzi di raylib (sfere, cilindri), uno shader a tre toni,
  il bordo d'inchiostro col guscio rovesciato, poi tutto disegnato in una
  texture a bassa risoluzione e ritagliato come una carta (linea d'inchiostro,
  fascia di carta con la grana, spessore). L'arco compound è una mesh fatta da
  codice ([first_person_compound.odin](../src/render/first_person_compound.odin)).
  L'asso di bastoni, il Viandante e il nonno usano la stessa ricetta.
- **Camera in terza persona.** Sul tabellone non c'è. C'è una camera che gira
  attorno al personaggio (`Orbit_Camera`, `engine/camera/camera.odin`) nel
  minigioco Guglie Sospese, che disegna il Viandante come cartoncino
  (`gfx.flipbook_player(.Pilgrim)`, con uno schiacciamento suo).
- **Stordimento, cura, oro.** Lo stordimento è `Status_Kind.Stagger`, in battiti
  (oggi 1 battito per il gancio critico e la spada). La cura è `heal_effect`
  (fino alla vita massima: 22 nella run e nel laboratorio, 32 in spedizione).
  L'oro è `.Gain_Gold` (`room.player.gold += amount`, evento `Gold_Gained`).
- **Oggetti sul tabellone.** `Grid_Object_Kind` (`game/grid_object.odin`) ha solo
  pericoli e dispositivi (barile, bomba, Tesla, cannone…). Non c'è nessun
  personaggio non giocante e nessun oggetto da «usare» con un passo.
- **Carte del nemico.** Ogni nemico è una carta piatta girata verso la camera
  (`tactical_billboard` → `living_billboard_geometry`,
  [living_card.odin](../src/render/living_card.odin)); l'arretramento del succo
  (`juice_kick_offset`) sposta già la carta senza cambiare la casella. Lo
  schiacciamento si aggiunge lì, accanto al tremito.
- **Peso della stanza.** La stanza pesa 9208 byte su 9216
  (`size_of(Room) < 9*1024`, `event_test.odin`): restano **8 byte**. Ogni stato
  nuovo deve stare dentro quello che c'è già (vedi «Rischi»).
- **Il laboratorio.** Ogni prova è un «atto»
  (`src/devtools/mechanics_lab_*.odin`), da solo con `ODIN_PP_LAB_ONLY=<nome>`;
  l'atto del Dinosauro (`mechanics_lab_arsenal.odin`) prova già le quattro facce
  di un D4 una per una (`mechanics_lab_dice_for_face`). Le arene e i loro mazzi
  stanno in `run/mechanics_practice.odin`.

## Come si incastra nel codice (proposta)

- **La carta:** `Card_Id.Napoli`, nome «Benvenuti a Napoli», `Lab_Only` fino alla
  Fase 7, `dice_count = 1`, un effetto nuovo `.Napoli` con la faccia nelle
  `charges`, risolto da `resolve_napoli_card` come il Dinosauro.
- **Effetti 1 e 4 sono due armi nuove della vista:** `First_Person_Weapon.Club`
  (il bastone a griglia) e `First_Person_Weapon.Nonno` (il nonno libero). Così
  prendono gratis secondi, divieto delle carte, discesa della camera e
  salvataggio, e il loro stato sta nel `#raw_union` che c'è già: **la stanza non
  cresce** se i due stati nuovi non superano il più grande di oggi. Le regole
  delle armi dicono in più se la camera è in terza persona.
- **Effetto 2:** la tavolata è un oggetto della griglia nuovo
  (`Grid_Object_Kind.Napoli_Table`), nell'elenco degli oggetti che la stanza ha
  già. Un passo contro di lei = mangiare.
- **Effetto 3:** solo `.Gain_Gold`, subito.
- **Il nonno ospite è solo immagine:** arriva, porge, se ne va guardando gli
  eventi delle regole; le regole non hanno un personaggio in più.

## Fase 0 — Base: la carta, il D4 e i quattro rami

**Obiettivo:** la carta esiste nel laboratorio, si gioca, il D4 gira e la faccia
apre il ramo giusto (ancora vuoto); si sa da dove si parte.

Domande all'utente all'inizio della fase (proposte):
- **Giocata critica** (il tick): il Dinosauro aggiunge 3 s. Proposta: effetto 1
  +3 s, tavolata e borsellino ×1,5, nonno giocatore +10 di vita (il minuto
  resta un minuto).
- **Arena del laboratorio:** proposta, l'arena «Prima persona» (muri, nicchie,
  coperture, un arciere e un bruto) con la carta nel suo mazzo, più un tasto per
  scegliere la faccia del dado (come per il Dinosauro).
- Sigla e icona provvisorie (proposta: `BAN`, «Benvenuti a Napoli», e un asso di
  bastoni disegnato da codice in una cella libera dell'atlante).

Passi:
1. **Misure di partenza:** `scripts/check.ps1` (numero di test), prova completa
   del laboratorio (catture e suoni), peso della stanza, misura delle
   prestazioni come nella Fase 0 di [piano-succo.md](piano-succo.md) (benchmark
   delle spedizioni), per poter dire alla fine «costa X% in più o in meno».
2. **La carta nel codice:** `Card_Id.Napoli` e la sua definizione (rara, 3
   energia, prezzo 8, peso 60, `Lab_Only`, `dice_count = 1`, D4 fisso in
   `card_die_sides`); l'effetto `.Napoli`; le tabelle che lo chiedono
   (`EXPEDITION_CARD_COSTS`, `CARD_VISUALS`, descrizioni, suggerimenti della
   mano, anteprima dei potenziamenti, eventi attesi del film).
3. **Il D4 e i rami:** `resolve_napoli_card` tira il dado, sceglie la faccia
   (`napoli_for_face`), registra il tiro; un evento nuovo `Napoli_Begun` con la
   faccia. Per ora ogni ramo mostra solo il suo nome
   («1 BASTONE», «2 TAVOLATA», «3 BORSELLINO», «4 NONNO»); il pannello del
   risultato del dado (`dice_outcome_text`) dice cosa è uscito.
4. **Laboratorio:** la carta nel mazzo dell'arena; atto nuovo
   `mechanics_lab_napoli` (`ODIN_PP_LAB_ONLY=napoli`) che gioca la carta con le
   quattro facce, una per volta, e controlla il ramo; catture
   `odin_pp_napoli_dice_NN.png`.
5. **Test:** la carta tira sempre un D4 a ogni livello; ogni faccia apre il suo
   ramo; non si gioca durante una vista né in groppa al Dinosauro; la stanza
   resta sotto i 9 KB.
6. Voce nuova in [registro-carte.md](registro-carte.md) («Carta nuova:
   Benvenuti a Napoli (solo laboratorio)»).

**Fatto quando:** nel laboratorio la carta si gioca, il D4 gira e la scritta
dice il ramo giusto per ognuna delle quattro facce; misure scritte nell'Esito;
`scripts/check.ps1` verde; prova completa del laboratorio verde.

## Fase 1 — Il nonno ospite: tavolata e borsellino

**Obiettivo:** le facce 2 e 3 funzionano per davvero, con un nonno provvisorio
(cartoncino) che arriva e se ne va.

Proposta di regole (da confermare all'inizio della fase):
- **Tavolata (faccia 2):** compare sulla casella libera più vicina al Viandante
  (prima davanti a lui, poi di lato); occupa la casella, ferma i passi e le
  frecce come un muretto basso, nessuno la colpisce né la rompe. Un passo del
  Viandante contro di lei: si siede, mangia (0,8 s del suo prezzo, come un
  colpo), si cura di **metà della vita massima** (+2 a potenziamento), la
  tavolata sparisce. Resta finché non si mangia, al massimo fino a fine
  combattimento. Una tavolata alla volta: se ce n'è già una, la seconda
  la sostituisce (proposta).
- **Borsellino (faccia 3):** **15 oro** (+2 a potenziamento) subito, con
  l'evento `Gold_Gained`.
- **Il nonno ospite** è solo immagine: entra dal bordo del tabellone più vicino
  alla casella, cammina fino al Viandante, posa la tavola o porge il borsellino,
  saluta e se ne va. Domanda: **il mondo si ferma mentre arriva** (una scena
  cinematica di circa 2 s, come il dado) **o no**? Proposta: sì, così è un
  momento comico e non costa vita.

Passi:
1. Regole della tavolata (`Grid_Object_Kind.Napoli_Table`, il passo che mangia,
   eventi `Napoli_Table_Set` e `Napoli_Feast`) e del borsellino.
2. Il nonno ospite provvisorio: un cartoncino che cammina sul tabellone
   (nessun personaggio nuovo nelle regole).
3. Tavolata e borsellino provvisori, disegnati semplici (l'aspetto vero è della
   Fase 5).
4. Il salvataggio della spedizione tiene la tavolata (`expedition/snapshot.odin`).
5. **Test:** la tavolata nasce sulla casella giusta e mai su un nemico, un muro
   o un buco; il passo contro di lei cura e la toglie; i nemici non la toccano;
   resta fino a fine combattimento; il borsellino dà l'oro col potenziamento
   giusto; con la critica i numeri della Fase 0.
6. **Laboratorio:** l'atto `napoli` gioca la faccia 2 (il Viandante ferito
   mangia) e la faccia 3 (l'oro sale); catture `odin_pp_napoli_table_NN.png` e
   `odin_pp_napoli_purse_NN.png`.

**Fatto quando:** nel laboratorio il nonno porta la tavolata e il Viandante
mangia, e porta il borsellino e l'oro sale; test verdi.

## Fase 2 — La terza persona e la mazzata

**Obiettivo:** la faccia 1 si gioca: camera dietro la schiena, passi sulla
griglia, mazzate che stordiscono. Viandante e bastone ancora provvisori.

Proposta (da confermare all'inizio della fase):
- **Arma `Club`** della vista: **30 s del mondo, +2 a potenziamento**.
- **Comandi come l'AK:** il mouse gira la visuale, WASD un passo sulla griglia
  rispetto alla visuale (`first_person_key_directions`), clic sinistro =
  mazzata. La mazzata colpisce la casella davanti: la direzione della visuale
  presa fra le 8 attorno al Viandante.
- **Mazzata:** **8 danni (+1 a potenziamento) e Stagger per 2 battiti**.
  Proposta di tempi, per avere il peso dei colpi dall'alto (anticipo, impatto,
  ritorno): 0,25 s di carica sopra la testa, impatto, 0,35 s di ritorno; nessun
  colpo nuovo prima della fine. La mazzata a vuoto picchia il pavimento.
- **Stordire di continuo?** Con una mazzata ogni 0,6 s e 2 s di stordimento lo
  stesso nemico potrebbe restare fermo per sempre. Proposta: lo stordimento non
  si somma, si rinnova soltanto; e dopo due mazzate di fila sullo stesso nemico
  la terza stordisce la metà (i «ritorni decrescenti» di molti giochi). Domanda
  all'utente.
- **Camera in terza persona** (proposta di numeri, da provare con l'utente):
  - un perno sopra la spalla destra: 0,35 caselle a destra, 1,45 caselle
    d'altezza;
  - la camera 1,4 caselle dietro il perno, FOV 70, guarda 2 caselle avanti;
  - contro i muri la camera si avvicina **subito** e torna indietro piano (in
    0,3 s), come un braccio a molla: si controlla con un raggio dal perno alla
    camera (più quattro raggi attorno), e la camera si ferma un po' prima del
    muro;
  - se la camera arriva troppo vicina al Viandante, lui sbiadisce (come fanno
    The Witcher 3 e altri);
  - la discesa dal tabellone dura 0,6 s come per la prima persona;
  - fra un passo e l'altro la camera segue morbida (non a scatti).
- Niente carte mentre dura, non si gioca in groppa al Dinosauro, come le altre
  viste.

Passi:
1. Regole: arma `Club` (stato nel `#raw_union`), mazzata come azione d'attacco
   (`make_action(.Attack)` + danno + `Stagger`), passi sulla griglia.
2. Camera in terza persona: una funzione nuova accanto a
   `frame_first_person_camera`, con il braccio a molla contro i muri e i
   piani/altezze del terreno.
3. Comandi in `run/first_person_input.odin` (`drive_first_person_club`).
4. Viandante e bastone provvisori (un cartoncino e un bastone semplice),
   mirino discreto e riquadro dei secondi come le altre viste.
5. **Test:** la mazzata colpisce solo la casella davanti, fa 8 (+1) e stordisce
   2 battiti; i passi seguono la visuale; la vista finisce coi secondi; la
   camera non entra mai nei muri; la stanza resta sotto i 9 KB.
6. **Laboratorio:** l'atto `napoli` gioca la faccia 1, gira, fa due passi, dà
   una mazzata al bruto e controlla danno e stordimento; catture
   `odin_pp_napoli_club_NN.png`, anche con la camera contro un muro.

**Fatto quando:** l'utente prova la faccia 1 nel laboratorio e approva camera e
comandi; test verdi.

## Fase 3 — Schiacciamento alla Looney Tunes e succo della mazzata

**Obiettivo:** la mazzata si sente e si vede, come nei cartoni animati.

Proposta (da confermare all'inizio della fase):
- **Schiacciamento (un colpo veloce, la scelta dell'utente):** la carta del
  nemico colpito scende fino al 45% dell'altezza in 0,06 s e si allarga
  tenendo lo stesso volume (larghezza = 1/√altezza, cioè circa 1,5 volte);
  poi torna su con una molla e un piccolo rimbalzo (sale fino al 112% e si
  posa), tutto in circa **0,5 s**. I piedi restano a terra. Solo immagine: la
  casella e le regole non cambiano.
- **Succo:** la mazzata usa la pausa sull'impatto e la scossa del piano del
  succo, un po' più forti di un colpo a urto (proposta: pausa 90 ms, trauma
  0,45), polvere e schegge di carta dal pavimento; la mazzata a vuoto solo un
  po' di scossa.
- Lo stordimento si vede dal segno dello stato che c'è già (con le stelline,
  se l'utente le vuole).

Passi:
1. Lo schiacciamento in `living_billboard_geometry` (accanto al tremito) o
   subito dopo in `tactical_billboard`, letto da uno stato dell'immagine
   accanto a `Juice_Kick`.
2. Succo della mazzata (`observe_juice_blows`) e polvere.
3. **Test:** lo schiacciamento tiene il volume, i piedi a terra, finisce in
   0,5 s; la mazzata dà la sua pausa una volta sola; la casella non cambia.
4. **Laboratorio:** l'atto `napoli` controlla altezza e larghezza della carta
   colpita a metà dello schiacciamento e a fine; catture
   `odin_pp_napoli_squash_NN.png`.

**Fatto quando:** l'utente approva lo schiacciamento nel laboratorio; test
verdi.

## Fase 4 — Diventi il nonno

**Obiettivo:** la faccia 4 si gioca: un minuto da nonno, libero sulla mappa,
con bastone, cura e monete. Nonno provvisorio.

Proposta (da confermare all'inizio della fase):
- **Arma `Nonno`** della vista: **60 s del mondo** (fissi), camera in terza
  persona della Fase 2.
- **Movimento libero** col corpo dei pugni (`First_Person_Fists`), un po' più
  lento da nonno (proposta: 4 caselle al secondo invece di 5, niente salto né
  scatto, oppure tutti e due se l'utente vuole il nonno agile per ridere).
- **Il bastone:** all'inizio il nonno lo tira fuori **da solo** dalla tasca
  (un'animazione di circa 1,2 s: la mano in tasca, l'asso di bastoni gigante che
  esce piano, sempre più lungo; volutamente stupida); poi **clic sinistro =
  mazzata** (8 danni +1, Stagger 2 battiti) sul nemico davanti, entro 1,2
  caselle (proposta).
- **Vita sua: 30** (+5 a potenziamento). I colpi dei nemici tolgono la vita del
  nonno, non quella del Viandante; se finisce, la vista finisce subito e torna
  il Viandante senza danni.
- **Q, una volta sola:** il nonno si cura di metà della sua vita e il Viandante
  di metà della vita massima.
- **E, una volta sola:** 15 oro (+2 a potenziamento).
- Nell'HUD: vita del nonno, secondi, e i due tasti accesi finché non si usano.
- Alla fine il nonno «se ne va» (il Viandante torna nella sua casella).

Passi:
1. Regole: arma `Nonno` (corpo libero, vita, Q ed E usati, attesa del bastone
   nel `#raw_union`); i colpi nemici sulla vita del nonno; fine anticipata.
2. Comandi (`drive_first_person_nonno`), con Q ed E che durante questa vista
   non fanno i passi in diagonale né la difesa.
3. Nonno e bastone provvisori; l'uscita dalla tasca come animazione
   provvisoria.
4. Il salvataggio della spedizione tiene la vista del nonno
   (`First_Person_Save`).
5. **Test:** 60 s esatti; Q ed E una volta sola; la cura di Q va a tutti e due;
   i colpi nemici vanno al nonno; a vita zero torna il Viandante con la sua vita
   intatta; nessuna mazzata prima che il bastone sia fuori.
6. **Laboratorio:** l'atto `napoli` gioca la faccia 4, aspetta il bastone, dà una
   mazzata, usa Q ed E, prende un colpo dell'arciere, poi lascia finire la vita
   del nonno; catture `odin_pp_napoli_nonno_NN.png`.

**Fatto quando:** l'utente prova il minuto da nonno nel laboratorio e lo approva;
test verdi.

## Fase 5 — Aspetto 3D: asso di bastoni, Viandante, nonno

**Obiettivo:** tutto ha il suo aspetto vero, 3D di carta come i guantoni.

Prima di disegnare si mostrano all'utente **immagini di prova** (render dei
modelli) e si sceglie insieme.

Proposta:
- **Asso di bastoni** (dal mazzo napoletano vero): un grosso randello curvo e
  nodoso, **senza mano**; la testa larga e tonda **verde**, il manico
  **rosso**, avvolto da **foglie d'acanto gialle** e una foglia verde; in fondo
  il taglio con gli anelli del legno verdi. In 3D con lo shader a tre toni, il
  bordo d'inchiostro e il taglio di carta dei guantoni (cartoncino crema ai
  bordi, come se fosse ritagliato da una carta).
- **Viandante da dietro:** il personaggio del suo cartoncino (`Pilgrim`) fatto in
  3D di carta, con gli stessi colori, visto di spalle; braccia che alzano il
  bastone sopra la testa e lo calano.
- **Il nonno** (proposta da approvare con le immagini): **coppola** un po'
  storta, baffi bianchi, camicia bianca con le maniche arrotolate, gilet scuro,
  pantaloni con le bretelle, pancia, pantofole; cammina un po' curvo. È lo
  stesso modello per il nonno ospite e per il nonno giocatore.
- **La tavolata:** tovaglia buona a quadri o bianca, pasta al ragù, la
  parmigiana, il babà e una guantiera di dolci, la caffettiera; quando il
  Viandante mangia i piatti si svuotano.
- **Il borsellino:** di cuoio, gonfio, che tintinna; le monete che volano
  nell'oro del Viandante.
- **L'uscita dalla tasca:** l'asso esce dalla tasca dei pantaloni, molto più
  lungo della tasca, a scatti, con la faccia del nonno che si stupisce.

Passi:
1. Immagini di prova dei tre modelli; scelta dell'utente.
2. Asso di bastoni 3D (mesh da codice come l'arco compound).
3. Viandante e nonno 3D di carta, con le pose della mazzata, del cammino e
   dell'uscita dalla tasca.
4. Tavolata e borsellino; il nonno ospite cammina in 3D sul tabellone.
5. Icona definitiva della carta e sigla.
6. Misura delle prestazioni nel laboratorio (i modelli nuovi devono uscire
   subito quando non si disegnano, la lezione della Fase 6 di
   [piano-succo.md](piano-succo.md)).

**Fatto quando:** l'utente approva l'aspetto nel laboratorio; le catture della
prova del laboratorio mostrano i modelli; test verdi.

## Fase 6 — Suoni e tarantella

**Obiettivo:** la carta si sente.

Passi:
1. **Ricerca CC0** su internet (per esempio Freesound con il filtro CC0,
   OpenGameArt con il filtro CC0): suoni (mazzata di legno, «boing» dello
   schiacciamento, piatti e posate, monete, passi del nonno) e una tarantella
   col mandolino e la tammorra. Si tengono solo file **CC0 o pubblico dominio**
   con uso completo e libero anche a scopo di lucro. Si presentano all'utente i
   candidati con fonte e licenza; **si scarica solo dopo il suo sì**.
2. Quello che non si trova CC0 si fa **da codice** (`tools/audio`), come gli
   altri suoni del laboratorio; la tarantella da codice segue il metodo della
   musica del Brawler (ritmo in 6/8, mandolino pizzicato, tamburello).
3. Fonte e licenza di ogni file CC0 annotate nel repository (proposta:
   `assets/audio/LICENZE.md`).
4. Suoni e musica solo nel laboratorio, come per le altre carte (domanda
   all'utente: anche nel gioco vero?).

**Fatto quando:** l'utente approva suoni e musica nel laboratorio; la prova del
laboratorio conta i suoni nuovi.

## Fase 7 — Nel gioco vero

Passi:
1. Domanda all'utente: la carta entra nelle offerte, nei negozi e negli archivi
   dei biomi (si toglie `Lab_Only`), o resta solo laboratorio come le carte in
   prima persona?
2. Il film di «Mostra effetto» con le quattro facce (`card_demo.odin`).
3. Run, spedizione e campagna: salvataggi (vista, tavolata), costi della
   spedizione, vita massima di 32.
4. Partita di prova con l'utente; bilanciamento dei numeri.
5. Misure finali come nella Fase 0, spiegate in parole semplici; documenti
   ([meccaniche.md](regole/meccaniche.md)), registro delle carte, CHANGELOG,
   README.

**Fatto quando:** l'utente approva; `scripts/check.ps1` verde; prova completa
del laboratorio verde.

## Rischi

- **Peso della stanza (8 byte liberi).** Per questo bastone e nonno sono armi
  della vista nel `#raw_union` che c'è già e la tavolata è un oggetto della
  griglia. Se lo stato del nonno (corpo libero + vita + tasti usati) supera il
  più grande di oggi, si stringe (per esempio vita in `i16`, tasti in due bit)
  prima di far crescere la stanza.
- **La camera in terza persona sul tabellone:** muri alti, piani e coperture
  possono stare fra camera e Viandante. Braccio a molla e Viandante che sbiadisce
  lo risolvono; la Fase 2 lo prova con catture contro un muro e in un corridoio.
- **Mazzata sulla griglia con la visuale libera:** la casella davanti va scelta
  in modo chiaro (le 8 direzioni); la casella mirata va segnata a terra.
- **Due modi di muoversi nella stessa carta** (griglia nell'effetto 1, libero
  nel 4): riusare quello che c'è già (passi dell'AK, corpo dei pugni) e non
  scriverne uno nuovo.
- **Tasti Q ed E** fanno anche i passi in diagonale e la difesa: nella vista del
  nonno non devono fare altro; un test lo controlla.
- **Il nonno ospite non deve toccare le regole:** è solo immagine, guidata dagli
  eventi; se il mondo si ferma mentre arriva, si usa il meccanismo cinematico
  dei dadi.
- **Suoni CC0:** controllare la licenza sulla pagina di ogni singolo file (su
  Freesound ogni file ha la sua); niente CC-BY né licenze di siti.
- **Lavoro in parallelo:** `piano-succo` e `piano-prima-persona` sono rami
  dell'altra sessione; questo piano parte da `piano-succo` e non li modifica.

## Fonti

Il nonno napoletano e la tavola:
- [The Italian Coppola Hat (Tenement Museum)](https://yourstory.tenement.org/stories/the-italian-coppola-hat/): la coppola, anche portata storta
- [Pulcinella, storia della maschera (Bottega Capuano)](https://www.bottegacapuano.it/blogs/news/pulcinella-napoletano-storia-maschera-presepe)
- [Il pranzo della domenica napoletano (GialloZafferano)](https://blog.giallozafferano.it/cuordinutella/pranzo-della-domenica-napoletano/): ragù, parmigiana, babà, guantiera, caffè

L'asso di bastoni:
- [31 Asso di bastoni, mazzo napoletano (Wikimedia Commons)](https://commons.wikimedia.org/wiki/File:31_Asso_di_bastoni.jpg)
- [Bastoni (seme) — Carte da gioco (Wikipedia)](https://it.wikipedia.org/wiki/Bastoni_(seme))
- [Carte napoletane e piacentine (Wired)](https://www.wired.it/gallery/carte-gioco-napoletane-piacentine-briscola-regioni-giochi/)
- [Neapolitan pattern by Luigi Pignalosa (World of Playing Cards)](https://www.wopc.co.uk/italy/neapolitan-pattern-by-luigi-pignalosa)
- [The Neapolitan playing card deck](https://tuisnider.com/its-different-in-naples-italy-the-neapolitan-playing-card-deck/)

Schiacciamento:
- [Squash and stretch, volume costante (Adam Madej)](https://adammadej.com/posts/202403-squashstretch/)
- [Squash and Stretch, i 12 principi (Animation Mentor)](https://www.animationmentor.com/blog/squash-and-stretch-the-12-basic-principles-of-animation/)
- [Squash & Stretch Kit, la molla del ritorno](http://longbunnylabs.com/squash-stretch-kit-manual/)
- [Squashed Flat (TV Tropes)](https://tvtropes.org/pmwiki/pmwiki.php/Main/SquashedFlat)

Camera in terza persona e colpi:
- [Cinemachine 3rd Person Follow (Unity)](https://docs.unity3d.com/Packages/com.unity.cinemachine@2.10/manual/Cinemachine3rdPersonFollow.html)
- [Kingdom Come Deliverance II, una camera in terza persona (tkhquang)](https://tkhquang.dev/blog/posts/devlog-kingdom-come-deliverance-ii-building-a-proper-third-person-camera): braccio a molla, vicino subito e lontano piano
- [Third-person camera view in games: i problemi più comuni (Game Developer)](https://www.gamedeveloper.com/design/third-person-camera-view-in-games-a-record-of-the-most-common-problems-in-modern-games-solutions-taken-from-new-and-retro-games)
- [FOV comuni in terza persona (GameDev Stack Exchange)](https://gamedev.stackexchange.com/questions/135214/what-are-some-common-fov-for-third-person-games)
- [Hitstop nei picchiaduro a scorrimento (Shane Sicienski)](https://shane-sicienski.com/blog/blog-post-title-one-55pmn)

Un tiro di dado che sceglie l'effetto:
- [Dice Room (The Binding of Isaac Wiki)](https://bindingofisaacrebirth.wiki.gg/wiki/Dice_Room)
- [The Wheel of Fortune (Balatro Wiki)](https://balatrowiki.org/w/The_Wheel_of_Fortune)
- [Crowd control e ritorni decrescenti (Maxroll)](https://maxroll.gg/wow/resources/crowd-control-diminishing-returns): per non stordire per sempre lo stesso nemico
