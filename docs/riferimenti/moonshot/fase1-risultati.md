# Fase 1 — Il laboratorio della pagina

Resoconto storico del primo campione. Per la successiva integrazione di cartoncino e sprite e la correzione
della capacità dei salvataggi vedere il [resoconto aggiornato](fase1-cartoncino-capacita.md).

4 novembre 2026, ramo `piano-moonshot`, base `ddc6b186942d4c78597dc0f3f06c1a73483b716e`.
Modifiche locali, nessun commit o push. Comando dell'utente: «vai alla prossima!! perche' gli snapshot falliscono??».

**Stato: campione implementato e verificato localmente; fase aperta al giudizio visivo dell'utente.**
La grammatica di movimento, i casi freccia/bomba/volo e l'aspetto definitivo non sono approvati.
Le misure non certificano 60 FPS stabili. Non è stata avviata la Fase 2.

## A cosa serve e come si apre

Dal menu scegliere **La pagina prende vita**, oppure avviare `build/odin-page-lab --page-lab`.
È un laboratorio visivo isolato, destinato a verificare continuità al piede, pieghe, ombre e selezione.
Le figure semplici sono campioni tecnici; non costituiscono la direzione artistica definitiva.
La campagna mantiene il renderer e le regole esistenti.

- `1–9` oppure frecce del pannello: fermo, passo, curva, salita, montatura, morte, freccia, bomba, volo.
- Spazio: pausa; cursore Piega: posizione nel ciclo, mettendo in pausa.
- `C`: camera reale della spedizione, dettaglio, prima persona reale.
- Tasto centrale trascinato: rotazione nel dettaglio o sguardo in prima persona; rotella: zoom nel dettaglio.
- Clic su una superficie e **Osserva**: centratura per l'ispezione. `O`: ombre; `T`: copertura; `F4`: contatori.
- Esc o Torna: menu. Le prove automatiche non leggono né scrivono il profilo.

La [galleria locale](../../../build/moonshot/fase1/gallery/index.html) raccoglie le catture originali:
21 viste e tre sequenze da 12 immagini. Le sequenze sono campionate ogni 20 aggiornamenti a passo 1/60 s,
quindi la riproduzione a 3 immagini/s permette di seguire la piega ma non certifica la fluidità fra frame adiacenti.
Il comando e il generatore per ricrearla sono in `tools/moonshot/README.md`.

## Cosa è effettivamente implementato

**FATTO — `src/render/page_lab_geometry.odin:439,481`.** Un dominio di pagina 16×12 viene suddiviso
fra terreno e ritagli. I triangoli sollevati sostituiscono il suolo: sotto rimane un foro reale. I bordi
non tagliati usano gli stessi indici di vertice della pagina. La validazione controlla indici, coordinate
finite, area nel foglio originale, connessione e cerniere di tutte le categorie. Non ci sono basette.

**FATTO — `src/render/page_lab_geometry.odin:203`.** Le suole si incurvano dalla pagina; cammino e curva
trasferiscono la posizione del ritaglio. La salita campiona la stessa rampa della stanza reale.
La morte chiude la figura nel proprio taglio. Montatura mostra cavaliere e cavalcatura come un'unica
sagoma con quattro radici e una piega animata: non dimostra ancora la trasformazione completa fra
personaggio a piedi e personaggio montato. Freccia, bomba e volo sono sagome incernierate; non hanno
traiettorie, danni o nuove regole di gioco.

**FATTO — `src/render/page_lab_draw.odin:158,358,405`.** Disegno, picking e proiezione delle ombre usano
gli stessi triangoli. Il foro dell'arco lascia passare il raggio; il tetto nascosto smette di intercettarlo.
Sotto ponte e tetto non viene inventato un secondo pavimento per riempire il taglio. Le ombre sono
proiettate sulle parti reali della pagina, con indice spaziale e clipping; non c'è auto-ombra fra sagome.
Lo spessore visivo del taglio è 0,014 unità; il picking usa la superficie centrale, senza ingrandirne il bersaglio.

