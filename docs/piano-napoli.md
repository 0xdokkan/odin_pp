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
| 0 | Base: la carta, il D4 e i quattro rami nel laboratorio; misure di partenza | — | Fatta | vedi Esito |
| 1 | Il nonno ospite: tavolata (effetto 2) e borsellino (effetto 3), regole e prototipo | 0 | Fatta | vedi Esito |
| 2 | La terza persona e la mazzata (effetto 1), regole e prototipo | 0 | Fatta | vedi Esito |
| 3 | Lo schiacciamento alla Looney Tunes e il succo della mazzata | 2 | Fatta | vedi Esito |
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

### Esito (2 novembre 2026)

Scelte dell'utente all'inizio della fase: la **giocata critica dà un po' di
tutto** (bastone +3 s, tavolata e borsellino ×1,5, nonno +10 di vita; il minuto
resta un minuto); la carta si prova nell'**arena «Prima persona»**; un **tasto
del laboratorio fissa la faccia** del D4; sigla **`BAN`** e icona provvisoria
**il Vesuvio col pennacchio**.

1. **Misure di partenza** (sul commit di partenza `99e8799`, in una copia pulita
   del ramo):
   - `scripts/check.ps1` verde: **1857 test**, con e senza assert, in 9,5 minuti;
   - prova completa del laboratorio verde nella finestra vera: **2175 catture**
   in 15,6 minuti (i suoni sono i 152 della fine del piano del succo, che ha
   lo stesso codice);
   - peso della stanza: **9208 byte su 9216**; la carta non aggiunge niente alla
     stanza (la faccia, il numero e il livello viaggiano nell'effetto);
   - benchmark delle spedizioni: le corse C e D dell'appendice B di
     [piano-succo.md](piano-succo.md) sono state fatte sullo stesso commit di
     partenza e restano il riferimento; la corsa nuova (E) è nell'appendice A
     qui sotto.
2. **La carta** ([napoli.odin](../src/game/napoli.odin)): `Card_Id.Napoli`,
   «Benvenuti a Napoli», rara, 3 energia, prezzo 8, peso 60, `Lab_Only`, un
   dado (`dice_count = 1`), lo stesso tempo di lancio del Dinosauro, fino a 4
   potenziamenti come le carte coi dadi. Prezzo in spedizione 60. Un effetto
   nuovo, `.Napoli`, che tiene la faccia (1-4), il suo numero e il livello
   della carta. Non si gioca dentro una vista né in groppa al Dinosauro
   (`napoli_can_begin`).
3. **Il D4 e i rami:** `card_die_sides` tiene il D4 a ogni livello;
   `resolve_napoli_card` tira il dado come il Dinosauro, sceglie la faccia
   (`napoli_for_face`) e calcola il suo numero (`napoli_face_amount`) con i
   numeri dell'utente: bastone 30 s (+2), tavolata metà della vita massima
   (+2), borsellino 15 oro (+2), nonno 30 di vita (+5); la mazzata
   (`napoli_club_damage`) 8 (+1). L'evento nuovo `Napoli_Begun` dice faccia e
   numero; **i rami non fanno ancora nulla** (arrivano con le Fasi 1-4). Il
   pannello del dado dice il ramo («2 TAVOLATA», «CURA 11 VITA») e così la
   scritta sopra il Viandante («3 BORSELLINO +15 ORO»).
4. **Aspetto e suono provvisori:** icona del Vesuvio in una **decima riga**
   dell'atlante (cella 36; le icone di prima non si muovono di un pixel,
   `tools/art/build_card_icons.py`); suono della carta fatto da codice
   (`card_napoli`, [sfx_napoli.py](../tools/audio/sfx_napoli.py)): la carta che
   scatta, il D4 agitato in mano, poi un mandolino in tremolo sulla cadenza
   napoletana (Si bemolle maggiore, Mi maggiore, La minore: ♭II6 – V – i, la
   cadenza che porta il nome della città). Serviva un suono
   suo perché un test vuole un suono diverso per ogni carta. Rigenerati tutti
   i suoni: gli altri 233 sono identici byte per byte.
5. **Laboratorio:** la carta è nel mazzo dell'arena «Prima persona» (ora
   cinque carte in mano più la canna da pesca). **`F12`** fissa la faccia del
   D4 (A CASO, 1, 2, 3, 4) e il cartello lo scrive (`F12 D4: 2 TAVOLATA`); il
   tasto proposto era `F11`, ma `F11` è già lo schermo intero. Atto nuovo
   `mechanics_lab_napoli` (`ODIN_PP_LAB_ONLY=napoli`, per ultimo nella prova
   completa): la carta in mano, il giro di `F12`, poi la carta giocata quattro
   volte con la faccia fissata; per ognuna il dado gira, il pannello e la
   scritta dicono il ramo e il numero giusti. Catture
   `odin_pp_mechanics_lab_card_Napoli.png`, `odin_pp_napoli_dice_<faccia>.png`,
   `odin_pp_napoli_said_<faccia>.png` e `odin_pp_living_napoli_<faccia>_NN.png`.
6. **Test nuovi** ([napoli_test.odin](../src/game/napoli_test.odin)): carta
   rara del laboratorio con il D4 fisso; i numeri dell'utente a ogni livello;
   ogni faccia apre il suo ramo, col dado prima; la giocata critica; non si
   gioca in una vista né in groppa al Dinosauro (energia e dado restano).
   Aggiornati i test che contano le carte coi dadi, le carte del laboratorio
   (da 9 a 10), le icone dell'atlante e il mazzo dell'arena «Prima persona».
7. **Registro:** voce nuova in [registro-carte.md](registro-carte.md);
   [avvio.md](avvio.md) spiega `F12` e l'atto `napoli`.
