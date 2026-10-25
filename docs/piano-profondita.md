# Piano di lavoro: profondità, terreno scolpito e mappa a piani

Scritto il 25 ottobre 2026 sul ramo `piano-profondita`, partito da
`biomi-sbloccati` (commit `de887a1`). Quel ramo contiene tutto il
[piano della griglia](piano-griglia.md) (Fasi 0–11 fatte), la revisione delle
carte e il pulsante temporaneo «TEST tutti i biomi», utile per provare le fasi
in ogni bioma (sezione 1.6).

Il documento raccoglie due richieste dell'utente dello stesso giorno:

1. **Terreno scolpito.** «Un'asse in più all'interno della mappa»: la mappa
   deve essere modellabile, ciò che è calpestabile si distingue da ciò che non
   lo è, e nessuno dei due è una superficie piatta.
2. **Profondità.** Una mappa «interconnessa in parecchi punti», con «accesso a
   grotte senza caricamento» e salite, «tenendo sempre la griglia per il
   combat».

La risposta discussa in chat è una **mappa a piani**: fino a tre griglie
sovrapposte (sotto, terra, sopra), ognuna con il suo terreno scolpito, e il
combattimento sempre a griglia. La sezione 2 descrive il modello; le fasi lo
costruiscono un pezzo alla volta.

Rispetto alle otto fasi proposte in chat ci sono tre differenze:
- **Una Fase 0 in più**, proposta da Claude: oggi il benchmark non arriva agli
  stage di rilievi, montagna e grotte, cioè proprio alle parti che questo
  lavoro cambia.
- **I salvataggi entrano nella Fase 5**, perché i piani nelle spedizioni non si
  possono provare senza salvarli.
- **L'editor viene prima dei biomi** (Fase 6, poi Fase 7): le interconnessioni
  dei biomi si costruiscono meglio scolpendole a mano.

**Aggiornato lo stesso giorno** dopo lo studio della mappa di Elden Ring,
chiesto dall'utente: le idee che ne vengono sono nella sezione 2.9 e nelle
Fasi 3, 5, 7 e 8.

In questo documento «piano» vuol dire sempre un piano della mappa; il
documento stesso si chiama «questo documento».

Le fasi si eseguono **una alla volta, solo su comando dell'utente**. Le regole
per Claude sono nella sezione 1 e vanno lette prima di ogni fase. L'ordine
consigliato è nella scaletta, subito dopo la tabella.

## Stato delle fasi

La tabella è in ordine di priorità, cioè l'ordine della scaletta qui sotto.

