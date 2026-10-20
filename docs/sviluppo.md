[← Odin PP](../README.md)

### Formato e confini

`.editorconfig` definisce UTF-8, LF e tabulazioni per Odin. Il controllo
statico usa `-vet -strict-style`; non viene dichiarato un controllo `odinfmt`
finché il repository non dispone di un formatter fissato e riproducibile.
Le nuove procedure interne vanno marcate `@(private)` o
`@(private = "file")`; esportare soltanto contratti usati dagli altri package.

Le build degli script finiscono in `build/`, le catture native in
`build/captures/`. Il binario locale `game` non è più tracciato. Non spostare
le modalità di pratica del giocatore in `devtools`: quel package contiene
strumenti di sviluppo, non schermate o regole del prodotto.


## Odin: appunti per lo sviluppo

Questi appunti conservano i principi e la sintassi utili delle guide originali.
Il progetto privilegia dati, ownership, lifetime e costi espliciti.

### Dati, memoria ed errori

Odin usa struct e procedure esterne, composizione e allocatori espliciti;
non ha GC, classi con ereditarietà o eccezioni. Una directory è un package;
i file condividono `package`, le dichiarazioni sono pubbliche per default,
`@(private)` restringe al package e `@(private="file")` al file.

| Container | Uso |
|---|---|
| `[N]T` | storage fisso, nessuna allocazione |
| `[Enum]T` | tabella indicizzata da enum |
| `[]T` | vista su memoria altrui, senza ownership |
| `[dynamic]T` | collezione densa che può crescere |
| `map[K]V` | lookup per asset/config/cache; ordine di iterazione non stabile |
| `#soa[dynamic]T` | layout per campi, da introdurre quando le misure lo giustificano |

Una slice o stringa temporanea non può sopravvivere al backing storage.
`append` può riallocare un array dinamico e invalidare i puntatori;
`unordered_remove` può cambiarne gli indici. Conservare ID e risolverli al
momento dell'uso. `reserve` va fatto in inizializzazione quando la capacità
è prevedibile. `clear` conserva il buffer; `ordered_remove` preserva l'ordine.

Acquisire una risorsa e dichiarare subito il cleanup con `defer`, eseguito a
fine **scope** in ordine inverso. `new/free` gestiscono un valore;
`make/delete` il backing storage dei container. `free_all` svuota allocatori
che lo supportano. `context.allocator` e `context.temp_allocator` propagano la
politica alle chiamate nello scope: gli asset richiedono vita lunga, lo scratch
di frame può essere liberato a fine frame. Mai conservare dati temp oltre quel
confine. Le risorse GPU vanno rilasciate prima della finestra.

Gli errori attesi, come file mancanti o input malformati, sono valori restituiti;
assert controlla invarianti interne, panic stati irrecuperabili. Non inserire
mutazioni dentro assert: con `-disable-assert` non verrebbero eseguite.
Eseguire prima l'operazione e controllarne il risultato separatamente.
`or_return` serve quando propagare l'errore è la gestione voluta; altrimenti
aggiungere contesto con un controllo esplicito.

### Sintassi essenziale

```odin
count: i32 = 10                 // tipo esplicito
speed := f32(240)               // inferenza e conversione esplicita
MAX_COUNT :: 32                // costante compile-time
Vec2 :: [2]f32
Entity_Id :: distinct u32       // stesso layout, identità di tipo diversa

position := Vec2{10, 20}
position += Vec2{1, 0} * 2      // operazioni su array; accessori .x, .y

Actor :: struct {
    id: Entity_Id,
    health: i32,
}

hurt :: proc(actor: ^Actor, amount: i32) {
    actor.health -= amount     // accesso ai campi tramite puntatore
}

actor := Actor{id = Entity_Id(1), health = 10}
ptr := &actor.health
ptr^ -= 1                      // dereferenziazione

for i in 0..<10 { }             // limite escluso; 0..=9 lo include
for value, index in values { }  // value è una copia
for &value in values {          // modifica in place
    value += 1
}

Mode :: enum { Menu, Playing }
mode := Mode.Playing
switch mode {                  // enum esaustivo, no fallthrough implicito
case .Menu:
case .Playing:
}

first :: proc(values: []$T) -> (value: T, ok: bool) {
    if len(values) == 0 do return {}, false
    return values[0], true
}
```

Gli snippet illustrano costrutti separati, non un file eseguibile completo.
I parametri sono immutabili: per modificare il chiamante passare `^T`.
`using` promuove campi per composizione, senza introdurre una gerarchia.

