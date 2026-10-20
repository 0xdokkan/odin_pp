[← Odin PP](../../README.md)

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
esaurire il risultato del dado. Con un **3**, fuori dal colpo a tempo, produce
quindi **3 scariche**, ognuna su **massimo 3 nemici** nell'area. Sul colpo a tempo
il bonus porta entrambi a 4: il pannello distingue tiro e risultato effettivo. Il danno è **1 per bersaglio** a ogni livello:
il dado non decide il danno e gli upgrade alzano soltanto il dado. Una pedana
tiene al massimo 21 scariche (un 20 del D20 più quella del
[colpo a tempo](combattimento.md#colpo-a-tempo)). Si preferiscono i nemici
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
trascorso durante le azioni; cast e dadi non accelerano la ricarica. La mega
combo con un campo valido consuma tutte e quattro le Tesla dopo la scarica,
liberando gli slot per una nuova rete. Quattro torri allineate o con campo
ostruito producono soltanto collegamenti e rimangono. Restano danneggiabili
(4 HP): la persistenza non conferisce invulnerabilità.

Preview, overlay e danno interrogano la stessa geometria in
[board_device.odin](../../src/game/board_device.odin). I dispositivi sono locali al
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
film di quella scelta ([Mostra effetto](../presentazione.md#mostra-effetto)). Il pulsante
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
in [M9](../modalita_libere.md#m9-fondazioni-per-le-modalità-libere).

La stanza rimane sospesa e il duello non consuma tempo della board. Le vite
entrano in proporzione: il giocatore porta nel ring la sua percentuale di vita
(su 8 HP), ogni nemico la propria su 12 HP da solo, 9/7/6 HP a testa in un tag
match da 2/3/4 (`ring_opponent_health` in [tag.odin](../../src/fight/tag.odin)).
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