**FATTO — `src/run/page_lab_fixture.odin:75`; test in `page_lab_fixture_test.odin:42,60,83`.** Le viste
Spedizione e Nei suoi occhi passano dalle funzioni reali del gioco, comprese quota e transizione della
prima persona. Dettaglio è dichiaratamente una camera di ispezione. Non viene scelta una nuova camera
per il gioco. La fixture contiene soltanto stato già esistente e viene distrutta uscendo dalla scena.

**FATTO — `src/render/page_lab_draw.odin:67,81`.** Colori, righe, fibra, retro, tagli e pieghe sono prodotti
da codice. Nessun asset scaricato. Un solo shader persistente; nessuna mesh o texture GPU posseduta
dal campione. Il batch e le risorse del motore restano condivisi e hanno un costo separato.

## Cartoncino e animazioni interne

L'utente ha chiesto se il campione potrà conservare l'effetto cartoncino e le animazioni all'interno della
figura già presenti nei placeholder. **PROPOSTA: sì, mantenere insieme movimento del supporto e stampa animata.**
La piega modifica la superficie; il fotogramma o il disegno procedurale modifica ciò che è stampato sopra.
Le coordinate della stampa devono seguire la superficie senza scorrere e senza spostare la cerniera del piede.

**FATTO:** la selezione del fotogramma e del suo rettangolo esiste già in
`src/render/sprite_assets.odin:387,400`; anche le strutture hanno stampe animate in
`src/render/expedition_fixture_sprites.odin:137`. **INFERENZA:** questo offre una base da adattare alla
nuova geometria, non un collegamento già realizzato in F1. Le animazioni che cambiano soltanto occhi,
luci o ingranaggi possono conservare la sagoma; quelle che cambiano il contorno devono aggiornare
geometria, ombra e selezione coerentemente. Materiale e stampa definitiva richiedono un'altra prova
visiva e misure: non si promette un costo nullo.

## Misure e limiti

**MISURA:** Apple M1, OpenGL `4.1 Metal - 90.5`, Odin `dev-2026-10:84bc3fc21`, build `-o:speed` del
driver `tools/moonshot/page_lab`. Tre processi seriali, quattro atti per processo, canvas logico e
texture entrambi 1920×1080, limite FPS e vsync disabilitati. Per atto: 60 frame iniziali esclusi e 600
misurati, tempo simulato 1/60 s. Totale 7.200 campioni misurati, 7.920 con il riscaldamento.
Nessun readback, cattura o stampa CSV durante la raccolta dei singoli atti; niente compilazioni concorrenti.

| Atto | Media r1 / r2 / r3, ms | p95 r1 / r2 / r3, ms |
|---|---:|---:|
| Fermo | 11,65 / 12,75 / 11,81 | 16,18 / 17,91 / 18,26 |
| Passo | 14,67 / 14,12 / 12,89 | 22,75 / 23,03 / 17,52 |
| Salita | 18,65 / 14,10 / 17,02 | 25,64 / 14,99 / 19,91 |
| Volo | 13,91 / 8,33 / 8,33 | 19,64 / 8,49 / 8,48 |

Il campione **non rispetta stabilmente il budget p95 ≤16,7 ms**. Non è una misura del combattimento o
di una mappa grande, né una previsione del costo finale. La variabilità fra processi resta nei risultati.
Update comprende ricostruzione del modello e camera; draw comprende preparazione e invio CPU, incluse
le ombre, non il tempo GPU. Prima dell'integrazione servono riuso della geometria statica e un percorso
di ombre meno costoso; il prototipo attuale ricostruisce anche le parti ferme a ogni aggiornamento.

