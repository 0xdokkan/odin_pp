[← Odin PP](../README.md)

# Registro delle carte

Qui si segna ogni carta tolta dal gioco o cambiata, con quello che faceva, così da poterla confrontare o rimettere in
futuro. Le voci più recenti stanno in cima. Per ritrovare il commit di una voce:
`git log --all --grep "<titolo del commit>"`.

## 2026-10-29 — Carta nuova: First Person Archer (solo laboratorio)

Commit **«Prima persona, Fase 6, passi 1-5: l'arco, regole e prototipo»** sul ramo `piano-prima-persona`
([piano](piano-prima-persona.md), Fase 6).

| Carta | Nel codice | Rarità | Energia | Effetto | Peso nelle offerte | Dove sta |
|---|---|---|---:|---|---:|---|
| First Person Archer | `First_Person_Archer` | rara | 3 | su di sé, 0 s di finestra: la vista in prima persona con l'arco per 30 s del mondo (+2 a potenziamento, fino a 40 a +5): a griglia come l'AK; destro tenuto tende (piena in 1,6 s), rilasciato tira, sinistro abbassa; da 0 a 4 rimbalzi sui muri secondo la carica, ognuno ×1,25 di velocità; danno 2 × velocità / 12, fino al 50% in più con i rimbalzi (da 2 a 15); cinque frecce a caso (veleno, fuoco, ghiaccio, stordente, dentata) con i loro stati; tre zone critiche sui muri (×1,6 e un rimbalzo gratis) | 60 (ma `Lab_Only`: mai offerta) | solo nell'arena «Prima persona» del laboratorio, nel suo mazzo |

- È la quarta arma della vista di First Person Shooter (`First_Person_Weapon.Bow`); non si gioca in groppa al Dinosauro.
- La freccia che torna sul Viandante rimbalza su di lui senza ferirlo, e conta come un rimbalzo gratis (la scelta
  dell'utente); vola e colpisce anche fuori vista; frecce infinite.
- Icona (cella 35): l'arco compound Neon di lato, la scelta dell'utente per la Fase 7. Suono della carta
  (`card_first_person_archer`): le carrucole che girano, la corda che vibra (Karplus-Strong), il fischio.
- **Fase 7 (aspetto e suoni):** l'arco è un compound Neon in 3D con le carrucole (la scelta dell'utente), frecce con la
  scia del loro colore, scintille ai rimbalzi, zone critiche come bersagli di carta con la luce che pulsa, la faretra
  attorno al mirino; suoni suoi (un ping più alto a ogni rimbalzo) e una musica sua nel laboratorio. Le regole non
  cambiano.

## 2026-10-29 — Carta nuova: First Person Fencer (solo laboratorio)

Commit **«Prima persona, Fase 4, passo 6: First Person Fencer nel laboratorio»** sul ramo `piano-prima-persona`
([piano](piano-prima-persona.md), Fase 4).

