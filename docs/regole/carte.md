[← Odin PP](../../README.md)

## Carte e ciclo del mazzo

Sorgenti: [card.odin](../../src/game/card.odin), [card_play.odin](../../src/game/card_play.odin),
[deck.odin](../../src/game/deck.odin) e [refocus.odin](../../src/game/refocus.odin).

### Definizioni, istanze e compilazione

Una `Card_Definition` contiene nome, rarità, peso, prezzo, costo, policy,
targeting e fino a quattro effect template. Una `Card_Instance` contiene ID
non nullo, definizione, upgrade e lifetime. La Action compilata è temporanea:
non resta nel mazzo. La compilazione valida fase, istanza e definizione,
riesegue targeting e movimento, espande i destinatari per ID e controlla la
capacità prima di produrre effetti. Non paga energia e non modifica RNG.

Preview e compilazione condividono `build_card_target_plan`: la preview conta
i destinatari, il compilatore conserva e consuma il piano locale della stessa
espansione. L'ordine resta template, oggetti colpiti, nemici per ID. Il conteggio
prosegue anche oltre la capacità per restituire l'errore completo; nessun piano
viene conservato fra comandi o passato dalla HUD alla simulazione.

I selettori sono `Chosen_Entity`, `Player`, `Each_Enemy` ed
`Each_Affected_Enemy`. Un template Move deriva la destinazione come
`Player_To_Anchor`, `Away_From_Player` o `Adjacent_To_Player`. Create_Card
richiede una definizione esplicita con `has_card_definition = true`.
Lo scaling ordinario è `base_amount + amount_per_upgrade * upgrade_level`,
con livello 0–10 e controllo overflow in `i64`. Le carte con dadi non scalano
importi: il livello 0–5 sceglie il dado (`DICE_LADDER`). Durata, cariche e costo non
scalano automaticamente.

### Ownership, zone e risorse

| Dato | Regola |
|---|---|
| `owned` | massimo 32 permanenti; rimozione consentita fino al minimo di 5 |
| carte temporanee | massimo 16 presenti nel runtime, mai in owned |
| draw / discard / exhaust | ciascuno può contenere tutte le 48 carte runtime |
| mano | massimo 8 (`MAX_HAND_CARDS`); regole che ne danno di più tutte insieme, come la Prova meccaniche, tengono la loro `hand_size`, fino a 10 (`MAX_HAND_CAPACITY`, `deck_hand_limit`); `hand_size = 5` è il target iniziale e di refill |
| resolving | uno slot interno, durante la giocata |
| energia | massimo 3, recupero 1 ogni tre beat del mondo |
| ID | unico `next_card_id` monotono, senza riciclo |

