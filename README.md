# Odin PP — M9 / engine e minigiochi integrati

Vertical slice di un roguelike con deck building, griglia logica 2D, ambiente
realmente 3D a blocchi e personaggi sprite pixel art, scritto in Odin con Raylib.
L’integrazione dell’engine aggiunge un menu comune e sei prove con
gameplay diversi: platform 2D e 3D, arena a ondate, FPS, puzzle e ring 1v1.
La run attraversa sette livelli di una rotta
procedurale, fra combattimenti, ricompense e nodi speciali, fino al Demolitore.
Carte, spinte, esplosivi, status e reliquie condividono una simulazione
deterministica, separata dalle animazioni.
Il ring usa la simulazione continua `fight`; l’FPS unico è Cripta delle Rune.
I prototipi M9 restano laboratori tecnici espliciti da CLI, con collisioni e strumenti condivisi.
Il combattimento tattico della 0.4 conserva le proprie regole a griglia.

Questo README raccoglie la documentazione del progetto: uso della demo,
contratti dei sistemi, riferimenti per sviluppare e lavoro ancora pianificato.
Per i dettagli delle API, ogni sezione rimanda ai sorgenti pertinenti.

## Indice

- [Avvio](#avvio)
- [Engine e minigiochi](#engine-e-minigiochi)
- [Controlli e loop di gioco](#controlli-e-loop-di-gioco)
- [M8: versione 0.4](#m8-versione-04)
- [M9: fondazioni per le modalità libere](#m9-fondazioni-per-le-modalità-libere)
- [Modalità tattica M7](#modalità-tattica-m7)
- [Verifica e smoke test](#verifica-e-smoke-test)
- [Architettura e ownership](#architettura-e-ownership)
- [Azioni, impulsi, status e reazioni](#azioni-impulsi-status-e-reazioni)
- [Targeting e movimento](#targeting-e-movimento)
- [Oggetti, esplosivi e loot](#oggetti-esplosivi-e-loot)
- [Carte e ciclo del mazzo](#carte-e-ciclo-del-mazzo)
- [Spell e dadi](#spell-e-dadi)
- [Nemici e combattimento tattico](#nemici-e-combattimento-tattico)
- [Rotta e generazione delle stanze](#rotta-e-generazione-delle-stanze)
- [Ricompense, economia e nodi speciali](#ricompense-economia-e-nodi-speciali)
- [Reliquie](#reliquie)
- [Timeline e input](#timeline-e-input)
- [Sprite e animazioni personalizzate](#sprite-e-animazioni-personalizzate)
- [Telemetria e playtest](#telemetria-e-playtest)
- [Odin: appunti per lo sviluppo](#odin-appunti-per-lo-sviluppo)
- [Roadmap e manutenzione](#roadmap-e-manutenzione)

## Avvio

Serve Odin con i binding e le librerie native Raylib della distribuzione.
La toolchain usata nelle verifiche correnti è
`odin version dev-2026-10:84bc3fc21`; non è un vincolo imposto automaticamente.
Eseguire i comandi dalla radice della repo:

```sh
./run.sh
./run.sh --seed=0xC0FFEE --fast
```

Il launcher usa `odin run src -o:none`, passa gli argomenti al gioco e funziona
anche se invocato da un'altra directory. `ODIN` può indicare un compilatore
alternativo. Ricompila i sorgenti a ogni avvio, per eseguire sempre le modifiche
correnti. Il comando senza `-o:none` abilita invece l'ottimizzazione predefinita
(`minimal`), che su questo progetto può rendere molto lunga l'attesa **prima**
dell'apertura della finestra.

Comando equivalente, oppure build da riutilizzare senza ricompilare:

```sh
odin run src -o:none
odin build src -o:none -out:odin_pp
./odin_pp
```

Su Windows (PowerShell) gli equivalenti sono `.\run.ps1` e
`.\scripts\check.ps1` (`-Headless` salta le build finali); `odin run src -o:none`
funziona anche a mano. Windows riserva al thread principale 1 MiB di stack
contro gli 8 MiB di macOS: [windows_stack.odin](src/windows_stack.odin) porta la
riserva a 16 MiB dal sorgente, senza flag del linker sulla riga di comando.

Dopo modifiche ai sorgenti, ricompilare prima di riutilizzare `./odin_pp`.
Le build rapide mantengono assert e controlli di sicurezza; non riducono asset
o qualità grafica. `-o:none` permette build senza ottimizzazione. `--seed` accetta un `u64`
decimale o esadecimale con prefisso `0x`; seed e percorso scelto rendono la run
riproducibile per la versione corrente del generatore.

Senza argomenti si apre il **menu**: la run del roguelike, i minigiochi con i
record e le impostazioni (volumi, scuotimento, sensibilità del
mouse, FPS), salvate con i record in `odin_pp/profilo.json` nella cartella dati
dell'utente. Se il file è corrotto o appartiene a una versione futura, la sessione
usa valori predefiniti e disabilita le scritture per conservare il file originale.
Smoke, laboratori e report di playtest avviano la run direttamente, come prima.
Gli smoke e i laboratori non scrivono i profili.

### Prova meccaniche

Il pulsante **Prova meccaniche** del menu (o `--mechanics-lab`) apre una sandbox
per provare le meccaniche nuove, una alla volta. È un'arena grande 23x17 senza
ostacoli né nebbia, con il giocatore al centro. Il combattimento non finisce
mai: l'ultimo nemico ucciso non ripulisce la stanza, e ogni 4 secondi di gioco
arriva un nemico casuale (Chaser, Archer, Brute, Bomber o Custode) su una
casella libera ad almeno 4 celle dal giocatore, fino a 6 insieme; un'arena vuota
si riempie subito. Gli easter egg si riaprono ogni volta. Il mazzo contiene
**una copia di Movimento Ombra, una di ogni carta nuova della Fase 2** (Pozza di
Veleno, Incendio, Deflect, Feretro, Dado del Destino e Lama Velenosa), **una del
Lazzo e della Canna da Pesca e una del Pinball e di First Person Shooter**:
tutte in mano (energia 12) tranne la Canna, in attesa fra le esaurite perché non
si pesca mai in mano. Sono dieci carte, più di quante ne tenga mai la mano del
gioco: restano larghe come in una mano piena di otto e si sovrappongono da un
lato all'altro dello schermo, ognuna in vista quanto le serve per mostrare tutte
le sue parole, l'icona, i segni della rarità e il tasto, in qualunque ordine
stiano; quella sotto il mouse si alza intera sopra le altre, e `9` e `0` giocano
la nona e la decima (vedi [Movimento Ombra](#movimento-ombra),
[Pozza di Veleno e Incendio](#pozza-di-veleno-e-incendio),
[Deflect, Feretro, Dado del Destino e Lama Velenosa](#deflect-feretro-dado-del-destino-e-lama-velenosa),
[Lazzo](#lazzo), [Canna da Pesca](#canna-da-pesca), [Pinball](#pinball) e
[First Person Shooter](#first-person-shooter)). Niente ricompense, uscita o
profilo; `F5` ricomincia, `F10` torna al menu. Arena, mazzo e ritmo degli arrivi
sono in [mechanics_lab.odin](src/mechanics_lab.odin) e
[sandbox.odin](src/game/sandbox.odin): per provare una nuova meccanica basta
cambiare `MECHANICS_LAB_DECK`.

**Arena libera (`F7`).** L'arena non si libera mai da sola, quindi `F7` la
libera subito, come una stanza quando cade il suo ultimo nemico: tutti i nemici
cadono, il bottino a portata arriva al Viandante, il combattimento finisce e non
arriva più nessuno. Si apre lo slot della Canna da Pesca, con le pesche e senza
acqua di una stanza nuova; l'uscita resta chiusa (sul tavolo niente portale né
`USCITA`). Il cartello scrive
`ARENA LIBERA / PESCA n/m / F7 DA CAPO / F5 RICOMINCIA`: `F7` di nuovo ricomincia
la pesca da capo (senza acqua), `F5` riporta il combattimento.

Le novità nate qui ora valgono in tutto il gioco: le azioni che durano il loro
costo e la finestra che si accorcia ([Modalità tattica M7](#modalità-tattica-m7)),
i cartoncini vivi, il cerchio d'azione del Viandante, le intenzioni dei nemici
con sigilli e terreno, i segnalini di carta e la vita di ogni nemico sempre
visibile in un cuore di carta sopra la testa
([Il tavolo](#il-tavolo-cartoncini-vivi-cerchi-e-segnalini)). Anche
[Movimento Ombra](#movimento-ombra), la carta che si prova qui adesso, è nel
mazzo iniziale di ogni run tattica. Lo stesso vale per gli status a stack
Veleno, Bruciatura e Rallentamento ([Status](#status)), per i dadi delle carte
che salgono dal D4 al D20 con gli upgrade ([Spell e dadi](#spell-e-dadi)) e per
i colpi che si vedono sul tavolo, ognuno con la sua arma di carta
([Il tavolo](#il-tavolo-cartoncini-vivi-cerchi-e-segnalini)). Le carte nuove della
Fase 2 ([Pozza di Veleno e Incendio](#pozza-di-veleno-e-incendio) e
[Deflect, Feretro, Dado del Destino e Lama Velenosa](#deflect-feretro-dado-del-destino-e-lama-velenosa))
compaiono fra ricompense e negozio di ogni run tattica, come il [Lazzo](#lazzo),
la [Canna da Pesca](#canna-da-pesca), il [Pinball](#pinball) e
[First Person Shooter](#first-person-shooter).
La prova resta la sandbox in cui provare le prossime.

**Intenzioni dei nemici (`F6`).** Nel gioco i nemici mostrano cosa stanno per
fare con sigilli e terreno ([Il tavolo](#il-tavolo-cartoncini-vivi-cerchi-e-segnalini));
qui `F6` passa fra i quattro modi per confrontarli: `SIGILLI + TERRENO`,
`SIGILLI`, `TERRENO` e `ADESIVI`, cioè il tavolo di prima, con il piccolo
adesivo dell'intento accanto al cuore del nemico (dove prima c'era l'etichetta
scura). Il cartello mostra il modo attivo.

**Suoni (solo qui).** La prova ha i suoi effetti sonori: ogni azione di ogni
personaggio (passi, colpi, ferite, parate, caduta e i telegrafi come la MIRA
dell'arciere o la CARICA del bruto), ogni carta, i dispositivi, le bombe, gli
status, il battito del secondo, il colpo a tempo, la fine della finestra, lo
stordimento e l'avviso di difesa, sopra il fondo di una cripta in loop. Ogni
status ha la sua voce: il Veleno gorgoglia, la Bruciatura è la carta che prende
fuoco (uno sfregamento, la vampata, le braci che crepitano) e il Rallentamento
è lo scappamento del battito che ticchetta sempre più lento e più grave, con un
filo di sabbia di clessidra. Sono **tutti fatti da codice**, senza registrazioni
né librerie (quindi senza licenze):
[tools/audio](tools/audio/SOUND_SPEC.md) li sintetizza dalla materia
dell'azione (cuoio, ferro, legno, osso, pietra e la carta del cartoncino che
striscia sulla pietra), li mette tutti nella stessa sala di pietra e tiene
magie e segnali in Re frigio. Partono con il disegno che li mostra
([lab_sounds.odin](src/render/lab_sounds.odin)), così i passi cadono sui passi
e i colpi sull'impatto (un dardo che manca suona quando arriva a terra, e chi
lo schiva quando lo schiva), con piccole variazioni di altezza e volume a ogni
colpo, e un limitatore sull'uscita tiene puliti i momenti più fitti (un colpo,
una caduta e un'esplosione insieme); seguono il volume degli effetti e il muto
delle impostazioni. Nel gioco normale per ora non suonano, e così i film di
[Mostra effetto](#mostra-effetto), che si sentono solo qui. Per rifarli dopo
aver cambiato una ricetta (`tools/audio/sfx_<famiglia>.py`):

```bash
"C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe" tools/audio/build_sfx.py
```

Il comando riscrive `assets/audio/lab/*.ogg` (Ogg Vorbis a 192 kbit/s: un terzo
dei WAV, e raylib lo decodifica campione per campione; lo codifica il modulo
audio di Blender) e la tabella generata
[lab_sfx_data.odin](src/engine/audio/lab_sfx_data.odin); con
`--only <famiglia> --preview <cartella> --no-write` produce invece spettrogrammi,
misure e un ascolto di tutta la famiglia, senza toccare il gioco.

| Opzione | Uso |
|---|---|
| `--run` | salta il menu ed entra subito nella run |
| `--minigame=<id>` | apre un minigioco sopra il menu (`platform2d`, `platform3d`, `arena`, `fps`, `puzzle`, `ring`) |
| `--smoke-menu` | cattura `odin_pp_menu.png` dopo 30 frame ed esce |
| `--animation-speed=2` | velocità delle animazioni ordinarie, fra 0.25x e 4x; non accelera cast o dadi M8 |
| `--fast` | velocità 4x |
| `--mechanics-lab` | Prova meccaniche: arena aperta senza fine, mazzo delle carte in prova (Movimento Ombra, Pozza di Veleno, Incendio, Deflect, Feretro, Dado del Destino, Lama Velenosa, Lazzo, Pinball, First Person Shooter, Canna da Pesca), nemici che continuano ad arrivare; `F7` libera l'arena per la Canna da Pesca |
| `--spell-lab` | arena con Firebomb, Fate Strike, Chain Lightning, Sundering Blow e Guard |
| `--dice-lab` | arena con Fate Strike, Sundering Blow, Prismatic Barrage, Twin Venom e Guard |
| `--dice-set-lab` | tavolo 3D del set D4/D6/D8/D10/D%/D12/D20: selezione, lancio e rotazione con il mouse |
| `--engine-lab` / `--arena-lab` | arena libera con collisioni, dummy e strumenti M9 |
| `--ring-lab` | ring 1v1 di pratica con strumenti M9; non assegna sblocchi |
| `--fps-lab` | prova FPS con strumenti M9 e due livelli selezionabili |
| `--sprites=/percorso/sprites.json` | manifest grafico alternativo |
| `--debug-abilities` | abilita gli shortcut di debug `C` e `V` |
| `--playtest-report` | registra una sessione interattiva |
| `--playtest-output=/percorso/sessione.json` | attiva la telemetria e sceglie il percorso di base |

Nei laboratori spell e dice le carte sono già in mano, nell'ordine indicato; `F5` ricrea
l'arena con un nuovo seed. Restano attivi costi, pulse e risposta dei nemici.
Il tavolo `--dice-set-lab` è invece una galleria autonoma: non modifica la run,
il profilo o i risultati dei dadi del gameplay. I sette modelli sono disponibili
nel renderer; in gioco le carte con dadi lanciano dal D4 al D20 secondo il
livello di upgrade (il D% resta soltanto nel tavolo).
Usare i laboratori senza opzioni smoke o report di playtest. Gli smoke grafici
mantengono velocità 1x per rendere riproducibile la cattura.
I laboratori M9 richiedono gli asset tattici e non si combinano con `--classic`,
altri laboratori, smoke o report. `--m9` è un alias del tattico corrente;
non sostituisce il combattimento principale con il movimento libero.

## Engine e minigiochi

Il roguelike e i minigiochi girano sullo stesso engine, in
[src/engine](src/engine): il nucleo continuo M9 e tredici package di servizi, senza dipendenze dal gameplay,
ognuno con i propri test headless. Le parti di sola logica (casualità, tempo,
fisica, layout dell'interfaccia, sintesi audio, salvataggi) non chiamano Raylib.

| Package | Contenuto |
|---|---|
| [rng](src/engine/rng) | stream xorshift64* con derivazione splitmix per dominio, range senza bias, pesi, shuffle; lo usano anche mazzo, dadi ed economia del roguelike |
| [timing](src/engine/timing) | accumulatore a passo fisso con limite di recupero, timer e cooldown |
| [tween](src/engine/tween) | curve di easing, smoothing indipendente dal frame rate, tween tipizzati |
| [pool](src/engine/pool) | pool a capacità fissa con handle generazionali |
| [physics](src/engine/physics) | rettangoli, cerchi e raggi; tile map 2D con piattaforme attraversabili, raycast DDA e move-and-slide; controller platform (coyote time, jump buffer, salto variabile, doppio salto, wall jump, dash); mappe voxel con collisioni e raycast 3D e controller platform 3D |
| [input](src/engine/input) | azioni logiche su tastiera, mouse e gamepad con rimappatura; fronti pressed/released calcolati da campioni puri |
| [audio](src/engine/audio) | effetti procedurali in stile sfxr, musica chiptune generata in loop, codifica WAV; senza dispositivo audio ogni chiamata è nulla |
| [ui](src/engine/ui) | interfaccia immediata: pulsanti, interruttori, slider, tessere, pannelli, testo a capo; comandi di disegno registrati e resi in un punto, focus da tastiera e pad, layout a tagli di rettangolo, font pixel incorporato |
| [camera](src/engine/camera) | camera 2D con zona morta, limiti e scuotimento a "trauma"; camera in prima persona e orbitale in terza persona |
| [fx](src/engine/fx) | particelle a pool fisso 2D/3D, popup, flash e hit stop |
| [gfx](src/engine/gfx) | sprite pixel art scritti come righe di caratteri, billboard, shader con sole, luce puntiforme e nebbia, mesh di voxel con facce nascoste rimosse, fondali procedurali |
| [save](src/engine/save) | JSON versionato scritto in modo atomico, percorsi per utente |
| [host](src/engine/host) | finestra, ciclo dei frame, stack di scene, profilo con impostazioni e record, guscio dei minigiochi |

### Interfaccia e input condivisi

La palette semantica vive in `engine/ui.GOTHIC_PALETTE`: nero e ardesia per
le superfici, blu per interazione e focus, rosso per danni, oro per premi.
Il renderer del roguelike usa le stesse costanti; texture delle carte,
materiali 3D e ambienti mantengono le proprie variazioni artistiche.
`hud_panel`, `hud_meter`, `draw_text_fit` e `hud_columns` sono i componenti
comuni. Le prove del catalogo ordinano vita/risorse a sinistra, obiettivo al centro,
punti/progresso a destra. La run conserva pulse, carte e QTE nella propria
HUD, con gli stessi pannelli e colori.

Il menu dà priorità all’ascesa e presenta le prove in righe leggibili. Durante
Combat la barra degli oggetti mostra solo dispositivi o equipaggiamento
presenti; i controlli disabilitati visibili intercettano il mouse, quelli
nascosti non lasciano zone invisibili sulla board. Nel Loot attività e pratica
occupano un piccolo pannello in basso a destra; l’uscita resta libera al centro.
Disegno, hit test e occlusione del mouse usano lo stesso layout.

L’host concede input soltanto alla scena superiore e annulla clic e focus UI
al cambio scena. `input.Resume_Gate` è condiviso dagli adattatori delle prove, incluso il ring:
il primo campione dopo la pausa stabilisce lo stato dei tasti senza generare
nuove pressioni; il fuoco già tenuto resta bloccato fino al rilascio.
I singoli giochi possiedono ancora le code delle azioni da consegnare ai tick.
La run riceve tempo e puntatore da `host.Frame`; non tiene comandi in coda e,
quando perde l’input, pulisce selezioni, trascinamenti e il passo sul secondo
che aspetta il tasto della diagonale, preservando pulse, QTE e stato del mondo.

### Scene

Run e minigiochi del menu sono `host.Scene`: dati propri sull'heap e procedure `update`,
`draw` (canvas), `draw_window` (overlay in coordinate di finestra, come i dadi
3D), `after_present` (screenshot), `suspend` (cede l’input a una scena nuova),
`resume` (la scena sopra è stata chiusa,
con un eventuale `host.Result`) e `destroy`. Lo stack ha due regole: sotto una
scena **modal** non si aggiorna nulla, sotto una scena **opaque** non si
disegna nulla. `push`, `pop`, `replace` e `quit` sono comandi accodati e
applicati a fine frame, quindi nessuna scena viene distrutta mentre è in uso.
`suspend` viene chiamato solo per un push accettato, anche se l’overlay è
modale: i minigiochi entrano in pausa e rilasciano il cursore. Dopo la chiusura
dell’overlay richiedono una ripresa esplicita. I nomi in `resume` e
`Result.minigame` sono validi per il callback anche dopo `destroy` della scena
figlia; vanno copiati se si desidera conservarli oltre quel frame.
I widget di `ui` vanno chiamati in `update`, così stanno sopra al mondo di ogni
scena; il mondo si disegna in `draw`.

Il roguelike è la scena [roguelike_scene.odin](src/roguelike_scene.odin): lo
stato che prima viveva nelle variabili locali di `main` è in
`Roguelike_Session`, sull'heap. Il setup è diviso fra `roguelike_prepare`
(run, stanza e smoke headless, senza finestra) e `roguelike_attach` (risorse
GPU sulla finestra dell'host).

### Contratto dei minigiochi

Un minigioco è un package in [src/minigames](src/minigames) con due procedure:
`info() -> host.Minigame_Info` (id, titolo, genere, descrizione, comandi,
colore) e `create(host.Minigame_Config) -> host.Scene`. La configurazione porta
seed e il flag `challenge` per le sfide della run, che sono
più brevi e hanno un solo tentativo. Il gioco implementa `Minigame_Hooks`
(`reset`, `step`, `draw`, `score`, `destroy`, musica, cattura del mouse) e
`host.minigame_scene` aggiunge il guscio comune: scheda iniziale con i comandi,
pausa con `Esc` o quando la finestra perde il focus, risultati con stelle,
punteggio e record, riprova. La simulazione di ogni minigioco è pura, a passo
fisso e deterministica per seed e input; i test la guidano senza finestra.
Il catalogo per menu e sfide è in [minigame_registry.odin](src/minigame_registry.odin).

Tutte le prove usano un unico bilanciamento fisso, equivalente al precedente
livello Normale. Non esistono selettori di difficoltà nel menu o nella
configurazione; i vecchi flag `--easy` e `--hard` non sono più accettati.
Restano la progressione interna di livelli/ondate e la varietà data dal seed.
Le sfide della run mantengono la durata ridotta, senza modificatori legati
alla profondità o alle stanze Elite.

### I minigiochi

| Id | Titolo | Gioco | Comandi principali | Stelle |
|---|---|---|---|---|
| [platform2d](src/minigames/platform2d) | Torre di Cenere | platform a scorrimento: livelli composti per seed da 22 blocchi verificati da un solver che usa il controller vero; nemici da schiacciare, totem che sparano, blocchi che crollano, bracieri di checkpoint | `A`/`D`, `Spazio` (doppio salto, wall jump), `Shift` scatto, `S` scende | arrivo; 60% delle braci; 90% senza ferite |
| [platform3d](src/minigames/platform3d) | Guglie Sospese | platform 3D su isole di voxel con distanze tarate sul salto misurato; frammenti d'anima, portale, piattaforme mobili e friabili, spuntoni a tempo, sentinelle | `WASD`, `Spazio`, `Shift`, `Q`/`E` o tasto destro per la camera | portale; tutti i frammenti; senza vite perse |
| [arena](src/minigames/arena) | Arena delle Braci | twin-stick a ondate in arene simmetriche: cinque nemici con attacchi telegrafati e il Signore delle Braci, potenziamenti, combo fino a x8 | `WASD`, mouse per mirare, clic sinistro, `Spazio` scatto | vittoria; metà vita; combo obiettivo |
| [fps](src/minigames/fps) | Cripta delle Rune | prima persona in una cripta generata: tre nemici con IA su flow field, bastone runico a mana, rune che aprono il portale, minimappa | mouse, `WASD`, `Shift`, clic sinistro, `Tab` mappa | fuga; tempo sotto il par; vita e mira oltre il 50% |
| [puzzle](src/minigames/puzzle) | Sigilli della Cripta | Sokoban con ghiaccio e grate a piastre; 17 livelli risolti da un BFS che ne fissa il par; undo/redo e suggerimenti | frecce/`WASD`, `Z` annulla, `Y` ripete, `R` ricomincia, `H` aiuto | entro par; entro 1,5 par; risolto |
| [ring](src/ring_minigame.odin) | Il Ring delle Ombre | duello 3D continuo contro il campione, guardia, schivata, combo e presa in quattro pose; stessa scena dal menu e dalla run | `WASD`, `1` pugno, `2` pesante, `3` presa, `Spazio` schiva, `Shift` para; pad stick/X/Y/RB/A/LB | vittoria; salute residua almeno 3; almeno 6 |

Ogni pacchetto ha un bot deterministico (`create_autoplay` o `autoplay`) usato
dai test e per le catture, e test headless su determinismo, vincibilità,
sconfitta, validità della generazione su molti seed e soak con input casuali.
`--smoke-minigame=<id>` usa il bot, ignora input live e cattura
`odin_pp_<id>.png` dopo 180 frame di gioco.
Gli avvii diretti `--minigame` e `--smoke-minigame` rispettano esattamente
`--seed`; dal menu ogni nuova partita può usare un nuovo seed.
La cattura verifica avvio e rendering, mentre i bot dei test verificano partite
complete. `--minigame=fps` e il menu avviano la Cripta delle Rune con bastone
e mana. `--fps-lab` conserva soltanto il banco di prova M9 per
raycast/caricatore: non compare nel menu.

### Minigiochi nella run

I minigiochi non si aprono più alla fine della stanza: niente pulsanti nel Loot.
Nella run si sbloccano rispettando condizioni precise durante il combattimento,
e ognuno **una sola volta per piano** (`Floor_Secret` in
[tesla_ring.odin](src/game/tesla_ring.odin); per ora la run è un solo piano).
Dal menu restano tutti giocabili liberamente.

- **Il Ring delle Ombre**: quattro Tesla sugli angoli di un quadrato con
  l'interno di almeno 2x2 caselle (Tesla escluse). Se si attiva il quadrato
  mentre uno o più nemici sono nel campo, al posto della scarica parte il ring
  (vedi [sotto](#il-ring-delle-ombre-e-gli-sblocchi)).
- **6 RANCH 7**: appena il 6 e il 7 di denari sono insieme in mano, accanto al
  giocatore si apre una nuvoletta di pensiero a fumetto (circa un sesto dello
  schermo) mentre la board resta ferma. Le due carte volano dalla mano
  nell'insegna del ranch, a sinistra e a destra della scritta (6 RANCH 7), le
  porte si aprono ed escono il giocatore e un cowboy a cavallo. Vista dall'alto,
  due corsie divise da una linea nera, il terreno scorre: un countdown da 5
  scocca ogni secondo e a ogni scocco la moneta va a chi preme (`Spazio`,
  `Invio` o clic) più vicino all'istante giusto. Chi arriva a 3 monete vince.
  **Vittoria**: vita piena e +10 oro. **Sconfitta**: nessuna perdita. Le carte
  finiscono negli scarti. Logica in [western.odin](src/western/western.odin),
  disegno in [western_bubble.odin](src/render/western_bubble.odin).

Pausa, ologramma, cast, QTE e attività M9 impediscono di aprire una seconda
attività sovrapposta.

## Controlli e loop di gioco

Prima del primo combattimento si sceglie una reliquia fra tre offerte, oppure
si usa Skip. Ogni stanza parte con cinque carte e tre energia. I nemici
annunciano già il piano per la prossima risposta: schivare o spostare un
bersaglio può invalidarlo, senza permettere all'IA di cambiarlo all'ultimo momento.

Nel loop classico, un comando accettato durante Combat concede un **pulse**, cioè una risposta
nemica, se lo scontro continua. Vale per movimento, bump attack, attesa,
abilità, carta e Refocus; una carta con più effetti costa al massimo un pulse.
La modalità tattica M8, evoluzione di M7, consuma tempo dentro una finestra,
seguita da un secondo di recupero con movimento libero. Le carte spendono il
proprio tempo durante il cast, con mondo fermo; i dadi sospendono anche il timer. I QTE possono sospendere un attacco prima del
danno. I comandi rifiutati non aggiungono costi. Nessun comando resta in coda:
una pressione fatta mentre la propria azione è ancora in corso (la sua
animazione o, nel tattico, i suoi secondi) viene scartata, e agisce solo una
pressione fatta dopo. Il classico rigenera un'energia
per pulse; M7 ne rigenera una ogni tre secondi del mondo, fino al massimo di tre.

Alla morte dell'ultimo nemico la stanza passa a Loot. Ci si può muovere senza
pulse, raccogliere i drop rimasti ed entrare sull'uscita verde. Una stanza non
finale offre tre carte: scelta o Skip aprono la mappa. Un Elite offre prima una
reliquia. Shop, Rest, Event e Treasure hanno schermate dedicate; il boss porta
a Victory, la morte del player a Defeat.

| Contesto / input | Azione |
|---|---|
| hover su carta | mostra regole, costo e range |
| trascina carta sulla griglia | anteprima di area, percorso, landing e blocker; il rilascio prova la giocata |
| `1`–`8` in Combat | gioca una carta non spaziale o seleziona una carta spaziale (nella mano da dieci della Prova meccaniche anche `9` e `0`) |
| click su cella | conferma il bersaglio della carta selezionata |
| `Esc` / click destro | annulla selezione o drag |
| `WASD` | un passo per pressione; contro un nemico esegue un bump attack senza muovere il player |
| `Spazio` | attesa: un pulse classico, oppure costo di 1 secondo nel tattico |
| `F` / Refocus | riordina la mano e pesca il refill; un pulse classico oppure 2 secondi nel tattico |
| `C`, `V` con `--debug-abilities` | Thorn Coat e Afterimage |
| frecce / trascinamento rotella | muove la camera |
| rotella / `R` | zoom ancorato al cursore / inquadra il livello |
| `M` | mostra o nasconde la rotta nella stanza, a timeline idle |
| click / `1`–`3` in Reward, scelta reliquie o mappa | sceglie una delle opzioni |
| `S` / Skip | salta la ricompensa di carte o reliquie |
| click / `1`–`3` nello Shop | acquista una carta |
| click su carta posseduta | seleziona l'istanza da migliorare o rimuovere |
| `U`, `R` nello Shop | upgrade / rimozione della selezione |
| frecce nello Shop o al Rest | pagina del deck, otto carte per pagina |
| `Enter`, `Esc` / Continue nello Shop | esce; il pulsante Shop sulla mappa riapre lo stesso vendor |
| `1` in Rest, Event, Treasure | Recover, prima scelta Event o Claim |
| `2` in Rest o Event | upgrade della selezione o seconda scelta Event |
| `U` al Rest | upgrade della carta selezionata |
| clic su **MOSTRA EFFETTO** / `I` in Reward, Shop o Rest (solo tattico) | apre il film della carta ([Mostra effetto](#mostra-effetto)): sotto una carta offerta quella, al livello 0; nella riga dei comandi di Shop e Rest la carta posseduta scelta / la ricompensa o l'offerta sotto il mouse, altrimenti la carta scelta |
| `Esc`, clic destro o **CHIUDI** / `R` o **RICOMINCIA**, nella finestra Mostra effetto | la chiude, senza clic che arrivino alla run / fa ripartire il film dal primo fotogramma |
| `L` / Leave | risolve un nodo speciale senza ricompensa |
| `Enter` / Continue dopo il risultato | completa il nodo speciale e torna alla mappa |
| `Enter` / Restart in Defeat | avvia una nuova run |
| `F5` | nuova run o laboratorio, con seed diverso |
| `F8` | salva uno snapshot diagnostico locale `odin_pp_input_N.txt`, senza cambiare lo stato |
| `F1`, `F2`, `F3` | scaling fit con letterbox, integer, stretch |
| `F4` | cambia velocità delle animazioni ordinarie: 1x, 2x, 4x; cast e dadi M8 restano a 1x |
| `F11` | fullscreen borderless |
| `F9` | diagnostica dell'host: FPS, grafico dei frame, stack delle scene |
| `F10` | torna al menu (run avviata dal menu) |

Per spostare un barile serve **Shove in mano, un'energia e adiacenza
ortogonale**. Trascinare la carta sul corpo del barile oppure selezionarla e
cliccare: la spinta va di una cella lontano dal player. Camminargli contro in
Combat non lo spinge. Shove accende un barile spento anche se la spinta è
bloccata; l'esplosione arriva dopo altri due pulse classici o beat del mondo tattico.

## M8: versione 0.4

M8 introduce cast con controllo esplicito del tempo, carte-dispositivo,
equipaggiamento e il primo minigioco completo. `./run.sh` avvia questa versione;
`--m7` rimane un alias del tattico corrente e `--classic` conserva il loop
classico. Lo starter tattico include ora una Shock Floor e una Tesla Coil,
oltre alle carte già presenti: i nuovi dispositivi possono comparire anche
fra ricompense e offerte. Include anche il **6** e il **7 di denari**, carte con
la grafica della Scopa: costano 1, danno 6 e 7 oro e si esauriscono per il resto
del combattimento; non compaiono fra ricompense e offerte. Infine una copia di
**[Movimento Ombra](#movimento-ombra)**, che invece si trova anche fra
ricompense e offerte delle run tattiche.

### Tre regole del tempo

| Stato | Countdown del pulse | Nemici, bombe, status e dispositivi |
|---|---|---|
| Decisione, movimento, targeting, ologramma | scorre; le azioni non-carta aggiungono il proprio costo | avanzano sui beat del mondo |
| Cast di una carta da `Ns` | scorre per la durata effettiva del cast, senza doppio addebito | fermi, compresa la presentazione nemica già in corso |
| Dadi / cinematica, pausa, scheda personaggio o attività M9 | fermo | fermi |
| [Movimento Ombra](#movimento-ombra) | fermo; scorrono solo i 4 s dell'ombra | fermi, comprese le loro animazioni |
| Finestra [Mostra effetto](#mostra-effetto) aperta | fermo | fermi, con le loro animazioni: la run non riceve il fotogramma, che è tutto del film e della sua stanza di prova |

Il cast occupa i comandi del player per la durata indicata sulla carta. Un
lancio di dadi all'interno della carta è una pausa completa aggiuntiva: non
riduce il pulse e non fa scadere il cast. `F4` e `--fast` non abbreviano né il
cast né questa cinematica. Alla ripresa non si scaricano beat accumulati durante
la pausa. QTE e perdita del focus mantengono le rispettive pause già esistenti.
La fog senza memoria e l'ologramma che consuma tempo restano attivi.

La policy riutilizzabile `Live / Cast / Cinematic` è in
[cast_playback.odin](src/render/cast_playback.odin): nuovi tipi di ruota o reveal
potranno dichiararsi cinematici nello stesso punto. Attualmente sono integrati
i dadi dal D4 al D20; non è ancora presente una carta con ruota. La risoluzione logica
resta una sola transazione deterministica, seguita dalla presentazione; il
renderer non tira nuovamente i dadi e non riapplica effetti.

### Colpo a tempo

Ogni volta che il countdown del pulse scocca un secondo intero (per esempio da
4,35 a 4), un'azione fatta **entro 0,15 s** da quell'istante, prima o dopo, è
**critica**. Ogni scocco premia una sola azione; i secondi saltati dal costo di
un'azione non scoccano, e la finestra appena aperta non conta come scocco.
Lo scocco si giudica alla pressione: un passo premuto in tempo resta critico
anche se parte qualche fotogramma dopo, mentre aspetta (al massimo 0,06 s) il
secondo tasto della diagonale. Non c'è coda: premuto mentre l'azione precedente
è ancora in corso, il passo si perde. L'HUD mostra una spia che si accende
nella finestra; l'azione critica mostra **CRITICO!**. Un passo in linea retta
resta sempre di una casella e non consuma lo scocco: sul secondo, il critico
del movimento è solo il passo in diagonale.

| Azione sul secondo | Effetto critico |
|---|---|
| Due tasti insieme (`W`+`D`, `S`+`A`...) | passo in diagonale (solo sul secondo) |
| Attacco a urto | danno doppio |
| Carta: danni | x1,5, almeno +2 |
| Carta: scudo, cura, oro | x1,5, almeno +1 |
| Carta: altri status | +1 potenza e +1 durata (Veleno, Bruciatura, Rallentamento e le cariche del Viandante: +1 stack, non hanno durata; Lama Velenosa: il dado più uno) |
| Carta: pesca, energia, carte create, reazioni | +1 (anche il primo colpo del Lazzo e il valore del Pinball, quello da cui parte e a cui lo riportano i muri) |
| Carta-dispositivo | danno x1,5 (almeno +2); la Tesla nasce con vita doppia, la Shock Floor con un colpo in più (massimo 21: un 20 del D20 più uno) |
| First Person Shooter | +2 s dietro gli occhi |
| Movimento Ombra, Dado del Destino | nessun critico: giocate sul secondo lasciano lo scocco all'azione dopo |
| Canna da Pesca | mai critica: pesca a stanza liberata, senza finestra |
| Freccia di Feretro | mai critica: non prende lo scocco |

Le regole e i numeri sono in [tactical_beat.odin](src/game/tactical_beat.odin).

### Movimento Ombra

`Movimento Ombra` (rara, energia 3, **0 s** di finestra, senza potenziamenti né
exhaust) fa sprofondare il Viandante nella propria ombra per **4 secondi
reali**. Il mondo si ferma del tutto: nemici, intenti e loro tempi, micce,
dispositivi, impulsi, clock e battiti del mondo, finestra, stordimento e
recuperi, arrivi della Prova restano esattamente dov'erano (18 s prima, 18 s
dopo). I 4 secondi partono quando la giocata ha finito di mostrarsi: il
cartoncino sprofonda, poi la carta va negli scarti e se ne pesca un'altra
(circa 0,9 s in tutto); fino ad allora, come durante ogni propria azione, una
pressione si perde, e l'arco sulla pozza e la barra dell'HUD cominciano a
calare solo quando l'ombra si può muovere. Il
Viandante è intangibile, nessun danno lo raggiunge, e può solo **muovere
l'ombra**: niente carte, attacchi, schivate, attese, Refocus o dispositivi. Ogni
passo dell'ombra dura 0,4 s e parte dalla sua casella con le regole normali del
movimento (muri, oggetti e nemici bloccano, nessuno viene urtato); una pressione
durante il passo si perde. L'ombra ha i suoi battiti, a 1, 2 e 3 secondi del suo
orologio (entro 0,15 s): due tasti premuti su uno di questi fanno il passo in
diagonale (CRITICO!), come sul secondo del mondo. Allo scadere, appena l'ultimo
passo è arrivato, il Viandante risale dove si trova l'ombra con un
teletrasporto: di nuovo tangibile, trappole e fuoco della casella d'arrivo
mordono come a ogni atterraggio e il magnete raccoglie il bottino vicino; poi il
mondo riprende, e un colpo annunciato sulla casella lasciata va a vuoto. Giocata
sul secondo non consuma lo scocco (niente CRITICO né bonus); si può giocare
anche da storditi, e lo stordimento riprende con gli stessi secondi. Una copia è
nel mazzo iniziale di ogni run tattica ([tactical_setup.odin](src/tactical_setup.odin))
e la carta compare fra ricompense e negozio; le run classiche non la offrono e,
se l'hanno in mano, la rifiutano.

Sul tavolo il cartoncino del Viandante scende sotto il pavimento fino al
cappuccio, scuro, dentro una pozza d'inchiostro viola che scivola di casella in
casella; i colori del mondo si spengono, e i suoi cartoncini, sigilli, lampade e
dispositivi restano nella posa in cui si sono fermati; anche ciò che il mondo
stava mostrando sul Viandante (un `MANCATO`, una parata, le loro scintille)
resta dove lui è sprofondato e non segue la pozza. Il bordo della pozza
segna i secondi rimasti, un anello d'oro si stringe verso ogni battito e si
accende sopra di esso. L'HUD diventa viola: `OMBRA` con i secondi dell'ombra, la
loro barra e la spia dei suoi battiti; sotto, la finestra ferma (`FERMO 18.0s`);
una linea viola si consuma a ogni passo e la riga di stato dice
`MONDO FERMO / SOLO PASSI / DIAGONALE SUL BATTITO`. La mano scrive
`OMBRA / SOLO PASSI` e la schivata `OMBRA`. La carta mostra `0s` di tempo,
`OMBRA 4s / MONDO FERMO` e `INTANGIBILE / SOLO PASSI`. Per non confondersi con
l'ombra, lo status di Afterimage nell'HUD si chiama ora `SCIA`. Regole in
[tactical_shadow.odin](src/game/tactical_shadow.odin), quadro in
[shadow_step.odin](src/render/shadow_step.odin).

Nella Prova meccaniche anche l'ombra si sente
([lab_sounds.odin](src/render/lab_sounds.odin)): la carta sfila dalla mano e
una campana si ferma insieme al tempo, il Viandante sprofonda in un'onda
d'inchiostro, ogni passo dell'ombra è un fruscio morbido (mai gli stivali), la
diagonale sul battito suona il CRITICO e la risalita finisce con il cartoncino
posato sulla pietra. Lo smoke `--smoke-mechanics-lab` la gioca dalla mano e la
filma ([Verifica e smoke test](#verifica-e-smoke-test)).

### Pozza di Veleno e Incendio

Le prime carte della Fase 2 vivono sul pavimento della stanza tattica. Pozze e
fuochi non sono oggetti della griglia: non occupano uno dei 32 posti, non
bloccano niente, le bombe ci cadono sopra e i dispositivi ci si posano, e non
toccano mai il Viandante. Entrambe le carte puntano una **cella libera** a
distanza Chebyshev 1–3 con linea di vista: calpestabile, senza copertura, senza
nemici, oggetti di alcun tipo o il giocatore stesso (trappole e uscita vanno
bene). Restano fino alla fine della stanza, anche durante il bottino (una stanza
nuova parte pulita); nelle run classiche non compaiono e, se sono in mano, vengono
rifiutate (`Invalid_Phase`). Regole in [ground.odin](src/game/ground.odin).

`Pozza di Veleno` (comune, energia 1, **1 s** di finestra) versa una pozza. Un
**nemico** che entra in una sua cella, con qualunque movimento (un passo, ogni
cella di una carica, una spinta o un trascinamento, l'atterraggio di un
teletrasporto), prende **2 Veleno** (+1 per upgrade, +1 se giocata sul secondo),
e altrettanto per ogni cella di pozza in cui passa, anche da una cella di pozza
all'altra; uscirne non dà niente. Il Veleno arriva dal System, come quello dei
dispositivi: la reliquia Venom Vial non lo aumenta e le reazioni del Viandante
non lo vedono. Pozze vicine sono un'unica area e si disegnano come una sola chiazza.
Dopo ogni pozza il pavimento libero (calpestabile, senza coperture né oggetti che
bloccano, non ancora pozza) si divide in aree a 4 vicini: la più grande è
l'esterno, e ogni altra area che tocca una pozza è chiusa e **si riempie subito**
con il veleno della carta che l'ha chiusa; chi ci sta dentro prende quel Veleno.
Gli attori non chiudono mai un'area, muri, coperture e oggetti solidi sì. Una
tasca chiusa solo da muri o oggetti, senza pozze intorno, resta asciutta; due
aree a pari merito come più grandi restano entrambe esterne. Un nemico che entra
nella pozza con un proprio passo prende il Veleno subito e lo sente alla fine di
quella stessa azione (2 danni, poi ne resta 1).

`Incendio` (non comune, energia 2, **2 s** di finestra) accende un fuoco sulla
cella: un effetto del pavimento, non l'oggetto Fire (non accende barili e non
brucia il Viandante). Un **nemico** che entra in una cella in fiamme prende **1
Bruciatura** (+1 per upgrade, +1 se giocata sul secondo) a ogni ingresso. A ogni
nuova finestra, nello stesso momento in cui morde la Bruciatura, ogni fuoco cresce
a croce: bracci lunghi 1, poi 2, 3 e 4 caselle; un braccio si ferma per sempre al
primo muro, copertura o oggetto solido (anche se poi l'ostacolo si sposta); alla
quinta finestra, quando arriverebbe a 5, il fuoco si spegne. Un nemico sulla
casella che prende fuoco riceve la Bruciatura del fuoco più forte, una volta
sola anche se lo raggiungono due fuochi, e la sente dalla finestra dopo: prima
morde, poi il fuoco cresce, come per chi ci entra camminando. Al massimo 32 fuochi
per stanza; un fuoco può ardere sopra una pozza o un altro fuoco, una pozza non
si versa su un'altra pozza. I nemici non evitano pozze e fiamme: le attraversano
come il resto del pavimento.

Sul tavolo ([ground_fx.odin](src/render/ground_fx.odin)) pozze e bruciature sono
un decalco di carta disteso sul pavimento, in pixel art: il liquido verde (bruno
e braci sotto il fuoco) con il margine di carta bianca, la linea d'inchiostro e
il taglio della carta verso la camera, come cartoncini e oggetti di carta, e la
luce sul lato lontano del liquido. Quando la camera gira verso un altro lato del
tavolo, taglio e luce la seguono (alla diagonale più vicina) e il decalco si
ricuoce a poco a poco; una camera ferma vicino a un asse non lo ricuoce avanti e
indietro. Le
celle vicine si fondono in una chiazza dai bordi arrotondati, quelle che si
toccano solo in diagonale restano separate. La pozza compare quando la fiala di
carta lanciata dal Viandante atterra, con uno schizzo di gocce, e un'area chiusa
si allaga dalla cella versata verso l'esterno. Il fuoco arriva come una brace;
a ogni finestra le fiamme di carta spuntano sulle caselle nuove (più alte al
centro, più basse nell'ultima finestra) e alla fine si abbassano e spariscono con
la loro bruciatura. Un nemico che mette piede in una pozza schizza gocce verdi,
in una fiamma tira faville. Mirando, l'anteprima della carta colora di verde anche
le celle che la pozza riempirebbe, e di brace la croce intera che il fuoco
raggiungerebbe. Sul tavolo piatto (`--flat`) la pozza è un rombo verde con carta e
inchiostro sui lati asciutti, il fuoco un rombo di brace con la sua fiammella.
Le carte scrivono `2 VELENO A CELLA` / `SOLO NEMICI / STANZA` e
`1 BRUCIATURA A CELLA` / `CROCE: +1 A FINESTRA` (con sette carte in mano o più,
sulle carte strette, `Pozza` / `2 VELENO` / `A OGNI CELLA` e `1 BRUCIATURA` /
`CRESCE A CROCE`); l'ispettore aggiunge
`AREE CHIUSE: SI RIEMPIONO` / `OGNI CELLA ENTRATA AVVELENA` e
`CRESCE A OGNI NUOVA FINESTRA` / `SI SPEGNE ALLA QUINTA`. Le icone, nella quinta
riga dell'atlante ([build_card_icons.py](tools/art/build_card_icons.py)), sono una
fiala rovesciata nella sua pozza e un fuoco su una croce bruciata, con una
fiamma in fondo a ogni braccio.

Nella Prova meccaniche ognuna ha il suo suono: la Pozza è una fiala stappata, il
veleno che gorgoglia fuori e lo schizzo sulla pietra; l'Incendio un acciarino
battuto due volte, la vampata e il crepitio che si allarga. Una pozza in cui
entra un nemico schizza (`world_pool_splash`); un fuoco i cui bracci si allungano
a una nuova finestra rugge (`world_fire_spread`, una volta: un fuoco appena acceso
suona con la sua carta) e quello che alla quinta si spegne sfrigola via in un filo
di fumo con un'ultima brace (`world_fire_out`); un nemico che entra nel fuoco lo
fa divampare (`world_fire`). Lo smoke `--smoke-mechanics-lab` le gioca dalla
mano, le filma ([Verifica e smoke test](#verifica-e-smoke-test)) e ne controlla
le regole. L'anello chiuso dall'ultima pozza fa otto celle da 2 Veleno, e il
chaser rimasto dentro prende i suoi 2 una volta sola. Il chaser che attraversa
due pozze prende 2 Veleno a ogni cella e ogni suo passo morde i suoi stack: arriva
accanto al Viandante con 33 vita su 40 e 1 Veleno. Il Viandante entra in una
pozza sua senza prendere niente e senza schizzi. Il fuoco allunga i quattro
bracci di una casella a ogni finestra; prende il bruto alla seconda con 1
Bruciatura, che non cala mai e morde dalla terza (dopo la seconda, la terza, la
quarta e la quinta finestra il bruto ha 60, 59, 58 e 57 di vita); brucia la
casella del Viandante senza segnarlo; senza muri sulla sua strada deve ruggire
quattro volte e spegnersi una.

### Deflect, Feretro, Dado del Destino e Lama Velenosa

Le altre quattro carte della Fase 2 caricano il Viandante di **cariche**: status
a stack che porta solo lui (un nemico non ne riceve mai) e che si spendono una
alla volta con l'uso, fino all'ultima o alla fine della stanza (una stanza nuova
parte senza). Si giocano su di sé, con il loro tasto (`1`–`8`) o con un secondo
clic sulla carta. Tutte e quattro prendono **1 s** di finestra e sono solo tattiche:
compaiono fra ricompense e negozio delle run tattiche, le run classiche non le
offrono e, se le hanno in mano, le rifiutano (`Invalid_Phase`). Nell'HUD vengono
prima Veleno e Bruciatura del Viandante, che lo mordono (con tre o quattro cariche
non finiscono mai nel `+n`), poi le cariche: `RIFLESSO n`, `FRECCE n`,
`DESTINO n d8` (con il dado che tireranno gli urti caricati: quello dell'ultimo
Dado del Destino giocato, che compare con le sue cariche; un d4 se nella stanza
non ne è stato giocato nessuno), `LAMA n` (con poco spazio `RIF`, `FRE`,
`DES 3 d8`, `LAM`), poi gli altri status. Una carica si vede spesa quando il suo colpo arriva (la lanterna cala, la
freccia colpisce, il colpo rimandato raggiunge il Viandante), non quando parte;
l'ultima carica spesa fa sparire il suo chip. Un colpo, un urto o una freccia spendono le
loro cariche solo se vengono accettati. Ogni status ha ora un posto per tipo
(`MAX_STATUSES_PER_ENTITY = len(Status_Kind)`): il Viandante può portarli tutti
insieme, tranne il Rallentamento. Regole in
[player_charges.odin](src/game/player_charges.odin).

`Deflect` (non comune, energia 1, senza potenziamenti) dà una carica di
**RIFLESSO**; ogni giocata ne aggiunge una (giocata sul secondo, due). Il
prossimo colpo nemico che colpirebbe il Viandante (un attacco in mischia, un
dardo, il colpo di una carica) torna indietro: lui non subisce niente, né danno
né spinta, il suo Shield resta intatto, e l'attaccante prende il danno che
avrebbe preso lui (dopo la sua difesa, almeno 1); si spende una carica e per
quel colpo non si apre la scelta di difesa. Bombe, esplosioni, trappole,
pericoli, Veleno e Bruciatura non sono colpi e non la toccano; nell'ombra di
Movimento Ombra nessun colpo lo raggiunge e la carica resta. Sul tavolo il
dardo arriva al cartoncino del Viandante, che para, gira e torna nel
balestriere che l'ha tirato (è lo stesso dardo, mai un secondo); un fendente o
una carica vengono parati e il Viandante risponde con un colpo della sua
lanterna (o dell'arma M8 che ha in mano). `RIFLESSO` compare sopra di lui quando
il colpo torna indietro, una volta per colpo; se l'attaccante ha uno Scudo, sopra
l'attaccante si legge anche `PARATA n`, e un dardo rimandato che lo Scudo ferma
tutto rimbalza via invece di conficcarsi. Il chip `RIFLESSO` resta nell'HUD, al
suo posto, finché il colpo non raggiunge il Viandante.

`Feretro` (non comune, energia 2) dà **3 frecce** (+1 per upgrade, +1 sul
secondo); le giocate si sommano. Tenendo premuto `Ctrl` il tavolo segna con un
anello d'oro ai piedi i nemici che le frecce raggiungono: visibili e sulla
linea di tiro, con la LoS dei tiri del gioco (muri, ostacoli e oggetti opachi
la fermano, come la diagonale fra due blocchi; gli altri combattenti no; una
traccia di 12 celle al massimo);
quello sotto il mouse si accende, con la linea che la freccia farebbe. Un clic
sinistro su uno di loro scocca una freccia: è un'azione del Viandante come un
attacco a urto (1 s di finestra, il suo Veleno morde, si gira verso il
bersaglio), senza coda (premuta durante la propria azione si perde) e mai
critica. Vola come un dardo di carta e fa 1 danno più uno status scelto dai dadi
del giocatore: Veleno 2, Bruciatura 1 o Rallentamento 1. Lo status compare sul
nemico quando la freccia arriva: finché vola, quello che segue il tiro (lo
status, la caduta del nemico, la freccia spesa) aspetta, mentre il mondo e il
tempo della finestra vanno avanti. Con `Ctrl` premuto, un
clic che non cade su un nemico raggiungibile non fa niente (non prende né gioca
carte); sulla mano il clic resta della mano. La riga della mano scrive
`CTRL+CLIC SU UN NEMICO: FRECCIA (n)` e, con `Ctrl` premuto,
`CLIC SU UN NEMICO EVIDENZIATO: FRECCIA`.

`Dado del Destino` (rara, energia 2, carta con dadi: d4 al livello 0, poi la
scala fino al d20) carica i prossimi **3 attacchi a urto** (`DESTINO 3 d4`: il
chip dice anche il dado che tireranno): una
nuova giocata li riporta a 3, mai oltre, e il dado è quello dell'ultima carta
giocata. Giocata sul secondo non consuma lo scocco, come Movimento Ombra: non ha
una versione critica. A ogni urto caricato, dritto o in diagonale, il dado si
tira al colpo e decide: **1** Veleno, **2** Bruciatura, **3** Rallentamento, con
tanti stack quanto il risultato; **4** ruba vita (il Viandante guarisce del
danno inflitto, niente a vita piena); **5** critico (danno doppio; un urto già
critico sul secondo resta doppio, non quadruplo); **6 o più** letale: il nemico
cade, scudo compreso. Il boss (il Demolitore) e il miniboss (il Custode) non
cadono mai così: per loro è un critico. Con il d4 del livello 0 escono solo le
prime quattro facce. Sul tavolo, appena il colpo arriva, dal lato sinistro del
cartoncino colpito esce un cartellino di carta con il contorno in pixel del dado
(il triangolo del d4, il quadrato del d6, il rombo del d8, l'aquilone del d10, il
pentagono del d12, l'esagono del d20) e la faccia uscita nel colore di ciò che
fa. Si ferma accanto al cuore del nemico, mai sopra, nemmeno mentre spunta: da
un cartoncino stretto, come quello del Custode, esce più in là. Sopra il nemico
si legge `VELENO n`, `BRUCIATURA n`, `RALLENTAMENTO n`, `RUBA VITA +n`, `CRITICO`
o `LETALE`; sul tavolo piatto l'etichetta dice anche il dado
(`d8 4 / RUBA VITA +2`). Il critico fatto dal dado lo dice solo il dado, quando
compare: l'urto non lo annuncia prima. Un urto critico sul secondo dice `CRITICO`
da sé, se il dado non lo dice già. Due urti di fila sullo stesso nemico con la
stessa faccia mostrano ciascuno il suo dado e il suo suono.

`Lama Velenosa` (comune, energia 1, carta con dadi) tira il suo dado quando la
si gioca, come ogni carta con dadi (il lancio si vede a tutto schermo): il
risultato è il numero di **attacchi a urto avvelenati** (`LAMA n`; le giocate si
sommano, sul secondo uno in più). Ogni urto caricato lascia 2 Veleno; Lama e
Destino possono caricare lo stesso urto.

Le carte scrivono `+1 RIFLESSO` / `RIMANDA UN COLPO`, `3 FRECCE / CTRL+CLIC` /
`1 DANNO + 1 STATUS`, `1d4 SU 3 COLPI` / `UN TIRO A OGNI COLPO` e
`1d4 COLPI AVVELENATI` / `2 VELENO A COLPO` (con sette carte in mano o più
`+1 RIFLESSO` / `IL COLPO TORNA`, `3 FRECCE` / `CTRL+CLIC`, `Dado` /
`1d4 A COLPO` / `PER 3 COLPI` e `Lama` / `1d4 COLPI` / `2 VELENO L'UNO`);
l'ispettore aggiunge
`IL NEMICO PRENDE IL COLPO` / `NO BOMBE, TRAPPOLE, STATUS`,
`+ VEL 2 O BRU 1 O RAL 1` / `LINEA DI TIRO / 1s L'UNA`,
`1 VEL 2 BRU 3 RAL 4 VITA` / `5 CRITICO / 6+ LETALE` e
`IL DADO DECIDE I COLPI` / `LE CARICHE SI SOMMANO`. Per non confonderla con
Deflect, la difesa di Thorn Coat contro i dardi si legge ora
`ABILITA DEVIAZIONE` e `QTE: DEVIAZIONE (FRECCE)`, come il tasto `L`. Le icone,
nella quinta e nella sesta riga dell'atlante
([build_card_icons.py](tools/art/build_card_icons.py)), sono uno scudo tondo
d'acciaio da cui un dardo rimbalza via, una bara con la croce d'oro e tre frecce
che spuntano dalla testa, un d20 d'osso con il 20 in un anello viola e un pugnale
dall'elsa d'oro che gocciola veleno.

Nella Prova meccaniche ognuna ha il suo suono: lo scudo alzato e il colpo che
rimbalza via, il coperchio di una bara che cigola e tre frecce estratte, un dado
d'osso sul legno e una campana bassa del destino, un pugnale sfilato e una goccia
di veleno che sfrigola; ogni carica ha il suo suono quando arriva, il colpo
rimandato squilla quando raggiunge il Viandante (`pilgrim_deflect`), la freccia
ha la sua corda (`pilgrim_shoot`) e il dado del Destino rimbalza sul nemico
colpito (`ui_fate_die`). Lo smoke `--smoke-mechanics-lab` le gioca dalla mano, le
filma ([Verifica e smoke test](#verifica-e-smoke-test)) e ne controlla le regole.
Deflect rimanda un dardo, un fendente e una carica: per nessuno dei tre si apre
la scelta di difesa, anche se la schivata è pronta; il Viandante non perde vita
né casella, l'attaccante prende i 3 del colpo e la carica si spende. Il dardo è
uno solo, che va e torna; fendente e carica hanno la risposta della lanterna.
Feretro dà 3 frecce. Con `Ctrl` le frecce raggiungono il nemico sulla linea di
tiro, che il tavolo segna, e non quello dietro un blocco di copertura: un clic su
quest'ultimo non scocca niente. La freccia è un'azione da 1 s e lascia 1 danno e
uno solo fra Veleno 2, Bruciatura 1 e Rallentamento 1. Il Dado del Destino carica
3 urti con il d4 del livello 0; quando il d4 fa 2, l'urto lascia 2 danni e
Bruciatura 2. Giocato di nuovo, riporta gli urti a 3 e non oltre. Un 16 del d20
fa cadere il nemico, ma sul Custode è solo un critico (4 danni). Lama Velenosa
tira 3 e il suo urto lascia 2 danni e Veleno 2, con 2 cariche rimaste.

### Lazzo

`Lazzo` (rara, energia 2, **2 s** di finestra, solo tattica: compare fra
ricompense e negozio delle run tattiche, le run classiche non lo offrono e, se
lo hanno in mano, lo rifiutano) prende al lazo un nemico e lo fa girare intorno
al Viandante finché non muore. Regole in [lasso.odin](src/game/lasso.odin),
tavolo in [lasso.odin](src/render/lasso.odin).

**Il lancio.** Il bersaglio è un nemico entro 4 celle (Chebyshev), visibile e
in linea di vista. Il boss (il Demolitore) e il miniboss (il Custode) sono
troppo pesanti: la carta li rifiuta e la mano scrive `TROPPO PESANTE PER IL
LAZZO`. Il lancio è il cast della carta: per i suoi 2 s il mondo è fermo, come
per ogni carta. Il nemico gira su un vero cerchio intorno al centro della
casella del Viandante, e l'**anello** di raggio r sono tutte le caselle che quel
cerchio attraversa. Il **raggio** del giro, scelto prima di girare, è il più
grande fra 4 e 1 il cui anello non ha caselle solide (muri, fuori dalla stanza,
coperture, oggetti che bloccano il passo): un muro sulla quarta cella in linea
retta dà raggio 3, mentre una copertura più vicina, dentro l'anello di 4, non lo
accorcia (il nemico in volo ci passa sopra). Se anche l'anello di 1 ha una
casella solida (il Viandante accanto a un muro, che taglia tutti gli anelli) il
raggio è 1 e il nemico sbatte (vedi sotto). Il nemico viene tirato sulla casella
dell'anello dalla sua parte (se è solida, sulla libera più vicina lungo
l'anello; a pari distanza, nel verso del giro), perde il suo intento e il giro
parte da lì, in senso antiorario sul tavolo.

**Il giro.** Il primo giro dura 0,9 s, ogni giro dopo dura il 12% in meno di
quello prima (0,88 volte), fino a 8 giri al secondo (dal diciassettesimo): un
nemico da 60 di vita, da solo e senza colpi, cade dopo 60 giri, in 12,03 s, e i
colpi lo accorciano molto (`LASSO_FIRST_TURN_SECONDS`, `LASSO_TURN_SPEEDUP` e
`LASSO_FASTEST_TURN_SECONDS` in [lasso.odin](src/game/lasso.odin)). Il moto è
continuo e si risolve a passi esatti, casella per casella, sul tempo del mondo:
un fotogramma lungo non salta niente. Ogni volta che il nemico in volo entra in
una casella dell'anello occupata da un altro nemico è il **colpo n** (1, poi
2, 3...): tutti e due prendono n danni dal Viandante e il colpito viene spinto
di n celle via dal Viandante (nella più vicina delle otto direzioni, al massimo
12), con le regole della spinta: si ferma prima di un muro o di un altro corpo,
e le caselle in cui entra (pozze, fuochi, scosse, pericoli) fanno il loro
effetto. Se la casella dopo è solida (con raggio 1, o un oggetto messo
sull'anello durante il giro) è uno **schianto**: il colpo n lo prende solo il
nemico in volo, che rimbalza e torna indietro nell'altro verso. Ogni giro
intero percorso (360°, in un verso o nell'altro) gli costa **1 vita**. Il
giro finisce solo con la sua morte, e il suo loot cade dove muore.

**Il perno.** Il mondo continua: i nemici agiscono e la finestra scorre. Il
Viandante fa da perno: niente passi, urti, carte o frecce (premuti si perdono,
non restano in coda); i colpi nemici, la scelta di difesa, i QTE e Deflect
valgono come sempre. Ogni schivata o spostamento del Viandante, una spinta
compresa, **lascia andare** la corda: il nemico atterra sotto di sé o, se la
casella è occupata, sulla libera più vicina (entrandoci), e riparte subito con
un intento nuovo, senza stordimento (il tempo in volo chiude anche un recupero
in cui era; se la corda si molla nel mezzo di un battito, per una spinta o per
la schivata della scelta di difesa, l'intento arriva alla fine di quel battito,
con quelli degli altri). La mano lo ricorda quando si può: `LAZZO / SHIFT+WASD:
LO MOLLI`, e con la scelta di difesa aperta `LAZZO / E, POI WASD: LO MOLLI` (o
`LAZZO / DIFESA`, se la scelta non offre la schivata); a finestra scaduta, da
stordito o con la schivata in ricarica dice invece `LAZZO / IN RECUPERO`,
`LAZZO / STORDITO` o `LAZZO / SCHIVA FRA n`. In volo il nemico non agisce (il
suo Veleno quindi non morde), non entra in pozze, fuochi o scosse e nessuno lo
prende di mira; la sua Bruciatura continua a mordere.

**Upgrade e secondo.** Ogni upgrade dà +1 al primo colpo, fino al livello 5
(`PRIMO COLPO 1 -> 2`); giocato sul secondo, il primo colpo ha +1. La vita
persa a ogni giro resta 1.

**Sul tavolo.** La corda è una striscia di carta in pixel art: due trefoli di
canapa intrecciati fra due linee d'inchiostro, dentro il margine bianco. Durante
il lancio il Viandante si alza nella posa del suo cast, il braccio in su (mai
il salto con la lanterna e la capriola di un colpo), e il cappio aperto vola
dalla sua mano sopra il nemico, gli cade intorno alla vita e si stringe con una
torsione; il cartoncino si solleva e viene tirato su una curva alta fino
all'anello. Poi vola intorno al Viandante, sollevato dal pavimento, dove la
stanza dice che è, con la corda che resta indietro rispetto al giro e si
affloscia quando è lento; sul pavimento un anello di carta tratteggiato mostra
il raggio (senza le caselle solide, con tacche rosse dove sbatterà). Il
Viandante canalizza e si gira a seguirlo finché il giro non supera i 3 giri al
secondo. Ogni colpo fa una stella di carta rossa fra i due cartoncini, `COLPO n`
sopra il colpito e i segnalini di danno, e il colpito scivola via; uno schianto
fa una stella grigia e sbuffi di polvere di pietra al muro (pezzi di carta in
pixel art di [build_attack_props.py](tools/art/build_attack_props.py), come la
stella), con `SCHIANTO n`; a ogni giro intero un piccolo `-1` resta dove il
nemico era. Quando la corda lo lascia cade molle e il
cartoncino torna a terra con `MOLLATO` sopra, mentre il tavolo mostra quello che
ha mosso il Viandante (la schivata subito, una spinta quando il colpo del bruto
arriva); fino ad allora resta appeso alla corda tesa. Con un anello largo la
telecamera si allontana un poco e si accosta al Viandante, perché l'anello
intero si veda fra l'HUD e la mano, poi torna dov'era. L'HUD scrive `LAZZO` /
`GIRO n` e `LAZZO: COLPI n / PROSSIMO n / SCHIVA: LO MOLLI` (o, quando una
schivata non si può fare, `IN RECUPERO`, `STORDITO` o `SCHIVA FRA n` in fondo);
mentre gira, come nell'ombra, il riquadro tiene a destra solo `NEMICI n`, perché
le carte non si giocano e la riga ci stia intera anche con la finestra che si
accorcia. Sul tavolo piatto (`--flat`) l'anello è tratteggiato e la corda
dritta.

**Il mirino.** Con la carta in mano, i nemici che può prendere hanno un mirino
color canapa, il boss e il miniboss in portata un mirino rosso e
`TROPPO PESANTE` sotto i piedi (sopra gli adesivi degli intenti degli altri
nemici, e le altre scritte del tavolo lo evitano; se lì c'è già il cuore di un
vicino, scende di una riga o si sposta di lato, senza coprirlo); l'anello che
farebbe si vede tratteggiato, con le sue caselle (rosse con una croce dove
sbatterà, arancio dove colpirà un nemico) e, per il nemico sotto il mouse, la
casella da cui partirà in verde e una freccia nel verso del giro.

La carta scrive `COLPI 1, 2, 3...` / `-1 VITA A OGNI GIRO` (con sette carte in
mano o più `COLPI 1, 2...` / `-1 VITA A GIRO`); l'ispettore aggiunge
`BOSS E MINIBOSS: TROPPO PESANTI` / `SCHIVA O SPINTA: LO MOLLI`. L'icona, nella
cella 23 dell'atlante (l'ultima della sesta riga,
[build_card_icons.py](tools/art/build_card_icons.py)), è un cappio di canapa
intrecciata, aperto, con la corda che scende dal nodo a un rotolo e a un capo
sfilacciato. Nella Prova meccaniche ha i suoi suoni, fatti da codice come gli
altri ([SOUND_SPEC.md](tools/audio/SOUND_SPEC.md)): la carta (il rotolo di canapa
sciolto dalla spalla e il cappio fatto girare una volta sopra la testa), il
lancio (il cappio lasciato andare in un fruscio pieno, la corda che scorre nel
guanto e il fischio del cappio che si allontana), la stretta quando il cappio
arriva al nemico (la corda che scorre nel nodo, il cigolio della canapa, la carta
stretta e lo strattone quando il cartoncino si alza), un fruscio a ogni giro che
sale di tono man mano che accelera (fino a otto al secondo), il colpo (due
cartoncini sbattuti insieme), lo schianto sul muro (pietra, sassolini, polvere)
e la corda mollata (la canapa che si allenta e il cartoncino che ricade).

Lo smoke `--smoke-mechanics-lab` lo gioca dalla mano, lo filma
([Verifica e smoke test](#verifica-e-smoke-test)) e ne controlla le regole. A
quattro celle dal muro ovest il raggio è 3, dove una cella più in là sarebbe 4:
il muro sta sulla quarta cella. Il mirino segna i nemici che può prendere e
l'anello, con i tre nemici fermi che ci stanno sopra; sul Custode scrive
`TROPPO PESANTE` e né la regola né la carta lasciata su di lui lo prendono.
Lanciato su un nemico a quattro celle, che viene tirato dentro sull'anello, lo
fa girare mentre il mondo va avanti: colpo 1 sul nemico fermo a nord, spinto di una
cella, colpo 2 su quello a sud, spinto di due, colpo 3 su quello a nord-est,
spinto di tre in diagonale, ognuno ferito del numero del suo colpo e il nemico in
volo con lui; a ogni fotogramma la vita del nemico in volo è quella di partenza
meno i colpi e meno un punto per ogni giro intero, e niente altro. Intanto un
balestriere libero, messo giù dopo le immagini del mirino, prende la mira e tira
al perno: si apre la scelta di difesa, che nessuno sceglie, il colpo arriva e la
corda tiene. Il nemico in volo cade al dodicesimo giro e la corda si affloscia;
l'arena resta in combattimento, perché la stanza della prova non si libera mai.
Accanto al muro ovest il raggio è 1: il nemico sbatte nel muro, ogni schianto
con il suo numero solo su di lui, e a ogni schianto il giro torna indietro.
Intanto la riga dell'HUD sul giro sta intera, misurata con il font del gioco,
con la finestra fissa della prova e con quella che si accorcia del gioco, anche
con due cifre e una stanza piena. Una schivata lo lascia andare: atterra sotto
di sé e annuncia subito un intento nuovo, senza stordimento, e il suo
cartoncino cade con `MOLLATO` mentre la schivata si vede.

### Canna da Pesca

`Canna da Pesca` (non comune, energia 0, **0 s**, solo tattica: compare fra
ricompense e negozio delle run tattiche, le run classiche non la offrono) non si
gioca mai in combattimento: è un attrezzo da fine stanza. Regole in
[fishing.odin](src/game/fishing.odin), tavolo in [fishing.odin](src/render/fishing.odin).

**Mai in mano.** Quando comincia un combattimento la Canna va subito fra le
esaurite e ci resta: non si pesca, non si scarta, non torna con i rimescolamenti
(le esaurite non si rimescolano mai) e i contatori della mano non la contano.
Resta però una carta del mazzo come le altre: la scheda del personaggio la
mostra, il riposo e il negozio la potenziano, il negozio la può togliere.

**Lo slot.** Liberata la stanza (cade il suo ultimo nemico), in basso a destra,
dove starebbe la carta di una mano, compare lo slot della Canna con `PESCA n/m`
(le pesche che restano alla stanza, sulle sue). Si prende come una carta: la si
trascina su una casella, oppure un clic sulla Canna e poi un clic sulla casella;
`Esc` o il destro la rimettono giù. Mentre è presa il tavolo segna in blu le
caselle che può pescare, più chiare quelle già d'acqua, e in verde (o in rosso)
quella sotto il mouse. L'HUD scrive `CANNA DA PESCA n/m / RAGGIUNGI L'USCITA` e,
finite le pesche, `PESCHE FINITE`.

**La casella.** Una casella entro 3 celle (Chebyshev), in linea di vista, con le
regole della Pozza di Veleno (pavimento libero: niente coperture, oggetti,
nemici, non la propria) e in più, scelte della Canna, mai l'uscita, una
trappola, un bottino per terra, una pozza o un fuoco. Diventa **acqua** finché
non si lascia la stanza: la decalcomania di carta delle pozze, ma blu, con due
anelli di increspature intorno al centro di ogni casella e cerchi di luce che si
allargano. Un'acqua già fatta si pesca di nuovo.

**La pesca.** Circa tre secondi in cui il Viandante è occupato (i tasti premuti
intanto si perdono, come sempre): tira indietro la canna di carta e la lancia,
la lenza vola con il galleggiante sulla casella, che diventa acqua al tonfo; il
galleggiante galleggia finché un pesce abbocca (uno schizzo e un `!` di carta);
il Viandante tira su la canna, la preda esce dall'acqua fra gli spruzzi e gli
vola addosso. Il suo cartoncino si gira verso l'acqua e al lancio si alza nella
posa del suo cast, il braccio in su (mai il salto con la lanterna e la capriola
di un colpo), poi tiene ferma la canna, canalizzando, mentre è la canna a
riavvolgere (nessun chinarsi a raccogliere). L'HUD scrive `PESCA` / `PESCA IN
CORSO`.

**La preda.** Dal flusso proprio della stanza (il suo seme e i dadi della run,
mai l'orologio): **95% cibo** (pesce, mela, pane, formaggio o carne, che dice il
suo nome sopra il Viandante) che cura un **d4** tirato sui dadi della run e
mostrato con il dado 3D come gli altri tiri, fino alla vita massima, con il
segnalino verde `+n`; **5% una carta** del pool delle ricompense tattiche, con i
pesi di rarità del nodo della stanza e mai la Canna, che esce dall'acqua, resta
un momento sopra il Viandante con `CARTA PESCATA / nome` sotto il tavolo ed
entra nel mazzo della run. Con il mazzo pieno (32 carte) la preda è cibo.

**Pesche e upgrade.** Ogni stanza dà 1 pesca più il livello della Canna (fino al
livello 5: 6 pesche), da capo in ogni stanza. Gli upgrade alzano solo le pesche
(`PESCHE 1 -> 2`): la cura resta un d4 a ogni livello, perché la Canna non è
una carta dei dadi.

**Una per run.** Finché il mazzo ne ha una, nessuna offerta ne porta un'altra:
ricompense, negozio, Armeria dimenticata e prede la lasciano fuori. Tolta al
negozio, si può trovare di nuovo.

La carta scrive `1 PESCA A STANZA` (o `n PESCHE A STANZA`) / `CIBO d4 / 5% CARTA`
(su una carta stretta `Canna` / `1 PESCA` / `CIBO d4 O CARTA`, ma lo slot del
canvas del gioco è largo come la carta di una mano di cinque);
l'ispettore aggiunge `SOLO A STANZA LIBERATA` / `MAI IN MANO / UNA PER RUN`.
L'icona, nella cella 24 dell'atlante (la prima della settima riga,
[build_card_icons.py](tools/art/build_card_icons.py)), è una canna di legno con
l'impugnatura di sughero e il mulinello d'acciaio, la lenza che scende dalla
punta a un galleggiante rosso e bianco su uno stagno blu. La canna, il
galleggiante, le gocce, il `!` e le prede sono pezzi di carta di
[build_attack_props.py](tools/art/build_attack_props.py). Nella Prova meccaniche
ha i suoi suoni, fatti da codice come gli altri
([SOUND_SPEC.md](tools/audio/SOUND_SPEC.md)): la carta al lancio (la canna tirata
indietro e frustata in avanti, il mulinello che gira libero mentre la lenza
vola), il tonfo del galleggiante sull'acqua nuova, l'abboccata (il galleggiante
tirato sotto, uno schizzo, la lenza tesa), il mulinello che riavvolge con lo
spruzzo della preda che esce dall'acqua proprio quando si vede, la preda che
arriva nella mano (uno schiaffo bagnato sul guanto) o la carta pescata (la carta
scossa due volte e tre note di cristallo che salgono); il cartoncino del
Viandante non ne aggiunge di suoi (né il colpo di lanterna né le monete del
bottino raccolto).

La si prova con `F7`, che libera l'arena ([Prova meccaniche](#prova-meccaniche)),
e lo smoke `--smoke-mechanics-lab` la gioca, la filma
([Verifica e smoke test](#verifica-e-smoke-test)) e ne controlla le regole: la
Canna presa dallo slot e lasciata su una casella pesca un pesce (il suo d4 fa 3,
3 di vita) e la casella diventa acqua, sul tavolo 3D e su quello piatto; la
stanza ha finito la sua pesca. In nessuna pesca il cartoncino del Viandante fa
sentire il colpo di lanterna, le monete del bottino o il cast di una carta. Potenziata a +1, come la potenzierebbero un
riposo o un negozio, `F7` di nuovo dà una stanza nuova senza acqua e con due
pesche (`PESCA 2/2`): dalla prima esce una carta, mai un'altra Canna, che entra
nel mazzo; la seconda, sulla stessa acqua (nessuna casella nuova), tira fuori un
pane che cura il 2 del suo d4. Poi le pesche della stanza sono finite, e un altro
`F7` le ridà tutte e due. Per ultima la regola di una Canna per run: con la
Canna nel mazzo nessuna di 400 offerte, estratte come le estraggono ricompense,
negozio e Armeria dimenticata (`card_offer_exclusions`), ne porta un'altra,
mentre le stesse estrazioni senza di lei ne portano.

### Pinball

`Pinball` (rara, energia 3, **2 s** di finestra, solo tattica: compare fra
ricompense e negozio delle run tattiche, le run classiche non la offrono e, se
l'hanno in mano, la rifiutano) trasforma un nemico accanto al Viandante in una
grossa palla d'acciaio e la manda a rimbalzare per la stanza per 20 secondi; poi
la palla scoppia e il nemico cade. Regole in
[pinball.odin](src/game/pinball.odin), tavolo in
[pinball.odin](src/render/pinball.odin).

**Il colpo.** Il bersaglio è un nemico su una delle otto caselle intorno al
Viandante (diagonali comprese), visibile e in linea di vista: non dietro un
angolo chiuso da due blocchi. Il boss (il Demolitore) e il miniboss (il Custode)
sono troppo pesanti, come per il Lazzo e per il letale del Dado del Destino,
perché alla fine la palla muore: la carta li rifiuta e la mano scrive
`TROPPO PESANTE PER IL PINBALL`. Una palla alla volta: mentre una rotola, la
carta non prende nessun altro (`UNA PALLA ALLA VOLTA`). Il colpo è il cast della
carta: per i suoi 2 s il mondo è fermo, e la palla con lui. Il nemico diventa la
palla dov'è; i suoi status spariscono nello sbuffo (anche Veleno e Bruciatura:
la palla non ne porta), e con loro le sue reazioni e il suo intento. Il
Viandante la colpisce e la manda via da sé, nella direzione che va da lui al
nemico girata di 15–35 gradi interi a sinistra o a destra, perché non rimbalzi
mai su un asse solo. Il giro lo decide il flusso proprio della stanza
(`Room.pinball_random`, dal suo seme e dai dadi della run quando la stanza
comincia), mai l'orologio.

**La corsa.** La palla rotola sul tavolo a **7 caselle al secondo** per **20
secondi del mondo**: un disco di raggio 0,45 che rimbalza elastico su ogni cosa
solida (un muro, il bordo della stanza, una copertura, un oggetto che blocca il
passo come un barile, un blocco di ghiaccio o una bobina Tesla, che però non
prende mai danni) e su ogni nemico a terra, un respingente rotondo di raggio 0,4
al centro della sua casella. Il moto si risolve da un evento al successivo (un
contatto, il bordo della casella sotto la palla, la fine del suo tempo), mai a
fotogrammi: nessun muro viene attraversato e nessun nemico saltato a qualunque
frame rate, e la stessa stanza dà gli stessi rimbalzi comunque i secondi vengano
divisi in fotogrammi. La palla passa sopra il Viandante senza fargli niente (né
rimbalzo né danno) e sotto il nemico appeso al Lazzo. Un nemico che ci entra con
un passo, una spinta o un arrivo viene colpito subito. Nessuna bobina si posa
dove sta il suo disco; una cosa solida spinta lì comunque viene attraversata
finché il disco non ne esce.

**Il valore.** Parte da **2**. Un nemico toccato prende il valore come danno del
Viandante, con le regole normali (lo Shield lo assorbe, le reazioni rispondono,
la morte lascia il bottino, ma la stanza si libera solo con lo scoppio), e viene
spinto di **una cella** via dalla palla, nella più vicina delle otto direzioni,
con le regole della spinta: un muro, un ostacolo o un corpo lo fermano, e pozze,
fuochi e trappole della casella in cui entra fanno il loro effetto. La palla
rimbalza su di lui come su un respingente e il valore sale di uno: 2, 3, 4... Un
colpo per contatto: lo stesso nemico si colpisce di nuovo solo dopo che la palla
se n'è staccata. Ogni tocco di un muro o di un'altra cosa solida riporta il
valore a 2 (al valore della carta).

**La palla fuori dal mondo.** Per i suoi 20 secondi la palla è il nemico stesso,
ma fuori dal gioco: non occupa una casella, non agisce, non annuncia niente, non
porta status e niente la raggiunge: né danni, né status, né spinte, né carte
(aree, catene e Toxic Wave comprese), né le frecce di Feretro, le pozze, i
fuochi, le trappole, le esplosioni, le scariche Tesla o la protezione del
Custode. Il mondo intanto va avanti e il Viandante agisce liberamente (passi,
urti, carte, frecce); solo ciò che ferma il mondo (un cast, la scelta di difesa,
i dadi a tutto schermo, l'ombra di Movimento Ombra, la pausa) ferma anche la
palla. La stanza non si libera prima dello scoppio, perché la palla conta fra i
nemici; se cade il Viandante, la palla si ferma con il combattimento.

**Lo scoppio.** Finiti i 20 secondi la palla scoppia e il nemico cade dove si
trova: un'uccisione normale del Viandante (nemmeno uno Shield lo salva), con il
suo bottino lì e la stanza liberata se era l'ultimo.

**Upgrade e secondo.** Ogni upgrade dà +1 al valore di partenza, che è anche
quello a cui la riportano i muri, fino al livello 5 (`VALORE 2 -> 3`); giocata
sul secondo, +1 anche lei.

**Sul tavolo.** La palla è pixel art d'acciaio dipinta da codice, larga 1,2
caselle: una sfera in sei toni che riflette la stanza (la luce in alto,
l'orizzonte chiaro, il pavimento scuro in basso), il suo riflesso bianco, una
fascia del colore del nemico perché si sappia chi era (rossa per il ghoul,
azzurra per il balestriere, arancio per il bruto, viola per il bombarolo), la
linea d'inchiostro e il margine bianco di carta dei cartoncini con il suo
taglio. Durante il cast il cartoncino del nemico svanisce in uno sbuffo di carta
e la palla si gonfia oltre la sua misura e si assesta; il cartoncino del
Viandante tira il colpo con la sua lanterna (o con l'arma M8 che ha in mano) e
lo fa arrivare sulla palla proprio quando il cast finisce e la palla parte, con
una stella d'oro. Poi il tavolo la mostra dove la stanza dice che è, a ogni
fotogramma, con la fascia che gira con la corsa e un'ombra tonda e morbida
sotto. A ogni muro una stella grigia e uno sbuffo di polvere di pietra, a ogni
nemico una stella rossa fra la palla e il cartoncino e `COLPO n` sopra di lui.
Allo scoppio la palla si gonfia con un lampo bianco e si apre in carta e
coriandoli del suo colore, con `POP!` sopra la sua cima gonfia (il lampo e la
carta restano in vista); il cartoncino del nemico non torna più, nemmeno a
cadere. La telecamera resta sul Viandante, non segue la palla. Sul tavolo piatto
(`--flat`) lo stesso disegno sta sopra il pavimento; dietro gli occhi del
Viandante ([First Person Shooter](#first-person-shooter)) la palla sbiadisce
quando gli rotola addosso, e all'altezza degli occhi sparisce.

**Il mirino.** Con la carta in mano i nemici che può prendere hanno un mirino
d'acciaio, il boss e il miniboss in portata un mirino rosso e `TROPPO PESANTE`
sotto i piedi, lontano dai cuori dei vicini come per il [Lazzo](#lazzo); per il
nemico sotto il mouse il tavolo traccia la partenza della palla (trattini di
carta sull'inchiostro, fino a dove il disco toccherebbe la prima cosa solida,
quattro caselle al massimo, e una punta), già girata come la girerà il flusso
della stanza.

**L'HUD.** Mentre la palla rotola l'HUD ha un chip d'acciaio subito dopo Veleno
e Bruciatura del Viandante: `PINBALL 14s x5`, i secondi che restano e il valore
(con poco spazio `PIN 14s x5`).

La carta scrive `COLPI 2, 3, 4...` / `MURO: TORNA A 2 / 20s` (con sette carte in
mano o più `COLPI 2, 3...` / `MURO: 2 / 20s`; nel classico `SOLO TATTICA`);
l'ispettore aggiunge `BOSS E MINIBOSS: TROPPO PESANTI` /
`DOPO 20s SCOPPIA E CADE`. L'icona, nella cella 25 dell'atlante (la seconda
della settima riga, [build_card_icons.py](tools/art/build_card_icons.py)), è una
palla cromata illuminata dall'alto a sinistra che colpisce un respingente (un
cappello rosso con un riflesso chiaro in cima, in un anello d'oro), con una
scintilla fra i due. Nella Prova meccaniche ha i suoi suoni, fatti da codice
come gli altri ([SOUND_SPEC.md](tools/audio/SOUND_SPEC.md)): la carta (uno
stantuffo tirato indietro, la molla che sale di tono e il cricchetto sempre più
fitto, fermato a fondo corsa; poi il cartoncino del nemico appallottolato come
un foglio e la palla che cade intera, un tintinnio d'acciaio), il colpo che la
manda via (ferro sull'acciaio, la palla che risuona, un fruscio che si
allontana), il tocco di un muro (un piccolo toc d'acciaio sulla pietra, breve,
anche più volte al secondo), il respingente di un nemico (un bong cavo, la carta
schiaffeggiata e lo squillo del respingente, sempre più acuto man mano che il
valore sale) e lo scoppio (un palloncino di carta, coriandoli che cadono, un
ultimo tintinnio). Finché è la palla il nemico non fa sentire niente di suo, e
il colpo del Viandante non aggiunge quello della lanterna.

Lo smoke `--smoke-mechanics-lab` la gioca dalla mano, la filma
([Verifica e smoke test](#verifica-e-smoke-test)) e ne controlla le regole. Il
Viandante sta al centro di un'arena nuova con un balestriere avvelenato accanto
a est, il Custode accanto a sud-ovest, un bruto a due celle e altri nemici
fermi; il flusso della stanza è fissato su un giro di 30 gradi a sinistra, e tre
ghoul fermi stanno sulla strada della palla. Per la corsa la telecamera si
allontana, perché la fila e il muro nord restino in vista, e per lo scoppio
ancora di più. Il mirino segna il balestriere e la sua partenza; sul Custode
scrive `TROPPO PESANTE` e né la regola né la carta lasciata su di lui lo
prendono, e il bruto a due celle è fuori portata. Il colpo costa 3 di energia,
toglie il Veleno al balestriere e tiene fermi il mondo e la palla per tutto il
cast; la palla parte nella direzione dal Viandante al balestriere girata di 30
gradi, e la lanterna la raggiunge entro un fotogramma e mezzo dalla fine del
cast. Poi la palla prende i tre ghoul uno dopo l'altro per 2, 3 e 4, ognuno
spinto di una cella via da lei, e il muro nord riporta 5 a 2. Per tutti i 20
secondi ogni nemico toccato prende il valore di quel momento, uno in più del
precedente, ogni cosa solida lo riporta a 2, ogni spinta è di una cella via
dalla palla e per ogni contatto il tavolo mostra la sua stella; la vita di ogni
nemico colpito scende di quanto ha preso, e niente altro. A ogni fotogramma il
disco della palla resta fuori da ogni casella solida, la sua direzione resta
unitaria e la vita del balestriere non cambia; un colpo, uno status, una freccia
o una carta su di lui vengono rifiutati. La palla rotola sopra il Viandante
senza fargli niente, lui fa un passo mentre lei rotola e il mondo batte un
secondo dopo l'altro. Il chip dell'HUD sta intero accanto ai morsi e alle
cariche, anche con un valore di due cifre. Scoppia nel fotogramma che porta la
palla ai suoi 20 secondi, dopo una ventina di battiti del mondo: il balestriere
cade sulla casella della palla con il suo bottino, senza che il suo cartoncino
ricompaia, e l'arena resta in combattimento.

### First Person Shooter

`First Person Shooter` (rara, energia 3, **0 s** di finestra, solo tattica:
compare fra ricompense e negozio delle run tattiche, le run classiche non la
offrono e, se l'hanno in mano, la rifiutano) mette il Viandante dietro i suoi
occhi per **20 secondi del mondo**, con un AK di carta. Si gioca su di sé, con
il suo tasto o con un secondo clic sulla carta, a finestra aperta o da storditi,
ma non con la scelta di difesa aperta, con un nemico appeso al Lazzo o dentro
un'altra prima persona. Non ha cast: la carta di rimpiazzo arriva subito e la
finestra non perde niente. Regole in
[first_person.odin](src/game/first_person.odin), tavolo in
[first_person.odin](src/render/first_person.odin), mouse e tasti in
[first_person_input.odin](src/first_person_input.odin).

**La vista.** Mentre la carta si mostra, la telecamera scende dalla vista del
tavolo negli occhi del Viandante, nella sua casella, a 1,05 sopra il pavimento,
con un campo visivo di 70 gradi: guarda dove guarda lui se è entro 50 gradi da
dove guardava la telecamera, altrimenti lungo la direzione della griglia più
vicina a quello sguardo. Da lì la stanza è il tavolo 3D: nemici e oggetti sono i
soliti cartoncini e pezzi di carta, girati verso di lui. Il suo cartoncino
svanisce quando la telecamera lo raggiunge, i muri interni diventano interi e
opachi, quelli del bordo non si abbassano più verso la telecamera, e cuori,
sigilli e scritte restano solo sui nemici che l'occhio vede (mai dietro un
muro). Con il tavolo piatto (`--flat`) il tavolo torna 3D per quei secondi, e
dopo di nuovo piatto. Finiti i secondi, quando il combattimento finisce o se il
Viandante cade, la telecamera risale com'era scesa, in 0,6 s.

**Il mouse.** Il cursore sparisce ed è catturato: il mouse gira la vista (a
destra gira a destra, in su guarda in su), libera intorno e fino a 0,55 radianti
in su e in giù, con la sensibilità del mouse delle impostazioni. `P`, e qui
anche `Esc`, mettono in pausa e liberano il mouse; lo liberano anche la perdita
del focus, una finestra sopra il tavolo e la fine della vista. Un clic fatto
prima (quello che riprende dalla pausa, il doppio clic della carta) non spara
finché non lo si rilascia, come nella prova FPS di Cripta delle Rune, da cui
vengono anche la cattura e la sensibilità.

**L'AK.** In basso a destra c'è un AK di carta, pixel art dipinta da codice con
gli strati dei cartoncini ritagliati (il margine bianco compreso), al centro un
mirino. Tenendo premuto il tasto sinistro spara **6 colpi al secondo** da **1
danno**, senza munizioni e senza tempo di finestra. Ogni colpo segue la linea
del mirino dall'occhio, casella per casella, e il primo nemico che incontra lo
prende: un attacco normale del Viandante (lo Shield lo assorbe, le reazioni
rispondono, la morte lascia il bottino e può liberare la stanza). Un muro, il
bordo della stanza, una copertura o un oggetto che blocca il passo lo fermano,
qualunque sia la loro altezza, e così un angolo chiuso da due blocchi; il
pavimento lo ferma dove la linea lo raggiunge, e una casella fuori vista lo
perde. Ogni nemico è il suo cartoncino, girato verso l'occhio: il colpo lo
prende dovunque la linea ne incontri la carta, bordo bianco compreso, larga a
ogni altezza quanto la carta del cartoncino vivo (gli artigli larghi, la testa
più stretta), anche dove sporge sulla casella accanto a quella che la linea
attraversa; accanto alla carta e sopra la sua cima il colpo passa e va avanti.
La linea parte dall'occhio dove la vista lo mostra, anche mentre scivola da una
casella all'altra, e trova i cartoncini dove il tavolo li mostra, anche mentre
scivolano verso la casella nuova o saltano: il colpo va dove il mirino stava
sopra quello che si vedeva, e il mirino si scalda solo lì. Il nemico appeso al
Lazzo e la palla del [Pinball](#pinball) non sono corpi per i colpi; gli oggetti
non si danneggiano. Un colpo non è un'azione del Viandante: il suo Veleno non
morde e il suo cartoncino non colpisce. Il grilletto spara un colpo ogni sesto
di secondo e da un fotogramma all'altro porta al più il ritardo di un colpo,
quindi sono 6 al secondo a qualunque frame rate; i colpi aspettano mentre si
risolve un battito, mentre è aperta la scelta di difesa e durante un cast.

**I passi.** `W`, `A`, `S` e `D` fanno un passo di una casella secondo la vista:
`W` avanti (lungo la direzione della griglia più vicina alla vista), `S`
indietro, `A` a sinistra e `D` a destra, ognuno con le regole e il tempo di un
passo normale (contro un nemico è l'urto: si vede dove colpisce, sulla carta del
nemico, perché la lanterna svanisce con il cartoncino del Viandante e non passa
davanti agli occhi), e l'occhio scivola da una casella all'altra. Anche la
schivata (`Shift` + `WASD`) e l'atterraggio della schivata di difesa seguono la
vista; i tasti delle diagonali (`Q`, `E`, `Z`, `C`) tacciono, `Spazio` aspetta.

**Niente carte.** Per tutti quei secondi la mano scivola sotto il bordo dello
schermo e nessuna carta si gioca, nemmeno con i tasti; niente frecce di Feretro,
Refocus, abilità, 6 RANCH 7 o Movimento Ombra, e niente mappa (`Tab` e il
pulsante tacciono), e il puntatore non arriva a nessun pulsante: solo l'AK. Il
resto va avanti come sempre: l'orologio della finestra, gli intenti e i colpi
dei nemici con la loro scelta di difesa, i morsi della Bruciatura, i fuochi.

**Il tavolo e l'HUD.** Ogni colpo vola come un tracciante di carta dalla bocca
dell'AK fino a dove si ferma e lì fa una scintilla: una stella rossa su un
nemico, una stella d'oro e schegge di pietra su una cosa solida (sul corpo che
l'ha fermato, anche se basso), polvere sul pavimento. L'AK rincula a ogni colpo
con una fiammata alla bocca, in due disegni che si alternano; il mirino si
scalda sopra un nemico e ne segna gli angoli quando un colpo va a segno. Le
ferite dell'AK non fanno animare né il Viandante né il colpito e lasciano
piccoli segnalini di danno. In basso a sinistra, dove stava la mano, un riquadro
conta i secondi (`FPS 12s`, rosso negli ultimi 3); la riga di stato dice
`MIRA COL MOUSE / CLIC: SPARA / WASD: PASSI`, i pulsanti della mappa e del
personaggio sono spenti (il puntatore è della vista) e, a ogni ferita (un colpo
nemico, un morso della Bruciatura o del suo Veleno), i bordi dello schermo
lampeggiano di rosso e la vista trema un poco. Vita e finestra restano al loro
posto nell'HUD.

**Upgrade e secondo.** Ogni upgrade dà +2 s, fino al livello 5 (30 s,
`SECONDI 20 -> 22`); giocata sul secondo, +2 s anche lei.

La carta scrive `PRIMA PERSONA 20s` / `AK: 6 COLPI/s, 1 DANNO` (con sette carte
in mano o più `FPS` / `FPS 20s` / `AK: 6 COLPI/s`; nel classico `FPS 20s` /
`SOLO TATTICA`); l'ispettore aggiunge `NIENTE CARTE: SOLO L'AK` /
`WASD SECONDO LA VISTA`. L'icona, nella cella 26 dell'atlante (la terza della
settima riga, [build_card_icons.py](tools/art/build_card_icons.py)), è un AK di
profilo (calcio, impugnatura e paramano di legno, castello d'acciaio e
caricatore a banana) con la fiammata alla bocca e tre bossoli d'ottone che
volano via, dentro l'anello rosso di un mirino. Nella Prova meccaniche ha i suoi
suoni, fatti da codice come gli altri
([SOUND_SPEC.md](tools/audio/SOUND_SPEC.md)): la carta (l'AK preparato: il
caricatore inserito, la leva d'armamento tirata indietro e lasciata andare), la
discesa negli occhi (la stanza che arriva in un soffio, il cappuccio che si
chiude intorno alla vista con un tonfo morbido) e la risalita, ogni colpo (breve
e secco: lo schiocco della bocca, la carta del fucile, l'otturatore), il colpo
che ferisce (il cartoncino bucato, un tonfo sordo) e quello che si ferma sulla
pietra (una scheggia e il fischio del rimbalzo); il colpito non aggiunge la sua
ferita.

Lo smoke `--smoke-mechanics-lab` la gioca dalla mano, la filma
([Verifica e smoke test](#verifica-e-smoke-test)) e ne controlla le regole. Le
sue parole stanno sulla carta della mano a ogni livello, e anche su quelle più
larghe del gioco (mani da cinque e da sei, negozio, ricompense), dove il nome è
`FPS`. Giocata su di sé costa 3 di energia e nessun secondo di finestra, dura 20
secondi e non ha cast; una carta, un Refocus e una freccia vengono rifiutati. La
telecamera arriva negli occhi, il cartoncino del Viandante sparisce, la mano
scivola via e la discesa suona. Un secondo di grilletto tenuto, a 60 fotogrammi
al secondo, spara 6 colpi nel ghoul tre celle a nord, ognuno da un punto (il suo
cuore va da 40 a 34); in quei 72 fotogrammi la finestra e i secondi della vista
calano di 1,2 s e non di più, il Veleno del Viandante non morde e lui non perde
vita; suonano 6 colpi, né la lanterna né la ferita del ghoul. A ovest un blocco
di ghiaccio ferma un colpo e il balestriere dietro resta intatto; a sud il muro
del bordo ne ferma un altro. Con la vista a est `W`, `D`, `S` e `A` vanno a est,
sud, ovest e nord, e l'occhio scivola solo in avanti fino al centro della
casella; `W` contro un nemico è un urto e `Shift` con `D` schiva di due celle a
sud. Il colpo di un ghoul libero apre la scelta di difesa dietro gli occhi, con
i secondi della vista fermi come quelli del mondo, e `E` poi `A` schiva a nord,
la sinistra della vista; un colpo lasciato passare fa lampeggiare i bordi di
rosso. Nel recupero dopo la fine della finestra l'AK spara ancora. Finiti i 20
secondi, dopo una ventina di battiti del mondo, la vista finisce, la telecamera
risale con il suo suono e il mouse torna libero. Una copia +5 dura 30 secondi, e
un tavolo piatto diventa 3D per la vista e di nuovo piatto dopo `F7`. Il
riquadro dei secondi e la riga dell'HUD ci stanno interi.

### Mostra effetto

Ovunque si guardi una carta, **MOSTRA EFFETTO** apre sopra la run una finestra
che la mostra al lavoro: un piccolo film in cui un guanto di carta la prende da
una piccola mano, la gioca sul suo bersaglio e una stanza di prova la risolve
con le regole vere del gioco. Ogni carta ha il suo film, a ogni livello, e così
ogni carta che verrà aggiunta. Solo nel gioco tattico: le run classiche
(`--classic`) non mostrano pulsanti. Finestra in
[effect_window.odin](src/effect_window.odin), film in
[card_demo.odin](src/card_demo.odin), scene in
[card_demo.odin](src/game/card_demo.odin), guanto e didascalie in
[card_demo.odin](src/render/card_demo.odin), pulsanti delle schermate in
[effect_entries.odin](src/render/effect_entries.odin).

**Dove si apre.** I pulsanti hanno lo stile gotico dell'HUD e non stanno mai
sopra una carta (nemmeno quella che si alza sotto il mouse), un prezzo, una
scritta o un altro comando: un clic su di loro non sceglie, non compra e non
gira pagina.

- **L'ispettore della carta**, in combattimento. Con il mouse su una carta della
  mano l'ispettore aggiunge in fondo una riga spenta, `I` `MOSTRA EFFETTO`: lì
  un clic prenderebbe la carta, quindi basta il tasto `I`. Scelta la carta (un
  clic, o il suo numero se ha un bersaglio), l'ispettore resta anche quando il
  mouse se ne va e la riga diventa un pulsante, che si clicca senza giocare,
  mirare o muovere niente; `I` vale ancora. Pulsante e tasto tacciono mentre il
  tavolo è occupato (una difesa, un cast, [Movimento Ombra](#movimento-ombra),
  un'azione o una pesca che si stanno ancora mostrando), e intanto il pulsante
  resta spento, come **PERSONAGGIO**; non c'è mentre la carta è trascinata né
  dietro gli occhi di [First Person Shooter](#first-person-shooter).
- **Lo slot della [Canna da Pesca](#canna-da-pesca)**, a stanza liberata: lo
  stesso ispettore, con il mouse sulla Canna o con la Canna scelta.
- **La scheda del personaggio** (**PERSONAGGIO**). Il riquadro **MAZZO** elenca
  il mazzo della run, una riga per carta e livello, nell'ordine in cui il mazzo
  li tiene la prima volta (`2x Strike`, `1x Pinball +2`): cinque righe, oppure
  quattro per pagina con `<`, `n/m` e `>` in fondo quando non ci stanno tutte.
  Un clic sceglie una riga (girare pagina sceglie la prima della pagina), e
  `I` `MOSTRA EFFETTO`, nella testa del riquadro, o il tasto `I` mostrano quella
  scelta. La finestra si apre sopra la scheda: `Esc` chiude la finestra e lascia
  aperta la scheda.
- **La ricompensa**: un pulsante sotto ogni carta offerta; `I` mostra quella
  sotto il mouse.
- **Il negozio**: un pulsante sotto il prezzo di ogni offerta, e
  `I  MOSTRA EFFETTO` nella riga dei comandi, a sinistra dell'upgrade, per la
  carta posseduta scelta per l'upgrade o la rimozione; `I` mostra l'offerta
  sotto il mouse, altrimenti la carta scelta.
- **Il riposo**: lo stesso `I  MOSTRA EFFETTO`, per la carta scelta per
  l'upgrade, finché il riposo non è risolto; anche qui `I`.

Le carte offerte si vedono come sono offerte, al livello 0; quelle del mazzo
come il mazzo le tiene, con il loro upgrade. La testa della finestra scrive il
nome della carta con il suo `+n` e
`MOSTRA EFFETTO / LE REGOLE DEL GIOCO IN UNA STANZA DI PROVA / TEMPO SOSPESO`.

**I comandi.** `Esc`, un clic destro o **CHIUDI** (in alto a destra, con il suo
`ESC`) chiudono la finestra; `R` o **RICOMINCIA** fanno ripartire il film dal
primo fotogramma. Un clic altrove, sul film compreso, non fa niente: il film non
si comanda, si guarda. Senza il focus la finestra non risponde e il film resta
fermo dov'è. `F1`–`F3`, `F9` e `F11` valgono anche a finestra aperta (il film
segue la scala); gli altri tasti della run, come `F5` e `F10`, aspettano che si
chiuda.

**La run ferma.** La finestra non è una scena dell'host ([Scene](#scene)) ma un
modale dentro la run: niente dissolvenza, niente `resume`. Finché è aperta,
`roguelike_update` le dà tutto il fotogramma, subito dopo il controllo del
focus: alla run non arriva nessun tasto né clic e non scorre nessuno dei suoi
orologi (la finestra del pulse e il mondo, la timeline, gli arrivi della Prova,
i cartoncini), quindi niente di quello che la run possiede cambia; sotto un velo
scuro resta la run com'era nell'ultimo fotogramma disegnato. Aprendosi, la
finestra fa lasciare alla run quello che teneva, come quando la finestra del
gioco perde il focus (`roguelike_suspend_input`: la carta presa o scelta, il
passo in attesa della diagonale, il trascinamento della camera, il mouse dietro
gli occhi); chiudendosi, la run riprende come al ritorno del focus: il primo
fotogramma legge i tasti come sono e non conta tempo, quindi né il clic che l'ha
chiusa né un tasto di quel fotogramma arrivano al tavolo. Non si apre mentre il
tavolo è occupato (`effect_window_refusal`): in pausa, con la mappa olografica,
con 6 RANCH 7 o il ring (anche quando un quadrato di Tesla sta per aprirlo),
durante la scelta di difesa, un cast o i dadi, dietro gli occhi di First Person
Shooter (anche mentre la vista scende o risale), in Movimento Ombra e finché il
tavolo mostra ancora un'azione. Ricompensa, negozio e riposo non mostrano il
tavolo: lì si apre sempre, qualunque cosa abbia lasciato la stanza.

**Le regole vere in una stanza di prova.** Il film non è un'animazione fatta a
mano. Ogni ripresa costruisce una stanza tattica sua (`create_card_demo_room`):
11x9 caselle muri compresi, il Viandante al centro con 22 di vita massima e 3 di
energia, la carta sola in mano (o la Canna nel mazzo), le regole del gioco con
le azioni a tempo, una finestra che non si accorcia, niente nebbia e quello che
la scena chiede. La carta si gioca come la gioca la mano, per le sue stesse
strade: un trascinamento lasciato sul bersaglio (`card_drop_target`), un clic e
un secondo clic per le carte senza bersaglio, lo slot della Canna con
`poll_fishing_command`. Poi la stanza va avanti solo con il proprio
`step_tactical_controller`, il controller del gioco, e le azioni della scena (un
passo, una freccia, ATTIVA, il grilletto dell'AK) passano dagli stessi comandi
del gioco quando il tavolo le lascia passare. La disegna il renderer del gioco
(tavolo, cartoncini vivi, colpi, dadi, HUD e mano): un renderer prestato
([effect_stage.odin](src/render/effect_stage.odin)) con il suo stato di vista
(timeline, snapshot, etichette, attori, la superficie del tavolo) e gli asset
GPU del renderer della run, presi in prestito e mai scaricati. La run non viene
mai toccata: stanza, livello, giocatore, mazzo e dadi del film sono del film.
Tutto è deterministico, mai l'orologio: semi fissi per la stanza e per il mazzo,
i dadi della ripresa cercati una volta fra i semi perché il primo tiro mostri le
facce che la scena vuole, il flusso della Canna scelto perché la prima preda sia
cibo. I nemici stanno fermi dove sono, senza piani né colpi, tranne quelli che
la scena lascia liberi, e la stanza non si libera da sola all'ultima uccisione
(`Room_Content.endless`), salvo quella della Canna, già liberata.

**Il film.** Un guanto di cuoio in pixel art, ritagliato nella carta come i
pezzi del tavolo (la stampa, la linea d'inchiostro, il margine bianco, il
taglio), aspetta in basso, va alla carta, la prende chiudendo la mano e la porta
sul bersaglio: un nemico, una casella, una casella in linea retta. Le carte su
di sé o senza bersaglio si giocano con un doppio clic, come nella mano: il primo
la sceglie, il secondo la gioca. Ogni clic lascia sotto il dito un anello di
carta. Mentre il guanto porta la carta il mondo del film aspetta: il suo orologio
parte quando la carta è lasciata, così ogni ripresa mostra lo stesso. Una
didascalia in basso a sinistra dice cosa si fa, con il tasto da premere su un
tastino di carta quando ce n'è uno: `TRASCINA LA CARTA SUL NEMICO`,
`TRASCINA LA CARTA SU UNA CASELLA`, `TRASCINA LA CARTA IN LINEA RETTA` (o
`TRASCINA SUL NEMICO IN LINEA RETTA`), `DOPPIO CLIC SULLA CARTA`,
`TRASCINA LA CANNA SU UNA CASELLA`; poi `L'EFFETTO, CON LE REGOLE DEL GIOCO` e,
quando la scena lo chiede, quello che il Viandante fa dopo la carta:
`W: UN PASSO` (con il tasto della sua direzione), `W: COLPISCI IL NEMICO`,
`W: UN PASSO NELL'OMBRA`, `CTRL + CLIC SUL NEMICO: FRECCIA`,
`CLIC SU ATTIVA: SCARICA LE TESLA`, `MUOVI IL MOUSE: GIRI LA VISTA` e
`TIENI PREMUTO IL CLIC: SPARI`. Nei film in cui la mano cresce (carte che
pescano o creano carte) la didascalia sale sopra la riga dell'`ENERGIA`; non
copre mai una carta, lo slot della Canna o la barra degli oggetti. Quando la
carta cambia quello che la piastra VITA dell'HUD mostra del Viandante (uno
scudo, l'oro, una ferita, una cura, uno status), la piastra si accende con una
cornice di carta che batte tre volte mentre si spegne: Guard la accende con
`SCUDO 4`. Dietro gli occhi di First Person Shooter il guanto sparisce: la vista
gira e spara secondo il copione della ripresa, e il mouse vero non viene mai
catturato. Il tavolo del film è una vetrina (`Tactical_View.showcase`): tiene le
piastre dell'HUD e la barra degli oggetti (la Tesla vi clicca ATTIVA), non i
COMANDI, l'ispettore del nemico o un MOSTRA EFFETTO suo, e la sua camera mira
più vicino al Viandante (0,30 celle avanti invece di 1,10, che nel gioco
lasciano il fondo a una mano piena), perché quello che gli sta oltre resti in
vista sotto le piastre dell'HUD.

**Da capo.** Quando la carta ha mostrato tutto e la stanza si è fermata, la
ripresa resta un momento, il film si scurisce e riparte da capo: la stessa
stanza, gli stessi semi, la stessa ripresa, finché la finestra resta aperta.
**RICOMINCIA** la fa ripartire subito dal primo fotogramma. Una ripresa dura al
massimo 40 secondi (`CARD_DEMO_TAKE_LIMIT`); le più lunghe seguono le regole
delle loro carte: il Pinball circa 27 s (la palla rotola 20 s), l'Incendio 21 s
(finestre da 2 s, perché il fuoco cresca e si spenga), First Person Shooter +5
33 s (30 s di vista, con una raffica dell'AK ogni 3 s). Un fotogramma lento non
fa saltare il film: ogni passo conta al più un quindicesimo di secondo.

**La scala.** Il film si disegna in uno stage, un render target di 960x540,
durante l'update (i render target di raylib non si annidano: mai dentro il passo
del canvas, e i dadi del film prima ancora, fuori da ogni render target), e si
mostra opaco dopo il canvas, sui pixel della finestra, a tre quarti del canvas:
alla misura predefinita, 1280x720, lo stage sta in {160, 116, 960, 540} e ogni
suo pixel è un pixel della finestra. Alle altre misure segue il canvas (`F1`–`F3`
compresi), con il filtro nearest da 1:1 in su (a 1600x900 in
{200, 145, 1200, 675}) e bilineare quando la finestra è più piccola, perché
nessuna riga si perda (a 960x540 è largo 720). Su quei 960x540 il film disegna
tavolo, HUD e mano nelle misure del gioco, con la camera un po' più vicina (10
invece di 12,5), perché i cartoncini sembrino grandi come nel gioco.

**Una carta nuova.** Ogni carta ha un film senza scriverne una riga.
`card_demo_default_scene` ricava la scena dal targeting e dagli effetti della
carta: il gesto che il targeting chiede (doppio clic per `Self`, `Player` e
`None`; trascinata su un nemico, su una casella o lungo una linea per gli
altri), un nemico dove il bersaglio è un nemico, a due celle (dentro la portata,
mai oltre tre; accanto, se la carta lo vuole adiacente) alla destra del
Viandante sullo schermo; due nemici dentro l'area che colpisce, e un barile se
tocca gli oggetti; due nemici a portata di una carta che colpisce tutti; altre
carte nel mazzo (Strike, Guard e Arc Bolt) se pesca o scarta; sul Viandante lo
status che toglie. Quello che la ripresa deve mostrare viene dalla definizione
della carta (`card_demo_expected_events`): gli eventi di ogni suo effetto,
quanti nemici deve ferire, la pozza o il fuoco che lascia
(`card_demo_ground_expected`) e i colpi dell'AK. Lo switch su `Effect_Kind` è
esaustivo, e così quello su `Status_Kind` per ciò che il Viandante porta
(`card_demo_status_use`): un nuovo tipo di effetto o di status non compila
finché non dice come la sua ripresa lo mostra.
`test_every_card_has_a_demo_that_shows_its_effect` gioca ogni `Card_Id` a ogni
livello, due riprese uguali, e per una carta nuova che il default non mostra
fallisce dicendo quali eventi mancano. Vuole anche che ogni didascalia venga
dalla tabella del film (`CARD_DEMO_WORDS`), che lo smoke misura tutta nella sua
piastra: una didascalia nuova va lì.

Allora serve un override in `card_demo_scene`, la scena della carta che parte
dal default: un nemico libero che colpisca dopo la carta (Thorn Coat e Counter
Rune, il balestriere di Deflect), un'azione del Viandante dopo la carta (il
passo di Afterimage, l'urto caricato del Dado del Destino e di Lama Velenosa, la
freccia di Feretro, ATTIVA della Tesla, i quattro passi dell'ombra, le raffiche
dell'AK), altri nemici in fila o intorno (Chain Lightning, Storm Crown, Lazzo,
Pinball), le facce dei dadi (Sundering Blow 4+4, Prismatic Barrage 4/1/4, Twin
Venom 3/3, la faccia più alta di Fate Strike, Shock Floor 3, il d4 della Canna
a 3), una stanza diversa (già liberata per la Canna, finestre da 2 s per
l'Incendio, la nebbia per Battle Focus) o pozze già versate (l'anello della
Pozza di Veleno). Una scena può anche chiedere eventi oltre a quelli della carta
(`expects`) e più nemici feriti (`foe_hurt`), e cambiare con il livello (le
raffiche di First Person Shooter seguono i secondi della vista). Un override
serve anche quando il test passa ma la ripresa si vede male:
`test_card_demo_frames_its_scene` vuole ogni nemico, oggetto, bobina, pozza e
bersaglio di ogni scena sullo stage, dai piedi alla testa, fuori dalle piastre
VITA e del pulse, dall'ispettore, dalla mano, dallo slot della Canna e dalla
didascalia, sul tavolo 3D e su quello piatto; il resto si guarda nelle immagini
dello smoke.

**Suoni.** Fuori dalla Prova meccaniche il film tace. Nella Prova il suo tavolo
è quello della prova: mette in coda i suoni della prova come il tavolo della
run, e la finestra li suona al volume degli effetti
(`effect_window_film_sounds`); il fondo della cripta tace finché la finestra è
aperta.

**Le verifiche.** [effect_window_test.odin](src/effect_window_test.odin) apre la
finestra da ogni ingresso e vuole la carta giusta al livello giusto, senza
scelte, acquisti o pagine girate; la run ferma e intatta mentre è aperta; la
chiusura solo con `Esc`, il clic destro o CHIUDI, senza clic che passino al
tavolo; un rifiuto per ogni stato occupato; lo stage 1:1 a 1280x720; ogni carta,
al primo livello e all'ultimo, che si apre, gira e si chiude senza lasciare
memoria; e con ogni carta a ogni livello, sul tavolo piatto e su quello 3D, una
prima ripresa che mostra tutto quello che la carta promette e una seconda che
riparte da capo. [card_demo_test.odin](src/card_demo_test.odin) tiene i film a
30 e a 144 fotogrammi al secondo e a fotogrammi irregolari, sul tavolo della
vetrina con la didascalia mai sopra la mano, e la loro inquadratura;
[card_demo_test.odin](src/game/card_demo_test.odin) costruisce la stanza di
ogni scena a ogni livello e tiene i default sul targeting delle carte;
[effect_entry_test.odin](src/render/effect_entry_test.odin) tiene i pulsanti
lontani da carte, prezzi e comandi;
[effect_stage_test.odin](src/render/effect_stage_test.odin) percorre con
`core:reflect` tutto il `Renderer` e fallisce se il renderer prestato non prende
in prestito una texture, uno shader, un font, una mesh o un modello, o se divide
con quello della run uno stato che deve essere suo.

Lo smoke `--smoke-effect-window` ([Verifica e smoke test](#verifica-e-smoke-test))
apre la finestra vera da ogni ingresso, sulla run della sessione, e poi filma
una ripresa intera di ogni carta, al livello 0 e al più alto, attraverso la
finestra: ognuna deve mostrare l'effetto nel suo tempo, senza errori della
timeline e con la run ferma; a ogni fotogramma la didascalia sta intera nella
sua piastra, misurata con il font del gioco, la piastra non copre niente e il
guanto resta sullo stage; fuori dalla Prova non va in coda nessun suono, mentre
una ripresa di Strike come nella Prova suona i suoi, e il cursore non sparisce
mai. Misura anche il costo del fotogramma: con la finestra aperta il gioco deve
tenere i 60 fotogrammi al secondo, e più di un fotogramma su cinquanta in
ritardo lo fa fallire. Dura circa dieci minuti;
`-define:EFFECT_SMOKE_CARDS=,Strike,Pinball,` filma solo le carte nominate (con
i nomi di `Card_Id`) e `--flat` le filma sul tavolo piatto:

```sh
odin run src -o:none -- --smoke-effect-window
odin run src -o:none -define:EFFECT_SMOKE_CARDS=,Strike,Pinball, -- --smoke-effect-window --flat
```

### Il tavolo: cartoncini vivi, cerchi e segnalini

I personaggi del tavolo 3D sono **cartoncini vivi**: la figura è un disegno
animato su un cartoncino che resta fermo e non cambia mai forma né dimensione.
Il personaggio si muove dentro la carta e il bordo lo taglia quando ne esce; per
cambiare casella spinge il cartoncino, che scivola rigido (la spallata del
Viandante, la corsa del ghoul, i passi pesanti del bruto...). I disegni vanno a
12 al secondo, a 24 nei momenti più rapidi, con schiacciamento e allungamento,
linea viva e piccoli segni a matita. Generatore e regole sono in
[tools/art/README.md](tools/art/README.md#cartoncini-vivi); il runtime è
[living_card.odin](src/render/living_card.odin). I minigiochi (Platform 3D, FPS)
usano ancora i cartoncini classici.

Il Viandante ha un **cerchio d'azione**: una linea sottile oro, come il colpo
critico, con la forma del suo cartoncino. Batte i secondi: è al massimo subito
dopo uno scocco e si stringe fino a toccare la carta allo scocco successivo, il
momento giusto per un'azione critica; segue il tempo reale anche quando
un'azione consuma secondi.

**Le intenzioni dei nemici** si leggono anche con la coda dell'occhio. La
visione periferica perde colore e dettaglio ma coglie i cambi di luminosità (un
tremolio fra 5 e 10 Hz) e il movimento; per questo ogni nemico dice **cosa** sta
per fare con un pittogramma grande e un colore, **quando** con un indicatore che
si riempie verso l'azione, e **adesso** con un tremolio di luce e della figura
nell'ultimo mezzo secondo e un lampo verso l'esterno quando l'azione arriva. Solo
le azioni a meno di un secondo e mezzo sono vivide: le altre restano tenui, così
più nemici non gridano tutti insieme
([intent_display.odin](src/render/intent_display.odin)).

- **Sigilli**: un sigillo appuntato sulla carta del nemico, con il pittogramma
  su carta (spada, arco, bomba, stivale, scudo), un indicatore spesso con una
  tacca per secondo (anche per quelli aggiunti dal Rallentamento) e un alone del
  colore dell'azione quando si avvicina; la figura trema prima di agire.
- **Terreno**: la conseguenza dove arriva, come in Into the Breach. Le celle
  colpite si riempiono dai bordi al centro e la cella del Viandante si contorna
  se è fra queste; un movimento riempie la cella d'arrivo con una freccia, una
  protezione tira un filo verso l'alleato.

Nella nebbia niente tradisce un nemico nascosto: sigillo, freccia, filo e lampo
compaiono solo se è in vista, una cella minacciata solo se è visibile. Il colore
dice il tipo di azione:

| Colore | Azione in arrivo |
|---|---|
| rosso | colpo ravvicinato: attacco, spinta, fendente, carica |
| arancio | colpo a distanza o ad area: mira, tiro, bombe, barili accesi |
| verde | movimento |
| viola | protezione di un alleato |

Recupero e attesa non hanno colore. I colori caldi staccano dal pavimento blu e
segnano le minacce;
verde e viola, vicini al blu, sono chiari; rosso e verde differiscono anche per
luminosità, per chi è daltonico ([living_ring.odin](src/render/living_ring.odin)).

Danni e cure compaiono su **segnalini di carta**: piccoli cartoncini tagliati e
inchiostrati come quelli dei personaggi, che escono di lato dalla carta di chi è
colpito o curato con il numero in pixel, rosso per i danni e verde per le cure,
restano un attimo e cadono ([living_token.odin](src/render/living_token.odin)).
Prendono il posto dei riquadri scuri con i numeri; un colpo critico mostra
ancora CRITICO. Ogni colpo ha il suo segnalino anche quando è uguale al
precedente: due urti da 2 sullo stesso nemico, uno dopo l'altro, ne mostrano due.

**I colpi si vedono sul tavolo.** Ogni colpo fisico, del Viandante o di un
nemico, ha la sua arma di carta: pixel art ritagliata con lo stesso bordo
bianco dei cartoncini vivi, disegnata da codice
([build_attack_props.py](tools/art/README.md#armi-e-colpi-di-carta)).

- **Corpo a corpo**: l'arma di chi colpisce spazza **ogni casella** del colpo,
  dalla più lontana dalla telecamera alla più vicina, con una scia di carta; la
  stella dell'impatto cade sul cartoncino colpito e le caselle vuote perdono
  pezzetti di carta. Il fendente del bruto passa sulle sue tre caselle, il
  ghoul graffia due volte con gli artigli, la Picca della tempesta affonda.
- **A distanza**: il dardo della balestra (e la bomba del bombarolo, la brace
  che l'arcimago lancia su un barile) vola dal tiratore alla casella con un arco
  leggero, orientato sul suo volo: resta conficcato nel cartoncino colpito,
  rimbalza sullo scudo, si pianta nel pavimento se manca.
- **Ognuno ha la sua arma**: il Viandante la sua lanterna di ferro o l'arma M8
  che ha in mano (Mannaia di ferro, Picca della tempesta), anche nel colpo che
  ne consuma l'ultimo uso; ghoul gli artigli, balestriere il dardo, bruto la
  mannaia, bombarolo la bomba, custode il pastorale, arcimago il bastone.
- **Il tempo**: il colpo arriva sul disegno d'impatto della clip d'attacco di
  chi colpisce; il dardo parte lì, e la reazione del colpito, il suo segnalino
  e i suoni della Prova aspettano che arrivi. Una carica colpisce quando il
  cartoncino è arrivato, una spinta cede terreno quando il colpo cade. Quello
  che nello stesso battito tocca a chi ha colpito (la risposta delle Thorns, il
  morso del suo Veleno, la sua morte e il suo bottino) aspetta che abbia finito
  il colpo: prima si vede colpire, poi incassare o cadere. Un colpo che
  incontra uno Shield è un colpo solo anche nella corsia del giocatore:
  parata, scudo rotto e ferita partono insieme, con la stella rossa (oro se
  critico). La stella sta al centro del punto colpito, sopra il dardo
  conficcato; su un oggetto, sul lato della sua scatola verso la telecamera.
  Un colpo mai sferrato (un intento interrotto, una mira spezzata, un lancio
  che non parte, una carica parata prima di partire) non ha arma, né attacco
  né schivata: resta solo il MANCATO.

Per questi colpi le armi prendono il posto del taglio rosso generico e del
lampo sulla figura; magie e dispositivi restano come prima. I tavoli 2D
(`--flat`, `--classic`) tengono il taglio e il lampo; anche lì però una carica
colpisce quando è arrivata, e un colpo che incontra uno Shield parte insieme
alla sua ferita. Il runtime è [attack_fx.odin](src/render/attack_fx.odin):
`play_attack_swing`, `play_attack_projectile` e `reflect_attack_projectile`
(che rimanda un dardo al suo tiratore) servono anche a
[Deflect](#deflect-feretro-dado-del-destino-e-lama-velenosa): il dardo deviato
gira quando arriva, la risposta a un fendente è un colpo del Viandante, e la
freccia di Feretro vola come il dardo.

La vita dei nemici è un **cartellino di carta** sopra la testa, tagliato e
inchiostrato come i segnalini: un cuore rosso e `12/18` (la vita sul massimo)
nelle stesse cifre a pixel ([living_heart.odin](src/render/living_heart.odin)).
Resta sempre visibile finché il nemico è sullo schermo: lascia libero l'angolo
del sigillo, sale di una riga sopra un altro cartellino, si sposta di lato
invece di coprire il Viandante e, se la testa finisce sotto il pannello in alto
o sotto il cartello della Prova, scende appena sotto, ma mai oltre i piedi del
nemico: se anche i piedi sono lì sotto, il cartellino resta al suo posto,
coperto con lui. In mezzo alla folla prende il posto libero più vicino al suo;
se non ce n'è, si sovrappone agli altri cartellini dove ne copre meno, ma mai a
un sigillo, a un pannello o a un'etichetta. Il pixel raddoppia quando la
telecamera è vicina. Come il segnalino, il cuore aspetta che il colpo arrivi: finché
un dardo vola o un fendente non è calato, cuore e VITA dell'HUD mostrano ancora
la vita di prima, anche quando il colpo abbatte il nemico (un colpo `LETALE`, una
freccia sull'ultimo punto di vita): il cuore se ne va quando il colpo arriva
([world_playback.odin](src/render/world_playback.odin)). L'ispettore del nemico
sotto il mouse dice lo stesso: vita e status come il tavolo li mostra, quindi
dopo un `Ctrl`+clic lo status della freccia compare anche lì quando arriva.
Prende il posto delle etichette scure sopra i nemici (la piastra nera con `HP 18/18`, la
riga colorata dell'intento come `MUOVE / 2.8s` e la barra rossa): l'intento si
legge da sigilli e terreno, lo scudo dall'anello e dal numero ai piedi, e le
etichette scure restano solo per bombe, micce e uscita. Sui tavoli
senza sigilli (`--flat`, i modi terreno e adesivi di `F6`) l'adesivo
dell'intento sta accanto al cuore. Il riquadro del nemico sotto il mouse
resta visibile anche durante le animazioni e mentre la telecamera scorre con il
mouse fermo; lascia il posto solo alla difesa.

### Dispositivi elettrici e attivazione

| Carta | Energia / cast | Comportamento base |
|---|---|---|
| Shock Floor | 2 / 3 s | pavimento calpestabile, area 3×3, massimo 4 nella stanza; il dado (D4, fino al D20 con gli upgrade) decide sia il numero di scariche sia il massimo di nemici per scarica |
| Tesla Coil | 1 / 2 s | torretta solida da 4 HP, massimo 4 nella stanza; 2–3 nodi creano collegamenti, 4 nodi non allineati possono chiudere un campo |

La **Shock Floor è una trappola passiva**: aspetta senza consumare cariche finché
un nemico entra nella sua area 3×3, anche attraverso una spinta o una carica.
Un teletrasporto controlla solo l'arrivo. Il player non la innesca; una pedana
posata sotto un nemico si innesca al primo beat del mondo. Cast e cinematiche
non fanno avanzare le scariche. Dopo l'innesco, ogni pavimento emette una
scarica per beat del mondo fino a
esaurire il risultato del dado. Con un **3** produce quindi **3 scariche**, ognuna
su **massimo 3 nemici** nell'area. Il danno è **1 per bersaglio** a ogni livello:
il dado non decide il danno e gli upgrade alzano soltanto il dado. Una pedana
tiene al massimo 21 scariche (un 20 del D20 più quella del
[colpo a tempo](#colpo-a-tempo)). Si preferiscono i nemici
più vicini, poi l'ID stabile; pavimento e scariche non feriscono il player.
La sequenza, una volta innescata, procede anche se l'area torna vuota. L'HUD
distingue le pedane in attesa da quelle innescate; non hanno un pulsante attivo.

Il pulsante **ATTIVA**, da cliccare nella barra degli oggetti, riguarda soltanto
una rete Tesla pronta; costa un secondo in Combat se il comando riesce.
Le Tesla emettono un impulso sui collegamenti al clic; non sono muri
invalicabili e non infliggono danno continuo al semplice attraversamento.
I collegamenti rispettano muri, coperture e angoli chiusi. Il danno base di un
collegamento è **`max(1, ceil(8 / distanza))`**, con distanza Chebyshev: 1 cella
→ 8, 2 → 4, 4 → 2, 8 → 1. Raddoppiare la distanza dimezza quindi la potenza,
con arrotondamento per eccesso. Gli upgrade aumentano la potenza iniziale;
fra bobine migliorate la rete usa la potenza massima presente.

Con quattro Tesla il campo usa l'inviluppo convesso, indipendentemente
dall'ordine di posa, se i bordi hanno linea di vista libera. Il danno dell'area
è quello del **bordo più debole**. Il campo colpisce anche il player presente
nell'area; scudo e difesa applicano le regole normali. Una configurazione
allineata o con bordo ostruito resta una rete di soli collegamenti validi.
Ogni bersaglio riceve al massimo un colpo per attivazione. Le torri mantengono
la posizione di posa: le scariche con 2–3 torri non le consumano e richiedono
**3 beat del mondo** prima della successiva attivazione, compreso il tempo
aggiunto da azioni accettate; cast e dadi non accelerano la ricarica. La mega
combo con un campo valido consuma tutte e quattro le Tesla dopo la scarica,
liberando gli slot per una nuova rete. Quattro torri allineate o con campo
ostruito producono soltanto collegamenti e rimangono. Restano danneggiabili
(4 HP): la persistenza non conferisce invulnerabilità.

Preview, overlay e danno interrogano la stessa geometria in
[board_device.odin](src/game/board_device.odin). I dispositivi sono locali al
fight: a fine combattimento vengono rimossi, liberando anche corridoi o uscita
che le bobine avrebbero potuto ostacolare. Una nuova stanza parte senza reti,
scariche o cooldown residui.

### Equipaggiamento, passive e scheda personaggio

Un Brute sconfitto nel tattico lascia una **Mannaia di ferro**: +2 danni agli
attacchi base, **4 utilizzi**. La raccolta magnetica la mette in riserva; un clic
su **EQUIPAGGIA** la inserisce nello slot e conserva l'eventuale arma precedente in riserva con
le sue cariche. Uno scambio riuscito costa 1 secondo in Combat ed è gratuito
nel Loot. Con la riserva piena un'altra arma rimane sul terreno.

Solo un attacco base accettato consuma un utilizzo, anche quando colpisce un
oggetto distruttibile nel Loot. Carte, passi bloccati e attacchi vietati durante
il recupero non consumano cariche. All'esaurimento si torna all'attacco normale.
L'equipaggiamento resta tra stanze della stessa run, ma non viene salvato nel
profilo permanente. La prima versione offre questo drop; altri tipi di arma e
oggetti attivi riutilizzeranno gli slot e il comando di attivazione.

La barra sopra la mano mostra attivazione e dispositivi solo quando presenti,
e arma/usi solo se equipaggiati o in riserva. Nel Loot si sposta in basso.
**ATTIVA**, **EQUIPAGGIA** e **PERSONAGGIO** sono
pulsanti usati **solo con il mouse**. Disegno e hitbox condividono le stesse
coordinate; i comandi disabilitati non cliccano la board. **PERSONAGGIO**
apre una scheda in pausa: modellino **realmente 3D** del player a sinistra,
statistiche a destra, arma, riserva e reliquie esplicitamente indicate come
**passive**. Accanto alle passive, nell'altra metà della riga, il **MAZZO**
elenca le carte della run una riga per carta e livello, a pagine, e mostra il
film di quella scelta ([Mostra effetto](#mostra-effetto)). Il pulsante
**CHIUDI**, in alto a destra, torna al gioco. Il danno mostrato include l'arma.

### Il Ring delle Ombre e gli sblocchi

Quattro Tesla che formano un quadrato perfetto, con almeno 2x2 caselle
all'interno, trasformano **ATTIVA** in **APRI IL RING** quando nel campo ci sono
nemici: le bobine si consumano senza scarica e i nemici dentro (fino a quattro)
salgono sul ring 3D con combattenti pixel ritagliati. Con un solo nemico è il
duello classico; con più nemici è un **tag match**: ne combatte uno alla volta,
gli altri aspettano sul bordo al proprio angolo. Un avversario in difficoltà può
correre all'angolo di un alleato in salute e dargli il cambio con la mano;
un avversario al tappeto lascia il posto al successivo. Il giocatore vince
quando li ha battuti tutti.
Il ring giocato usa ora la simulazione continua M9: `WASD` muovono sul piano,
`1` esegue un pugno, `2` un colpo pesante, `3` una presa ravvicinata,
`Spazio` schiva e `Shift` tiene la guardia. Tempi e collisioni sono descritti
in [M9](#m9-fondazioni-per-le-modalità-libere).

La stanza rimane sospesa e il duello non consuma tempo della board. Le vite
entrano in proporzione: il giocatore porta nel ring la sua percentuale di vita
(su 8 HP), ogni nemico la propria su 12 HP da solo, 9/7/6 HP a testa in un tag
match da 2/3/4 (`ring_opponent_health` in [tag.odin](src/fight/tag.odin)).
**Vittoria**: tutti gli sfidanti sono sconfitti e lasciano il loro bottino.
**Sconfitta** o **Abbandona**: il giocatore perde un quarto della vita massima
(mai l'ultimo punto), i nemici tornano sulla board con le ferite subite nel
ring e quelli messi al tappeto restano a terra. Intro, pausa e risultati sono
gli stessi del catalogo. Dal menu sono possibili riprove e record, ma nessuno
sblocco M8. Sul pad: stick muove, X pugno, Y pesante, RB presa, A schiva,
LB parata; B/Start restano alla pausa della shell. Dal menu il campione ha
12 HP, con le stesse mosse e gli stessi tempi.

| Traguardo persistente | Sblocco |
|---|---|
| Prima vittoria | **Titan Grip**: 2 energia / 3 s, 3 danni, spinta di 2 celle e Stagger |
| Terza vittoria | **Storm Crown**, ricompensa leggendaria: 3 energia / 4 s, 5 danni su fino a 3 nemici collegati |

Al raggiungimento del traguardo viene aggiunta una copia se il mazzo ha spazio.
Lo sblocco resta valido anche con mazzo pieno e abilita la carta nelle future
ricompense, nello Shop e nell'Armory; prima del traguardo è esclusa dalle offerte.
Storm Crown usa il peso economico Rare e un vincolo di sblocco leggendario.
Le vittorie vengono salvate in **`odin_pp_profile.json`**, nella directory di
avvio, tramite scrittura su file temporaneo e rinomina. Il launcher avvia dalla
radice della repo. Il profilo è versionato e validato; un file invalido viene
preservato e disabilita il salvataggio della sessione, con messaggio esplicito.
Questo è un salvataggio degli sblocchi, non della run in corso.

### Direzione grafica e perimetro della milestone

Gli attori mantengono i pixel e ricevono un bordo spesso avorio/nero, ricavato
dall'alpha reale con limiti dell'atlante. Il contorno ha una piccola oscillazione
indipendente: dilatazione esterna di 8 pixel sorgente e interna avorio di 6,
con un minimo nel mondo 3D di **4 pixel canvas esterni e 3 avorio**, così
player e tutti i nemici mantengono un contorno evidente anche quando piccoli.
Il ring conserva lo spessore sorgente 8/6; l'ologramma usa un bordo compatto
1,25/0,85 pixel canvas per non nascondere celle e marker. Il quad espanso e lo
shader usano gli stessi raggi. Il renderer classico/flat resta invariato.
L'oscillazione è in quattro passi distinta dalla clip interna; le clip d'azione sono quantizzate
in quattro pose. Si conservano corpi 2D, profondità 3D, blocchi plastici blu scuro
e HUD pixel. Dispositivi e campo hanno geometrie e rune dedicate, senza nascondere
la griglia o mostrare nemici coperti dalla fog.

Il ring introdotto in M8 converge nella scena condivisa basata su `fight`: la
vecchia simulazione laterale e il suo overlay sono rimossi. Il catalogo include
platform 2D/3D, arena a ondate, Cripta FPS, puzzle e ring; un
picchiaduro 3D più articolato resta una direzione futura. Non sono presenti una raccolta di
minigiochi completa, ruote, un inventario esteso di consumabili o un
salvataggio/ripristino della run. Bilanciamento delle reti, durata dei cast e
difficoltà delle sfide richiedono ancora partite umane.

## M9: fondazioni per le modalità libere

M9 aggiunge quattro incrementi giocabili alla base **0.4**: arena senza
griglia, ring con mosse e collisioni, una prova FPS e strumenti per sviluppare
questi contenuti. Non modifica pulse, cast, dadi, fog o regole del classico/M7.

```sh
./run.sh --engine-lab
./run.sh --ring-lab
./run.sh --fps-lab
./run.sh --smoke-m9-view
```

Nella run, **SFIDA RING** e **CRIPTA DELLE RUNE** aprono le scene canoniche
del catalogo durante Loot, a presentazione conclusa. **SFIDA EXTRA** offre
una delle cinque prove storiche per oro, preservando la scelta degli stessi seed.
Il laboratorio è disponibile solo da CLI. L’attività possiede input e tempo
fino al ritorno tramite la shell. Stanza,
salute, carte, RNG e pulse della run rimangono sospesi. Il frame di chiusura
consuma anche il clic, impedendo che arrivi alla board.

Soltanto **SFIDA RING** dalla stanza può assegnare i traguardi M8, una
volta per tentativo. Cripta libera, arena libera, ring del catalogo e tutti i
laboratori M9 avviati da CLI sono pratica: non scrivono vittorie del ring nel
profilo M8 e non sbloccano carte. I minigiochi del nuovo menu hanno record
separati nel profilo dell'engine. Cambiare modalità nel laboratorio conserva questa distinzione.

### Arena libera, corpi e tempo

`engine` gestisce posizioni continue **X/Z con i piedi a Y=0**. I corpi sono
capsule verticali; il movimento usa il loro cerchio orizzontale contro solidi
AABB e altri personaggi. I test lungo l'intero spostamento impediscono di
attraversare ostacoli sottili, mentre lo scivolamento permette di seguire una
parete. Sprite, contorno illustrato e collider hanno dimensioni indipendenti.
Raycast, layer World/Actor/Trigger e volumi evento sono condivisi fra le modalità.

La simulazione procede a **60 tick al secondo**, indipendentemente dal
rendering interpolato. Un frame recupera al massimo **8 tick**; un blocco più
lungo scarta il tempo eccedente e lo registra in `dropped_seconds`. Pausa e
perdita del focus svuotano tempo frazionario e input pendenti: la ripresa non
scarica azioni arretrate. Dopo una perdita del focus è richiesta una ripresa
esplicita. Il clock dei minigiochi non alimenta quello del tattico.

L'arena libera parte nel cortile con pilastri e un avversario fermo. Con
**LIVELLO** si passa alla galleria con coperture; **CAMBIA AVVERSARIO** attiva
o disattiva l'IA. I corpi vengono registrati nuovamente a ogni cambio livello.

### Ring 1v1

| Input | Azione |
|---|---|
| `WASD` mantenuti | movimento continuo X/Z; diagonali normalizzate |
| `1` | pugno rapido: 1 danno |
| `2` | colpo pesante: 2 danni, maggiore portata e spinta |
| `3` | presa ravvicinata e lancio: 3 danni |
| `Spazio` + direzione | schivata; senza direzione arretra |
| `Shift` mantenuto | guardia frontale e movimento rallentato |
| `Esc` / **PAUSA**, **RIPRENDI** | sospende/riprende la modalità |
| clic su **TORNA** | ritorna alla stanza oppure chiude il laboratorio CLI |

Ogni mossa definisce startup, fotogrammi attivi, recupero, volume del colpo,
danno, spinta, stordimento, hit-stop e finestre di concatenazione. La mossa
iniziata conserva una copia dei dati: modificarla nel laboratorio ha effetto
dal prossimo attacco. Un colpo può danneggiare ciascun avversario una sola
volta; le concatenazioni del pugno richiedono un contatto e la finestra prevista.

Body, hitbox e hurtbox sono separati. La guardia blocca i colpi frontali;
la presa la supera. La schivata rende invulnerabili soltanto nei fotogrammi
attivi e non attraversa i corpi. Colpi e prese rispettano la linea di vista
fra i personaggi, anche quando la portata è aumentata dal laboratorio.
L'IA alterna colpi pesanti annunciati e pugni, con aperture sfruttabili.

Il lancio coordina due personaggi in **quattro pose da 18 tick**: aggancio,
sollevamento, lancio e impatto. La sequenza occupa 72 tick di simulazione
(1,2 s), oltre alla breve pausa d'impatto. Il danno arriva una sola volta e
l'eventuale vittoria attende l'ultima posa. La destinazione si ferma al primo
contatto con un ostacolo; l'arco verticale è una posa visiva, non un salto
fisico. L'hit-stop ferma la simulazione del ring; un input breve può essere
conservato nella finestra di concatenazione, senza accodare mosse durante
l'intera presa.

### Prova FPS

La prova offre due stanze selezionabili, **Navata** e **Cortile**, con tre
nemici, coperture e pilastri. Si vince eliminando i tre avversari; la salute
parte da 100 ed è indipendente dalla run. Il movimento è relativo alla visuale,
con collisioni degli stessi servizi dell'arena libera.

`WASD` muovono, il mouse mira, il tasto sinistro mantenuto spara, `R` ricarica.
L'arma ha **6 colpi nel caricatore e 30 di riserva**, danno 12, intervallo
fra colpi di 0,24 s e ricarica di 1,2 s. I raycast colpiscono il primo corpo o
solido: i nemici non possono essere colpiti attraverso le pareti. Gli avversari
annunciano il tiro, conservano il punto mirato e attraversano un recupero.

L'FPS entra in pausa. Il pulsante centrale **CLICCA QUI PER GIOCARE**, oppure
**RIPRENDI** in alto, avvia la simulazione e cattura il mouse; `Esc`, perdita del focus,
esito o uscita lo liberano. Il clic usato per riprendere non spara
automaticamente: occorre rilasciare il pulsante prima del primo colpo.

### Laboratorio e contenuti modificabili

I laboratori CLI mostrano gli strumenti azionabili con
il mouse: selezione Arena/Ring/FPS, reset, livello, collisioni, pausa e
avanzamento di **1 TICK**. Il ring mostra anche hitbox e hurtbox. Il pannello
delle mosse seleziona pugno, pesante o presa e modifica startup e danno;
variando lo startup sposta anche la finestra di concatenazione, conservandone
la posizione relativa al recupero. Le altre proprietà sono già dati
strutturati nel package `fight`.

**SALVA MOSSE** scrive `odin_pp_moves.json` nella directory di avvio, usando
un file temporaneo e rinomina;
**CARICA** valida versione, dimensione e tutte le definizioni prima di
sostituire il set. Dati corrotti o finestre di concatenazione incompatibili
vengono rifiutati senza modifiche parziali. Questi preset sono strumenti di
pratica: una sfida della run parte con le mosse normali.

**REGISTRA / FERMA REC** conserva lo stato iniziale e gli input di ogni tick.
**REPLAY** ripristina quello stato, ignora i comandi di combattimento dal vivo
e va in pausa al termine. La registrazione rimane **in memoria**, fino a
18.000 tick (5 minuti), e non sopravvive a una nuova sessione o al cambio
di modalità. Non è un replay salvato su disco né una registrazione della run.
Durante registrazione/replay i controlli che cambierebbero contenuti o modalità
sono disabilitati. Pausa, esecuzione al singolo tick e replay condividono il
medesimo percorso di simulazione.

Il controller continuo di questi laboratori resta sul piano X/Z; i nuovi
platform usano invece `engine/physics`, con movimento verticale, gravità e
mappe tile/voxel. Sono due domini distinti: le capsule e le collisioni fra
attori del ring non vengono sostituite dai collider AABB dei platform. Non
sono presenti un editor generale di livelli, corpi rigidi dinamici o un
picchiaduro completo con catalogo di combo e personaggi.

## Modalità tattica M7

La demo avvia **M8 / 0.4**, costruita sul loop M7: scena 3D con sprite 2D,
fog locale, timer, recupero mobile di un secondo e QTE. Le regole qui sotto
sono aggiornate al cast M8; le note cronologiche M7 sono nella roadmap.
`--classic` mantiene il loop
precedente per i confronti. Le sezioni dei sistemi descrivono i contratti
condivisi; le differenze del nuovo ciclo sono raccolte qui e nella roadmap.

```sh
odin run src -o:none
odin run src -o:none -- --decision-time=15 --vision=2
odin run src -o:none -- --vision=9
odin run src -o:none -- --orthographic
odin run src -o:none -- --flat --no-fog
odin run src -o:none -- --classic
```

| Opzione | Valore / funzione |
|---|---|
| `--decision-time=20` | budget iniziale in secondi, default 20; ammessi 1–60 |
| `--vision=7` | lato della vista locale; default 7×7 (raggio 3), ammessi 2, 3, 5, 7 e 9 |
| `--no-fog` | vista completa per confronto e diagnostica |
| `--qte-time=1.2` | finestra QTE in secondi, default 1.2; ammessi 0.2–5 |
| `--flat` | proiezione isometrica 2D mantenendo il gameplay tattico M8 |
| `--perspective` / `--orthographic` | prospettiva 3D predefinita oppure proiezione ortografica |
| `--classic` / `--m7` | loop classico / tattico corrente M8; `--m7` resta un alias compatibile |
| `--smoke-m7` | confronto headless riproducibile, senza aprire finestre |
| `--smoke-m7-view` | prova grafica di scena, oggetti 3D, fog, ologramma, QTE e menu |
| `--smoke-m8-view` | prova 3D di d4, dispositivi, offerta del ring, equipaggiamento, scheda personaggio, tag match e cambio stanza |
| `--smoke-western` | nuvoletta 6 RANCH 7: apertura automatica, volo delle carte, insegna, porte, corsa a tempo e premio |
| `--smoke-mechanics-lab` | Prova meccaniche: arena aperta, mano con tutto il mazzo in prova (dieci carte sovrapposte, larghe come in una mano piena di otto, ognuna con tutte le parole della faccia, l'icona, i segni e il tasto in vista prima della successiva, nella mano come la dà e in qualunque ordine, e trovata dal puntatore, quella alzata intera dentro il canvas; ogni parola di ogni sua carta, a ogni livello, misurata con il font del gioco sulle carte da 109 pixel della mano, la Canna sul suo slot, e nell'ispettore: ogni riga ci sta senza stringere le lettere, rimpicciolirsi o tagliarsi, nessun nome tagliato; Pinball e First Person Shooter anche sulle carte più larghe del gioco, mani da cinque e sei, negozio e ricompense), ring riaperto, arrivi fino al massimo, ultima uccisione senza fine del combattimento, cartoncino del giocatore di nuovo in piedi dopo morte e riavvio, cartoncini vivi (un passo e un attacco fotogramma per fotogramma), cerchi d'azione e segnalini di danno e cura, gli status a stack (Veleno, Bruciatura e Rallentamento su un nemico, Bruciatura e Veleno sul giocatore: etichette di carta ai piedi, nomi e stack nell'HUD e nell'ispettore del nemico, `odin_pp_living_statuses_NN.png` e `odin_pp_mechanics_lab_statuses.png`; la finestra che scade subito dopo li fa bruciare), i suoni che ogni azione mette in coda (passo, colpo, ferita, caduta, cura, status, battito, stordimento: senza dispositivo audio, li conta) e infine un Movimento Ombra giocato dalla mano: finestra e clock del mondo fermi per tutta l'ombra, quattro passi dell'ombra con una diagonale sul suo primo battito, risalita sull'ultima casella dell'ombra, nessun passo del Viandante fra i suoni e tutti quelli dell'ombra (carta, sprofondare, passi, CRITICO, battiti, risalita); per finire ogni colpo uno alla volta, con la sua arma di carta: il dardo nel Viandante e nel pavimento, il fendente del bruto sulle tre caselle e la sua carica colpita all'arrivo, gli artigli del ghoul, il pastorale, il bastone, la bomba del bombarolo, la brace dell'arcimago su un barile e i colpi del Viandante con la lanterna e con le due armi M8 (ogni arma deve comparire); ultimo, il Rallentamento sul sigillo: un bruto rallentato di 2 compie il passo già annunciato, poi annuncia il prossimo intento 2 secondi più lungo (due tacche in più) e, compiuta quell'azione, perde uno stack e trattiene il successivo di un secondo solo; infine Pozza di Veleno e Incendio dalla mano: un anello di pozze chiuso dall'ultima, che allaga l'area (otto celle da 2 Veleno) e avvelena una volta sola il chaser rimasto dentro, un chaser che attraversa due pozze schizzando e prendendo 2 Veleno a ogni cella, il Viandante che entra in una pozza sua senza prendere niente, un fuoco accanto a un bruto che allunga i bracci per quattro finestre, lo prende alla seconda (Bruciatura 1, che morde dalla terza), brucia la casella del Viandante senza segnarlo e si spegne alla quinta, con i suoni delle carte, dello schizzo e del fuoco che si allarga e si spegne; ultime le cariche del Viandante: Deflect su un dardo (lo stesso dardo torna nel balestriere), su un fendente e su una carica (risposta con la lanterna), mai con la scelta di difesa, il Viandante illeso e fermo e l'attaccante con i 3 del colpo, Feretro con `Ctrl` (segnato il nemico sulla linea di tiro, non quello dietro una copertura, su cui il clic non scocca niente) e una freccia da 1 s scoccata dal clic, con 1 danno e uno status, il Dado del Destino su tre urti (un d4 che fa BRUCIATURA 2, una nuova giocata che riporta gli urti a 3, un d20 che fa LETALE e lo stesso 16 che sul Custode è solo un CRITICO) e Lama Velenosa con il suo dado e l'urto avvelenato (con tre cariche in più, i chip dell'HUD: ogni parola intera, il d20 di DESTINO compreso), con i suoni delle carte, delle cariche, del colpo rimandato, della freccia e del dado; per ultimo il Lazzo: a quattro celle dal muro ovest il raggio è 3 (una cella più in là sarebbe 4), il mirino (i nemici che prende, i tre fermi sull'anello, il Custode `TROPPO PESANTE`, che né la regola né la carta prendono), il lancio su un nemico a quattro celle tirato dentro sull'anello e il giro con il mondo che continua: colpi 1, 2 e 3 sui nemici fermi a nord, a sud e a nord-est, spinti di 1, 2 e 3 celle e feriti di 1, 2 e 3 come il nemico in volo, la vita di questo controllata a ogni fotogramma (meno i colpi, meno 1 a ogni giro intero), un balestriere libero che mira e tira al perno (la scelta di difesa si apre, il colpo passa, la corda tiene) e la caduta al dodicesimo giro, con la riga dell'HUD sul giro intera con la finestra fissa e con quella che si accorcia; poi raggio 1 accanto al muro, con gli schianti, ognuno col suo numero solo sul nemico in volo e il giro che torna indietro a ogni schianto, e una schivata che lo lascia andare (atterra sotto di sé e annuncia subito un intento nuovo, senza stordimento, e il suo cartoncino cade con `MOLLATO` mentre la schivata si vede), con i suoni della carta, del lancio, della stretta, dei giri, dei colpi, degli schianti e della corda mollata; poi il Pinball: il mirino sul balestriere accanto (i mirini d'acciaio e la partenza della palla, girata di 30 gradi dal flusso della stanza fissato) e sul Custode `TROPPO PESANTE`, che né la regola né la carta prendono, il bruto a due celle fuori portata, il colpo (3 di energia, il Veleno del balestriere sparito, mondo e palla fermi per tutto il cast, la lanterna sulla palla quando il cast finisce) e i 20 secondi della corsa: i tre ghoul in fila presi per 2, 3 e 4 e spinti di una cella, poi il muro nord che riporta 5 a 2 (la telecamera allontanata per la corsa), e per tutta la corsa ogni nemico ferito del valore di quel momento, uno in più a ogni colpo, ogni cosa solida che lo riporta a 2, ogni spinta di una cella via dalla palla e una stella sul tavolo per ogni contatto; a ogni fotogramma il disco fuori dalle caselle solide, la direzione unitaria e la vita del balestriere intatta, mentre un colpo, uno status, una freccia o una carta su di lui sono rifiutati; la palla che rotola sopra il Viandante senza ferirlo, un suo passo durante la corsa, i battiti del mondo uno al secondo, il chip dell'HUD intero anche con un valore di due cifre; lo scoppio nel fotogramma dei 20 secondi, con il balestriere che cade lì con il suo bottino e senza fantasma del cartoncino, con i suoni della carta, del colpo, dei muri, dei respingenti e dello scoppio; poi First Person Shooter: le sue parole a ogni livello, la giocata su di sé (3 di energia, nessun secondo di finestra, 20 secondi, niente cast), una carta, un Refocus e una freccia rifiutati, la discesa negli occhi (il cartoncino del Viandante nascosto, la mano scivolata via), un secondo di grilletto a 60 fotogrammi: 6 colpi nel ghoul da 1 danno l'uno, la finestra e i secondi della vista più corti solo del tempo passato, nessun morso del Veleno, né lanterna né ferita fra i suoni; un colpo fermato dal blocco di ghiaccio (il balestriere dietro intatto) e uno dal muro del bordo, i passi `WASD` secondo la vista con l'occhio che scivola, l'urto e la schivata, la scelta di difesa dietro gli occhi con i secondi fermi, i bordi rossi di una ferita, un colpo nel recupero, la fine dopo una ventina di battiti con la risalita e il mouse libero, una copia +5 da 30 secondi e il tavolo piatto che diventa 3D e torna piatto, con i suoni della carta, della discesa, dei colpi, delle ferite, dei colpi sulla pietra e della risalita; infine la Canna da Pesca: `F7` libera l'arena (due nemici fermi cadono e si apre lo slot con `PESCA 1/1`), la canna presa dallo slot e lasciata su una casella a due celle pesca lì (lancio, galleggiante sull'acqua nuova, abboccata, un pesce tirato fuori che vola al Viandante, il suo d4 a 3 e 3 di vita, l'acqua sul tavolo 3D e su quello piatto), poi la pesca della stanza è finita; potenziata a +1, `F7` di nuovo dà una stanza nuova senza acqua e con due pesche (`PESCA 2/2`): dall'acqua esce una carta, mai un'altra canna, che entra nel mazzo, poi la stessa acqua (nessuna casella nuova) dà un pane per il 2 del suo d4 e le pesche finiscono, finché un altro `F7` le ridà tutte e due; per ultima nessuna di 400 offerte porta una seconda Canna a chi ne ha già una, mentre senza di lei ne arrivano, con i suoni della carta al lancio, del tonfo, dell'abboccata, del mulinello, della preda presa e della carta pescata |
| `--smoke-effect-window` | [Mostra effetto](#mostra-effetto) nella finestra vera, sulla run della sessione: il costo del fotogramma (il tavolo da solo, poi la finestra aperta a 60 fotogrammi al secondo sui film di Strike, Pinball, Incendio e First Person Shooter: più di un fotogramma su cinquanta in ritardo lo fa fallire); ogni ingresso, cioè l'ispettore con il tasto e con il pulsante (spento, e senza richieste, in Movimento Ombra), il MAZZO della scheda alla seconda pagina con una riga scelta (`Esc` chiude la finestra e non la scheda), lo slot della Canna, la ricompensa, l'offerta e la carta posseduta del negozio e il riposo, ognuno con la carta giusta, la run ferma a finestra aperta e un primo fotogramma senza tempo né clic dopo la chiusura; le chiusure con `Esc`, clic destro e CHIUDI, RICOMINCIA, la finestra a 1600x900, 960x540 e 1280x720 (lì lo stage 1:1); una ripresa di Strike come nella Prova meccaniche, con i suoi suoni; poi una ripresa intera di ogni carta, al livello 0 e al più alto, attraverso la finestra (l'effetto mostrato nel suo tempo, nessun errore della timeline, la run ferma, a ogni fotogramma una didascalia che sta nella sua piastra senza coprire niente, il guanto sullo stage, nessun suono fuori dalla Prova, il cursore mai nascosto); infine ogni parola nuova misurata con il font del gioco nel suo spazio e il costo dei film. Circa dieci minuti; `-define:EFFECT_SMOKE_CARDS=,Strike,Pinball,` filma solo quelle carte, `--flat` le filma sul tavolo piatto |
| `--smoke-m9-view` | arena continua, duello con IA, presa in quattro pose, replay e FPS con ricarica e vittoria |

Gli smoke classici e i laboratori `--spell-lab` / `--dice-lab` conservano il comportamento classico;
gli smoke `m7` esercitano il loop tattico aggiornato a M8.
Gli sprite esterni continuano a usare `--sprites`: nella scena 3D M7 sono
riservati ai personaggi; ghiaccio, barili, bombe e fuoco sono mesh a blocchi.
La vista classica conserva anche gli sprite personalizzati degli oggetti.
Le miniature dell'ologramma sono mesh procedurali separate dagli sprite degli attori.

HUD e carte conservano avorio, nero e cremisi, pergamena e cornici a gradini.
L'ambiente usa invece nero, grigio e blu: pareti scure, blocchi smussati,
grana fine e riflessi lucidi che cambiano con la camera. Nessun fondale o
torre decorativa circonda la stanza: il livello emerge da un vuoto nero uniforme.
Le carte usano il nuovo atlante `card-icons-pixel.png`, con sagome semplificate
e pixel più grossi. Reliquie, ricompense, mercante, riposo, eventi, tesori,
mappa della rotta e schermate terminali condividono font, palette e cornici.
Il font pixel **Jersey 10** è incorporato nel binario insieme agli atlanti:
non servono download o una directory di avvio particolare. Texture e canvas
M7 usano il filtro nearest; `F2` sceglie lo scaling intero per pixel uniformi,
mentre `F1` adatta la scena alla finestra. Licenza e provenienza del font sono
in [assets/fonts](assets/fonts/README.md); i prompt delle illustrazioni sono
in [assets/gothic/generation-prompts.md](assets/gothic/generation-prompts.md).
La mappa ha una griglia cremisi, miniature 3D illuminate e una legenda con
player, melee, ranged, miniboss, boss e uscita.

La revisione della scena usa il renderer OpenGL 3D di Raylib: pavimenti a volume,
muri con altezze e cornici, illuminazione direzionale e locale, profondità reale
e sprite billboard 2D per i soli personaggi. Oggetti, coperture, trappole,
portali sono costruiti da blocchi 3D; gli oggetti si selezionano sul
loro volume anche dopo una rotazione. La parallasse deriva dalla camera
prospettica e dalle geometrie. I muri in primo piano si abbassano per lasciare leggibile il player.
Durante Combat la fog non memorizza celle visitate e nasconde anche ciò che si trova dietro
muri/ostacoli; solo l’ologramma mostra l’intera stanza. La base scura fuori dalla
vista è composta da blocchi opachi di nebbia, identici per qualsiasi terreno
nascosto: non rivela altezze dei muri, oggetti o celle esplorate in precedenza.
Minacce e aree di esplosione sono disegnate sul pavimento 3D visibile;
le bombe mostrano i pulse rimasti prima della detonazione.

Alla fine del fight, dopo la scomparsa dell'ultimo nemico nella timeline, la
fog si apre sulla stanza e la luce fredda aumenta con una transizione di
1,2 secondi. Loot e portale ricevono marcatori discreti; in BOTTINO l'HUD
mostra movimento libero, senza countdown. Il nuovo Combat ripristina subito
la luce e la visibilità locale, anche riutilizzando renderer e Room. La
transizione usa il tempo della presentazione e non modifica pulse, timer,
RNG o regole dell'ologramma. I blocchi hanno ombre di contatto corte sul
pavimento, senza una shadow map aggiuntiva.

La vita di ogni nemico è un cuore di carta sopra la testa, l'intento un sigillo
e il terreno ([Il tavolo](#il-tavolo-cartoncini-vivi-cerchi-e-segnalini)); cuori,
sigilli, micce, annunci delle bombe e segnalini usano lo stesso posizionamento
per evitare sovrapposizioni fra testi.
Gli indicatori degli status mantengono la propria zona sul terreno. Bruciatura
e Rallentamento sono etichette di carta in pixel art sotto i piedi, ritagliate e
inchiostrate come i cuori (una fiamma, una clessidra e i loro stack), in fila
sotto i dischi degli status più vecchi; con i cuori raddoppiano il pixel quando
la camera è vicina. Le etichette restano dentro la zona della scena e usano un
collegamento sottile quando devono spostarsi. L'HUD tiene gli status separati
dai contatori; l'ispettore del nemico ne elenca nomi e stack (o potenza e secondi).

Le prime due profondità della rotta restano compatte: Combat **17×11**, quattro
nemici e spazio sicuro centrale. Dal terzo livello superficie, coperture e
composizione crescono a fasce: fino a **41×29 / 16 nemici** nei Combat avanzati
e **45×31 / 22 nemici** per il boss finale. La crescita segue la profondità della
rotta, anche passando dai nodi speciali. Le statistiche individuali conservano
le curve precedenti; cambiano numero, varietà e distribuzione delle squadre.
Vedi [progressione delle arene](#progressione-delle-arene-tattiche) per la tabella.

La camera segue il player senza allontanarlo nelle stanze grandi; la mappa
olografica inquadra invece tutta la superficie al reset. Lo zoom manuale resta
libero. Il renderer scarta solo geometria sicuramente fuori schermo, senza
alterare fog, luce, minacce o picking; la fog continua a non memorizzare celle.

La mano M7 è una fila senza sovrapposizioni: fino a otto carte completamente
visibili, con energia richiesta, bersaglio/raggio, effetto, durata del cast in
secondi e stato di disponibilità. Hover e selezione aprono un pannello di
dettaglio, con il tasto `I` e, a carta scelta, il pulsante **MOSTRA EFFETTO**
([Mostra effetto](#mostra-effetto)); con sette–otto carte il titolo e
l'illustrazione adottano un layout compatto; eventuali testi troppo lunghi
terminano con puntini e restano nel dettaglio. Nel gioco la mano non supera mai otto carte (`MAX_HAND_CARDS`); solo
regole che ne danno di più tutte insieme, come le dieci della Prova meccaniche,
le tengono, e allora le carte si sovrappongono su tutta la larghezza del canvas,
a 8 pixel dai bordi: restano larghe come in una mano piena di otto e ognuna
resta in vista quanto serve perché la successiva copra solo carta: ogni parola
della sua faccia (nome, righe, raggio), costo, tempo, l'icona intera (spostata
nella parte in vista), i segni della rarità (sotto il tempo) e il tasto,
misurati con il font del gioco a ogni fotogramma; lo spazio che avanza si divide
fra tutte e l'ultima resta intera. Quella sotto il mouse, o altrimenti la carta
mirata o scelta, si alza di 8 pixel e si disegna intera sopra le altre, e il
puntatore la trova nella sua striscia anche mentre si alza
([tactical_hand.odin](src/render/tactical_hand.odin)); `9` e `0` giocano la nona
e la decima, mentre i menu restano su `1`–`8`. Le carte le cui righe lì si
rimpicciolirebbero o si taglierebbero ne hanno una forma corta (Shock Floor,
Tesla Coil, Movimento Ombra con `OMBRA 4s` / `MONDO FERMO`, Pozza di Veleno,
Incendio, Deflect, Feretro, Dado del Destino, Lama Velenosa, Lazzo, Pinball e
First Person Shooter) e quelle il cui nome lì si taglierebbe un nome corto
(`Ombra`, `Pozza`, `Dado`, `Lama`, `FPS`; l'ispettore tiene il nome intero), che
dicono anche sulle carte più larghe (mani da cinque o sei, negozio, ricompense)
dove il nome intero, con il suo `+n`, non ci starebbe così com'è alla sua
misura: First Person Shooter è `FPS` su ogni carta della mano e dei menu,
`Movimento Ombra` diventa `Ombra` dove si stringerebbe: la Prova meccaniche
tiene in mano dieci carte, tutto il suo mazzo tranne la Canna da Pesca, che non
viene mai in mano (anche lei ha la sua forma corta, `Canna`, per uno slot più
stretto su un canvas più piccolo). Le sue carte sono larghe 109 pixel sul canvas
di 960, e il suo smoke misura con il font del gioco ogni parola di ogni carta
del mazzo a ogni livello che può raggiungere, sulla carta della mano (la Canna
sul suo slot) e nell'ispettore: ogni riga ci sta così com'è, senza stringere le
lettere (stretto, il font di pixel le attacca: `CTRL+CLIC` si leggerebbe
`CTRL+CUC`), rimpicciolirsi o tagliarsi, e nessun nome si taglia (solo con il
`+n` di un upgrade può stringersi o scendere di una misura); controlla anche che
di ognuna delle dieci carte si vedano tutte le parole, l'icona e il tasto prima
della successiva, nella mano come la dà e in qualunque ordine possa prendere,
che il puntatore trovi ognuna e che quella alzata resti dentro il canvas;
Pinball e First Person Shooter li misura anche sulle carte più larghe del gioco.
Le carte difensive indicano anche i QTE che abilitano. Le carte restano nella
loro posizione durante la selezione. Il catalogo tattico ora distingue mobilità
protetta, interruzione, ricognizione e contrattacco; rarità, lifetime e regole
di costruzione del mazzo restano condivisi. Il bilanciamento numerico è una
prima proposta giocabile, ancora da provare in run.

Il rework dei nemici si applica al gameplay M7; il classico resta disponibile
come confronto:

- **Bombaroli:** preparazione di 4 secondi, poi rilascio dopo 1 secondo sulla cella annunciata,
  senza inseguire il nuovo bersaglio. Una sola bomba nemica attiva o in preparazione
  nella stanza, miccia di **3 secondi**, **3 danni** e almeno **2 secondi di recupero**.
  I nemici rinviano il lancio anche se è già presente una bomba del player.
  Spostare il lanciatore dopo l'annuncio fa fallire il lancio. Le bombe del
  player conservano miccia di 2 secondi e 4 danni; non subiscono questa riduzione.
- **Inseguitori:** il percorso tiene conto di fuoco, trappole e zone di esplosione;
  i pericoli hanno un costo, non diventano muri invalicabili. Dopo ogni attacco,
  anche mancato, recuperano per un secondo. La cadenza normale è di 2 secondi.
- **Arcieri:** cercano una linea di tiro libera a distanza 2–5, arretrando
  quando necessario. **3 secondi per mirare/muovere**, rilascio sulla cella fissata dopo 1 secondo, poi recupero 1 secondo.
  La mira non infligge danno e non apre QTE; durante il tiro si possono usare le
  normali difese. Spostarli o stordirli interrompe il tiro. Da adiacenti e senza
  vie di fuga possono colpire per un solo danno.
- **Bruti:** cadenza di 4 secondi; il fendente adiacente copre tre celle frontali; recupero 1 dopo
  il fendente e 2 dopo la carica, anche mancata. Colpi e cariche possono
  spingere di una cella, attivando i pericoli
  della destinazione. Uno scudo che assorbe tutto il danno impedisce la spinta;
  le cariche ammettono le difese QTE abilitate da carte e condizioni.
- **Custodi:** agiscono ogni 3 secondi, proteggono gli altri archetipi con 2 Shield per 2 secondi,
  poi recuperano per 2 secondi. Non possono creare catene di protezione fra custodi.
  Spostarli, spezzare la linea di vista o stordirli annulla la protezione annunciata.
- **Boss:** cadenza normale di 4 secondi; conserva fasi, cariche e bombe, ma recupera almeno 1 secondo dopo
  un attacco e almeno 2 dopo carica/lancio. Può essere interrotto con Heavy Blow.
  Il Demolitionist può accendere un barile che minaccia il player, oltre a
  caricare e bombardare; il bersaglio annunciato non viene sostituito se spostato.

Gli avvisi sul pavimento sono leggibili anche quando il lanciatore è fuori
vista: segnalano l'impatto nella zona visibile senza scoprire il nemico.
Mira, preparazione, lancio, recupero, fendente, carica e protezione hanno
pittogrammi e colori distinti nei sigilli e sul terreno. L’hover su un nemico
visibile ne scrive l'intento con i secondi rimasti (`MUOVE / 2.8s`), il ruolo e
come rispondere.
Lo stordimento nasconde le minacce dell’intento interrotto, ma non disinnesca
esplosivi già presenti. Questi valori sono un primo bilanciamento da provare durante le run,
anche mentre il player si muove durante il recupero.

Il rework carte M7 usa lo stesso catalogo effettivo per costo, targeting, effetti,
mano, mercante, ricompense, upgrade e timeline. Il costo energetico resta distinto
dal **costo temporale**, centralizzato in `game/tactical_action_cost.odin`:

| Azione | Costo temporale / durata del cast |
|---|---:|
| Passo, attacco base, attesa, schivata attiva, tentativo diagonale, freccia di Feretro | 1 s |
| Refocus | 2 s |
| Clic su **ATTIVA** o **EQUIPAGGIA** in Combat | 1 s |
| Supporto, Guard, Afterimage, Battle Focus, Spark, Pozza di Veleno, Deflect, Feretro, Dado del Destino, Lama Velenosa | 1 s |
| Strike, Arc Bolt, Shove, Dash, Grappling Hook, Venom Needle, Fate Strike, Tesla Coil, Incendio, Lazzo (il lancio; il giro sta sul tempo del mondo), Pinball (il colpo; la corsa sta sul tempo del mondo) | 2 s |
| Piercing Ray, Cross Slash, Heavy Blow, Sundering Blow, Twin Venom, Shock Floor, Titan Grip | 3 s |
| Firebomb, Toxic Wave, Caustic Bloom, Chain Lightning, Prismatic Barrage, Storm Crown | 4 s |
| [Movimento Ombra](#movimento-ombra) | 0 s: i suoi 4 s reali stanno fuori dalla finestra |
| [Canna da Pesca](#canna-da-pesca) | 0 s: pesca a stanza liberata, dove non c'è finestra |
| [First Person Shooter](#first-person-shooter) | 0 s: i suoi 20 s sono del mondo e i colpi dell'AK non costano tempo |

Le carte mostrano la durata `Ns`: il cast spende quei secondi una sola volta,
progressivamente, e ferma il mondo. Movimento Ombra mostra `0s`: non ha cast, la
carta di rimpiazzo arriva subito e la finestra resta ferma per tutta l'ombra.
Le altre azioni sottraggono subito il costo aggiuntivo e possono far maturare
beat. Anche Spark a energia zero costa tempo.
La schivata base rimane accessibile fuori recupero, senza richiedere carte.

| Carta M7 | Energia | Effetto base / ruolo |
|---|---:|---|
| Strike | 1 | 3 danni; **+2** contro un nemico in recupero o stordito |
| Arc Bolt | 1 | 2 danni, tiro economico |
| Piercing Ray / Cross Slash | 2 | 3 danni in linea / a croce, nelle celle visibili |
| Guard | 1 | 4 Shield per 2 secondi; abilita Block e Parry |
| Thorn Coat | 1 | 2 Thorns per 3 secondi; abilita la deviazione (QTE `L`) contro gli arcieri |
| Counter Rune | 1 | contrattacco 3, 2 cariche, 4 secondi; Retain |
| Battle Focus | 1 | pesca fino a 2 carte; Survey per 3 secondi: lato della vista +2 (da 2×2 passa a 5×5), massimo 9; Exhaust / Ethereal |
| Spark Forge | 1 | crea fino a 2 Spark temporanee a costo 0 |
| Dash | 1 | 2 Shield **prima** di muovere, durata 2 secondi; movimento fino a 4 celle, senza usare il recupero della schivata |
| Shove | 1 | prima spinge di 1 cella, poi infligge 1 danno; allontana bombe e interrompe intenti tramite spostamento |
| Grappling Hook | 1 | 1 danno e trascina adiacente, raggio 2–4; interrompe gli intenti spostando il nemico |
| Heavy Blow | 2 | 4 danni e Stagger: salta l’azione annunciata e apre almeno 1 secondo di recupero dopo il pagamento del costo temporale |
| Venom Needle | 1 | 1 danno + 2 Veleno (danno a ogni azione del bersaglio, poi uno stack in meno) |
| Purifying Guard | 1 | 3 Shield per 2 secondi e rimuove il Veleno |
| Volatile Study | 2 | crea 1 Spark, pesca fino a 2 carte; Exhaust |
| Toxic Wave | 2 | 1 Veleno ai nemici visibili entro raggio Chebyshev 2 (5×5) |
| Movimento Ombra | 3 | 4 secondi reali nell'ombra: mondo e finestra fermi, intangibile, solo passi dell'ombra da 0,4 s (diagonale sui suoi battiti); risale sull'ultima casella dell'ombra. 0 s di finestra, giocabile anche da storditi |
| Pozza di Veleno | 1 | una pozza su una cella libera fino alla fine della stanza: 2 Veleno (+1 per upgrade) a un nemico per ogni sua cella in cui entra; le aree che chiude si riempiono ([Pozza di Veleno e Incendio](#pozza-di-veleno-e-incendio)) |
| Incendio | 2 | un fuoco su una cella libera: 1 Bruciatura (+1 per upgrade) a ogni ingresso e a chi prende fuoco; cresce a croce di una casella a ogni nuova finestra e si spegne alla quinta |
| Deflect | 1 | una carica di RIFLESSO: il prossimo colpo nemico sul Viandante torna all'attaccante, senza scelta di difesa ([Deflect, Feretro, Dado del Destino e Lama Velenosa](#deflect-feretro-dado-del-destino-e-lama-velenosa)) |
| Feretro | 2 | 3 frecce (+1 per upgrade): `Ctrl` + clic su un nemico in linea di tiro, 1 danno + Veleno 2, Bruciatura 1 o Rallentamento 1; 1 s a freccia |
| Dado del Destino | 2 | i prossimi 3 urti tirano il dado del suo livello: 1-3 status, 4 ruba vita, 5 critico, 6+ letale (boss e miniboss: critico) |
| Lama Velenosa | 1 | tira il suo dado: tanti urti con 2 Veleno |
| Lazzo | 2 | un nemico entro 4 celle (non boss né miniboss) gira intorno al Viandante fino alla morte: colpi 1, 2, 3... sui nemici che incontra (spinti di n celle), -1 vita a ogni giro; schivare lo lascia andare ([Lazzo](#lazzo)) |
| Canna da Pesca | 0 | mai in mano: a stanza liberata pesca da un suo slot una casella libera entro 3 celle, che diventa acqua; 95% cibo che cura un d4, 5% una carta nel mazzo; 1 pesca a stanza +1 per upgrade (fino a 6); una sola per run ([Canna da Pesca](#canna-da-pesca)) |
| Pinball | 3 | un nemico accanto (non boss né miniboss) diventa una palla d'acciaio che rimbalza per 20 s del mondo a 7 caselle al secondo: i nemici che tocca prendono 2, 3, 4... (+1 per upgrade) e sono spinti di una cella, ogni muro la riporta a 2; poi scoppia e il nemico cade ([Pinball](#pinball)) |
| First Person Shooter | 3 | 20 s del mondo (+2 per upgrade) dietro gli occhi del Viandante: un AK di carta da 6 colpi al secondo, 1 danno lungo il mirino, passi secondo la vista, niente carte; 0 s di finestra ([First Person Shooter](#first-person-shooter)) |

Afterimage mantiene il bypass del recupero della schivata e lo Shield dopo il
movimento. Calculated Risk, Spark, Firebomb, Caustic Bloom e le formule delle
cinque carte con dadi/catene conservano i valori del catalogo base. **Aree e
rimbalzi colpiscono solo celle/nemici visibili**: nessun bersaglio occultato viene
rivelato dalla preview. Survey rispetta muri e ostacoli; quando scade, la vista
si restringe senza memoria dell’esplorazione. Con `--no-fog` non modifica la vista.
Le durate degli status avanzano ogni secondo del mondo; Veleno, Bruciatura e
Rallentamento non hanno durata: il Veleno morde le azioni di chi lo porta, la
Bruciatura brucia a ogni nuova finestra, il Rallentamento allunga gli intenti
del nemico ([Status](#status)). Durante cast e dadi il mondo
è fermo: non scadono status, micce, recuperi o cooldown dei dispositivi. Le carte con
pescata/creazione rispettano capienza e disponibilità; non garantiscono sempre
il numero massimo di carte scritto. Upgrade e keyword mantengono le policy esistenti.

| Input M7 | Azione |
|---|---|
| Pulsante **MAPPA 3D [TAB]** / `Tab` | apre/chiude la schermata olografica; **il countdown continua** |
| Trascinamento sinistro sulla mappa / rotella | ruota e inclina l’ologramma / zoom; `R` o **RICENTRA** ripristina la vista, `Esc` chiude |
| Trascinamento col tasto centrale sulla scena / rotella | orbita la camera 3D / zoom; gli assi WASD restano quelli della griglia |
| Clic su una carta / trascinamento | seleziona e mostra i dettagli / gioca sul bersaglio; un secondo clic gioca le carte senza bersaglio |
| `1`–`8` / clic destro o `Esc` | seleziona una carta con bersaglio o gioca subito una carta senza bersaglio / annulla la selezione (nella mano da dieci della Prova meccaniche anche `9` e `0`) |
| `Ctrl` + clic sinistro su un nemico | con le frecce di Feretro: scocca una freccia al nemico segnato (visibile e in linea di tiro); con `Ctrl` premuto il tavolo segna quelli raggiungibili |
| `I` / clic su **MOSTRA EFFETTO** nell'ispettore della carta | apre il film della carta sotto il mouse o di quella scelta, anche della Canna nel suo slot ([Mostra effetto](#mostra-effetto)); il pulsante compare a carta scelta, e pulsante e tasto tacciono mentre il tavolo è occupato |
| nella scheda **PERSONAGGIO**: clic su una riga del **MAZZO** / `<`, `>` / **MOSTRA EFFETTO** o `I` | sceglie la carta con il suo livello / gira pagina / apre il film della riga scelta; `Esc` chiude prima la finestra, poi la scheda |
| mouse / tasto sinistro tenuto, dietro gli occhi di [First Person Shooter](#first-person-shooter) | gira la vista / spara l'AK, 6 colpi al secondo; `WASD` sono passi secondo la vista, `P` o `Esc` mettono in pausa e liberano il mouse |
| `P` | pausa esplicita, con scena coperta; `P` riprende |
| `Q`, `E`, `Z`, `C` | tenta rispettivamente diagonale nord-ovest, nord-est, sud-ovest, sud-est sulla griglia |
| `WASD` durante QTE diagonale | due pressioni nell'ordine indicato: prima asse orizzontale, poi verticale |
| `Shift + WASD` | schivata attiva di 1–2 celle in linea; costo 1 secondo, recupero 2 secondi, senza carta richiesta |
| `J` / `K` durante scelta difesa | parata / parry, disponibili con Shield |
| `L` durante scelta difesa | deviazione di una freccia, disponibile con Thorns |
| `E` durante scelta difesa | schivata reattiva di una cella; poi `WASD` sceglie la landing; disponibile senza carte quando pronta |
| `WASD` dopo scelta parata/parry/deviazione | premi il tasto richiesto entro la finestra residua |
| rotella | zoom della camera locale |
| `M` | mappa della rotta fuori Combat; in Combat si usa l'ologramma |

Nel tattico `C` è riservato alla diagonale; l’equipaggiamento si usa con il mouse. Gli shortcut di debug delle abilità
restano disponibili integralmente in modalità classica. I comandi ordinari
sono sospesi durante cast, dadi, QTE, ologramma e pausa; dentro
[Movimento Ombra](#movimento-ombra) `WASD` muove soltanto l'ombra e tutto il
resto tace. I movimenti e le animazioni dei
nemici non bloccano movimento, carte o targeting del player. Durante il recupero
rimane disponibile la camminata ordinaria; carte, attacchi, refocus, schivata
attiva e diagonali sono sospesi. Le difese QTE restano disponibili secondo le
loro condizioni.

Il **pulse del player è una finestra di 20 secondi**, configurabile da 1 a 60,
che può contenere più azioni. Il countdown scorre mentre si decide. Movimento,
attacco, attesa, refocus, attivazione ed equipaggiamento **durano in tempo reale
il loro costo** (`Tactical_Config.timed_actions`): un passo da 1 s occupa il
Viandante per un secondo, mentre il countdown e i nemici scorrono come sempre (un
battito al secondo). Un comando premuto nel frattempo viene **scartato**, mai
tenuto da parte per dopo: agisce solo una pressione fatta a fine azione. La
schivata (`Shift + WASD`) invece non aspetta e interrompe subito l'azione, e la
fine della finestra chiude anche l'azione in corso. L'HUD mostra **AZIONE** con
una linea dorata che si consuma. Con le regole di base (`DEFAULT_TACTICAL_CONFIG`, usate
dalle sonde di regressione) il costo si sottrae invece subito. Una carta avvia
un cast di `Ns`: durante questi
secondi il countdown scende, il mondo resta fermo e il costo non viene sottratto
una seconda volta. Gli input rifiutati non pagano costi. Una carta iniziata con
tempo residuo positivo completa il proprio cast anche se il countdown arriva
prima a zero; il recupero parte dopo il cast.

Fuori dai cast, tempo reale e costi immediati alimentano il **clock del mondo**.
Ogni secondo matura un beat: agiscono solo i nemici giunti alla propria scadenza,
poi avanzano status, micce, recuperi e dispositivi (ogni nemico che ha agito
riceve subito il morso del proprio Veleno). La Bruciatura morde invece sul
comando di scadenza della finestra, quando cambia il numero di pulse. I cast non accumulano beat
arretrati da recuperare tutti insieme. Gli intenti restano fissati fino alla
scadenza. Energia: +1 ogni 3 secondi del mondo, entro il massimo. Il rimpiazzo
della carta si pesca al termine del cast se Combat continua (subito, per una
carta da 0 s); non serve un beat nemico aggiuntivo. La velocità delle animazioni
non altera questi contratti.

Solo allo zero dell'intera finestra parte un **recupero di 1 secondo di tempo
attivo**. Si può camminare senza costo temporale aggiuntivo: i passi non
accorciano né prolungano il recupero. Camminare verso un nemico non permette un
attacco; collisioni e hazard mantengono le regole normali. Nemici, bombe, status
ed energia continuano sul clock condiviso. Allo scadere, dopo aver risolto gli
eventuali beat/QTE pendenti, riparte la finestra successiva.

**La finestra si accorcia** (`Tactical_Config.shrinking_window`): ogni finestra
che arriva a zero lascia alla successiva un secondo in meno (20, 19, 18...).
Quando non resta più neanche un secondo il Viandante è **stordito**: niente
passi, attacchi, schivate o difese, solo carte, per 1 secondo la prima volta
nella stanza, 2 la seconda, 3 la terza e così via; poi la finestra torna intera.
Ogni **6 carte giocate** annullano il calo della scadenza successiva e danno un
secondo in più: a 18, invece di scendere a 17, si riparte da 19. La finestra non
supera mai i 20 secondi iniziali. L'HUD mostra `STORDITO` e, accanto ai nemici,
la lunghezza della finestra e le carte contate (`MAX 19s / CARTE 4/6`). Con le
regole di base ogni finestra resta intera.

All'ingresso di **ogni nuova stanza** ciclo, debito di tempo, recupero schivata,
lunghezza della finestra, carte contate e stordimenti si azzerano. Le statistiche cumulative della run rimangono. Un timeout chiude
la finestra una sola volta, dopo la risoluzione del tempo già pagato; il secondo
di recupero trascorre realmente, senza aggiungere una Wait o beat immediati.

Dadi, QTE, pausa, scheda personaggio, la finestra di
[Mostra effetto](#mostra-effetto), attività M9 e perdita del focus sospendono il
countdown dell’arena; Movimento Ombra lo ferma per i suoi 4 secondi. Cast,
movimento, animazioni nemiche, hover, targeting e
ologramma consumano tempo; durante il cast sono sospesi mondo e input ordinari.
Consultare la mappa
lascia avanzare anche i nemici, senza reset. Un input sullo stesso frame di un
beat viene eseguito subito dopo la risoluzione logica, mentre l’animazione nemica
prosegue. L'azione del player (la sua animazione, i suoi secondi o il passo
dell'ombra) occupa invece il suo input: una pressione fatta nel frattempo viene
scartata, non conservata, e solo una nuova pressione a fine azione agisce.
Lo stesso per cast e cinematiche: al termine della carta non parte nessuna
azione involontaria. L'unico input che aspetta qualche fotogramma è il passo
premuto sul secondo, in attesa del tasto della diagonale; ogni confine (fine
della finestra, QTE, pausa, mappa, schivata, perdita del focus, nuova stanza) lo
lascia cadere. Il targeting
delle carte sopravvive ai beat autonomi,
ma viene chiuso da timeout o QTE. Anche il recupero avanza durante le animazioni
e la consultazione dell'ologramma; QTE, pausa e perdita del focus lo sospendono.
L'HUD mostra `RECUPERO`, countdown decimale e carte disabilitate. La fine del
fight cancella subito il debito e consente il movimento nel Loot.

Una diagonale riuscita sposta di una cella e costa un secondo. Errore o
scadenza perdono la mossa e costano comunque un secondo; una landing inizialmente
bloccata non apre il QTE. I QTE difensivi intercettano attacchi ordinari melee,
cariche e frecce prima del danno: la parata aggiunge Shield 2 per quel pulse, il parry
annulla il colpo e infligge 2 danni, la deviazione restituisce il danno previsto,
la schivata usa movimento e hazard normali. Il parry restringe la finestra
residua a massimo 0.45 secondi; scegliere la difesa non rinnova la scadenza.
Attacchi ad area e hazard restano soggetti alle loro normali regole;
non tutti gli attacchi offrono un QTE. Shield e gli altri status mantengono
anche gli effetti automatici già esistenti.

La schivata non richiede carte: quella attiva attraversa al massimo due celle
ortogonali e costa un secondo; quella reattiva muove di una cella durante il
QTE dell'attacco in corso, senza aggiungere altro tempo. Dopo una schivata
riuscita devono passare due secondi del mondo completi, compresi i beat maturati nel recupero del player.
**Afterimage permette di schivare anche durante il recupero**, oltre al suo
effetto automatico. Fine combattimento e nuova run azzerano questo recupero.
La schivata non attraversa muri, oggetti solidi o nemici e non conferisce
invulnerabilità ai pericoli sul pavimento. Un tentativo attivo senza spazio
non consuma tempo; una landing reattiva bloccata fa fallire il QTE.

La fog non memorizza celle visitate. Le viste 3×3, 5×5, 7×7 e 9×9 sono centrate sul player; nel 2×2 il
quadrante include il player e segue il segno dell'ultima direzione. Gli angoli
fra due occlusori restano nascosti. L'ologramma mostra invece l'intera griglia
e le posizioni correnti: pedina ciano per il player, pedina rossa condivisa
per i nemici, modello viola/oro condiviso per Custode e Demolitore. Consultarlo
non estende il targeting delle carte oltre la visibilità locale.

## Verifica e smoke test

[Lo script di verifica](scripts/check.sh) esegue controllo statico, suite di tutti
i package e link della demo, sia con assert attivi sia con `-disable-assert`.
I binari sono temporanei; `ODIN` può indicare un compilatore alternativo.

```sh
sh scripts/check.sh
sh scripts/check.sh --headless
```

`--headless` omette le build della demo con finestra. I comandi utili per una
verifica mirata sono:

```sh
odin check src -vet -strict-style
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -o:none -out:/tmp/odin-pp-tests
odin test src/game -o:none -out:/tmp/odin-pp-game-tests
odin test src/render -o:none -out:/tmp/odin-pp-render-tests
odin test src/combatdebug -o:none -out:/tmp/odin-pp-combatdebug-tests
odin test src/engine -o:none -out:/tmp/odin-pp-engine-tests
odin test src/fight -o:none -out:/tmp/odin-pp-fight-tests
odin test src/shooter -o:none -out:/tmp/odin-pp-shooter-tests
```

Specificare sempre `-out` nei test: il runner crea e rimuove il proprio binario;
un output predefinito nella repo può interferire con una build del gioco omonima.
`-o:none` evita il lungo passaggio di ottimizzazione durante lo sviluppo.
Anche `src/grid`, `src/level` e `src/view` hanno test dedicati. I test del renderer
verificano la logica testabile; gli smoke con finestra verificano anche la resa
GPU. Un `libraylib.a` contenente `version https://git-lfs.github.com/spec/v1` è
un puntatore LFS, non un archivio collegabile: occorrono gli artefatti nativi
della toolchain. Era il limite dell'ambiente Linux dell'audit storico.

Gli smoke si eseguono con `odin run src -o:none -- <flag>`, uno alla volta. Quelli
grafici salvano lo screenshot nella directory di avvio e chiudono la finestra;
le immagini sono output rigenerabili, non prerequisiti del checkout.

| Flag | Screenshot / verifica |
|---|---|
| `--smoke-m9-view` | collisioni continue, vittoria contro l'IA del ring, quattro pose della presa, replay esatto, FPS con telegraph/ricarica/vittoria e ritorno; screenshot `odin_pp_m9_arena.png`, `ring.png`, `ring_grab_0.png`–`ring_grab_3.png`, `tools.png`, `fps.png` (prefisso comune `odin_pp_m9_`) |
| `--smoke-arenas-view` | quattro fasce di arene reali, combattimento, ologramma, Loot e cambio stanza; screenshot `odin_pp_arenas_*.png` |
| `--smoke-m8-view` | dispositivi con APRI IL RING, campo, tag match, ritorno Loot: `odin_pp_m8_d4.png`, `devices`, `mega_combo`, `character`, `loot`, `tag_ring`, `next_room` (tutti con prefisso `odin_pp_m8_` e suffisso `.png`) |
| `--smoke-western` | 6 RANCH 7 dalla mano al premio: `odin_pp_western_hand.png`, `cards`, `sign`, `gate`, `riders`, `ride`, `grab`, `win`, `reward` (prefisso `odin_pp_western_`) |
| `--smoke-mechanics-lab` | sandbox: `odin_pp_mechanics_lab.png`, `_square`, `_full`, `_refill`, `_restart`, `_stun`, `_pause`, `_defeat` (prefisso `odin_pp_mechanics_lab`); cartoncini vivi: `odin_pp_living_move_00.png`–`_37` e `odin_pp_living_attack_00.png`–`_37`, un'immagine ogni due fotogrammi; modi degli intenti nemici (F6): `odin_pp_living_intents_0_00.png`–`_3_39` (0 sigilli + terreno, 1 sigilli, 2 terreno, 3 adesivi), ogni tre, e lo stesso istante con un colpo in arrivo nei modi 0 e 3 (`odin_pp_living_intent_both.png`, `_labels`); segnalino di cura: `odin_pp_living_heal_00.png`–`_39`, ogni due; status a stack: `odin_pp_living_statuses_00.png`–`_19`, ogni tre, e `odin_pp_mechanics_lab_statuses.png` (fermo, con l'ispettore del nemico); Movimento Ombra dalla mano: `odin_pp_living_shadow_00.png`–`_82` (sprofonda, quattro passi dell'ombra con la diagonale sul primo battito, risale), ogni quattro; colpi: `odin_pp_living_blow_<nome>_00.png`–`_23` per `bolt`, `bolt_miss`, `cleave`, `claws`, `crozier`, `staff`, `bomb` ed `ember`, `_00`–`_39` per `charge`, `_00`–`_37` per `lantern`, `iron_cleaver` e `storm_pike`, ogni due; Rallentamento sul sigillo: `odin_pp_mechanics_lab_slow.png` (l'intento trattenuto, con l'ispettore del bruto) e `odin_pp_mechanics_lab_slow_worn.png` (dopo l'azione, uno stack in meno); Pozza di Veleno e Incendio: `odin_pp_mechanics_lab_pool_preview.png` (l'anteprima con l'area che l'ultima pozza chiuderebbe), `odin_pp_living_pool_00.png`–`_29` (la fiala lanciata chiude l'anello e l'area si allaga), ogni tre, `odin_pp_living_pool_walk_NN.png` (un chaser attraversa due pozze, poi il Viandante entra in una sua), ogni sei, `odin_pp_living_fire_NN.png` (il fuoco accanto al bruto per cinque finestre), ogni quattro, `odin_pp_mechanics_lab_fire.png` (alla quarta finestra) e il tavolo piatto in `odin_pp_mechanics_lab_pool_flat.png` e `odin_pp_mechanics_lab_fire_flat.png`; le cariche: `odin_pp_mechanics_lab_card_Deflect.png`, `_Coffin`, `_Fate_Dice`, `_Venom_Blade` (ogni carta sotto il mouse, con l'ispettore), `odin_pp_living_deflect_bolt_00.png`–`_31`, `odin_pp_living_deflect_cleave_00.png`–`_31` e `odin_pp_living_deflect_charge_00.png`–`_39`, ogni due, `odin_pp_mechanics_lab_arrow_aim.png` (`Ctrl` premuto, il mouse sul nemico segnato; quello dietro la copertura resta senza segno), `odin_pp_living_arrow_00.png`–`_37`, `odin_pp_living_fate_00.png`–`_37`, `odin_pp_living_fate_lethal_00.png`–`_37` e `odin_pp_living_fate_boss_00.png`–`_37` (il Custode), ogni due, `odin_pp_mechanics_lab_fate_chip.png` (il chip `DESTINO 3 d4` dell'HUD), `odin_pp_mechanics_lab_fate_chips.png` (tre cariche in più: tre chip e il conto, `DES 2 d20` intero), `odin_pp_mechanics_lab_venom_roll.png` (il dado di Lama Velenosa) e `odin_pp_living_venom_00.png`–`_37`; il Lazzo: `odin_pp_mechanics_lab_card_Lasso.png`, `odin_pp_mechanics_lab_lasso_preview.png` (il mirino sul nemico a quattro celle: l'anello di raggio 3 accanto al muro e i tre nemici fermi sopra), `odin_pp_mechanics_lab_lasso_heavy.png` (il Custode, `TROPPO PESANTE`), `odin_pp_living_lasso_throw_NN.png` (il lancio), ogni quattro, `odin_pp_living_lasso_NN.png` (il giro: i tre colpi ogni tre fotogrammi, poi ogni otto i giri, la difesa che lascia passare la freccia del balestriere e la caduta), `odin_pp_mechanics_lab_lasso_flat.png` (il tavolo piatto durante il giro), `odin_pp_living_lasso_smash_NN.png` (gli schianti e i rimbalzi), ogni cinque, e `odin_pp_living_lasso_release_00.png`–`_14` (la schivata che lo lascia andare), ogni tre; il Pinball: `odin_pp_mechanics_lab_card_Pinball.png`, `odin_pp_mechanics_lab_pinball_preview.png` (il mirino sul balestriere e la partenza della palla), `odin_pp_mechanics_lab_pinball_heavy.png` (il Custode, `TROPPO PESANTE`), `odin_pp_living_pinball_strike_NN.png` (il nemico che diventa la palla e il colpo che la manda via), ogni quattro, `odin_pp_living_pinball_NN.png` (la corsa, con la telecamera allontanata: ogni tre fotogrammi i primi 2,6 secondi, con i tre ghoul presi per 2, 3 e 4 e il muro nord che riporta 5 a 2, poi ogni venti fino a 3 secondi; il resto corre veloce senza immagini), `odin_pp_mechanics_lab_pinball_chip.png` (il chip della palla, con il valore a 5, accanto ai morsi e alle cariche), `odin_pp_mechanics_lab_pinball_flat.png` (il tavolo piatto durante la corsa) e `odin_pp_living_pinball_burst_NN.png` (l'ultimo mezzo secondo e lo scoppio, la telecamera ancora più lontana), ogni due; First Person Shooter: `odin_pp_mechanics_lab_card_First_Person.png`, `odin_pp_living_fps_dive_NN.png` (la discesa negli occhi), ogni tre, `odin_pp_mechanics_lab_fps.png` (la vista: l'AK, il mirino e il conto dei secondi), `odin_pp_living_fps_fire_NN.png` (il grilletto tenuto: traccianti, scintille, il cuore del ghoul da 40 a 34), ogni due, `odin_pp_mechanics_lab_fps_wall.png` (il colpo fermato dal ghiaccio), `odin_pp_mechanics_lab_fps_stone.png` (quello fermato dal muro del bordo, con le schegge di pietra), `odin_pp_living_fps_steps_NN.png` (il primo passo, con l'occhio che scivola) e `odin_pp_living_fps_bump_NN.png` (l'urto), ogni due, `odin_pp_mechanics_lab_fps_defense.png` (la scelta di difesa dietro gli occhi), `odin_pp_mechanics_lab_fps_hurt.png` (i bordi rossi), `odin_pp_living_fps_rise_NN.png` (la risalita), ogni due, `odin_pp_mechanics_lab_fps_flat.png` e `odin_pp_mechanics_lab_fps_flat_after.png` (il tavolo piatto diventato 3D, e di nuovo piatto); la Canna da Pesca: `odin_pp_living_fishing_clear_NN.png` (`F7`: i due nemici cadono e si apre lo slot), ogni sei, `odin_pp_mechanics_lab_rod_slot.png` (lo slot sotto il mouse, con l'ispettore), `odin_pp_mechanics_lab_rod_preview.png` (la Canna presa: le caselle che può pescare e quella sotto il mouse), `odin_pp_living_fishing_NN.png` (lancio, galleggiante, abboccata, il pesce che vola al Viandante, il d4 e la cura), ogni cinque, `odin_pp_mechanics_lab_fishing_roll.png` (il d4 fermo sul 3), `odin_pp_mechanics_lab_fishing_flat.png` (l'acqua sul tavolo piatto), `odin_pp_mechanics_lab_rod_slot_upgraded.png` (la Canna +1 nella stanza nuova: `PESCA 2/2`), `odin_pp_living_fishing_card_NN.png` (la carta pescata) e `odin_pp_living_fishing_again_NN.png` (la stessa acqua di nuovo: il pane e il suo d4), ogni cinque |
| `--smoke-effect-window` | [Mostra effetto](#mostra-effetto): ogni ingresso con il suo pulsante, `odin_pp_effect_entry_inspector_hover.png` (una carta sotto il mouse, la riga del tasto), `_inspector_chosen` (la carta scelta, il pulsante), `_inspector_busy` (spento in Movimento Ombra), `_sheet` (il MAZZO alla seconda pagina, una riga scelta), `_sheet_after` (la scheda rimasta aperta dopo `Esc`), `_rod_hover`, `_rod_chosen`, `_reward`, `_shop_offer`, `_shop_owned` e `_rest` (prefisso `odin_pp_effect_entry`); la finestra aperta da ognuno, `odin_pp_effect_window_<ingresso>_00.png`–`_02` (ogni 24 fotogrammi) e `_close` (con CHIUDI sotto il mouse) per `inspector_key`, `inspector_button`, `sheet`, `rod`, `reward`, `shop_offer`, `shop_owned` e `rest`, e `odin_pp_effect_window_reward_restart.png` (dopo RICOMINCIA); la finestra a tre misure, `odin_pp_effect_scale_1600x900.png`, `_960x540` e `_1280x720`; il film di ogni carta al livello 0 e al più alto, `odin_pp_effect_film_<Card_Id>_<livello>_NN.png` (lo stage nei suoi 960x540 pixel: il guanto sulla carta, in viaggio, sul bersaglio, poi l'effetto ogni 0,6 s, ogni 1,5 s dall'ottavo secondo, e la ripresa ferma alla fine; al più 40) e `odin_pp_effect_film_<Card_Id>_<livello>_window.png` (tutta la finestra, con il guanto sul bersaglio) |
| `--smoke` | `odin_pp_isometric.png` |
| `--smoke-generation` | `odin_pp_procedural_room.png` |
| `--smoke-map` | `odin_pp_route.png` |
| `--smoke-family=pillars` | `odin_pp_pillars.png` |
| `--smoke-family=ring` | `odin_pp_ring.png` |
| `--smoke-family=courts` | `odin_pp_courts.png` |
| `--smoke-family=cover` | `odin_pp_cover.png` |
| `--smoke-status`, `--smoke-loot` | `odin_pp_status.png`, `odin_pp_loot.png` |
| `--smoke-card` | `odin_pp_card_drag.png` |
| `--smoke-targeting` | `odin_pp_advanced_targeting.png` |
| `--smoke-spatial` | `odin_pp_spatial_targeting.png` |
| `--smoke-object`, `--smoke-fire` | `odin_pp_ice_block.png`, `odin_pp_fire.png` |
| `--smoke-content` | `odin_pp_content_pass.png` |
| `--smoke-movement` | `odin_pp_enemy_movement.png` |
| `--smoke-timeline` | `odin_pp_timeline.png` |
| `--smoke-deck-flow`, `--smoke-refocus` | `odin_pp_deck_flow.png`, `odin_pp_refocus.png` |
| `--smoke-reward`, `--smoke-shop` | `odin_pp_reward.png`, `odin_pp_shop.png` |
| `--smoke-rest`, `--smoke-event` | `odin_pp_rest.png`, `odin_pp_event.png` |
| `--smoke-treasure`, `--smoke-special-result` | `odin_pp_treasure.png`, `odin_pp_special_result.png` |
| `--smoke-intents`, `--smoke-archetypes` | `odin_pp_enemy_intents.png`, `odin_pp_enemy_archetypes.png` |
| `--smoke-tactics`, `--smoke-encounters` | `odin_pp_tactics.png`, `odin_pp_encounters.png` |
| `--smoke-miniboss`, `--smoke-furnace` | `odin_pp_miniboss.png`, `odin_pp_furnace.png` |
| `--smoke-defeat` | `odin_pp_defeat.png` |
| `--smoke-relics`, `--smoke-relic-combat` | `odin_pp_relics.png`, `odin_pp_relic_combat.png` |
| `--smoke-firebomb-spell` | `odin_pp_firebomb_spell.png` |
| `--smoke-dice`, `--smoke-dice-pool` | `odin_pp_dice.png`, `odin_pp_dice_pool.png` |
| `--smoke-chain`, `--smoke-spell-preview` | `odin_pp_chain.png`, `odin_pp_spell_preview.png` |
| `--smoke-sunder-preview` | `odin_pp_sunder_preview.png` |
| `--smoke-barrage`, `--smoke-twin-venom` | `odin_pp_barrage.png`, `odin_pp_twin_venom.png` |
| `--smoke-sprites` | `odin_pp_sprites.png`, caricamento, alpha, clip e fallback |
| `--smoke-playtest` | headless: al massimo venti decisioni, `odin_pp_playtest_smoke.json` |

Gli smoke di spell e impatti controllano anche il completamento del replay;
le preview non consumano RNG. Lo smoke sprite crea e rimuove asset diagnostici
temporanei. Per i report interattivi vedere [Telemetria](#telemetria-e-playtest).
Le regressioni M9 verificano simulazione invariata a 30/60/144 FPS, collisioni
e raggi senza attraversamenti, finestre delle mosse, parata/schivata/prese,
replay esatto, input al cambio focus e transizioni fra run e attività.
[m9_transition_test.odin](src/m9_transition_test.odin) copre anche ricompense
una sola volta, isolamento della pratica e chiusura senza click-through.
[effect_window_test.odin](src/effect_window_test.odin) e
[card_demo_test.odin](src/card_demo_test.odin) fanno lo stesso per
[Mostra effetto](#mostra-effetto): ingressi, run ferma, rifiuti, chiusura senza
click-through e il film di ogni carta a ogni livello, che deve mostrare quello
che la carta promette.

## Architettura e ownership

| Percorso | Responsabilità |
|---|---|
| [src/main.odin](src/main.odin) | punto di ingresso, preparazione e installazione delle stanze demo, comandi di gioco |
| [src/roguelike_scene.odin](src/roguelike_scene.odin) | la run come scena dell'host: stato della sessione, schermate e transizioni |
| [src/launcher.odin](src/launcher.odin), [minigame_registry.odin](src/minigame_registry.odin) | menu, impostazioni e catalogo dei minigiochi |
| [src/engine](src/engine), [src/minigames](src/minigames) | engine condiviso e minigiochi (vedi [Engine e minigiochi](#engine-e-minigiochi)) |
| [src/app](src/app) | finestra, canvas virtuale e presentazione |
| [src/grid](src/grid) | `Grid(T)`, coordinate, memoria contigua, accesso sicuro |
| [src/level](src/level) | tile, layout e validazione topologica BFS |
| [src/game](src/game) | simulazione, azioni, carte, run, generazione degli incontri |
| [src/engine](src/engine) | clock fisso, corpi e solidi continui, collisioni, raycast, trigger e livelli riutilizzabili |
| [src/fight](src/fight) | simulazione pura del ring X/Z, mosse, hit/hurtbox, IA, presa e hit-stop |
| [src/shooter](src/shooter) | simulazione pura FPS, arma, munizioni, nemici e due livelli |
| [src/view](src/view) | scaling, camera e proiezione testabili |
| [src/render](src/render) | renderer Raylib, snapshot e timeline |
| [src/combatdebug](src/combatdebug) | observer, scenari headless e report |
| [src/gameplay_input.odin](src/gameplay_input.odin) | comandi logici, fase d'origine e l'unico input in attesa (il passo sul secondo che aspetta la diagonale, [beat_input.odin](src/beat_input.odin)) |
| [src/runtime_options.odin](src/runtime_options.odin) | opzioni della sessione |
| [src/m8_session.odin](src/m8_session.odin) | scheda personaggio con il suo MAZZO, richieste di MOSTRA EFFETTO dalla scheda e dall'ispettore, ingresso/ritorno dalle attività, ricevuta del ring e persistenza degli sblocchi |
| [src/effect_window.odin](src/effect_window.odin), [effect_window_smoke.odin](src/effect_window_smoke.odin) | la finestra di [Mostra effetto](#mostra-effetto): modale della run che prende tutto il fotogramma, rifiuti a tavolo occupato, ingressi di ricompensa, negozio e riposo, stage 960x540 sopra il canvas, proprietà del film e del suo renderer; lo smoke |
| [src/card_demo.odin](src/card_demo.odin) | il film di una carta, dietro `card_demo_open`, `card_demo_step`, `card_demo_restart`, `card_demo_prepare`, `card_demo_draw`, `card_demo_close` e `card_demo_caption`: la ripresa, il guanto che gioca la carta come la mano, il controller della ripresa, le didascalie, il ritorno da capo |
| [src/game/card_demo.odin](src/game/card_demo.odin) | le scene dei film: default dal targeting, override per carta, eventi attesi esaustivi su `Effect_Kind` e `Status_Kind`, dadi e stanza di prova |
| [src/render/effect_stage.odin](src/render/effect_stage.odin), [card_demo.odin](src/render/card_demo.odin), [effect_entries.odin](src/render/effect_entries.odin) | il renderer prestato del film (stato proprio, asset GPU della run), guanto, clic, didascalie e luce della piastra VITA, pulsanti MOSTRA EFFETTO delle schermate |
| [src/m9_session.odin](src/m9_session.odin) | proprietario di input/clock della modalità libera, pause, cursore, preset delle mosse e registrazione/replay |
| [src/m9_lab.odin](src/m9_lab.odin), [m9_smoke.odin](src/m9_smoke.odin) | ciclo dei laboratori e verifica nativa riproducibile |
| [src/game/board_device.odin](src/game/board_device.odin) | geometria condivisa, attivazione, scariche e cleanup dei dispositivi |
| [src/game/m8_equipment.odin](src/game/m8_equipment.odin), [m8_ring.odin](src/game/m8_ring.odin) | armi a utilizzi, progressione del ring e compatibilità della simulazione M8 precedente |
| [src/render/cast_playback.odin](src/render/cast_playback.odin) | policy Live/Cast/Cinematic e durata visiva del cast |
| [src/render/m9_world.odin](src/render/m9_world.odin), [m9_controls.odin](src/render/m9_controls.odin) | scena/camera delle modalità libere, interpolazione, HUD e controlli mouse condivisi |

`grid` non conosce il gioco. `level` conosce la topologia, ma non difficoltà,
nemici o tipi di nodo. `game` non dipende dal renderer o dalla telemetria;
`combatdebug` legge `game`. Il rendering non modifica gameplay o RNG.
La griglia ha soltanto coordinate `(x, y)`: M7 la presenta con terreno 3D e
sprite su piani orientati alla camera; la vista classica usa la proiezione
isometrica. La profondità visiva non aggiunge movimento verticale. Il canvas virtuale è `960x540`.

`Run_State` possiede player, deck, reliquie, grafo e payload dei nodi. `Level`
possiede la propria `Grid(Tile)`. `Room` possiede nemici, trappole, ostacoli,
oggetti, loot e scratch buffer, ma prende in prestito `^Level` e `^Player`.
Il renderer possiede soltanto risorse e copie di presentazione.

`Effect_Window`, nella sessione della run, possiede il film di
[Mostra effetto](#mostra-effetto) (`Card_Demo`, sull'heap: la sua stanza punta
dentro di lui), il suo renderer e i render target dello stage. Il film possiede
la sua stanza, il suo livello e il suo giocatore, e non tocca mai quelli della
run. Il suo renderer possiede soltanto il proprio stato di vista e prende in
prestito le risorse GPU del renderer della run, che vive più a lungo
(`destroy_effect_window` è la prima cosa di `roguelike_destroy`). Un asset nuovo
del `Renderer` va preso in prestito anche in `borrow_renderer_assets`: il test
che percorre il `Renderer` con `core:reflect` fallisce finché non c'è, e così se
il renderer prestato divide con quello della run un puntatore o uno stato. Un
pezzo di stato nuovo che `destroy_tactical_assets` libera va liberato anche in
`destroy_borrowed_renderer`.

`engine`, `fight` e `shooter` non importano Raylib, `game` o la griglia tattica.
Le due simulazioni libere possiedono ciascuna il proprio `engine.World` e
dipendono soltanto dai servizi geometrici/temporali condivisi. `M9_Session`
possiede la modalità corrente e la registrazione dinamica, liberata da
`destroy_m9_session`. Il loop principale sospende l'aggiornamento tattico mentre
questa sessione è aperta; il renderer non decide esiti o ricompense.
Il risultato del ring passa attraverso `settle_ring_challenge`, mantenendo la
progressione M8 senza usare il vecchio duello monodimensionale nel gioco live.

La nuova stanza viene costruita in un `Room_Blueprint` e preparata con copie di
player, livello e stanza. Si valida tutto prima del commit; un fallimento libera
le risorse temporanee senza cambiare run, salute, oro, status, deck o RNG.
Nell'installazione si distrugge la vecchia Room **prima** del vecchio Level,
si trasferiscono gli owner e si riagganciano i puntatori alle destinazioni
stabili. Gli owner trasferiti vengono azzerati. Le grandi copie per valore di
Room restano negli helper di installazione, per evitare la scalarizzazione
LLVM osservata quando erano dentro `main`.

I riferimenti durevoli sono ID, mai puntatori o indici di array dinamici.
`Entity_Ref` contiene categoria e ID: player e sistema usano zero; nemici,
trappole e oggetti hanno ID stabili. Una rimozione `unordered_remove` può
cambiare l'indice, ma non il destinatario di un'azione già costruita.

## Azioni, impulsi, status e reazioni

Sorgenti: [action.odin](src/game/action.odin), [pulse.odin](src/game/pulse.odin),
[event.odin](src/game/event.odin), [status.odin](src/game/status.odin),
[reaction.odin](src/game/reaction.odin),
[reaction_definition.odin](src/game/reaction_definition.odin) e
[reaction_binding.odin](src/game/reaction_binding.odin).

### Azioni e commit

```text
Input / IA / trigger -> Action -> validazione -> effetti ordinati
                                            -> reazioni FIFO -> report
Il chiamante decide poi se avanzare il pulse.
```

Il target primario descrive la scelta; i destinatari degli effetti possono
essere diversi, come per un'area o una carta che colpisce e concede Shield.
Gli effetti comprendono `Damage`, `Heal`, `Gain_Gold`, `Move`,
`Apply_Status`, `Remove_Status`, `Add_Reaction_Binding`, `Draw_Cards`,
`Discard_Cards` e `Create_Card`.

Il resolver valida fase, sorgente, target e almeno un effetto inizialmente
applicabile, se presente. Ricontrolla poi ogni effetto nell'ordine dichiarato:
un effetto diventato invalido incrementa `skipped_effects`, senza annullare
quelli già applicati. Per esempio, Shove può infliggere danno e saltare la
spinta se il bersaglio muore. Un'azione vuota come Wait resta valida.

`resolve_action_once` risolve una sola azione; `resolve_action` aggiunge il
dispatch reattivo. Nessuno dei due avanza il pulse. La transazione della carta
paga energia e cambia zone del deck, ripristinandole se l'intera azione è
rifiutata: non offre rollback globale degli effetti di un'azione già accettata.

### Ordine del pulse e degli eventi

Dopo azione del player, reazioni, prima raccolta magnetica e morso del suo
Veleno, se Combat continua:

1. scoppiano gli esplosivi in scadenza;
2. si risolve l'eventuale corsia Furnace;
3. si risolvono i Protect, poi gli altri intenti nemici, ordinati per ID; dopo
   ogni intento portato a termine (colpo, mancato, passo bloccato, attesa o
   recupero) morde il Veleno di quel nemico e il suo Rallentamento perde uno stack;
4. se il fight continua, avanzano gli status del player e poi dei nemici (la
   Bruciatura morde a ogni pulse classico);
5. avanzano le durate dei binding; si rigenera energia se ancora in Combat;
6. aumenta `pulse_count`, si pianifica il prossimo intento o si svuotano i piani;
7. `Pulse_Advanced` registra pulse, energia recuperata/sprecata e tick;
8. seguono la raccolta magnetica post-pulse e l'eventuale pesca o refill.

Le fasi già concluse o terminali non eseguono i segmenti successivi non più
validi. Un'azione che elimina l'ultimo nemico prima della risposta non avvia
un pulse; muoversi in Loot non lo avvia. `Room.recent_events` conserva soltanto
l'ultimo comando e viene azzerato all'inizio del successivo.

### Status

Ogni combattente possiede uno `Status_Set` inline, con un posto per tipo
(`MAX_STATUSES_PER_ENTITY = len(Status_Kind)`) e una sola istanza per tipo. La
potenza deve essere positiva, e così la durata, tranne per gli status a
**stack** (`status_kind_stacks`: Veleno, Bruciatura, Rallentamento e le cariche
del Viandante): non ne hanno (`remaining_pulses` resta 0) e nessun pulse li
consuma; ogni applicazione aggiunge i propri stack.

| Status | Stacking | Comportamento |
|---|---|---|
| Shield | somma saturata della potenza, durata maggiore | assorbe danno dopo la difesa; a zero viene rimosso |
| Poison (Veleno) | somma saturata degli stack, senza durata | a ogni azione di chi lo porta infligge danno pari agli stack (sorgente System), poi perde uno stack; a zero finisce |
| Burn (Bruciatura) | somma saturata degli stack, senza durata | M7: all'inizio di ogni nuova finestra (quando quella in corso scade e cambia il numero di pulse) infligge danno pari agli stack; in combattimento classico a ogni pulse. Gli stack non calano mai: dura fino alla morte o alla fine della stanza |
| Slow (Rallentamento) | somma saturata degli stack, senza durata | M7: ogni stack fa aspettare 1 secondo in più il prossimo intento pianificato dal nemico (il conto alla rovescia, il sigillo e l'anello lo includono; `Enemy_Intent.slowed`); dopo l'azione così trattenuta perde uno stack. L'intento già in corso quando arriva non si allunga e non lo consuma. In classico ogni azione ne consuma uno senza altro effetto. Il player non può esserne colpito |
| Thorns | potenza e durata maggiori | contraccolpo per danno effettivo ricevuto da un avversario vivo |
| Afterimage | potenza e durata maggiori | dopo il proprio `Moved` in Combat concede Shield pari alla potenza, per due pulse; in M7 permette schivate durante il recupero |
| Stagger | potenza e durata maggiori | M7: interrompe l’intento nemico, cancella mira/lancio preparati e lascia almeno 1 secondo sfruttabile dopo il costo della carta |
| Survey | potenza e durata maggiori | M7: lato della vista +2 (2×2 → 5×5), massimo 9, rispettando LoS e senza memoria |
| Deflect (RIFLESSO) | somma saturata degli stack, senza durata | solo il Viandante: il prossimo colpo nemico che lo colpirebbe torna all'attaccante; uno stack per colpo, fino alla fine della stanza |
| Arrows (FRECCE) | somma saturata degli stack, senza durata | solo il Viandante: frecce da scoccare con `Ctrl` + clic; uno stack a freccia, fino alla fine della stanza |
| Fate (DESTINO) | il massimo degli stack (3), senza durata | solo il Viandante: gli urti caricati tirano il dado dell'ultimo Dado del Destino, che il chip nomina (`DESTINO 3 d8`); uno stack a urto, fino alla fine della stanza |
| Venom_Blade (LAMA) | somma saturata degli stack, senza durata | solo il Viandante: urti con 2 Veleno; uno stack a urto, fino alla fine della stanza |

Il danno al player segue `danno base -> difesa -> Shield -> salute`; i nemici
non hanno ancora una statistica difesa. Il morso di Veleno e Bruciatura salta
la difesa (resta pari agli stack): solo lo Shield lo assorbe, e può concludere
il fight. La durata applicata prima della risposta nemica avanza già alla fine
di quel pulse.
L'ordine dei tick per entità è Bruciatura (solo in classico), Shield, Thorns,
Afterimage, Stagger, Survey: la Bruciatura morde prima che uno Shield in
scadenza sparisca.

Sono **azioni** del player tutti i comandi accettati in combattimento: passo
(anche durante il recupero), attacco a urto, carta, attesa, schivata (anche
quella reattiva del QTE di difesa, appena atterra), diagonale (anche fallita),
refocus, Activate, Equip e la freccia di Feretro; il Veleno morde alla fine del comando, prima del
tempo del mondo che il comando fa scorrere. Non lo sono Movimento Ombra (la
carta, i passi dell'ombra e la risalita: nell'ombra il player è intangibile),
le altre risposte ai QTE di difesa (blocco, parata, deviazione) e l'anello
Tesla. Del nemico ogni intento risolto, di qualsiasi tipo; un intento
interrotto da Stagger non è un'azione. La Bruciatura in M7 morde sul comando
`Timeout`, con i suoi cue e i suoi suoni.

Veleno e Bruciatura del pavimento (pozze e fuochi,
[Pozza di Veleno e Incendio](#pozza-di-veleno-e-incendio)) hanno sorgente System,
come i morsi: nessuna reliquia o reazione del Viandante li modifica.
Thorns non scatta su danno interamente assorbito, veleno, bruciatura o hazard neutrali.
Afterimage osserva solo il movimento terminale: un Dash di tre celle lo attiva
una volta. Il suo Shield arriva **dopo** gli hazard attraversati, ma prima della
risposta nemica. Nessuna reazione può essere costruita per un owner già morto.
Gli status sono locali alla stanza; non avanzano durante Loot o schermate della
run e si azzerano solo quando la nuova stanza viene installata con successo.

### Reazioni e limiti

Il dispatcher osserva gli eventi solo dopo gli effetti dell'azione radice.
Se la radice produce A e B e A genera C, la coda procede A, B, C. Le reazioni
sono normali Action risolte senza ricorsione. Una definizione dichiara trigger,
filtri, reactor, priorità e template; il binding runtime aggiunge owner,
potenza, cariche, durata e sorgente System, Ability, Card o Passive.

Le richieste sono ordinate per priorità decrescente e poi per `Reaction_Id`.
Il modificatore di priorità usa somma saturata. Cariche e durata usano `-1`
per illimitato, mai zero come stato attivo; una carica si consuma solo dopo
una reazione accettata. Esaurimento, scadenza e morte dell'owner rimuovono i
binding e producono la diagnostica prevista.

| Budget | Limite |
|---|---:|
| effetti per Action / nemici per Room | 32 / 32 |
| template per carta | 4, di cui al massimo un Move |
| eventi per log / cue di presentazione | 416 / 416 |
| richieste reattive per evento | 8 |
| azioni reattive per catena / binding per Room | 32 / 32 |
| oggetti / trappole per Room | 32 / 64 |

L'overflow di un log staged rifiuta la transazione. Gli eventi di
`Action_Report` alimentano anche le reazioni: perderli cambierebbe il gameplay,
quindi `record_report_event` termina esplicitamente in caso di esaurimento.
Solo le copie post-commit per storico e presentazione possono perdere eventi,
contando `dropped_count` e convergendo allo snapshot finale. Il limite anti-ciclo
delle reazioni è distinto e resta diagnosticabile.

Lo stress storico produce 258 eventi, con 158 slot di margine; il caso di dodici
celle con trappole ne produce 36. Nuovi effetti composti devono verificare il
proprio envelope, senza aumentare i limiti per nascondere cicli o overflow.
I template reattivi non rappresentano ancora Move o Add_Reaction_Binding;
gli eventi di scadenza dello scheduler vengono registrati ma non riaprono
catene reattive. Le definizioni restano tabelle compilate, non file esterni.

## Targeting e movimento

Sorgenti: [targeting.odin](src/game/targeting.odin),
[movement.odin](src/game/movement.odin) e [hazard.odin](src/game/hazard.odin).

### Geometria condivisa

`Targeting_Spec` distingue origine, range dell'anchor e forma colpita.
Il range limita **l'anchor**, non ogni bersaglio nell'area: un nemico sul bordo
della Firebomb può essere più lontano dal player del suo range di cast.
Manhattan misura `abs(dx) + abs(dy)`, Chebyshev `max(abs(dx), abs(dy))`;
minimo e massimo sono inclusivi.

| Forma | Regola |
|---|---|
| None | niente celle; target implicito Self, Player o None |
| Single | solo anchor, raggio zero |
| Line | esclude origine, include anchor; otto direzioni ortogonali o diagonali perfette |
| Cross | centro e quattro bracci fino al raggio; i muri possono fermare i singoli bracci |
| Square | lato `2 * radius + 1`; raggio uno produce un 3x3 |

Footprint fuori bounds o su celle staticamente bloccate vengono ritagliate,
senza duplicati. Un'area sul bordo può restare valida. Square non proietta
ombre fra le proprie celle. `requires_line_of_sight` e `stops_on_wall`
controllano il percorso di cast; la diagonale fra due blocchi ortogonali è
vietata. Un oggetto targetable può essere l'endpoint di un ray anche se opaco.
Gli attori non bloccano la LoS; `stops_on_actor`, riservato a Line, include il
primo attore e ferma lì la footprint. Piercing Ray attraversa gli attori.

`evaluate_target_query` è pura. Restituisce percorso, footprint, target,
blocker e ID nemici ordinati; `error == .None` è il verdetto completo.
`anchor_reachable` serve a mostrare il range, ma non garantisce una giocata:
un'area vuota può produrre `No_Effects`. L'energia viene controllata da
`play_card`, fuori dalla query geometrica.

Preview, drop e compilazione usano `evaluate_card_targeting`. Se una carta
sposta un'entità, questa valutazione include anche `Movement_Query`:
anchor e destinazione del movimento sono concetti distinti. Il renderer
visualizza questi risultati senza ricostruire geometria o selezionare bersagli.

I limiti sono range 12, raggio 4, traccia e movimento 12 celle, footprint 81
celle. Specifiche incoerenti, linea non allineata, target invalido, blocker e
capacità superata producono errori espliciti. La compilazione distingue fra
l'altro `Target_Out_Of_Range`, `Target_Blocked`, `No_Effects` e
`Too_Many_Effects`; nessuna giocata viene troncata silenziosamente.

### Percorsi e hazard

| Modalità | Validazione e applicazione |
|---|---|
| Traverse | intera linea in una delle otto direzioni, ogni cella libera da blocker e attori |
| Teleport | solo landing; ignora geometria, attori e hazard intermedi |

Entrambe verificano la destinazione; `Teleport` non permette un atterraggio
illegale. Movimento e LoS hanno query separate: `cell_blocks_movement` e
`cell_blocks_line_of_sight`. La geometria statica viene controllata prima degli
attori. Un oggetto mobile non può sovrapporsi ad alcun altro oggetto, incluso
Fire, anche se un attore potrebbe attraversarlo.

Il resolver ricontrolla la query prima dell'applicazione. Ogni ingresso produce
`Movement_Step`, l'ultimo `Moved`; subito dopo si risolve la trappola e poi
l'eventuale oggetto pericoloso, se l'attore è vivo:

```text
Movement_Step / Moved -> Trap_Triggered -> danno
                     -> Hazard_Triggered -> danno -> eventuale morte e drop
```

Le trappole si disarmano; Fire resta e infligge due danni a ogni ingresso in
Combat o Loot. Wait e permanenza sul fuoco non causano tick. Traverse risolve
tutte le celle; Teleport solo la landing. Se un hazard uccide il mover, il
percorso si ferma e l'ultimo step viene promosso a Moved, senza inventare celle
attraversate. Gli oggetti spinti non attivano hazard o trappole.

Shove e Grappling Hook applicano danno, poi movimento opzionale; un blocker
non annulla il danno. Dash contiene solo Move: il percorso deve essere valido
prima di pagare. Tutte e tre usano Traverse. Grappling Hook si ferma al primo
attore e trascina il bersaglio fino alla cella adiacente al player.
Spostare un nemico non aggiorna il suo intento già committed: il piano stale
produce miss o blocco, poi viene ripianificato per il pulse successivo.

## Oggetti, esplosivi e loot

Sorgenti: [grid_object.odin](src/game/grid_object.odin),
[explosive.odin](src/game/explosive.odin), [room.odin](src/game/room.odin).

### Oggetti sulla griglia

`Grid_Object_Definition` contiene capability immutabili; l'istanza conserva ID,
posizione, HP e `detonation_pulse`. Collisione, LoS, targeting, danno,
movimento, pericolosità ed esplosione sono proprietà indipendenti. Non esiste
un generico `is_occupied`: loot, trappole e Fire hanno regole diverse dai solidi.

| Oggetto | Movimento / LoS | Interazione |
|---|---|---|
| Ice Block | blocca entrambi | 4 HP, selezionabile, danneggiabile e spostabile |
| Fire | attraversabile / trasparente | 2 danni all'ingresso; non selezionabile, danneggiabile o spostabile |
| Barrel | solido / trasparente | spostabile; in Combat il danno accende la miccia |
| Bomb | attraversabile / trasparente | spostabile, nasce accesa dal lancio del Bombarolo |

Pozze e fuochi delle carte della Fase 2 non sono oggetti: stanno sul pavimento
(`Room.ground`, [ground.odin](src/game/ground.odin)) e non occupano né posti né celle.
Gli oggetti hanno storage preallocato per 32 istanze e ID monotoni non nulli.
Lo spawn iniziale rifiuta sovrapposizioni con attori, uscita, spawn, trappole,
ostacoli e altri oggetti, anche per Fire. Lo spawn runtime di una bomba può
invece avvenire sotto un attore; non sopra un altro oggetto o un ostacolo.
Un fallimento non consuma ID. Una spinta può portare ghiaccio su una trappola,
ma non la disarma. La distruzione di oggetti non conclude Combat: contano i
nemici vivi. Gli oggetti non ricevono status, Shield, difesa o cure degli attori.

`Opponent_Or_Object` permette a Shove, Strike e Arc Bolt di selezionare un
oggetto valido. Il picking riconosce anche il corpo rialzato, mentre aree e
Dash usano il pavimento; un attore disegnato sopra una bomba mantiene priorità.
La preview Shove indica `PUSH 1`, `BLOCKED` o `BREAKS` quando il ghiaccio morirà
prima della spinta. Durante Loot il bump può rompere i solidi spostabili,
senza pulse, per liberare corridoi o uscita.

### Micce e combinazioni

Una bomba o un barile acceso infligge **4 danni base nel 3x3** a player, nemici
e oggetti danneggiabili. La footprint esclude muri, ostacoli fissi e fuori
bounds; non richiede LoS fra le celle dell'area. Difesa e Shield valgono
normalmente. Preview e danno condividono le stesse celle.

La miccia misura decisioni accettate, non secondi: dopo il comando che accende
l'esplosivo restano due ulteriori azioni. Alla seconda, lo scoppio precede gli
intenti nemici. Un comando rifiutato non consuma miccia. Spostare o colpire un
esplosivo acceso non ne rinvia la scadenza; il solo danno a un esplosivo già
acceso viene rifiutato. Shove resta valido se riesce a spostarlo.

- Strike, Arc Bolt e Firebomb accendono i barili; Firebomb può colpire soltanto oggetti.
- Shove accende e sposta un barile spento; anche con movimento bloccato il danno può essere valido.
- Spostare un barile accanto a Fire, a distanza ortogonale uno, accende la miccia.
- Un'esplosione che accende un altro barile avvia una nuova miccia: la catena è ritardata.
- Il limite è quattro **bombe** accese, condiviso fra lanci e prenotazioni; i barili hanno micce indipendenti.
- Uccidere il lanciatore non cancella una bomba se il fight continua.
- A fine Combat tutte le micce vengono disinnescate. Morte simultanea del player e dell'ultimo nemico produce Defeat.

Gli eventi `Object_Spawned`, `Explosive_Armed`, `Explosion` ed
`Explosive_Disarmed` mantengono countdown e replay osservabili.

### Loot magnetico

Il magnete raccoglie in Combat e Loot entro distanza Chebyshev tre, quindi
un quadrato massimo 7x7. Si controlla dopo l'azione accettata, dopo il pulse e
dopo gli spostamenti in Loot (in Loot pesca anche la [Canna da Pesca](#canna-da-pesca)). La raccolta non paga energia o pulse e ignora
LoS, muri, ostacoli, trappole e uscita: raccogliere da quelle celle non significa
entrarci.

Ogni raccolta usa una normale Action Collect con Gain_Gold o Heal e rimuove il
drop soltanto se accettata. Una cura a vita piena viene consumata con guarigione
effettiva zero. `Loot_Dropped` precede `Loot_Collected`, poi Gold_Gained o Healed;
la simulazione assegna tutto subito, la timeline ne mostra il percorso.
`create_room` prealloca il drop d'oro di ogni nemico più i drop curativi previsti,
così il resolver non deve far crescere il buffer durante le uccisioni.

## Carte e ciclo del mazzo

Sorgenti: [card.odin](src/game/card.odin), [card_play.odin](src/game/card_play.odin),
[deck.odin](src/game/deck.odin) e [refocus.odin](src/game/refocus.odin).

### Definizioni, istanze e compilazione

Una `Card_Definition` contiene nome, rarità, peso, prezzo, costo, policy,
targeting e fino a quattro effect template. Una `Card_Instance` contiene ID
non nullo, definizione, upgrade e lifetime. La Action compilata è temporanea:
non resta nel mazzo. La compilazione valida fase, istanza e definizione,
riesegue targeting e movimento, espande i destinatari per ID e controlla la
capacità prima di produrre effetti. Non paga energia e non modifica RNG.

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
| energia | massimo 3, recupero 1 per pulse |
| ID | unico `next_card_id` monotono, senza riciclo |

Lo starter deck ha dieci carte: Strike, Arc Bolt, Piercing Ray, Shove,
Firebomb, Guard, Toxic Wave, Thorn Coat, Afterimage e Dash.
La run tattica ([tactical_setup.odin](src/tactical_setup.odin)) sostituisce Arc
Bolt con **Fate Strike**, Piercing Ray con **Heavy Blow** e Toxic Wave con
**Battle Focus**, per provare subito dadi, interruzione e ricognizione, e
aggiunge una Shock Floor, una Tesla Coil, il 6 e il 7 di denari e un
**Movimento Ombra**: quindici carte. Il classico resta a dieci. In entrambi la
mano è mescolata, senza pesca garantita.
`begin_deck_combat` copia owned nel draw, imposta `combat_card_id_floor`,
mescola e pesca cinque carte. Un attrezzo da fine stanza, la
[Canna da Pesca](#canna-da-pesca), va invece subito fra le esaurite, da cui
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

Il diagramma seguente descrive il classico; nel tattico M8 il cast sostituisce
il pulse immediato e la pesca di rimpiazzo avviene al termine del cast.

```text
validazione e compilazione -> snapshot del deck -> pagamento
-> Hand → Resolving -> effetti e reazioni -> Discard oppure Exhaust
-> pulse se Combat continua -> pesca di rimpiazzo se possibile
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

Il cleanup viene validato e committato, poi si concede un pulse e, soltanto se
Combat continua, si pesca fino a cinque contando le retained. Refocus non
resetta l'energia: vale la rigenerazione normale. Anche una mano vuota è
valida. Se il pulse conclude il fight o uccide il player, niente refill;
il cleanup resta committed.

`Hand_Refocused` precede un `Card_Refocused` per ogni carta originale,
compreso `Hand -> Hand` per Retain; seguono pulse, raccolta e refill.
Questi eventi non sono intercambiabili con Card_Moved senza normalizzare la
causa. Durante la timeline del player il pulsante è disabilitato e `F` premuto
si perde: non resta in coda.

### Catalogo delle carte

La tabella seguente descrive il **catalogo classico** al livello base. Le
variazioni del catalogo tattico sono nella sezione [M7](#modalità-tattica-m7).
Le spell con dadi e rimbalzi sono descritte subito dopo. Rarità e metadati
completi restano in `CARD_DEFINITIONS`; l'upgrade è disponibile solo se
`card_can_upgrade` rileva un beneficio effettivo; per le carte con dadi il
beneficio è il dado successivo, fino al D20.

| Carta | Rarita | Costo | Anchor e forma | Effetto base |
|---|---|---:|---|---|
| `Strike` | Common | 1 | avversario o oggetto, Manhattan 1, Single | 3 danni, +1 per upgrade; accende barili |
| `Arc_Bolt` | Common | 2 | avversario o oggetto, Manhattan 1-3, Single, LoS | 3 danni, +1 per upgrade; accende barili |
| `Piercing_Ray` | Uncommon | 2 | cella, Chebyshev 1-5, Line | 2 danni a ogni nemico attraversato, +1 per upgrade |
| `Cross_Slash` | Uncommon | 2 | cella, Manhattan 1-3, Cross raggio 1 | 2 danni a ogni nemico nella croce, +1 per upgrade |
| `Firebomb` | Rare | 2 | cella, Chebyshev 1-3, Square raggio 1 | 2 danni a nemici e oggetti nel 3x3, +1 per upgrade; accende barili |
| `Guard` | Common | 1 | player, None | Shield 3 per 3 pulse |
| `Toxic_Wave` | Rare | 2 | implicito, None | 1 Veleno, +1 per upgrade, a ogni nemico |
| `Thorn_Coat` | Uncommon | 1 | player, None | Thorns 1 per 3 pulse |
| `Afterimage` | Uncommon | 1 | player, None | Afterimage 1 per 4 pulse |
| `Counter_Rune` | Rare | 1 | player, None | Retain; due contraccolpi, durata 4 pulse |
| `Battle_Focus` | Rare | 1 | player, None | Ethereal; pesca 2, poi exhaust |
| `Calculated_Risk` | Uncommon | 1 | player, None | pesca 2, poi scarta la carta piu a sinistra |
| `Spark_Forge` | Uncommon | 1 | player, None | crea una `Spark` temporanea |
| `Spark` | temporary only | 0 | avversario, Manhattan 1-2, Single | 2 danni, +1 per upgrade; exhaust on play |
| `Shove` | Common | 1 | avversario o oggetto, Manhattan 1, Single | 1 danno, +1 per upgrade; spinta di 1 cella |
| `Dash` | Uncommon | 2 | cella, Chebyshev 1-3, Line, LoS | attraversa la linea fino all'anchor |
| `Grappling_Hook` | Rare | 2 | avversario, Chebyshev 2-4, Line, LoS e actor stop | 1 danno, +1 per upgrade; trascina adiacente al player |
| `Heavy_Blow` | Common | 2 | avversario adiacente, Single | 5 danni, +1 per upgrade |
| `Venom_Needle` | Common | 1 | avversario, Chebyshev 1-3, Single, LoS | 1 danno, +1 per upgrade; 1 Veleno |
| `Caustic_Bloom` | Uncommon | 2 | cella, Chebyshev 1-3, Square raggio 1 | 2 Veleno, +1 per upgrade, ai nemici nel 3x3 |
| `Purifying_Guard` | Uncommon | 1 | player, None | Shield 2, +1 per upgrade, per 3 pulse; rimuove il Veleno se presente |
| `Volatile_Study` | Rare | 2 | player, None | Ethereal; crea 1 `Spark`, pesca 1 + upgrade, poi exhaust |
| `Sei_Denari` | starter, mai offerta | 1 | player, None | +6 oro; exhaust on play. Con il 7 in mano apre 6 RANCH 7 |
| `Sette_Denari` | starter, mai offerta | 1 | player, None | +7 oro; exhaust on play. Con il 6 in mano apre 6 RANCH 7 |
| `Shadow_Step` (Movimento Ombra) | Rare, starter tattico | 3 | player, None | solo tattica: 4 s reali nell'ombra; mondo, nemici, finestra e stordimento fermi; intangibile; solo passi dell'ombra (diagonale sui suoi battiti); risale sull'ultima casella. 0 s di finestra, senza upgrade. Il classico non la offre e la rifiuta (`Invalid_Phase`) |
| `Poison_Pool` (Pozza di Veleno) | Common | 1 | cella libera, Chebyshev 1-3, Single, LoS | solo tattica: una pozza fino alla fine della stanza; 2 Veleno, +1 per upgrade, a un nemico per ogni sua cella in cui entra; le aree che chiude si riempiono. 1 s di finestra. Il classico non la offre e la rifiuta |
| `Wildfire` (Incendio) | Uncommon | 2 | cella libera, Chebyshev 1-3, Single, LoS | solo tattica: un fuoco che cresce a croce (bracci da 1 a 4 caselle) a ogni nuova finestra e si spegne alla quinta; 1 Bruciatura, +1 per upgrade, a ogni ingresso e a chi prende fuoco. 2 s di finestra. Il classico non la offre e la rifiuta |
| `Deflect` | Uncommon | 1 | player, None | solo tattica: una carica di RIFLESSO, il prossimo colpo nemico torna all'attaccante; senza upgrade. 1 s di finestra |
| `Coffin` (Feretro) | Uncommon | 2 | player, None | solo tattica: 3 frecce, +1 per upgrade, da scoccare con `Ctrl` + clic. 1 s di finestra, e 1 s a freccia |
| `Fate_Dice` (Dado del Destino) | Rare | 2 | player, None | solo tattica, carta con dadi: 3 urti che tirano il dado del suo livello. 1 s di finestra |
| `Venom_Blade` (Lama Velenosa) | Common | 1 | player, None | solo tattica, carta con dadi: il dado decide quanti urti lasciano 2 Veleno. 1 s di finestra |
| `Lasso` (Lazzo) | Rare | 2 | nemico, Chebyshev 1-4, Single, LoS (non boss né miniboss: `Target_Too_Heavy`) | solo tattica: il nemico gira intorno al Viandante sul raggio libero più largo (4-1) fino alla morte; colpi crescenti dal primo (1, +1 per upgrade, fino al livello 5), -1 vita a ogni giro; schivate e spostamenti lo lasciano andare. 2 s di finestra. Il classico non la offre e la rifiuta |
| `Fishing_Rod` (Canna da Pesca) | Uncommon | 0 | casella libera, Chebyshev 1-3, Single, LoS (`Walkable_Cell`; mai l'uscita, trappole, bottino, pozze o fuochi) | solo tattica e mai in mano (attende fra le esaurite): a stanza liberata pesca dal suo slot, la casella diventa acqua; 95% cibo che cura un d4 (sempre un d4), 5% una carta del pool tattico nel mazzo; 1 pesca a stanza, +1 per upgrade fino al livello 5; una sola per run (`card_offer_exclusions`). 0 s. Il classico non la offre e non può giocarla come carta (`Invalid_Phase`) |
| `Pinball` | Rare | 3 | nemico, Chebyshev 1, Single, LoS (non boss né miniboss: `Target_Too_Heavy`; una palla alla volta: `Target_Blocked`) | solo tattica: il nemico diventa una palla d'acciaio che rotola a 7 caselle al secondo per 20 s del mondo, rimbalzando su muri, coperture, oggetti e nemici; valore 2 (+1 per upgrade fino al livello 5), +1 a ogni nemico colpito (spinto di una cella), di nuovo 2 a ogni cosa solida; poi scoppia e il nemico cade. 2 s di finestra. Il classico non la offre e la rifiuta |
| `First_Person` (First Person Shooter) | Rare | 3 | player, None | solo tattica: 20 s del mondo in prima persona (+2 per upgrade fino al livello 5, 30 s); un AK di carta da 6 colpi al secondo, 1 danno l'uno; passi secondo la vista, niente carte né frecce. 0 s di finestra. Il classico non la offre e la rifiuta |

## Spell e dadi

Sorgenti: [spell.odin](src/game/spell.odin), [dice.odin](src/game/dice.odin),
[spell_renderer.odin](src/render/spell_renderer.odin),
[dice_physics.odin](src/render/dice_physics.odin) e
[dice_playback.odin](src/render/dice_playback.odin).

`U` è il livello dell'istanza e `D` il dado del suo livello: D4 al livello 0,
poi D6, D8, D10, D12 e D20 al quinto e ultimo upgrade (`DICE_LADDER` in
[dice.odin](src/game/dice.odin)). Un upgrade di una carta con dadi cambia solo
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
([Deflect, Feretro, Dado del Destino e Lama Velenosa](#deflect-feretro-dado-del-destino-e-lama-velenosa)).
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
registrate; Shock Floor nomina il proprio dado nell'etichetta del risultato. Il
totale appare in un pannello laterale separato dalla mano. Il classico conserva
i D6 rossi con punti; gli altri dadi usano il set numerato anche lì. D10, D12 e
D20 sporgono dal cubo della simulazione: a riposo vengono separati sul piano
durante l'ultimo assestamento, senza toccare il volo.

Riferimenti fotografici dei modelli: [tavola locale dei dadi](references/dice/index.html),
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

## Nemici e combattimento tattico

Sorgenti: [enemy_intent.odin](src/game/enemy_intent.odin),
[bomber.odin](src/game/bomber.odin), [custodian.odin](src/game/custodian.odin),
[miniboss.odin](src/game/miniboss.odin) e [room_modifier.odin](src/game/room_modifier.odin).

### Intenti committed

Nel classico ogni nemico conserva un `Enemy_Intent` per `pulse_count + 1`, con origine,
percorso, destinazione, celle minacciate e danno. Protect conserva anche ID e
cella dell'alleato. Il piano è un impegno sulle celle, non una Action con target
che segue il player. Viene creato all'ingresso e dopo ogni pulse, mai per un
comando rifiutato o durante la risoluzione corrente.

La pianificazione ordina gli ID e aggiorna una copia delle posizioni previste:
i nemici successivi vedono le prenotazioni, senza occupare la stessa
destinazione. Il planner non usa RNG; il Demolitore aggiorna fase e ciclo al
confine della nuova pianificazione. La BFS dal player usa scratch buffer della
Room e considera muri e oggetti solidi; gli attori sono gestiti dalle prenotazioni.

La risoluzione fotografa gli ID vivi, consuma prima i Protect e poi gli altri
intenti in ordine di ID. Ogni nemico agisce al massimo una volta; morti e
rimozioni unordered non invalidano l'iterazione. Eventuali spawn agiranno dal
pulse successivo. Origine spostata, cella liberata o percorso occupato producono
`Attack_Missed` o `Move_Blocked`, senza retargeting. Gli attacchi a distanza
ricontrollano anche la LoS. In Loot e Defeat i piani vengono azzerati.

### Archetipi

Questa tabella descrive il profilo classico; mira, fendenti, recuperi e protezioni
del profilo corrente sono descritti nella sezione [M7](#modalità-tattica-m7).

| Archetipo | Regole principali |
|---|---|
| Chaser | melee se adiacente, altrimenti un passo ortogonale che riduce la distanza BFS; Wait se impossibile |
| Archer | tiro ortogonale con LoS a Manhattan 2–5; da adiacente arretra o attacca; fuori finestra usa il Chaser |
| Brute | carica ortogonale a distanza 2–4, impatto doppio, poi recupero 1; altrimenti melee/Chaser |
| Bomber | lancia a Manhattan 2–5 anche oltre coperture, poi recupero 1; da adiacente arretra o attacca |
| Custodian | protegge un alleato a Manhattan 1–2 con LoS, poi recupero 1; altrimenti cerca gli alleati o avanza |
| Demolitionist | boss con 30 HP, attacco base 2 e ciclo a due fasi |

Il Chaser risolve le parità preferendo l'asse con distanza maggiore, poi X,
poi North, East, South, West. L'Archer prova le ritirate nello stesso ordine
cardinale e conserva la prima alla massima distanza. Il Brute verifica tutta
la carica: se il percorso è bloccato non muove né colpisce; se il player ha
schivato completa il movimento e manca l'impatto. Anche un tentativo fallito
lascia il recupero previsto.

Il Bombarolo preferisce la cella del player, poi una delle otto vicine libere
da oggetti; le anchor sono prenotate senza duplicati. Spostare il lanciatore
o occupare l'anchor invalida il lancio, che conserva comunque il recupero.

Il Custode preferisce alleati senza almeno tre Shield, vicini al player e di
altri archetipi; le parità si risolvono per ID. `SHIELD 3` concede protezione
per due decisioni del player: durata interna tre perché il primo tick segue
subito. Spostare Custode o alleato, ucciderli o interrompere la LoS invalida il
piano. Lo Shield già applicato non dipende più dalla distanza.

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
base a player, nemici e oggetti. Il primo scatto segue due azioni accettate;
poi ci sono due pulse di pausa e due di preavviso, per una cadenza di quattro.
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
`SHIELD 3` e `RECOVER N`, senza prendere decisioni. I limiti per intento sono
otto celle di percorso e sedici minacciate; la BFS non pianifica ancora code
su più pulse e gli altri nemici non sono copertura per l'Archer.

## Rotta e generazione delle stanze

Sorgenti: [run.odin](src/game/run.odin),
[run_validation.odin](src/game/run_validation.odin),
[room_generation.odin](src/game/room_generation.odin),
[encounter_director.odin](src/game/encounter_director.odin),
[room_generation_objects.odin](src/game/room_generation_objects.odin) e
[level.odin](src/level/level.odin).

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

Il profilo classico usa Combat 15×9, Elite 17×10, Boss 19×11.
Il profilo tattico delle prime due profondità usa rispettivamente 17×11,
19×12 e 21×13, con due nemici aggiuntivi e budget +3. Per questi casi la
geometria, i contenuti e lo stream casuale precedenti sono conservati;
le profondità successive usano la progressione qui sotto.
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
oggetti; nemici e trappole possono usarli. Nei profili classici e introduttivi, Combat contiene tre oggetti, quattro
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

Sorgenti: [arena_progression.odin](src/game/arena_progression.odin),
[complex_room.odin](src/level/complex_room.odin) e
[tactical_framing.odin](src/render/tactical_framing.odin).

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

Sorgenti: [reward.odin](src/game/reward.odin), [economy.odin](src/game/economy.odin),
[shop.odin](src/game/shop.odin), [special_node.odin](src/game/special_node.odin).

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
[Canna da Pesca](#canna-da-pesca): finché il mazzo ne ha una,
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

Sorgenti: [relic.odin](src/game/relic.odin),
[relic_effects.odin](src/game/relic_effects.odin) e
[run_relic_reward.odin](src/game/run_relic_reward.odin).

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

## Timeline e input

Sorgenti: [presentation_timeline.odin](src/render/presentation_timeline.odin),
[frame_timeline.odin](src/render/frame_timeline.odin),
[gameplay_input.odin](src/gameplay_input.odin).

### Due stati, un solo gameplay

Il percorso seguente descrive un segmento committed. In M7 un comando del
player può accodare un pulse, poi `Continue_Pulse` ne risolve i segmenti; un
QTE può sospendere la sequenza prima del danno. Ogni segmento cattura i propri
snapshot ed eventi. Nessuna correzione viene applicata a posteriori al replay.

```text
comando -> snapshot prima -> simulazione sincrona -> eventi + snapshot finale
                                |                         |
                            Room finale            replay sulla copia
```

`commit_gameplay_command` cattura le viste prima e dopo
`execute_gameplay_command`. Solo un risultato committed avvia la timeline;
un comando senza eventi non la rende busy. Room è già nello stato finale,
mentre `Room_Presentation` riproduce gli eventi su una copia arretrata.
La copia non viene mai scritta nella simulazione.

La vista conserva attori, oggetti, trappole, loot, deck, status, reliquie,
famiglia, modifier e fase del boss. Gli ID restano validi anche se l'entità
è stata rimossa dalla Room. I cue rispettano il log: movimento, trigger,
Shield/danno, morte, drop e raccolta si mostrano nell'ordine causale.
Card_Played paga e sposta in Resolving; Draw riproduce reshuffle e RNG;
Create deve generare lo stesso ID; mismatch rollbackano la mutazione visuale.

`Explosion` nasconde la sorgente prima dei danni. Il countdown usa il pulse
dello snapshot. `Room_Hazard_Triggered` mostra Furnace e aggiorna la scadenza;
`Pulse_Advanced` sincronizza durate, energia, reliquie e nuova fase del boss.
La Fornace viene disarmata anche se il comando conclude Combat senza pulse.
Il set dei reaction binding non è copiato: i relativi eventi mostrano avvisi.

Di norma è attivo un cue; eventi contigui, compatibili e con lo stesso
`visual_group` esplicito possono animarsi insieme. Firebomb usa questa regola
per gli effetti diretti, applicando comunque le mutazioni in ordine e usando
la durata massima del gruppo. Somiglianza o vicinanza non autorizzano gruppi;
reazioni, movimenti e frontiere dei pulse restano separate.

Il delta residuo passa ai cue successivi, salvo i limiti per frame dei dadi.
Oltre dodici secondi nominali, la sequenza ordinaria comprime proporzionalmente
le durate. In M8 `fit_card_cast_timeline` adatta poi i gruppi non cinematici alla
durata della carta: dadi esclusi dal costo, cast e dadi non accelerabili con F4.
`PRESENTATION_TIME_SCALE` maggiore di uno le allunga; la velocità runtime
0.25x–4x scala invece il delta, viene conservata fra stanze/restart e non cambia
il gameplay. Corpi animati usano un clock cosmetico; clip evento seguono il cue.

### Input senza coda e transizioni

**Nessun comando resta in coda**, in nessuna modalità (classico, tattico, Prova
meccaniche e laboratori: `route_gameplay_command` in
[beat_input.odin](src/beat_input.odin)). Mentre è in corso l'azione del player
stesso, cioè la sua animazione nella timeline, i secondi di un'azione a tempo o
il passo da 0,4 s dell'ombra di [Movimento Ombra](#movimento-ombra), una
pressione viene scartata; agisce solo una pressione fatta dopo la fine
dell'azione. Il poll continua a girare, così hover, `Esc` e l'annullamento del
drag rispondono, ma il suo comando non viene tenuto. Lo stesso vale per la
freccia di Feretro (`Ctrl` + clic, il comando `Shoot`): un'azione da 1 s come le
altre, mai tenuta per dopo e mai segnata con lo scocco. La schivata
`Shift + WASD` che interrompe un'azione a tempo è una regola del gioco, non una
coda, e così il grilletto dell'AK di
[First Person Shooter](#first-person-shooter): finché il tasto è tenuto spara un
colpo ogni sesto di secondo come comando del mondo (`First_Person_Fire`, come i
giri del Lazzo e la corsa del Pinball), e da un fotogramma all'altro non porta
più del ritardo di un colpo; un clic fatto prima che la vista prenda il mouse
non spara finché non lo si rilascia. L'unico input che attraversa qualche
fotogramma è il passo premuto sul secondo, che aspetta al massimo
`BEAT_CHORD_SECONDS` (0,06 s) il tasto perpendicolare della diagonale: vive in
`Buffered_Gameplay_Command`, e ogni confine che svuota quella struttura
(controller bloccato, fine della finestra, QTE, pausa, mappa, schivata o
diagonale, perdita del focus, restart, nuova stanza, schermate) lo lascia
cadere. I comandi portano valori logici e ID, mai puntatori o indici visuali, e
la fase d'origine: un Move nato in Combat non diventa implicitamente un Move in
Loot. Tenere un tasto premuto non genera repeat.

Nel classico, mentre lo snapshot è arretrato, drag, drop, click spaziali, range
e intenti a terra sono sospesi; il drag attivo si annulla. Gli slot della
tastiera si risolvono contro la mano visibile: una carta pescata non è
disponibile prima del relativo cue. Nuove selezioni spaziali aspettano che la
timeline sia idle. Nel tattico la timeline dei nemici non blocca le azioni del
player: cast, cinematiche e QTE mantengono gate espliciti. La camera resta
indipendente.

`finish_room` e le schermate Reward, Victory e Defeat aspettano l'ultimo cue.
Restart, nuova stanza e cambio schermata svuotano la timeline e lasciano cadere
il passo in attesa; anche l'apertura manuale della mappa richiede idle e
cancella il vecchio contesto.

### Diagnostica ed estensioni

Timeline e log hanno 416 slot; lo snapshot conserva 32 nemici, 64 trappole,
32 oggetti e 96 drop (oro, cura e arma per ciascuno dei 32 nemici). `dropped_count` segnala perdite; `update_failures`
segnala eventi non applicabili. Lo snapshot `F8` mostra anche il passo in
attesa della diagonale (`chord_active`, `chord_direction`, `chord_timer`).
Controllare lo stato intermedio dei cue nei test: la convergenza finale può
nascondere errori nell'ordine visuale.

Per un evento nuovo: payload sufficiente, mapping esaustivo a cue, durata,
mutazioni start/finish, interpolazione, disegno e verifica di ordine e delta
in eccesso. Il renderer non deve recuperare payload mancanti dalla Room futura.
Per un comando nuovo: kind e payload stabili, polling senza mutazioni,
API autorevole, criterio committed, snapshot e fase d'origine
(`gameplay_command_is_valid`).

| Sintomo | Controllo |
|---|---|
| salto visivo / danno su entità scomparsa | ordine eventi, ID, payload from/to, start/finish, update_failures |
| ultimo feedback tagliato | guardia timeline idle prima della transizione |
| input perso | premuto durante la propria azione (scartato per regola) o a controller bloccato: `player_animation_blocks_input`, fase e timeline nello snapshot `F8` |
| comando vecchio nella stanza nuova | passo in attesa della diagonale non lasciato cadere a quel confine (`clear_gameplay_command_buffer`) |
| preview diversa dall'esito | targeting attivo su snapshot arretrato |
| coda incompleta | dropped_count e budget eventi |

## Sprite e animazioni personalizzate

Il renderer può sostituire il corpo del giocatore e dei nemici con PNG, sprite sheet PNG o GIF animate. La vista classica supporta anche gli sprite degli oggetti; nella scena 3D M7 gli oggetti restano mesh a blocchi. Supporta anche clip per lancio, proiettile, impatto e danno, sincronizzate con gli eventi di combattimento. Gli indicatori di salute, le intenzioni e le micce restano gestiti dal gioco. Senza un asset valido continua a essere usata la grafica incorporata di quel tipo o effetto.

Non sono incluse nuove illustrazioni: il sistema permette di inserire le proprie immagini senza ricompilare.

### Avvio rapido

1. Crea `assets/sprites.json`, prendendo come riferimento [assets/sprites.example.json](assets/sprites.example.json).
2. Inserisci le immagini nelle posizioni indicate dal manifest. I percorsi dei file sono relativi alla cartella che contiene il manifest.
3. Avvia `odin run src -o:none`. Il manifest predefinito è `assets/sprites.json`, relativo alla directory di avvio.

Per usare un altro pacchetto:

```sh
odin run src -o:none -- --sprites=/percorso/del/pacchetto/sprites.json
```

Per cominciare con una sola immagine statica:

```json
{
  "version": 1,
  "sprites": [
    {
      "key": "player",
      "file": "player.png",
      "width": 32,
      "height": 48,
      "anchor": [0.5, 1.0]
    }
  ]
}
```

Non occorre specificare gli altri tipi. Riavvia il gioco dopo aver modificato il manifest o un'immagine; il caricamento avviene una sola volta all'avvio.

### Tipi e dimensioni

Le chiavi dei corpi, animate in loop durante l'attesa, sono `player`, `chaser`, `archer`, `brute`, `bomber`, `custodian`, `demolitionist`, `ice_block`, `fire`, `barrel` e `bomb`. Le clip evento usano le otto chiavi descritte più sotto. Ogni chiave può apparire una sola volta nello stesso manifest, che mantiene `version: 1`.

| Campo | Significato | Valore predefinito |
| --- | --- | --- |
| `file` | PNG o GIF; il formato viene riconosciuto dal contenuto | Obbligatorio |
| `width`, `height` | Dimensioni sul canvas con zoom 1; seguono lo zoom della camera | Dimensioni di un frame |
| `anchor` | Punto dell'immagine che coincide con la posizione dell'attore, oggetto o effetto, da 0 a 1 | `[0.5, 1.0]`, centro in basso |
| `columns`, `rows` | Griglia regolare dei frame di uno sheet PNG | `1`, `1` |
| `frames` | Numero di frame PNG usati, in ordine da sinistra a destra e dall'alto al basso | Tutte le celle dello sheet |
| `fps` | Velocità del loop in frame al secondo; ignorata dalle clip evento | `8` |

Lo zoom 1 usa tessere larghe 64 e alte 32 pixel. Per gli attori sono un buon punto di partenza immagini mostrate a 32 × 48 pixel; conviene assegnare sempre dimensioni esplicite se il file sorgente è grande. Gli sprite possono avere margini trasparenti: adatta `anchor`, per esempio `[0.5, 0.9]`, se i piedi non arrivano al bordo inferiore dell'immagine.

Le immagini vengono disegnate con filtro nearest-neighbor, adatto alla pixel art. La selezione usa l'alpha del frame visibile: la testa rialzata di uno sprite è cliccabile, mentre i margini trasparenti lasciano passare il puntatore. Il bersaglio resta sempre la cella dell'entità; portata, collisioni e regole delle carte restano invariati.

### GIF e sprite sheet

Per una GIF indica soltanto `file`, dimensioni, eventuale `anchor` e `fps`. Non impostare `columns`, `rows` o `frames`: i frame provengono dal file GIF. Le animazioni dei corpi vengono ripetute a velocità uniforme; le durate originali dei singoli frame GIF e il numero di ripetizioni non vengono usati. Raylib non espone le durate attraverso la funzione di caricamento impiegata.

Uno sprite sheet PNG deve avere dimensioni divisibili per `columns` e `rows`. `frames` permette di escludere celle vuote finali. Tutte le istanze del corpo di uno stesso tipo condividono la fase del loop. Questa animazione è cosmetica e non fa avanzare impulsi, intenzioni o RNG; le animazioni di spostamento e combattimento del gioco continuano ad applicarsi allo sprite.

### Clip collegate agli eventi

Le clip evento partono quando il renderer presenta il relativo lancio, volo, impatto o danno. Non vengono riprodotte continuamente: terminano insieme alla fase dell'evento che le contiene.

| Chiave | Uso |
| --- | --- |
| `player_cast` | Animazione del giocatore durante il lancio |
| `player_hit` | Animazione del giocatore quando subisce danno |
| `firebomb_cast` | Effetto di preparazione/lancio di Firebomb |
| `firebomb_projectile` | Proiettile di Firebomb, lungo il suo percorso |
| `firebomb_impact` | Impatto di Firebomb |
| `chain_bolt` | Effetto di un fulmine di Chain Lightning |
| `fate_cast` | Effetto di lancio di Fate Strike |
| `fate_impact` | Effetto di risoluzione di Fate Strike |

Le clip accettano PNG statici, sheet PNG e GIF con gli stessi campi dei corpi. Per un'esplosione o un fulmine centrato sulla posizione dell'effetto è spesso più comodo `anchor: [0.5, 0.5]`; per `player_cast` e `player_hit` usa dimensioni e anchor compatibili con il corpo `player`.

```json
{
  "version": 1,
  "sprites": [
    {
      "key": "firebomb_impact",
      "file": "effects/firebomb_impact.png",
      "columns": 4,
      "rows": 2,
      "frames": 8,
      "width": 112,
      "height": 96,
      "anchor": [0.5, 0.5]
    }
  ]
}
```

La durata di una clip si adatta alla durata della fase di presentazione del gioco. `fps` influenza soltanto i loop dei corpi: non accelera né rallenta un'azione. All'inizio viene mostrato il primo frame, alla fine l'ultimo, senza tornare al primo. Due impatti contemporanei possono usare lo stesso file e avere progressi diversi; non si azzerano né si sincronizzano a vicenda. Un PNG statico resta visibile per la durata della fase.

Il manifest può contenere insieme corpi e clip; è possibile sostituire soltanto gli effetti desiderati. Le clip mancanti mantengono gli effetti procedurali. Le clip non sono bersagli selezionabili e non alterano collisioni o risultati del combattimento. Questa versione non aggiunge animazioni distinte per direzione.

### Caricamento e limiti

I file condivisi da più chiavi usano la stessa texture, anche quando una chiave è un corpo in loop e l'altra è una clip evento. I frame GIF vengono riuniti in un atlas, caricato sulla GPU una sola volta; durante il gioco non vengono decodificate GIF né ricaricate texture. Le risorse GPU e le maschere alpha vengono liberate prima della chiusura della finestra.

- Manifest fino a 64 KiB, con un massimo di 19 associazioni: 11 corpi e 8 clip evento.
- File PNG/GIF fino a 16 MiB; massimo 128 frame e 8 milioni di pixel decodificati per file/atlas.
- Texture con lato massimo di 4096 pixel; budget complessivo di 32 milioni di pixel.
- Dimensioni visualizzate positive fino a 256 pixel per asse e velocità fino a 60 fps.

Dimensioni PNG e struttura GIF vengono controllate prima della decodifica. Manifest mancante, file non validi o configurazioni incompatibili conservano la grafica procedurale; un errore di un singolo sprite non impedisce il caricamento degli altri.

### Verifica grafica

```sh
odin run src -o:none -- --smoke-sprites
```

Il comando crea PNG e GIF di prova temporanei, verifica condivisione delle
texture fra corpi e clip, primo e ultimo frame di una clip leggendo i pixel
renderizzati sulla GPU, cambio di frame GIF, selezione trasparente e fallback, poi salva
`odin_pp_sprites.png` e chiude la finestra. Lo screenshot mostra anche la barra
di salute di un Ice Block danneggiato sopra lo sprite personalizzato. Le immagini
di prova vengono rimosse; non costituiscono un pacchetto grafico per la run.

## Telemetria e playtest

Sorgenti: [telemetry.odin](src/combatdebug/telemetry.odin),
[session.odin](src/combatdebug/session.odin), [report.odin](src/combatdebug/report.odin),
[kiting.odin](src/combatdebug/kiting.odin) e [playtest_session.odin](src/playtest_session.odin).

Il dispatcher condiviso da input, controller e driver di prova cattura uno snapshot
pre-comando e un descrittore della carta, esegue l'API autorevole e passa
esito e Room finale a `observe_command_detailed`. Il tipo è esplicito:
un Move contro un nemico viene classificato Bump_Attack prima della risoluzione,
anche se il colpo termina il combattimento.

Un rifiuto incrementa attempted/rejected senza leggere un log precedente.
Per i commit si aggrega `Room.recent_events`, verificando marker Pulse_Advanced
e delta del pulse; perdite o mismatch rendono il sample incompleto.
Il perimetro della carta va da Card_Played alla sua uscita da Resolving,
separando danno diretto, reazioni, status, trappole e risposta nemica.
`has_status_cause/status_cause` attribuisce i tick anche quando Shield assorbe tutto.

Le metriche contano comandi e carte, pulse, target previsti/effettivi, danni
subiti/diretti/indiretti/assorbiti, energia spesa/recuperata/sprecata, Poison,
Refocus, movimento forzato e hazard. I campi `object_hazard_*` distinguono
trigger e danno effettivo su player e nemici. Il confronto bump/Strike/Heavy
Blow considera solo decisioni in cui tutte e tre le opzioni erano disponibili.

`Playtest_Session` apre e chiude ogni fight una volta sola; il giro Loot non
contamina i campioni. Il JSON ha `schema_version = 1`, seed, outcome Victory,
Defeat o Abandoned, completezza, metadata del nodo, aggregati e sample ordinati.
Usa interi e booleani, senza timestamp, hash map o dati del renderer: stessa
sequenza e seed producono gli stessi byte.

```sh
odin run src -o:none -- --seed=0xC0FFEE --playtest-report
odin run src -o:none -- --playtest-output=/percorso/sessione.json
odin run src -o:none -- --smoke-playtest
```

Il report interattivo viene scritto a fine run, restart o chiusura come
`odin_pp_playtest_<seed>.json`; creazione esclusiva e suffissi `_1`, `_2`, ecc.
proteggono anche sessioni concorrenti. Il percorso esplicito è una base con la
stessa protezione; la directory deve esistere. Il nome effettivo è stampato
fuori dal JSON. Lo smoke headless non inizializza Raylib e sovrascrive invece
intenzionalmente `odin_pp_playtest_smoke.json` o il file esatto scelto con output.

La policy headless considera North, East, South, West e Wait. Valida le mosse
con Movement_Query, tratta Wait separatamente, minimizza danno da hazard,
evita le celle minacciate, massimizza distanza minima e somma delle distanze,
poi preferisce la direzione precedente e l'ordine fisso dei candidati.
Termina per budget, fine fight, sconfitta o comando rifiutato.

### Domande per il bilanciamento

| Azione melee base | Danno | Energia | Pulse se il fight continua |
|---|---:|---:|---:|
| bump attack | 2 | 0 | 1 |
| Strike | 3 | 1 | 1 |
| Heavy Blow | 5 | 2 | 1 |

Heavy Blow concentra danno in una sola risposta nemica; il valore non si misura
soltanto in danno per energia. Prima di aggiungere nuove primitive, confrontare
più run riproducibili e misurare:

- scelta fra bump, Strike e Heavy Blow, danno subito ed energia sprecata;
- quanti Venom Needle ottengono almeno due tick prima della morte del bersaglio;
- numero medio di nemici colpiti da Caustic Bloom;
- quante Purifying Guard rimuovono davvero Poison;
- Volatile Study giocata o exhaustata da Refocus, rispetto a Battle Focus;
- spinte/pull che attivano hazard o invalidano intenti;
- Refocus come ricerca di una risposta o semplice recupero di una mano debole.

Root, coni e costi dinamici devono rispondere a un bisogno ripetuto dei
playtest, non alla sola possibilità tecnica di aggiungerli.

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

## Roadmap e manutenzione

Una milestone è completa quando è integrata nella demo, coperta da test delle
invarianti e descritta dalla documentazione. Stati: `[x]` completata,
`[~]` in corso, `[ ]` pianificata.

| Milestone | Stato | Risultato / lavoro restante |
|---|---|---|
| Baseline | [x] | loop della run, griglia, azioni, deck, intenti, timeline e input |
| M1 + M1A | [x] | stanze procedurali, quattro famiglie, placement tattico, seed e commit transazionale |
| M2 | [x] | rarità, reward pesate, upgrade, rimozione e Shop |
| M3 | [x] | nodi Shop, Rest, Event e Treasure con distribuzione e scelte one-shot |
| M4 | [~] | profondità di carte e status; sotto-incrementi elencati qui |
| M4A | [x] | Resolving, Exhaust, temporanee, Draw/Discard/Create |
| M4B | [~] | Refocus, Retain ed Ethereal completati; costi/rigenerazione dinamici e scarto selezionato restano da fare |
| M4C | [x] | movimento condiviso, hazard, Shove/Dash/Grappling Hook |
| M4C.1–M4C.2 | [x] | content pass e telemetria deterministica |
| M4C.3–M4C.5 | [x] | oggetti, Fire persistente, esplosivi e prima zona tattica |
| M4D | [ ] | nuovi trigger e scadenze, coni e nuove footprint motivate dal playtest |
| M4E | [x] | sei reliquie, acquisizione e sinergie |
| M4F | [x] | spell, pool di dadi, catene, gruppi di impatto e laboratori |
| M5 + M5A | [~] | M5A completata: cooperazione, composizioni e primo boss; restano altri elite/boss, evocazione, controllo e nuove geometrie nemiche |
| M6 + M6A | [~] | M6A completata: sprite, GIF, sheet e clip; M8 salva gli sblocchi, M9 registra input in memoria; restano salvataggio run, replay su disco e ulteriori feedback |
| M7 | [~] | prototipo M7A–M7F integrato; M7G attende playtest umano e bilanciamento |
| M7A | [x] | timer decrescente e cicli di recupero locali alla stanza; statistiche cumulative della run |
| M7B | [x] | visibilità locale 7×7 predefinita, confronto 2/3/5/7/9 senza memoria, ologramma 3D ruotabile e con countdown attivo |
| M7C | [x] | più azioni per finestra con costi in tempo; recupero mobile fisso al posto della preparazione anticipata |
| M7D | [x] | QTE da tastiera difficile per un passo diagonale, con esito e costo espliciti |
| M7E | [x] | difese abilitate da carte/condizioni, in alcuni casi con QTE da tastiera |
| M7F | [x] | ambiente 3D illuminato con sprite 2D, camera prospettica orbitabile e parallasse |
| M7G | [~] | stress e run terminali deterministiche, telemetria e smoke grafico completati; bilanciamento manuale da fare |
| M7H | [x] | revisione leggibilità: mano completa senza sovrapposizioni, dettagli carta, selezione con clic e mappa con pulsante dedicato |
| M7I | [x] | veste dark fantasy pixel: font incorporato, carte e sprite illustrati, pietra e archi gotici, HUD avorio/cremisi e ologramma rosso con legenda |
| M7J | [x] | art delle carte più pixelata, ambiente e fog a blocchi 3D, nemici adattati alle nuove interazioni e menu unificati; bilanciamento umano in M7G |
| M7K | [x] | blocchi grigio-blu lucidi senza fondali, vista ampliata, stanze più grandi e due nemici aggiuntivi, schivata senza carte con recupero e dadi 3D coordinati |
| M7L | [x] | catalogo tattico, interruzione/ricognizione/contrattacco, ruoli nemici e recuperi leggibili, pannello nemico e starter aggiornato; bilanciamento umano in M7G |
| M8 / 0.4 | [x] | cast e cinematiche separati, Shock Floor/Tesla, arma a utilizzi, scheda 3D, ring giocabile con sblocchi persistenti e contorni da illustrazione |
| M9A — arena libera | [x] | clock 60 Hz, movimento continuo X/Z, collisioni corpi/solidi, raycast, layer e livelli con coperture |
| M9B — ring | [x] | duello live libero, mosse configurabili, guardia, schivata, presa a quattro pose, hit-stop e ritorno alla run con sblocco singolo |
| M9C — FPS | [x] | due stanze, arma con caricatore/riserva/ricarica, tre nemici con telegraph, vittoria/sconfitta e gestione del cursore |
| M9D — strumenti | [x] | laboratorio mouse, collider/hitbox, passo singolo, preset mosse JSON validati e replay degli input in memoria |
| M9 / 0.5 | [x] | engine condiviso in tredici package, run come scena, menu e impostazioni, sei prove (platform 2D e 3D, arena, FPS, puzzle, ring unificato) e sfide nella run; launcher e script Windows disponibili |
| Dopo M9 | [ ] | bilanciamento umano di run e minigiochi, input del roguelike su action map (rimappatura, pad), timeline di presentazione generica nell'engine, altri oggetti/armi; salvataggio completo della run |

### M7: implementazione e verifiche storiche

Il prototipo M7 è stato integrato il 9 ottobre 2026. Questa sezione conserva
la cronologia della base su cui interviene M8; per tempo, dispositivi e
persistenza correnti vedere [M8](#m8-versione-04). Le attività ancora aperte
di M4–M6 restano valide. M8 salva gli sblocchi, ma non la run o replay completi.

| Incremento | Sorgenti / contratto implementato |
|---|---|
| M7A | [tactical.odin](src/game/tactical.odin), [tactical_controller.odin](src/tactical_controller.odin): pressione azzerata alla creazione riuscita di una nuova stanza; clock fornito dall'app; timeout esplicito; recupero fisso di 1 secondo attivo |
| M7B | visibilità logica senza memoria, condivisa col targeting; il renderer ricostruisce la maschera sullo snapshot mostrato; ologramma completo consultabile con countdown attivo |
| M7C | [card_play.odin](src/game/card_play.odin): base del costo temporale; in M8 il pagamento avviene durante il cast e il refill alla sua conclusione; carte sospese durante il recupero mobile |
| M7D | QTE diagonale con input ordinati, validazione del movimento e un secondo per successo o fallimento; nessun attraversamento degli angoli bloccati |
| M7E | pulse segmentato con ordine Protect/priorità per ID conservato; attacco fermato prima del danno, QTE da tastiera, ripresa una sola volta; difese disponibili anche durante il recupero |
| M7F | [tactical_renderer.odin](src/render/tactical_renderer.odin): terreno 3D, sprite su quad, alpha e profondità, [tactical_scene.odin](src/render/tactical_scene.odin): camera orbitabile, shader di luce/nebbia e geometrie; picking coerente con la camera; [hologram.odin](src/render/hologram.odin): schermo dedicato con miniature distinte, rotazione e zoom |
| M7H | [tactical_hand.odin](src/render/tactical_hand.odin): dock leggibile, dettagli effetti/QTE, targeting e costi visibili |
| M7I | [gothic_theme.odin](src/render/gothic_theme.odin), [assets/gothic](assets/gothic): atlanti trasparenti incorporati, font Jersey 10 con licenza OFL, pergamena, palette e cornici; sprite esterni e picking alpha conservati |
| M7J | [voxel_scene.odin](src/render/voxel_scene.odin): props, fog e minacce nello spazio 3D; [enemy_tactical_ai.odin](src/game/enemy_tactical_ai.odin): percorsi pesati, bombe annunciate, spinte e interazioni ambientali; [menu_theme.odin](src/render/menu_theme.odin): tema condiviso delle schermate |
| M7K | [resin_material.odin](src/render/resin_material.odin): materiale e mesh smussate condivisi con i dadi; [tactical_dodge.odin](src/game/tactical_dodge.odin): schivate attive/reattive e recupero; [room_generation.odin](src/game/room_generation.odin): profilo M7 ampliato; [m7_resin_smoke.odin](src/m7_resin_smoke.odin): avvio reale e tiro di tre dadi da carta |
| M7L | [tactical_cards.odin](src/game/tactical_cards.odin): catalogo e status; [tactical_enemy_inspector.odin](src/render/tactical_enemy_inspector.odin): lettura dei nemici; [m7_rework_smoke.odin](src/m7_rework_smoke.odin): interruzione, recupero e ricognizione tramite comandi reali |
| M7G | [m7_smoke.odin](src/m7_smoke.odin), [m7_view_smoke.odin](src/m7_view_smoke.odin): stress, confronto classico/M7, replay deterministico dei driver e verifica GPU; prove umane ancora da fare |

`Player.tactical` conserva configurazione, budget, cicli e metriche. La Room
possiede il cursore del pulse, il QTE attivo e la pesca rinviata. Ogni
continuazione produce un log limitato: il debito di tempo non accumula tutti i
beat nei 416 slot di un singolo comando. Fine del combattimento e restart
cancellano continuazioni/QTE; una nuova stanza azzera il contatore di finestre,
il recupero schivata e ripristina budget/timer. Configurazione e metriche
restano nel player della run. Il clock decisionale e quello QTE non dipendono da
FPS, `--fast` o velocità delle animazioni.

I comandi M7 passano dal dispatcher condiviso: `Timeout`, `Continue_Pulse`,
`Begin_Diagonal`, `Defense`, `QTE_Key`, `QTE_Fail`.
Il pulse conserva gli intenti committed; parry e deviazione annullano la
risoluzione dell'attacco senza riscriverne il piano. I comandi ordinari non
possono intervenire mentre una risposta è sospesa.

```sh
sh scripts/check.sh
odin run src -o:none -- --smoke-m7
odin run src -o:none -- --smoke-m7-view
odin run src -o:none -- --decision-time=15 --vision=2 --playtest-report
```

Lo smoke headless scrive `odin_pp_m7_stress.json`: dieci combinazioni di
15/20 secondi e visibilità completa/2×2/3×3/5×5/7×7, ripetute due volte. Ogni arena
raggiunge otto cicli e otto beat di recupero. La salute elevata dell'arena serve
a verificare cicli ripetuti, non a stimare il bilanciamento. Quattro run con
statistiche normali confrontano classico/M7 su due seed fino a Victory o
Defeat, anch'esse ripetute; il driver semplice non rappresenta un giocatore
esperto e può perdere. Ogni percorso controlla commit, log e terminazione.

Lo smoke grafico salva `odin_pp_m7_scene.png`, `odin_pp_m7_hologram.png`,
`odin_pp_m7_hologram_rotated.png`, `odin_pp_m7_cards.png`,
`odin_pp_m7_full_hand.png`, `odin_pp_m7_diagonal.png` e `odin_pp_m7_defense.png`; ruota e ingrandisce
l’ologramma verificando che consumi tempo, esegue una diagonale e
un parry usando i comandi reali, verifica un solo avanzamento del pulse contenente il parry e la sincronizzazione
della timeline. Cattura inoltre `odin_pp_m7_voxels_0/1/2.png` per oggetti,
camera ruotata e confronto senza fog; salva schermate di reliquie, ricompense,
rotta, mercante, riposo, eventi, tesori, vittoria e sconfitta, poi chiude la
finestra. Le scene di combattimento sono arene controllate.
`odin_pp_m7_expanded_room.png` mostra invece il primo incontro realmente
generato; `odin_pp_m7_expanded_overview.png` ne mostra il confronto senza fog.
`odin_pp_m7_resin_dice_0/1.png` catturano rimbalzo e assestamento di tre dadi,
prodotti da una giocata reale di Prismatic Barrage: il playback verifica
che lo stato RNG non cambi e che la timeline termini senza errori.
`odin_pp_m7_rework_cards.png`, `odin_pp_m7_rework_enemy.png` e
`odin_pp_m7_rework_survey.png` mostrano carte, pannello nemico e visuale ampliata
dopo vere giocate di Heavy Blow e Battle Focus.

Con `--playtest-report`, oltre al report esistente, viene scritto un file
separato `*.m7_N.json` con `schema_version = 2`, seed, configurazione e
metriche M7: decisioni, timeout, recuperi, beat del recupero (`forced_pulses`,
nome storico), esiti QTE e tempo attivo (`decision_seconds`, incluso recupero)
e nell'ologramma. La versione 2 rimuove durata della preparazione e carte
anticipate; anche `odin_pp_m7_stress.json` usa lo schema 2. La creazione
esclusiva evita sovrascritture; i tempi riflettono la sessione interattiva.
Lo schema del report di combattimento classico resta invariato. I segmenti
M7 vengono osservati separatamente: per il costo complessivo di una carta
va considerata anche la successiva risposta nemica.

Le regressioni di [tactical_test.odin](src/game/tactical_test.odin) verificano
cicli, recupero fisso, timeout, QTE, angoli, difese e morte. I test
`tactical_room_pressure_test.odin` nei package game/main coprono reset della
pressione alla nuova stanza, transizione con reward e mancata mutazione
quando la costruzione fallisce. Quelle di [tactical_renderer_test.odin](src/render/tactical_renderer_test.odin)
verificano fog dello snapshot, proiezione/picking in entrambe le camere e
selezione alpha degli sprite e selezione dei volumi degli oggetti, esclusi
quelli nascosti dalla fog. [enemy_tactical_ai_test.odin](src/game/enemy_tactical_ai_test.odin)
copre preparazione e interruzione dei lanci, micce e danni, percorsi sicuri,
spinte, blocchi completi, parry delle cariche e barili spostati. Verifica anche
che l'avvio M7 ripianifichi gli intenti inizialmente creati con le regole classiche.
[tactical_controller_test.odin](src/tactical_controller_test.odin)
verifica il gestore condiviso degli input: pulsante, trascinamento, zoom,
ricentramento, chiusura senza clic passanti e countdown durante la mappa.
Il test interattivo tramite automazione macOS non ha recepito i clic sintetici:
resta da confermare la sensazione dei controlli con mouse/tastiera reali.
La suite classica viene eseguita insieme a
quelle nuove, con e senza assert.

### Stabilità input e verifica del blocco persistente

La revisione del 9 ottobre distingueva due problemi. Il primo era la
**pressione WASD persa durante la timeline M7**: il controller ritornava
prima che il poll ordinario potesse leggerla. La correzione di allora la
conservava (al massimo un passo nella stessa fase Combat/Loot); dal 14 ottobre
la regola è l'opposto e vale in tutto il gioco: **nessun comando resta in
coda**. Il passo conservato partiva da solo alla fine dell'azione, e chi
premeva più volte si trovava azioni in più; ora una pressione fatta durante la
propria azione (animazione, secondi dell'azione o passo dell'ombra) viene
scartata e agisce solo una pressione successiva
([Input senza coda e transizioni](#input-senza-coda-e-transizioni)). Resta solo
il passo premuto sul secondo, che aspetta per 0,06 s il tasto della diagonale:
QTE, fine della finestra, cambio fase, ologramma, pausa e perdita del focus lo
lasciano cadere, e non esiste uno sblocco forzato. L'ingresso nel recupero
permette un nuovo passo nello stesso frame; durante il recupero i nuovi passi
restano validi.

Il **blocco persistente anche con nuove pressioni** segnalato nel playtest
non è ancora riprodotto: non va considerato risolto né dalla coda di allora né
dalla sua rimozione.
Il successivo pass grafico è stato richiesto separatamente: i nuovi feedback
leggono la timeline esistente e non introducono timer di blocco o fasi logiche.
Quando si verifica, premere **F8** prima di riavviare: viene creato un file
esclusivo `odin_pp_input_N.txt` nella directory di avvio (massimo 8 KiB per
cattura, 256 file). Contiene seed, nodo, fasi logiche e mostrate, focus,
pausa, QTE, clock, pulse, cursore/tempo della timeline, drag, il passo in
attesa della diagonale (`chord_active`, `chord_direction`, `chord_timer`) e
collisioni delle quattro celle vicine. Ripetere F8 dopo una nuova pressione
WASD consente di confrontare gli stati. La cattura non modifica il gioco.
Per una traccia di ogni input durante lo sviluppo:

```sh
odin run src -o:none -define:M7_INPUT_TRACE=true
```

Le regressioni di `gameplay_input_test.odin` e `tactical_controller_test.odin`
fanno passare ogni pressione per una copia della corsia della scena
(presentazione, controller, scarto dell'input nei fotogrammi che il controller
tiene per sé, poi il comando con lo stesso stato "occupato" della scena) e
verificano che una pressione durante la propria azione si perda invece di
accodarsi, senza che il controller ne tenga nulla da parte, premendo a ogni
fotogramma: per tutto il secondo di un passo in combattimento, per tutto il
turno di un passo con `--classic` (la stessa corsia di `--spell-lab` e
`--dice-lab`) e per tutto un passo del loot. Verificano anche che la schivata
interrompa ancora l'azione e che il passo in attesa della diagonale cada a ogni
confine; `shadow_controller_test.odin` fa lo stesso dentro l'ombra di Movimento
Ombra. `tactical_liveness_test.odin` attraversa controller e timeline frame per
frame, con timestep regolari/irregolari, velocità 1×/4×, QTE,
recuperi ripetuti. Verifica inoltre tre finali di fight (parry, veleno durante
recupero, parry durante recupero), Loot, reward e
movimento nella nuova stanza. Un harness esplorativo temporaneo ha provato
192 partite generate: 7.610 comandi, 8.028 pulse, 474 tiri di dadi e 388
Refocus, senza stalli; questo non dimostra l'assenza del bug segnalato.

Lo smoke grafico include `m7_polish_smoke.odin`: movimento che dimentica la
vecchia zona visibile, uccisione reale con Piercing Ray, transizione luminosa,
sette passi nel loot con raccolta del drop (durante il primo, `D` premuto a
ogni fotogramma passa per la corsia della scena e si perde: il giocatore resta
fermo finché un nuovo tasto non lo muove di una casella), reward, stanza
successiva e nuovo movimento, verificando reset di luce/fog e assenza di
errori di timeline.
Salva `odin_pp_m7_polish_combat.png`, `odin_pp_m7_polish_loot.png` e
`odin_pp_m7_polish_next_room.png`. L'automazione nativa macOS non ha consegnato
tasti/clic a Raylib neppure nel menu iniziale: il playtest automatizzato in
finestra usa i controller e i comandi reali del progetto.

Il refactor di `render/card_description.odin` elimina la tabella numerica
parallela nei testi di mano/ispettore: valori, durate, raggi e cariche derivano
dal catalogo effettivo, compresi gli upgrade. Formule dei dadi e differenze
intenzionali classico/M7 restano esplicite e coperte da test.

### Direzione visiva: diorama gotico e pixel dark fantasy

La scena M7 unisce architettura 3D in resina blu scuro e personaggi 2D pixel.
`render/diorama_scene.odin` raccoglie pavimenti incisi, modanature, nicchie,
lanterne e pulviscolo. Lo shader usa al massimo quattro lanterne visibili,
oltre alla luce del giocatore; la scelta è deterministica e non consuma RNG.
Gli elementi trasparenti rispettano la profondità senza scriverla. La fog
non conserva memoria e le decorazioni non rivelano celle nascoste.

I nuovi personaggi incorporati sono in `assets/gothic/figures-v2.png`:
arciere con balestra, bruto corazzato, ghoul, custode e pose del pellegrino
hanno silhouette e accenti blu più distinti. La versione precedente resta
disponibile; metodo, prompt e regioni dell'atlante sono documentati in
[`assets/gothic/generation-prompts.md`](assets/gothic/generation-prompts.md).
L'opzione `--sprites` continua a prevalere sugli asset incorporati. Salute
e intenti si ancorano alla geometria effettiva dello sprite, incluse le pose.
L'allocatore riserva anche le sagome proiettate: il vincolo del bordo superiore
non può spingere un'etichetta sopra un personaggio. Se le corsie preferite
sono occupate, una ricerca limitata sceglie lo spazio libero più vicino,
anche sotto l'ancoraggio. Due regressioni coprono bordo superiore e folla.

`render/tactical_feedback.odin` interpreta le cue già esistenti: piccoli
salti, flash di danno, scudi esagonali, rune, interruzioni, proiettili e
frammenti d'impatto. Gli effetti sono locali, limitati a 32 cue simultanee,
senza particelle persistenti o aggiornamenti di gameplay. I badge condividono
l'allocatore di cuori, sigilli e bombe e, se spostati, hanno un collegamento
al bersaglio. Le carte mostrano cornici metalliche, gemme energia, sigilli
rarità e feedback di selezione; a otto carte i dettagli lunghi restano
consultabili nell'ispettore. Layout e hitbox della mano non cambiano.

La transizione di 1,2 secondi dopo il combattimento schiarisce stanza,
percorso e loot; una nuova stanza ripristina luce e fog da combattimento.
`--smoke-m7-view` include ora `m7_visual_smoke.odin`: azioni reali generano
cast, movimento, danni a entrambi gli attori, scudo, assorbimento,
interruzione, volo e impatto di Firebomb. Salva `odin_pp_m7_visual_*.png`,
controlla RNG e integrità della timeline e stampa un microprofilo locale
di update e invio draw CPU. Quest'ultimo esclude present/vsync, screenshot
e completamento GPU: non è una misura del frame time complessivo.

I test dei feedback verificano isolamento del bersaglio, immutabilità della
timeline e ritorno a terra al termine del movimento senza contatori residui.
Gli smoke di loot/stanza successiva e le suite classica/M7 restano attivi.

Verifica locale del primo pass (9 ottobre 2026, Apple M1, build `-o:none`):
`scripts/check.sh` passa 634 test sia con sia senza assert, check strict/vet
e build in entrambe le configurazioni. Lo smoke 3D attraversa combattimento,
sette passi nel loot, raccolta e nuova stanza con zero errori di timeline.
Il campione dei nove feedback comprende 328 frame: invio draw CPU medio
7,893 ms, picco 13,221 ms. Non certifica tempi GPU o tutti gli incontri densi.

### Reset stanza, spawn centrale e HUD compatto

Il ciclo di penalità era conservato in `Player.tactical` anche entrando nella
stanza successiva. `begin_tactical_room` ripristina ora ciclo zero, fase Decision,
timer/budget configurati, zero pulse residui e zero recupero schivata. Il reset
avviene soltanto dopo la costruzione riuscita della stanza; configurazione,
orientamento e metriche cumulative restano conservati. Ogni stanza riparte da
Pulse 1; il recupero resta sempre di un secondo. I percorsi classici non
applicano questo reset.

Le stanze procedurali M7 selezionano lo spawn centrale **prima** di collocare
incontri e oggetti. Viene scelta la cella valida più vicina al centro, con
clearance completa e un'uscita alla distanza minima richiesta; i pareggi
dipendono dal seed. Le forme delle cinque famiglie, la connettività e le
distanze da nemici, trappole e solidi restano validate. Classico e arene
costruite a mano conservano gli spawn previsti. Le regressioni coprono
360 layout con rigenerazione deterministica e 192 blueprint M7.

`render/tactical_hud.odin` separa salute/stati, fase/timer e controlli in
tre pannelli compatti. Rosso per urgenza e danni; blu per informazioni normali.
L'area mano passa da 221 a 184 pixel logici, le carte da 182 a 154; vengono
eliminate istruzioni e footer ripetuti. Le hitbox condividono i nuovi bounds.
L'ispettore conserva i testi completi anche con otto carte e i QTE mostrano
sempre le difese disponibili. La camera lascia più spazio al campo di gioco.

Il nuovo pass usa smussi uniformi nello spazio 3D, riflessi e grana più
controllati, incavi sui capitelli e ombre di contatto morbide sotto gli attori.
`render/tactical_surface.odin` disegna la scena 3D e l'ologramma a risoluzione
2×, riducendoli con filtro bilineare prima di comporre HUD e testi pixel.
Il target GPU viene allocato una volta e rilasciato con il renderer; se non
disponibile resta il percorso diretto. Il resolve è opaco: l'ologramma non
lascia trasparire le carte o la scena precedente. Picking e regole rimangono
in coordinate logiche. La mappa ha griglia ciano, minacce rosse, sprite reali
e legenda orizzontale; il countdown continua durante la consultazione.

`m7_room_refresh_smoke.odin`, incluso in `--smoke-m7-view`, attraversa due
stanze realmente generate con comandi, loot, reward e ingresso nel nodo.
Verifica spawn centrali, reset di ciclo/timer, metriche conservate e ritorno
a fog/luce da combattimento. Salva `odin_pp_m7_room_refresh_first.png` e
`odin_pp_m7_room_refresh_next.png`. La fixture usa salute/attacco elevati per
verificare la transizione, non per misurare il bilanciamento.

Verifica della revisione: `scripts/check.sh` supera 640 test con e senza
assert, strict/vet e entrambe le build; `--smoke-m7` passa 10 preset e quattro
run terminali ripetuti. Lo smoke 3D conferma spawn `{8,5}` nelle due stanze
generate della fixture, ciclo `5 → 0`, metriche conservate e zero errori di
timeline. QA visiva completata su HUD, otto carte, QTE, ologramma normale e
ruotato, loot e nuova stanza. Nel campione finale di 328 frame il costo CPU
medio di invio draw è 7,729 ms (picco 15,465 ms, Apple M1, `-o:none`), sempre
esclusi present/vsync, cattura PNG e completamento GPU.

### Mura interne trasparenti e perimetro orientato alla camera

Nel diorama 3D le mura interne conservano l'altezza completa (1,58 unità),
con corpo e rilievi blu semitrasparenti e zoccolo opaco per rendere leggibile
la cella occupata. Si abbassano a 0,5 unità soltanto i due lati del perimetro
rivolti verso la camera. I lati opposti rimangono alti; un raccordo angolare
continuo evita scatti quando la camera passa da un quadrante al successivo.
Lo spostamento del player o lo zoom non cambiano i lati abbassati.

`render/diorama_scene.odin` separa basamenti opachi e corpi delle mura.
`render/tactical_translucency.odin` ordina pareti interne e sprite insieme,
dal fondo verso la camera, conservando il test di profondità del terreno
senza scrivere profondità per le superfici trasparenti. Anche rilievi e
lampade interne seguono la trasparenza. Il buffer di ordinamento riusa la
capacità fra i frame ed è rilasciato con il renderer.

È una modifica di presentazione: le mura restano solide e bloccano la linea
di vista. La fog di combattimento continua a nascondere le celle non visibili;
il materiale trasparente non rivela nemici oltre la fog. L'ologramma conserva
la propria geometria e il timer attivo; la modalità classica non cambia.

Le regressioni coprono classificazione interno/perimetro, quattro quadranti,
rotazione continua, traslazione/zoom, ordine dei layer e visibilità. Lo smoke
`m7_wall_smoke.odin`, incluso in `--smoke-m7-view`, cattura un combattimento
con nemico occluso e quattro angoli della stessa stanza in Loot:
`odin_pp_m7_walls_combat.png` e `odin_pp_m7_walls_corner_0.png` … `_3.png`.

Verifica della revisione: `scripts/check.sh` supera 645 test con e senza
assert, strict/vet e le due build. Gli smoke headless e 3D passano; la prova
in finestra include quattro angoli, nemico nascosto dalla fog, combattimento,
movimento nel Loot e nuova stanza, con zero errori della timeline.

### M7: pulse temporale e cadenze autonome

Nota storica: in M7 anche il costo delle carte maturava beat immediati. M8
separa il cast dal clock del mondo; la descrizione seguente conserva il contesto
del rework, con smoke e regressioni aggiornati alla nuova regola.

`game/tactical_clock.odin` riceve sia il tempo decisionale reale sia il costo
delle azioni accettate. Accumula le frazioni e accoda beat da un secondo;
`Continue_Pulse` li risolve con log limitati, senza ricorsione né perdita dei
beat durante un QTE. La scadenza della finestra usa `tactical_expire_window`,
dopo aver risolto il tempo già pagato. `remaining` non viene più ripristinato
al termine di ogni comando. Le regole e i valori iniziali sono descritti in
[Modalità tattica M7](#modalità-tattica-m7).

I nemici conservano una scadenza individuale e l'intento già annunciato.
Gli status a durata, le bombe e i recuperi avanzano sul clock del mondo; il
Veleno morde le azioni di chi lo porta, la Bruciatura ogni finestra che scade e
il Rallentamento allunga i prossimi intenti del nemico; l'energia ha
una cadenza distinta di tre secondi. Stagger cancella un intento anche prima
della sua scadenza e lascia almeno un secondo di recupero sfruttabile dopo
il costo della carta. Fine fight e nuova stanza cancellano frazioni/debito,
continuazioni e QTE. Il classico conserva la risposta a ogni comando.

La presentazione M7 ha due canali: l’azione del player e i cue del mondo.
`drain_tactical_world_commands` completa i segmenti logici dovuti nello stesso
frame, con budget derivato dal debito e dal numero massimo di nemici; si ferma
su QTE o fine fight. Il polling del player avviene subito dopo, senza attendere
le immagini. `renderer_blocks_player_input` considera soltanto la propria azione;
`renderer_timeline_is_busy` include entrambi i canali per completare correttamente
transizioni e smoke. Il clock reale prosegue durante i cue ordinari. In M8
il cast ferma il mondo e le cinematiche fermano anche il countdown del player.

`render/world_playback.odin` conserva cue e trasformazioni, senza sostituire lo
stato aggiornato con snapshot di vecchi beat. Corpi diversi si animano insieme;
i waypoint dello stesso corpo mantengono ordine e durata. Un banco limitato,
allocato una volta e riutilizzato, riserva spazio prima del commit logico: nessun
beat già applicato perde la sua presentazione. Clear e distruzione includono
entrambi i canali. Lo snapshot diagnostico F8 distingue il blocco della propria
animazione, i cue del mondo e il debito del clock. Il flag interno `forced`
identifica soltanto i beat maturati durante il recupero e non blocca l'input.

Lo smoke `m7_timed_pulse_smoke.odin` esegue due passi e Guard nello stesso
Pulse 1 (`20 → 17 s`), poi consulta l'ologramma per 1,25 secondi (`15,75 s`).
In M8 i due passi producono due beat e Guard nessuno: il successivo tempo
dell’ologramma aggiunge il terzo beat, rispettando le cadenze dei nemici. Salva
`odin_pp_m7_timed_actions.png` e `odin_pp_m7_timed_hologram.png`.
Lo smoke `m7_independent_world_smoke.odin` esegue un passo, una nuova pressione
e Guard durante animazioni nemiche ancora attive, facendo avanzare il clock a
ogni frame. Salva `odin_pp_m7_independent_movement.png` e
`odin_pp_m7_independent_card.png`; `odin_pp_m7_independent_ready.png` mostra
il ritorno immediato ai comandi mentre i nemici stanno ancora animando.
Le regressioni verificano anche interpolazione
simultanea, stato aggiornato dopo danni/scudi, velocità di playback 1×/4× e
countdown attivo ma mondo fermo durante il cast del player.
Le regressioni coprono anche input esattamente sul beat, targeting conservato,
scadenza senza doppio addebito, animazioni/QTE, tempo frazionario, interruzioni
e cancellazione del debito nel Loot. La fixture grafica usa salute elevata
per verificare il flusso; i costi sono una prima taratura da valutare in run.

Verifica storica della base M7: `scripts/check.sh` passava 683 test con e senza assert, strict/vet
e le due build. Lo smoke headless completa dieci preset e quattro run terminali
ripetuti due volte. Lo smoke 3D verifica azioni multiple, ologramma, nove feedback,
combattimento/Loot/stanza successiva e quattro angoli delle mura, senza errori
della timeline. La QA visiva conferma costi energetici e temporali distinti e
countdown dei nemici leggibili; il bilanciamento resta da valutare giocando.


### M7: recupero mobile di un secondo

Il precedente salto di turno contava beat `1, 3, 5…` ma aspettava la timeline
per ogni segmento: la durata percepita dipendeva da nemici, effetti e velocità
visiva. Ora `TACTICAL_RECOVERY_SECONDS = 1` usa il clock attivo condiviso.
`tactical_allows_movement` separa la camminata dall'offensiva;
`tactical_allows_action` viene usato da gameplay, carte, preview e HUD.
Il controllo dell'attacco contro un nemico avviene prima di modificare il log.

`Recovery` sostituisce `Forced`; sono rimossi `Preparation`, `End_Preparation`,
la configurazione della preparazione, il contatore di pulse da saltare e la
formula crescente. `Continue_Pulse` accetta soltanto beat già maturati:
richiamarlo non accelera il recupero. `tactical_finish_recovery` riattiva le
azioni soltanto dopo timer zero, debito risolto e nessun QTE pendente. Camminare
non genera tempo, energia o beat aggiuntivi; bombe, status e collisioni
conservano gli effetti normali. Il classico conserva le sue regole.

Le regressioni verificano partizioni del secondo a 1/4/60/120 aggiornamenti,
playback 1×/4×, passi ripetuti gratuiti, attacchi/carte/refocus respinti senza
mutazioni, beat anticipato, QTE sospeso e ripreso, morte da hazard e fine fight
da veleno. `m7_recovery_smoke.odin` usa i comandi reali anche nella finestra 3D:
cattura `odin_pp_m7_recovery_walk.png` a metà recupero, dopo due passi, e
verifica il ritorno delle carte al pulse successivo. Un secondo è la prima
taratura da valutare con partite reali, non un bilanciamento definitivo.

### M8 / 0.4: implementazione e verifica

Il perimetro consegnato e i controlli sono descritti in [M8](#m8-versione-04).
Le policy temporali sono separate in `cast_playback.odin`, `frame_timeline.odin`
e `tactical_controller.odin`; i costi restano centralizzati nel catalogo tattico.
Geometria, preview e danno dei dispositivi condividono `board_device.odin`.
`m8_equipment.odin` gestisce gli utilizzi senza cambiare l'attacco classico;
`m8_ring.odin` conserva la progressione, i traguardi una sola volta e la
simulazione originaria per compatibilità. Il duello live corrente è in `fight`;
`m8_session.odin` possiede il passaggio alla sessione M9 e il file del profilo.

I test coprono separazione dei clock, mancato doppio addebito, dadi e F4,
scadenza a fine cast, rifiuti senza mutazioni, d4 con più bersagli, massimo
numero di dispositivi, distanza, linea di vista, campo con fuoco amico, ricarica
e rimozione nel Loot. Equipaggiamento e ring verificano cariche, swap, vincita
con tre schivate/prese, quattro pose, sconfitta non letale, sblocchi a mazzo pieno,
filtri delle offerte, input temporali non finiti e persistenza del profilo.
Gli smoke precedenti sono migrati al nuovo cast, mantenendo classico, QTE,
recupero, fog, ologramma, Loot e ingresso nella stanza successiva.

```sh
sh scripts/check.sh
./run.sh --smoke-m7
./run.sh --smoke-m8-view
./run.sh --smoke-arenas-view
./run.sh --smoke-dice-set
```

Verifica precedente della base M8 del 9 ottobre 2026: `scripts/check.sh` completo, **748 test superati**
sia con assert sia senza, vet/strict-style e build puliti, nessun leak segnalato.
Passati lo stress headless (10 preset e 4 run terminali ripetute due volte),
il percorso 3D M7 e quello M8: piazzamenti, d4, campo Tesla con fuoco amico,
equipaggiamento, Loot, ring con quattro pose/sblocco e stanza successiva.
Lo smoke headless delle run avanza un cast direttamente attraverso
`tactical_tick(cast_remaining)`: il suo limite conta passi logici anziché ogni
frame grafico a 60 Hz, che nei nuovi combattimenti esauriva prematuramente il
budget. Il comportamento a frame rimane coperto dai test dei clock/controller
e dagli smoke 3D. Il seed che falliva completa ora tutti i sette nodi.
Le regressioni includono l'ultimo frame cinematografico senza addebito,
la sospensione di eventi già pendenti, i bordi della pausa e il campo che
colpisce tutti i bersagli anche quando la stessa scarica uccide il player.
I controlli solo mouse verificano equipaggiamento e attivazione al singolo
clic, pulsanti disabilitati e apertura/chiusura dei modali senza clic sulla board.

Lo smoke M8 usa una vera finestra Raylib 3D e comandi scriptati attraverso il
dispatcher. Salva d4, rete elettrica, scheda personaggio, Loot, quattro pose del
ring e stanza successiva. Queste sono prove riproducibili di integrazione e resa
visiva; non sostituiscono una sessione manuale di bilanciamento. Gli esiti finali
della verifica vanno riferiti alla revisione eseguita, senza riutilizzare i
conteggi storici delle milestone precedenti.

Aggiornamento trappole, Tesla e dadi del 9 ottobre 2026: **770 test superati**
con e senza assert, `scripts/check.sh` completo (vet/strict-style e due build).
Le regressioni aggiunte coprono attesa senza consumo, ingresso/spinta/carica,
teletrasporto, player escluso dall'innesco, pulsante solo Tesla e sincronizzazione
del nuovo evento `Hazard_Triggered` con la presentazione. Per la rete verificano
persistenza delle pareti, cooldown, danni prima del consumo delle quattro torri
e possibilità di riposarle. I test dei dadi verificano geometria chiusa,
numerazione fissa, appoggio di ogni risultato sul piano, ripetibilità e assenza
di mutazioni durante il playback.
Un controllo nativo più stretto ha inoltre riprodotto due errori di timeline
per ogni piazzamento Tesla: il validator dei lanci/impatti ammetteva solo le
vecchie spell e le carte con dadi. Ora riconosce anche le carte dispositivo;
una regressione verifica gli eventi reali di posa, scarica e consumo, con
zero errori di presentazione e nessun evento perso.

Passati lo stress M7 (10 preset e 4 run ripetute due volte) e gli smoke nativi
M8 e set dadi. Il primo prova pedana automatica, consumo della mega con fuoco
amico, equipaggiamento, Loot, ring e stanza successiva. Il secondo disegna i
sette modelli lungo 100 frame di lancio, tutti i risultati del D4 e lo 00 del
percentuale. Screenshot: `odin_pp_dice_set.png`, `odin_pp_dice_d4_detail.png`,
`odin_pp_m8_d4.png`, `odin_pp_m8_devices.png` (rete prima della mega) e
`odin_pp_m8_mega_combo.png` (dopo il consumo). La verifica visiva ha corretto
anche il materiale che ignorava l'alpha dell'atlante e copriva le cifre con
rettangoli: ora la resina campiona la texture dei numeri e mantiene l'avorio
leggibile sulle facce in ombra.

La verifica delle arene progressive usa quattro blueprint reali (17×11,
25×17, 33×23 e 45×31), fino a 22 nemici. Lo smoke 3D ha verificato 28 beat
nemici, quattro movimenti durante il playback indipendente, 63 passi nel Loot,
quattro transizioni e nessun evento scartato. Per isolare il flusso usa un player
con 1.000 HP e un finisher scriptato attraverso il normale risolutore di effetti;
non dimostra il bilanciamento di una vittoria giocata manualmente.
Il log distingue tempo CPU di generazione/simulazione e invio del disegno di
mondo/ologramma, escludendo presentazione, vsync, PNG e completamento GPU.

### M9: implementazione e verifica

Le [fondazioni M9](#m9-fondazioni-per-le-modalità-libere) sono integrate nella
base 0.4. Prima dell’integrazione del branch engine, il controllo del
10 ottobre 2026 superava **829 test** in
tutti i package, sia con assert sia senza, oltre a vet/strict-style e alle
due build. Lo smoke nativo M9 verifica collisioni nell'arena, vittoria contro
l'IA del ring con valori ordinari, presa in quattro pose, replay identico,
FPS con attacco annunciato, ricarica, vittoria e ritorno fra modalità.
Sulla stessa build passano anche il confronto headless M7 (dieci preset,
quattro run terminali e otto cicli stress) e lo smoke 3D M8: dispositivi,
equipaggiamento, loot e ingresso nella stanza successiva.

Le regressioni coprono anche pareti sottili, collisioni veloci, colpi e prese
ostruiti dai pilastri, lancio fermato al primo contatto, registrazione dei
corpi dopo cambio livello, mancato click sui controlli nascosti, input al
cambio focus e assegnazione singola degli sblocchi. Le prove scriptate
dimostrano questi contratti; difficoltà, varietà delle mosse e qualità del
ritmo restano da valutare con partite umane.

Screenshot rigenerabili: `odin_pp_m9_arena.png`, `odin_pp_m9_ring.png`,
`odin_pp_m9_fps.png`, `odin_pp_m9_tools.png` e le quattro pose
`odin_pp_m9_ring_grab_0.png`–`odin_pp_m9_ring_grab_3.png`.

Correzione dell'avvio FPS con il mouse: il precedente messaggio centrale era
solo disegnato, mentre il clic era riconosciuto esclusivamente su **RIPRENDI**
in alto. Ora il pannello centrale è un pulsante con disegno e hitbox condivisi,
attivo solo durante una partita FPS in pausa. La ripresa è idempotente e
consuma il clic senza sparare. Le regressioni seguono il percorso
posizione del mouse → controllo → simulazione e verificano anche gli stati
non riprendibili; l'avvio è stato confermato nella finestra macOS.


### Integrazione del branch engine/minigiochi

Il 10 ottobre 2026 è stato integrato `claude/engine-minigiochi` (`67b6297`)
partendo dal checkpoint locale M9 `5f7650a`. Il merge a tre vie mantiene
entrambi gli sviluppi: i servizi dell’engine, il menu e i cinque minigiochi del
branch; collisioni continue, ring, FPS, replay, strumenti e fix del clic M9
locali. Dadi canonici, Tesla persistenti e trappola passiva restano presenti.
Il controller continuo X/Z di `src/engine` e i controller tile/voxel di
`src/engine/physics` coprono domini diversi; non sono stati sostituiti l’uno
con l’altro. RNG ed easing comuni eliminano duplicazioni senza cambiare le
sequenze di gameplay.

L’audit ha aggiunto regressioni e correzioni funzionali:

- FPS e arena conservano un clic breve ricevuto fra due tick e lo consumano
  una volta. Il clic del menu non spara all’avvio o alla ripresa.
- Pausa e perdita del focus cancellano input pendenti e frazioni temporali
  residue; i clock ignorano delta negativi o non finiti. I tick completati
  non vengono azzerati.
- I profili corrotti o di versione futura non vengono sovrascritti con i
  valori predefiniti. Il decode JSON usa memoria temporanea fino alla
  validazione, evitando perdite con dati annidati rifiutati.
- Un raycast può entrare dall’esterno in una tile map aperta.
- Le sfide della run verificano identità, stanza ed esito pendente prima
  della ricompensa. Risultati duplicati, estranei o già consumati non pagano.
- Seed CLI riproducibile, nessuna scrittura dei profili negli smoke/lab e
  pulsante delle nuove sfide azionabile con il mouse, separato dai controlli M9.

Verifica dell’integrazione: `scripts/check.sh` copre tutti i **1.011 test**
con assert attivi e disattivati, controllo strict/vet e due build. Tutti i
servizi e minigiochi registrati sono raggiungibili da `src`: le due esecuzioni
`-all-packages` bastano, senza ripetere singolarmente le stesse suite negli
script Unix e PowerShell.

Il report headless M7 prima/dopo il merge è identico byte per byte (4.023
byte, SHA-256 `343cae6483dc8f40cc4cf4973a721b8107861abbeb64b7db00e0f767acd8687c`):
dieci preset, quattro run terminali ripetute e otto cicli stress. Gli smoke
nativi verificano menu, avvio/rendering dei cinque minigiochi, flusso M9,
dispositivi/loot/cambio stanza M8 e i sette dadi 3D. Catture rigenerabili:
`odin_pp_menu.png`, `odin_pp_platform2d.png`, `odin_pp_platform3d.png`,
`odin_pp_arena.png`, `odin_pp_fps.png`, `odin_pp_puzzle.png`, oltre alle
catture M8/M9 e del tavolo dadi.

Le verifiche native sono state eseguite su macOS; gli script Windows sono
inclusi ma non sono stati eseguiti su Windows in questa integrazione.
Gli smoke dei nuovi minigiochi durano 180 frame: le partite complete sono
coperte dai bot headless, non da playtest umani. Restano da valutare difficoltà,
ritmo e coerenza visiva fra le modalità. Raylib segnala dodici codepoint non
presenti nel font incorporato; nelle catture esaminate i testi di gioco sono
leggibili, ma non è una verifica completa di tutti i caratteri del font.


### Allineamento engine e HUD dopo il merge

L’host gestisce ora interattività e sospensione delle scene in modo uniforme;
la run e le attività M9 rispettano la stessa ownership dell’input. Sono stati
riprodotti e corretti due difetti del contratto scene: una prova continuava a
simulare sotto un overlay non modale e il nome/esito di una scena poteva
essere invalidato da `destroy` prima della callback di ritorno. Le regressioni
coprono anche overlay modali, push rifiutati e clic ereditati fra schermate.
`Resume_Gate` sostituisce cinque implementazioni locali della ripresa input.

HUD e menu condividono palette e primitivi grafici dell’engine. Nella run
sono stati rimossi pannelli vuoti, ridotte le informazioni ripetute e separate
le attività del Loot dal percorso centrale. Nelle cinque prove sono allineati
pannelli, barre, obiettivi e notifiche; il puzzle riserva esplicitamente spazio
alla board su tutti i livelli. Il test della barra oggetti distingue controlli
nascosti, controlli visibili disabilitati e click sulla board.

Verifica del 10 ottobre 2026: **1.025 test** con e senza assert, strict/vet e
due build tramite `scripts/check.sh`. Dopo l’ultimo aggiustamento geometrico
del pannello Loot sono state ripetute le regressioni HUD e lo smoke M8.
Il report M7 è ancora identico byte per byte al merge precedente. Gli smoke
nativi coprono menu, avvio e rendering delle cinque prove, ring/FPS/replay M9,
combattimento e dispositivi M8, Loot e stanza successiva. Screenshot:
`odin_pp_menu.png`, `odin_pp_m8_devices.png`, `odin_pp_m8_loot.png`,
`odin_pp_platform3d.png`, `odin_pp_fps.png`, `odin_pp_puzzle.png`.

Questo allineamento non modifica bilanciamento o regole di combattimento.
Griglia tattica, fisica continua X/Z e controller platform tile/voxel restano
specializzati; i laboratori CLI conservano i propri driver diagnostici.
L’input del roguelike non è ancora completamente rimappabile tramite action
map e le due progressioni salvate restano distinte. La revisione artistica successiva è descritta sotto. Verifiche native su
macOS, script Windows non eseguiti.


### Coesione delle prove e FPS/ring unificati

Tutte le prove adottano nero, ardesia/blu e avorio. Rosso comunica pericolo,
oro indica rune e ricompense. FPS e platform 3D usano le figure dell’atlante
principale con silhouette di carta separate, precompilate al caricamento;
platform 2D, arena e puzzle conservano le pose dei propri sprite e ricevono
la stessa cornice avorio/nera. Nessuna rigenerazione di texture per frame.
La lieve lucentezza è un parametro opzionale del lighting condiviso, zero
per i renderer che non la richiedono.

Il ring ha una pedana scolpita, intarsi, angoli illuminati e camera più ampia.
La Cripta ha superfici blu levigate, architettura incisa, magie leggibili e
segnali d’attacco. Guglie Sospese sostituisce l’avatar cubico con il Viandante;
le piattaforme hanno bordi e nicchie. Torre di Cenere, Arena delle Braci e
Sigilli della Cripta condividono pietra, cornici e accenti freddi mantenendo
intatti geometria di gioco, collisioni e obiettivi.

`ring_minigame.odin` adatta l’unica simulazione `fight` alla shell. Il receipt
M8 conserva soltanto esito e pagamento, senza simulazione parallela. Le
regressioni verificano routing unico, assenza di ricompense dalla pratica,
un solo sblocco al ritorno, abbandono, sospensione e input ripresi senza
azioni ereditate. Gli strumenti M9 restano diagnostica esplicita: non sono
una seconda scelta di FPS/ring nel gioco. Non sono stati unificati i due
formati di profilo o modificati pulse, carte e combattimento della run.

Verifica: **1.028 test con e senza assert**, strict/vet e due build.
Smoke nelle finestre native per menu, tutte le sei prove, dispositivi M8,
ring/sblocco/ritorno Loot/stanza successiva e laboratori M9 con replay.
Il report M7 prima/dopo è identico byte per byte (4.023 byte). Le catture
usano bot e seed 7, senza registrare record o sblocchi di test.
Regressioni aggiuntive proteggono il mirror delle celle dell’atlante,
la presa su RB (B/Start appartengono alla shell) e il clic su Sfida extra,
che non deve attraversare la HUD fino alla board. Le due figure trasparenti
di ogni attore si compongono senza scrivere profondità: pareti e piattaforme
continuano a occultarle, mentre il bordo non può coprire la propria illustrazione.
Dopo questa correzione grafica sono stati ripetuti strict/vet, build, test FPS
e verifiche native di FPS e platform 3D.

Screenshot: `odin_pp_menu.png`, `odin_pp_ring.png`, `odin_pp_fps.png`,
`odin_pp_platform2d.png`, `odin_pp_platform3d.png`, `odin_pp_arena.png`,
`odin_pp_puzzle.png`. Le animazioni dei cutout usano pose e trasformazioni
a scatti dei disegni esistenti, non nuovi fotogrammi anatomici disegnati.
Restano da valutare in playtest umano difficoltà, pad e leggibilità alle
varie distanze; verifica nativa effettuata su macOS, non su Windows.


### M7G: lavoro restante dopo il prototipo

Restano da svolgere le revisioni del codice e i playtest umani concordati:

- confrontare 15/20 secondi e 3×3/5×5/7×7 separatamente, poi insieme;
- valutare la leggibilità di minacce, carte e QTE, compreso l'uso dell'ologramma
  mentre il timer scorre e la durata del parry;
- misurare danni ed efficacia del movimento nel recupero fisso di un secondo,
  per tararne la durata senza reintrodurre blocchi crescenti;
- provare il nuovo ritmo dei bombaroli (preparazione, miccia 3, danno 3,
  recupero 2, limite condiviso 1), le spinte dei bruti e i barili accesi dai boss;
- valutare due nemici aggiuntivi, vista 7×7/9×9 e recupero di due pulse della
  schivata; confrontare la frequenza dei QTE e il valore di Afterimage;
- verificare il valore delle carte a lungo raggio con fog e delle combinazioni
  di pesca/creazione dentro la finestra temporale;
- decidere eventuali correzioni a progressione, costi, durata delle finestre
  e gestione dei rimpiazzi sulle evidenze delle run.

### Criteri per gli incrementi successivi

Per carte e geometrie: preview e compilazione devono concordare, zone e ID
restare validi, timeline seguire le mutazioni e test coprire composizione e
limiti. Per encounter: intenti committed e deterministici, geometria condivisa,
simulazioni headless con morti, blocchi, spawn e cambi di fase senza deadlock
o overflow. Per persistenza: save versionati con round trip, migrazioni e
corruzione diagnosticabili, replay dei comandi con stesso risultato finale.
Velocità o disattivazione dei feedback non devono cambiare il gameplay.

Restano fuori dallo scope attuale: Chest con stato/interazione e premio
one-shot; fuoco periodico o propagazione; status e binding degli oggetti;
status persistenti fra stanze, immunità e tipi di danno; cataloghi caricati da
file; unlock, reroll, sconti e vendita di carte; eventi concatenati;
animazioni complete fra pile, direzioni dei personaggi e raggruppamento
generale di azioni indipendenti. Audio, illustrazioni definitive, particelle,
hit stop e screen shake ulteriori appartengono agli incrementi di game feel.

### Indicazioni conservate dall'audit

L'audit del 6 settembre 2026 si riferiva al commit `ca64a3a`. Conteggi dei test,
tempi, dimensioni delle struct e riproduzioni in `/tmp` erano misure locali di
quella versione, non benchmark o istruzioni valide per ogni checkout.
Le correzioni successive comprendono upgrade senza benefici rifiutati,
policy headless che usa Movement_Query, report con creazione esclusiva,
velocità configurabile, BFS e loot preallocato. Le verifiche con e senza assert
sono raccolte in `scripts/check.sh`; le regressioni economiche e del loot in
[audit_regression_test.odin](src/game/audit_regression_test.odin).

Le indicazioni di manutenzione ancora utili sono:

- mantenere ogni mutazione fuori dagli assert e verificare entrambe le configurazioni;
- derivare numeri e preview delle carte dai template, evitando copie manuali divergenti;
- rendere chiari i motivi di rifiuto delle giocate e migliorare la consultazione del deck;
- proseguire l'estrazione di controller e disegno dai file principali quando il confine è utile;
- misurare preview, conteggi intenti, copie dei report e validazioni prima di introdurre cache;
- conservare la validazione completa ai confini e controllare i budget di stack degli eventi;
- se l'envelope cresce, valutare storage a blocchi con ownership esplicita invece di gonfiare gli array;
- automatizzare check, test e link in CI, documentando la toolchain verificata.

Le nuove nozioni e decisioni vanno aggiornate nella sezione pertinente di questo
README, mantenendo un unico riferimento e distinguendo implementato e pianificato.
