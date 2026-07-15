# Odin — Quick Reference

Consultazione rapida: solo *come si scrive X*. Il *perché* (memoria, ownership,
architettura dell'engine, trappole, percorso di studio) è in
[**ODIN_GUIDA.md**](ODIN_GUIDA.md).

Snippet verificati con `odin check` (versione dev-2026-06).

---

## Indice

[CLI](#cli) · [Dichiarazioni](#dichiarazioni) · [Tipi](#tipi) ·
[Literal](#literal) · [Conversioni](#conversioni) · [If / Switch](#if--switch) ·
[For](#for) · [Procedure](#procedure) · [Array e slice](#array-e-slice) ·
[Dynamic array](#dynamic-array) · [Vettori e matematica](#vettori-e-matematica) ·
[Stringhe](#stringhe) · [Mappe](#mappe) · [Struct e puntatori](#struct-e-puntatori) ·
[Enum / bit_set / distinct](#enum--bit_set--distinct) · [Union e any](#union-e-any) ·
[Errori](#errori) · [Defer](#defer) · [Memoria e allocatori](#memoria-e-allocatori) ·
[Generics](#generics-parapoly) · [Compile-time](#compile-time) ·
[Stdlib](#stdlib) · [Foreign e Raylib](#foreign-e-raylib) · [Test](#test) ·
[Tracking allocator](#tracking-allocator)

---

## CLI

| Comando | Effetto |
|---|---|
| `odin run .` | compila ed esegue il package |
| `odin build .` | compila soltanto |
| `odin check .` | type-check veloce (usalo di continuo) |
| `odin test .` | esegue i test |
| `odin run file.odin -file` | singolo file come package |
| `odin doc core:fmt` | documentazione da terminale |

| Flag | Effetto |
|---|---|
| `-debug` | simboli di debug, `ODIN_DEBUG = true` |
| `-out:bin/game` | nome/percorso eseguibile |
| `-vet` | warning extra (unused, shadowing…) |
| `-o:speed` | build ottimizzata |
| `-all-packages` | (test) tutti i package |
| `-- arg1 arg2` | argomenti al programma |

---

## Dichiarazioni

```odin
x: int = 10          // variabile, tipo esplicito
y := 3.14            // tipo inferito
PI_ISH :: 3.14159    // costante compile-time
MAX : i32 : 100      // costante con tipo esplicito

Vec2 :: [2]f32       // i tipi si dichiarano con ::
main :: proc() { }   // anche le procedure
```

Mnemonico: `nome : tipo = valore` → togli il tipo: `:=` → congela il valore: `::`

- Zero value garantito: `i32`→`0`, `bool`→`false`, puntatori/map/union→`nil`.
- Visibilità: pubblica per default; `@(private)` = package, `@(private="file")` = file.

---

## Tipi

| Categoria | Tipi |
|---|---|
| Booleani | `bool` (`b8 b16 b32 b64`) |
| Signed | `i8 i16 i32 i64 i128 int` |
| Unsigned | `u8 u16 u32 u64 u128 uint uintptr` |
| Float | `f16 f32 f64` |
| Testo | `string` (byte UTF-8, immutabile), `cstring`, `rune` |
| Endianness | `u32le`, `u32be`, … |

Per un gioco: quasi sempre `i32 u32 f32 bool string` + ID `distinct`.

---

## Literal

```odin
decimal := 1_000_000
binary  := 0b1010
octal   := 0o755
hex     := 0xff
float   := 1.25e3

text := "riga\nriga2"        // stringa con escape
path := `C:\project\assets`  // raw string: nessun escape
char := 'A'                  // rune
```

I literal costanti sono **untyped**: `speed: f32 = 240` funziona senza cast.

---

## Conversioni

```odin
speed := f32(count)          // forma idiomatica T(x)
speed2 := cast(f32)count     // equivalente
bits := transmute(u32)f      // reinterpreta i bit (stessa size, raro)

Entity_Id :: distinct u32
id := Entity_Id(42)

size_of(Vec2)   align_of(Vec2)   type_of(x)
```

Sempre esplicite tra valori tipizzati. → [Guida §2](ODIN_GUIDA.md#2-dati-ownership-lifetime)

---

## If / Switch

```odin
if x > 0 { }                    // niente parentesi, graffe obbligatorie
if paused do return             // `do` = corpo a singola istruzione
if v, ok := m["k"]; ok { }      // if con dichiarazione

x := a if cond else b           // espressione condizionale
x := cond ? a : b               // equivalente
```

```odin
switch state {                  // NIENTE fallthrough implicito
case .Menu:      update_menu()
case .Playing:   fallthrough    // esplicito quando lo vuoi
case .Paused:    update_pause()
case:            panic("unknown")
}

#partial switch state {         // enum: gestisci solo alcuni casi
case .Playing: ...
}

switch {                        // switch su condizioni (catena else-if)
case x < 0:  ...
case x == 0: ...
case:        ...
}

case .A, .B:                    // più valori
case 0..<10:                    // range
```

Su un enum senza `#partial` il compilatore **esige tutti i casi**.

---

## For

Unico costrutto di loop.

```odin
for i := 0; i < 10; i += 1 { }  // stile C (niente ++)
for i in 0..<10 { }             // range esclusivo
for i in 0..=9  { }             // range inclusivo
for cond { }                    // "while"
for { }                         // infinito

for e, i in slice { }           // e = COPIA, i = indice
for &e in slice { e.hp -= 1 }   // &e = riferimento, modifica in-place

outer: for y in 0..<h {         // label per break/continue annidati
    for x in 0..<w {
        if found do break outer
    }
}
```

---

## Procedure

```odin
add :: proc(a, b: i32) -> i32 { return a + b }

// default + chiamata con nome
spawn :: proc(pos: Vec2, health: i32 = 100) -> Entity_Id { ... }
id := spawn(pos = {0, 0}, health = 50)

// multi-return (errore per ultimo, per convenzione)
divide :: proc(a, b: f32) -> (result: f32, ok: bool) {
    if b == 0 do return 0, false
    return a / b, true
}

// parametri immutabili: shadowing esplicito per una copia locale
wrap :: proc(angle: f32) -> f32 {
    angle := angle
    angle = math.mod(angle, 360)
    return angle
}

// proc group = overload esplicito (così fanno min/max/abs in core)
length :: proc{length_vec2, length_vec3}

// procedure come valori (callback, strategie AI)
Operation :: proc(a, b: i32) -> i32
apply :: proc(op: Operation, a, b: i32) -> i32 { return op(a, b) }
```

- Per mutare il valore del chiamante: passa `^T`.
- `proc "c"` (callback C) non riceve il `context`: se serve,
  `context = runtime.default_context()`.

---

## Array e slice

```odin
weights: [4]f32 = {1.0, 0.5, 0.25, 0.125}  // lunghezza NEL tipo
grid: [10][10]Tile

// enumerated array: lookup table verificata dal compilatore
tile_solid := [Tile]bool{
    .Empty = false,
    .Wall  = true,
    .Goal  = false,
}

// slice = vista (ptr + len), NON ownership
values := []i32{10, 20, 30, 40}
part := values[1:3]     // anche values[:2], values[2:]
```

---

## Dynamic array

```odin
enemies := make([dynamic]Enemy, 0, 64)   // len=0, cap=64
defer delete(enemies)

append(&enemies, Enemy{health = 10})
```

| Operazione | Note |
|---|---|
| `len(d)` / `cap(d)` | elementi vivi / capacità |
| `reserve(&d, n)` | prealloca → meno riallocazioni |
| `clear(&d)` | len=0, buffer riusabile |
| `ordered_remove(&d, i)` | preserva ordine, O(n) |
| `unordered_remove(&d, i)` | swap con ultimo, O(1) — proiettili/particelle |

⚠ `append` può riallocare e **invalidare i puntatori** agli elementi.
→ [Guida §9](ODIN_GUIDA.md#9-trappole-comuni)

```odin
entities: #soa[dynamic]Entity   // layout struct-of-arrays, accesso identico
append_soa(&entities, Entity{})
```

---

## Vettori e matematica

Il vettore idiomatico **non è una struct**:

```odin
Vec2 :: [2]f32
Vec3 :: [3]f32

position += velocity * dt   // array programming: element-wise gratis
doubled := position * 2     // broadcast scalare

p := Vec3{1, 2, 3}
p.x  p.y  p.z               // accessor su array len ≤ 4 (anche .r .g .b .a)
p.xz                        // swizzle → Vec2{1, 3}
```

```odin
import "core:math/linalg"

linalg.length(v)   linalg.normalize(v)   linalg.dot(a, b)   linalg.cross(a, b)

M :: matrix[4, 4]f32        // matrice nativa, moltiplicazione con *
```

Altri: `core:math` (`clamp`, `lerp`, trig), `core:math/rand` (seed espliciti
→ determinismo/replay).

---

## Stringhe

```odin
s := "Odin dungeon"
len(s)                       // BYTE, non caratteri

for r, byte_idx in "così" {} // itera rune UTF-8, indice in byte

// costruzione: Builder, non concatenazioni
b := strings.builder_make(context.temp_allocator)
strings.write_string(&b, "score: ")
strings.write_int(&b, score)
label := strings.to_string(b)

// formattazione temp (vive fino a free_all del temp allocator)
tmp := fmt.tprintf("FPS: %d", fps)
rl.DrawText(fmt.ctprintf("FPS: %d", fps), 10, 10, 20, rl.BLACK)  // cstring temp
```

⚠ Non salvare stringhe temp oltre il frame. → [Guida §4](ODIN_GUIDA.md#4-la-politica-del-frame)

---

## Mappe

```odin
scores := make(map[string]int)
defer delete(scores)

scores["raven"] = 1200
v, ok := scores["raven"]         // lettura con test
v2 := scores["x"] or_else 0      // fallback
delete_key(&scores, "raven")

for key, value in scores { }     // ⚠ ordine NON stabile
```

Lookup (asset, config, cache): sì. Entità aggiornate ogni frame: no —
array densi + ID. → [Guida §3](ODIN_GUIDA.md#3-scegliere-i-container)

---

## Struct e puntatori

```odin
Transform :: struct {
    position: Vec2,
    rotation: f32,
    scale:    Vec2,
}

t := Transform{position = {100, 50}, scale = {1, 1}}  // campi omessi = zero
origin := Vec2{0, 0}                                  // posizionale se ovvio
```

```odin
ptr: ^i32 = &health    // ^T = tipo puntatore
ptr^ -= 10             // deref: cappello DOPO
// zero value: nil — niente pointer arithmetic implicita

move :: proc(t: ^Transform, delta: Vec2) {
    t.position += delta          // deref implicita sui campi
}
```

```odin
Entity :: struct {
    using transform: Transform,  // promuove i campi: entity.position
    id: Entity_Id,
}
```

`using`: un livello di composizione, non gerarchie. → [Guida §9](ODIN_GUIDA.md#9-trappole-comuni)

---

## Enum / bit_set / distinct

```odin
Game_State :: enum { Menu, Playing, Paused, Game_Over }

state := Game_State.Playing
if state == .Playing { }         // selettore implicito
for s in Game_State { }          // itera tutti i valori
```

```odin
Entity_Flag  :: enum { Visible, Solid, Hostile, Damaged }
Entity_Flags :: bit_set[Entity_Flag]

flags: Entity_Flags = {.Visible, .Solid}

.Solid in flags                  // test
flags += {.Damaged}              // aggiungi
flags -= {.Visible}              // togli
a + b   a & b   a - b            // unione, intersezione, differenza
card(flags)                      // conteggio
flags & {.Visible, .Hostile} != {}   // "almeno uno"
```

```odin
Entity_Id  :: distinct u32       // stesso layout, tipo incompatibile
Texture_Id :: distinct u32       // impossibile scambiarli. Costo: zero
```

---

## Union e any

```odin
Config_Value :: union { bool, i64, f64, string }   // tagged, zero value = nil

v: Config_Value = "windowed"

s, ok := v.(string)              // type assertion sicura

switch x in v {                  // type switch
case bool:   ...
case i64:    ...
case f64:    ...
case string: ...
case:        ...                 // nil
}
```

```odin
a: any = 42                      // ptr + typeid runtime
n, ok := a.(int)
```

`any` solo per logging/tool/reflection, mai come modello dati.
→ [Guida §9](ODIN_GUIDA.md#9-trappole-comuni)

---

## Errori

Niente eccezioni: errori = valori di ritorno (ultimo, per convenzione).

```odin
Parse_Error :: enum { None, Empty_Input, Invalid_Character }

parse_digit :: proc(text: string) -> (value: i32, err: Parse_Error) {
    if len(text) == 0 do return 0, .Empty_Input
    if text[0] < '0' || text[0] > '9' do return 0, .Invalid_Character
    return i32(text[0] - '0'), .None
}

digit, err := parse_digit("7")
if err != .None do return
```

| Costrutto | Uso |
|---|---|
| `x := expr or_else default` | fallback su `(value, ok)` |
| `x := expr or_return` | propaga l'errore/`false` al chiamante |
| `or_break` / `or_continue` | come sopra, nei loop |
| `assert(cond, "msg")` | invarianti INTERNE (bug tuoi) |
| `panic("msg")` | stato irrecuperabile |

```odin
load_config :: proc() -> (config: Config, ok: bool) {
    data := read_file("config.txt") or_return
    config = parse_config(data)    or_return
    ok = true
    return
}
```

⚠ Mai `assert` su input esterno/file: quelli si restituiscono.
→ [Guida §5](ODIN_GUIDA.md#5-errori-e-robustezza)

---

## Defer

Esegue a **fine scope** (non fine funzione!), in ordine inverso.

```odin
resource := acquire_resource()
defer release_resource(resource)   // regola: acquisisci → defer SUBITO

entities := make([dynamic]Entity, 0, 128)
defer delete(entities)

// API core:os recente: allocator esplicito, errore come union
data, err := os.read_entire_file("config.txt", context.allocator)
if err != nil do return
defer delete(data)
```

⚠ Dentro un loop scatta a ogni iterazione; dentro un `if` a fine blocco.

---

## Memoria e allocatori

```odin
ptr := new(i32);  defer free(ptr)              // singolo valore → ^T
d := make([dynamic]i32, 0, 64);  defer delete(d)
m := make(map[string]int, 32);   defer delete(m)
s := make([]u8, 256, context.temp_allocator)   // allocator esplicito
```

| Operazione | Per cosa |
|---|---|
| `new(T)` / `free(p)` | singolo valore |
| `make(...)` / `delete(x)` | backing storage dei container |
| `free_all(alloc)` | svuota tutto (se supportato: temp, arene) |

**Context** — implicito in ogni proc Odin; modificarlo vale per lo scope e
tutto ciò che chiami da lì:

```odin
context.allocator        // default di new/make
context.temp_allocator   // dati a vita breve
context.logger

context.allocator = arena_allocator
load_level()             // tutte le allocazioni interne usano l'arena
```

**Politica del frame** (classica per un gioco):

```odin
for !rl.WindowShouldClose() {
    update(&game, dt)
    draw(&game)
    free_all(context.temp_allocator)   // una volta per frame
}
```

Strategie per dato (asset, arena di livello, pool…): → [Guida §4](ODIN_GUIDA.md#4-la-politica-del-frame)

---

## Generics (parapoly)

Specializzati al compile-time.

```odin
allocate_one :: proc($T: typeid) -> ^T {       // tipo esplicito
    return new(T)
}
health := allocate_one(i32)

first :: proc(values: []$T) -> (value: T, ok: bool) {  // tipo inferito
    if len(values) == 0 do return {}, false
    return values[0], true
}

Pool :: struct($T: typeid, $N: int) {          // struct parametrica
    items: [N]T,
    alive: bit_set[0..<N],
}
```

Non è la prima risposta alla duplicazione. → [Guida §9](ODIN_GUIDA.md#9-trappole-comuni)

---

## Compile-time

```odin
when ODIN_DEBUG { enable_debug_overlay() }     // true con -debug
when ODIN_OS == .Linux { } else { }            // ramo escluso non compilato
when ODIN_ARCH == .amd64 { }
```

File filtrati automaticamente dal suffisso:
`clipboard_linux.odin`, `backend_windows_amd64.odin`
(suffisso = file intero per piattaforma; `when` = blocco piccolo).

```odin
@(test)            // attributi: sulle dichiarazioni
@(private)
@(private="file")

#partial  #soa  #force_inline  #no_bounds_check   // direttive: su espressioni
```

⚠ Direttive di ottimizzazione solo dopo profiling.

---

## Stdlib

| Package | Uso |
|---|---|
| `core:fmt` | `println`, `printf`, `tprintf` (temp), `aprintf` (allocata) |
| `core:math` | trig, `clamp`, `lerp`, costanti |
| `core:math/linalg` | vettori, matrici, quaternioni |
| `core:math/rand` | random con seed espliciti |
| `core:mem` | arene, tracking allocator |
| `core:slice` | sort, ricerca, manipolazione slice |
| `core:strings` | `Builder`, split, trim |
| `core:os` | file, argomenti, processi |
| `core:time` | durate, clock, timestamp |
| `core:log` | logging via `context.logger` |
| `core:encoding/json` | config e livelli |
| `core:container` | queue, small array, … |
| `core:testing` | test |

Indice completo: <https://pkg.odin-lang.org/> — consultalo prima di
reinventare un helper.

---

## Foreign e Raylib

```odin
foreign import kernel32 "system:kernel32.lib"

foreign kernel32 {
    ExitProcess :: proc "stdcall" (exit_code: u32) ---   // --- = nessun corpo Odin
}
```

`vendor:` include già: raylib, SDL2/SDL3, OpenGL, wgpu, miniaudio, stb, Box2D…

```odin
package main

import rl "vendor:raylib"

SCREEN_WIDTH  :: 1280
SCREEN_HEIGHT :: 720

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Odin project")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        // input -> update -> render
        rl.BeginDrawing()
        rl.ClearBackground(rl.RAYWHITE)
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
```

Domande da farsi a ogni confine C: chi alloca/libera? calling convention?
layout compatibile? per quanto la libreria trattiene i puntatori?
→ [Guida §7](ODIN_GUIDA.md#7-architettura-del-mini-engine)

---

## Test

```odin
package game

import "core:testing"

@(test)
test_clamp :: proc(t: ^testing.T) {
    testing.expect_value(t, clamp(12, 0, 10), 10)
}
```

```sh
odin test .
odin test . -all-packages
```

Il runner monitora allocazioni e bad free per default.
Cosa testare in un gioco: → [Guida §8](ODIN_GUIDA.md#8-test-debug-e-profiling)

---

## Tracking allocator

Idioma canonico in `main`, attivo nelle build `-debug`:

```odin
import "core:fmt"
import "core:mem"

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
        defer {
            for _, entry in track.allocation_map {
                fmt.eprintfln("%v leaked %v bytes", entry.location, entry.size)
            }
            for entry in track.bad_free_array {
                fmt.eprintfln("%v bad free", entry.location)
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    run_game()
}
```

---

## Riferimenti

- [Overview ufficiale](https://odin-lang.org/docs/overview/) — il documento singolo più utile
- [Indice dei package](https://pkg.odin-lang.org/)
- [Repository Odin](https://github.com/odin-lang/Odin) — la sorgente di `core:` è documentazione
- [Karl Zylinski — Odin + Raylib](https://zylinski.se/) — tutorial e libro orientati a giochi in Odin
- [**ODIN_GUIDA.md**](ODIN_GUIDA.md) — il ragionamento dietro questa reference