| Priorità | Fase | Contenuto | Dipende da | Stato | Commit |
|---|---|---|---|---|---|
| 0 | 0 | Misure di partenza: il benchmark arriva a rilievi, montagna e grotte (proposta di Claude) | — | Proposta | — |
| 1 | 1 | Terreno scolpito: rampe, colline e dirupi di roccia, solo grafica | — (meglio dopo la 0) | Da fare | — |
| 2 | 2 | Posizioni con il piano: il terzo numero, tutto a «terra» | — | Da fare | — |
| 3 | 3 | Piani nel laboratorio: dati e regole | 2 | Da fare | — |
| 4 | 4 | Piani nel laboratorio: trasparenze, contorni, mouse, luce | 3 (1 per l'aspetto) | Da fare | — |
| 5 | 5 | Piani nelle spedizioni: grotte senza caricamento | 1, 3, 4 | Da fare | — |
| 6 | 6 | Editor per scolpire i piani | 1, 3 (5 per le mappe dei biomi) | Da fare | — |
| 7 | 7 | Ponti, gallerie e scorciatoie nei biomi | 5, 6 | Da fare | — |
| 8 | 8 | Ologramma completo, prestazioni, grotte vecchie | 5 (meglio dopo la 7) | Da fare | — |

## Scaletta: cosa sviluppare prima

Ordine consigliato da Claude il 25 ottobre 2026. È l'ordine della tabella, e
«Passa alla prossima fase» lo segue. L'utente può sempre cambiarlo nominando
una fase.

**I criteri:**
- **Valore subito:** il terreno scolpito si vede in ogni partita e non tocca
  le regole, quindi viene per primo.
- **Rischio:** le regole fra piani si collaudano nel laboratorio, dove l'arena
  è piccola e i test sono veloci; renderer, salvataggi e prestazioni delle
  spedizioni vengono dopo.
- **Dipendenze:** nessuna fase arriva prima di ciò che le serve.
- **Niente lavoro rifatto:** le posizioni prendono il piano una volta sola,
  prima di tutte le regole che lo usano; l'editor arriva prima dei biomi che
  servirà a modellare.
- **Misure confrontabili:** ogni fase che tocca il renderer misura prima e
  dopo sugli stessi stage (Fase 0).

**La scaletta.** Le dimensioni sono relative alle altre fasi di questo
documento.

| Priorità | Fase | Perché in questa posizione | Dimensione | Rischio |
|---|---|---|---|---|
| 0 | Fase 0: misure di partenza | Ogni fase grafica misura le prestazioni, ma oggi il benchmark si ferma prima di rilievi, montagna e grotte, e i numeri dei documenti vengono da un altro computer. | piccola | basso |
| 1 | Fase 1: terreno scolpito | È il salto visivo più grande, in ogni bioma, senza cambiare una regola. È anche la superficie su cui poggeranno i piani. | grande | medio: renderer delle spedizioni e prestazioni |
| 2 | Fase 2: posizioni con il piano | È il prezzo dei piani: lavoro meccanico ma esteso (circa mille posizioni scritte nel codice e ancora di più nei test). Si fa una volta, prima delle regole. | grande | medio: tocca quasi tutti i pacchetti |
| 3 | Fase 3: piani nel laboratorio, regole | Movimento, vista, aree e IA fra piani, provati in un'arena piccola. | grande | alto |
| 4 | Fase 4: piani nel laboratorio, grafica | Senza trasparenze, contorni e il mouse giusto i piani non si leggono a schermo. | media | medio |
| 5 | Fase 5: grotte senza caricamento | Il primo uso vero: le grotte di oggi diventano un piano sotto, senza dissolvenza. Porta i piani nel renderer, nei salvataggi, nell'esplorazione e nell'ologramma. | molto grande | alto |
| 6 | Fase 6: editor | Serve a scolpire a mano le mappe dei biomi della Fase 7. È uno strumento: non cambia le regole. | media | basso |
| 7 | Fase 7: ponti, gallerie e scorciatoie | Qui la profondità diventa disegno dei livelli: la mappa interconnessa che l'utente chiede, con altopiani dai pochi accessi, scorciatoie e sotterranei sul modello di Elden Ring (sezione 2.9). | grande | medio |
| 8 | Fase 8: ologramma, prestazioni, pulizia | Chiude il lavoro: l'ologramma si completa, si misura tutto e si toglie il codice vecchio delle grotte. | media | basso |

**Se la priorità è un'altra:**
- **Solo l'aspetto, per ora:** 0 → 1, e ci si ferma lì. Il terreno scolpito
  sta in piedi da solo.
- **Le grotte prima possibile:** 0 → 2 → 3 → 4 → 5, con il terreno scolpito
  dopo; le grotte nascono con le terrazze di oggi.

**Prima delle fasi grandi** conviene controllare se `main` è cambiato negli
stessi file: 0xdokkan lavora anche su renderer e spedizioni.

## 1. Comandi per Claude

### 1.1 Come si avvia una fase

L'utente scrive uno di questi comandi:

```text
Esegui la Fase 1 di docs/piano-profondita.md
```

```text
Passa alla prossima fase di docs/piano-profondita.md
```

Ogni fase ha anche il suo comando pronto, alla fine della sua sezione.
- **Prossima fase.** La tabella è in ordine di priorità, quindi «prossima
  fase» significa la prima riga con stato `Da fare`. Se prima c'è una fase
  `Proposta`, chiedi se va fatta o saltata.
- **Fasi `Proposta`.** Si eseguono solo se l'utente le conferma.

### 1.2 Regole per ogni fase

1. **Una fase sola.** Esegui solo la fase richiesta. Non iniziare, non
   preparare e non affidare ad altri (sessioni nuove, agenti in background,
   workflow) nessun'altra fase. Vale anche se la memoria dice di concatenare
   le fasi: per questo documento, come per il piano della griglia, l'utente
   vuole fermarsi dopo ognuna.
2. **Prima di scrivere codice.**
   - `git status` deve essere pulito. Lavora sul ramo `piano-profondita`, o su
     quello che indica l'utente. Mai commit su `main`.
   - Rileggi la sezione della fase e controlla che file e funzioni citati
     esistano ancora: il documento descrive il codice del 25 ottobre 2026. Se
     qualcosa è cambiato, adatta il lavoro e scrivilo nell'esito della fase.
   - Fai all'utente, **tutte insieme**, le domande della voce «Da chiedere
     prima di iniziare», con la raccomandazione come prima opzione. Aspetta le
     risposte. Se una risposta cambia il progetto, aggiorna prima questo
     documento.
   - Segna la fase `In corso` nella tabella.
3. **Durante la fase** valgono le regole del progetto:
   - rispondi in italiano;
   - le meccaniche nuove si provano prima in Prova meccaniche e passano al
     gioco normale solo dove la fase lo dice;
   - suoni e disegni si creano da codice (`tools/audio`, `tools/art`), mai
     scaricati;
   - i file di prova vanno nella scratchpad, non nel repo;
   - compilatore: `C:\Users\lukeg\OneDrive\Desktop\odin-dev-2026-10\dist\odin.exe`
     (quello nel PATH è troppo vecchio);
   - dopo ogni modifica piccola: `odin check src -vet -strict-style` e i test
     del pacchetto toccato.
4. **Verifica di fine fase.** È obbligatoria; i comandi sono nella sezione
   1.4. Servono:
   - check normale e senza assert;
   - suite completa: nessun test deve fallire (sezione 1.5);
   - build del gioco;
   - smoke del laboratorio e, nelle fasi che toccano le spedizioni, delle
     spedizioni, guardando davvero le catture;
   - nelle fasi che toccano il renderer, il benchmark prima e dopo.
5. **Chiusura.**
   - Aggiorna `CHANGELOG.md`, i documenti che la fase nomina, la tabella
     (stato `Fatta`, commit) e la voce «Esito» della fase.
   - Fai il commit sul ramo, con un messaggio in italiano che finisce con la
     riga `Co-Authored-By` di Claude. Niente push.
6. **Stop.**
   - Suona l'avviso forte sul PC dell'utente, come alla fine delle fasi del
     piano della griglia (comando nella sezione 1.4).
   - Scrivi il resoconto con il modello della sezione 1.3 e chiudi con la
     domanda sulla fase successiva. Poi **fermati**. Non iniziare la fase
     dopo, nemmeno in parte, finché l'utente non risponde di sì.
7. **Se qualcosa si blocca** (una decisione che manca, test che non passano,
   un'idea che non regge): fermati, spiega e chiedi. Non saltare a un'altra
   fase per guadagnare tempo.
8. **Se l'utente cambia idea:** prima aggiorna questo documento (la sezione
   della fase e la tabella), poi lavora.

### 1.3 Modello del messaggio di chiusura

```text
Fase N — <titolo>: completata (commit <hash> sul ramo piano-profondita).

Cosa è cambiato: …
Verifiche: check ok (anche senza assert); test <passati>/<totali>; build ok;
smoke: <atti e stage>, catture <…>; benchmark: <prima → dopo>.
Non verificato: …
Decisioni prese: …

Vuoi che passi alla Fase N+1 — <titolo>?
```

Dopo questa domanda il turno finisce.

### 1.4 Comandi delle verifiche

Da Git Bash, nella cartella `odin_pp`. `$S` è la scratchpad della sessione.

```bash
ODIN="/c/Users/lukeg/OneDrive/Desktop/odin-dev-2026-10/dist/odin.exe"
"$ODIN" check src -vet -strict-style
"$ODIN" check src -vet -strict-style -disable-assert
"$ODIN" test src -all-packages -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_FULL=false -o:none -out:"$S/tests.exe"
"$ODIN" build src -o:none -out:"$S/odin_pp.exe"
"$S/odin_pp.exe" --smoke-mechanics-lab
"$S/odin_pp.exe" --smoke-expedition
```

- **Suite completa in un colpo** (PowerShell): `$env:ODIN` con il percorso
  del compilatore, poi `.\scripts\check.ps1`: test con e senza assert, più le
  due build.
- **Un solo atto del laboratorio:** `ODIN_PP_LAB_ONLY=<atto>` (oggi
  `hit_marks`, `heights`, `structures`, `mountain`, `cave`:
  `src/devtools/mechanics_lab.odin:82-93`). Ogni fase che aggiunge un atto lo
  aggiunge anche qui. A fine fase lo smoke del laboratorio va completato:
  dura più di otto minuti.
- **Spedizioni da un punto:** `ODIN_PP_SMOKE_ONLY=hits` parte dagli scontri
  dei segni dei colpi (`src/application/campaign_smoke.odin:321-322`). Gli
  stage che contano qui: rilievi dal 63, ologrammi dal 75, due livelli 78,
  montagna 79, grotte dall'87.
- **Benchmark:**
  `"$ODIN" build src -o:speed -define:EXPEDITION_BENCHMARK=true -out:"$S/bench.exe"`,
  poi `"$S/bench.exe" --smoke-expedition` (`docs/direzione-implementazione.md`,
  «Ripetere il benchmark e leggere il profiler»). Dopo la Fase 0 arriva anche
  agli stage di rilievi, montagna e grotte.
- **Catture:** in `build/captures` (cartella ignorata da git). Gira un solo
  smoke alla volta.
- **Avviso di fine fase** (PowerShell, senza toccare il volume del sistema):

```powershell
$p = New-Object System.Media.SoundPlayer "$env:WINDIR\Media\Alarm01.wav"; 1..3 | ForEach-Object { $p.PlaySync() }
```

### 1.5 Test su Windows

- Il 25 ottobre 2026, sul ramo `biomi-sbloccati`, `.\scripts\check.ps1`
  completo finisce con **1654 test verdi**, con e senza assert, più le due
  build. Non ci sono fallimenti noti.
- Ogni pacchetto si lancia da solo con `odin test src/<pacchetto>`.
- Un test nuovo che decodifica lo snapshot della spedizione deve stare in un
  pacchetto che importa `src/engine/teststack`
  (`import _ "../engine/teststack"`), altrimenti su Windows lo stack non basta.
- I test scrivono nella cartella temporanea del sistema (`os.temp_directory`),
  mai in `/private/tmp`.

### 1.6 Il pulsante «TEST tutti i biomi»

Su questo ramo la galassia del Portale ha il pulsante temporaneo «TEST tutti i
biomi» (commit `de887a1`, voce del 25 ottobre 2026 in `CHANGELOG.md`). Serve a
provare le Fasi 5 e 7 in ogni bioma senza vincere quelli prima. Una spedizione
in un bioma aperto solo dal test non cambia il progresso; lo zaino segue le
regole normali.

## 2. Il modello: terreno scolpito e mappa a piani

### 2.1 Le parole del documento

- **Piano:** una delle griglie sovrapposte della mappa: **sotto** (−1, grotte
  e gallerie), **terra** (0, la mappa di oggi), **sopra** (+1, ponti,
  passerelle, balconi).
- **Colonna:** le caselle con le stesse x e y su tutti i piani.
- **Gradino:** l'unità di altezza delle regole, come oggi. A schermo è 0,12 di
  cella (`HEIGHT_STEP_DRAWN`, `src/game/height.odin:26`).
- **Superficie scolpita:** la forma disegnata del terreno: rampe, colline,
  dirupi.
- **Luce:** lo spazio libero sopra una casella calpestabile, dove sta un
  personaggio.
- **Spessore:** il pieno di un ponte, o della roccia sopra una grotta.
- **Imbocco:** un punto dove due piani si toccano e si passa camminando: una
  rampa, la bocca di una grotta, la testa di un ponte.

### 2.2 Com'è oggi, in breve

- **Una griglia sola** per spedizione, da 160, 192 o 224 caselle di lato
  (`map_size`, `src/expedition/world.odin:109`). Ogni casella ha un tipo
  (pavimento, muro, porta, recinto, vuoto…) e un'altezza in gradini, da 0 a
  255 (`src/level/level.odin:31-44`).
- **Le regole delle altezze** stanno tutte in `src/game/height.odin`: si sale
  e si scende un gradino; da due in su è un dirupo, che ferma chi cammina; una
  spinta fa cadere con danno; la vista passa sopra il terreno; da 4 gradini più
  in alto le carte a distanza arrivano una casella più in là.
- **A schermo** ogni casella rialzata è una terrazza piatta con fianchi di
  roccia dritti (`src/render/expedition_terrain.odin`). I personaggi però
  camminano su una media delle caselle vicine (`point_ground`,
  `src/render/height_view.odin:65`): scivolano su una rampa che non si vede.
- **Le grotte** sono una mappa a parte stampata sulla stessa griglia: con **E**
  all'arco lo schermo va al nero, la mappa aperta viene messa da parte e al suo
  posto compare la grotta (`enter_cave`, `src/expedition/cave.odin:221`).
- **Le posizioni** hanno due numeri (`grid.Position`,
  `src/engine/grid/grid.odin:5-7`).

### 2.3 Il terreno scolpito

- **La superficie si ricava dalle altezze**, con una funzione pura:
  - ogni casella ha un vertice al centro, alla sua altezza esatta, e quattro
    angoli;
  - un angolo è la media delle caselle che lo toccano e che stanno a un
    gradino al massimo dalla casella: una fila di gradini diventa una rampa,
    una collina a gradoni diventa una collina;
  - dove c'è un dirupo l'angolo non si unisce: resta lo spigolo, e sotto c'è
    una parete di roccia;
  - quattro triangoli per casella attorno al centro, a facce piatte: lo stile
    low-poly al neon del gioco.
- **Il centro resta alla sua altezza**, perché le regole contano l'altezza
  della casella e gli scontri si fanno al centro delle caselle: ciò che si vede
  coincide con ciò che conta.
- **Calpestabile o no** resta il tipo di casella di oggi più la regola del
  dirupo. Il terreno scolpito lo rende leggibile: dove si cammina ci sono la
  griglia e i colori del pavimento, dove non si cammina c'è roccia (pareti dei
  dirupi, massicci sopra le grotte) o ci sono gli oggetti del bioma. Rispetto
  alla prima proposta in chat non serve uno strato nuovo di «superfici»: il
  tipo di casella e i terreni dei biomi (`Expedition_Terrain`,
  `src/game/expedition_terrain.odin:6`) bastano.
- **Modellabile:** con l'editor della Fase 6, che scolpisce altezze e tipi di
  casella piano per piano.

### 2.4 I piani

```text
 sopra           ═══════ ponte ═══════
 terra   ________/______ strada _____\________/ montagna \________
 sotto                                         ( grotta )
```

- Tre griglie della stessa misura. La terra è la mappa di oggi; sotto e sopra
  sono quasi vuote e hanno caselle solo dove servono.
- Le altezze di tutti i piani si contano dallo stesso zero, in gradini. Il
  piano sotto sta dentro i rilievi: una grotta entra di lato in una collina, a
  livello del terreno attorno. Per scendere davvero sotto il suolo un bioma può
  alzare tutto il suo terreno di una base (Fase 7).
- **Colonna valida:** due caselle calpestabili della stessa colonna, su piani
  diversi, distano almeno luce + spessore (proposta: 10 + 2 gradini). Così
  sopra ogni personaggio c'è spazio, e in una colonna vicina c'è al massimo una
  casella calpestabile a un gradino di distanza.