Capacità CPU fissa del modello: **5.712.064 byte**; contesto di disegno: **3.409.456 byte**, compresi
gli scratch buffer. Non sono conteggi VRAM. RSS massima dell'intero processo: **128,36 / 135,19 / 128,52 MiB**.
Uno shader e zero mesh posseduti dal campione in tutti gli atti; nessun fallback dell'indice delle ombre.
Il caso fermo ha 4.547 vertici e 6.942 triangoli; il picco osservato nei quattro atti è 5.674 vertici e
9.032 triangoli. La prima versione ne aveva 7.186 e 12.144 da ferma: ponte e tetto sono stati compressi
conservando cerniere e superfici. Non è stato misurato un A/B prestazionale completo della prima versione.

I [dati numerici](fase1-misure.json), il [rapporto esteso](fase1-misure.md) e
l'[archivio delle prove](fase1-prove.zip) conservano risultati e condizioni. Il primo smoke v1 fu
interrotto volontariamente dopo quattro catture per correggere costo delle ombre e stampa a triangoli;
il suo log resta conservato. Non viene contato come smoke completo. Nessuna misura Windows eseguita.

## Verifiche e carta IA

- `odin check src -vet -strict-style` e variante driver benchmark: superati.
- Renderer: **526/526**; run: **25/25**; application: **23/23**. Comprendono 22 nuovi test Odin.
- Strumenti Python: **17/17**, di cui otto nuovi per rifiutare misure troncate, incoerenti o non finite.
- Smoke finale: **21 catture e 36 frame di sequenza**, tutte le verifiche topologiche valide; shader
  compilato, scena distrutta e finestra chiusa. Controllo visivo di panorama, piede, arco, copertura,
  morte, prima persona e pannello; accesso dal menu verificato con cattura nativa.
- Picking sul modello reale, fronte/retro, tetto nascosto, vuoti e ombre sulla rampa; equivalenza delle
  query spaziali rispetto alla ricerca esaustiva e rilascio della memoria della fixture.

**IA: nessuna nuova meccanica.** Non sono stati cambiati enum, carte, bersagli, collisioni o tempi della
simulazione. La selezione qui ispeziona il disegno e non invia mosse. Non si inventa un puzzle o una voce
IA per una posa visiva; restano attivi i controlli esistenti. Qualunque futura regola di movimento, volo,
montata o terreno richiederà copia, mosse, valutazione, contesto, puzzle e registro nello stesso lavoro.

## Perché falliscono gli snapshot grandi

**FATTO — `src/expedition/snapshot.odin:7,85`.** Lo snapshot di stato ha capacità `224*224 = 50.176`
celle. Già la più piccola mappa a 2× lato è 320×320, cioè 102.400 celle: `capture` la rifiuta prima della
copia. Il probe riesce a generare la mappa ma non a conservarla in quel formato. Non è un errore delle
immagini dello schermo. Inoltre `layer_cell_pack/unpack`, righe 71–76, riserva solo 16 bit all'indice
della cella: aumentare la sola capacità non risolverebbe la persistenza dei livelli sovrapposti.
La modifica versionata di formato, ripristino e dati del mondo resta nella Fase 4, con verifiche IA.

## Fonte primaria consultata per il percorso grafico

**FONTE:** [raylib 6.0, rlgl.h](https://github.com/raysan5/raylib/blob/6.0/src/rlgl.h), letto nel sorgente:
batch condiviso, flush e fattori/equazioni separati del blend personalizzato. Il prototipo utilizza
queste API, già disponibili nel progetto; la fonte non certifica prestazioni o compatibilità di una
scena particolare. Le misure sopra sono locali. Non è stato cambiato back-end.

Il laboratorio è stato riaperto in modalità interattiva su richiesta dell'utente e lasciato disponibile.
Il controllo finale ha corretto il doppio uso di Spazio (pausa e conferma del pulsante focalizzato),
con test dedicato: la correzione è nel binario su disco e si applica al successivo avvio.
Non cambia geometria o misure. Il manifest conserva la scena esatta compilata per il benchmark e
distingue il binario delle catture dall'ultima build interattiva.
