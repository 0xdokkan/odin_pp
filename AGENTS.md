# Istruzioni per gli agenti

Questo file vale per **ogni agente** che lavora su Odin PP: Codex, Jules, Cursor, Aider, Zed, Claude Code (che lo
legge attraverso `CLAUDE.md`) e gli altri. Le regole di lavoro complete stanno in [docs/sviluppo.md](docs/sviluppo.md)
e nei piani in `docs/`.

## La regola per sempre: la carta IA conosce tutto il gioco

Decisa dall'utente il 3 novembre 2026 (piano: [docs/piano-ia.md](docs/piano-ia.md), sezione «La regola per
sempre»). La carta «IA» consiglia sempre la mossa migliore, quindi deve conoscere **tutto** il gioco, sempre.

**Ogni volta che aggiungi o cambi qualcosa nel gioco**, su qualunque PC e con qualunque IA, **aggiorna anche la IA
nello stesso lavoro.** Conta tutto: una carta, un effetto, uno stato, un nemico, un oggetto della griglia, una
struttura, un tipo di casella o di terreno, un posto o un bioma della spedizione, un nodo della mappa della run, un
oggetto dello zaino, un comando del giocatore, una regola del combattimento.

Aggiornare la IA vuol dire:
1. la copia di prova (`src/advisor/`) copia anche lo stato nuovo;
2. la IA sa **usare** la cosa nuova: le sue mosse e i suoi bersagli buoni;
3. la IA sa **quanto vale**, anche oltre l'orizzonte della ricerca;
4. il **contesto** la conosce (`src/run/advisor_context.odin`): se cura e quanto, se è pericolosa, se conta per il
   progresso della run o della spedizione;
5. almeno una **situazione di prova** (un puzzle) nuova mostra che la IA la usa bene;
6. una riga in `docs/registro-carte.md` (o nel `CHANGELOG.md`, se non è una carta) dice «IA aggiornata».

Le cure che la IA conta sono tutte quelle vere, tranne la Canna da pesca e il Cibo pescato che dà.

**Il codice lo controlla.** Le tabelle della IA hanno una voce per ogni elenco del gioco, e una voce mancante non
compila. I test della IA falliscono se la copia di prova non conosce un campo nuovo, o se la copia e il gioco vero non
fanno la stessa cosa. **Non aggirare questi controlli** (niente `#partial` nelle tabelle della IA, niente voci finte,
niente test saltati): aggiorna la IA.

**Se nel ramo dove lavori la IA non c'è ancora** (le fasi del piano non sono ancora fatte o non sono ancora unite),
annota nel `CHANGELOG.md` che cosa hai aggiunto al gioco: la prossima fase della IA lo prende, e il controllo del
codice lo pretende comunque quando i rami si uniscono.
