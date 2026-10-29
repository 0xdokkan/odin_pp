[← Odin PP](../README.md)

## Avvio

Serve Odin con i binding e le librerie native Raylib della distribuzione.
La toolchain usata nelle verifiche correnti è
`odin version dev-2026-10:84bc3fc21`; non è un vincolo imposto automaticamente.
Eseguire i comandi dalla radice della repo:

```sh
./run.sh
./run.sh --seed=0xC0FFEE --fast
./run.sh --release --expedition
```

Il launcher usa `odin run src -o:none`, passa gli argomenti al gioco e funziona
anche se invocato da un'altra directory. `ODIN` può indicare un compilatore
alternativo. Ricompila i sorgenti a ogni avvio, per eseguire sempre le modifiche
correnti. Il comando senza `-o:none` abilita invece l'ottimizzazione predefinita
(`minimal`), che su questo progetto può rendere molto lunga l'attesa **prima**
dell'apertura della finestra.

Per giocare e misurare le prestazioni, aggiungere `--release` come primo
argomento di `run.sh` o `run.ps1`: attiva `-o:speed` e viene consumato dallo
script. Gli altri argomenti arrivano al gioco invariati. La compilazione
richiede più tempo; dopo la prima build si può avviare direttamente
`./build/odin_pp` (Windows: `.\build\odin_pp.exe`). Le misure FPS vanno
effettuate su questa build, alla stessa risoluzione e nelle stesse scene.

Comando equivalente, oppure build da riutilizzare senza ricompilare:

```sh
odin run src -o:none
odin build src -o:none -out:odin_pp
./odin_pp
```

Su Windows (PowerShell) gli equivalenti sono `.\run.ps1` e
`.\scripts\check.ps1` (`-Headless` salta le build finali); `odin run src -o:none`
funziona anche a mano. Windows riserva al thread principale 1 MiB di stack
contro gli 8 MiB di macOS: [windows_stack.odin](../src/windows_stack.odin) porta la
riserva a 16 MiB dal sorgente, senza flag del linker sulla riga di comando.
I test dei singoli pacchetti non includono quel file: i pacchetti che decodificano
lo snapshot della spedizione importano [teststack](../src/engine/teststack), che dà
all'eseguibile di test 32 MiB, e `odin test src/<pacchetto>` funziona a mano.
Sui portatili con due schede video, Windows dà a un programma sconosciuto quella
integrata: [windows_gpu.odin](../src/windows_gpu.odin) chiede quella dedicata (NVIDIA
Optimus e AMD PowerXpress). La riga `Renderer:` all'avvio dice quale scheda disegna.

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

### Campagna dei ricordi

**Gioca** apre tre slot indipendenti. Scegli una memoria, prepara lo zaino
nel deposito e parti dalla galassia. Un salvataggio con una spedizione
attiva riprende la posizione e lo stato del bioma. I file della campagna
sono separati da `profilo.json`; cancellarli richiede due conferme nella UI.
La [checklist della direzione](direzione-implementazione.md) descrive
controlli, avanzamento, salvataggi e verifiche della nuova campagna.

`--expedition` avvia una prova senza slot. `--smoke-hub`, `--smoke-hub-world` e
`--smoke-expedition` catturano schermate senza scrivere profili o memorie.
`--run` continua ad aprire il vecchio percorso a stanze: i dettagli che
seguono sulle finestre di combattimento e le ricompense di quel percorso
non definiscono le regole della spedizione aperta.

### Prova meccaniche

