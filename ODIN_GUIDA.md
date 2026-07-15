# Odin — Guida Ragionata per un Mini Game Engine

Il *perché* dietro la sintassi. Per il *come si scrive X* consulta
[**ODIN_CHEATSHEET.md**](ODIN_CHEATSHEET.md).

> **Regola guida:** rendi espliciti dati, ownership, lifetime e costo. In Odin
> la chiarezza del programma è più importante della quantità di astrazione.

## Indice

- [1. Mappa mentale](#1-mappa-mentale)
- [2. Dati, ownership, lifetime](#2-dati-ownership-lifetime)
- [3. Scegliere i container](#3-scegliere-i-container)
- [4. La politica del frame](#4-la-politica-del-frame)
- [5. Errori e robustezza](#5-errori-e-robustezza)
- [6. Package e struttura del progetto](#6-package-e-struttura-del-progetto)
- [7. Architettura del mini-engine](#7-architettura-del-mini-engine)
- [8. Test, debug e profiling](#8-test-debug-e-profiling)
- [9. Trappole comuni](#9-trappole-comuni)
- [10. Percorso di studio](#10-percorso-di-studio)
- [Promemoria finale](#promemoria-finale)

---

## 1. Mappa mentale

Odin è un linguaggio general-purpose, compilato e data-oriented. Offre un
controllo di basso livello pratico senza richiedere di scrivere C.

### Cosa **non** ha

- Garbage collector.
- Classi, ereditarietà o metodi impliciti.
- Eccezioni.
- Overload implicito di procedure (esiste quello *esplicito* via proc group).
- Interfacce nello stile Java/C#.
- Pointer arithmetic implicita.

### Cosa ha al loro posto

| Se cerchi... | In Odin usa... |
|---|---|
| Oggetti con stato | `struct` e procedure esterne |
| Ereditarietà | Composizione, `using`, union o procedure come valori |
| Eccezioni | Valori di ritorno `Error`/`bool`, `or_return` |
| GC | Allocatori e lifetime espliciti |
| Overload | Proc group espliciti: `f :: proc{f_int, f_f32}` |
| Collection generiche | Parametric polymorphism |
| Binding a librerie native | `foreign` e package `vendor:` |

Il punto non è la minimalità in sé: è che ogni costo (allocazione, copia,
dispatch) resta visibile nel codice. Quando leggi una procedura Odin, sai
cosa fa senza cercare una classe base o un distruttore nascosto:

```odin
update_player :: proc(player: ^Player, dt: f32) {
    player.position += player.velocity * dt
}
```

Modifica il `Player` passato per puntatore. Tutto qui, e si vede.

---

## 2. Dati, ownership, lifetime

Le domande da farsi **prima** di progettare qualunque funzione o sistema:

1. Quali dati esistono?
2. Chi li possiede?
3. Quanto devono vivere?
4. Quale procedura li legge o modifica?

In un linguaggio senza GC queste domande non sono opzionali — ma sono anche
il motivo per cui il codice risultante è più semplice da debuggare: ogni byte
ha un proprietario e un momento di morte deciso da te.

Conseguenze pratiche:

- **Una slice è una vista, non ownership.** Chi la riceve deve poter contare
  sul fatto che la memoria sottostante resti valida per tutta la durata
  dell'uso. Se un dato deve sopravvivere al proprietario della memoria,
  copialo.
- **Le conversioni sono decisioni.** `f32(x)` non è rumore sintattico: è una
  scelta su range, precisione e segno. Non convertire "per far tacere il
  compilatore".
- **I parametri sono immutabili** e questo è un vincolo utile: se una
  procedura deve modificare qualcosa del chiamante, la firma lo dichiara
  (`^T`). Leggendo la firma sai già gli effetti.
- **`distinct` è ownership a livello di tipo.** `Entity_Id :: distinct u32` e
  `Texture_Id :: distinct u32` hanno lo stesso layout ma il compilatore
  impedisce di scambiarli. Costo zero, bug interi eliminati.

La regola operativa per le risorse: **acquisisci, poi scrivi subito il
`defer` di rilascio**. Ownership e cleanup restano visibili nello stesso
punto, e lo scope del `defer` (blocco, non funzione) ti obbliga a decidere
*dove* la risorsa muore.

---

## 3. Scegliere i container

| Container | Quando | Perché |
|---|---|---|
| `[N]T` array fisso | dimensione nota al compile-time | zero allocazioni, lunghezza nel tipo |
| `[Enum]T` enumerated array | lookup table per enum | completezza verificata dal compilatore |
| `[]T` slice | passare dati a una procedura | vista economica, nessuna ownership |
| `[dynamic]T` | collezioni che crescono | dati densi, cache-friendly |
| `map[K]V` | lookup sparsi | asset per path, config, cache |
| `#soa[dynamic]T` | update che scandiscono un campo | layout SoA gratis — solo dopo misura |

Le decisioni che contano per un gioco:

- **Entità aggiornate ogni frame → array densi + ID.** Una mappa ha cache
  locality scarsa e ordine di iterazione instabile; un `[dynamic]Enemy`
  scandito linearmente è più veloce *e* più semplice da debuggare.
- **`unordered_remove` per proiettili e particelle.** Scambia con l'ultimo
  elemento in O(1); l'ordine quasi mai conta per queste entità.
- **`reserve` in inizializzazione** se fai `append` ogni frame: meno
  riallocazioni, e soprattutto meno occasioni di invalidare puntatori.
- **Mai conservare puntatori a elementi di un dynamic array** che può
  crescere: `append` può riallocare. Conserva ID o indici, e risolvi il
  puntatore al momento dell'uso.
- **SoA non è il punto di partenza.** `#soa` costa zero da adottare dopo:
  fallo quando il profiler mostra che un update scandisce un solo campo su
  migliaia di entità.

---

## 4. La politica del frame

Odin ha gestione manuale della memoria, ma tutte le allocazioni passano da
un'interfaccia di allocator. Questo trasforma "gestione manuale" da *chiamare
free ovunque* a *decidere politiche per gruppi di dati*.

### Il context come canale delle politiche

`context.allocator` e `context.temp_allocator` viaggiano implicitamente con
ogni chiamata. Modificare il context in uno scope cambia la politica per
tutto ciò che chiami da lì:

```odin
context.allocator = arena_allocator
load_level()   // ogni allocazione interna finisce nell'arena
```

Questo è il pattern chiave: il codice di `load_level` non sa niente di arene,
eppure tutta la sua memoria si libera con un solo `free_all` al cambio scena.

### Il temp allocator e il confine del frame

La politica classica per un gioco: **`free_all(context.temp_allocator)` una
volta per frame**, a fine frame. Da quel momento tutto ciò che era temporaneo
(testo di debug formattato con `tprintf`, liste di lavoro, scratch buffer) è
invalido.

Il confine deve essere netto: niente puntatori o stringhe temp conservati
oltre il frame. Se un dato deve sopravvivere, si copia in memoria posseduta.

### Strategie per tipo di dato

| Dato | Strategia iniziale |
|---|---|
| Asset caricati | allocator a lunga vita |
| Stato della partita | arena/session allocator |
| Dati solo-frame (testo debug, liste di lavoro) | `context.temp_allocator` |
| Proiettili/particelle | array preallocati o pool |
| Livello attuale | arena liberata al cambio scena |

L'ordine giusto: **prima rendi corretta l'ownership, poi misura**. Non
costruire un allocator sofisticato per un problema non ancora osservato — il
tracking allocator (snippet nel cheat sheet) ti dice quando ne hai uno vero.

---

## 5. Errori e robustezza

Odin non ha eccezioni: gli errori sono dati restituiti normalmente. La
distinzione che conta non è sintattica ma di **categoria**:

| Categoria | Esempi | Strumento |
|---|---|---|
| Errore atteso | file mancante, input malformato, rete | valore di ritorno, gestito dal chiamante |
| Bug interno | health negativa, indice fuori range logico | `assert` — deve esplodere in debug |
| Stato irrecuperabile | enum sconosciuto in uno switch esaustivo | `panic` |

`assert` su input esterno è un errore di categoria: trasformi un caso
gestibile in un crash. Al contrario, restituire un errore per un invariante
interno lo nasconde: il bug sopravvive e si manifesta più lontano.

Su `or_return`: usalo quando la propagazione *è* la gestione giusta (catene
di parsing, caricamento risorse). Quando devi trasformare l'errore o
aggiungere contesto, il controllo esplicito con `if err != ...` resta più
chiaro. La convenzione dell'errore come ultimo valore di ritorno è ciò che
rende `or_return` componibile: mantienila nelle tue API.

---

## 6. Package e struttura del progetto

Regole del linguaggio: una directory = un package; tutti i file della
directory dichiarano lo stesso `package`; le dichiarazioni sono pubbliche per
default (`@(private)` per restringere); `core:foo/bar` è tassonomia di
directory, non una gerarchia di dipendenze.

Struttura iniziale ragionevole:

```text
src/
  main.odin
  core/      # Vec2, rect, random, timer — zero dipendenze
  app/       # finestra, loop, frame time
  input/
  render/
  physics/
  game/
  debug/
tests/
assets/
```

Due indicazioni pratiche:

- **Non creare package microscopici all'inizio.** Sposta codice in un package
  quando ha una responsabilità precisa o un confine di dipendenze utile — il
  confine giusto emerge dal codice, non lo si indovina prima.
- **La direzione delle dipendenze conta più della suddivisione**: `core/` non
  dipende da niente, `game/` non importa `render/` (comunica tramite dati),
  solo `render/` e `app/` toccano Raylib.

Flusso di lavoro: modifica piccola → `odin check .` → test se la logica è
pura → avvia il gioco se cambia comportamento visivo o di input.

---

## 7. Architettura del mini-engine

Non iniziare con un engine "universale". Costruisci servizi riusabili solo
quando il gioco dimostra di averne bisogno.

### Ordine di implementazione

1. **App loop**: finestra, shutdown, input e frame time.
2. **Core 2D**: `Vec2`, rettangoli, camera, random con seed, timer.
3. **Vertical slice**: player, stanza, muro, nemico, proiettile, danno,
   restart.
4. **Debug**: hitbox, FPS, entità e memoria.
5. **Dati**: tilemap e asset da file.
6. **Servizi**: audio, animazioni, scene, UI, asset cache.
7. **Rigore**: timestep fisso, replay, profiling e test.

### Separare subito loop e stato

Appena il loop Raylib minimo funziona, estrai:

```odin
Game :: struct {
    // Stato persistente della partita.
}

game_init   :: proc() -> Game
game_update :: proc(game: ^Game, dt: f32)
game_draw   :: proc(game: ^Game)
game_deinit :: proc(game: ^Game)
```

Raylib è il backend iniziale, non la tua architettura: il package `game` non
dovrebbe spargere chiamate Raylib in ogni sistema. Questo confine è ciò che
rende possibile testare la simulazione senza finestra.

### World semplice prima dell'ECS

```odin
World :: struct {
    players: [dynamic]Player,
    enemies: [dynamic]Enemy,
    bullets: [dynamic]Bullet,
}
```

Spesso migliore di un ECS all'inizio: dati densi, update leggibile, debug
immediato. Introduci componenti solo quando hai veri incroci di tipi di
entità e duplicazione che giustificano il costo mentale.

### Contratti da preservare

- La simulazione può girare senza rendering.
- Il rendering non modifica il gameplay.
- L'input viene letto una volta per frame e trasformato in azioni.
- Collisioni e danno hanno test deterministici.
- La memoria temporanea non esce dal frame (§4).
- Gli asset hanno un proprietario e una deinizializzazione chiara (§2).

### Fixed timestep: obiettivo, non primo ostacolo

All'inizio un `dt` variabile è accettabile per arrivare alla vertical slice.
Poi sposta la simulazione su un passo fisso e renderizza in modo
indipendente: rende molto più semplici replay, determinismo, collisioni e
test. Il seed esplicito di `core:math/rand` è l'altro ingrediente del
determinismo — fissalo fin dall'inizio, costa niente.

---

## 8. Test, debug e profiling

### Cosa testare in un gioco

Il test runner di Odin monitora allocazioni e bad free per default. La
candela va spesa sulla logica pura e deterministica:

- Collisioni AABB e risoluzione.
- Matematica e conversioni di coordinate.
- Parsing di livelli e configurazioni.
- Handle/ID e gestione di entità.
- Random seed e simulazione deterministica.
- State machine di menu, partita e pausa.

Non testare il rendering: rendilo *ininfluente* (il rendering non modifica il
gameplay, §7) e testa ciò che sta sotto.

### Debug overlay

Il gioco dovrebbe poter mostrare, senza cambiare logica: FPS e frame time,
posizione di player e camera, hitbox e collision layer, numero di entità e
proiettili, uso memoria e allocazioni, seed corrente, stato del gioco.

L'overlay non è un extra: è ciò che trasforma "il movimento sembra strano" in
"la velocità raddoppia quando dt supera 33ms".

### Memoria e tempi: osservali da subito

Attiva il tracking allocator (snippet nel cheat sheet) nelle build `-debug`
dal giorno uno: un leak trovato il giorno in cui nasce si corregge in un
minuto; trovato a fine progetto è un'archeologia. Lo stesso vale per il frame
time: misura prima di ottimizzare, sempre (§9).

---

## 9. Trappole comuni

| Trappola | Perché è un problema | Abitudine migliore |
|---|---|---|
| Usare `any` ovunque | Nasconde invarianti | Union o struct esplicite |
| Allocare nel loop caldo | Frame spike e lifetime opaco | Preallocare, riusare, misurare |
| Salvare slice/stringhe temp | Puntatori invalidi dopo `free_all` | Copiare o usare allocator lungo |
| Puntatori a elementi di dynamic array | `append` può riallocare e invalidarli | ID/indici, oppure `reserve` |
| Modificare in `for e in xs` | `e` è una copia: la modifica si perde | `for &e in xs` |
| Mappe per tutte le entità | Cache locality e ordine scarsi | Array densi per update per-frame |
| `using` in profondità | Proprietario del campo poco chiaro | Composizione piccola ed esplicita |
| Generics come prima risposta | Generalizzazione prematura | Due implementazioni concrete, poi astrai |
| ECS prima del gameplay | Astrazione senza requisito | Vertical slice prima |
| `assert` su input esterno | Crash invece di recupero | Errori restituiti e validazione (§5) |
| Ottimizzare senza misura | Complessità gratuita | Profiling e benchmark |
| Scrivere tutto in `main` | Nessun confine testabile | `init`, `update`, `draw`, `deinit` |

---

## 10. Percorso di studio

### Fase 1: una settimana di fondazioni

- Variabili, procedure, struct e puntatori.
- Slice, dynamic array, map e `defer`.
- `make`, `delete`, `new`, `free` e `context`.
- Esercizi: parser piccolo, handle `distinct u32`, lista con rimozione O(1).

### Fase 2: due settimane di fondazioni 2D

- Raylib, input, `dt`, vettori e camera.
- Tilemap e collisioni AABB.
- Esercizi: player con movimento, muri e debug draw delle hitbox.

### Fase 3: vertical slice

- Nemico, proiettile, danno, HUD, restart.
- Test per collisioni e damage.
- Nessun ECS, editor o scripting prima di questo punto.

### Fase 4: servizi dell'engine

- Asset manager con cleanup.
- Animazioni, audio e scene.
- Livelli da file.
- Pool per oggetti molto frequenti.
- Debug overlay e tracking allocator.

### Fase 5: qualità tecnica

- Fixed timestep.
- Seed riproducibili e replay.
- Profiling di frame, update e allocazioni.
- Build release e smoke test.

---

## Riferimenti

- [Overview ufficiale](https://odin-lang.org/docs/overview/) — il documento singolo più utile
- [Guida ufficiale ai test](https://odin-lang.org/docs/testing/)
- [Indice dei package](https://pkg.odin-lang.org/)
- [Repository Odin](https://github.com/odin-lang/Odin) — la sorgente di `core:` è documentazione
- [Karl Zylinski — Odin + Raylib](https://zylinski.se/) — tutorial e libro orientati a giochi in Odin
- [**ODIN_CHEATSHEET.md**](ODIN_CHEATSHEET.md) — la sintassi, in forma di reference

---

## Promemoria finale

Quando non sai come progettare qualcosa, fermati e scrivi:

1. I dati che esistono.
2. Il proprietario di ogni dato.
3. La durata della memoria.
4. Le procedure che possono modificarlo.
5. Il comportamento verificabile con un test o debug draw.

Un buon mini-game engine non è una lista di pattern: è una serie coerente di
decisioni su dati, tempo, memoria, rendering e confini di responsabilità.
