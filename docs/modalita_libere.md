[← Odin PP](../README.md)

## M9: fondazioni per le modalità libere

M9 aggiunge quattro incrementi giocabili alla base **0.4**: arena senza
griglia, ring con mosse e collisioni, una prova FPS e strumenti per sviluppare
questi contenuti. Non modifica pulse, cast, dadi, fog o regole del combattimento.

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
