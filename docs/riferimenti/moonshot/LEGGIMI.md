# Evidenze del piano moonshot — 4 novembre 2026

La raccolta contiene la ricerca preliminare e la successiva esecuzione locale della Fase 0.
Non sono i diciassette rapporti Windows citati nella richiesta: quelli restano da acquisire e confrontare.
Il riferimento è [piano-moonshot.md](../../piano-moonshot.md), sul commit base
`ddc6b186942d4c78597dc0f3f06c1a73483b716e`.

## Fase 0 eseguita sul Mac

- [Esito, strumenti, verifiche e limiti](fase0-risultati.md).
- [Riconciliazione delle evidenze](fase0-riconciliazione.md).
- [Generazione, memoria, snapshot e IA](fase0-headless.md).
- [Fotogrammi, tracciati e casi incompleti](fase0-grafica.md).
- [Risultati strutturati](fase0-results.json) e [prove grezze](fase0-prove.zip).

L'archivio contiene percorsi `build/...`: estrarlo nella radice di un clone per ripristinare i link ai log.
Include la sessione sandbox fallita, la serie nativa v1 e la validazione diagnostica v2 separate;
esclude binari e profili. Il [runner attuale](../../../tools/moonshot/README.md) riproduce il protocollo con
la correzione diagnostica v2. Per ricostruire la prima serie sono conservati anche il runner v1,
il driver v1, la patch e gli hash originali: non confondere le due revisioni dello strumento.

## Ricerca preliminare del piano

Tre rapporti indipendenti e un supplemento grafico, precedenti alla Fase 0:

- [Combattimento, mondo, strutture e IA](combat-world.md): ricognizione del codice.
- [Carta e renderer](paper-render.md): stato grafico, categorie, fonti primarie e vincoli.
- [Scala e back-end](scale-backend.md): generazione, heap e salvataggio; fonti tecniche.
- [Scala grafica](scala-grafica.md): aggiornamento successivo, quattro corse riuscite fuori sandbox.

Le misure sono esplorative. La serie CPU comprende tre campioni per bioma/taglia; la serie grafica una corsa
per taglia in una scena statica. Non certificano prestazioni del gioco completo né equivalenza delle scene.
I rapporti conservano i limiti osservati e i percorsi temporanei usati durante il lavoro.

## Riprodurre in una copia temporanea

1. Esportare il commit base con `git archive` in una nuova directory temporanea. Non cambiare checkout,
   salvataggi personali o sorgenti del repository. Annotare versione Odin, OS e hardware.
2. Nella copia, cambiare soltanto `map_size` in `src/expedition/world.odin` da
   `return legacy_map_size(b)*2` a `return legacy_map_size(b)*2*#config(MOONSHOT_SCALE,1)`.
   Il resto, compresi limiti e controlli, resta uguale. Questa incoerenza intenzionale con
   `campaign.biome_size` è parte dello stress test, non una patch da promuovere.
3. Creare nella copia `probe/main.odin` dal file [probe.odin.txt](scala/probe.odin.txt).
   Gli import relativi richiedono che `probe/` e `src/` siano directory sorelle.
4. Compilare ed eseguire ogni moltiplicatore come descritto nel rapporto scala. Sostituire `N` sia
   nel nome del binario sia in `-define:MOONSHOT_SCALE=N` con 1, 2, 4 o 8. Nessun controllo saltato.
   Conservare stdout/stderr. Per la serie aggiuntiva 8× usare `-o:speed`.
5. Per il benchmark grafico usare i define del supplemento, working directory della copia,
   argomento `--smoke-expedition`, timeout 35 s. È una prova senza profilo personale. Se la sandbox
   impedisce i servizi grafici, registrare il fallimento; nella sessione originale il retry fuori
   sandbox è stato autorizzato automaticamente ed è riuscito. Non estrapolare FPS da un avvio fallito.

## File delle prove

`scala/probe-{1,2,4,8}.log`: tutti i campioni headless `-o:none`, con generazione, creazione stanza,
byte tracciati, capture e numero di siti/gruppi. `scala/probe-speed-8.log`: serie aggiuntiva ottimizzata.
`scala/graphics-1.log`: primo avvio fallito nella sandbox.
`scala/graphics-{1,2,4,8}-unsandboxed.log`: corse grafiche riuscite, inclusi dettagli runtime e statistiche.

In questa serie preliminare non sono inclusi binari, asset, sorgenti duplicati del gioco o salvataggi. L'harness è testo di evidenza,
non un nuovo test integrato nel progetto. Il piano non dichiara superati i controlli delle fasi future.

## Polish della spedizione — 6 novembre

La cartella [polish-carte](polish-carte/) conserva i log mirati, le due corse native finali e due
catture del gioco: bersaglio fuori portata e scudo/colpo sul pianoro. Le copie dei log hanno solo
i fine-file normalizzati; contenuto dei risultati e timestamp sono conservati. Gli hash stanno in
[`SHA256SUMS`](polish-carte/SHA256SUMS). Procedura, copertura e limiti sono in
[docs/verifica.md](../../verifica.md#carte-e-leggibilità-degli-scontri-passo-successivo-del-6-novembre).