| Carta | Nel codice | Rarità | Energia | Effetto | Peso nelle offerte | Dove sta |
|---|---|---|---:|---|---:|---|
| First Person Fencer | `First_Person_Fencer` | rara | 3 | su di sé, 0 s di finestra: la vista in prima persona con la spada per 35 s del mondo (+2 a potenziamento, fino a 45 a +5; erano 20, alzati dopo la prova dell'utente): a griglia con passi di 0,3 s, `Q`/`E` di 90°, la lama mossa dal mouse (danno da velocità, ampiezza, linea, punto della lama e direzione: fino a 11), parata senza limite con il destro (perfetta entro 0,25 s), rampino con `Ctrl` | 60 (ma `Lab_Only`: mai offerta) | solo nell'arena «Prima persona» del laboratorio, nel suo mazzo |

- È la terza arma della vista di First Person Shooter (`First_Person_Weapon.Sword`); non si gioca in groppa al Dinosauro.
- **Dopo la prova dell'utente:** niente più attesa fra un taglio e l'altro (ogni passaggio sul petto taglia, anche al
  ritorno, dopo almeno un quinto di schermo di strada); affondo ×1,25 con un passo durante lo swing; colpo roteante ×1,5
  girando con `Q`/`E` nel verso della lama; striscia di sangue, lampo, fermo della lama e scossa al colpo.
- **Terza prova:** durata da 20 a **35 s** (pochi colpi senza i passi liberi né la distanza); il colpo roteante si vede
  (scia magenta dal giro, parole `COLPO ROTEANTE x1,5` accanto al nemico).
- **Fase 5 (aspetto e suoni):** la spada è uno zweihänder Neon (la scelta dell'utente); icona definitiva (cella 34, lo
  spadone in diagonale); la carta dice «SPADONE: TAGLIA E PARA» (stretta «SPADONE, PARATA»); cartellino del colpo
  («FENDENTE 9»), angoli della guardia attorno al mirino, scintille e lampo delle parate, catena del rampino; suoni suoi
  e una musica sua nel laboratorio. Le regole non cambiano.
- Icona (cella 34) e suono (`card_first_person_fencer`) **provvisori**: quelli definitivi sono della Fase 5, nello stile Neon.

## 2026-10-29 — First Person Brawler: critico senza mira, guantoni 3D

Commit **«Prima persona, Fase 2: critico senza mira e guantoni 3D»** sul ramo
`piano-prima-persona` ([piano](piano-prima-persona.md), Fase 2, dopo la prova).

- **Prima:** il critico voleva il pugno chiesto dal segno **e** il mirino sopra il segno (testa o corpo compresi).
- **Ora:** basta il pugno chiesto dal segno che prende quel nemico, dovunque. Il segno sta sul petto, dalla parte del suo
  pugno, solo come aiuto.
- **Aspetto:** i guantoni rossi di carta ai lati diventano guantoni in guardia al centro in basso: un modello 3D disegnato
  come pixel art di cartoncino (tinte piene, inchiostro, bordo di carta e spessore). Prima neri e oro; poi (Fase 3, scelta
  dell'utente) **Neon**: carbonio viola scuro, fasce e tubi magenta, bordo di luce ciano.
- **Icona e ispettore** (Fase 3): icona del guantone ridipinta Neon; nell'ispettore «SX JAB / DX CROSS / SHIFT GANCI» al
  posto di «NIENTE CARTE: SOLO I PUGNI»; riquadro dei secondi magenta.
- **Suono** (Fase 3): `card_first_person_brawler` non ha più la campanella (ora suona alla discesa nella vista): solo i
  guantoni battuti con un crepitio Neon.
- Danni, tempi, rarità, energia e durata non cambiano.

## 2026-10-28 — Carta nuova: First Person Brawler (solo laboratorio)

Commit **«Prima persona, Fase 2, passo 5: First Person Brawler nel laboratorio»** sul ramo `piano-prima-persona`
([piano](piano-prima-persona.md), Fase 2).

| Carta | Nel codice | Rarità | Energia | Effetto | Peso nelle offerte | Dove sta |
|---|---|---|---:|---|---:|---|
| First Person Brawler | `First_Person_Brawler` | rara | 3 | su di te, 0 s di finestra: la vista in prima persona con i pugni per 20 s del mondo (+2 a potenziamento, fino a 30 a +5): movimento libero a 5 caselle al secondo, salto, scatto con il doppio tocco, jab 3, cross 4, ganci 6, segni critici (triplo; il gancio critico stordisce 1 s) | 60 (ma `Lab_Only`: mai offerta) | solo nell'arena «Prima persona» del laboratorio, nel suo mazzo |

- È la seconda arma della vista di First Person Shooter (`First_Person_Weapon.Fists`, l'arma nei `charges` del suo
  effetto `.First_Person`); niente carte mentre dura, non si gioca in groppa al Dinosauro.
- Icona e sigla (`FPB`) **provvisorie**: un guantone rosso disegnato da codice nella cella 33 dell'atlante
  (`tools/art/build_card_icons.py`), e un suono provvisorio suo (`card_first_person_brawler`: i guantoni battuti e la
  campanella del ring); quelli definitivi sono della Fase 3, in stile cibernetico.

## 2026-10-25 — Revisione delle carte

Commit **«Carte: ritirate otto carte, cinque diventano potenziamenti»** sul ramo `revisione-carte` (partito da
`piano-griglia`).

### Come si toglie una carta, e come si rimette

- **Ritirata** vuol dire: nella sua definizione in [card.odin](../src/game/card.odin) c'è `traits = {.Retired}`. Il codice
  della carta resta tutto (regole, disegno, suoni, test), ma niente la dà: né il mazzo iniziale, né le ricompense, né i
  negozi, né le officine, né gli archivi dei biomi, né il ring. L'archivio dell'hub non la conta e non la mostra.
  Per **rimetterla** basta togliere quella riga (e, se si vuole, rimetterla dove stava: mazzo iniziale, ring, archivi;
  sotto è scritto dove stava ciascuna).
- **Diventata potenziamento** vuol dire: la carta base ha `evolves_to = .<carta>, evolve_level = CARD_EVOLVE_LEVEL`
  (`CARD_EVOLVE_LEVEL = 2`, in card.odin), e la carta che ne nasce ha `evolution_only = true` e `reward_weight = 0`. Al
  **secondo potenziamento** la carta base diventa l'altra, che riparte dal suo livello 0 e si potenzia per conto suo.
  Per **rimettere** la carta da sola: togliere le due righe dalla carta base, togliere `evolution_only = true` e ridarle il
  `reward_weight` scritto sotto.
- Le carte ritirate o diventate potenziamento **restano nei salvataggi**: se un mazzo di una spedizione in corso ne ha una,
  la si gioca fino alla fine di quella spedizione. Nelle scoperte della campagna restano segnate, solo nascoste.

### Carte ritirate (8)

| Carta | Nel codice | Rarità | Energia | Effetto (com'era) | Peso nelle offerte | Prima comparsa | Dove stava |
|---|---|---|---:|---|---:|---|---|
| Thorn Coat | `Thorn_Coat` | non comune | 25 | su di te: 2 spine per 3 s; abilita la deviazione (contro gli arcieri) | 85 | 15/07, `37487b6` | mazzo iniziale |
| Afterimage | `Afterimage` | non comune | 25 | su di te: schiva senza recupero; 1 scudo se ti muovi, per 4 s | 85 | 15/07, `37487b6` | mazzo iniziale |
| Counter Rune | `Counter_Rune` | rara | 25 | su di te: contrattacco 3; 2 cariche, retain | 65 | 15/07, `37487b6` | — |
| Battle Focus | `Battle_Focus` | rara | 15 | su di te: pesca 2; esplora, vista per 3 s fino a 9 celle; exhaust/ethereal | 65 | 16/07, `bc29683` | run tattica (`--run`), al posto di Toxic Wave |
| Spark Forge | `Spark_Forge` | non comune | 15 | su di te: crea 2 Spark temporanee a energia 0 | 75 | 16/07, `bc29683` | — |
| Spark | `Spark` | comune (temporanea) | 10 | raggio 1-2: 2 danni | 0 (temporanea) | 16/07, `bc29683` | nasceva solo da Spark Forge e Volatile Study |
| Volatile Study | `Volatile_Study` | rara | 20 | su di te: crea 1 Spark, pesca 2; exhaust | 60 | 17/07, `c3ec4b8` | — |
| Titan Grip | `Titan_Grip` | rara | 45 | raggio 1: 3 danni, lancia di 2; interrompe e stordisce 1 s | 65 | 09/10, `8f2b6ae` | premio del primo ring vinto; archivio del bioma Segreto |

### Carte diventate potenziamenti (5)

Ognuna si ottiene ora solo potenziando due volte la carta base; da sola non è più offerta, venduta né scoperta.

| Carta base | Diventa (al 2° potenziamento) | Rarità | Energia | Effetto della carta che ne nasce | Peso che aveva | Prima comparsa | Dove stava |
|---|---|---|---:|---|---:|---|---|
| Guard | **Purifying Guard** (`Purifying_Guard`) | non comune | 25 | su di te: 3 scudo per 2 s; rimuove il veleno | 80 | 17/07, `c3ec4b8` | archivio della Neve |
| Strike | **Cross Slash** (`Cross_Slash`) | non comune | 25 | raggio 1-3: 3 danni a croce; solo celle visibili | 90 | 15/07, `37487b6` | — |
| Arc Bolt | **Chain Lightning** (`Chain_Lightning`) | rara | 40 | raggio 1-4: 3 danni a nemico; salta fino a 3 visibili | 65 | 08/09, `5d7e91d` | archivio dello Spazio |
| Fate Strike | **Prismatic Barrage** (`Prismatic_Barrage`) | non comune | 50 | raggio 1-3: 3d4, ogni 4+ fa 3 danni; con 1-3, 1 scudo per dado | 75 | 08/09, `5d7e91d` | archivi dell'Egitto e dello Spazio |
| Venom Needle | **Twin Venom** (`Twin_Venom`) | non comune | 30 | raggio 1-3: max(2d4) + 1 danni; con una coppia, 2 veleno | 75 | 08/09, `5d7e91d` | — |

Fate Strike, che sale di dado a ogni potenziamento, ora arriva al d6 (livello 1) e al secondo potenziamento diventa
Prismatic Barrage, che riparte dal d4 e sale fino al d20 come prima.

### Cambiamenti che ne seguono

- **Mazzo iniziale** ([deck.odin](../src/game/deck.odin)): da 10 a **8 carte**. Thorn Coat e Afterimage sono uscite senza
  sostituti: Strike, Arc Bolt, Piercing Ray, Shove, Firebomb, Guard, Toxic Wave, Dash.
- **Run tattica** `--run` ([tactical_setup.odin](../src/run/tactical_setup.odin)): Toxic Wave non è più sostituita da Battle
  Focus; restano gli altri cambi (Fate Strike al posto di Arc Bolt, Heavy Blow al posto di Piercing Ray) e le cinque
  carte aggiunte: 13 carte invece di 15.
- **Ring** ([m8_ring.odin](../src/game/m8_ring.odin)): il primo ring vinto dà **Grappling Hook** invece di Titan Grip (la
  presa del ring passa all'uncino: rara, raggio 2-4, 1 danno e trascina il nemico accanto). Come prima Titan Grip, nelle
  run tattiche Grappling Hook non è offerto prima del primo ring vinto; nelle spedizioni non cambia nulla. Storm Crown resta
  al terzo ring.
- **Archivi dei biomi** (scoperte, [expedition_scene.odin](../src/run/expedition_scene.odin)): Neve, Purifying Guard →
  Sundering Blow; Egitto, Prismatic Barrage → Feretro; Spazio, Prismatic Barrage e Chain Lightning → Tesla Coil e Storm
  Crown; Segreto, Titan Grip → Grappling Hook.
- **Collezione**: una nuova funzione, `game.card_in_collection`, dice quali carte si scoprono, entrano nel pool di una
  spedizione e si contano nell'archivio e nell'hub («N / M carte scoperte»): non quelle del laboratorio, non le ritirate,
  non quelle che nascono da un potenziamento, non le temporanee.
- **Interfaccia**: nel pannello PERSONAGGIO una carta che cambia dice «Potenziamento X / 2: diventa <carta>»; nei negozi e
  nei riposi della run tattica l'anteprima del potenziamento che la cambia è «-> <carta>».
- **Restano com'erano**: i tasti di prova `C`/`V` con `--debug-abilities` (sono abilità di prova, non carte); le arene di
  prova `--spell-lab`, `--dice-lab` e gli smoke tattici, che usano alcune di queste carte per provarne le regole.

### Verifica

1651 test, con e senza assert (`scripts/check.ps1`). Due test nuovi
([card_evolution_test.odin](../src/game/card_evolution_test.odin)): le cinque carte cambiano al secondo potenziamento e poi
si potenziano per conto loro; le ritirate restano valide nel codice ma nessuna offerta, mazzo iniziale o collezione le
contiene. Gli altri test che contavano su queste carte sono stati aggiornati (mazzo di 8 carte, premio del ring, pool
delle offerte contato invece che scritto a mano, Fate Strike che cambia).