| Costrutto | Promemoria |
|---|---|
| `nome := valore`, `nome :: valore` | variabile inferita / costante o dichiarazione di tipo/procedura |
| `T(x)`, `cast(T)x` | conversione esplicita; valutare range, precisione e segno |
| `transmute(T)x` | reinterpretazione dei bit, con stessa dimensione |
| `size_of(T)`, `align_of(T)`, `type_of(x)` | introspezione di layout e tipo |
| `if cond do return` | corpo a istruzione singola |
| `a if cond else b` | espressione condizionale |
| `for cond {}`, `for {}` | ciclo condizionale / infinito |
| `proc(a: i32 = 1)` | parametro con default; chiamata con nome `f(a = 2)` |
| `f :: proc{f_int, f_float}` | overload esplicito |
| `bit_set[Enum]` | insieme di flag; `in`, `+`, `-`, `&`, `card` |
| `union {bool, i64, string}` | alternative tipizzate; `v.(T)` e type switch |
| `any` | valore dinamico per tooling/reflection, non sostituto delle invarianti |
| `x := expr or_else fallback` | fallback su risultato optional |
| `or_return`, `or_break`, `or_continue` | propagazione o controllo del loop |
| `$T: typeid`, `[]$T` | parametric polymorphism esplicito o inferito |
| `when ODIN_DEBUG`, `when ODIN_OS == .Linux` | selezione compile-time |
| `#partial switch` | gestione intenzionalmente parziale di enum |
| `@(test)` | procedura di test con `t: ^testing.T` |

String è una vista UTF-8 immutabile: `len` conta byte, l'iterazione produce
rune e indice in byte. Usare `strings.Builder` per costruire testo;
`fmt.tprintf` e `fmt.ctprintf` producono rispettivamente string/cstring temp,
valide solo fino al reset dell'allocatore. Le stringhe raw fra backtick non
interpretano escape. Map lookup supporta `value, ok := map[key]`;
`delete_key(&map, key)` rimuove una chiave.

`foreign` collega API native; `proc "c"` non riceve il context Odin.
A ogni confine C verificare ownership, durata dei puntatori, layout e calling
convention. Raylib si importa con `import rl "vendor:raylib"`.

| Package | Utilità |
|---|---|
| `core:fmt`, `core:strings` | formattazione e testo |
| `core:math`, `core:math/linalg` | scalari, vettori, matrici e quaternioni |
| `core:math/rand` | generatori con seed espliciti |
| `core:mem` | allocatori, arene e tracking |
| `core:slice`, `core:container` | ordinamento, ricerca e container |
| `core:os`, `core:time`, `core:log` | file, argomenti, clock e logging |
| `core:encoding/json`, `core:testing` | configurazioni e test |

### Metodo di lavoro

Chiarire dati, proprietario, durata e procedure che possono mutarli prima di
introdurre astrazioni. Mantenere simulazione senza finestra, renderer passivo,
input trasformato in comandi e RNG isolati. Il tattico avanza con pulse e beat;
la fisica cosmetica dei dadi non deve influenzarlo. Le modalità libere M9
avanzano invece con il proprio tick fisso a 60 Hz, senza alimentare il clock
della run sospesa.

Preferire servizi richiesti dal gioco a ECS o generics anticipati. Misurare
frame time, allocazioni e copie prima di ottimizzare; `mem.Tracking_Allocator`
e il runner di test aiutano a rilevare leak e bad free. Mantenere il tracking
attivo per tutta la durata delle operazioni osservate e distruggerlo dopo le
risorse tracciate. Testare logica pura, ID, parsing, determinismo e transizioni;
per la presentazione verificare anche snapshot intermedi e smoke grafici.

Il flusso quotidiano è modifica piccola, `odin check`, test pertinenti e demo
quando cambiano grafica o input. Per un singolo file usare
`odin run esempio.odin -file`; `odin doc core:fmt` apre la documentazione CLI.
`-debug` aggiunge simboli, `-o:speed` ottimizza, `-out:...` sceglie il binario,
`--` separa gli argomenti del programma.

Riferimenti: [overview Odin](https://odin-lang.org/docs/overview/),
[guida ai test](https://odin-lang.org/docs/testing/),
[indice dei package](https://pkg.odin-lang.org/),
[sorgenti Odin](https://github.com/odin-lang/Odin),
[materiale Odin e Raylib di Karl Zylinski](https://zylinski.se/).
