# Odin PP

Roguelike con deck building, simulazione tattica a griglia, ambienti 3D a blocchi
e personaggi pixel art. Carte, nemici, terreno e dispositivi condividono un
mondo deterministico; il renderer ne anima gli eventi senza decidere le regole.
Il menu offre anche sei minigiochi: platform 2D e 3D, arena, FPS, puzzle e ring.

Il gioco principale usa un solo runtime tattico 3D. Gli alias `--m7`, `--m8` e
`--m9` restano compatibili; la modalità classica e la vista `--flat` sono ritirate.

## Avvio

Serve Odin con le librerie Raylib della distribuzione. La toolchain fissata
nella CI è `dev-2026-10:84bc3fc21`. Dalla radice del progetto:

```sh
./run.sh
./run.sh --seed=0xC0FFEE
./run.sh --run
```

Su Windows usare `./run.ps1`. `ODIN` può indicare un compilatore alternativo.
Gli script ricompilano con `-o:none`, evitando l'attesa dell'ottimizzatore
prima dell'apertura della finestra. Per una build riutilizzabile:

```sh
mkdir -p build
odin build src -o:none -out:build/odin_pp
./build/odin_pp
```

Il launcher raccoglie run, minigiochi, record e impostazioni. Gli avvii
`--minigame=fps` e `--minigame=ring` aprono direttamente le rispettive prove;
`--mechanics-lab` apre la pratica delle carte. Le altre opzioni e le regole
per i salvataggi sono nel [manuale di avvio](docs/avvio.md).

## Giocare

Ogni combattimento offre una finestra temporale per agire. Movimento, attacchi
e carte consumano tempo; i nemici seguono ritmi propri. Un cast ferma il mondo
mentre consuma il tempo della carta; le animazioni dei dadi fermano anche
quel timer. Terminato il combattimento, la stanza si illumina e si attraversa
liberamente per raccogliere il loot e raggiungere l'uscita.

| Input | Azione principale |
|---|---|
| `WASD` | movimento; attacco contro un nemico adiacente |
| trascina una carta | anteprima e giocata sulla griglia |
| `1`–`8` | seleziona o gioca una carta |
| `F` | Refocus |
| `Tab` | ologramma; durante il combattimento il tempo continua |
| clic sui pulsanti dell'HUD | dispositivi, equipaggiamento e personaggio |
| `Esc` | annulla o chiude la schermata corrente |
| `P` | pausa della run |
| `F10` | ritorna al menu, nelle partite avviate dal launcher |
| `F11` | schermo intero |

L'elenco completo dei controlli, i QTE e le regole del tempo sono in
[Combattimento](docs/regole/combattimento.md). Le schermate di ricompensa,
negozio e riposo consentono di aprire **Mostra effetto** per provare una carta.

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
