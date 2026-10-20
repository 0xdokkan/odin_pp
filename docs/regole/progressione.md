[← Odin PP](../../README.md)

## Nemici e combattimento tattico

Sorgenti: [enemy_intent.odin](../../src/game/enemy_intent.odin),
[enemy_tactical_ai.odin](../../src/game/enemy_tactical_ai.odin),
[custodian.odin](../../src/game/custodian.odin) e [miniboss.odin](../../src/game/miniboss.odin).

### Intenti committed

Ogni nemico conserva un piano con origine, percorso, destinazione, celle
minacciate e danno, più il proprio countdown. Protect conserva anche ID e
cella dell'alleato. Il piano impegna celle precise: non segue automaticamente
il player quando questo si sposta. Gli ID ordinano le prenotazioni; l'IA evita
ostacoli e pericoli e non usa RNG per scegliere un percorso.

Quando il countdown scade, il mondo risolve l'intento annunciato. Un'origine
spostata, una destinazione occupata o una LoS interrotta possono farlo fallire.
Morti e rimozioni non invalidano l'iterazione. Loot e Defeat cancellano i piani.

### Archetipi

Cadenze, mira, fendenti, recuperi e protezioni sono descritti una sola volta
nella sezione [M7](combattimento.md#modalità-tattica-m7). Chaser, Archer, Brute, Bomber,
Custodian e Demolitionist usano lo stesso planner del gioco corrente;
non è mantenuto un secondo comportamento classico.

### Incontri, Furnace e boss

| Composizione | Coppia garantita |
|---|---|
| Powder Keg / Polveriera | Bomber + Chaser; due barili nei Combat |
| Escort / Scorta | Custodian + Archer vicini, con collegamento libero |
| Assault / Assalto | Brute + Chaser |
| Demolitionist | Demolitore + Bomber, nei nodi Boss |

Il budget può aggiungere altri nemici. I Combat di profondità 0–1 sono
Polveriera; i successivi Combat e gli Elite scelgono fra le prime tre ricette
in modo deterministico.

Furnace evidenzia una fila o colonna, fino a 16 celle, e infligge tre danni
base a player, nemici e oggetti. Il primo scatto segue due beat del mondo;
poi ci sono due secondi di pausa e due di preavviso, per una cadenza di quattro.
Si risolve dopo gli esplosivi e prima dei nemici, può accendere barili e non
crea Fire persistente. La corsia resta fissa. Profondità 0–1 e Boss sono Calm;
a fine Combat Furnace si spegne.

| Fase del Demolitore | Ciclo |
|---|---|
| Demolition | bomba → recupero 1 → carica da 4 danni, range 2–4 → recupero 2 |
| Overdrive, HP ≤ 15 | due lanci → carica da 6 danni, range 2–6 → recupero 2 |

La transizione avviene alla prossima pianificazione: non cambia un attacco
annunciato e conserva il recupero guadagnato. Senza linea per caricare, il boss
prova al massimo due avvicinamenti o attese, poi recupera e riparte dai lanci.
Il Bombarolo di supporto agisce anche durante le pause del boss.

La presentazione distingue `WAIT`, `MOVE`, `ATK N`, `CHG N`, `BOMB 2`,
`SHIELD 2` e `RECOVER N`, senza prendere decisioni. I limiti per intento sono
otto celle di percorso e sedici minacciate; la BFS non pianifica ancora code
su più pulse e gli altri nemici non sono copertura per l'Archer.

## Rotta e generazione delle stanze

Sorgenti: [run.odin](../../src/game/run.odin),
[run_validation.odin](../../src/game/run_validation.odin),
[room_generation.odin](../../src/game/room_generation.odin),
[encounter_director.odin](../../src/game/encounter_director.odin),
[room_generation_objects.odin](../../src/game/room_generation_objects.odin) e
[level.odin](../../src/level/level.odin).

### Rotta e seed

La rotta è un DAG a livelli: un Combat iniziale, un Boss finale, due o tre nodi
per livello intermedio con esattamente uno speciale e almeno uno con stanza.
Gli archi portano solo al livello successivo, senza duplicati, con massimo tre
uscite; ogni nodo è raggiungibile dall'inizio e conduce al boss.
Il ciclo speciale è Shop → Rest → Event → Treasure, con offset dal seed.
`validate_run_map` ricontrolla distribuzione, collegamenti e room seed.

`room_seed` deriva da seed run, ID, profondità, tipo del nodo e salt dedicato,
senza consumare RNG della rotta, deck o reward. Layout ed encounter hanno
stream separati; famiglia, ricetta e modificatore hanno salt distinti.
La casualità grafica non deve cambiare alcuno di questi risultati.

`last_room_family` esclude la famiglia dell'ultima stanza **installata**,
anche passando da nodi speciali. Si aggiorna solo al commit e si azzera al
restart; un ingresso fallito non consuma storico. Lo stesso nodo raggiunto da
una famiglia precedente diversa può quindi cambiare geometria. Il determinismo
vale per la versione corrente: un futuro save basato sul seed richiede versione
del generatore e golden vector per le migrazioni.

### Layout e placement

| Famiglia | Geometria |
|---|---|
| Pillars | quattro isole iniziali; nelle arene grandi gruppi di pilastri e corsie alternate |
| Ring | blocco centrale iniziale; poi cortile anulare con quattro varchi e coperture esterne |
| Twin Courts | due cortili iniziali; poi tre–cinque cortili collegati da più passaggi |
| Asymmetric / Broken Cover | parete a L iniziale; poi coperture a L separate e percorsi trasversali |

Il profilo delle prime due profondità usa Combat **17×11**, Elite **19×12**
e Boss **21×13**. Le profondità successive usano la progressione qui sotto.
Prima si costruisce la forma, poi
spawn e uscita con clearance e distanza minima. Le famiglie tattiche richiedono
almeno 13x9. `Scattered` resta il default generico e la sentinella dello
storico iniziale; la demo non vi ripiega quando una famiglia fallisce.
I tentativi sono limitati e restituiscono errori espliciti.

La BFS valida un solo spawn e un'uscita, bordo, clearance, spazio disponibile
e connessione di tutte le celle aperte. `min_spawn_exit_distance` usa distanza
Manhattan; il report conserva anche la lunghezza del percorso minimo BFS.
Soltanto dopo questa verifica `game` spende il budget degli incontri:
Chaser costa 1, Archer/Bomber/Custodian 2, Brute 3, Demolitionist 6.
Il boss compare esattamente una volta e non entra nel campionamento comune.

La coppia della ricetta è adiacente o allineata a distanza due con collegamento
libero. Il placement cerca coperture con più approcci per Archer, corsie di
almeno tre celle per Brute e Demolitore, spazio per Bomber e prossimità per
Chaser. Gli oggetti successivi conservano quelle opportunità e la LoS della
Scorta. Ostacoli che disconnettono il layout vengono rifiutati; un budget non
collocabile fa fallire il blueprint, senza ridurre di nascosto la difficoltà.

Il perimetro e i due accessi dei cortili sono riservati rispetto a ostacoli e
oggetti; nemici e trappole possono usarli. Nei profili introduttivi, Combat contiene tre oggetti, quattro
in Polveriera; Elite e Boss sei. Nelle arene progressive aumentano con il tier. Si aggiungono barili, Ice Block e Fire usando
candidati già mescolati, senza consumare altro RNG o spostare gli spawn scelti.
La connettività considera anche Fire come cella da evitare, garantendo un
percorso iniziale senza danno da fuoco.

Ogni barile deve avere almeno due celle opposte libere: una per raggiungerlo,
una per la spinta. Il controllo finale include tutti i contenuti.
Furnace esclude spawn, uscita e solidi fissi; ogni cella segnata deve avere
un'uscita dalla corsia entro due passi, evitando oggetti e fuoco. Gli attori
sono esclusi da questo controllo statico. Se non esiste una corsia valida,
il modificatore resta Calm. Le condizioni durante il fight possono cambiare.

`Room_Blueprint` possiede layout e spawn fino al trasferimento; la validazione
ricalcola famiglia, composizione, budget, statistiche e modificatore prima
dell'installazione transazionale. Gli ID vengono assegnati dalla Room.
I test includono 1536 layout delle famiglie e 4096 combinazioni di seed,
profilo e famiglia precedente; i fallimenti devono riportare seed e nodo
riproducibili.

Per i livelli ASCII: spazio = Void, `.` = pavimento, `#` = muro, `+` = porta,
`@` = spawn, `>` = uscita.

### Progressione delle arene tattiche

Sorgenti: [arena_progression.odin](../../src/game/arena_progression.odin),
[complex_room.odin](../../src/level/complex_room.odin) e
[tactical_framing.odin](../../src/render/tactical_framing.odin).

| Livello della rotta (depth) | Combat | Nemici Combat | Elite | Nemici Elite | Boss | Nemici Boss |
|---|---|---:|---|---:|---|---:|
| 1–2 (0–1) | 17×11 | 4 | 19×12 | budget precedente | 21×13 | budget precedente |
| 3–4 (2–3) | 25×17 | 8 | 27×18 | 10 | 29×19 | 12 |
| 5–6 (4–5) | 33×23 | 12 | 35×24 | 14 | 37×25 | 16 |
| 7+ (6+) | 41×29 | 16 | 43×30 | 18 | 45×31 | 22 |

La run attuale ha sette livelli: il boss finale occupa 1.395 celle totali,
circa 7,5 volte l'impronta delle 187 celle della prima stanza (muri compresi).
Dimensioni e quantità smettono di crescere dopo il quarto tier; il limite
strutturale resta 32 nemici. Il conteggio è esatto, non soltanto un tetto.
Dal tier 1 sono garantiti Chaser, Archer, Bomber e Custodian; dal tier 2 anche
Brute. Il Demolitionist resta unico e riservato al boss. Dopo la coppia della
ricetta, i nemici vengono disposti a squadre di tre nei diversi settori.

Le arene grandi proteggono un perimetro largo due celle, un incrocio centrale
largo tre e gli approcci ai cancelli contro ostacoli/oggetti solidi. Le famiglie
hanno percorsi alternativi; la verifica finale conserva accesso sicuro all'uscita
anche dopo il placement. Trappole/ostacoli/oggetti dei Combat passano a
4/8/6, 6/12/8 e 8/16/10; Elite aggiunge 1/2/2, Boss 2/4/4.

La ricerca della coppia iniziale controlla gli otto vicini ammissibili tramite
indice anziché confrontare tutte le coppie, preservando i pareggi precedenti.
Il percorso tattico pesato usa Dijkstra con heap indicizzato e ordine costo/cella:
O(celle log celle), anziché O(celle²). Fuoco, trappole, bombe, destinazioni
alternative degli arcieri e scelte deterministiche conservano la stessa semantica;
un test confronta tutte le distanze con il vecchio solver sulle quattro fasce.

I test nuovi coprono 864 layout complessi senza strozzature di una sola cella,
216 blueprint con conteggi/ruoli/distribuzione e 18 fingerprint compatibili.
Il maggior numero di nemici e drop richiede comunque playtest di difficoltà ed
economia su run complete: questa taratura è una prima versione giocabile.

## Ricompense, economia e nodi speciali

Sorgenti: [reward.odin](../../src/game/reward.odin), [economy.odin](../../src/game/economy.odin),
[shop.odin](../../src/game/shop.odin), [special_node.odin](../../src/game/special_node.odin).

### Reward e modifiche permanenti

`finish_room` chiude il deck runtime, completa il nodo e incrementa
`cleared_count`. Una stanza con uscite apre Reward; il boss porta direttamente
a Victory. Reward conserva tre `Card_Id` distinti, non istanze: gli ID si
consumano soltanto quando una scelta valida aggiunge la carta.

Le offerte combinano `reward_weight` della definizione e peso della rarità
Common/Uncommon/Rare per tipo di nodo e profondità, limitata a 12.
Il sampling è pesato senza rimpiazzo, in ordine stabile di catalogo.
Reward e Shop preparano offerta e avanzamento RNG su copie, confermandoli solo
dopo la validazione; gli stream sono separati dal deck e fra loro.
Le carte `temporary_only` sono escluse. Una run ha al massimo una
[Canna da Pesca](meccaniche.md#canna-da-pesca): finché il mazzo ne ha una,
`card_offer_exclusions` la toglie da ogni offerta (reward, Shop, Armory e le
carte pescate).

`choose_card_reward` modifica una copia del deck, valida la run risultante,
azzera l'offerta e passa a Choose_Path. Skip fa lo stesso senza creare carte.
Deck pieno lascia la reward aperta con Skip disponibile; indice errato, ID
esauriti e tentativi ripetuti non consumano risorse. Durante Reward non si
può scegliere un nodo della mappa.

Upgrade e rimozione richiedono deck inattivo e **ID della specifica istanza**.
Upgrade conserva identità, ordine, RNG e prossimo ID; remove compatta owned
senza riciclare ID e conserva almeno cinque carte. Il livello massimo è dieci,
cinque per le carte con dadi (dal D4 al D20), per il Lazzo, il Pinball, First
Person Shooter e la Canna da Pesca (il suo d4 non cambia mai); deck, Shop e Rest
rispondono `Maximum_Upgrade` oltre quel limite. La preview di una carta con dadi
mostra soltanto il dado, per esempio `d4 -> d6`. `card_can_upgrade` richiede un
beneficio effettivo: Battle Focus, Calculated Risk, Spark Forge e Dash non sono
migliorabili. Shop e Rest condividono la query e la preview prima/dopo,
restituendo `Upgrade_Unavailable` senza costi.

### Shop

Il vendor è un vero nodo della rotta: tre carte, un upgrade e una rimozione.
Ogni offerta può essere venduta una volta e ogni servizio usato una volta.
Acquisti e servizi lavorano su copie staged; solo il successo modifica deck,
oro e flag. Non consumano RNG. Deck pieno impedisce l'acquisto ma non i servizi
o l'uscita.

Con `d = min(depth, 12)` e rarità Common = 0, Uncommon = 1, Rare = 2:

| Acquisto | Prezzo, divisione intera |
|---|---|
| carta | `shop_base_price + d / 3` |
| upgrade | `2 + rarity + 2 * upgrade_level + d / 4` |
| rimozione | `4 + d / 4` |

I calcoli usano intermedi `i64` e validano il risultato `i32`. Oro insufficiente,
slot venduto, deck pieno/minimo, carta invalida o livello massimo lasciano tutto
invariato. `leave_shop` completa il nodo una sola volta e apre Choose_Path.
Finché resta il nodo corrente, `open_shop` lo riapre senza reroll; entrare nel
nodo successivo azzera il payload.

### Rest, Event e Treasure

Un nodo speciale non crea una Room vuota: `Run_State` possiede un payload
costruito e validato prima di cambiare nodo, fase, RNG o flag entered.
Si può entrare solo in un'uscita disponibile non già visitata.

| Nodo / evento | Scelte |
|---|---|
| Rest | recupera 30% della vita massima, minimo 1; oppure upgrade gratuito di un'istanza; oppure Leave |
| Blood Offering | paga 20% della vita massima per `8 + 2*d` oro; oppure rifiuta |
| Healing Spring | cura fino al 25% della vita massima; oppure ottieni `4 + d` oro |
| Forgotten Armory | aggiungi la carta offerta; oppure ottieni `5 + d` oro |
| Treasure | Claim assegna `7 + 2*d` oro e nella demo offre anche una reliquia; oppure Leave |

Event e carta dell'Armory derivano dal seed del nodo, indipendentemente da
pescate e rendering; l'Armory lascia fuori soltanto una Canna da Pesca che il
mazzo ha già quando si entra nel nodo (ricontrollando l'offerta dopo la scelta
non conta quella appena presa). Blood Offering richiede vita strettamente maggiore del
costo. Le cure non superano max_health; Recover a vita piena è valido con
beneficio zero. Overflow dell'oro, deck pieno, ID esauriti e upgrade invalido
non risolvono il nodo e non alterano lo stato.

Una scelta o Leave rende il payload `resolved` e mostra l'esito. Solo dopo
`continue_special_node` completa il nodo, incrementa `cleared_count`, azzera
il payload e apre Choose_Path, dopo l'eventuale scelta reliquia. Scelte e
Continue sono one-shot. Solo il payload pertinente alla fase può essere attivo;
nessuno di questi nodi avanza pulse o status. Hover, pagina e selezione
appartengono alla presentazione, non allo stato della run.

## Reliquie

Sorgenti: [relic.odin](../../src/game/relic.odin),
[relic_effects.odin](../../src/game/relic_effects.odin) e
[run_relic_reward.odin](../../src/game/run_relic_reward.odin).

Le reliquie durano per l'intera run e si azzerano al restart. La demo offre una
scelta iniziale, una dopo gli Elite prima delle carte e una dopo Claim al
Treasure. Le offerte dipendono da seed, nodo e inventario, senza duplicati o
reliquie già possedute. Se ne restano meno di tre, l'offerta si riduce;
con tutte e sei non compare. Scegliere o saltare è necessario per proseguire.

| Reliquia | Effetto | Sinergia |
| --- | --- | --- |
| Iron Knuckle | Il primo spostamento forzato riuscito di un nemico o oggetto in ogni impulso dà 1 Shield per 2 impulsi | Shove, Grappling Hook e barili |
| Ash Bookmark | Il primo Exhaust di ogni combattimento pesca una carta aggiuntiva | Battle Focus, Volatile Study, Ethereal |
| Swift Soles | La prima carta che sposta effettivamente il giocatore in ogni combattimento recupera 1 energia | Dash e riposizionamento |
| Venom Vial | La prima applicazione riuscita di Veleno a un nemico in ogni combattimento ha uno stack in più | Venom Needle e Caustic Bloom |
| Guard Sigil | All'ingresso in combattimento dà 2 Shield per 3 impulsi | Avvicinamento e prime decisioni |
| Mending Thread | Alla fine di un combattimento vinto cura 2 HP | Recupero fra gli scontri |

Una spinta bloccata non attiva Iron Knuckle; camminare non attiva Swift Soles.
Venom Vial modifica soltanto il primo bersaglio valido. Ash Bookmark funziona
anche con l'Ethereal exhaustata da Refocus: la pesca bonus segue pulse e refill,
se Combat continua. Mending Thread cura una volta alla vittoria, mai alla
sconfitta o durante il giro Loot. Salute ed energia rispettano i massimi.

L'inventario vive nel Player; i limiti per fight si reimpostano all'installazione.
I bonus usano azioni ed eventi ordinari senza consumare RNG di combattimento;
Swift Soles produce `Energy_Gained` prima del prossimo Pulse_Advanced.
`create_run(..., with_relic_rewards = true)` abilita le offerte nella demo;
il default API resta false per gli scenari headless preesistenti. Offerte
obsolete, indici invalidi e tentativi ripetuti non modificano inventario,
deck o RNG.
