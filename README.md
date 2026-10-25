# Odin PP

Roguelike di esplorazione e deck building: dodici biomi aperti, combattimenti
continui a battito, uno zaino fisico da estrarre e una galassia di ricordi.
Il mondo è geometrico e al neon; carte e personaggi sono di cartoncino.
La campagna offre tre salvataggi, un deposito, dodici cabinati e quattro
giochi del casinò con i crediti raccolti nelle spedizioni.

La nuova campagna parte da **Gioca**. La modalità a stanze precedente
resta accessibile con `--run`; i suoi manuali storici restano consultabili.
La [checklist della direzione](docs/direzione-implementazione.md) descrive
le nuove regole, le verifiche e i limiti attuali.

## Avvio

Serve Odin con le librerie Raylib della distribuzione. La toolchain fissata
nella CI è `dev-2026-10:84bc3fc21`. Dalla radice del progetto:

```sh
./run.sh
./run.sh --seed=0xC0FFEE
./run.sh --expedition   # prova senza slot
./run.sh --run          # modalità precedente
./run.sh --release --expedition  # build ottimizzata per giocare
```

Su Windows usare `./run.ps1`. `ODIN` può indicare un compilatore alternativo.
Gli script ricompilano con `-o:none`, evitando l'attesa dell'ottimizzatore
prima dell'apertura della finestra. `--release`, come primo argomento,
usa `-o:speed`: la compilazione richiede più tempo, l'esecuzione è ottimizzata.
Per una build ottimizzata riutilizzabile:

```sh
mkdir -p build
odin build src -o:speed -out:build/odin_pp
./build/odin_pp
```

Il launcher raccoglie run, minigiochi, record e impostazioni. Gli avvii
`--minigame=fps` e `--minigame=ring` aprono direttamente le rispettive prove;
`--mechanics-lab` apre la pratica delle carte. Le altre opzioni e le regole
per i salvataggi sono nel [manuale di avvio](docs/avvio.md).

## Giocare

Esplora il bioma, trova equipaggiamento e carte, sconfiggi il boss e raggiungi
il portale. Il minigioco finale assegna un bonus: lo zaino viene estratto
anche se perdi il minigioco. La morte nella spedizione perde lo zaino e la
serie, ma conserva scoperte e sblocchi. I salvataggi sono automatici.

In combattimento il mondo avanza senza scadenza decisionale. Cast e dadi
fermano il mondo; l'energia si ricarica soltanto mentre il mondo avanza.

| Input | Azione principale |
|---|---|
| `WASD` | esplorazione libera (`W` verso l'alto dello schermo); in combattimento un passo per cella, attacco contro un nemico adiacente |
| rotella | seleziona la carta; durante il piazzamento la ruota |
| clic sinistro | piazza/conferma la carta; le carte semplici si giocano subito |
| clic destro | annulla il piazzamento |
| `M` | evoca o lascia la cavalcatura fuori dagli scontri |
| `E` | interagisce con POI, oggetti e portale |
| `Z` | zaino; il mondo continua durante gli scontri |
| `U` | personaggio, mazzo e potenziamenti; mette in pausa |
| `Tab` | miniatura 3D dell'intero bioma, legenda POI e posizione del robot |
| `I` / Mostra effetto | anteprima isolata della carta selezionata |
| `F` | Refocus |
| `P` / `Esc` | pausa o chiusura della schermata corrente |
| `F10` | salva e torna all'hub |
| `F11` | schermo intero |

Nel deposito prepari gli oggetti da portare. Trascina gli oggetti e ruotali
con la rotella o `R`; tre slot ospitano le reliquie attive. I punti esperienza
migliorano singole carte dalla scheda personaggio fuori dagli scontri.

Le mappe nuove misurano 160, 192 o 224 celle per lato. I punti d'interesse
hanno cortili, ingressi e coperture. Fuori dagli scontri il robot si muove
liberamente; durante gli scontri il pavimento attorno ai combattenti diventa
una griglia di piastrelle e il movimento torna a celle. I muri che coprono
il robot o i nemici si diradano per lasciarli vedere. L'ologramma indica aree approssimative dei POI senza mostrare
i nemici. Le spedizioni già salvate mantengono la loro geografia originale.

## Documentazione

| Documento | Contenuto |
|---|---|
| [Architettura](docs/architettura.md) | package, dipendenze, proprietà delle risorse e contratti |
| [Engine e minigiochi](docs/engine.md) | host, scene, input, minigiochi e atlanti incorporati |
| [Combattimento](docs/regole/combattimento.md) | clock, comandi, status, reazioni, movimento e oggetti |
| [Carte e dadi](docs/regole/carte.md) | catalogo, mazzo, targeting, spell e RNG |
| [Meccaniche delle carte](docs/regole/meccaniche.md) | ombra, terreno, cariche, lazzo, pesca, Pinball, FPS, Inondazione, Bomb Marley, Cannone, Buco Nero e Dinosauro |
| [Dispositivi e attività](docs/regole/dispositivi.md) | Tesla, trappole, equipaggiamento, ring e sblocchi |
| [Nemici e progressione](docs/regole/progressione.md) | incontri, stanze, rotta, economia e reliquie |
| [Presentazione](docs/presentazione.md) | film delle carte, timeline, HUD, sprite e animazioni |
| [Modalità libere](docs/modalita_libere.md) | simulazioni continue e laboratori tecnici |
| [Verifica](docs/verifica.md) | controlli, catture e telemetria |
| [Sviluppo](docs/sviluppo.md) | convenzioni Odin e metodo di lavoro |
| [Piano della griglia](docs/piano-griglia.md) | fasi da eseguire una alla volta: bersagli in evidenza, altezze, montagna a spirale, caverne, strutture, hub in 3D |
| [Piano della profondità](docs/piano-profondita.md) | fasi da eseguire una alla volta: terreno scolpito, mappa a piani, grotte senza caricamento, editor, ponti e gallerie nei biomi |
| [Cronologia](CHANGELOG.md) | milestone e refactor precedenti; le note storiche non definiscono le regole attuali |

## Sviluppo

```sh
sh scripts/check.sh --quick --headless
sh scripts/check.sh
```

Gli script usano output temporanei e controllano tutti i package raggiungibili.
I controlli completi includono le configurazioni con e senza assert e il link
nativo. Su Windows usare `scripts/check.ps1`. Dettagli e comandi mirati sono
in [Verifica](docs/verifica.md).

Le modifiche strutturali devono preservare regole, ordine degli eventi e RNG.
Il confine fra simulazione e presentazione resta esplicito; nuove proprietà
delle carte appartengono al catalogo, nuove risorse devono avere un proprietario
e una durata documentati. I risultati dei singoli lotti appartengono alla
cronologia o alla descrizione della modifica, senza conteggi della suite qui.