Lo starter deck ha dieci carte: Strike, Arc Bolt, Piercing Ray, Shove,
Firebomb, Guard, Toxic Wave, Thorn Coat, Afterimage e Dash.
La run tattica ([tactical_setup.odin](../../src/run/tactical_setup.odin)) sostituisce Arc
Bolt con **Fate Strike**, Piercing Ray con **Heavy Blow** e Toxic Wave con
**Battle Focus**, per provare subito dadi, interruzione e ricognizione, e
aggiunge una Shock Floor, una Tesla Coil, il 6 e il 7 di denari e un
**Movimento Ombra**: quindici carte. La mano è mescolata, senza pesca garantita.
`begin_deck_combat` copia owned nel draw, imposta `combat_card_id_floor`,
mescola e pesca cinque carte. Un attrezzo da fine stanza, la
[Canna da Pesca](meccaniche.md#canna-da-pesca), va invece subito fra le esaurite, da cui
nessuna pesca e nessun rimescolamento la riprendono. Fisher–Yates usa uno xorshift64* locale separato
dagli RNG della run. Si pesca dalla fine del draw in fondo alla mano; quando
serve, il discard diventa draw e viene rimescolato.

Una permanente compare esattamente in una zona durante Combat (la Canna da
Pesca nell'Exhaust, per tutto il combattimento). Una carta con
lifetime `Combat` usa un ID almeno pari al floor del fight, non entra in owned
e scompare a fine stanza; gli ID consumati restano consumati. Una definizione
`temporary_only`, come Spark, non è collezionabile e ha peso/prezzo zero.
Lifetime ed Exhaust sono distinti: una permanente exhaustata torna nel prossimo
fight; una temporanea può essere scartata e rimescolata, ma viene sempre
exhaustata quando giocata. `finish_deck_combat` svuota tutte le zone, energia e
floor, conservando owned, upgrade, RNG e prossimo ID.

`validate_deck_state` verifica identità, lifetime, capacità e ownership.
`-define:DECK_DEEP_VALIDATION=false` alleggerisce solo le primitive interne:
i confini di transazione mantengono la validazione completa.

### Giocata ed effetti sul deck

La giocata usa il catalogo unico e non esegue una risposta nemica immediata.
La pesca di rimpiazzo avviene al termine del cast.

```text
validazione e compilazione -> snapshot del deck -> pagamento
-> Hand → Resolving -> effetti e reazioni -> Discard oppure Exhaust
-> cast -> pesca di rimpiazzo se Combat continua
```

Resolving impedisce alla carta di rimescolarsi e pescare se stessa durante i
propri effetti Draw. Una giocata rifiutata ripristina deck, energia, zone e RNG.
`Played`, `Combat_Ended` e `Player_Defeated` indicano tutti un commit avvenuto;
`card_play_was_committed` centralizza il controllo. Una giocata terminale non
produce pulse o rimpiazzo aggiuntivi.

Draw, Discard e Create sono normali effetti sequenziali **fino a N**:
Draw si ferma a mano piena o fonti vuote; Discard usa la carta più a sinistra;
Create inserisce temporanee in mano fino al limite di mano, budget o ID.
Create non usa RNG. Calculated Risk pesca prima di scartare; Volatile Study
crea prima la Spark e poi pesca. Un effetto successivo invalido non annulla
quelli precedenti. Purifying Guard concede Shield anche senza Poison da rimuovere.

Gli eventi `Card_Played`, `Card_Drawn`, `Card_Moved` e `Card_Created`
conservano identità completa, upgrade, lifetime e zone. Per Create, la zona
sorgente `.Count` significa assenza di origine. Il replay usa le stesse
primitive su una copia del deck e controlla anche gli ID e l'RNG del reshuffle.

### Refocus, Retain ed Ethereal

Refocus è la frontiera manuale della mano, non la fine di ogni pulse.
Osserva la mano originale da sinistra a destra: Retain resta in mano,
Ethereal va in Exhaust, le altre carte in Discard. Le due policy sono
mutuamente esclusive; `exhaust_on_play` è una regola distinta.

Il cleanup viene validato e committato; Refocus consuma due secondi e richiede
un refill fino a cinque, contando le retained, al completamento del beat.
Non resetta l'energia: vale la rigenerazione normale. Anche una mano vuota è
valida. Se il combattimento finisce prima del refill, il cleanup resta committed.

`Hand_Refocused` precede un `Card_Refocused` per ogni carta originale,
compreso `Hand -> Hand` per Retain; seguono, sul clock del mondo, raccolta e refill.
Questi eventi non sono intercambiabili con Card_Moved senza normalizzare la
causa. Durante la timeline del player il pulsante è disabilitato e `F` premuto
si perde: non resta in coda.

### Catalogo delle carte

Esiste un solo catalogo di **46 carte**, in [card.odin](../../src/game/card.odin)
(`CARD_DEFINITIONS`): costo, targeting, effetti, rarità e metadati sono condivisi
da gameplay, preview, HUD e offerte. Non ci sono più sovrascritture per modalità.
Il bilanciamento delle carte originarie è descritto nella sezione
[M7](combattimento.md#modalità-tattica-m7); dispositivi, carte speciali e spell hanno le proprie
sezioni sopra e sotto. `card_can_upgrade` permette l'upgrade solo se offre un
beneficio effettivo; per i dadi il beneficio è il poliedro successivo, fino al D20.

## Spell e dadi

Sorgenti: [spell.odin](../../src/game/spell.odin), [dice.odin](../../src/game/dice.odin),
[spell_renderer.odin](../../src/render/spell_renderer.odin),
[dice_physics.odin](../../src/render/dice_physics.odin) e
[dice_playback.odin](../../src/render/dice_playback.odin).

`U` è il livello dell'istanza e `D` il dado del suo livello: D4 al livello 0,
poi D6, D8, D10, D12 e D20 al quinto e ultimo upgrade (`DICE_LADDER` in
[dice.odin](../../src/game/dice.odin)). Un upgrade di una carta con dadi cambia solo
il dado; il numero di dadi resta quello della carta. La stessa scala vale per
Shock Floor. Sulle carte il dado si scrive con la d minuscola (`1d4`, `2d8`;
la preview di upgrade mostra `d4 -> d6`): nel font pixel la D maiuscola si
confonde con lo zero. Tutte queste carte costano due energia; valori prima di
difesa, Shield e reazioni:

| Carta | Rarità | Primo bersaglio con LoS | Effetto |
|---|---|---|---|
| Firebomb | Rare | cella calpestabile, Chebyshev 1–3 | `2 + U` danni ai nemici e oggetti validi nel 3x3 |
| Fate Strike | Uncommon | nemico, Manhattan 1–4 | `2 + 1D`; con la faccia più alta del dado, possibile rimbalzo da 3 |
| Chain Lightning | Rare | nemico, Manhattan 1–4 | `3 + U` a fino a tre nemici distinti |
| Sundering Blow | Uncommon | nemico allineato, Manhattan 1–2 | `2D`; somma dei dadi almeno 8: spinta di una cella |
| Prismatic Barrage | Uncommon | nemico, Manhattan 1–3 | `3D`: ogni 4+ vale 3 danni; ogni dado sotto il 4 dà 1 Shield per due pulse |
| Twin Venom | Uncommon | nemico, Manhattan 1–3 | `1 + max(2D)`; una coppia applica 2 Veleno al sopravvissuto |

Due carte della Fase 2 tirano un dado della stessa scala, in tattica:
`Dado del Destino` (energia 2) non tira niente quando la si gioca, ma ogni suo
urto caricato tira il dado al colpo (il cartellino del dado sul nemico, non il
tavolo dei dadi), e `Lama Velenosa` (energia 1) lo tira giocandola, con il lancio
a tutto schermo come le altre
([Deflect, Feretro, Dado del Destino e Lama Velenosa](meccaniche.md#deflect-feretro-dado-del-destino-e-lama-velenosa)).
Anche le frecce di Feretro scelgono il loro status con i dadi del player
(`Player.dice`, sotto).

Con un dado da N facce Fate rimbalza con probabilità `1/N`. Le soglie restano
numeri fissi, quindi un dado più grande le supera più spesso: Sundering spinge
con `1/16` (2D4), `15/36` (2D6), `43/64`, `79/100`, `123/144` e `379/400` (2D20);
ogni dado di Barrage è un successo con `(N-3)/N`, dal 25% del D4 all'85% del D20.
Barrage aggrega i danni dei successi in un colpo, preceduto dallo Shield: con
zero successi è comunque una giocata valida da tre Shield. La probabilità di
almeno un successo è `37/64` con 3D4 e `7/8` con 3D6. Twin Venom ha probabilità
`1/N` di coppia; l'upgrade non cambia gli stack del veleno.

### RNG e percorso committed

`Player.dice` contiene uno stream e un contatore dedicati, indipendenti da
mazzo, mappa, incontri, reward e rendering. Ogni dado usa rejection sampling per
non introdurre bias di modulo. `roll_card_dice` è l'unico tiro delle carte: il
numero di dadi viene da `card_dice_count`, il dado da `card_die_sides`, e
`roll_dice_pool` prepara su copia fino a tre facce dello stesso dado, il totale
e le facce del dado. Una nuova carta con dadi eredita così scala, limite di
upgrade, testi e presentazione. `Dice_Rolled` rappresenta l'intero lancio e
porta il dado: la presentazione rifiuta un dado diverso da quello del livello
registrato. Il commit avviene con l'effetto accettato; una giocata rifiutata
non consuma dadi. Hover, preview e compilazione non estraggono risultati.

`query_spell_path` sceglie tutti i destinatari prima della risoluzione. Ogni
salto parte dalla posizione precedente e cerca un nemico vivo non visitato,
entro tre passi Manhattan e con LoS. Vince il più vicino, poi l'ID minore.
Chain e Storm Crown conservano massimo tre bersagli, Fate due. La preview numera i salti;
il secondo di Fate è tratteggiato e marcato `SOLO N` (la faccia più alta del suo
dado), la spinta di Sundering `8+`. Le righe della preview riportano le
probabilità del dado del livello.

Ogni colpo conclude le proprie reazioni prima del successivo. Morte del player,
fine combattimento o scomparsa del prossimo bersaglio interrompono il resto:
nessuna sostituzione o ricerca successiva. La carta rimane Resolving per tutta
la sequenza, pagando e avanzando il combattimento una sola volta.

### Impatti e presentazione dei dadi

`Spell_Launched` e `Spell_Impact` precedono i danni; Dice_Rolled precede il
lancio quando richiesto. Firebomb registra il 3x3 filtrato in `area_mask` e
assegna un `visual_group` ai feedback diretti compatibili: si animano insieme,
ma le mutazioni dello snapshot restano ordinate. Reazioni e rimbalzi restano
separati. Il renderer non interroga la stanza futura per ricostruire l'area.

Il set 3D numerato comprende **D4, D6, D8, D10, D%, D12 e D20**: tetraedro,
cubo, ottaedro, trapezoedri pentagonali, dodecaedro e icosaedro. Le mesh sono
chiuse e smussate, con numeri fissi avorio, 6/9 sottolineati e resina blu scura
lucida. Il D4 ripete tre cifre per faccia: si legge il valore alla punta.
Nel set il D10 mostra 0–9 (0 vale 10), il percentuale 00–90; in gioco la
faccia del 10 porta 10, come la chiamano le carte (`10: RIMBALZO 3`,
`SOLO 10`). Il laboratorio si apre con `./run.sh --dice-set-lab`; basta
cliccare un dado per osservarlo da vicino.

In gioco ogni carta lancia il poliedro del proprio livello, fino a tre dadi
uguali, durante la stessa pausa completa, e i dadi si fermano sulle facce
registrate. Il pannello laterale separa le **facce estratte** dall'**effetto
applicato**, leggendo gli eventi risolti della stessa giocata: bonus critico,
danni e assorbimento dello scudo, cariche/status totali e cura effettiva.
Per esempio, Shock Floor con D4 = 3 sul colpo a tempo ottiene 4 scariche fino
a 4 nemici: il dado resta 3, il pannello dichiara il bonus incluso. Run, film
delle carte e laboratori usano lo stesso risultato; il renderer non esegue
un secondo tiro. Anche il D6 usa il set numerato. D10, D12 e
D20 sporgono dal cubo della simulazione: a riposo vengono separati sul piano
durante l'ultimo assestamento, senza toccare il volo.

Riferimenti fotografici dei modelli: [tavola locale dei dadi](../../references/dice/index.html),
[Chessex Translucent Blue/White](https://magicmerchant.it/catalogue/7-dice-chessex-translucent-blue-white-23076-dadi-832)
e [Lunar Veil di Misty Mountain Gaming](https://mistymountaingaming.com/products/lunar-veil-sharp-edged-resin-dice-set).
Le foto guidano proporzioni, facce e numerazione del set D4/D6/D8/D10/D%/D12/D20;
sono materiale di consultazione, separato dagli asset caricati dal gioco.
La fisica è cosmetica, precalcolata a passo fisso una volta per
lancio. Le facce vengono orientate prima del playback per mostrare il risultato
committed, senza cambiare numeri durante la caduta; nel D6 le facce opposte sommano sette.
Il percorso dei rimbalzi riusa la simulazione cubica esistente: ogni poliedro
corregge l'appoggio sul piano usando i propri vertici e conserva una rotazione
locale costante durante il lancio. Non è una simulazione di collisioni dedicata
a ogni solido. Modelli e lanci sono precalcolati, senza costruire mesh a ogni frame.
I primi due urti danno spinte verticali di 12 e 9 unità/s e impulsi angolari;
seguono attrito e assestamento, senza leggere RNG del gameplay.

Il cue dura nominalmente 2,1 secondi a 1x, indipendentemente dal numero di dadi.
I primi contatti sono a 0,648, 0,972 e 1,224 secondi. Il loop limita l'avanzamento
per frame a 1/18 del tiro e mostra i contatti prima di proseguire; in quel caso
scarta il tempo eccedente. I seek espliciti dei test restano immediati.
Successi, massimo e coppia sono letti dalle facce registrate; la somma resta
visibile. Una render texture trasparente riutilizzata viene composta in
coordinate finestra dopo il canvas, anche nel letterbox e senza deformazioni
in Stretch. Le risorse GPU si liberano prima della finestra.