- **Ogni casella calpestabile di ogni piano è una casella della griglia:** il
  combattimento resta a griglia, anche fra piani.

### 2.5 Regole fra piani (proposte, da confermare nella Fase 3)

- **Passo.** Si passa nella colonna vicina se lì c'è una casella calpestabile
  a un gradino al massimo, su qualsiasi piano. Per la regola della colonna ce
  n'è al massimo una, quindi il passo non sceglie mai il piano. Gli imbocchi
  nascono dalla forma della mappa, senza dati in più.
- **Scale a pioli**, se l'utente le vuole: collegano due caselle di piani
  diversi anche dove il dislivello è grande.
- **Ascensori e pozzi** (sezione 2.9): portano al piano sopra o sotto, nella
  stessa colonna; salirci è un passo.
- **Spinte e cadute.** Una spinta oltre il bordo di un ponte porta nella
  colonna vicina. Se lì il piano del ponte non c'è, si cade sulla prima casella
  calpestabile sotto, con il danno di caduta di oggi (dislivello − 1, al
  massimo 10).
- **Vista e tiri.** Ogni colonna ha tratti pieni (terreno, muri, impalcato del
  ponte, roccia sopra una grotta) e tratti vuoti. Una linea passa se a ogni
  colonna sta in un tratto vuoto. Dal ponte si vede e si colpisce chi sta sulla
  strada; dalla collina non si vede dentro la grotta. Il +1 di gittata da 4
  gradini più in alto vale anche fra piani.
- **Gittata.** Si misura su x e y, come oggi.
- **Aree.** In ogni colonna del disegno colpiscono la casella dello stesso
  piano dell'ancora, come oggi. Dove quel piano non c'è, colpiscono la casella
  più vicina in altezza, se dista al massimo 2 gradini: così un'area segue una
  rampa o un imbocco. Ponti e volte fermano l'area.
- **Mischia.** Fra piani diversi solo fra caselle a un gradino al massimo,
  cioè agli imbocchi; sullo stesso piano come oggi.
- **Chi sta dove.** Un personaggio per casella, come oggi: due personaggi
  possono stare sulla stessa x,y a piani diversi.
- **Nemici.** Il loro campo delle distanze attraversa i piani con la stessa
  regola del passo.

### 2.6 A schermo

- Ciò che sta sopra la testa del robot, vicino a lui, si dirada come gli
  edifici della Fase 6 del piano della griglia: la roccia sopra la grotta
  quando è dentro, il ponte quando ci passa sotto.
- Dentro una grotta il fuori si scurisce, come fuori da un edificio; sotto
  terra la luce è più scura e restano le luci dei personaggi.
- Chi è nascosto sotto un ponte o dietro la roccia si vede con un contorno.
- Il mouse sceglie la prima superficie visibile, saltando ciò che è diradato.
- La telecamera resta fissa, come vuole la direzione del gioco
  ([direzione.md](../direzione.md), 1.4), e segue la quota del robot.

### 2.7 Regole che proteggono il lavoro

1. **Tutto a «terra» e terreno piatto = gioco di oggi.** I test esistenti
   continuano a passare senza cambiare i valori attesi.
2. **Nessuno scambio silenzioso.** Una griglia di un solo piano rifiuta le
   posizioni di un altro piano, invece di confonderle con la casella della
   terra che ha le stesse x e y.
3. **Il disegno non cambia le regole.** Si conta sempre in gradini, al centro
   delle caselle.
4. **Geografia fissa.** I piani di un bioma sono uguali a ogni run
   ([direzione.md](../direzione.md), 1.1): il seme cambia nemici, bottino e
   luoghi attivi, non la forma della mappa.
5. **Salvataggi vecchi validi.** Ogni dato nuovo ha un valore predefinito che
   lascia validi i salvataggi di prima, con un test di andata e ritorno.

### 2.8 Strade scartate

- **Volume libero, tipo Minecraft** (scavare ovunque): più libertà, ma costa
  molto di più (mesh del volume, editor 3D, vista) e alla griglia del
  combattimento non serve.
- **Piani affiancati sulla stessa griglia 2D**, il trucco delle grotte di oggi:
  le posizioni non cambierebbero, ma distanze, aree e tiri fra piani sarebbero
  falsi, perché due caselle una sopra l'altra risulterebbero lontane.
- **Posizione come vettore di tre numeri** al posto della struct: cambierebbe
  il formato delle posizioni nei salvataggi di oggi (oggetti JSON con `x` e
  `y`).
- **Movimento libero senza griglia:** romperebbe il combattimento tattico.
- **Mappe modellate in Blender** con la griglia ricavata: la geografia
  uscirebbe dal codice, e dodici mappe fino a 224×224 andrebbero modellate
  tutte a mano.

### 2.9 Un riferimento: la mappa di Elden Ring

Il 25 ottobre 2026 l'utente ha chiesto di guardare la conformazione fisica
della mappa di Elden Ring. Ciò che conta per noi (fonti in fondo alla sezione):

