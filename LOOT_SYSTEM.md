# Magnetic Loot

Questa guida descrive la raccolta magnetica del loot durante e dopo un combattimento.

## Indice

- [Range](#range)
- [Fase di attivazione](#fase-di-attivazione)
- [Momenti di raccolta](#momenti-di-raccolta)
- [Raccolta](#raccolta)
- [Celle compromesse](#celle-compromesse)
- [Transizione dal combattimento](#transizione-dal-combattimento)
- [Eventi](#eventi)
- [Animazione](#animazione)
- [Limiti intenzionali](#limiti-intenzionali)

## Range

Il range e configurato da:

```odin
LOOT_MAGNET_RANGE_CELLS :: 3
```

La distanza usata e Chebyshev:

```text
distance = max(abs(player.x - loot.x), abs(player.y - loot.y))
```

Un valore tre significa tre celle per asse, diagonali incluse: il footprint
massimo e un quadrato `7x7` centrato sul player. La costante puo essere cambiata
senza modificare la logica di raccolta.

## Fase di attivazione

Il magnete funziona quando `Room.phase` e `Combat` oppure `Loot`. Non opera in
`Complete` o `Defeat`.

I drop dei primi nemici sconfitti possono quindi essere assorbiti mentre altri
nemici sono ancora vivi. La raccolta non richiede un passo, non consuma energia e
non produce un pulse.

## Momenti di raccolta

Il range viene rivalutato:

- dopo un'azione accettata del player;
- dopo il pulse nemico e i tick degli status;
- dopo ogni spostamento senza pulse durante `Loot`.

Il primo controllo copre un drop appena creato da un attacco e un loot gia a
terra raggiunto col movimento. Il secondo copre morti causate da `Poison`,
`Thorns` o altre reazioni avvenute durante il pulse.

## Raccolta

`collect_loot_in_magnet_range` scandisce la dynamic array del loot. Ogni oggetto
nel range costruisce una normale `Action_Kind.Collect`:

- `Gold` produce `Gain_Gold`;
- `Healing` produce `Heal` sul player.

L'oggetto viene rimosso soltanto se il resolver accetta l'azione. La scansione
usa `unordered_remove` senza incrementare l'indice dopo una rimozione, cosi anche
l'elemento spostato viene controllato.

Una cura raccolta a vita piena viene consumata, come accadeva gia con la raccolta
sulla stessa cella: l'effetto e valido, ma `healing_done` vale zero.

## Celle compromesse

Il controllo magnetico usa soltanto le coordinate. Non richiede line of sight e
non interroga muri, ostacoli, trappole o tipo della tile.

Di conseguenza un drop puo essere assorbito da:

- una trappola ancora armata, senza attivarla;
- la cella di uscita, senza concludere la stanza;
- una cella occupata da un ostacolo;
- una diagonale entro il range.

Il player attiva trappola o uscita soltanto quando esegue realmente un movimento
sulla relativa cella.

## Transizione dal combattimento

La stessa raccolta copre ogni percorso che puo portare da `Combat` a `Loot`:

- attacco del player;
- risposta o reazione nemica;
- tick di `Poison`;
- attesa;
- abilita.

Gli oggetti vicini a qualunque nemico sconfitto possono quindi essere assegnati
nello stesso comando della morte. I drop fuori range restano visibili e vengono
rivalutati dai comandi successivi, anche prima della fine del fight.

## Eventi

La morte emette prima `Loot_Dropped` per ogni oggetto creato, con tipo, quantita e
cella. Prima di rimuovere un oggetto raccolto viene poi emesso `Loot_Collected`,
che conserva:

- tipo e quantita del loot;
- cella di origine;
- cella del player al momento della raccolta;
- player come target.

Subito dopo, il normale resolver emette `Gold_Gained` oppure `Healed`. Lo stato
autorevole viene quindi aggiornato nello stesso comando; l'evento di raccolta
contiene soltanto i dati necessari alla presentazione.

## Animazione

Prima del comando viene catturato un `Room_Presentation`. `Loot_Dropped` fa
comparire l'oggetto con un pulse sulla cella; `Loot_Collected` interpola origine e
player con easing e un piccolo arco prospettico. Il successivo `Gold_Gained` o
`Healed` aggiorna la copia visuale nel medesimo ordine del log.

La timeline ha capacita fissa pari a `MAX_GAME_EVENTS` e non possiede loot di
gameplay. Oro, cura e rimozione dalla stanza sono gia avvenuti nella simulazione
autorevole, quindi durata del cue, FPS o camera non possono cambiare il risultato.
Il log viene copiato una sola volta da `begin_renderer_event_timeline`: ridisegnare
lo stesso snapshot non riavvia la raccolta.

Le vecchie pool `Loot_Animation` restano temporaneamente disponibili per test di
compatibilita, ma il gameplay principale usa la timeline descritta in
[Presentation Timeline](PRESENTATION_TIMELINE.md).

## Limiti intenzionali

Non sono ancora implementati:

- sprite, suono e particelle di raccolta;
- filtri per rarita o tipo;
- statistiche che modificano il range;
- inventario pieno o scelta di lasciare un oggetto a terra.
