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

La risposta discussa in chat è una **mappa a piani**: fino a quattro griglie
sovrapposte (due sotto, la terra, una sopra; erano tre, l'utente ne ha scelte
quattro nella Fase 2), ognuna con il suo terreno scolpito, e il combattimento
sempre a griglia. La sezione 2 descrive il modello; le fasi lo
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
| 0 | 0 | Misure di partenza: il benchmark arriva a rilievi, montagna e grotte (proposta di Claude) | — | Fatta | vedi Esito |
| 1 | 1 | Terreno scolpito: rampe, colline e dirupi di roccia, solo grafica | — (meglio dopo la 0) | Fatta | vedi Esito |
| 2 | 2 | Posizioni con il piano: il terzo numero, tutto a «terra» | — | Fatta | vedi Esito |
| 3 | 3 | Piani nel laboratorio: dati e regole | 2 | Fatta | vedi Esito |
| 4 | 4 | Piani nel laboratorio: trasparenze, contorni, mouse, luce | 3 (1 per l'aspetto) | Fatta | vedi Esito |
| 5 | 5 | Piani nelle spedizioni: grotte senza caricamento | 1, 3, 4 | Fatta | vedi Esito |
| 6 | 6 | Editor per scolpire i piani | 1, 3 (5 per le mappe dei biomi) | Fatta | vedi Esito |
| 7 | 7 | Ponti, gallerie e scorciatoie nei biomi | 5, 6 | In corso | — |
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
"$S/odin_pp.exe" --smoke-editor-mappe
```

- **Suite completa in un colpo** (PowerShell): `$env:ODIN` con il percorso
  del compilatore, poi `.\scripts\check.ps1`: test con e senza assert, più le
  due build.
- **Un solo atto del laboratorio:** `ODIN_PP_LAB_ONLY=<atto>` (oggi
  `hit_marks`, `heights`, `structures`, `mountain`, `cave`, `layers`, `lift`:
  `src/devtools/mechanics_lab.odin:82-97`). Ogni fase che aggiunge un atto lo
  aggiunge anche qui. A fine fase lo smoke del laboratorio va completato:
  dura circa venti minuti. L'atto `lift` (dalla Fase 7) gira per ultimo, così
  le catture di prima restano confrontabili al byte.
- **Spedizioni da un punto:** `ODIN_PP_SMOKE_ONLY=hits` parte dagli scontri
  dei segni dei colpi, `ODIN_PP_SMOKE_ONLY=caves` dalle grotte,
  `ODIN_PP_SMOKE_ONLY=complessi` dai complessi della Fase 7,
  `ODIN_PP_SMOKE_ONLY=reti` dalle reti sotterranee
  (`src/application/campaign_smoke.odin`, `expedition_enable_smoke`). Gli
  stage che contano qui: rilievi dal 63, ologrammi dal 75, due livelli 78,
  montagna 79, grotte dall'87, ologramma in grotta 103 (dalla Fase 5),
  complessi dal 104, sei per bioma, reti dal 140, tre per bioma (dalla
  Fase 7).
- **Benchmark:**
  `"$ODIN" build src -o:speed -define:EXPEDITION_BENCHMARK=true -out:"$S/bench.exe"`,
  poi `"$S/bench.exe" --smoke-expedition > "$S/bench_a.log" 2>&1`
  (`docs/direzione-implementazione.md`, «Ripetere il benchmark e leggere il
  profiler»).
  - Dalla Fase 0 misura tutti gli stage, 0–102, in circa 22 secondi, su un
    canvas fisso di 1920×1080. Per una parte sola:
    `-define:EXPEDITION_BENCHMARK_FIRST=63 -define:EXPEDITION_BENCHMARK_LAST=98`.
  - Si misura due volte, sulla RTX 3060 (la riga `Renderer:` del log lo
    conferma), con il portatile alla corrente, e si confrontano le medie dei
    gruppi con quelle della Fase 0 (appendice A). Sul singolo stage, una
    differenza sotto il 10% è rumore.
- **Editor delle mappe** (dalla Fase 6): `--smoke-editor-mappe` scolpisce,
  salva e riapre in pochi secondi, poi usa l'editor con mouse e tasti
  simulati, con dodici catture `odin_pp_editor_*.png`; scrive solo in
  `build/editor_smoke/mappe`. Va ripetuto quando una fase tocca i pennelli, i
  ritocchi o la geografia dei biomi.
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

- **Piano:** una delle griglie sovrapposte della mappa: **sotto profondo**
  (−2, un sotterraneo più in basso), **sotto** (−1, grotte e gallerie),
  **terra** (0, la mappa di oggi), **sopra** (+1, ponti, passerelle, balconi).
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
  - quattro triangoli per casella attorno al centro; la luce è morbida sulle
    salite e sfaccettata sulle pareti di roccia (risposte della Fase 1).
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

- Quattro griglie della stessa misura (tre nella prima versione; l'utente ne ha
  scelte quattro nella Fase 2). La terra è la mappa di oggi; gli altri piani
  sono quasi vuoti e hanno caselle solo dove servono.
- Le altezze di tutti i piani si contano dallo stesso zero, in gradini. Il
  piano sotto sta dentro i rilievi: una grotta entra di lato in una collina, a
  livello del terreno attorno. Per scendere davvero sotto il suolo un bioma può
  alzare tutto il suo terreno di una base (Fase 7).
- **Colonna valida:** due caselle calpestabili della stessa colonna, su piani
  diversi, distano almeno luce + spessore (10 + 2 gradini, scelti nella Fase 3). Così
  sopra ogni personaggio c'è spazio, e in una colonna vicina c'è al massimo una
  casella calpestabile a un gradino di distanza.
- **Ogni casella calpestabile di ogni piano è una casella della griglia:** il
  combattimento resta a griglia, anche fra piani.

### 2.5 Regole fra piani (proposte, da confermare nella Fase 3)

Nella Fase 3 l'utente le ha confermate tutte, con una differenza: niente
ascensori, solo scale a pioli (risposte nell'Esito della Fase 3).

- **Passo.** Si passa nella colonna vicina se lì c'è una casella calpestabile
  a un gradino al massimo, su qualsiasi piano. Per la regola della colonna ce
  n'è al massimo una, quindi il passo non sceglie mai il piano. Gli imbocchi
  nascono dalla forma della mappa, senza dati in più.
- **Scale a pioli** (scelte nella Fase 3): collegano due caselle di colonne
  vicine anche dove il dislivello è grande; si usano premendo la direzione
  verso la scala.
- **Ascensori e pozzi** (sezione 2.9): portano al piano sopra o sotto, nella
  stessa colonna; salirci è un passo. Nella Fase 3 l'utente non li ha voluti:
  se servono, si decidono nella Fase 7.
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
  quando è dentro, il ponte quando ci passa sotto. Quando il robot è sul
  ponte, ciò che sta sotto si scurisce un poco (Fase 4).
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
2. **Ascensori e pozzi** (proposti per la Fase 3): un collegamento fra piani
   nella stessa colonna, accanto a rampe e scale a pioli. Nella Fase 3 l'utente
   ha scelto solo le scale: gli ascensori restano un'idea per la Fase 7.
3. **Un sotterraneo grande in alcuni biomi** (Fase 7): non solo grotte dentro le
   colline, ma zone ampie sotto il suolo, raggiunte da un pozzo.
4. **Scorciatoie che si aprono dall'altra parte** (Fase 7): una porta, una leva
   o un ascensore; una volta aperte restano aperte anche nelle run dopo, come i
   segreti scoperti.
5. **L'ologramma a piani già nella Fase 5**, quando arriva il primo piano
   sotto, e non solo nella Fase 8. Nella Fase 5 l'utente ha scelto che cambi
   piano da solo, con il robot, senza tasto.
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
2. Ogni scena del benchmark si disegna su un canvas fisso di 1920×1080 pixel
   (risposta alla domanda 2).
3. Il gioco chiede la scheda video dedicata sui portatili con due schede
   (domanda nata durante la fase, vedi l'esito).
4. Misura di partenza sul PC dell'utente, ripetuta due volte (le due misure
   devono concordare): media, mediana e p95 per stage, scritte nell'esito e
   nell'appendice A.
5. Documenti: `docs/direzione-implementazione.md` (come ripetere il
   benchmark), `docs/avvio.md` (la scheda video) e `CHANGELOG.md`.

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

**Fatta il 25 ottobre 2026** sul ramo `piano-profondita`.

**Risposte dell'utente**
1. **Fare questa fase:** sì, con il comando della fase.
2. **Grandezza delle misure:** 1920×1080 pixel fissi in tutte le schermate. La
   mia raccomandazione era la finestra dello smoke. La domanda era stata
   riformulata, perché la grandezza la decide lo smoke, non lo schermo.
3. **Quando misurare:** subito.
4. **Scheda video**, domanda nata durante la fase: la RTX 3060. Il gioco
   disegnava con la Intel UHD integrata (`Renderer: Intel(R) UHD Graphics` nel
   log). L'utente ha scelto di far chiedere al gioco la scheda dedicata, sapendo
   che cambia il gioco per tutti.

**Cosa è stato fatto**
- **Intervallo di stage** (`src/application/campaign_smoke.odin`):
  `EXPEDITION_BENCHMARK_FIRST` e `EXPEDITION_BENCHMARK_LAST`, per default tutto
  il percorso, 0–102 (prima al massimo 0–50). Gli stage prima del primo
  preparano la loro scena per due fotogrammi, senza misurarla. Un intervallo
  sbagliato non compila.
- **Canvas fisso:** `Window.fixed_canvas_size` e la funzione pura
  `canvas_target_size` (`src/engine/app/window.odin`). Il benchmark lo mette a
  1920×1080 (`EXPEDITION_BENCHMARK_CANVAS_WIDTH` e `_HEIGHT`; 0 e 0 seguono la
  finestra). Nel gioco normale il campo resta a zero e non cambia niente.
- **Scheda video dedicata:** `src/windows_gpu.odin` esporta
  `NvOptimusEnablement` e `AmdPowerXpressRequestHighPerformance`, il modo
  documentato dai driver NVIDIA e AMD. Vale per tutto il gioco su Windows; dove
  c'è una scheda sola non cambia niente.
- **Documenti:** `docs/direzione-implementazione.md` (come ripetere il
  benchmark), `docs/avvio.md` (la scheda video), `CHANGELOG.md`, la sezione 1.4
  e l'appendice A di questo documento.
- **Test:** 1 nuovo, `test_fixed_canvas_ignores_window_and_display_scaling`
  in `src/engine/app`.

**Misure di partenza**
- **Macchina:** portatile HP con Intel Core i7-11800H, NVIDIA GeForce RTX 3060
  Laptop GPU (driver 32.0.15.9282) e Intel UHD Graphics, 15,6 GB di RAM,
  schermo 1920×1080 a 144 Hz, alla corrente, piano energetico consigliato da
  HP.
- **Come:** build `-o:speed`, 103 stage, canvas 1920×1080 in tutti, due giri
  (A e B) da 22 secondi ciascuno. Il log conferma
  `Renderer: NVIDIA GeForce RTX 3060 Laptop GPU`.
- **Concordanza:** le mediane dei due giri differiscono in media del 2,2%: 91
  stage su 103 entro il 5%, 99 entro il 10%, il peggiore del 14%. Le medie dei
  gruppi differiscono di meno del 2%, tranne lo scontro su due livelli (5%).

| Gruppo di stage | Media A (ms) | Media B (ms) | Mediana A | Mediana B | p95 peggiore |
|---|---:|---:|---:|---:|---:|
| Viste di base (0–6) | 1,73 | 1,73 | 1,60 | 1,60 | 3,67 |
| Biomi (7–18) | 1,44 | 1,44 | 1,38 | 1,36 | 2,42 |
| Luoghi e viste speciali (19–24) | 1,86 | 1,88 | 1,85 | 1,87 | 4,02 |
| Corsa e ingaggio (25–26) | 1,43 | 1,43 | 1,42 | 1,42 | 1,60 |
| Centro dei biomi (27–38) | 1,11 | 1,12 | 1,08 | 1,09 | 1,69 |
| Officine (39–50) | 1,14 | 1,15 | 1,11 | 1,12 | 1,64 |
| Bersagli (51–54) | 1,17 | 1,19 | 1,14 | 1,16 | 1,57 |
| Edifici (55–62) | 0,97 | 0,95 | 0,95 | 0,93 | 1,41 |
| Rilievi (63–74) | 1,06 | 1,08 | 1,03 | 1,04 | 1,46 |
| Ologrammi del rilievo (75–77) | 4,02 | 4,06 | 4,00 | 4,03 | 4,74 |
| Scontro su due livelli (78) | 1,07 | 1,14 | 1,01 | 1,06 | 1,65 |
| Montagna (79–86) | 1,01 | 1,01 | 0,93 | 0,95 | 1,55 |
| Grotte (87–98) | 0,91 | 0,93 | 0,88 | 0,90 | 1,34 |
| Posa delle strutture (99–102) | 0,99 | 0,99 | 0,93 | 0,93 | 1,42 |

- **Stage per stage:** appendice A.
- **Prima e dopo la scheda dedicata** (stessa build `-o:none`, stage 96–98,
  grotta dell'Inferno): con la Intel UHD 9,6, 5,7 e 5,7 ms; con la RTX 3060
  2,5, 1,2 e 1,2 ms. Circa quattro volte più rapido.

**Verifiche**
- Check normale e senza assert. `.\scripts\check.ps1` completo: 1655 test
  verdi, con e senza assert, più le due build.
- Prova breve del benchmark (stage 96–98) per l'intervallo e il canvas fisso.
- Smoke delle spedizioni completo sulla RTX 3060: 103 catture, nessun errore.
  Guardate quelle del bioma iniziale, della montagna, della grotta dell'Egitto
  e dell'ologramma della Neve: si vedono come prima.
- **Smoke del laboratorio: non completato.** Due giri si sono fermati senza
  errori: il primo dopo 13 atti su 18 (fino alla montagna; mancano grotta,
  cannone, buco nero, dinosauro e pesca), il secondo già nel primo atto. In
  tutti e due i casi il processo era vivo ma non scriveva più, mentre l'utente
  usava altre finestre. La causa, verificata all'inizio della Fase 1, è la
  finestra ridotta a icona: senza il flag `WINDOW_ALWAYS_RUN` raylib aspetta un
  evento e smette di disegnare. Prova: 15 secondi da ridotta a icona, log
  fermo; rimessa a posto, lo smoke riparte e finisce. (Prima avevo indicato il
  fuoco della finestra: era sbagliato.) L'utente ha chiesto di fare comunque il
  commit. Di questa fase, il
  laboratorio vede solo il cambio di scheda video, e gli atti arrivati in fondo
  sulla RTX non hanno dato errori. La correzione è il primo passo della Fase 1.

**Da sapere**
- A circa 1 ms per fotogramma (quasi 1000 fps) si misura vicino al costo fisso
  di presentazione: sul singolo stage, una differenza sotto il 10% è rumore. Le
  fasi dopo confrontano le medie dei gruppi, sulla stessa macchina, sulla RTX e
  alla corrente.
- Le scene più care sono quelle con l'ologramma aperto (stage 1, 23 e 75–77, da
  3,3 a 4,4 ms): l'ologramma della spedizione ricostruisce la geometria a ogni
  fotogramma. Va tenuto d'occhio nella Fase 5, quando diventa a piani.
- Con il canvas fisso lo smoke cambia ancora la grandezza della finestra in
  alcune schermate: cambia solo come il canvas si scala a schermo, non i pixel
  disegnati.
- I numeri dei documenti precedenti (Apple M1, canvas diversi, stage 0–26) non
  si confrontano con questi.
- Il primo smoke del laboratorio si è fermato da fuori dopo l'atto della
  montagna, senza errori; è stato rifatto intero.

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
- **Salite smussate** (risposta 2): le normali si mediano fra i triangoli
  vicini della stessa superficie, così rampe e colline hanno una luce morbida.
- **Dirupi:** pareti di roccia sfaccettate, con qualche irregolarità sotto lo
  spigolo, mai sopra, dove si cammina; senza le righe dei gradini
  (risposta 5).
- **Bordo al neon** in cima ai dirupi, tenue, del colore del bioma
  (risposta 4).
- **Prestazioni:** al massimo +10% di media sui gruppi della Fase 0
  (risposta 6).
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
6. **Obiettivo di prestazioni.** Il singolo stage oscilla fino al 10% tra due
   giri (esito della Fase 0), quindi si confrontano le medie dei gruppi.
   - (Consigliato) Al massimo +5% di media su tutti i gruppi della Fase 0,
     nessun gruppo oltre +10%.
   - Oppure un altro.

### Passi

0. Gli smoke non devono fermarsi quando la loro finestra è ridotta a icona: il
   host accende `WINDOW_ALWAYS_RUN` per gli smoke (esito della Fase 0). Poi lo
   smoke completo del laboratorio, come base delle catture di questa fase.
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

**Fatta il 25 ottobre 2026** sul ramo `piano-profondita`.

**Risposte dell'utente**
1. **Dove:** laboratorio e spedizioni insieme.
2. **Salite:** facce smussate (la mia raccomandazione era facce piatte).
3. **Pareti dei dirupi:** roccia sfaccettata.
4. **Bordo al neon in cima ai dirupi:** sì, tenue.
5. **Righe dei gradini sui fianchi:** via (la mia raccomandazione era tenerle).
6. **Obiettivo di prestazioni:** più largo, fino a +10% di media.

**Cosa è stato fatto**
- **Passo 0, smoke che non si fermano:** `host.Config.keep_running` accende `WINDOW_ALWAYS_RUN` per tutti
  gli smoke (`src/engine/host/host.odin`, `src/application/launcher.odin`,
  `src/application/application_start.odin`). Prova: ridotto a icona per 15 secondi, lo smoke continua e
  finisce; prima si fermava. Il gioco normale si mette ancora in pausa quando è ridotto a icona.
- **Superficie:** `src/level/surface.odin`, funzione pura: `surface_cell` (centro e angoli),
  `surface_height_at`, `surface_linked`, `surface_top`. Un angolo è la media delle caselle attorno che la
  casella raggiunge per lati collegati (al massimo un gradino: `SURFACE_LINK_STEPS`, uguale a
  `game.HEIGHT_MAX_STEP`, e un test lo controlla). Dove il terreno gira attorno alla fine di un dirupo, lo
  spigolo sfuma.
- **Spedizioni** (`src/render/expedition_terrain.odin`, riscritto): quattro triangoli per casella con le
  normali mediate fra i triangoli della stessa superficie (due triangoli per le caselle in piano senza
  dirupi); pareti di roccia in otto facce, con il mezzo spinto un poco nella roccia; il bordo al neon viene
  dall'alfa dei vertici; il piano si disegna solo dove il rilievo non copre (`raised`). Nello shader del
  pavimento (`src/render/expedition_floor.odin`) tolte le righe dei gradini, la luce usa la normale vera e
  lo spigolo dei dirupi brilla del colore del bioma.
- **Laboratorio** (`src/render/diorama_scene.odin`): le caselle in pendenza sono piastrelle inclinate
  (`draw_sloped_tile`); quelle in piano restano i blocchi di prima; tolte le righe dei gradini.
- **Personaggi e segni:** `point_ground` legge la superficie; `rim_ground` tiene piedistalli e ombre a
  contatto sul punto più alto sotto il loro bordo (le ombre ora stanno sul terreno anche in alto, prima
  finivano sotto); `cell_overlay_ground` alza anteprime, segni dei bersagli, intenti e marcatori sulla cima
  della casella; il rombo del puntatore 2D segue gli angoli; il puntatore 3D colpisce la superficie.
- **Test:** 7 nuovi (6 in `level`, 1 in `game`). In `render` il test di `point_ground` è stato riscritto:
  descriveva la media delle quattro caselle attorno, che non c'è più.

**Verifiche**
- Check normale e senza assert. `.\scripts\check.ps1` completo: 1662 test verdi, con e senza assert,
  più le due build.
- Smoke del laboratorio completo, prima e dopo: 110 catture ciascuno, nessun errore. 89 catture sono
  identiche al byte; cambiano solo le 20 delle arene «Altezze» e «Montagna» (rampa di piastrelle, sentiero
  in pendenza, pareti pulite).
- Smoke delle spedizioni completo: 103 catture, nessun errore. Guardate Egitto (dune morbide), Vietnam
  (colline), Neve (montagna e scontro su due livelli), Cyber (altopiano con il bordo rosso) e Cielo (ponti
  in rampa).
- Benchmark, due giri prima (Fase 0) e due dopo, sulla RTX 3060 alla corrente; medie dei due giri:

| Gruppo di stage | Fase 0 (ms) | Fase 1 (ms) | Differenza |
|---|---:|---:|---:|
| Viste di base (0–6) | 1,73 | 1,78 | +2,9% |
| Biomi (7–18) | 1,44 | 1,50 | +4,3% |
| Luoghi e viste speciali (19–24) | 1,87 | 1,92 | +2,7% |
| Corsa e ingaggio (25–26) | 1,43 | 1,46 | +2,4% |
| Centro dei biomi (27–38) | 1,12 | 1,14 | +2,2% |
| Officine (39–50) | 1,14 | 1,18 | +3,2% |
| Bersagli (51–54) | 1,18 | 1,20 | +1,8% |
| Edifici (55–62) | 0,96 | 0,99 | +3,5% |
| Rilievi (63–74) | 1,07 | 1,09 | +2,4% |
| Ologrammi del rilievo (75–77) | 4,04 | 4,07 | +0,7% |
| Scontro su due livelli (78) | 1,10 | 1,11 | +0,7% |
| Montagna (79–86) | 1,01 | 1,05 | +3,6% |
| Grotte (87–98) | 0,92 | 0,93 | +1,0% |
| Posa delle strutture (99–102) | 0,99 | 1,01 | +2,6% |

  In media +2,4%, il gruppo peggiore +4,3%: dentro l'obiettivo (+10%). I due giri nuovi concordano (2,3%
  di differenza media, 101 stage su 103 entro il 10%).

**Da sapere**
- I segni a terra stanno sulla cima della casella: su una rampa galleggiano un poco sul lato basso (al
  massimo circa un decimo di casella) invece di sparire sul lato alto.
- Sulle caselle in pendenza del laboratorio mancano le piccole incisioni decorative: affonderebbero nel
  lato alto.
- Un personaggio spinto giù da un dirupo dovrebbe scendere di colpo sullo spigolo, perché prima scivolava
  lungo una rampa invisibile. È atteso, ma non l'ho guardato in movimento: le catture sono ferme.
- Dalla sezione 12: tolto `covered`; il rilassamento sulle diagonali passa alla Fase 3 e la sfera di
  taglio alla Fase 5.

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

- `grid.Position` riceve `layer: i8`: −2 sotto profondo, −1 sotto, 0 terra,
  +1 sopra (quattro piani, risposte 1 e 3).
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

**Fatta il 25 ottobre 2026** sul ramo `piano-profondita`.

**Risposte dell'utente**
1. **Valori del piano:** −1, 0, +1, con la terra a 0.
2. **Forma delle posizioni riscritte:** con i nomi, più `grid.offset` per le vicine.
3. **Quanti piani:** quattro (la mia raccomandazione era tre): −2 sotto profondo, −1 sotto, 0 terra,
   +1 sopra. Il documento è aggiornato (introduzione, sezioni 2.1 e 2.4, Fasi 3 e 7).
4. **Domande nate durante la fase:**
   - il test del budget dello stack falliva: limiti alzati, con un commento (`Room` sotto i 9 KB, registri
     degli eventi entro 104 KB);
   - 35 avvisi del compilatore sulle `Renderer` dei test messe sullo stack: spostate sullo heap;
   - salvataggi più grandi e più lenti (in background): vanno bene così.

**Cosa è stato fatto**
- **`grid.Position`** ha `layer: i8` (`src/engine/grid/grid.odin`), con `LOWEST_LAYER` (−2),
  `GROUND_LAYER` (0) e `HIGHEST_LAYER` (+1). `contains`, `index_of`, `get` e `set` di una `Grid` rifiutano
  gli altri piani; `grid.offset(p, dx, dy)` dà la vicina conservando il piano; `grid.cell_index` vale per
  le tabelle parallele.
- **Riscrittura guidata dal compilatore**, con un programma nella scratchpad (non nel repo): 3215
  posizioni in un solo giro, di cui 2909 nella forma con i nomi, 300 vicine diventate `grid.offset`, 4
  vicine con i nomi in test senza l'import di `grid` e 2 copie (`{p.x, p.y}`). Una sola correzione a mano:
  in `relief.odin` la «vicina» era un `Plateau`, non una posizione.
- **Indici a mano:** `reachable_walkable` (strutture) passa da `grid.cell_index`. Gli altri lavorano su
  finestre locali di interi, giuste finché tutto sta sulla terra, e diventano per piano nella Fase 3.
  `place_check` rifiuta le strutture fuori dalla terra.
- **Test:** 3 nuovi, in `engine/grid`: una griglia ha un piano solo, `offset` conserva il piano, una
  posizione salvata senza `layer` torna sulla terra. In `level` un test esistente ha due controlli in
  più: la stessa struttura si piazza sulla terra e non su un altro piano. Nei test esistenti, oltre alla
  scrittura delle posizioni, due cambi approvati dall'utente: i limiti del budget dello stack e le
  `Renderer` sullo heap (35 in 20 file).

**Costi misurati**
- Una posizione pesa 24 byte invece di 16. Un evento di gioco passa da 232 a 248 byte, `Room` da 7.768 a
  8.616 e i registri degli eventi da circa 96,6 a 103,3 KB; la `Renderer` pesa 290.560 byte.
- Lo snapshot della spedizione in memoria passa da 1.427.944 a 1.885.888 byte; il salvataggio da 2,76 a
  3,33 MB e da 198 a 249 ms di media, in un thread a parte.

**Verifiche**
- Check normale e senza assert, senza avvisi. `.\scripts\check.ps1` completo: 1665 test verdi, con e
  senza assert, più le due build.
- Smoke del laboratorio completo: le 109 catture sono identiche al byte a quelle della Fase 1. A schermo il
  gioco non cambia.
- Smoke delle spedizioni completo: 103 catture, nessun errore. Non si confrontano al byte, perché
  l'animazione segue il tempo vero: due giri della stessa build differiscono in 67 catture. Le ho guardate:
  lo scontro nel Cyber e la grotta della Neve sono come prima.
- Benchmark contro la Fase 1: +0,2% di media, gruppo peggiore +2,1% (gli ologrammi): rumore.

**Da rivedere quando arrivano i piani (Fase 3)**
- Vicine scritte con i nomi perché il file non importa `grid` (restano sulla terra):
  `src/render/world_playback_test.odin:94`, `src/integration/mechanics_lab_test.odin:105`,
  `src/run/expedition_flow_test.odin:254` e `:277`.
- Copia senza piano: `src/expedition/player_structures_test.odin:100`. L'altra copia,
  `src/expedition/relief.odin:114`, è un `Plateau`: corretta così.
- Le finestre locali dell'IA (`rebuild_tactical_enemy_distances`) e il campo delle distanze diventano per
  piano.

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

- **Dati:** `level.Level` riceve i piani sotto (−1 e −2) e sopra (tipi e
  altezze), vuoti finché non servono; la terra resta quella di oggi. `tile_at` e `height_at`
  scelgono il piano dalla posizione. Cambiare un piano alza
  `geometry_revision`.
- **Controllo della colonna:** due caselle calpestabili della stessa colonna
  distano almeno luce + spessore; una mappa che non lo rispetta è rifiutata,
  con un test.
- **Regole** della sezione 2.5, in tutti i punti elencati sopra:
  - passo, diagonale, schivata e passo dei nemici;
  - scale a pioli (l'utente non vuole gli ascensori);
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
  - una scala a pioli sul dirupo della collina;
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
   catture: salire sul ponte, passarci sotto, entrare in grotta, salire con
   la scala, tiro dal ponte, spinta giù dal ponte.
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
- La scala porta da un piano all'altro, il robot e i nemici.
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

**Fatta il 25 ottobre 2026** sul ramo `piano-profondita`.

**Risposte dell'utente**
1. **Luce e spessore:** 10 + 2 gradini.
2. **Scale a pioli e ascensori:** solo le scale a pioli. Il documento è aggiornato (sezioni 2.4, 2.5
   e 2.9, Fasi 3 e 7): gli ascensori, se servono, si decidono nella Fase 7.
3. **Tiri fra piani:** in tutte e due le direzioni.
4. **Aree fra piani:** il piano dell'ancora; dove manca, la casella più vicina in altezza entro 2
   gradini.
5. **Bordo dei ponti:** aperto, con il danno di caduta di oggi.
6. **Mischia:** fra piani diversi solo agli imbocchi; sullo stesso piano come oggi.
7. **Carte che agiscono su tutta la mappa o con una forma propria:** sul piano di chi gioca come oggi,
   sugli altri solo su ciò che vede.
8. **Sotto profondo nell'arena:** no, bastano i test.

**Cosa è stato fatto**
- **Dati** (`src/level/layers.odin`):
  - `Level.planes`: un piano per livello, grande come la terra e vuoto finché non ha una casella;
  - `Level.ladders`: le scale a pioli;
  - `tile_at`, `height_at`, `set_tile` e `set_height` scelgono il piano dalla posizione; ogni cambio alza
    `geometry_revision`;
  - `layer_contains`, `has_layers` e `column_walkable_near`;
  - `check_layers` controlla la colonna (12 gradini, piani in ordine) e le scale (colonne vicine).
- **Colonne e vista** (`src/level/layer_sight.odin`):
  - `Layer_Map` legge i piani di un livello o della copia del renderer;
  - `Column` dà i pavimenti e le parti solide di una colonna: la terra, la roccia sopra una grotta,
    l'impalcato di un ponte;
  - `layer_line_blocker` è la vista attraverso i piani. Al centro della casella la linea segue la regola
    della terra di sempre; impalcati e rocce non li tocca in nessun punto della casella, estremi compresi;
  - `column_landing` dice dove atterra uno spostamento.
- **Regole** (`src/game/layers.odin`):
  - passo e scale: `layer_step`;
  - mischia: `bump_cell` e `melee_layers_meet`;
  - aree: `area_cell`;
  - vista e carte speciali: `room_line_blocker` ed `effect_reaches`;
  - tabelle della stanza per piano (distanze dei nemici, pozze): `room_table_index`.
- **Dove entrano le regole:**
  - passo, diagonale e schivata;
  - la pipeline degli spostamenti: ogni casella del percorso atterra sul suo piano. Il movimento nuovo
    `Climb` sale o scende una scala, senza caduta;
  - i nemici:
    - passi pianificati ed esecuzione, anche sulle scale;
    - mischia e carica del bruto;
    - campo delle distanze su tutti i piani. Senza piani né scale il calcolo resta quello di prima;
  - la vista: tiri, nebbia del gioco e copia del renderer, rete dei dispositivi, avvistamento delle
    spedizioni. Il ciclo di `tactical_line_visible` ora si ferma alla colonna d'arrivo: verso un altro piano
    non sarebbe finito mai;
  - le aree:
    - le forme delle carte (croce e quadrato; la linea segue la vista);
    - esplosioni, fuochi, scariche e onda tossica;
  - i confini: le convalide dei bersagli `Cell` e delle intenzioni dei nemici accettano gli altri piani.
- **Carte speciali**, controllate una per una:
  - Inondazione e Buco Nero seguono la regola scelta;
  - Bomb Marley: la festa ha il suo piano;
  - Lazzo: anello sul piano del robot, atterraggio sul piano del nemico;
  - Pinball: la palla rotola sul suo piano;
  - First Person Shooter: il colpo attraversa le colonne;
  - Cannone: il raggio resta sul suo piano;
  - dispositivi: vedono dal loro punto;
  - Dinosauro: passa dalla pipeline.
- **Disegno semplice** (renderer del laboratorio):
  - la vista copia anche i piani;
  - personaggi, ombre, oggetti e telecamera stanno sul pavimento del loro piano;
  - le caselle dei piani si disegnano come quelle della terra: il ponte come impalcato, la grotta scavata
    nella collina;
  - quando il robot è sotto, ciò che lo copre entro 5 caselle è mezzo trasparente;
  - il mouse attraversa le colonne e prende la prima superficie, anche sotto il ponte o dentro la grotta
    dall'imbocco.
- **Arena «Piani»** (sesta di F3, 46×29, `run/mechanics_practice.odin`) e **atto dello smoke** `layers`
  (`src/devtools/mechanics_lab_layers.odin`), con sette catture:
  - l'arena;
  - il robot sul ponte;
  - un Incendio lanciato dal ponte sulla strada;
  - la spinta dal ponte, con caduta di 10;
  - il robot sotto il ponte;
  - il robot in grotta;
  - il robot in cima alla scala.
- **Test:** 19 nuovi:
  - 9 in `level`: dati, colonna, scale, solidi, vista, atterraggio;
  - 8 in `game`: passo sul ponte e in galleria, scala, due personaggi nella stessa colonna, spinta giù dal
    ponte, vista, aree, nemici;
  - 1 in `render`: il mouse e i personaggi sui piani;
  - 1 in `integration`: l'arena.

**Scelte prese durante la fase**
- **Carte piazzate** (Buco Nero, Cannone, dispositivi): «chi gioca» è il punto da cui l'effetto agisce,
  cioè il loro piano e la loro vista.
- **Pinball e Cannone** restano sul loro piano: la palla e il raggio non cambiano piano.
- **La regola sullo stesso piano non cambia.** Inondazione, Bomb Marley e Lazzo raggiungono anche chi non
  si vede, come oggi.
- **Mouse:** prende la superficie più vicina lungo il raggio. Saltare ciò che è diradato spetta alla Fase 4.
- **Pozze:** chiudono le aree anche attraverso un imbocco. I fuochi stanno sul loro piano.

**Verifiche**
- **Check e test.** Check normale e senza assert, senza avvisi. `.\scripts\check.ps1` completo: 1684 test
  verdi (1665 più i 19 nuovi), con e senza assert, più le due build.
- **Atto `layers` dello smoke del laboratorio.** Le sette catture, guardate una per una:
  - il robot sul ponte;
  - l'anteprima dell'Incendio dal ponte sulla strada;
  - la caduta di 10;
  - sotto il ponte, con l'impalcato mezzo trasparente;
  - in grotta, con la collina mezza trasparente;
  - in cima alla scala.
- **Smoke del laboratorio completo.**
  - 86 catture sono identiche al byte a quelle della Fase 2, e 8 sono nuove.
  - Le 23 catture degli atti che vengono dopo quello dei piani cambiano perché quell'atto arriva prima: in
    due minuti l'orologio delle animazioni va avanti. Una copia del gioco che salta solo l'atto dei piani le
    rifà identiche al byte.
  - In quella copia due catture delle strutture differiscono di 6 e di 22 pixel. Nella corsa vera erano
    identiche: è rumore del disegno.
- **Smoke delle spedizioni completo.** 103 catture, nessun errore. Non si confrontano al byte: due corse
  della Fase 2 differivano in 67 catture, qui in 81. Ho guardato lo scontro nel Cyber, lo scontro su due
  livelli e la grotta della Neve, e sono come prima.
- **Benchmark contro la Fase 2.** Due corse alla corrente, sulla RTX 3060, tutti i 103 stage in 22 secondi
  a corsa: +0,3% di media dei gruppi, il gruppo peggiore +2,4% (gli ologrammi del rilievo, 75–77, come
  nella Fase 2). È rumore. Le due corse nuove concordano (2,4% di scarto medio fra le mediane, 100 stage su
  103 entro il 10%).
  - Una prima prova, alle 22:45, era stata fatta a batteria (47%): il driver teneva ogni stage a 30 fps
    fissi (33,3 ms), e quella misura non valeva. Questa è stata rifatta quando l'utente ha attaccato il
    portatile alla corrente.

| Gruppo | Fase 2 (ms) | Fase 3 (ms) | Differenza |
|---|---:|---:|---:|
| Viste di base (0–6) | 1,80 | 1,80 | −0,1% |
| Biomi (7–18) | 1,48 | 1,47 | −0,4% |
| Luoghi e viste speciali (19–24) | 1,94 | 1,95 | +0,5% |
| Corsa e ingaggio (25–26) | 1,46 | 1,47 | +0,6% |
| Centro dei biomi (27–38) | 1,14 | 1,15 | +0,9% |
| Officine (39–50) | 1,17 | 1,18 | +0,4% |
| Bersagli (51–54) | 1,20 | 1,22 | +1,8% |
| Edifici (55–62) | 0,99 | 0,99 | +0,1% |
| Rilievi (63–74) | 1,09 | 1,09 | −0,3% |
| Ologrammi del rilievo (75–77) | 4,15 | 4,25 | +2,4% |
| Scontro su due livelli (78) | 1,11 | 1,09 | −2,0% |
| Montagna (79–86) | 1,04 | 1,05 | +0,5% |
| Grotte (87–98) | 0,93 | 0,93 | −0,1% |
| Posa delle strutture (99–102) | 1,02 | 1,02 | +0,3% |

**Rivisto dalla Fase 2**
- Le vicine scritte con i nomi nei test (`world_playback_test`, `mechanics_lab_test`,
  `expedition_flow_test`) e la copia in `player_structures_test` restano sulla terra: sono giuste così.
- Le finestre locali dell'IA e il campo delle distanze ora vanno per piano.

**Non fatto, per la Fase 4**
- I personaggi nascosti (un nemico in grotta visto dalla collina) non hanno contorno; la sua etichetta si
  vede.
- Il mouse non salta ciò che è diradato.
- Non c'è la luce sotto terra.
- Il passaggio fra due piani si disegna con un piccolo scatto di altezza.

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
- **Sotto il ponte, più scuro** (scelta dell'utente nella Fase 4): quando il
  robot è su un piano sopra la terra, ciò che sta sotto di lui si scurisce un
  poco, per dare profondità.
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

**Fatta il 25 ottobre 2026** sul ramo `piano-profondita`.

**Risposte dell'utente**
1. **Cosa si dirada:** ciò che sta sopra la testa del robot entro 6 caselle, con un'apertura graduale come
   gli edifici.
2. **Personaggi nascosti:** un contorno del loro colore.
3. **Luce sotto terra:** più scura, con le luci dei personaggi.
4. **Ciò che sta sotto il robot quando è sul ponte:** un po' più scuro, non il consigliato «normalmente».
   Il documento è aggiornato (sezione 2.6 e Progetto di questa fase).

**Il codice citato** c'era ancora tutto; in `height_view.odin` le righe si sono spostate con la Fase 3
(all'inizio di questa fase `terrain_hides_actor` era alla 329).

**Cosa è stato fatto**
- **Regole pure** (`src/game/layer_view.odin`), come `structure_visibility`:
  - `layer_cover_opacity`: un pezzo su un piano sopra il robot, con la cima sopra la sua testa, entro 6
    caselle si apre dal 100% fino al 15% accanto a lui;
  - `layer_viewer_in_vault` e `layer_cell_dim`: in grotta, sotto la volta, è più scuro tutto ciò che non
    sta sul suo piano (60%); sul ponte, ciò che sta sotto di lui (25%);
  - `layer_solid_owner`: a quale pezzo appartiene un'altezza di una colonna (l'impalcato è del ponte, la
    roccia è della terra);
  - `layer_figure_hidden`: una figura è nascosta se la linea dalla telecamera al suo petto entra in un pezzo
    disegnato quasi intero; il pavimento sotto la figura non conta.
- **Disegno nel laboratorio:**
  - le caselle diradate vanno nel passaggio ordinato con gli attori, in resina trasparente. Prendono il
    posto dei riquadri provvisori della Fase 3;
  - le caselle più scure hanno un velo scuro sulla colonna, come fuori da un edificio;
  - un tabellone con i piani usa una variante dello shader della resina, con due valori nuovi:
    `underground`, per cui in grotta la luce del cielo cala al 35%, e `lanternBand`, per cui la lanterna sale
    con il pavimento del robot e illumina solo le altezze del suo piano (`resin_layer_fragment`,
    `Resin_Layer_Program`). Senza piani resta lo shader di prima, identico;
  - i nascosti hanno un contorno del loro colore (chiaro il robot, rosso i nemici), disegnato sopra tutto.
    Lo fa uno shader nuovo che dilata la trasparenza della figura come il contorno a fumetto, ma tiene solo
    l'anello e un velo dentro (`src/render/layer_outline.odin`);
  - il mouse attraversa i pezzi diradati più della metà (`game.LAYER_PICK_THROUGH`);
  - la telecamera va verso la quota del nuovo piano di un quinto a ogni aggiornamento della vista;
  - le ombre stavano già sul piano di chi le fa dalla Fase 3.
- **Atto dello smoke `layers`:** tre catture nuove:
  - il bruto sotto l'impalcato visto dal robot sul ponte, con il contorno rosso;
  - il mouse su una casella della strada sotto l'impalcato diradato, mostrata con l'anteprima
    dell'Incendio. L'atto controlla che il puntatore prenda proprio quella casella;
  - l'arciere sul ponte sopra il robot.

  La cattura della grotta ora ha la collina che si apre, il fuori più scuro e la lanterna.
- **Test:** 4 nuovi. 3 in `game` sulle regole pure (diradamento, scurimento, nascosti) e 1 in `render`: il
  mouse attraversa l'impalcato diradato e si ferma su quello intero.

**Scelte prese durante la fase**
- **Quando si dirada:** sempre, sopra la testa del robot, anche se non è proprio sotto. Il ponte si apre
  già quando il robot gli passa accanto sulla strada.
- **Nascosti:** valgono anche il terreno e i rilievi, nell'arena con i piani. Un nemico dietro una rampa,
  visto dalla grotta, ha il contorno.
- **Scurimento e diradamento cambiano di colpo**, al cambio di casella del robot (per lo scurimento) o con
  il suo punto disegnato (per il diradamento), senza animazione: così lo smoke resta deterministico.

**Verifiche**
- **Check e test.** Check normale e senza assert, senza avvisi. `.\scripts\check.ps1` completo: 1688 test
  verdi (1684 più i 4 nuovi), con e senza assert, più le due build.
- **Atto `layers` dello smoke del laboratorio.** Le dieci catture, guardate:
  - in grotta: la collina si apre attorno al robot, il fuori è più scuro, resta la lanterna, il nemico nella
    stanza ha il contorno;
  - dal ponte: il bruto sotto l'impalcato si vede col contorno rosso, la strada è un poco più scura;
  - sotto il ponte: l'impalcato si apre sopra il robot e l'arciere ci sta sopra;
  - il mouse prende la casella della strada (19,13) attraverso l'impalcato. L'atto lo controlla e la
    mostra con l'anteprima dell'Incendio.
- **Smoke del laboratorio completo, contro la Fase 3.**
  - Le 87 catture prima dell'atto dei piani sono identiche al byte. Cambiano le 7 dell'atto dei piani (il
    disegno nuovo) e le 23 degli atti dopo: l'atto più lungo sposta l'orologio delle animazioni.
  - Una copia del gioco che salta solo l'atto dei piani rifà tutte le 109 catture della Fase 2, identiche
    al byte. Senza piani il disegno non è cambiato in niente.
  - In una prima versione la Fase 4 cambiava lo shader della resina per tutti. Erano 71 catture con al
    massimo 7 pixel diversi ciascuna, sempre di 1 su 255. Per questo i piani hanno una variante tutta loro
    e lo shader di prima resta identico.
- **Smoke delle spedizioni completo.** 103 catture, nessun errore. Come sempre non si confrontano al byte (81
  diverse dalla Fase 3, come fra due corse uguali). Lo scontro su due livelli è come prima.
- **Benchmark contro la Fase 3.** Due corse alla corrente, sulla RTX 3060, 22 secondi a corsa. La media dei
  gruppi è −0,0%. Il gruppo peggiore è lo scontro su due livelli, uno stage solo: +4,3%, cioè 0,05 ms,
  sotto la soglia del rumore. Le due corse concordano (2,1% di scarto medio fra le mediane, 101 stage su
  103 entro il 10%).

**Non fatto, per le fasi dopo**
- Le spedizioni non usano ancora niente di tutto questo: arriva con la Fase 5.
- La telecamera segue la quota, ma non si avvicina in grotta.

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

- **Generatore** (risposte dell'utente nella Fase 5):
  - la grotta di oggi (`cave_plan`, 34×18) sta dentro un massiccio di roccia
    sulla terra, sul piano sotto, a livello del terreno attorno, e l'arco
    diventa l'imbocco;
  - i posti sono nuovi, dove il massiccio ha spazio: misurato all'inizio della
    fase, quello di una grotta di oggi entra libero solo in 2 dei 12 posti di
    allora. Gli archi si spostano;
  - nel Far West una grotta di oggi non entra da nessuna parte (la mappa è
    160×160 e i 16 luoghi la riempiono): lì le grotte sono di 24×14, con due
    stanze (scelta dell'utente durante la fase); negli altri tre biomi restano
    di 34×18;
  - ogni posto ha sempre il suo massiccio con la grotta (geografia fissa); la
    run sceglie quali grotte hanno nemici e segreto, le altre restano vuote;
  - nella Neve la grotta della montagna è una stanza sola nel nucleo, con il
    segreto, e l'imbocco resta sul sentiero a metà salita: a 68 gradini il
    nucleo con 12 gradini di roccia sopra è di circa 8×8 caselle.
- **In grotta:** gruppi e oggetti della grotta stanno semplicemente sul piano
  sotto, e la mappa fuori resta com'è. Spariscono `Outer_Map`, la dissolvenza
  e il bioma 255.
- **Renderer delle spedizioni:** una texture del pavimento per piano; blocchi
  della superficie per piano; diradamento della roccia sopra il robot con il
  retino del programma «reveal»; contorni; luci e ombre per piano. Le regole
  pure della Fase 4 si riusano.
- **Esplorazione, mount, pattuglie e avvistamento** con le regole fra piani.
- **Mount** (scelta dell'utente): si entra in grotta in sella, come negli altri
  posti. Se in sella si fa partire un evento che fa apparire nemici, il robot
  scende da solo.
- **Salvataggi:**
  - i piani sotto e sopra si salvano come una lista delle sole caselle che
    esistono (indice, tipo, altezza): quei piani sono quasi vuoti, quindi lo
    snapshot cresce poco e lo stack della decodifica non aumenta come farebbe
    con altre tabelle `[MAX_CELLS]`;
  - le posizioni hanno il piano (Fase 2);
  - i salvataggi di prima di questa fase non servono, perché l'utente li
    cancella: vengono rifiutati senza danni, senza conversione.
- **Ologramma a piani, già qui** (la lezione del DLC di Elden Ring, sezione
  2.9): si apre anche in grotta e mostra il piano del robot, cambiando piano da
  solo quando lo cambia lui (scelta dell'utente, senza tasto); gli imbocchi
  scoperti sono segnati, quelli segreti restano nascosti finché non li si
  scopre. La Fase 8 lo completa.
- **Prestazioni:** benchmark sugli stage della Fase 0, prima e dopo. La qualità
  viene prima (scelta dell'utente): fino a +10% se serve a un disegno migliore.

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
2. Salvataggi: piani come liste, posizioni con il piano, rifiuto senza danni
   dei salvataggi di prima, con test di andata e ritorno.
3. Esplorazione, mount, pattuglie e avvistamento fra piani.
4. Renderer delle spedizioni: texture e superfici per piano, diradamento,
   contorni, luci, ombre.
5. Ologramma a piani, che segue il piano del robot da solo, con gli imbocchi
   scoperti segnati.
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
- Un checkpoint preso in grotta si riapre in grotta; un salvataggio di prima
  di questa fase viene rifiutato senza danni.
- Le pattuglie seguono le regole scelte.

### Fatto quando

- In ognuno dei quattro biomi si entra in grotta camminando, senza nero, e se
  ne esce dallo stesso imbocco.
- I salvataggi nuovi si caricano; quelli di prima vengono rifiutati senza
  danni.
- Le prestazioni rispettano l'obiettivo.
- Le verifiche della sezione 1.4 sono a posto.

### Comando

```text
Esegui la Fase 5 di docs/piano-profondita.md (Piani nelle spedizioni: grotte
senza caricamento). Segui le regole della sezione 1: fammi prima le domande
della fase e fermati alla fine.
```

### Esito

**Fatta il 26 ottobre 2026** sul ramo `piano-profondita`.

**Risposte dell'utente**
1. **Quali grotte:** tutti e quattro i biomi. Ogni posto ha sempre il suo massiccio con la grotta (geografia
   fissa); la run sceglie quali hanno nemici e segreto, le altre restano vuote.
2. **Grandezza:** le grotte di oggi (34×18), in posti nuovi dove c'è spazio; gli archi si spostano. Durante
   la fase è venuto fuori che nel Far West una grotta di 34×18 non entra da nessuna parte (la mappa è
   160×160 e i 16 luoghi la riempiono): l'utente ha scelto grotte di 24×14 con due stanze, solo lì.
3. **La grotta della montagna:** una stanza sola nel nucleo, con il segreto; l'imbocco resta sul sentiero.
4. **Salvataggi di prima della fase:** non servono, l'utente li cancella: rifiutati senza danni, senza
   conversione.
5. **Scontri sull'imbocco:** sì, entrare è camminare.
6. **Pattuglie:** entrano in grotta come ovunque.
7. **Mount:** si entra in sella, in grotta e negli altri posti; un evento che fa apparire nemici, fatto
   partire in sella, fa scendere il robot.
8. **Prestazioni:** la qualità prima di tutto, fino a +10% se serve a un disegno migliore.
9. **Ologramma:** cambia piano da solo con il robot, senza tasto (non il consigliato); gli imbocchi
   scoperti sono segnati, quelli segreti restano nascosti finché non li si trova.

**Il codice citato** c'era ancora tutto; le righe della scena si erano spostate di poco.

**Cosa è stato fatto**
- **Generatore** (`src/expedition/cave.odin`):
  - i posti sono fissi per bioma e si scelgono prima dei rilievi (`plan_caves`), che tengono piano il
    terreno attorno a ogni massiccio come attorno ai luoghi. Il massiccio è alto 14 gradini al bordo e sale
    di un gradino a casella fino a 18; le stanze stanno sul piano −1 alla quota del terreno; un tunnel va
    dalla prima stanza all'imbocco, sul lato ovest. Gli oggetti sparsi finiscono sotto la roccia; davanti
    all'imbocco il terreno è sgombro e sicuro (niente lava);
  - con il seme 42: tre posti per bioma. Nella Neve la stanza della montagna ha 45 caselle a 67 gradini,
    con l'imbocco sul sentiero, più due massicci sul terreno aperto; nel Far West tre grotte di 24×14;
    in Egitto e nell'Inferno tre di 34×18;
  - ogni grotta ha un sito all'imbocco, anche quelle vuote; le abitate hanno i loro nemici e il segreto
    sul piano −1.
- **Mondo:** `in_cave` si ricava a ogni tick dalla posizione (`cave_at`), che segna anche le grotte visitate
  e saccheggiate. Sotto la roccia non c'è il terreno del bioma (`game.expedition_terrain`) e non arriva la
  corsia; la corsia dell'Inferno non spacca i massicci. Passo, esplorazione libera, pattuglie in sonno e
  campo delle distanze dei richiami passano dai piani con la regola del passo.
- **Salvataggi:** i piani fuori dalla terra sono una lista di caselle e di pozze; `layers_version` dice
  che il salvataggio è di questa fase. Uno di prima è rifiutato senza danni: lo slot risulta «stato non
  valido» e i progressi della campagna restano.
- **Scena:** niente dissolvenza, `Outer_Map`, `enter_cave`, `exit_cave` né bioma 255. In grotta si aprono
  l'ologramma e la mount; si interagisce anche in sella.
- **Disegno:**
  - le stanze sotto la terra sono un passaggio del programma del pavimento (`render/expedition_layers.odin`):
    pavimenti di lastre scure, pareti di roccia sfaccettate e il taglio della roccia alla quota del soffitto,
    così la roccia diradata si apre su stanze scavate; la parete del massiccio si apre sopra l'imbocco;
  - in grotta la terra sopra gli occhi del robot si dirada con un retino rotondo entro 6 caselle (la regola
    della Fase 4), e ciò che ne resta si scurisce; tutta la terra si scurisce del 60%; nelle stanze la luce
    del cielo cala al 35%; la lampada del robot è più forte e calda, e i nemici svegli hanno una luce rossa;
  - la cima dei massicci è roccia nuda con poche crepe; l'arco di luce del bioma incornicia l'imbocco;
  - i nemici che dormono, gli oggetti a terra, le etichette e i fuochi stanno sul pavimento del loro piano.
- **Ologramma:** in grotta toglie la roccia del suo massiccio e mostra le stanze; le altre grotte restano
  chiuse. Gli imbocchi trovati hanno un segno nel loro punto.
- **Smoke:** gli stage delle grotte (87–98) entrano, escono e rientrano camminando nei quattro biomi, e
  controllano che la mappa non cambi; `ODIN_PP_SMOKE_ONLY=caves` parte da lì; lo stage nuovo 103 fotografa
  l'ologramma nella grotta della montagna (in fondo, per non cambiare il numero degli altri).

**Scelte prese durante la fase**
- **Posti prima dei rilievi:** con i rilievi di oggi un'area piana di 42×24 non c'era quasi mai; ora sono i
  rilievi a spianare il terreno attorno ai massicci.
- **Margini più stretti:** il massiccio può stare a una casella dalla cornice di un luogo, a 4 dai punti
  delle pattuglie e a 12 dalla partenza. Con i margini di prima le grotte entravano in due biomi su quattro.
- **Lava sotto la roccia:** nell'Inferno le strisce di lava passano sotto i massicci; conta solo che davanti
  all'imbocco il terreno sia sicuro.
- **Retino continuo:** l'apertura sopra il robot si calcola per frammento, non per casella, così è rotonda e
  senza scalini; i coperchi traslucidi del laboratorio non si usano nelle spedizioni.
- **Disegno in base all'altezza vera:** oggetti a terra, etichette e fuochi ora stanno sulla quota della loro
  casella anche sulle colline, dove prima restavano a quota zero.

**Verifiche**
- `odin check src -vet -strict-style`, con e senza assert: puliti.
- `.\scripts\check.ps1` completo: **1692 test verdi** con e senza assert (erano 1688), più le due build.
  - I test delle grotte sono riscritti per il modello nuovo: 8 al posto dei 7 di prima. Ce n'è uno nuovo nel
    livello (la tavola piccola del Far West) e due nel disegno (stanze, imbocco aperto, figure sul loro piano).
  - Sono adattati i test che non sapevano dei massicci (rilievi, raggiungibilità, oggetti sparsi, pavimento,
    archi dei luoghi, strutture). Quelli dei salvataggi vecchi ora controllano il rifiuto.
- **Smoke del laboratorio** completo: le 120 catture sono identiche al byte a quelle della Fase 4.
- **Smoke delle spedizioni** completo: 104 catture (le 103 di prima più l'ologramma in grotta), nessun errore.
  Nelle quattro grotte si entra, si esce e si rientra camminando, e la mappa non cambia. Guardate le catture:
  l'imbocco con l'arco di luce, le stanze attraverso la roccia diradata, i nemici, l'ologramma.
- **Benchmark** sulla RTX 3060, alla corrente, due misure concordi (1,9% di scarto medio): media dei gruppi
  **+6,1%** rispetto alla Fase 4, dentro il +10% concesso.

  | Gruppo | Fase 4 (ms) | Fase 5 (ms) | Differenza |
  |---|---:|---:|---:|
  | Viste di base (0–6) | 1,81 | 1,84 | +1,6% |
  | Biomi (7–18) | 1,49 | 1,50 | +0,5% |
  | Luoghi e viste speciali (19–24) | 1,95 | 1,93 | −0,8% |
  | Corsa e ingaggio (25–26) | 1,46 | 1,47 | +0,2% |
  | Centro dei biomi (27–38) | 1,14 | 1,17 | +2,5% |
  | Officine (39–50) | 1,18 | 1,20 | +2,1% |
  | Bersagli (51–54) | 1,20 | 1,29 | +7,5% |
  | Edifici (55–62) | 0,99 | 1,01 | +1,9% |
  | Rilievi (63–74) | 1,10 | 1,11 | +0,8% |
  | Ologrammi del rilievo (75–77) | 4,10 | 4,16 | +1,5% |
  | Scontro su due livelli (78) | 1,14 | 1,56 | +37,5% |
  | Montagna (79–86) | 1,05 | 1,10 | +4,2% |
  | Grotte (87–98) | 0,93 | 1,11 | +19,5% |
  | Posa delle strutture (99–102) | 1,01 | 1,07 | +6,2% |

  - **Grotte, +19,5%:** prima erano una mappa piccola e piatta; ora sono la mappa intera, con massiccio,
    stanze, retino e luci.
  - **Scontro su due livelli, +37,5%:** la Neve ha cambiato geografia e lo stage inquadra un altro posto, con
    un massiccio e un luogo grande in vista. Una prova di controllo con lo stesso codice ma senza grotte dà
    1,12 ms contro 1,13 della Fase 4: il codice nuovo, da solo, non costa niente. Il resto è la mappa a piani
    e la scena diversa; i costi fissi dei piani sono già ridotti (tabella delle colonne con piani, strato sotto
    solo vicino al robot fuori dalle grotte).
  - **Stage nuovo 103** (ologramma in grotta): 4,57 ms, come gli altri ologrammi.

**Non fatto, per le fasi dopo**
- Gli interni delle grotte già visitate nell'ologramma, il piano sopra e gli accessi: Fase 8.
- Restano nel codice l'arco di roccia dei luoghi (`site_cell`, caso `.Cave`) e `level.cave_stamp`, che nessun
  gioco usa più: da togliere nella Fase 8. Anche il codice delle mappe piccole di prima (80, 96, 112) non
  serve più, perché quei salvataggi sono rifiutati.
- Ponti, gallerie e scorciatoie: Fase 7.

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

Con le risposte dell'utente nella Fase 6: un programma a parte, i ritocchi in
PNG, niente angoli scolpiti uno per uno, i pennelli del progetto più rampa,
copia e incolla e rumore.

- **Editor, un programma a parte** (scelta dell'utente, non il consigliato):
  - si apre con `odin_pp --editor-mappe` e sceglie fra le arene della Prova
    meccaniche e le mappe dei biomi;
  - piano attivo: i quattro piani (sotto profondo, sotto, terra, sopra);
  - pennelli: alza e abbassa di un gradino, leviga, appiattisci, dipingi il
    tipo di casella (pavimento, roccia, vuoto, recinto); in più, scelta
    dell'utente, la rampa fra due punti, copia e incolla, il rumore;
  - si scolpiscono le caselle; gli angoli si ricavano come oggi (sezione 2.3);
  - grandezza del pennello, annulla e ripeti, salva, ricarica;
  - una telecamera che ruota e fa zoom, solo nell'editor: le spedizioni
    restano a telecamera fissa.
- **Ritocchi:** PNG in `assets/mappe/`, due per piano: le altezze in grigio e
  i tipi a colori, trasparenti dove la mappa è come la genera il codice. Sono
  anche il formato per dipingere fuori dal gioco: l'editor li ricarica.
- **Mappe dei biomi:** l'editor apre la mappa generata di un bioma e ne salva
  i ritocchi. `generate` li applica dopo la geografia (rilievi, montagna,
  strutture, massicci e grotte) e prima di nemici e segreti delle grotte e
  degli altri abitanti. Il file fa parte del bioma, non della run: la
  geografia resta fissa.
- **Arene:** la Prova meccaniche applica i ritocchi della sua arena, se ci
  sono.
- **Controlli al salvataggio:** ogni luogo raggiungibile, colonne valide, zone
  dei luoghi e partenza in piano. Gli errori si vedono in rosso e il
  salvataggio aspetta che siano a posto.

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

1. Pennelli e piano attivo, annulla e ripeti, con test delle funzioni pure.
2. File dei ritocchi: PNG per piano, scrittura e lettura, con test di andata
   e ritorno.
3. Applicazione dei ritocchi: arene della Prova meccaniche e `generate`.
4. Controlli al salvataggio.
5. Programma `--editor-mappe`: vista, telecamera, pennelli, interfaccia.
6. Smoke dell'editor (`--smoke-editor-mappe`): una collina alzata, levigata,
   salvata in una cartella di prova e riaperta, con le catture.
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

**Fatta il 26 ottobre 2026** sul ramo `piano-profondita`.

**Risposte dell'utente**
1. **Dove:** un programma a parte, `--editor-mappe` (non il consigliato).
2. **Formato:** PNG per piano: le altezze in grigio e i tipi a colori, trasparenti dove la mappa resta del
   codice.
3. **Angoli:** no, si scolpiscono solo le caselle e gli angoli si ricavano.
4. **Pennelli:** quelli del progetto e anche gli altri proposti: rampa fra due punti, copia e incolla, rumore.

**Il codice citato** c'era ancora tutto.

**Cosa è stato fatto**
- **Pennelli** (`src/level/sculpt.odin`): funzioni pure sulle caselle e sulle altezze di un piano.
  - Alza e abbassa; leviga (la media con le vicine, dalle altezze di prima della passata); appiattisci;
    dipingi; rampa; copia e incolla; rumore (un gradino su, giù o niente, da un hash fisso di casella e
    passata).
  - Ogni passata tiene, per ogni casella, com'era prima e com'è dopo: si annulla e si rifà intera
    (`Sculpt_History`). Una passata che non cambia niente non resta.
- **Ritocchi** (`src/level/map_edits.odin`): la differenza fra la mappa scolpita e quella del codice, casella per
  casella e piano per piano (tipo, altezza o entrambi). `map_edits_apply` li mette sulla mappa del codice; rifiuta
  quelli di un'altra grandezza o con un tipo che non esiste.
- **File** (`src/mapeditor/files.odin`): due PNG per piano ritoccato, in `assets/mappe/laboratorio/<arena>/` e
  `assets/mappe/biomi/<bioma>/`. Il gioco li legge all'avvio (`load_all`), in ogni modo; senza file non cambia
  niente.
- **Applicazione:**
  - la Prova meccaniche mette i ritocchi della sua arena su `mechanics_lab_level`;
  - `generate` li mette sulla mappa del bioma dopo rilievi, montagna, strutture e grotte, e prima degli abitanti.
    Per questo il contenuto delle grotte (nemici e segreto) ora si mette dopo (`fill_caves`), e solo su caselle
    che hanno ancora un pavimento;
  - un file dipinto a mano che rompe la regola dei piani resta fuori intero, con un avviso
    (`map_edits_apply_checked`); l'editor invece lo apre, per mostrarne gli errori;
  - una spedizione salvata tiene la sua mappa: i ritocchi nuovi valgono dalla spedizione dopo.
- **Controlli** (`src/mapeditor/checks.odin`):
  - in ogni mappa: le colonne dei piani (`level.check_layers`) e la partenza calpestabile;
  - nei biomi, anche: la partenza in piano (±8 caselle) e i luoghi in piano nella loro cornice. Dalla partenza si
    devono raggiungere i luoghi (entro 3 caselle), l'interno di ogni grotta e l'uscita (`level.layer_reach`: una
    visita che passa da un piano all'altro con le regole del passo);
  - le 18 mappe come le fa il codice li passano tutti.
- **Editor** (`src/mapeditor/`): una scena dell'host sopra il menu.
  - La telecamera ruota, si avvicina e si sposta.
  - La mappa è disegnata a blocchi di 16×16 caselle per piano, con la luce del gioco: la superficie scolpita a
    colori per tipo e piano, la roccia in blocchi, i dirupi. Un blocco si ricostruisce quando un pennello lo
    cambia; i piani sopra quello attivo sono trasparenti.
  - Il mouse sceglie la casella seguendo il raggio fino alla superficie del piano attivo.
- **Smoke** `--smoke-editor-mappe`, otto catture (`odin_pp_editor_*.png`):
  - l'arena piana; la collina alzata, levigata, salvata e riaperta uguale;
  - rampa, rumore, un pezzo copiato e incollato e un muro dipinto;
  - le grotte dell'Egitto sul piano «sotto»;
  - la partenza murata, con 23 errori e il salvataggio rifiutato;
  - **G** sul primo errore; poi l'annulla, e gli errori spariscono.

  Scrive solo in `build/editor_smoke/mappe`.

**Scelte prese durante la fase**
- **Partenza, uscita e porte restano del codice,** come gli edifici: un pennello ne cambia l'altezza, ma non le
  toglie e non ne fa di nuove, e i ritocchi fanno lo stesso. Il motivo: nella prima cattura dei pennelli c'era una
  seconda partenza, incollata con la collina.
- **Errori da trovare:** su una mappa grande gli errori lontani non si vedevano. Ora hanno un'asta rossa sopra la
  casella, e **G** porta la telecamera all'errore seguente, sul suo piano.
- **Modifiche non salvate:** Tab, F5 ed Esc vanno premuti due volte, entro i 6 secondi dell'avviso.
- **File dipinti fuori dall'editor:** il gioco controlla almeno la regola dei piani e, se è rotta, usa la mappa
  del codice; gli altri controlli (luoghi raggiungibili, zone in piano) sono solo dell'editor.
- **La mappa di base di un bioma** si fa con il seme 1. La geografia non dipende dal seme (lo dicono i test),
  quindi i ritocchi valgono per ogni run.

**Verifiche**
- `odin check src -vet -strict-style`, con e senza assert: puliti.
- `.\scripts\check.ps1` completo: **1707 test verdi** con e senza assert (erano 1692), più le due build. I test
  nuovi sono 15: 9 nel livello (pennelli, annulla, ritocchi, visita fra i piani, caselle del codice) e 6
  nell'editor (file andata e ritorno, ritocchi nel laboratorio e nei biomi, controlli, mappe aperte, mouse, mappe
  del codice senza errori).
- **Smoke del laboratorio** completo: le 120 catture sono identiche al byte a quelle della Fase 5.
- **Smoke delle spedizioni** completo: 104 catture, nessun errore.
  - Al byte ne restano uguali 26; le altre cambiano di 3–31 pixel attorno al robot, che si anima in tempo reale
    (misurate tre coppie).
  - Per provarlo, una sonda ha generato i 12 biomi con 3 semi, una volta con il codice della Fase 5 e una con
    questo: la mappa (tipi, altezze, piani) e il mondo (luoghi, strutture, grotte, gruppi, nemici, bottino) sono
    identici.
- **Smoke dell'editor:** otto catture, guardate una per una.
- **Benchmark:** non serve, perché il disegno del gioco non è cambiato (nessun file in `src/render`).

**Prova dell'editor, dopo la chiusura** (chiesta dall'utente, commit a parte)
- In questa sessione Claude non ha il controllo del desktop («computer use»), quindi non può cliccare nella finestra.
  Lo smoke ha una seconda parte (`src/mapeditor/smoke_input.odin`): l'editor usato con mouse e tasti simulati, un
  fotogramma alla volta, attraverso lo stesso codice dell'input vero (`editor_input`).
  - Sono 64 azioni: un pennello scelto con il suo tasto, un clic, il tasto tenuto e un trascinamento; annulla e
    ripeti; T che fa il giro dei tipi; copia trascinando e incolla; rampa, rumore, leviga e appiattisci; la
    telecamera girata, avvicinata e spostata; i piani; Ctrl+S; Tab con modifiche non salvate (avviso, poi cambio),
    ritorno, F5, G ed Esc due volte.
  - Quattro catture in più: il cursore del pennello, il rettangolo della copia, l'anteprima dell'incolla e l'arena
    salvata.
- **Prova completa:** i due PNG salvati dall'editor, messi per un momento in `assets/mappe`, sono stati letti dal gioco
  all'avvio. Nella prima cattura della Prova meccaniche il Viandante sta sulla collina scolpita. Poi la cartella è
  stata tolta.
- **Difetti trovati e corretti:**
  - il mouse non si fermava sulla cima dei blocchi di roccia: ora la scelta della casella conta l'altezza disegnata
    di roccia e recinti;
  - aprendo un'altra mappa restava il messaggio di quella di prima (per esempio un errore dell'Egitto sull'arena):
    ora si cancella;
  - nello smoke, i fotogrammi senza un punto scelto prendevano il mouse vero: ora il mouse simulato resta fuori dalla
    finestra, così lo smoke è uguale chiunque sia al computer.

**Non fatto, per le fasi dopo**
- Nessuna mappa è ancora ritoccata: `assets/mappe` non c'è. La Fase 7 userà l'editor per i biomi.
- Scale a pioli, edifici e luoghi non si mettono con i pennelli: restano del codice.

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

Con le risposte dell'utente nella Fase 7:
- i temi della tabella;
- tre biomi per volta, con uno stop dopo ogni gruppo per guardare insieme le
  catture;
- scorciatoie che si aprono dal lato giusto e si richiudono a ogni run (non il
  consigliato);
- **anche ascensori, da chiamare e aspettare** (non il consigliato: nella Fase 3
  c'erano solo le scale a pioli);
- il tunnel del Vietnam diventa una galleria percorribile;
- i ponti del Cielo restano come oggi (non il consigliato);
- accessi agli altopiani liberi, bioma per bioma (non il consigliato);
- il sotterraneo grande in Egitto e nel Gotico, con un pozzo;
- **complessi a tema, alti 14** (risposta all'inizio del primo gruppo di biomi): la regola dei piani vuole 12
  gradini fra due pavimenti della stessa colonna, e gli altopiani di oggi ne hanno 3 o 4. Così ogni bioma riceve 1
  o 2 complessi a posti fissi, come i massicci delle grotte: blocchi alti 14 gradini con ponti o passerelle sopra
  (piano +1), gallerie sotto (piano −1), scorciatoie con cancello e accessi (rampe, ascensori). Il resto del bioma
  resta com'è;
- **secondo gruppo (City pop, Egitto, Vietnam), risposte all'inizio del gruppo:**
  - **terreno alzato di una base:** i tre biomi si alzano tutti di 14 gradini; la superficie resta identica e si
    disegna come oggi (il disegno toglie la base). Sotto c'è posto per reti vere sul piano −2, alla quota 0: la
    metropolitana sotto le strade, il sotterraneo grande sotto il deserto, le gallerie del Vietnam. Il piano −1 resta
    per le grotte e le gallerie dei complessi, alla quota della base;
  - **la galleria del Vietnam** va dal tunnel di oggi, a sud, fino al punto d'arrivo del teletrasporto, in alto a
    destra, con qualche botola laterale; il salto con E sparisce;
  - **accessi:** scale che scendono dalla strada o dalla sabbia (una rampa in una buca) e, in un punto per bioma, il
    pozzo con l'ascensore.
- **terzo gruppo (Neve, Inferno, Gotico), risposte date alla fine del secondo** (l'utente ha chiesto le domande prima,
  per fare il terzo gruppo subito dopo il secondo, senza fermarsi):
  - **Neve, il crepaccio scavato:** la Neve si alza di una base come i biomi del secondo gruppo, e la superficie si vede
    uguale. Il crepaccio è una spaccatura profonda 14 nella neve: il ponte di corda lo attraversa alla quota del terreno
    (piano +1) e il fondo è la strada lunga, con scale, ascensore, guardie e segreto;
  - **Inferno, sopra un fiume di lava:** il terreno resta com'è. Un complesso alto 14 a cavallo di uno dei fiumi di lava
    di oggi: due rupi, il ponte di ossa sopra la lava (piano +1) e dentro le rupi le caverne di lava (piano −1), con
    cancello e ascensore. Sul ponte si passa senza toccare la lava;
  - **Gotico, cripta e catacombe:** il terreno si alza di una base come l'Egitto. Sul piano −2 la cripta grande sotto la
    collina e le catacombe che la uniscono al cimitero, con scale nelle tombe aperte e il pozzo con l'ascensore. Sopra,
    il ballatoio di una casa in rovina, con la scorciatoia;
  - **il killer del Gotico non scende:** resta in superficie, e sotto terra lo si semina.

**Temi:**

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
| Isola nel cielo | — | — (i ponti fra le isole restano come oggi, scelta dell'utente) |
| Spazio | gallerie nei crateri | passerelle della stazione |
| La memoria del creatore | dentro la collina del masso | — |

- **Interconnessioni:** almeno due strade per arrivare ai luoghi importanti
  (una sopra o sotto); grotte con più imbocchi; scorciatoie che evitano un giro
  lungo.
- **Accessi agli altopiani:** decisi bioma per bioma, senza una regola fissa
  (scelta dell'utente). L'idea della sezione 2.9 (pochi accessi, uno nascosto)
  resta disponibile dove serve.
- **Scorciatoie che si aprono dall'altra parte:** un cancello a sbarre (si vede
  attraverso, non si passa) che si apre solo con un passo contro le sbarre dalla
  parte della leva; dall'altra parte resta chiuso. Una volta aperto resta aperto
  fino alla fine della spedizione; ogni run lo trova chiuso (scelta
  dell'utente). Nella mappa è un recinto finché è chiuso, un pavimento quando è
  aperto.
- **Ascensore** (meccanica nuova, prima nella Prova meccaniche):
  - unisce due pavimenti della stessa colonna su due piani: un pozzo verso una
    sala sotto, o un dirupo, con in cima un pianerottolo sul piano sopra, a un
    passo dal bordo. Così la piattaforma va sempre su e giù in verticale;
  - la piattaforma sta a uno dei due capi. Chi prova a salire sul pianerottolo
    vuoto la **chiama** e la **aspetta**: viaggia a 8 gradini al secondo, 1,5
    secondi per piano;
  - ci si sale con un passo, e parte da sola: chi c'è sopra arriva all'altro
    capo dopo lo stesso viaggio e ne scende con un passo;
  - tutto con i passi, senza tasti nuovi: in combattimento E è già della
    diagonale e della schivata;
  - la usano anche i nemici, con le stesse regole: la chiamano, la aspettano,
    ci salgono;
  - in combattimento il viaggio dura il suo tempo come ogni altra azione;
    durante il viaggio chi c'è sopra non agisce e non si colpisce (è nel
    pozzo). È uno stato nuovo: chi sale una scala, oggi, fa un passo e basta;
  - una sola piattaforma per pozzo, con al massimo una figura sopra.
- **Sotterraneo grande** in alcuni biomi (Egitto, Gotico): non solo grotte
  dentro le colline, ma zone ampie sotto il suolo, anche sul piano −2,
  raggiunte da un pozzo con l'ascensore, come i fiumi sotterranei di Elden Ring. Per farle, il bioma alza
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

1. **Ascensore nella Prova meccaniche:**
   - dati nel livello e regole nel gioco: chiamata, attesa, viaggio, nemici,
     combattimento;
   - disegno: pozzo, piattaforma, cavi;
   - un'arena o un tratto dell'arena «Piani», l'atto `lift` dello smoke e i
     test.
2. **Biomi a gruppi di tre**, nell'ordine dei biomi:
   - piani, imbocchi, accessi agli altopiani e scorciatoie, con test di
     geografia fissa, di raggiungibilità e delle scorciatoie che si richiudono
     a ogni run;
   - catture di ogni bioma (esplorazione e uno scontro fra piani), con il
     pulsante «TEST tutti i biomi»;
   - **stop dopo ogni gruppo** per guardare le catture con l'utente.

   I gruppi: Robotica, Far West, Giungla; City pop, Egitto, Vietnam; Neve,
   Inferno, Gotico; Cielo, Spazio, Memoria.
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

In corso.

**Avanzamento**
- **Passo 1, ascensore e cancello nella Prova meccaniche** (26 ottobre 2026): fatto, e fermo per guardare le
  catture con l'utente prima dei biomi.
  - Dati (`level.Lift`, `level.Gate`), regole (`src/game/lift.odin`), disegno (`src/render/lift_view.odin`),
    arena «Ascensori», atto `lift` con otto catture, test.
  - **Scelte prese:**
    - tutto con i passi, perché in combattimento E è già della diagonale e della schivata;
    - ogni ascensore va su e giù nella sua colonna: in cima al dirupo un pianerottolo sul piano sopra, così la
      piattaforma sale in verticale e chi c'è sopra non cambia colonna;
    - chi viaggia è fuori gioco, come il nemico del Lazzo: il codice non aveva uno stato «in salita» per le scale;
    - il cancello chiuso è un recinto (si vede attraverso), aperto un pavimento: a ogni run la mappa nuova lo ha
      chiuso, e il salvataggio della spedizione lo tiene com'è.
  - **Per i biomi:** ascensori e cancelli non sono ancora nei salvataggi delle spedizioni, né nel loro disegno.
    Servono quando arrivano in un bioma (Egitto e Gotico per i pozzi).
  - **Verifiche:**
    - check con e senza assert; `.\scripts\check.ps1` completo: 1715 test verdi (8 nuovi), più le due build;
    - smoke del laboratorio: le 120 catture di prima identiche al byte, più le 8 dell'atto `lift`;
    - smoke delle spedizioni (104 catture, nessun errore) e dell'editor (12 catture);
    - benchmark sulla RTX 3060, alla corrente: media dei gruppi +0,8% rispetto alla Fase 5, il peggiore +2,2%
      (rumore).
  - **Correzione prima della prova dell'utente:** fuori dal combattimento (l'arena liberata con F7, una spedizione
    esplorata) le piattaforme non andavano avanti, e chi ci era salito restava fermo. Ora vanno con il tempo del
    fotogramma (`step_tactical_controller`), con un test d'integrazione; 1716 test verdi.
  - **Crash trovato dall'utente nell'arena «Ascensori»** (con i nemici liberi, prima ancora di usare un
    ascensore): il nemico della sala arrivava in cima al pozzo senza intenzione, e il turno dei nemici dopo si
    fermava su un'asserzione (`validate_enemy_intent_structure`). Ora all'arrivo il nemico ripianifica, come
    quello che il Lazzo lascia andare. Lo smoke non lo vedeva perché teneva fermi i nemici.
    - Riprodotto con una sonda senza finestra: l'arena come nel gioco, con il controller tattico, i nemici liberi
      e gli arrivi.
    - Test d'integrazione nuovo: un minuto di partita nell'arena, con i nemici liberi. Senza la correzione si
      ferma sulla stessa asserzione.
    - Sonda mirata, sei semi: il robot prende i due ascensori e apre il cancello mentre i nemici, liberi, usano
      gli stessi ascensori. Nessun errore.
  - **Seconda prova dell'utente: il robot non saliva con la piattaforma.** La figura restava a terra durante e
    dopo il viaggio, e nel sotterraneo restava disegnata sopra il terreno mentre il corpo era sotto.
    - La causa è un difetto che c'era dalla Fase 3: `entity_point_ground` prendeva `Entity_Ref{}` per «nessuna
      figura», ma `{}` è il robot (`game.PLAYER_ENTITY`). Così il robot veniva disegnato sempre all'altezza del
      terreno di terra: sotto il ponte su cui stava, e sopra il massiccio quando era in una grotta.
    - Ora «nessuna figura» è `NO_FIGURE` (il riferimento di sistema), e il robot è disegnato sul suo piano e,
      in ascensore, sulla piattaforma.
    - Cambiano le catture con il robot fuori dal piano di terra: il ponte e la grotta dell'atto dei piani, le
      grotte delle spedizioni (il robot ora sta nella stanza). In più la telecamera segue la sua altezza vera.
    - Due test nuovi nel disegno (il robot sul ponte, il robot a metà viaggio) e una cattura in più nell'atto
      `lift` (l'arrivo in cima); 1719 test verdi.
    - Smoke completi rifatti dopo la correzione:
      - laboratorio: 118 catture identiche al byte, 10 cambiate e 1 nuova. Le cambiate sono quelle col robot
        fuori dal piano di terra: il ponte e la grotta dell'atto dei piani, e l'atto degli ascensori. Nella grotta
        il robot ora sta accanto al nemico, invece di fluttuare all'altezza della collina;
      - spedizioni: 104 catture, nessun errore. Cambiano le grotte, col robot nella stanza invece che sopra il
        massiccio; le altre differenze sono l'animazione.
    - Benchmark sulla RTX 3060, alla corrente: −0,3% rispetto al passo precedente, +0,5% rispetto alla Fase 5
      (rumore).
- **Passo 2, primo gruppo di biomi: Robotica cibernetica, Far West, Giungla preistorica** (26 ottobre 2026): fatto, e
  fermo per guardare le catture con l'utente prima del secondo gruppo.
  - **Domanda nuova all'inizio del gruppo.** La regola dei piani vuole 12 gradini fra due pavimenti della stessa
    colonna, e gli altopiani di oggi ne hanno 3 o 4. L'utente ha scelto i **complessi a tema, alti 14** (vedi
    «Progetto»): il resto dei biomi resta com'è.
  - **I complessi** (`src/expedition/complex.odin`, una mappa ASCII per tipo, a un posto fisso per bioma):
    - Robotica: due piattaforme dati con una passerella; sotto quella col segreto un condotto, con il cancello
      all'imbocco (leva dentro) e un pozzo con l'ascensore fino in cima. Si sale a piedi dalla rampa dell'altra.
    - Far West: il ponte del treno fra due mese; la mesa col segreto ha un ascensore lungo il fianco, con un cancello
      in cima aperto dalla mesa. Si sale a piedi dal sentiero dell'altra. La miniera resta la grotta di prima.
    - Giungla: la collina delle ossa con la caverna sotto (due imbocchi, le guardie dentro), due alberi giganti con
      ponti di liane; il cancello sul secondo ponte si apre dal primo albero (il segreto), il secondo ha l'ascensore.
    - In ogni complesso il luogo importante ha due strade: quella lunga, a piedi, e la scorciatoia, che si apre solo
      dall'altra parte e si richiude a ogni run. Le guardie sono un gruppo del bioma.
  - **Scelte prese:**
    - i posti si cercano come quelli delle grotte, prima dei rilievi. Le zone dei siti coprono quasi tutta la mappa:
      il complesso non tocca la pianta di un sito (prima chiedevo 4 caselle in più, e non c'era posto), e quello del
      Far West è largo 38 per stare fra le grotte;
    - ascensori e cancelli nel salvataggio stanno nel mondo; le piattaforme ferme nello snapshot; mentre una
      piattaforma porta qualcuno non si salva;
    - i ponti hanno un passaggio di disegno loro (`render/expedition_decks.odin`), con il programma «tall» quando
      sono in vista, per diradarli sopra gli occhi del robot; `EXPEDITION_TERRAIN_TALL` passa da 16 a 14 gradini;
    - i nemici che dormono sotto terra non si disegnano dove la roccia li nasconde: la testa di quelli nella caverna
      della Giungla spuntava dalla collina, alta solo 14.
  - **Test:** i test di raggiungibilità dei biomi ora usano `level.layer_reach` (piani, ponti, ascensori); il Far West,
    Robotica e Giungla hanno piani anche senza grotte; due test contavano i drop dal primo, e Robotica ha ora il
    segreto del complesso.
    - Nuovi: complessi fissi a ogni run, tutto raggiungibile con i cancelli chiusi (e i due lati di ogni cancello),
      salvataggio di cancello e piattaforma, ascensore e cancello camminando liberi; nel pacchetto integration un
      minuto di scontro con le guardie libere in ogni complesso e un nemico libero che chiama l'ascensore e sale dietro
      al robot.
  - **Verifiche:**
    - check con e senza assert; `.\scripts\check.ps1` completo: 1725 test verdi (6 nuovi), più le due build;
    - smoke del laboratorio: 128 catture identiche al byte e una con 22 pixel diversi di poco
      (`structures_hut_6`, una variante già uscita in un giro di prima). L'atto delle strutture da solo dà catture
      identiche al byte con il codice di prima e con quello nuovo: dipende dallo stato del giro, non dal codice;
    - smoke delle spedizioni: 122 catture, nessun errore. Cambiano davvero i tre rilievi di Robotica, Far West e
      Giungla (il punto più irregolare ora è il complesso); camminata e ingaggio cambiano a ogni giro; le altre
      differenze sono sotto l'1%, attorno al robot (animazione). 18 catture nuove dei complessi;
    - smoke dell'editor: 12 catture, nessun errore;
    - benchmark: il primo giro, a batteria, non valeva (la RTX 3060 bloccata a 30 fotogrammi al secondo, poi la
      grafica Intel). Rifatto alla corrente, su richiesta dell'utente, due giri prima e due dopo alternati: media dei
      gruppi +0,4%, peggiore +2,8% (lo scontro su due livelli, uno stage solo: rumore). Gli stage dei complessi
      costano 1,11 ms di media, come le grotte (1,12 ms).
- **Passo 2, secondo gruppo di biomi: City pop, Egitto, Vietnam** (26 ottobre 2026): fatto. L'utente ha dato prima le
  risposte del terzo gruppo, per farlo subito dopo: le catture dei due gruppi si guardano insieme alla fine del terzo.
  - **Domande all'inizio del gruppo** (risposte nel «Progetto»): metropolitana, sotterraneo grande e gallerie sono reti
    lunghe, e sotto il terreno alto 0 non c'è posto. L'utente ha scelto di **alzare il terreno dei tre biomi di una
    base**, la galleria del Vietnam **fino all'arrivo del tunnel di oggi** e gli accessi con **scale e un ascensore**.
  - **La base** (`level.Level.base`, `World.base`): le regole contano le quote da 0 come prima; il disegno toglie la base
    dappertutto (`board_drawn`), così la superficie dei tre biomi si vede uguale. Verificato con lo smoke: le catture di
    City pop, Egitto e Vietnam sono uguali a prima, salvo l'animazione del robot (meno dello 0,02% dei pixel).
  - **Le reti** (`src/expedition/network.odin`) sul piano −2 alla quota 0: la metro di City pop (tre stazioni), la
    necropoli dell'Egitto (grande sala, tomba, sala sotto la piramide), le gallerie del Vietnam (dal tunnel di oggi
    all'arrivo, sei camere, quattro botole). Un ascensore per bioma (in Egitto il pozzo dalla cima della piramide), un
    cancello che si apre da una parte sola, nemici e segreto.
  - **I complessi:** tetti e cavalcavia (City pop), piramidi a gradoni (Egitto), ponte di bambù sul fiume (Vietnam).
  - **Scelte prese durante il lavoro:**
    - le reti stanno sul piano −2, non −1: così passano anche sotto le grotte e le gallerie dei complessi, che sono
      sul −1 alla quota della base;
    - una rete non passa mai sotto un muro o una decorazione: per la regola delle colonne (`level.column_of`) sotto un
      muro c'è roccia piena, e il robot lì non risultava «sotto una volta» (niente dissolvenza, niente finestra).
      Le vie girano attorno con una ricerca in ampiezza; le sale tengono solo le caselle collegate al centro;
    - le scale si cercano attorno alla sala e si collegano con la stessa via: le stazioni stanno spesso dentro un
      luogo, con il muro di cinta, e una scala dritta non ne usciva. La stazione a sud-est della metro è in un incrocio
      libero (74%, 59%);
    - nelle buche delle scale la finestra attorno al robot non c'è: tagliava la rampa e sotto si vedeva il vuoto nero;
      sotto terra invece è più larga, per tagliare anche gli edifici e i luoghi sopra;
    - il tunnel del Vietnam non si usa più con E (come l'imbocco di una grotta): si scende dalle scale accanto;
    - **la telecamera dopo un salto** (`update_tactical_view`): sui piani la quota della telecamera va verso quella del
      robot un po' alla volta, e lo faceva anche quando la telecamera salta (una mappa nuova, il robot messo altrove),
      partendo dalla quota di prima. Ora in un salto prende subito la quota del robot, come già la posizione. L'ha
      mostrato lo smoke: con il Vietnam a piani, una cattura della Neve usciva inquadrata con la quota dello stage prima.
  - **Test:** i rilievi contano le quote dalla base. Nuovi: le reti nei tre biomi, segreto e nemici raggiungibili, la
    galleria del Vietnam dal tunnel all'arrivo, la base nel salvataggio, la telecamera che salta di piano; le prove con i
    nemici liberi girano nei sei complessi. Via il test del salto con E.
  - **Verifiche:**
    - check con e senza assert; `.\scripts\check.ps1` completo: 1729 test verdi (5 nuovi, uno tolto), più le due build;
    - smoke del laboratorio: le 129 catture identiche al byte a quelle del primo gruppo;
    - smoke delle spedizioni: 149 catture, nessun errore. City pop, Egitto e Vietnam si vedono come prima (meno dello
      0,02% dei pixel diversi, l'animazione del robot); 18 catture nuove dei complessi e 9 delle reti. Con la telecamera
      corretta cambiano le catture fatte dopo un salto di piano (montagna, imbocchi delle grotte, panorami dei complessi,
      quattro rilievi, il ponte del Far West): stessa scena, con il robot al centro;
    - smoke dell'editor: 12 catture, nessun errore;
    - benchmark sulla RTX 3060, alla corrente, tre giri per parte: lo stesso eseguibile al giro dopo esce più lento del
      3-5% (si scalda), quindi conta il confronto in ordine bilanciato (vecchio, nuovo, nuovo, vecchio). Media dei gruppi
      +2,0%, dentro il rumore. Costano davvero di più solo i centri di City pop (+13,5%, 0,15 ms) e dell'Egitto (+10,2%,
      0,11 ms), con la stessa immagine: lì la rete passa sotto la vista, e i blocchi sotterranei attorno al robot si
      mandano alla scheda a ogni fotogramma, come il terreno (la Fase 8 li carica una volta sola). In Vietnam, con le
      gallerie lontane dal centro, non cambia niente. Gli stage dei complessi costano 1,23 ms di media, quelli delle reti
      1,21 ms, le grotte 1,14 ms.

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
- **Grotte vecchie:** nella Fase 5 l'utente ha scelto di rifiutare i
  salvataggi vecchi senza convertirli, quindi `Outer_Map`, `enter_cave`,
  `exit_cave` e la dissolvenza spariscono già lì. Restano da guardare gli
  avanzi: l'arco di roccia dei luoghi (`site_cell`, caso `.Cave`) e
  `cave_stamp`, se nessuno li usa più.

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
| Il rilassamento dei rilievi limita solo le quattro vicine dritte: due vicine in diagonale possono stare a due gradini e bloccare una diagonale dove la strada dritta va bene. | `relax`, `src/expedition/relief.odin:329` | 3 (spostata dalla 1: riguarda il passo, non la grafica; a schermo la superficie è liscia anche lì) |
| I bordi degli edifici diradati non sfumano: l'alfa sembra perdersi nel disegno dei bordi. | `src/render/expedition_edges.odin` | 4 |
| Nell'ologramma delle stanze i personaggi potrebbero galleggiare sulle mappe con altezze. | `src/render/hologram.odin` | 8 |
| Il campo `covered` dei blocchi del terreno non era letto da nessuno: tolto. | `src/render/expedition_terrain.odin` | 1 (fatta) |
| La sfera di taglio per casella sta a quota fissa 0,65: il piano della griglia voleva allargarla, ma non è stato fatto. | `tactical_cell_on_screen`, `src/render/tactical_framing.odin` | 5 (spostata dalla 1: con i piani il taglio va rivisto comunque) |
| Entrando in grotta, trappole, oggetti, pozze, fuochi e ostacoli della stanza non vengono messi da parte. | `enter_cave`, `src/expedition/cave.odin:221` | 5 (sparisce con le grotte a piani) |
| Il benchmark non arrivava a rilievi, montagna e grotte: risolto. | `src/application/campaign_smoke.odin` | 0 (fatta) |
| Il gioco disegnava con la scheda Intel integrata anche dove c'è una scheda dedicata: risolto. | `src/windows_gpu.odin` | 0 (fatta) |

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

## Appendice A — Misure di partenza, stage per stage

Fase 0, 25 ottobre 2026: build `-o:speed`, canvas 1920×1080, NVIDIA GeForce RTX
3060 Laptop GPU, portatile alla corrente. Millisecondi per frame presentato
(non tempi GPU), due giri A e B da 120 campioni per stage (240 per corsa e
ingaggio). La macchina e il modo di leggerle sono nell'esito della Fase 0.

| Stage | Scena | Media A | Media B | Mediana A | Mediana B | p95 A | p95 B |
|---:|---|---:|---:|---:|---:|---:|---:|
| 0 | bioma | 1,46 | 1,30 | 1,16 | 1,12 | 2,26 | 2,03 |
| 1 | ologramma | 3,29 | 3,37 | 3,27 | 3,33 | 3,61 | 3,67 |
| 2 | mount | 1,29 | 1,33 | 1,10 | 1,10 | 1,96 | 2,01 |
| 3 | zaino | 1,44 | 1,45 | 1,48 | 1,48 | 1,80 | 1,86 |
| 4 | personaggio | 1,39 | 1,40 | 1,21 | 1,21 | 1,98 | 2,02 |
| 5 | scontro | 1,75 | 1,73 | 1,75 | 1,73 | 1,97 | 1,91 |
| 6 | tana | 1,53 | 1,53 | 1,24 | 1,23 | 2,23 | 2,22 |
| 7 | bioma, Cyber | 1,68 | 1,68 | 1,37 | 1,42 | 2,35 | 2,33 |
| 8 | bioma, Far West | 1,59 | 1,62 | 1,41 | 1,21 | 2,41 | 2,42 |
| 9 | bioma, Giungla | 1,42 | 1,42 | 1,42 | 1,42 | 1,48 | 1,48 |
| 10 | bioma, City pop | 1,44 | 1,42 | 1,42 | 1,41 | 1,51 | 1,50 |
| 11 | bioma, Egitto | 1,43 | 1,43 | 1,43 | 1,44 | 1,48 | 1,47 |
| 12 | bioma, Vietnam | 1,19 | 1,17 | 1,08 | 1,08 | 1,72 | 1,73 |
| 13 | bioma, Neve | 1,35 | 1,35 | 1,36 | 1,36 | 1,42 | 1,42 |
| 14 | bioma, Inferno | 1,48 | 1,46 | 1,48 | 1,46 | 1,54 | 1,53 |
| 15 | bioma, Gotico | 1,27 | 1,26 | 1,15 | 1,12 | 1,79 | 1,82 |
| 16 | bioma, Cielo | 1,54 | 1,53 | 1,54 | 1,53 | 1,60 | 1,59 |
| 17 | bioma, Spazio | 1,50 | 1,50 | 1,49 | 1,48 | 1,56 | 1,61 |
| 18 | bioma, Segreto | 1,42 | 1,42 | 1,43 | 1,42 | 1,48 | 1,50 |
| 19 | luogo 0 | 1,45 | 1,46 | 1,45 | 1,46 | 1,50 | 1,51 |
| 20 | luogo 1 | 1,66 | 1,68 | 1,65 | 1,66 | 1,78 | 1,88 |
| 21 | luogo 2 | 1,43 | 1,44 | 1,43 | 1,43 | 1,48 | 1,48 |
| 22 | luogo 3 | 1,35 | 1,35 | 1,34 | 1,34 | 1,49 | 1,45 |
| 23 | ologramma grande | 3,73 | 3,83 | 3,72 | 3,80 | 3,94 | 4,02 |
| 24 | dietro un muro | 1,52 | 1,52 | 1,53 | 1,53 | 1,59 | 1,58 |
| 25 | camminata | 1,46 | 1,47 | 1,46 | 1,47 | 1,56 | 1,60 |
| 26 | ingaggio | 1,39 | 1,39 | 1,38 | 1,37 | 1,52 | 1,55 |
| 27 | centro, Cyber | 1,08 | 1,05 | 1,05 | 1,01 | 1,29 | 1,23 |
| 28 | centro, Far West | 1,00 | 1,00 | 0,98 | 0,96 | 1,17 | 1,24 |
| 29 | centro, Giungla | 0,96 | 0,98 | 0,93 | 0,96 | 1,19 | 1,26 |
| 30 | centro, City pop | 1,08 | 1,11 | 1,07 | 1,09 | 1,20 | 1,21 |
| 31 | centro, Egitto | 0,97 | 1,00 | 0,96 | 0,97 | 1,11 | 1,22 |
| 32 | centro, Vietnam | 1,01 | 1,05 | 0,89 | 0,98 | 1,49 | 1,50 |
| 33 | centro, Neve | 1,03 | 1,09 | 1,01 | 1,08 | 1,18 | 1,31 |
| 34 | centro, Inferno | 1,19 | 1,20 | 1,18 | 1,20 | 1,28 | 1,30 |
| 35 | centro, Gotico | 1,16 | 1,14 | 1,08 | 1,09 | 1,69 | 1,43 |
| 36 | centro, Cielo | 1,26 | 1,24 | 1,21 | 1,21 | 1,52 | 1,48 |
| 37 | centro, Spazio | 1,25 | 1,26 | 1,22 | 1,24 | 1,48 | 1,45 |
| 38 | centro, Segreto | 1,33 | 1,34 | 1,32 | 1,31 | 1,47 | 1,54 |
| 39 | officina, Cyber | 1,15 | 1,17 | 1,13 | 1,16 | 1,35 | 1,45 |
| 40 | officina, Far West | 1,09 | 1,09 | 1,09 | 1,08 | 1,18 | 1,13 |
| 41 | officina, Giungla | 1,22 | 1,20 | 1,21 | 1,20 | 1,31 | 1,31 |
| 42 | officina, City pop | 1,31 | 1,33 | 1,31 | 1,31 | 1,49 | 1,52 |
| 43 | officina, Egitto | 1,09 | 1,10 | 1,08 | 1,09 | 1,19 | 1,23 |
| 44 | officina, Vietnam | 1,09 | 1,13 | 0,99 | 1,08 | 1,64 | 1,59 |
| 45 | officina, Neve | 1,25 | 1,26 | 1,24 | 1,25 | 1,35 | 1,37 |
| 46 | officina, Inferno | 1,18 | 1,17 | 1,11 | 1,05 | 1,54 | 1,58 |
| 47 | officina, Gotico | 1,04 | 1,05 | 0,98 | 0,98 | 1,48 | 1,49 |
| 48 | officina, Cielo | 1,07 | 1,07 | 1,01 | 1,02 | 1,51 | 1,41 |
| 49 | officina, Spazio | 1,18 | 1,18 | 1,18 | 1,17 | 1,23 | 1,26 |
| 50 | officina, Segreto | 1,01 | 1,02 | 1,00 | 1,01 | 1,10 | 1,08 |
| 51 | bersagli, Neve | 1,22 | 1,17 | 1,18 | 1,17 | 1,48 | 1,27 |
| 52 | bersagli, Far West | 1,14 | 1,22 | 1,11 | 1,17 | 1,27 | 1,57 |
| 53 | bersagli, Giungla | 1,14 | 1,17 | 1,10 | 1,13 | 1,25 | 1,38 |
| 54 | bersagli, Spazio | 1,18 | 1,19 | 1,17 | 1,18 | 1,27 | 1,31 |
| 55 | edificio, 6 | 0,93 | 0,96 | 0,93 | 0,92 | 1,07 | 1,27 |
| 56 | edificio, 4 | 0,95 | 0,94 | 0,94 | 0,95 | 1,05 | 1,06 |
| 57 | edificio, 2 | 0,96 | 0,94 | 0,94 | 0,95 | 1,11 | 1,05 |
| 58 | edificio, 1 | 0,97 | 0,93 | 0,96 | 0,93 | 1,18 | 1,04 |
| 59 | edificio, soglia | 0,96 | 0,92 | 0,96 | 0,92 | 1,16 | 1,02 |
| 60 | edificio, dentro | 0,99 | 0,95 | 0,99 | 0,93 | 1,23 | 1,07 |
| 61 | edificio, fuori | 0,99 | 0,94 | 0,98 | 0,96 | 1,24 | 1,09 |
| 62 | edificio, oggetti | 0,98 | 1,00 | 0,93 | 0,88 | 1,36 | 1,41 |
| 63 | rilievo, Cyber | 0,89 | 0,97 | 0,88 | 0,95 | 0,99 | 1,24 |
| 64 | rilievo, Far West | 1,02 | 1,03 | 1,02 | 1,02 | 1,10 | 1,14 |
| 65 | rilievo, Giungla | 0,97 | 0,98 | 0,89 | 0,89 | 1,38 | 1,32 |
| 66 | rilievo, City pop | 0,93 | 0,92 | 0,89 | 0,91 | 1,20 | 1,12 |
| 67 | rilievo, Egitto | 0,99 | 0,99 | 0,93 | 0,91 | 1,33 | 1,38 |
| 68 | rilievo, Vietnam | 1,11 | 1,13 | 1,10 | 1,12 | 1,28 | 1,41 |
| 69 | rilievo, Neve | 0,95 | 0,97 | 0,93 | 0,95 | 1,18 | 1,23 |
| 70 | rilievo, Inferno | 1,17 | 1,18 | 1,17 | 1,18 | 1,25 | 1,26 |
| 71 | rilievo, Gotico | 0,98 | 1,01 | 0,94 | 0,93 | 1,42 | 1,46 |
| 72 | rilievo, Cielo | 1,13 | 1,14 | 1,10 | 1,12 | 1,31 | 1,34 |
| 73 | rilievo, Spazio | 1,25 | 1,26 | 1,23 | 1,24 | 1,43 | 1,44 |
| 74 | rilievo, Segreto | 1,30 | 1,32 | 1,29 | 1,31 | 1,41 | 1,45 |
| 75 | ologramma rilievo, Egitto | 4,29 | 4,42 | 4,28 | 4,40 | 4,55 | 4,68 |
| 76 | ologramma rilievo, Neve | 4,34 | 4,35 | 4,32 | 4,29 | 4,63 | 4,74 |
| 77 | ologramma rilievo, Cielo | 3,41 | 3,42 | 3,40 | 3,41 | 3,60 | 3,58 |
| 78 | scontro su due livelli | 1,07 | 1,14 | 1,01 | 1,06 | 1,65 | 1,63 |
| 79 | montagna 0 | 1,06 | 1,05 | 0,88 | 0,97 | 1,55 | 1,45 |
| 80 | montagna 1 | 1,06 | 1,06 | 0,92 | 0,95 | 1,52 | 1,45 |
| 81 | montagna 2 | 0,96 | 0,99 | 0,94 | 0,97 | 1,14 | 1,18 |
| 82 | montagna 3 | 1,01 | 1,01 | 0,94 | 0,92 | 1,40 | 1,49 |
| 83 | montagna 4 | 0,95 | 0,98 | 0,93 | 0,95 | 1,10 | 1,12 |
| 84 | montagna 5 | 1,00 | 0,99 | 0,94 | 0,95 | 1,43 | 1,41 |
| 85 | montagna 6 | 1,02 | 1,02 | 0,94 | 0,95 | 1,40 | 1,45 |
| 86 | montagna 7 | 1,00 | 1,02 | 0,92 | 0,93 | 1,43 | 1,44 |
| 87 | grotta, Neve, arco | 0,95 | 0,98 | 0,93 | 0,96 | 1,19 | 1,20 |
| 88 | grotta, Neve, ingresso | 0,85 | 0,87 | 0,83 | 0,86 | 0,94 | 0,97 |
| 89 | grotta, Neve, stanza | 0,86 | 0,85 | 0,85 | 0,84 | 0,92 | 0,96 |
| 90 | grotta, Far West, arco | 0,99 | 0,98 | 0,90 | 0,87 | 1,32 | 1,34 |
| 91 | grotta, Far West, ingresso | 0,71 | 0,79 | 0,68 | 0,75 | 0,89 | 1,08 |
| 92 | grotta, Far West, stanza | 0,72 | 0,79 | 0,68 | 0,73 | 1,03 | 1,05 |
| 93 | grotta, Egitto, arco | 0,97 | 0,97 | 0,95 | 0,94 | 1,22 | 1,23 |
| 94 | grotta, Egitto, ingresso | 0,85 | 0,88 | 0,84 | 0,84 | 0,93 | 1,15 |
| 95 | grotta, Egitto, stanza | 0,86 | 0,86 | 0,84 | 0,84 | 0,95 | 0,96 |
| 96 | grotta, Inferno, arco | 1,19 | 1,19 | 1,18 | 1,20 | 1,25 | 1,25 |
| 97 | grotta, Inferno, ingresso | 0,95 | 0,99 | 0,93 | 0,97 | 1,17 | 1,26 |
| 98 | grotta, Inferno, stanza | 0,97 | 0,99 | 0,96 | 0,97 | 1,26 | 1,22 |
| 99 | posa, fantasma verde | 0,99 | 0,98 | 0,93 | 0,92 | 1,39 | 1,39 |
| 100 | posa, fantasma rosso | 0,97 | 0,98 | 0,91 | 0,93 | 1,39 | 1,40 |
| 101 | posa, posata | 0,98 | 1,00 | 0,93 | 0,93 | 1,39 | 1,42 |
| 102 | posa, rotta | 1,01 | 1,01 | 0,96 | 0,95 | 1,38 | 1,41 |