8. **Verifiche:** `scripts/check.ps1` verde (**1862 test** con e senza assert);
   prova completa del laboratorio verde nella finestra vera (**2244 catture,
   153 suoni**, in 15,3 minuti; il suono della carta fra questi).
   **Benchmark delle spedizioni** sul codice nuovo, due corse (E e F,
   appendice A): in media un'immagine si disegna in **1,455 ms** e **1,483 ms**,
   contro **1,465 ms** delle corse C e D sul commit di partenza: −0,7% e +1,2%,
   cioè **nessuna differenza misurabile** (circa 680 fotogrammi al secondo). La
   corsa E aveva 17 scene oltre il 10% in tutte e due le direzioni (la scheda
   video ancora fredda); la F, ripetuta subito dopo, nessuna. Corsa e ingaggio
   (stage 25 e 26) nella F 1,65 e 1,71 ms come prima; le scene più pesanti
   (127, 20, 5, 177, 178) intorno a 2,0 ms, 500 al secondo. La carta è solo del
   laboratorio: le spedizioni cambiano solo per l'atlante delle icone più alto
   e la scritta nuova, che non costano nulla di misurabile.

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

### Esito (2 novembre 2026)

Scelte dell'utente all'inizio della fase: mentre arriva il nonno **il mondo si
ferma per circa 2 secondi**; la tavolata va **accanto al Viandante, lontano dai
nemici**; per mangiare il Viandante **resta seduto 2 secondi**, con la cura che
arriva **a poco a poco** (come le pozioni di Monster Hunter) e un colpo che **non
interrompe** il pranzo; la tavolata **blocca tutto**: passi, vista e frecce.

1. **Regole della tavolata** ([napoli.odin](../src/game/napoli.odin)): un
   oggetto nuovo della griglia, `Grid_Object_Kind.Napoli_Table` («Tavolata»),
   che blocca passi, vista e frecce e che nessuno può colpire. Il nonno la posa
   sulla casella libera accanto al Viandante più lontana dal nemico più vicino
   (a pari distanza: nord, est, sud, ovest, poi gli angoli), mai su un muro, un
   nemico, un oggetto, una trappola, l'uscita o oltre un gradino. Una sola alla
   volta: una nuova prende il posto della vecchia. Se attorno è tutto pieno, il
   nonno lo cura sul posto, tutta la cura subito. Sparisce con la fine del
   combattimento.
2. **Mangiare:** un passo contro la tavola (anche in diagonale) lo fa sedere:
   evento nuovo `Napoli_Feast`, il corpo occupato per **2 secondi del mondo**
   (niente passi, carte o schivate; niente difesa: i colpi li prende), la cura
   in due metà sui due battiti che passa seduto (11 = 6 + 5), poi la tavola si
   sparecchia (evento nuovo `Napoli_Table_Cleared`).
3. **Borsellino:** l'oro subito (`Gold_Gained`), 15 (+2 a potenziamento, ×1,5
   sulla giocata critica).
4. **Il nonno ospite, provvisorio** ([render/napoli.odin](../src/render/napoli.odin)):
   una figurina di carta in pixel art (coppola, baffoni bianchi, fazzoletto
   rosso, gilet scuro) che arriva dal lato della telecamera, così non resta mai
   dietro un muro o dietro il Viandante. Porta la tavola davanti a sé, la posa e
   se ne va; col borsellino glielo lancia. La visita è una scena **cinematica di
   2 secondi** (`presentation_cue_is_cinematic`): il mondo è fermo, come per il
   dado, e la scena non si accorcia al ritmo del Viandante. La tavola vera resta
   nascosta finché lui non l'ha posata.
5. **Aspetto provvisorio:** la tavola di resina come gli altri oggetti
   (tovaglia a quadri rossi e bianchi, due piatti di pasta al ragù, pane, una
   bottiglia), il borsellino una figurina di cuoio con le monete; scritte «A
   TAVOLA!» quando si siede e «2 TAVOLATA +11 VITA» all'arrivo. L'aspetto vero
   è della Fase 5.
6. **Salvataggio:** la spedizione salva la tavola come gli altri oggetti, anche
   a pranzo iniziato (test nuovo in
   [napoli_snapshot_test.odin](../src/expedition/napoli_snapshot_test.odin)).
   Il tipo nuovo sta in fondo all'elenco, così i salvataggi vecchi non cambiano.
7. **Test nuovi** ([napoli_test.odin](../src/game/napoli_test.odin)): la tavola
   lontano dai nemici e il caso d'angolo; tutto pieno = cura subito; una tavola
   alla volta; il passo che fa sedere, nessuna schivata, la cura in due battiti
   e la tavola che sparisce; due secondi occupato nel gioco a tempo, un colpo che
   non interrompe; l'oro del borsellino coi potenziamenti; la tavola che se ne
   va col combattimento.