- **Regioni a quote diverse, separate da pareti.** Liurnia è un grande lago in
  basso, l'Altopiano di Altus sta molto più in alto: l'altopiano si vede, ma ci
  si sale solo da pochi punti (un grande ascensore da attivare, un sentiero in
  un burrone con un boss, un passaggio segreto). Il disegno che l'utente ha
  fatto lo stesso giorno (un livello alto, un'altura, il personaggio in basso)
  è questa idea in piccolo.
- **Un mondo sotto il mondo:** fiumi sotterranei e città sepolte, raggiunti da
  pochi pozzi con lunghi ascensori, da portali e da buchi nel terreno. La mappa
  del gioco ha un tasto per vedere solo il sotterraneo.
- **Dungeon fitti dentro il mondo aperto:** castelli verticali con scorciatoie
  che si aprono dall'altra parte.
- **Punti di riferimento** visibili da lontano, e quasi tutto ciò che si vede si
  può raggiungere.
- **Zone impilate nel DLC** (Shadow of the Erdtree): posti vicini sulla mappa
  sono separati da salti e pareti, e alcuni segreti stanno sotto la zona, in un
  burrone. La critica più comune: la mappa del DLC non ha il tasto del
  sotterraneo, e non si capisce a che livello si è.

**Cosa ne prende questo documento:**

1. **Altopiani con pochi accessi** (Fase 7): ogni altopiano grande ha da 1 a 3
   accessi, almeno uno nascosto; il resto del bordo è dirupo.
2. **Ascensori e pozzi** (Fase 3): un collegamento fra piani nella stessa
   colonna, accanto a rampe e scale a pioli.
3. **Un sotterraneo grande in alcuni biomi** (Fase 7): non solo grotte dentro le
   colline, ma zone ampie sotto il suolo, raggiunte da un pozzo.
4. **Scorciatoie che si aprono dall'altra parte** (Fase 7): una porta, una leva
   o un ascensore; una volta aperte restano aperte anche nelle run dopo, come i
   segreti scoperti.
5. **L'ologramma con il tasto del piano già nella Fase 5**, quando arriva il
   primo piano sotto, e non solo nella Fase 8.
6. **Accessi segnati sull'ologramma** una volta scoperti (Fasi 5 e 8), così due
   posti vicini sulla mappa ma lontani a piedi non confondono.

**Cosa non si copia:** le visuali lunghe. Qui la telecamera è fissa e vicina
(circa 25×15 caselle), quindi i punti di riferimento lontani li mostra
l'ologramma.

**Fonti** (consultate il 25 ottobre 2026):
- [eXputer: la verticalità di Shadow of the Erdtree e la sua mappa](https://exputer.com/features/shadow-of-the-erdtree-verticality-better-map-system/)
- [GamingBolt: Miyazaki sulla verticalità del DLC](https://gamingbolt.com/elden-ring-shadow-of-the-erdtrees-map-boasts-a-better-sense-of-verticality-miyazaki)
- [Elden Ring Wiki: Siofra River](https://eldenring.wiki.gg/wiki/Siofra_River)
- [Elden Ring Wiki (Fandom): Ainsel River](https://eldenring.fandom.com/wiki/Ainsel_River)
- [Push Square: come arrivare all'Altopiano di Altus](https://www.pushsquare.com/guides/elden-ring-how-to-reach-altus-plateau-using-the-grand-lift-of-dectus-and-dectus-medallions)
- [Sports Illustrated: recensione di Shadow of the Erdtree](https://videogames.si.com/reviews/elden-ring-sote-review)
- [Well Played: recensione di Shadow of the Erdtree](https://well-played.com.au/elden-ring-shadow-of-the-erdtree-review)
- [GameSpot: il mondo aperto di Elden Ring](https://gamespot.com/articles/elden-ring-puts-a-from-software-spin-on-open-worlds/1100-6495648/)
- [Keen Gamer: il design del mondo aperto di Elden Ring](https://keengamer.com/articles/features/opinion-pieces/why-elden-ring-revolutionizes-open-world-design/)

## 3. Fase 0 — Misure di partenza (proposta di Claude)

### Perché

- Le Fasi 1, 5, 7 e 8 cambiano il renderer delle spedizioni e devono misurare
  le prestazioni prima e dopo.
- Oggi il benchmark si ferma allo stage 50: `EXPEDITION_BENCHMARK_LAST` vale
  al massimo 50 (`src/application/campaign_smoke.odin:81-82`; l'uscita è a riga
  408). Rilievi (stage 63–74), ologrammi (75–77), due livelli (78), montagna
  (79) e grotte (dall'87) non sono mai stati misurati, e sono proprio le parti
  che questo documento cambia. Le misure delle fasi del piano della griglia
  erano sugli stage 0–26.
- I numeri dei documenti vengono da un Apple M1 a 2560×1440
  (`docs/direzione-implementazione.md`, «Misure finali a risoluzione
  nativa»); le fasi si misureranno sul PC Windows dell'utente.

### Cosa si fa

1. Il benchmark accetta un intervallo di stage, primo e ultimo, fino alle
   grotte.
2. Misura di partenza sul PC dell'utente, ripetuta due volte (le due misure
   devono concordare): media, mediana e p95 per stage, scritte nell'esito.
3. Documenti: `docs/direzione-implementazione.md` (come ripetere il
   benchmark) e `CHANGELOG.md`.

### Da chiedere prima di iniziare

1. **Fare questa fase.**
   - (Consigliato) Sì.
   - Oppure no: ogni fase misura solo gli stage che il benchmark raggiunge
     oggi.
2. **Risoluzione delle misure.**
   - (Consigliato) Quella dello schermo, a finestra intera, come le misure dei
     documenti.
   - Oppure 1920×1080 fissa.

### Fatto quando

- Il benchmark arriva fino alle grotte e i numeri di partenza sono
  nell'esito.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 0 di docs/piano-profondita.md (Misure di partenza). Segui le
regole della sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

Da fare.

## 4. Fase 1 — Terreno scolpito

### Cosa si fa

Le altezze di oggi diventano una superficie scolpita: rampe al posto delle
scale di gradini, colline al posto dei gradoni, pareti di roccia ai dirupi. È
solo grafica: le regole non cambiano. Lo scolpire a mano arriva con l'editor
(Fase 6).

### Come funziona oggi

- **Dati:** un'altezza `u8` per casella, in gradini
  (`src/level/level.odin:31-44`). Un gradino è disegnato alto 0,12
  (`src/game/height.odin:26`).
- **Pavimento delle spedizioni:**
  - un piano a quota −0,01 più le terrazze, nello stesso programma
    (`src/render/expedition_floor.odin`, `src/render/expedition_terrain.odin`);
  - una texture con un texel per casella e tutti i 32 bit occupati (tipo, muri
    vicini, terreno, superficie dei luoghi, bordi del vuoto:
    `src/render/expedition_floor_data.odin:9-15`), letta con
    `floor(worldPosition.xz)` (`expedition_floor.odin:121`);
  - lo shader distingue cima e fianco con `normal.y < .5` e disegna le righe
    dei gradini con `.12` scritto a mano (`expedition_floor.odin:112`); la
    variante «alta», con la finestra tonda del robot, si accende vicino a una
    montagna di 16 gradini o più (`TERRACE_REVEAL`, `:409`;
    `EXPEDITION_TERRAIN_TALL`, `expedition_terrain.odin:31`).
- **Terrazze:** blocchi di 8×8 caselle (`build_terrain_chunk`,
  `src/render/expedition_terrain.odin:57`): una cima piatta per casella
  rialzata e un fianco verticale verso ogni vicina più bassa, con normali
  dritte. I vertici passano ogni fotogramma in modalità immediata (`:128-134`)
  e tutti i blocchi si ricostruiscono quando cambia la geometria.
- **Laboratorio:** ogni casella è una colonna scura più una lastra, fatte di
  cubi (`draw_tactical_tile`, `src/render/diorama_scene.odin:156`), con le
  righe dei gradini (`draw_height_steps`, `src/render/height_view.odin:109`).
- **Personaggi:** su `point_ground`, la media delle quattro caselle attorno
  (`src/render/height_view.odin:65`).
- **Mouse:** `pick_ground_cell` avanza lungo il raggio a passi di 0,04 e prende
  la prima casella che il raggio raggiunge (`height_view.odin:78`); a ogni
  chiamata scorre tutta la mappa per trovare l'altezza massima.
- **Ombre e riflessi:** le ombre a contatto stanno a quota fissa e sbiadiscono
  sulle caselle alte (`src/render/expedition_shadows.odin`); il riflesso
  specchia solo l'architettura, a quota 0 (`src/render/expedition_post.odin`).

### Progetto

- **La superficie** della sezione 2.3, in una funzione pura usata da
  laboratorio e spedizioni.
- **Spedizioni:** i blocchi 8×8 si costruiscono con la superficie. La mesh
  serve solo vicino a un cambio di quota: le zone piatte restano sul piano di
  oggi, quindi un bioma piatto non costa nulla in più.
- **Dirupi:** pareti di roccia sfaccettate, con qualche irregolarità sotto lo
  spigolo, mai sopra, dove si cammina.
- **Bordo al neon** in cima ai dirupi, se l'utente lo vuole.
- **Personaggi, mouse e ombre** sulla superficie nuova: `point_ground` legge i
  triangoli, il mouse li colpisce, le ombre a contatto seguono il terreno.
- **Le regole non cambiano:** `src/game/height.odin` non si tocca.
- **L'ologramma** resta com'è (bande di quota e curve di livello).

### Da chiedere prima di iniziare

1. **Dove.**
   - (Consigliato) Laboratorio e spedizioni nella stessa fase: le regole non
     cambiano.
   - Oppure solo il laboratorio, con le spedizioni in una fase a parte.
2. **Aspetto delle salite.**
   - (Consigliato) Facce piatte, low-poly come il resto del mondo.
   - Oppure facce smussate.
3. **Pareti dei dirupi.**
   - (Consigliato) Roccia sfaccettata, un po' irregolare.
   - Oppure dritte come oggi.
4. **Bordo al neon in cima ai dirupi.**
   - (Consigliato) Sì, tenue, del colore del bioma.
   - Oppure no.
5. **Righe dei gradini sui fianchi.**
   - (Consigliato) Restano: aiutano a contare i gradini.
   - Oppure via.
6. **Obiettivo di prestazioni.**
   - (Consigliato) Al massimo +5% di media sugli stage della Fase 0, nessuno
     stage oltre +10%.
   - Oppure un altro.

### Passi

1. Funzione pura della superficie (centro, angoli, spigoli dei dirupi), con
   test.
2. Laboratorio: caselle disegnate con la superficie; personaggi, mouse e ombre
   sui triangoli.
3. Spedizioni: blocchi 8×8 con la superficie, piano solo dove è piatto,
   shader con cime in pendenza e pareti di roccia.
4. Bordo al neon dei dirupi, se scelto.
5. Benchmark prima e dopo, con i risultati nell'esito.
6. Catture: arene «Altezze» e «Montagna» del laboratorio; Egitto (dune),
   Vietnam (terrazze), Neve (montagna) e Cielo (ponti in pendenza) nelle
   spedizioni.
7. Documenti: `docs/presentazione.md`, `docs/direzione-implementazione.md`
   (rilievi), `CHANGELOG.md`.

### Test

- Una fila di gradini diventa una rampa continua; un dirupo resta uno spigolo
  con la parete.
- Il centro di ogni casella sta esattamente alla sua altezza.
- `point_ground` al centro di una casella dà la sua altezza, e sulle rampe non
  salta.
- Il mouse sceglie la casella giusta su una rampa e sul bordo di un dirupo.
- Su una mappa piatta non si costruisce nessuna mesh in più.
- I test esistenti passano senza modifiche.

### Fatto quando

- Nel laboratorio e nelle spedizioni le salite sono rampe e colline, i dirupi
  sono roccia.
- Robot e nemici camminano sulla superficie che si vede.
- Le prestazioni rispettano l'obiettivo.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 1 di docs/piano-profondita.md (Terreno scolpito). Segui le
regole della sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

Da fare.

## 5. Fase 2 — Posizioni con il piano

### Cosa si fa

Ogni posizione riceve un terzo numero, il piano. Tutto resta a «terra», quindi
il gioco non cambia in nulla: è il lavoro di base che serve a tutte le fasi
dopo.

### Come funziona oggi

- `grid.Position` ha due campi, `x` e `y` (`src/engine/grid/grid.odin:5-7`).
  `Grid(T)` tiene le caselle riga per riga: indice = y × larghezza + x.
- La usano i pacchetti `game`, `render`, `expedition`, `devtools`, `level`,
  `run`, `integration`, `combatdebug`, `application` e la mappa a tessere 2D
  di `engine/physics`. Non la usano minigiochi, `campaign` e `hubworld`.
- **Posizioni scritte nel codice** (conteggio approssimato con grep, 25
  ottobre 2026):
  - nel codice del gioco circa 290 `grid.Position{a, b}` e circa 650 `{a, b}`
    senza tipo; quelle scritte con i nomi (`{x = …, y = …}`) sono una
    cinquantina;
  - nei test molte di più: solo in `game` circa 240 con il tipo e oltre mille
    senza.
- **Prova fatta il 25 ottobre 2026** con il compilatore del progetto: se la
  struct riceve un terzo campo, ogni posizione scritta con due valori diventa
  un errore («Too few values in structure literal, expected 3, got 2»), mentre
  quelle scritte con i nomi restano valide e il campo nuovo vale 0. Il
  compilatore trova quindi ogni punto da aggiornare: nessuno si salta in
  silenzio.
- Le posizioni si confrontano con `==` (una settantina di confronti in
  `game`). Nessuna mappa usa una posizione come chiave.
- **Indici calcolati a mano** (`y*w + x`): in `src/level/structure.odin` (8
  punti), `src/expedition/relief.odin` (6), `src/game/enemy_tactical_ai.odin`
  e `src/expedition/patrol_lure.odin`.
- **Tabelle per casella:** tipi, altezze e strutture in `level.Level`
  (`src/level/level.odin:22-41`); le distanze dei nemici e le pozze in
  `game.Room` (`src/game/room.odin:206`, `:513-514`).
- **Chi sta su una casella** si cerca scorrendo le liste: non c'è una griglia
  di occupazione (`enemy_index_at`, `src/game/room.odin:427`;
  `object_index_at`, `:336`).
- **Salvataggi:** nel JSON una posizione è un oggetto con `x` e `y`
  (`src/expedition/snapshot.odin:11`); una chiave che manca vale 0.

### Progetto

- `grid.Position` riceve `layer: i8`: −1 sotto, 0 terra, +1 sopra.
- **Nessuno scambio silenzioso:** le `grid.Grid` di oggi sono griglie di un
  solo piano, e `contains` e `index_of` rifiutano ogni posizione con
  `layer != 0`. Il codice che non sa ancora dei piani tratta una casella di un
  altro piano come fuori mappa, mai come la casella della terra con le stesse
  x e y.
- **Riscrittura delle posizioni**, guidata dal compilatore:
  - un piccolo programma nella scratchpad legge gli errori «Too few values» e
    riscrive ogni posizione nella forma con i nomi;
  - quando una posizione è la vicina di un'altra (`{p.x+1, p.y}`), diventa
    `grid.offset(p, 1, 0)`, che conserva il piano: nessun piano si perde
    calcolando una vicina;
  - i casi dubbi si guardano a mano.
- **Indici a mano:** passano da una funzione sola, che rifiuta gli altri
  piani.
- **Salvataggi:** il campo nuovo entra nel JSON delle posizioni; nei
  salvataggi vecchi manca e vale 0. Nessuna migrazione.
- **Le regole non cambiano.**

### Da chiedere prima di iniziare

1. **Valori del piano.**
   - (Consigliato) −1 sotto, 0 terra, +1 sopra: la terra resta lo zero di
     oggi.
   - Oppure 0, 1, 2.
2. **Forma delle posizioni riscritte.**
   - (Consigliato) Con i nomi, `{x = a, y = b}`, più `grid.offset` per le
     vicine.
   - Oppure tre valori, `{a, b, 0}`.
3. **Quanti piani al massimo.**
   - (Consigliato) Tre.
   - Oppure quattro, con due piani sotto terra.

### Passi

1. Campo `layer`, `contains` e `index_of` a un piano, `grid.offset`, con test
   in `src/engine/grid`.
2. Riscrittura, un pacchetto alla volta, con `odin check` dopo ognuno.
3. Indici a mano controllati uno per uno.
4. Salvataggi: andata e ritorno con il campo nuovo, e un salvataggio vecchio
   senza.
5. Suite completa e smoke: tutto identico.
6. Documenti: `docs/engine.md` (la griglia), `docs/architettura.md`,
   `CHANGELOG.md`.

### Test

- `contains` e `index_of` rifiutano una posizione di un altro piano.
- `grid.offset` conserva il piano.
- Un salvataggio vecchio si carica con tutto a «terra».
- La suite passa: i test cambiano solo nel modo di scrivere le posizioni, mai
  nei valori attesi.

### Fatto quando

- Ogni posizione ha il suo piano, e il gioco è identico: smoke del
  laboratorio e delle spedizioni con le stesse catture di prima.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 2 di docs/piano-profondita.md (Posizioni con il piano). Segui
le regole della sezione 1: fammi prima le domande della fase e fermati alla
fine.
```

### Esito

Da fare.

## 6. Fase 3 — Piani nel laboratorio: dati e regole

### Cosa si fa

La mappa riceve i piani sotto e sopra, e tutte le regole imparano a passare
dall'uno all'altro (sezione 2.5). Si prova in un'arena nuova della Prova
meccaniche. La grafica vera dei piani è la Fase 4: qui basta un disegno
semplice per giocare l'arena.

### Come funziona oggi

- **Movimento:** una sola pipeline. `query_entity_movement`
  (`src/game/movement.odin:130`) chiama `query_movement_from` (`:167`), che
  usa `movement_path_blocker` (`:102`); poi `apply_movement_effect` (`:270`)
  sposta, fa cadere e chiama `trigger_cell_entry` (`:325`). La usano spinte,
  tirate, scatti, le spinte dei nemici e le carte speciali (Buco Nero,
  Inondazione, Lazzo, Pinball, gravità, vento…).
- **Passo del giocatore:** `try_move_player` (`src/game/room.odin:830`), la
  diagonale (`src/game/tactical_beat.odin:175-214`), la schivata
  (`src/game/tactical_dodge.odin:26-39`).
- **Passo dei nemici:** `planned_cell_is_available`
  (`src/game/enemy_intent.odin:108`) ed `enemy_can_move_to`
  (`src/game/room.odin:811`).
- **Altezze:** passo, dirupo, caduta, vista e gittata stanno in
  `src/game/height.odin`.
- **Vista:** linee di Bresenham (`trace_targeting_line`,
  `src/game/targeting.odin:207`, al massimo 12 caselle;
  `tactical_line_visible`, `src/game/tactical.odin:379`). Bloccano muri,
  vuoto, ostacoli e blocchi di ghiaccio (`cell_blocks_line_of_sight`,
  `src/game/room.odin:384`); il terreno blocca con `height_hides`
  (`src/game/height.odin:53`), copiato in `line_hidden_by_height`
  (`src/game/tactical.odin:411`). La usano anche l'arciere, il bombarolo, le
  bobine e l'avvistamento delle spedizioni (`can_see`,
  `src/expedition/world.odin:247`).
- **Carte:** gittata Manhattan o Chebyshev (`src/game/targeting.odin:86-103`)
  con il bonus d'altura (`:487`). Le aree sono scostamenti dall'ancora
  (`build_target_shape`, `:364`): singola, linea, croce, quadrato. Hanno aree
  proprie le esplosioni (3×3, senza controllo della vista:
  `src/game/enemy_tactical_ai.odin`), l'onda tossica, il fulmine a catena e
  l'Inondazione.
- **IA:** campo delle distanze con Dijkstra a 4 vicine, dove i dirupi tagliano
  i collegamenti (`rebuild_tactical_enemy_distances`,
  `src/game/enemy_tactical_ai.odin:127`).
- **Laboratorio:** arene `Flat, Heights, Structures, Mountain, Cave`
  (`src/run/mechanics_practice.odin:35`), che F3 scorre. Un'arena nuova vuole
  l'enum, la misura (`mechanics_lab_size`, `:52`), le righe a caratteri
  (`mechanics_lab_level`, `:76`, al massimo 29 righe) e i punti di partenza
  (`create_mechanics_lab_room`, `:134`). Gli atti dello smoke sono in
  `src/devtools/mechanics_lab.odin`.

### Progetto

- **Dati:** `level.Level` riceve i piani sotto e sopra (tipi e altezze), vuoti
  finché non servono; la terra resta quella di oggi. `tile_at` e `height_at`
  scelgono il piano dalla posizione. Cambiare un piano alza
  `geometry_revision`.
- **Controllo della colonna:** due caselle calpestabili della stessa colonna
  distano almeno luce + spessore; una mappa che non lo rispetta è rifiutata,
  con un test.
- **Regole** della sezione 2.5, in tutti i punti elencati sopra:
  - passo, diagonale, schivata e passo dei nemici;
  - scale a pioli e ascensori, se scelti;
  - spinte e cadute fra piani, nella pipeline degli spostamenti;
  - vista fra piani in tutti i punti che la usano, compresa la copia del
    renderer;
  - aree e mischia;
  - campo delle distanze dei nemici attraverso i piani.
- **Carte speciali**, controllate una per una all'inizio della fase:
  Inondazione, Buco Nero, Lazzo, Pinball, Dinosauro, Cannone e Cannone laser,
  Bomb Marley, First Person Shooter. La regola base: agiscono sul piano di chi
  le gioca e su ciò che vede.
- **Disegno semplice:** ogni piano alla sua quota; quando il robot è sotto, ciò
  che lo copre è mezzo trasparente. Il mouse colpisce la superficie più vicina
  lungo il raggio. Il resto è la Fase 4.
- **Arena «Piani»** (sesta di F3):
  - una strada con sopra un ponte e due rampe;
  - una collina con dentro una grotta e due imbocchi;
  - una scala a pioli e un pozzo con l'ascensore che scende nella grotta, se
    l'utente li vuole;
  - nemici su tutti i piani.

### Da chiedere prima di iniziare

1. **Luce sopra una casella** (lo spazio per un personaggio).
   - (Consigliato) 10 gradini, cioè 1,2 caselle.
   - Oppure un altro valore.
2. **Spessore di ponti e volte.**
   - (Consigliato) 2 gradini.
   - Oppure un altro valore.
3. **Scale a pioli e ascensori.**
   - (Consigliato) Sì, tutti e due nell'arena: collegano piani anche dove non
     c'è una rampa (l'ascensore è il pozzo di Elden Ring, sezione 2.9).
   - Oppure solo uno dei due (quale).
   - Oppure no: solo rampe e imbocchi.
4. **Tiri fra piani.**
   - (Consigliato) Sì, in tutte e due le direzioni, se la linea è libera.
   - Oppure solo dall'alto in basso.
5. **Aree fra piani.**
   - (Consigliato) Come nella sezione 2.5: il piano dell'ancora, e dove manca
     la casella più vicina entro 2 gradini.
   - Oppure solo il piano dell'ancora.
6. **Bordo dei ponti.**
   - (Consigliato) Aperto: una spinta fa cadere sul piano sotto, con il danno
     di oggi.
   - Oppure un parapetto che ferma le spinte.
7. **Mischia.**
   - (Consigliato) Fra piani diversi solo agli imbocchi; sullo stesso piano
     come oggi.
   - Oppure ovunque solo fra caselle a un gradino al massimo, anche sui dirupi
     di oggi.

### Passi

1. Dati dei piani e controllo della colonna, con test in `level`.
2. Passo, diagonale, schivata e passo dei nemici; spinte e cadute fra piani.
3. Vista fra piani in tutti i punti che la usano, con test.
4. Aree, mischia e carte speciali.
5. IA: campo delle distanze attraverso i piani.
6. Disegno semplice e mouse.
7. Arena «Piani» e atto dello smoke (`ODIN_PP_LAB_ONLY=layers`), con
   catture: salire sul ponte, passarci sotto, entrare in grotta, scendere con
   l'ascensore, tiro dal ponte, spinta giù dal ponte.
8. Documenti: `docs/regole/combattimento.md` (i piani), `docs/avvio.md`
   (l'arena), `CHANGELOG.md`.

### Test

- Dal ponte alla strada sotto non si scende camminando; dalle rampe sì.
- Sotto il ponte si cammina e si combatte; due personaggi stanno sulla stessa
  x,y a piani diversi.
- Una spinta giù dal ponte fa cadere sulla strada, con il danno giusto.
- Dal ponte si vede e si colpisce la strada; dalla collina non si vede dentro
  la grotta.
- I nemici trovano la strada per la grotta e per il ponte.
- Scala e ascensore portano da un piano all'altro, il robot e i nemici.
- Una colonna con due caselle troppo vicine viene rifiutata.
- Con un piano solo il comportamento è identico: la suite passa senza toccare
  i test esistenti.

### Fatto quando

- Nell'arena «Piani» il robot sale sul ponte, ci passa sotto ed entra nella
  grotta camminando, e i nemici fanno lo stesso.
- Vista, tiri, aree e cadute fra piani seguono le regole scelte.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 3 di docs/piano-profondita.md (Piani nel laboratorio: dati e
regole). Segui le regole della sezione 1: fammi prima le domande della fase e
fermati alla fine.
```

### Esito

Da fare.

## 7. Fase 4 — Piani nel laboratorio: grafica

### Cosa si fa

I piani si leggono a schermo: ciò che copre il robot si dirada, chi è nascosto
ha un contorno, il mouse sceglie il piano giusto, sotto terra la luce cambia.
Tutto nel laboratorio; le spedizioni lo riusano nella Fase 5.

### Come funziona oggi

- **Trasparenza degli edifici** (Fase 6 del piano della griglia): una regola
  pura, `structure_visibility` (`src/game/structure_view.odin:51`). Da 5
  caselle l'edificio si dirada, sulla soglia sparisce, dentro i muri tornano
  interi e il tetto sparisce. Nel laboratorio i solidi hanno un'alfa per
  vertice e vanno nel passaggio traslucido ordinato
  (`src/render/structure_diorama.odin`,
  `src/render/tactical_translucency.odin`); nelle spedizioni c'è un retino
  4×4 nel programma «reveal» (`src/render/expedition_material.odin`,
  `src/render/structure_expedition.odin`).
- **Personaggi dietro il terreno:** `terrain_hides_actor`
  (`src/render/height_view.odin:137`) e la finestra tonda col bordo, solo per
  il robot e solo nelle spedizioni. Nel laboratorio non ci sono.
- **Mouse:** `pick_ground_cell` dà una casella, e personaggi e oggetti hanno
  la precedenza (`src/render/tactical_renderer.odin`).
- **Luci delle spedizioni:** fino a 32 luci a capsula, senza occlusione, con
  una maschera per zone solo in x e z (`src/render/expedition_lighting.odin`):
  oggi una luce sopra una grotta illuminerebbe anche il suo pavimento.

### Progetto

- **Cosa si dirada:** una regola pura, come `structure_visibility`. Ciò che
  sta sopra la testa del robot, entro un raggio, si dirada; quando il robot è
  sotto una volta, il fuori si scurisce come fuori da un edificio.
- **Contorni** per i personaggi nascosti sotto un ponte o dietro la roccia, del
  loro colore.
- **Mouse** sui piani visibili: il raggio salta ciò che è diradato.
- **Luce** più scura sotto terra, con le luci dei personaggi; ogni luce
  illumina solo il suo piano e quelli che vede.
- **Telecamera** che segue morbida la quota del robot quando cambia piano.
- **Ombre a contatto** sul piano di chi le fa.

### Da chiedere prima di iniziare

1. **Cosa si dirada sopra il robot.**
   - (Consigliato) Ciò che sta sopra la sua testa entro 6 caselle, con
     un'apertura graduale come gli edifici.
   - Oppure l'intero piano sopra di lui.
2. **Personaggi nascosti.**
   - (Consigliato) Un contorno del loro colore.
   - Oppure una finestra tonda, come quella del robot sulla montagna.
3. **Luce sotto terra.**
   - (Consigliato) Più scura, con le luci dei personaggi.
   - Oppure come fuori.
4. **Ciò che sta sotto il robot quando è sul ponte.**
   - (Consigliato) Si vede normalmente.
   - Oppure un po' più scuro, per dare profondità.

### Passi

1. Regola pura di ciò che si dirada, con test.
2. Diradamento e scurimento nel laboratorio.
3. Contorni dei personaggi nascosti.
4. Mouse sui piani visibili, con il test della funzione pura.
5. Luce sotto terra, telecamera e ombre.
6. Atto dello smoke con le catture: robot dentro la grotta, robot sotto il
   ponte con un nemico sopra, robot sul ponte con un nemico sotto, mouse su
   una casella sotto il ponte.
7. Documenti: `docs/presentazione.md`, `CHANGELOG.md`.

### Test

- La regola dirada ciò che sta sopra il robot e niente di ciò che sta sotto o
  lontano.
- Il mouse sceglie la casella sotto il ponte quando il ponte è diradato, e il
  ponte quando non lo è.
- I personaggi nascosti hanno il contorno, quelli visibili no.

### Fatto quando

- Nell'arena «Piani» si vede sempre dove sono il robot e i nemici, su
  qualunque piano.
- Il mouse sceglie la casella giusta su ogni piano.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 4 di docs/piano-profondita.md (Piani nel laboratorio: grafica).
Segui le regole della sezione 1: fammi prima le domande della fase e fermati
alla fine.
```

### Esito

Da fare.

## 8. Fase 5 — Piani nelle spedizioni: grotte senza caricamento

### Cosa si fa

Le grotte di oggi diventano il piano sotto di un massiccio di roccia: ci si
entra camminando dall'imbocco, senza dissolvenza e senza cambiare mappa. Per
farlo i piani entrano nel renderer delle spedizioni, nei salvataggi,
nell'esplorazione e nelle pattuglie.

### Come funziona oggi

- **Generatore:** `generate` (`src/expedition/world.odin:154`) costruisce, in
  ordine, tessere e luoghi, rilievi, montagna, strutture, grotte e abitanti.
  La geografia è una funzione pura del bioma; il seme sceglie solo nemici,
  bottino e luoghi attivi.
- **Posti delle grotte:** tre fissi per bioma, in Neve, Far West, Egitto e
  Inferno (`cave_candidates`, `src/expedition/cave.odin:180`); la run ne
  sceglie da una a tre (`place_caves`, `:201`). Nella Neve la prima è sempre
  sul sentiero della montagna, a metà salita.
- **La grotta:** un piano di 34×18 caselle, con due o tre stanze in fila e il
  segreto in fondo (`cave_plan`, `src/level/cave.odin`).
- **Entrare e uscire:**
  - **E** vicino all'arco (`src/run/expedition_scene.odin:301`) avvia la
    dissolvenza (`expedition_cave_fade`, `:521`), che ferma il mondo;
  - al nero, `enter_cave` (`src/expedition/cave.odin:221`) mette da parte tipi
    e altezze della mappa aperta in un `Outer_Map` (`:31`), svuota la mappa e
    stampa la grotta al centro; `exit_cave` (`:245`) rimette tutto com'era;
  - non si entra né si esce durante uno scontro.
- **In grotta:** luoghi spenti; gruppi e oggetti a terra filtrati con
  `in_scope` (`cave.odin:53`); bioma 255, quindi niente terreni e niente
  corsia; niente ologramma, mount e posa di strutture.
- **Salvataggi:** lo `Snapshot` (`src/expedition/snapshot.odin:11`) ha
  tabelle `[MAX_CELLS]` per tipi, altezze, ostacoli e pozze, più `outer` per
  le grotte. `valid_snapshot` (`:94`) accetta i tipi di casella fino a
  `.Fence`. Non c'è codice di migrazione: una chiave che manca vale zero. La
  decodifica JSON vuole circa 6 MB di stack (sezione 1.5).
- **Esplorazione:** il robot ha una posizione continua e un cerchio di 0,3 che
  si ferma sulle caselle bloccate (`roam_blocked` e `roam_resolve`,
  `src/expedition/roam.odin:50`, `:58`). Il mount segue le stesse regole.
- **Pattuglie:** ricerca in ampiezza su una finestra di 65×65
  (`patrol_move_toward`, `src/expedition/patrol_lure.odin:47-89`);
  avvistamento con `can_see` (`src/expedition/world.odin:247`).
- **Renderer:** quello della Fase 1. La texture del pavimento si legge con le
  sole x e z, quindi due superfici una sopra l'altra avrebbero lo stesso tipo
  di casella; le luci non hanno occlusione; il programma «reveal» lavora sopra
  la quota assoluta 0,1.
- **Smoke:** gli stage delle grotte (dall'87) entrano, escono e controllano
  che la mappa torni identica (`src/application/campaign_smoke.odin:535-548`).

### Progetto

- **Generatore:** a ogni posto di grotta un massiccio di roccia sulla terra, e
  dentro, sul piano sotto, la grotta di oggi (`cave_plan`) a livello del
  terreno attorno. L'arco diventa l'imbocco. Nella Neve la grotta entra nella
  montagna dal sentiero; se il nucleo della montagna è troppo piccolo per
  34×18, la grotta della Neve è più piccola (si misura all'inizio della fase).
- **In grotta:** gruppi e oggetti della grotta stanno semplicemente sul piano
  sotto, e la mappa fuori resta com'è. Spariscono `Outer_Map`, la dissolvenza
  e il bioma 255.
- **Renderer delle spedizioni:** una texture del pavimento per piano; blocchi
  della superficie per piano; diradamento della roccia sopra il robot con il
  retino del programma «reveal»; contorni; luci e ombre per piano. Le regole
  pure della Fase 4 si riusano.
- **Esplorazione, mount, pattuglie e avvistamento** con le regole fra piani.
- **Salvataggi:**
  - i piani sotto e sopra si salvano come una lista delle sole caselle che
    esistono (indice, tipo, altezza): quei piani sono quasi vuoti, quindi lo
    snapshot cresce poco e lo stack della decodifica non aumenta come farebbe
    con altre tabelle `[MAX_CELLS]`;
  - le posizioni hanno il piano (Fase 2);
  - un salvataggio vecchio senza piani si carica com'era.
- **Ologramma a piani, già qui** (la lezione del DLC di Elden Ring, sezione
  2.9): si apre anche in grotta, mostra pieno il piano del robot e ha un tasto
  per guardare l'altro; gli imbocchi scoperti sono segnati, quelli segreti
  restano nascosti finché non li si scopre. La Fase 8 lo completa.
- **Prestazioni:** benchmark sugli stage della Fase 0, prima e dopo.

### Da chiedere prima di iniziare

1. **Quali grotte.**
   - (Consigliato) Tutte quelle di oggi: Neve, Far West, Egitto e Inferno,
     negli stessi posti.
   - Oppure solo la Neve per ora.
2. **Grandezza.**
   - (Consigliato) Le stanze di oggi (34×18), dentro un massiccio di roccia.
   - Oppure grotte più piccole.
3. **Salvataggi presi dentro una grotta vecchia.**
   - (Consigliato) Si riaprono con il robot davanti all'imbocco, e nemici e
     segreto della grotta al loro posto, sotto.
   - Oppure si riaprono con il robot dentro la grotta nuova.
4. **Scontri sull'imbocco.**
   - (Consigliato) Si combatte anche a cavallo dell'imbocco: entrare è solo
     camminare.
   - Oppure, come oggi, niente ingresso durante uno scontro.
5. **Pattuglie che inseguono.**
   - (Consigliato) Entrano anche in grotta, come ovunque.
   - Oppure la grotta è un rifugio.
6. **Mount in grotta.**
   - (Consigliato) No, come oggi.
   - Oppure sì.
7. **Obiettivo di prestazioni.**
   - (Consigliato) Al massimo +5% di media rispetto alla fine della Fase 1.
   - Oppure un altro.
8. **Ologramma.**
   - (Consigliato) Il piano del robot pieno, un tasto per guardare l'altro,
     gli imbocchi scoperti segnati.
   - Oppure cambia piano da solo, quando lo cambia il robot, senza tasto.

### Passi

1. Generatore: massicci e grotte sul piano sotto, con i test di geografia
   fissa e di raggiungibilità estesi ai piani.
2. Salvataggi: piani come liste, posizioni con il piano, conversione dei
   salvataggi presi in grotta, con test di andata e ritorno.
3. Esplorazione, mount, pattuglie e avvistamento fra piani.
4. Renderer delle spedizioni: texture e superfici per piano, diradamento,
   contorni, luci, ombre.
5. Ologramma a piani, con il tasto e gli imbocchi segnati.
6. Smoke delle grotte rifatto (entrare e uscire camminando) e catture in tutti
   e quattro i biomi, con il pulsante «TEST tutti i biomi».
7. Benchmark prima e dopo.
8. Documenti: `docs/direzione-implementazione.md` (grotte),
   `docs/regole/combattimento.md`, `CHANGELOG.md`.

### Test

- La geografia, piani compresi, è uguale con semi diversi; ogni luogo e ogni
  grotta si raggiunge camminando.
- Si entra e si esce dalla grotta camminando; il mount si comporta come deciso
  alla domanda 6.
- Un checkpoint preso in grotta si riapre in grotta; un salvataggio vecchio
  preso in grotta si apre come deciso alla domanda 3.
- Le pattuglie seguono le regole scelte.

### Fatto quando

- In ognuno dei quattro biomi si entra in grotta camminando, senza nero, e se
  ne esce dallo stesso imbocco.
- Salvataggi nuovi e vecchi si caricano.
- Le prestazioni rispettano l'obiettivo.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 5 di docs/piano-profondita.md (Piani nelle spedizioni: grotte
senza caricamento). Segui le regole della sezione 1: fammi prima le domande
della fase e fermati alla fine.
```

### Esito

Da fare.

## 9. Fase 6 — Editor per scolpire

### Cosa si fa

Uno strumento per modellare la mappa a mano: alzare, abbassare, levigare,
dipingere il calpestabile, piano per piano. Serve per le arene del laboratorio
e per ritoccare le mappe dei biomi, che la Fase 7 userà.

### Come funziona oggi

- La geografia delle spedizioni è tutta codice: rilievi
  (`src/expedition/relief.odin`), montagna, luoghi e strutture sono funzioni
  pure del bioma.
- Le uniche mappe scritte a mano sono le arene del laboratorio, a caratteri
  (`mechanics_lab_level`, `src/run/mechanics_practice.odin:76`), con le
  altezze in righe di cifre (`apply_height_rows`,
  `src/level/level.odin:203`).
- La geografia fissa è controllata dai test, per esempio
  `test_expedition_geography_is_seed_independent_and_all_sites_reachable`
  (`src/expedition/world_test.odin`).

### Progetto

- **Editor nella Prova meccaniche:**
  - piano attivo (sotto, terra, sopra);
  - pennelli: alza e abbassa di un gradino, leviga, appiattisci, dipingi il
    tipo di casella (pavimento, roccia, vuoto, recinto);
  - grandezza del pennello, annulla e ripeti, salva;
  - una telecamera che ruota e fa zoom, solo nell'editor: le spedizioni
    restano a telecamera fissa.
- **Mappe dei biomi:** l'editor apre la mappa generata di un bioma e salva i
  ritocchi in un file del bioma, in `assets/mappe/`. `generate` li applica
  dopo rilievi e montagna; luoghi, strutture e abitanti vengono dopo, come
  oggi. Il file fa parte del bioma, non della run: la geografia resta fissa.
- **Controlli al salvataggio:** ogni luogo raggiungibile, colonne valide, zone
  dei luoghi e partenza in piano. Gli errori si vedono in rosso.
- **Fuori dal gioco:** i ritocchi si possono esportare e reimportare come
  immagini (altezze in grigio, tipi a colori), per dipingerli con qualunque
  programma.

### Da chiedere prima di iniziare

1. **Dove.**
   - (Consigliato) Nella Prova meccaniche, con un tasto libero.
   - Oppure un programma a parte (`--editor-mappe`).
2. **Formato dei ritocchi.**
   - (Consigliato) Immagini PNG, una per piano: si dipingono anche fuori dal
     gioco.
   - Oppure JSON.
3. **Angoli scolpibili uno per uno.**
   - (Consigliato) No: si scolpiscono le caselle e gli angoli si ricavano
     (sezione 2.3), così ciò che si vede resta ciò che conta.
   - Oppure sì, con più dettaglio ma regole più complicate.
4. **Pennelli in più.**
   - (Consigliato) Quelli del progetto, per cominciare.
   - Oppure altri (quali).

### Passi

1. Pennelli e piano attivo nel laboratorio, con test delle funzioni pure.
2. Annulla, ripeti e salvataggio delle arene.
3. Mappe dei biomi: apertura, ritocchi, file, applicazione in `generate`.
4. Controlli al salvataggio.
5. Esporta e importa come immagini.
6. Atto dello smoke: una collina alzata, levigata e salvata, poi riaperta.
7. Documenti: `docs/avvio.md` (come si usa l'editor), `CHANGELOG.md`.

### Fatto quando

- Si scolpisce un'arena e si ritocca la mappa di un bioma; i ritocchi restano
  dopo il riavvio e la geografia resta fissa.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 6 di docs/piano-profondita.md (Editor per scolpire). Segui le
regole della sezione 1: fammi prima le domande della fase e fermati alla fine.
```

### Esito

Da fare.

## 10. Fase 7 — Ponti, gallerie e scorciatoie nei biomi

### Cosa si fa

La mappa diventa interconnessa: ponti sopra le strade, gallerie sotto i muri,
grotte con più imbocchi, scorciatoie. Ogni bioma riceve i suoi piani, sempre
con la geografia fissa.

### Come funziona oggi

- **Cielo:** isole di 21×21 a quote diverse, unite da ponti in pendenza larghi
  5 caselle; il resto degli spazi fra le isole è vuoto
  (`src/expedition/relief.odin`, `src/expedition/world.odin:167-169`). Il
  terreno «ponte» si chiude a tempo (`src/game/room.odin:308-314`). Sotto i
  ponti non passa niente.
- **Vietnam:** il tunnel è un luogo che con **E** teletrasporta il robot una
  volta sola (`tunnel_destination`, `src/expedition/world.odin:527`).
- **Altopiani** solo in Robotica cibernetica, Far West, City pop, Neve e
  Inferno (`src/expedition/relief.odin`).
- **Direzione del gioco:** nell'Antico Egitto le tombe sono «POI
  sotterranei» ([direzione.md](../direzione.md), scheda del bioma).
- **Segreti ricordati:** la campagna ricorda per ogni bioma fino a 64 segreti
  scoperti (`Campaign.secrets` e `discover_secret`,
  `src/campaign/campaign.odin:40`, `:103`). Una scorciatoia aperta si può
  ricordare allo stesso modo.
- Dopo la Fase 5 ci sono le grotte a piani in quattro biomi.

### Progetto

**Proposta di temi**, da confermare bioma per bioma:

| Bioma | Sotto | Sopra |
|---|---|---|
| Robotica cibernetica | condotti sotto le piattaforme dati | passerelle tra le piattaforme |
| Far West | la miniera (la grotta di oggi) | il ponte del treno sopra il canyon |
| Giungla preistorica | caverne delle ossa | ponti di liane tra gli alberi |
| City pop | metropolitana | cavalcavia e tetti |
| Antico Egitto | tombe sotto le piramidi | terrazze delle piramidi |
| Vietnam | gallerie: il tunnel diventa una galleria vera | ponti di bambù |
| Montagne innevate | la grotta dentro la montagna | ponte di corda sul crepaccio |
| Inferno | caverne di lava | ponti di ossa sopra la lava |
| Southern gothic | cripta sotto la collina | ballatoio della casa |
| Isola nel cielo | — | i ponti fra le isole diventano ponti veri, con sotto i sentieri delle isole basse |
| Spazio | gallerie nei crateri | passerelle della stazione |
| La memoria del creatore | dentro la collina del masso | — |

- **Interconnessioni:** almeno due strade per arrivare ai luoghi importanti
  (una sopra o sotto); grotte con più imbocchi; scorciatoie che evitano un giro
  lungo.
- **Altopiani con pochi accessi** (sezione 2.9): ogni altopiano grande ha da 1
  a 3 accessi, almeno uno nascosto; il resto del bordo è dirupo. L'altopiano si
  vede da sotto, ma la strada per salirci va trovata.
- **Scorciatoie che si aprono dall'altra parte:** una porta, una leva o un
  ascensore che si sblocca solo arrivandoci dal lato giusto. Una volta aperta,
  la scorciatoia resta aperta anche nelle run dopo, come i segreti scoperti.
- **Sotterraneo grande** in alcuni biomi (Egitto, Gotico): non solo grotte
  dentro le colline, ma zone ampie sotto il suolo, raggiunte da un pozzo con
  l'ascensore, come i fiumi sotterranei di Elden Ring. Per farle, il bioma alza
  tutto il suo terreno di una base e mette il sotterraneo sotto.
- **Strumenti:** il generatore per le forme ripetute, l'editor della Fase 6
  per i ritocchi.
- **Prestazioni:** benchmark per bioma.

### Da chiedere prima di iniziare

1. **Temi.**
   - (Consigliato) Quelli della tabella.
   - Oppure altri, bioma per bioma.
2. **Ordine.**
   - (Consigliato) Tre biomi per volta, con le catture da guardare insieme.
   - Oppure tutti insieme.
3. **Scorciatoie.**
   - (Consigliato) Si aprono dall'altra parte e restano aperte nelle run dopo,
     come i segreti scoperti.
   - Oppure si aprono, ma si richiudono a ogni run.
   - Oppure fisse, sempre aperte.
4. **Il tunnel del Vietnam.**
   - (Consigliato) Diventa una galleria percorribile.
   - Oppure resta il salto di oggi.
5. **I ponti del Cielo.**
   - (Consigliato) Diventano ponti veri, con i sentieri sotto.
   - Oppure restano come oggi.
6. **Accessi agli altopiani.**
   - (Consigliato) Da 1 a 3 per altopiano, almeno uno nascosto.
   - Oppure liberi, decisi bioma per bioma.
7. **Sotterraneo grande.**
   - (Consigliato) Nell'Egitto e nel Gotico, raggiunto da un pozzo con
     l'ascensore.
   - Oppure in altri biomi (quali).
   - Oppure niente: solo grotte dentro le colline.

### Passi

1. Biomi a gruppi di tre: piani, imbocchi, accessi agli altopiani e
   scorciatoie, con test di geografia fissa, di raggiungibilità e delle
   scorciatoie ricordate dalla campagna.
2. Catture di ogni bioma (esplorazione e uno scontro fra piani), con il
   pulsante «TEST tutti i biomi».
3. Benchmark per bioma.
4. Documenti: `docs/direzione-implementazione.md` (biomi), `CHANGELOG.md`.

### Fatto quando

- Ogni bioma scelto ha i suoi piani, raggiungibili e uguali a ogni run.
- Le prestazioni restano nell'obiettivo.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 7 di docs/piano-profondita.md (Ponti, gallerie e scorciatoie
nei biomi). Segui le regole della sezione 1: fammi prima le domande della fase
e fermati alla fine.
```

### Esito

Da fare.

## 11. Fase 8 — Ologramma a piani, prestazioni e grotte vecchie

### Cosa si fa

Chiude il lavoro: l'ologramma mostra i piani, si misurano e si migliorano le
prestazioni, si toglie il codice delle grotte vecchie.

### Come funziona oggi

- **Ologramma delle spedizioni** (`src/run/expedition_hologram.odin`): una
  banda di quota per casella (`hologram_band`, `:27`), ombreggiatura e curve
  di livello, i colori dei terreni; i luoghi segreti non visitati non si
  vedono (`:40`). Si ricostruisce ogni fotogramma mentre è aperto. Oggi non si
  apre in grotta.
- **Blocchi del terreno:** i vertici passano ogni fotogramma in modalità
  immediata (`src/render/expedition_terrain.odin:128-134`); con tre piani
  conviene caricarli una volta sola sulla scheda video.
- **Grotte vecchie:** dopo la Fase 5 `Outer_Map`, `enter_cave` ed `exit_cave`
  servono solo a convertire i salvataggi vecchi.

### Progetto

- **Ologramma a piani completo:** parte da quello della Fase 5 e aggiunge il
  piano sopra, gli interni delle grotte scoperte e gli accessi degli altopiani
  già trovati.
- **Prestazioni:** blocchi del terreno caricati sulla scheda video invece che
  rimandati a ogni fotogramma; misure in tutti i biomi.
- **Pulizia:** via il codice delle grotte vecchie, se la conversione dei
  salvataggi non ne ha più bisogno.

### Da chiedere prima di iniziare

1. **Ologramma.**
   - (Consigliato) Come nella Fase 5, più il piano sopra, gli interni delle
     grotte scoperte e gli accessi trovati.
   - Oppure tutti i piani insieme, uno sopra l'altro.
2. **Codice delle grotte vecchie.**
   - (Consigliato) Via, tenendo la conversione dei salvataggi vecchi.
   - Oppure resta.
3. **Obiettivo finale di prestazioni.**
   - (Consigliato) Al massimo +10% di media rispetto alla Fase 0, in ogni
     bioma.
   - Oppure un altro.

### Passi

1. Ologramma a piani, con le catture.
2. Blocchi del terreno sulla scheda video, con il benchmark prima e dopo.
3. Pulizia del codice delle grotte vecchie, con il test dei salvataggi
   vecchi.
4. Misure finali in tutti i biomi.
5. Documenti: `docs/direzione-implementazione.md`, `docs/presentazione.md`,
   `README.md`, `CHANGELOG.md`.

### Fatto quando

- L'ologramma mostra i piani; le prestazioni rispettano l'obiettivo; il
  codice vecchio non c'è più.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 8 di docs/piano-profondita.md (Ologramma a piani, prestazioni e
grotte vecchie). Segui le regole della sezione 1: fammi prima le domande della
fase e fermati alla fine.
```

### Esito

Da fare.

## 12. Cose notate durante lo studio (da verificare)

Lo studio del codice del 25 ottobre 2026 ha notato alcune cose che sembrano
problemi già presenti. **Nessuna è stata riprodotta:** vanno controllate nella
fase indicata, prima di correggerle.

| Cosa | Dove | Fase |
|---|---|---|
| La carica del bruto controlla l'altezza solo della prima casella: se le caselle dopo salgono di due gradini, l'assert che la mossa sia accettata potrebbe fallire. | `src/game/enemy_intent.odin`, verso la riga 900 | 3 |
| La diagonale con QTE, la schivata di difesa e il passo d'ombra usano solo la regola della salita: camminando potrebbero scendere un dirupo. | `src/game/tactical.odin`, `src/game/tactical_shadow.odin` | 3 |
| Il rilassamento dei rilievi limita solo le quattro vicine dritte: due vicine in diagonale possono stare a due gradini e bloccare una diagonale dove la strada dritta va bene. | `relax`, `src/expedition/relief.odin:329` | 1 |
| I bordi degli edifici diradati non sfumano: l'alfa sembra perdersi nel disegno dei bordi. | `src/render/expedition_edges.odin` | 4 |
| Nell'ologramma delle stanze i personaggi potrebbero galleggiare sulle mappe con altezze. | `src/render/hologram.odin` | 8 |
| Il campo `covered` dei blocchi del terreno non è letto da nessuno. | `src/render/expedition_terrain.odin` | 1 |
| La sfera di taglio per casella sta a quota fissa 0,65: il piano della griglia voleva allargarla, ma non è stato fatto. | `src/render/tactical_framing.odin` | 1 |
| Entrando in grotta, trappole, oggetti, pozze, fuochi e ostacoli della stanza non vengono messi da parte. | `enter_cave`, `src/expedition/cave.odin:221` | 5 (sparisce con le grotte a piani) |
| Il benchmark non arriva a rilievi, montagna e grotte. | `src/application/campaign_smoke.odin:81-82` | 0 |

## 13. Rischi che valgono per tutte le fasi

- **Prestazioni.** I piani moltiplicano la geometria vicino al robot, e i 60
  fps costanti non sono garantiti ovunque nemmeno oggi
  (`docs/direzione-implementazione.md`, «Limiti dichiarati»). Ogni fase
  grafica misura prima e dopo.
- **Salvataggi.** Lo snapshot pesa già circa 1,4 MB e la sua decodifica vuole
  molto stack: i piani si salvano come liste (Fase 5) e ogni dato nuovo ha un
  valore predefinito.
- **Ampiezza delle Fasi 2 e 3.** Toccano quasi tutti i pacchetti:
  compilazioni e test lunghi, e conflitti probabili con il lavoro di 0xdokkan
  su `main`.
- **Geografia fissa.** Piani, massicci e ritocchi dell'editor sono uguali a
  ogni run dello stesso bioma; il test esistente va esteso ai piani.
- **Telecamera fissa.** La direzione del gioco la vuole senza rotazione né
  zoom: la leggibilità dei piani si regge su diradamento e contorni (Fase 4).
  Se non bastassero, una rotazione a scatti è una decisione dell'utente.
- **È il cambiamento più grande fatto finora.** Ogni fase lascia il gioco
  funzionante, e la regola «tutto a terra = gioco di oggi» (sezione 2.7) è la
  rete di sicurezza.