**F3** cambia arena, una dopo l'altra: subito dopo la Piana, «Prima persona» (23×17) è l'arena delle carte in prima
persona, con il suo mazzo (First Person Shooter, First Person Brawler, First Person Fencer, First Person Archer e la
Canna da Pesca): un muro con due nicchie, quattro pilastri, due muri
di sbieco per i tiri di sponda, tre coperture basse, un corridoio di 5 caselle, un balestriere su un rialzo di 2
gradini e un bruto (docs/piano-prima-persona.md, Fase 1); «Altezze» ha un altopiano di 4 gradini con una
scala di 3, un pilastro di 8 e una collina a spirale (si prova la regola dei
dirupi, le cadute, la vista e la gittata dall'alto); «Strutture» (41×29) ha tutto il
catalogo: tre edifici, cinque oggetti complessi, un recinto e la casetta nelle quattro
rotazioni (si prova passo, vista e trasparenza avvicinandosi); «Piani» (46×29) ha una strada sotto un
ponte con due rampe, una collina con una grotta e due imbocchi, una scala a pioli sul dirupo della collina e
un nemico su ogni piano (si provano passo, scale, vista, aree e cadute fra piani: docs/regole/combattimento.md,
«Piani»); «Ascensori» (32×20) ha un altopiano di 14 gradini con un ascensore sul dirupo, una sala sotto raggiunta
da un pozzo con l'ascensore e un cancello che si apre solo da dentro. L'ascensore si usa con i passi: un passo verso
il pianerottolo vuoto chiama la piattaforma, un passo sulla piattaforma la fa partire; il cancello si apre con un
passo contro le sbarre dal lato della leva. Con `--smoke-mechanics-lab` e `ODIN_PP_LAB_ONLY=heights`, `structures`,
`mountain`, `cave`, `layers`, `lift`, `fps` o `prima_persona` gira solo l'atto delle altezze, delle strutture, della montagna a spirale,
della grotta, dei piani, degli ascensori, di First Person Shooter o dell'arena «Prima persona» (la montagna dura qualche minuto:
sale tutto il sentiero a passi veri). L'atto `prima_persona` gira per ultimo nello smoke completo: l'AK, poi First Person
Brawler (i guantoni Neon, un jab, un gancio, il jab che colpisce, un segno, il cross critico con la stella d'oro), poi
First Person Fencer (lo zweihänder, un tondo sul bruto, il bruto che si illumina di rosso e di viola, la parata, il rampino e la catena tesa, il colpo roteante, la
parata perfetta), poi First Person Archer (l'arco compound teso con l'anello della carica, un tiro dritto sul bruto, un
tiro di sponda trovato con la guida, una zona critica sul muro, una freccia tirata mentre la vista finisce che vola
ancora vista dall'alto).
Con `ODIN_PP_LAB_ONLY=fps` e `ODIN_PP_LAB_TIMING=1` l'atto di First Person Shooter si ferma dopo la discesa negli occhi e misura
600 fotogrammi con l'AK che spara, senza limite di fotogrammi né vsync (riga `FIRST PERSON TIMING`; meglio con una build `-o:speed`).
Con `ODIN_PP_LAB_ONLY=prima_persona` la stessa misura la fa `ODIN_PP_LAB_TIMING=1` con i pugni (un pugno ogni quarto di
secondo, `W` tenuto metà del tempo), `ODIN_PP_LAB_TIMING=sword` con la spada (la lama avanti e indietro) e
`ODIN_PP_LAB_TIMING=bow` con l'arco (teso un secondo e lasciato, di continuo) e `ODIN_PP_LAB_TIMING=ak` con l'AK,
nella stessa arena.
`--smoke-expedition` comprende l'atto «posa» (il fantasma verde e rosso, una statua e una casetta posate, la statua rotta da un colpo
e la casetta che resta), l'atto «grotte» (in Neve, Far West, Egitto e Inferno: l'arco, l'ingresso e la seconda
stanza della prima grotta, con il giro entra-esci controllato) e l'atto «montagna» (il robot in otto punti della salita, con le mappe della Neve
controllate: montagna, pattuglia e reliquia), gli atti «rilievi» (il robot nel punto più accidentato di ogni bioma, e
l'ologramma con le curve di livello in tre biomi), «scontro su due livelli» e «edifici»; quest'ultimo: il robot si avvicina a una capanna di
Robotica cibernetica (6, 4, 2 e 1 casella, soglia, dentro, fuori) e agli oggetti.

Il pulsante **Prova meccaniche** del menu (o `--mechanics-lab`) apre una sandbox
per provare le meccaniche nuove, una alla volta. È un'arena grande 23x17 senza
ostacoli né nebbia, con il giocatore al centro. Il combattimento non finisce
mai: l'ultimo nemico ucciso non ripulisce la stanza, e ogni 4 secondi di gioco
arriva un nemico casuale (Chaser, Archer, Brute, Bomber o Custode) su una
casella libera ad almeno 4 celle dal giocatore, fino a 6 insieme; un'arena vuota
si riempie subito. Gli easter egg si riaprono ogni volta. Il mazzo contiene
**una copia di Bomb Marley e una di Inondazione, una di Cannone, Buco Nero e
Dinosauro, due carte della Fase 2** (Incendio e Dado del Destino), **una del Lazzo
e della Canna da Pesca e una del Pinball e di First Person Shooter**
(Pozza di Veleno, Deflect e Feretro hanno lasciato il posto alle tre nuove; il
Cannone Laser è ciò che il Cannone diventa al secondo upgrade):
tutte in mano (energia 12) tranne la Canna, in attesa fra le esaurite perché non
si pesca mai in mano. Sono dieci carte, più di quante ne tenga mai la mano del
gioco: restano larghe come in una mano piena di otto e si sovrappongono da un
lato all'altro dello schermo, ognuna in vista quanto le serve per mostrare tutte
le sue parole, l'icona, i segni della rarità e il tasto, in qualunque ordine
stiano; quella sotto il mouse si alza intera sopra le altre, e `9` e `0` giocano
la nona e la decima (vedi [Bomb Marley](regole/meccaniche.md#bomb-marley),
[Inondazione](regole/meccaniche.md#inondazione),
[Cannone](regole/meccaniche.md#cannone-e-cannone-laser), [Buco Nero](regole/meccaniche.md#buco-nero),
[Dinosauro](regole/meccaniche.md#dinosauro-e-sanguinamento),
[Incendio](regole/meccaniche.md#pozza-di-veleno-e-incendio),
[Dado del Destino](regole/meccaniche.md#deflect-feretro-dado-del-destino-e-lama-velenosa),
[Lazzo](regole/meccaniche.md#lazzo), [Canna da Pesca](regole/meccaniche.md#canna-da-pesca), [Pinball](regole/meccaniche.md#pinball) e
[First Person Shooter](regole/meccaniche.md#first-person-shooter)). Niente ricompense, uscita o
profilo; `F5` ricomincia, `F10` torna al menu. Arena, mazzo e ritmo degli arrivi
sono in [mechanics_lab.odin](../src/devtools/mechanics_lab.odin) e
[sandbox.odin](../src/game/sandbox.odin): per provare una nuova meccanica basta
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
costo e la finestra che si accorcia ([Modalità tattica M7](regole/combattimento.md#modalità-tattica-m7)),
i cartoncini vivi, il cerchio d'azione del Viandante, le intenzioni dei nemici
nel cartellino della vita e sul terreno, i segnalini di carta e la vita di ogni nemico sempre
visibile in un cuore di carta sopra la testa
([Il tavolo](presentazione.md#il-tavolo-cartoncini-vivi-cerchi-e-segnalini)). Anche
[Movimento Ombra](regole/meccaniche.md#movimento-ombra), la carta che si prova qui adesso, è nel
mazzo iniziale di ogni run tattica. Lo stesso vale per gli status a stack
Veleno, Bruciatura e Rallentamento ([Status](regole/combattimento.md#status)), per i dadi delle carte
che salgono dal D4 al D20 con gli upgrade ([Spell e dadi](regole/carte.md#spell-e-dadi)) e per
i colpi che si vedono sul tavolo, ognuno con la sua arma di carta
([Il tavolo](presentazione.md#il-tavolo-cartoncini-vivi-cerchi-e-segnalini)). Le carte nuove della
Fase 2 ([Pozza di Veleno e Incendio](regole/meccaniche.md#pozza-di-veleno-e-incendio) e
[Deflect, Feretro, Dado del Destino e Lama Velenosa](regole/meccaniche.md#deflect-feretro-dado-del-destino-e-lama-velenosa))
compaiono fra ricompense e negozio di ogni run tattica, come il [Lazzo](regole/meccaniche.md#lazzo),
la [Canna da Pesca](regole/meccaniche.md#canna-da-pesca), il [Pinball](regole/meccaniche.md#pinball),
[First Person Shooter](regole/meccaniche.md#first-person-shooter), [Inondazione](regole/meccaniche.md#inondazione) e
[Bomb Marley](regole/meccaniche.md#bomb-marley).
La prova resta la sandbox in cui provare le prossime.

**Intenzioni dei nemici (`F6`).** Il simbolo dell'azione sta dentro il cartellino
della vita, vicino al cuore e alle cifre. Nella run è affiancato dalle minacce
sul terreno ([Il tavolo](presentazione.md#il-tavolo-cartoncini-vivi-cerchi-e-segnalini)).
Nel laboratorio `F6` alterna `HUD + TERRENO` e `SOLO HUD` per confrontarli:
i simboli compatti restano in entrambi i modi, senza icone separate sopra gli
attori. Il cartello mostra il modo attivo.

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
[tools/audio](../tools/audio/SOUND_SPEC.md) li sintetizza dalla materia
dell'azione (cuoio, ferro, legno, osso, pietra e la carta del cartoncino che
striscia sulla pietra), li mette tutti nella stessa sala di pietra e tiene
magie e segnali in Re frigio. Partono con il disegno che li mostra
([lab_sounds.odin](../src/render/lab_sounds.odin)), così i passi cadono sui passi
e i colpi sull'impatto (un dardo che manca suona quando arriva a terra, e chi
lo schiva quando lo schiva), con piccole variazioni di altezza e volume a ogni
colpo, e un limitatore sull'uscita tiene puliti i momenti più fitti (un colpo,
una caduta e un'esplosione insieme); seguono il volume degli effetti e il muto
delle impostazioni. Gli effetti suonano anche nella nuova spedizione. Nella modalità a stanze
precedente restano limitati al laboratorio, come i film di
[Mostra effetto](presentazione.md#mostra-effetto), che si sentono solo qui. Per rifarli dopo
aver cambiato una ricetta (`tools/audio/sfx_<famiglia>.py`):

```bash
"C:/Program Files/Blender Foundation/Blender 3.5/3.5/python/bin/python.exe" tools/audio/build_sfx.py
```

Il comando riscrive `assets/audio/lab/*.ogg` (Ogg Vorbis a 192 kbit/s: un terzo
dei WAV, e raylib lo decodifica campione per campione; lo codifica il modulo
audio di Blender) e la tabella generata
[lab_sfx_data.odin](../src/engine/audio/lab_sfx_data.odin); con
`--only <famiglia> --preview <cartella> --no-write` produce invece spettrogrammi,
misure e un ascolto di tutta la famiglia, senza toccare il gioco.

### Editor delle mappe

`--editor-mappe` apre l'editor per scolpire a mano le mappe (Fase 6 di
[piano-profondita.md](piano-profondita.md)): le sei arene della Prova meccaniche e le mappe dei dodici biomi,
come le fa il codice e con i ritocchi già salvati. **Tab** passa alla mappa seguente (**Maiusc+Tab** alla
precedente). Il pannello in alto dice la mappa, il piano, il pennello e la sua grandezza, se ci sono modifiche non
salvate e quanti errori ha la mappa; in basso c'è il promemoria dei tasti.

- **Telecamera:** il tasto destro trascinato, o **Q** ed **E**, la fanno ruotare; la rotella avvicina e
  allontana; **WASD** la sposta.
- **Piano attivo:** **PagSu** e **PagGiù** passano fra sotto profondo, sotto, terra e sopra. Il piano attivo e
  quelli sotto si vedono pieni, quelli sopra trasparenti.
- **Pennelli** (tasti **1**–**9**), con il tasto sinistro; tenuto premuto, il pennello ripassa:
  1. **Alza** e 2. **Abbassa**: un gradino a passata;
  3. **Leviga**: ogni casella prende la media con le sue vicine;
  4. **Appiattisci**: tutto all'altezza della casella da cui si parte;
  5. **Dipingi**: il tipo di casella, che **T** cambia (pavimento, roccia, vuoto, recinto). Sui piani sopra e
     sotto la terra il pavimento crea il piano e il vuoto lo toglie;
  6. **Rampa**: un clic per capo, e le caselle fra i due salgono in pendenza;
  7. **Copia**: si trascina un rettangolo; 8. **Incolla**: un clic mette giù il pezzo, con l'angolo in alto a
     sinistra sotto il mouse;
  9. **Rumore**: ogni casella un gradino su, giù o com'è, sempre uguale per la stessa passata.

  **[** e **]** (o **-** e **=**) cambiano la grandezza, da 0 (una casella) a 12.
- **Cosa resta del codice:** i pennelli non toccano le caselle degli edifici. Partenza, uscita e porte si
  possono alzare e abbassare, ma un pennello non le toglie e non ne fa di nuove: una partenza incollata diventa
  pavimento.
- **Ctrl+Z** annulla un'intera passata, **Ctrl+Y** (o **Ctrl+Maiusc+Z**) la rifà.
- **Ctrl+S** salva, ma prima controlla la mappa:
  - le colonne dei piani: almeno 12 gradini fra due pavimenti, e ogni scala fra due pavimenti vicini;
  - la partenza, che deve essere calpestabile;
  - nei biomi, anche: la partenza e i luoghi in piano, e dalla partenza si raggiungono ogni luogo, l'interno di
    ogni grotta e l'uscita.

  Gli errori sono segnati in rosso, con un'asta che si vede da lontano. **G** porta la telecamera all'errore
  seguente. Una mappa con errori non si salva. Le mappe come le fa il codice non ne hanno.
- **F5** ricarica la mappa dai file, **Esc** chiude. Con modifiche non salvate, Tab, F5 ed Esc vanno premuti
  due volte.

**I file.** I ritocchi stanno in `assets/mappe/laboratorio/<arena>/` (`piana`, `altezze`, `strutture`,
`montagna`, `grotta`, `piani`) e in `assets/mappe/biomi/<bioma>/`: il nome del bioma nel codice, in minuscolo
(`cyber`, `west`, `jungle`, `city`, `egypt`, `vietnam`, `snow`, `inferno`, `gothic`, `sky`, `space`, `secret`).
Ogni piano ritoccato ha due immagini grandi quanto la mappa, una casella un pixel; i piani si chiamano
`sotto_profondo`, `sotto`, `terra` e `sopra`:
- `<piano>_altezze.png`: le altezze in grigio, un livello di grigio a gradino;
- `<piano>_tipi.png`: i tipi a colori.

Un pixel trasparente è una casella come la fa il codice. Le immagini si possono dipingere anche con un altro
programma: ogni colore vale il tipo del colore più vicino (sotto). I colori di partenza, uscita e porte non
contano, e un'immagine di un'altra grandezza resta fuori. Se i file di una mappa rompono la regola dei piani, il
gioco li lascia fuori tutti, con un avviso, e usa la mappa del codice; l'editor invece li apre, con gli errori in
rosso, per correggerli.

| Tipo | Colore (R, G, B) |
|---|---|
| vuoto | 0, 0, 0 |
| pavimento | 200, 200, 200 |
| roccia | 120, 72, 40 |
| recinto | 230, 190, 40 |

Il gioco legge i file all'avvio. La Prova meccaniche li mette sulla sua arena; le spedizioni li mettono sulla
mappa del bioma dopo la geografia (rilievi, montagna, strutture, grotte) e prima di nemici e segreti. Fanno parte
del bioma, non della run: la mappa resta la stessa a ogni partita. `--smoke-editor-mappe` fa lo smoke
dell'editor: scrive solo in `build/editor_smoke/mappe` e lascia le catture in `build/captures/odin_pp_editor_*.png`.

| Opzione | Uso |
|---|---|
| `--run` | salta il menu ed entra subito nella run |
| `--minigame=<id>` | apre un minigioco sopra il menu (`platform2d`, `platform3d`, `arena`, `fps`, `puzzle`, `ring`) |
| `--smoke-menu` | cattura `odin_pp_menu.png` dopo 30 frame ed esce |
| `--animation-speed=2` | velocità delle animazioni ordinarie, fra 0.25x e 4x; non accelera cast o dadi M8 |
| `--fast` | velocità 4x |
| `--mechanics-lab` | Prova meccaniche: arena aperta senza fine, mazzo delle carte in prova (Bomb Marley, Inondazione, Cannone, Incendio, Buco Nero, Dinosauro, Dado del Destino, Lazzo, Pinball, First Person Shooter, Canna da Pesca), nemici che continuano ad arrivare; `F7` libera l'arena per la Canna da Pesca |
| `--spell-lab` | arena con Firebomb, Fate Strike, Chain Lightning, Sundering Blow e Guard |
| `--dice-lab` | arena con Fate Strike, Sundering Blow, Prismatic Barrage, Twin Venom e Guard |
| `--dice-set-lab` | tavolo 3D del set D4/D6/D8/D10/D%/D12/D20: selezione, lancio e rotazione con il mouse |
| `--engine-lab` / `--arena-lab` | arena libera con collisioni, dummy e strumenti M9 |
| `--ring-lab` | ring 1v1 di pratica con strumenti M9; non assegna sblocchi |
| `--fps-lab` | prova FPS con strumenti M9 e due livelli selezionabili |
| `--editor-mappe` | editor delle mappe: scolpisce arene e biomi e ne salva i ritocchi in `assets/mappe` (vedi «Editor delle mappe») |
| `--smoke-editor-mappe` | smoke dell'editor: scolpisce, salva in `build/editor_smoke/mappe`, riapre e cattura `odin_pp_editor_*.png` |
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
I laboratori M9 non si combinano con altri laboratori, smoke o report. `--m9` è un alias del tattico corrente;
non sostituisce il combattimento principale con il movimento libero.