8. **Laboratorio:** l'atto `napoli` ora prova anche le visite: il Viandante a 6
   di vita, la faccia 2, il nonno che arriva per 2 secondi col mondo fermo
   (controllati i fotogrammi e l'orologio del mondo), il passo nella tavola, la
   cura di 11 in due battiti, la tavola sparita; poi la faccia 3 e i 15 oro.
   Catture `odin_pp_napoli_table_NN.png`, `odin_pp_napoli_feast_NN.png` e
   `odin_pp_napoli_purse_NN.png`.
9. **Verifiche:** `scripts/check.ps1` verde (**1869 test** con e senza assert); prova
   completa del laboratorio verde nella finestra vera (**2347 catture, 153
   suoni**, in 16,3 minuti). **Prestazioni:** il disegno del tabellone ha tre
   controlli nuovi (la visita, la tavola in braccio, la tavola nascosta) che
   escono subito quando non c'è nessuna visita. Le prime due corse del
   benchmark davano la media uguale (1,462 e 1,493 ms contro 1,465) ma la scena
   157 più lenta del 15%; stasera però la macchina cambiava velocità fino al
   20% da una corsa all'altra, anche con il codice della Fase 0. Allora quattro
   corse in ordine incrociato (Fase 0, Fase 1, Fase 1, Fase 0) nelle stesse
   condizioni: media **1,668 ms** la Fase 0 e **1,692 ms** la Fase 1 (+1,4%), scena
   157 **2,05 e 2,08 ms** (+1,3%): **nessuna differenza misurabile**.

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

### Esito (3 novembre 2026)

Le scelte dell'utente all'inizio della fase:

| Domanda | Risposta |
|---|---|
| Stordire di continuo lo stesso nemico | **Ritorni decrescenti** come in World of Warcraft: 2 battiti, poi 1, poi niente sullo stesso nemico, finché non passano 4 s senza mazzate su di lui; il danno resta pieno |
| Ritmo della mazzata | **0,6 s:** 0,25 s di carica, impatto, 0,35 s di ritorno |
| Passo col bastone | **0,5 s** (il normale è 0,8, la spada 0,3; tutti dimezzati dal ritmo del Viandante) |
| Camera | **Spalla destra, vicina:** perno 0,35 caselle a destra e 1,45 in alto, camera 1,4 caselle dietro, FOV 70 |
| Mira | **8 direzioni + segno a terra** |
| Guardare su e giù | **Un po':** fino a 20° in su e 30° in giù |
| Mazzata a vuoto | **Picchia il pavimento**; rompe barili e blocchi di ghiaccio sulla casella |

Cosa c'è ora:
- **Regole** ([first_person_club.odin](../src/game/first_person_club.odin)): un'arma nuova della
  vista, `First_Person_Weapon.Club`, col suo stato nel `#raw_union` (non più grande di quello
  dell'arco: la stanza non cresce). La faccia 1 apre la vista (`tactical_begin_first_person`) e
  le dà il danno della carta; i secondi, il divieto delle carte e il salvataggio sono quelli della
  vista. Ogni fotogramma il comando `First_Person_Club` fa scorrere la mazzata coi secondi del
  mondo, come l'arco fa con le frecce. La mazzata parte solo col corpo libero e lo tiene
  occupato 0,6 s; un movimento a metà (una schivata) la annulla, e così la fine dei secondi.
  Colpisce la casella fra le 8 più vicina alla visuale (`club_way`); una diagonale chiusa da due
  muri non si colpisce. Senza nemico rompe solo quello che si rompe già con un urto (barile,
  blocco di ghiaccio), mai i dispositivi del giocatore. Lo stordimento ricorda fino a 4 nemici.
- **Comandi** ([first_person_input.odin](../src/run/first_person_input.odin),
  `drive_first_person_club`): il mouse gira la visuale, WASD fa i passi rispetto alla visuale
  come con l'AK, il clic sinistro tenuto dà una mazzata dopo l'altra.
- **Camera in terza persona** ([first_person_club.odin](../src/render/first_person_club.odin)):
  la discesa della prima persona porta la camera al posto dietro la spalla invece che agli occhi.
  Il braccio a molla lancia cinque raggi dal perno verso la camera (il suo e quattro attorno) e
  usa lo stesso controllo dei muri delle frecce dell'arco (`first_person_point_blocked`: muri,
  muretti, coperture, oggetti, rocce dei piani). Contro un muro la camera si avvicina subito e si
  ferma 0,15 caselle prima; poi torna indietro piano (95% in 0,3 s). Sotto 0,9 caselle il
  Viandante sbiadisce, fino al 20%. Il perno segue la scivolata del cartoncino, un po'
  ammorbidito.
- **Provvisori:** il Viandante è il suo cartoncino; il bastone è un manico rosso con la testa
  verde, appoggiato sulla spalla, che si alza dietro la testa e cala sulla casella. La casella
  mirata ha una cornice dorata a terra, rossa mentre la mazzata cala. Nel riquadro «BAN» e i
  secondi, nella riga dell'HUD «MOUSE: GIRA / CLIC: MAZZATA / WASD: PASSI», al centro solo un
  puntino.

Corretto durante la fase, dopo le prime catture del laboratorio:
1. **Il cartoncino copriva la mira.** Da 1,4 caselle il cartoncino del Viandante (largo quasi
   una casella, alto una e mezza) riempiva metà schermo e nascondeva il nemico davanti. Ora nella
   vista del bastone si vede **a metà** (50%), così il nemico si vede attraverso; contro un muro
   sbiadisce ancora di più. I numeri della camera restano quelli scelti; con il modello 3D di
   spalle della Fase 5 si potrà tornare a un Viandante pieno.
2. **Lo sguardo parte un po' in giù** (11°): la camera sta sopra la testa del cartoncino e la
   casella segnata si vede subito.
3. **Il bastone davanti all'obiettivo.** Con la camera schiacciata contro un muro il manico
   passava davanti alla camera: lì il bastone non si disegna.
4. **Test vecchi da aggiornare.** Ora la carta conta come «carta della vista»
   (`card_is_first_person`), ma il suo D4 si lancia ancora col tempo del Dinosauro: il test dei
   tempi la tiene fuori dall'eccezione. Il film di «Mostra effetto» chiude la vista del bastone
   dopo un secondo e mezzo, come fa con spada e arco (il film vero è della Fase 7). Un secondo
   di clic tenuto dà due mazzate.

Verifiche:
- `scripts/check.ps1`: **1879 test** verdi, con e senza assert (erano 1869: 7 test nuovi sulle
  regole del bastone, 3 sulla camera).
- Atto `napoli` del laboratorio: il bastone si prende, W fa il passo dove guarda la visuale, il
  segno a terra è sul bruto, tre mazzate da 8 con stordimento 2, 1, 0; contro il muro il braccio
  è di 0,36 caselle e la camera non entra mai nel muro.
- Prova completa del laboratorio: **2414 catture, 153 suoni**, verde.
- Bilanciamento (prova automatica di un minuto, `first_person_balance_test`): il bastone fa
  **6,4 danni al secondo** e ne prende 0,23; l'AK 4,8, la spada 3,1, i pugni 14,3, l'arco 8,9.
- Prestazioni: quattro corse del benchmark in ordine incrociato (Fase 1, Fase 2, Fase 2,
  Fase 1). La macchina è rallentata del 21% fra la prima e l'ultima corsa della stessa Fase 1
  (1,452 → 1,764 ms); in media la Fase 2 fa 1,545 ms contro 1,608 (−3,9%): **nessuna
  differenza misurabile**. Fuori dalla vista del bastone la camera e il bastone non fanno niente.

Da provare con l'utente: camera, comandi e il Viandante a metà trasparenza.

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

### Esito (3 novembre 2026)

Le scelte dell'utente all'inizio della fase:

| Domanda | Risposta |
|---|---|
| Quanto si schiaccia | **Più forte del piano:** al 30% dell'altezza in 0,06 s, larga 1/√altezza (circa 1,8 volte), piatta 0,08 s, poi la molla fino al 112% e si posa; tutto in 0,6 s |
| Peso della mazzata | **Come il piano:** pausa di 90 ms, scossa 0,45, schegge di carta e polvere; a vuoto solo una scossa piccola e la polvere |
| Il nemico stordito | **Stelline sulla testa** finché dura lo stordimento |
| La mazzata che uccide | **Frittella:** la carta resta schiacciata piatta mentre cade |
| Controlli | Da questa fase l'utente vuole **solo i controlli di quello che si fa** e di quello che può toccare, non la verifica completa né la prova completa del laboratorio |

Cosa c'è ora ([club_juice.odin](../src/render/club_juice.odin)):
- **Schiacciamento** (`juice_squash_shape`): solo immagine, la casella e le regole non
  cambiano. Si applica in `living_billboard_geometry` attorno ai piedi della carta, che restano a
  terra; anche il bordo di carta si schiaccia con il disegno. La molla è smorzata, col primo picco
  al 112% 0,14 s dopo la pausa da piatta, e a 0,6 s la carta è ferma (la differenza è sotto il
  millesimo).
- **Frittella:** se il colpo uccide la carta scende al 18% e resta così mentre cade, larga al
  massimo 2 volte (con 1/√altezza sarebbe 2,4).
- **Succo:** la ferita del bastone (`event_is_first_person_club`) dà la pausa di 90 ms, la
  scossa 0,45, il lampo bianco della carta, le schegge dal punto colpito e la polvere dal
  pavimento; niente arretramento, perché schiacciata la carta resta dov'è. La mazzata a vuoto
  dà una scossa di 0,15 e la polvere sulla casella; su un barile o un blocco di ghiaccio 0,25 e
  anche le schegge. Dietro la spalla ora la camera trema col succo come quella del tabellone (in
  prima persona no, ha il suo).
- **Stelline:** tre stelle di carta gialle col bordo d'inchiostro girano sopra la testa del
  nemico che il bastone ha stordito, finché ha lo stato `Stagger`; con la carta schiacciata
  scendono anche loro.

Corretto durante la fase: le stelline uscivano scure, perché scrivevano la profondità e il
passaggio finale del tabellone le scuriva; ora si disegnano come le schegge dei colpi, sopra
le carte e senza profondità.

Verifiche (solo quello che la fase tocca, la scelta dell'utente):
- `odin check src -vet -strict-style` pulito.
- 4 test nuovi ([club_juice_test.odin](../src/render/club_juice_test.odin)): la forma dello
  schiacciamento (volume, 30%, picco al 112%, fermo a 0,6 s, frittella), i piedi a terra, un
  colpo vero sul tabellone (pausa, scossa, schiacciamento, stelline, polvere a vuoto) e il colpo
  che uccide. Con loro **78 test** del tabellone su vista, succo, carte vive e colpi: verdi.
- Atto `napoli` del laboratorio: la prima mazzata schiaccia il bruto fino a **0,30** e lo lascia
  con le stelline, la quarta lo uccide a frittella; tutto il resto dell'atto (facce, visite,
  bastone, camera contro il muro) ancora verde.
- Non fatti, come chiesto: la verifica completa (`scripts/check.ps1`), la prova completa del
  laboratorio e il benchmark. Senza mazzate del bastone lo schiacciamento e le stelline non fanno
  niente (un ciclo su 8 voci per carta).

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

Il suono provvisorio della carta (Fase 0):
- [The Neapolitan sixth, ♭II6 (Open Music Theory)](https://pressbooks.nebraska.edu/openmusictheory/chapter/bii6/): la cadenza ♭II6 – V – i, più comune in minore
- [Mandolin (Wikipedia)](https://en.wikipedia.org/wiki/Mandolin): il tremolo sui cori di due corde accordate all'unisono

Mangiare seduti e vulnerabili (Fase 1):
- [Monster Hunter's animations make you a better player (Kotaku)](https://kotaku.com/monster-hunters-animations-make-you-a-better-player-1822776242): l'animazione che impegna il giocatore e lo lascia esposto, come la pozione bevuta

Un tiro di dado che sceglie l'effetto:
- [Dice Room (The Binding of Isaac Wiki)](https://bindingofisaacrebirth.wiki.gg/wiki/Dice_Room)
- [The Wheel of Fortune (Balatro Wiki)](https://balatrowiki.org/w/The_Wheel_of_Fortune)
- [Crowd control e ritorni decrescenti (Maxroll)](https://maxroll.gg/wow/resources/crowd-control-diminishing-returns): per non stordire per sempre lo stesso nemico

Il bastone (Fase 2):
- [Crowd control (Warcraft Wiki)](https://warcraft.wiki.gg/wiki/Crowd_Control): i ritorni decrescenti, metà e poi un quarto, poi immune
- [Diablo III, il controllo dei nemici nella patch 1.0.5 (GameBanshee)](https://www.gamebanshee.com/news/109393-diablo-iii-v105-patch-crowd-control-changes.html): perché in un gioco d'azione veloce i ritorni decrescenti vanno tenuti semplici
- [Third-person camera with spring arm (Godot)](https://docs.godotengine.org/en/stable/tutorials/3d/spring_arm.html): il braccio a molla che controlla gli urti ogni fotogramma e avvicina la camera al punto toccato

## Appendice A — Misure della Fase 0, scena per scena

Benchmark delle spedizioni (2 novembre 2026), RTX 3060 Laptop, canvas 1920×1080, `-o:speed`, sul codice della Fase 0,
due corse (E e F), accanto alle corse C e D dell'appendice B di [piano-succo.md](piano-succo.md), fatte sul commit di
partenza. Tempo di un'immagine in millisecondi: media e 95° percentile. Sotto il 10% di differenza è rumore.

| Stage | Bioma | Media C | Media D | Media E | Media F | p95 E | p95 F |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 1.45 | 1.22 | 1.45 | 1.45 | 1.74 | 1.68 |
| 1 | 0 | 1.69 | 1.68 | 1.71 | 1.69 | 2.36 | 2.32 |
| 2 | 0 | 1.21 | 1.23 | 1.21 | 1.24 | 1.46 | 1.40 |
| 3 | 0 | 1.27 | 1.27 | 1.34 | 1.27 | 1.68 | 1.45 |
| 4 | 0 | 1.27 | 1.34 | 1.26 | 1.27 | 1.43 | 1.42 |
| 5 | 0 | 1.94 | 1.97 | 1.97 | 1.97 | 2.77 | 2.88 |
| 6 | 0 | 1.64 | 1.65 | 1.64 | 1.66 | 2.42 | 2.41 |
| 7 | 0 | 1.58 | 1.60 | 1.58 | 1.60 | 1.80 | 1.79 |
| 8 | 1 | 1.58 | 1.64 | 1.57 | 1.61 | 1.76 | 1.81 |
| 9 | 2 | 1.62 | 1.64 | 1.64 | 1.66 | 2.39 | 2.45 |
| 10 | 3 | 1.65 | 1.64 | 1.65 | 1.65 | 2.43 | 2.46 |
| 11 | 4 | 1.66 | 1.67 | 1.67 | 1.67 | 2.50 | 2.53 |
| 12 | 5 | 1.14 | 1.17 | 1.16 | 1.16 | 1.31 | 1.36 |
| 13 | 6 | 1.47 | 1.50 | 1.48 | 1.50 | 1.68 | 1.70 |
| 14 | 7 | 1.64 | 1.67 | 1.66 | 1.67 | 2.44 | 2.47 |
| 15 | 8 | 1.20 | 1.23 | 1.22 | 1.24 | 1.48 | 1.56 |
| 16 | 9 | 1.53 | 1.56 | 1.58 | 1.54 | 2.03 | 1.72 |
| 17 | 10 | 1.67 | 1.70 | 1.57 | 1.71 | 2.04 | 2.58 |
| 18 | 11 | 1.63 | 1.67 | 1.48 | 1.68 | 1.58 | 2.46 |
| 19 | 11 | 1.64 | 1.67 | 1.51 | 1.66 | 1.57 | 2.46 |
| 20 | 11 | 1.99 | 2.00 | 1.80 | 1.99 | 2.10 | 2.60 |
| 21 | 11 | 1.63 | 1.64 | 1.50 | 1.67 | 1.60 | 2.44 |
| 22 | 11 | 1.49 | 1.52 | 1.31 | 1.52 | 1.39 | 2.30 |
| 23 | 11 | 1.76 | 1.77 | 1.56 | 1.78 | 1.88 | 2.36 |
| 24 | 11 | 1.60 | 1.62 | 1.58 | 1.61 | 1.64 | 1.83 |
| 25 | 11 | 1.64 | 1.67 | 1.50 | 1.65 | 1.66 | 2.44 |
| 26 | 11 | 1.68 | 1.71 | 1.53 | 1.71 | 1.78 | 2.41 |
| 27 | 0 | 1.60 | 1.58 | 1.53 | 1.59 | 1.81 | 2.40 |
| 28 | 1 | 1.64 | 1.66 | 1.46 | 1.65 | 1.52 | 2.42 |
| 29 | 2 | 1.64 | 1.65 | 1.41 | 1.64 | 1.49 | 2.39 |
| 30 | 3 | 1.82 | 1.87 | 1.84 | 1.86 | 2.11 | 2.11 |
| 31 | 4 | 1.67 | 1.67 | 1.52 | 1.69 | 1.63 | 2.48 |
| 32 | 5 | 1.11 | 1.13 | 1.25 | 1.12 | 1.80 | 1.31 |
| 33 | 6 | 1.62 | 1.63 | 1.42 | 1.66 | 1.51 | 2.43 |
| 34 | 7 | 1.46 | 1.50 | 1.29 | 1.49 | 1.46 | 2.30 |
| 35 | 8 | 1.30 | 1.34 | 1.22 | 1.34 | 1.50 | 2.02 |
| 36 | 9 | 1.23 | 1.24 | 1.25 | 1.26 | 1.41 | 1.46 |
| 37 | 10 | 1.50 | 1.49 | 1.33 | 1.53 | 1.48 | 2.29 |
| 38 | 11 | 1.25 | 1.25 | 1.25 | 1.24 | 1.44 | 1.40 |
| 39 | 0 | 1.64 | 1.68 | 1.67 | 1.68 | 1.75 | 1.91 |
| 40 | 1 | 1.61 | 1.63 | 1.48 | 1.64 | 1.53 | 2.43 |
| 41 | 2 | 1.41 | 1.46 | 1.42 | 1.45 | 1.47 | 1.71 |
| 42 | 3 | 1.82 | 1.83 | 1.75 | 1.85 | 1.84 | 2.75 |
| 43 | 4 | 1.70 | 1.73 | 1.49 | 1.75 | 1.54 | 2.52 |
| 44 | 5 | 1.22 | 1.24 | 1.23 | 1.22 | 1.72 | 1.93 |
| 45 | 6 | 1.57 | 1.61 | 1.58 | 1.61 | 1.65 | 1.81 |
| 46 | 7 | 1.62 | 1.66 | 1.63 | 1.65 | 1.67 | 1.87 |
| 47 | 8 | 1.18 | 1.20 | 1.33 | 1.19 | 1.94 | 1.42 |
| 48 | 9 | 1.44 | 1.46 | 1.46 | 1.47 | 1.50 | 1.68 |
| 49 | 10 | 1.52 | 1.53 | 1.53 | 1.53 | 1.71 | 1.74 |
| 50 | 11 | 1.51 | 1.52 | 1.52 | 1.52 | 1.63 | 1.68 |
| 51 | 6 | 1.70 | 1.71 | 1.64 | 1.72 | 1.81 | 1.95 |
| 52 | 1 | 1.60 | 1.61 | 1.62 | 1.64 | 1.94 | 1.89 |
| 53 | 2 | 1.66 | 1.66 | 1.68 | 1.68 | 2.07 | 2.07 |
| 54 | 10 | 1.55 | 1.59 | 1.76 | 1.57 | 2.14 | 1.78 |
| 55 | 0 | 1.73 | 1.76 | 1.59 | 1.77 | 1.64 | 2.65 |
| 56 | 0 | 1.65 | 1.71 | 1.58 | 1.75 | 1.64 | 2.66 |
| 57 | 0 | 1.53 | 1.52 | 1.54 | 1.51 | 1.84 | 1.67 |
| 58 | 0 | 1.44 | 1.43 | 1.41 | 1.43 | 1.51 | 1.68 |
| 59 | 0 | 1.39 | 1.42 | 1.39 | 1.42 | 1.51 | 1.63 |
| 60 | 0 | 1.47 | 1.49 | 1.47 | 1.49 | 1.56 | 1.71 |
| 61 | 0 | 1.56 | 1.69 | 1.55 | 1.72 | 1.61 | 2.54 |
| 62 | 0 | 1.25 | 1.43 | 1.25 | 1.42 | 1.38 | 2.15 |
| 63 | 0 | 1.46 | 1.66 | 1.48 | 1.70 | 1.67 | 2.43 |
| 64 | 1 | 1.48 | 1.70 | 1.47 | 1.70 | 1.63 | 2.45 |
| 65 | 2 | 1.39 | 1.63 | 1.40 | 1.64 | 1.44 | 2.42 |
| 66 | 3 | 1.58 | 1.75 | 1.60 | 1.76 | 1.80 | 2.59 |
| 67 | 4 | 1.31 | 1.53 | 1.32 | 1.51 | 1.42 | 2.27 |
| 68 | 5 | 1.11 | 1.13 | 1.09 | 1.12 | 1.47 | 1.32 |
| 69 | 6 | 1.27 | 1.51 | 1.28 | 1.49 | 1.43 | 2.23 |
| 70 | 7 | 1.46 | 1.67 | 1.46 | 1.65 | 1.53 | 2.43 |
| 71 | 8 | 1.21 | 1.27 | 1.18 | 1.27 | 1.44 | 1.69 |
| 72 | 9 | 1.40 | 1.61 | 1.42 | 1.62 | 1.58 | 2.41 |
| 73 | 10 | 1.34 | 1.55 | 1.34 | 1.55 | 1.50 | 2.45 |
| 74 | 11 | 1.41 | 1.57 | 1.41 | 1.61 | 1.61 | 2.40 |
| 75 | 4 | 1.35 | 1.43 | 1.43 | 1.45 | 1.67 | 1.62 |
| 76 | 6 | 1.35 | 1.67 | 1.37 | 1.64 | 1.57 | 2.20 |
| 77 | 9 | 1.27 | 1.34 | 1.30 | 1.39 | 1.50 | 1.61 |
| 78 | 6 | 1.74 | 1.81 | 1.73 | 1.79 | 1.97 | 2.68 |
| 79 | 6 | 1.38 | 1.41 | 1.38 | 1.40 | 1.43 | 1.57 |
| 80 | 6 | 1.30 | 1.54 | 1.29 | 1.51 | 1.35 | 2.27 |
| 81 | 6 | 1.38 | 1.56 | 1.38 | 1.46 | 1.45 | 2.23 |
| 82 | 6 | 1.23 | 1.23 | 1.23 | 1.23 | 1.31 | 1.27 |
| 83 | 6 | 1.29 | 1.31 | 1.30 | 1.31 | 1.41 | 1.35 |
| 84 | 6 | 1.22 | 1.26 | 1.23 | 1.28 | 1.32 | 1.54 |
| 85 | 6 | 1.20 | 1.22 | 1.20 | 1.21 | 1.31 | 1.29 |
| 86 | 6 | 1.19 | 1.21 | 1.20 | 1.21 | 1.31 | 1.36 |
| 87 | 6 | 1.27 | 1.28 | 1.29 | 1.28 | 1.43 | 1.33 |
| 88 | 6 | 1.24 | 1.25 | 1.24 | 1.25 | 1.31 | 1.30 |
| 89 | 6 | 1.24 | 1.26 | 1.24 | 1.25 | 1.33 | 1.31 |
| 90 | 1 | 1.38 | 1.40 | 1.37 | 1.39 | 1.43 | 1.45 |
| 91 | 1 | 1.45 | 1.45 | 1.46 | 1.45 | 1.72 | 1.61 |
| 92 | 1 | 1.43 | 1.44 | 1.45 | 1.44 | 1.62 | 1.55 |
| 93 | 4 | 1.33 | 1.35 | 1.34 | 1.36 | 1.41 | 1.42 |
| 94 | 4 | 1.30 | 1.33 | 1.31 | 1.32 | 1.40 | 1.37 |
| 95 | 4 | 1.25 | 1.27 | 1.26 | 1.27 | 1.37 | 1.38 |
| 96 | 7 | 1.35 | 1.38 | 1.37 | 1.36 | 1.67 | 1.41 |
| 97 | 7 | 1.44 | 1.40 | 1.42 | 1.39 | 1.65 | 1.52 |
| 98 | 7 | 1.40 | 1.41 | 1.44 | 1.44 | 1.69 | 1.66 |
| 99 | 4 | 1.23 | 1.24 | 1.33 | 1.23 | 1.71 | 1.34 |
| 100 | 4 | 1.22 | 1.24 | 1.23 | 1.24 | 1.32 | 1.30 |
| 101 | 4 | 1.37 | 1.39 | 1.38 | 1.38 | 1.49 | 1.48 |
| 102 | 4 | 1.26 | 1.28 | 1.26 | 1.26 | 1.35 | 1.34 |
| 103 | 6 | 1.38 | 1.40 | 1.39 | 1.39 | 1.48 | 1.47 |
| 104 | 0 | 1.31 | 1.33 | 1.38 | 1.31 | 1.69 | 1.46 |
| 105 | 0 | 1.43 | 1.44 | 1.78 | 1.44 | 2.73 | 1.53 |
| 106 | 0 | 1.42 | 1.44 | 1.56 | 1.43 | 2.27 | 1.57 |
| 107 | 0 | 1.36 | 1.39 | 1.48 | 1.39 | 1.96 | 1.53 |
| 108 | 0 | 1.33 | 1.35 | 1.47 | 1.35 | 2.04 | 1.52 |
| 109 | 0 | 1.65 | 1.66 | 1.87 | 1.73 | 2.21 | 2.06 |
| 110 | 1 | 1.48 | 1.49 | 1.50 | 1.49 | 1.75 | 1.55 |
| 111 | 1 | 1.27 | 1.30 | 1.31 | 1.29 | 1.49 | 1.40 |
| 112 | 1 | 1.22 | 1.22 | 1.25 | 1.23 | 1.40 | 1.34 |
| 113 | 1 | 1.25 | 1.26 | 1.25 | 1.26 | 1.39 | 1.39 |
| 114 | 1 | 1.21 | 1.23 | 1.23 | 1.24 | 1.36 | 1.37 |
| 115 | 1 | 1.46 | 1.48 | 2.01 | 1.51 | 3.22 | 1.67 |
| 116 | 2 | 1.41 | 1.43 | 1.71 | 1.44 | 2.90 | 1.54 |
| 117 | 2 | 1.19 | 1.19 | 1.20 | 1.19 | 1.35 | 1.29 |
| 118 | 2 | 1.16 | 1.15 | 1.14 | 1.16 | 1.24 | 1.29 |
| 119 | 2 | 1.13 | 1.14 | 1.14 | 1.18 | 1.23 | 1.52 |
| 120 | 2 | 1.25 | 1.25 | 1.27 | 1.25 | 1.78 | 1.82 |
| 121 | 2 | 1.41 | 1.42 | 1.66 | 1.45 | 2.16 | 1.64 |
| 122 | 3 | 1.68 | 1.69 | 1.69 | 1.70 | 1.99 | 1.80 |
| 123 | 3 | 1.85 | 1.84 | 1.86 | 1.84 | 2.15 | 1.91 |
| 124 | 3 | 1.78 | 1.78 | 1.80 | 1.77 | 1.99 | 1.91 |
| 125 | 3 | 1.62 | 1.61 | 1.61 | 1.63 | 1.82 | 1.83 |
| 126 | 3 | 1.63 | 1.62 | 1.60 | 1.63 | 1.76 | 1.79 |
| 127 | 3 | 1.98 | 2.00 | 1.97 | 2.04 | 2.12 | 2.27 |
| 128 | 4 | 1.12 | 1.16 | 1.14 | 1.12 | 1.74 | 1.70 |
| 129 | 4 | 1.28 | 1.29 | 1.28 | 1.28 | 1.38 | 1.34 |
| 130 | 4 | 1.28 | 1.28 | 1.28 | 1.33 | 1.40 | 1.58 |
| 131 | 4 | 1.52 | 1.52 | 1.53 | 1.57 | 1.72 | 1.93 |
| 132 | 4 | 1.32 | 1.35 | 1.36 | 1.34 | 1.71 | 1.47 |
| 133 | 4 | 1.72 | 1.69 | 1.81 | 1.79 | 2.04 | 1.97 |
| 134 | 5 | 1.06 | 1.07 | 1.09 | 1.07 | 1.29 | 1.23 |
| 135 | 5 | 1.16 | 1.20 | 1.18 | 1.21 | 1.76 | 1.87 |
| 136 | 5 | 1.19 | 1.15 | 1.19 | 1.15 | 1.70 | 1.39 |
| 137 | 5 | 1.18 | 1.16 | 1.16 | 1.16 | 1.47 | 1.57 |
| 138 | 5 | 1.17 | 1.10 | 1.10 | 1.10 | 1.33 | 1.28 |
| 139 | 5 | 1.57 | 1.57 | 1.60 | 1.71 | 1.78 | 2.03 |
| 140 | 6 | 1.51 | 1.52 | 1.50 | 1.50 | 1.68 | 1.61 |
| 141 | 6 | 1.46 | 1.47 | 1.49 | 1.47 | 1.69 | 1.61 |
| 142 | 6 | 1.46 | 1.44 | 1.58 | 1.44 | 2.05 | 1.54 |
| 143 | 6 | 1.44 | 1.45 | 1.46 | 1.46 | 1.62 | 1.59 |
| 144 | 6 | 1.44 | 1.45 | 1.44 | 1.46 | 1.57 | 1.64 |
| 145 | 6 | 1.67 | 1.69 | 1.70 | 1.68 | 1.94 | 1.85 |
| 146 | 7 | 1.65 | 1.68 | 1.67 | 1.68 | 1.74 | 1.76 |
| 147 | 7 | 1.55 | 1.55 | 1.55 | 1.56 | 1.71 | 1.72 |
| 148 | 7 | 1.48 | 1.47 | 1.48 | 1.48 | 1.56 | 1.59 |
| 149 | 7 | 1.58 | 1.62 | 1.58 | 1.61 | 1.75 | 1.79 |
| 150 | 7 | 1.63 | 1.67 | 1.65 | 1.66 | 1.72 | 1.72 |
| 151 | 7 | 1.72 | 1.74 | 1.72 | 1.71 | 1.90 | 1.88 |
| 152 | 8 | 1.44 | 1.48 | 1.42 | 1.43 | 2.16 | 2.18 |
| 153 | 8 | 1.42 | 1.42 | 1.42 | 1.40 | 2.15 | 2.14 |
| 154 | 8 | 1.44 | 1.43 | 1.39 | 1.38 | 2.09 | 2.13 |
| 155 | 8 | 1.26 | 1.30 | 1.32 | 1.29 | 2.03 | 1.49 |
| 156 | 8 | 1.27 | 1.32 | 1.27 | 1.29 | 1.51 | 1.55 |
| 157 | 8 | 1.60 | 1.60 | 1.64 | 1.65 | 1.89 | 1.77 |
| 158 | 9 | 1.29 | 1.37 | 1.31 | 1.31 | 1.49 | 1.41 |
| 159 | 9 | 1.35 | 1.39 | 1.36 | 1.36 | 1.61 | 1.64 |
| 160 | 9 | 1.38 | 1.40 | 1.36 | 1.36 | 1.50 | 1.54 |
| 161 | 9 | 1.34 | 1.35 | 1.36 | 1.42 | 1.63 | 1.69 |
| 162 | 9 | 1.42 | 1.33 | 1.38 | 1.36 | 1.66 | 1.54 |
| 163 | 9 | 1.57 | 1.59 | 1.63 | 1.62 | 1.87 | 1.84 |
| 164 | 10 | 1.44 | 1.46 | 1.46 | 1.45 | 1.63 | 1.52 |
| 165 | 10 | 1.36 | 1.38 | 1.38 | 1.35 | 1.44 | 1.40 |
| 166 | 10 | 1.45 | 1.43 | 1.45 | 1.40 | 1.75 | 1.53 |
| 167 | 10 | 1.47 | 1.47 | 1.45 | 1.46 | 1.58 | 1.61 |
| 168 | 10 | 1.46 | 1.48 | 1.47 | 1.49 | 1.57 | 1.65 |
| 169 | 10 | 1.69 | 1.69 | 1.70 | 1.77 | 1.85 | 2.04 |
| 170 | 11 | 1.63 | 1.65 | 1.63 | 1.67 | 1.70 | 1.86 |
| 171 | 11 | 1.38 | 1.38 | 1.37 | 1.38 | 1.47 | 1.55 |
| 172 | 11 | 1.32 | 1.32 | 1.32 | 1.29 | 1.45 | 1.41 |
| 173 | 11 | 1.43 | 1.42 | 1.40 | 1.41 | 1.57 | 1.55 |
| 174 | 11 | 1.33 | 1.35 | 1.35 | 1.34 | 1.57 | 1.43 |
| 175 | 11 | 1.66 | 1.65 | 1.66 | 1.67 | 1.88 | 1.96 |
| 176 | 3 | 1.81 | 1.82 | 1.85 | 1.83 | 2.22 | 2.15 |
| 177 | 3 | 1.99 | 1.99 | 2.00 | 1.97 | 2.07 | 2.02 |
| 178 | 3 | 1.96 | 1.96 | 1.97 | 1.94 | 2.19 | 2.13 |
| 179 | 4 | 1.57 | 1.58 | 1.55 | 1.57 | 1.64 | 1.64 |
| 180 | 4 | 1.47 | 1.47 | 1.47 | 1.47 | 1.64 | 1.59 |
| 181 | 4 | 1.31 | 1.33 | 1.32 | 1.34 | 1.42 | 1.43 |
| 182 | 5 | 1.22 | 1.22 | 1.24 | 1.25 | 1.72 | 1.92 |
| 183 | 5 | 1.34 | 1.37 | 1.34 | 1.35 | 2.12 | 1.80 |
| 184 | 5 | 1.31 | 1.34 | 1.32 | 1.32 | 1.52 | 1.49 |
| 185 | 8 | 1.16 | 1.19 | 1.21 | 1.19 | 1.45 | 1.43 |
| 186 | 8 | 1.29 | 1.33 | 1.32 | 1.34 | 1.49 | 1.59 |
| 187 | 8 | 1.32 | 1.34 | 1.31 | 1.32 | 2.06 | 2.05 |
| 188 | 10 | 1.40 | 1.45 | 1.40 | 1.45 | 1.52 | 1.71 |
| 189 | 10 | 1.35 | 1.34 | 1.34 | 1.35 | 1.47 | 1.45 |
| 190 | 10 | 1.45 | 1.50 | 1.48 | 1.46 | 1.73 | 1.62 |
| 191 | 3 | 1.62 | 1.64 | 1.62 | 1.63 | 1.74 | 1.76 |
| 192 | 3 | 1.50 | 1.51 | 1.49 | 1.51 | 1.55 | 1.56 |
| 193 | 3 | 1.52 | 1.52 | 1.51 | 1.52 | 1.61 | 1.59 |
| 194 | 11 | 1.50 | 1.48 | 1.48 | 1.49 | 1.63 | 1.64 |
