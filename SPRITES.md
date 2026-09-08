# Immagini e animazioni personalizzate

Il renderer può sostituire il corpo del giocatore, dei nemici e degli oggetti con PNG, sprite sheet PNG o GIF animate. Supporta anche clip per lancio, proiettile, impatto e danno, sincronizzate con gli eventi di combattimento. Gli indicatori di salute, le intenzioni e le micce restano gestiti dal gioco. Senza un asset valido continua a essere usata la grafica procedurale di quel tipo o effetto.

Non sono incluse nuove illustrazioni: il sistema permette di inserire le proprie immagini senza ricompilare.

## Avvio rapido

1. Crea `assets/sprites.json`, prendendo come riferimento `assets/sprites.example.json`.
2. Inserisci le immagini nelle posizioni indicate dal manifest. I percorsi dei file sono relativi alla cartella che contiene il manifest.
3. Avvia `odin run src`. Il manifest predefinito è `assets/sprites.json`, relativo alla directory di avvio.

Per usare un altro pacchetto:

```sh
odin run src -- --sprites=/percorso/del/pacchetto/sprites.json
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

## Tipi e dimensioni

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

## GIF e sprite sheet

Per una GIF indica soltanto `file`, dimensioni, eventuale `anchor` e `fps`. Non impostare `columns`, `rows` o `frames`: i frame provengono dal file GIF. Le animazioni dei corpi vengono ripetute a velocità uniforme; le durate originali dei singoli frame GIF e il numero di ripetizioni non vengono usati. Raylib non espone le durate attraverso la funzione di caricamento impiegata.

Uno sprite sheet PNG deve avere dimensioni divisibili per `columns` e `rows`. `frames` permette di escludere celle vuote finali. Tutte le istanze del corpo di uno stesso tipo condividono la fase del loop. Questa animazione è cosmetica e non fa avanzare impulsi, intenzioni o RNG; le animazioni di spostamento e combattimento del gioco continuano ad applicarsi allo sprite.

## Clip collegate agli eventi

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

## Caricamento e limiti

I file condivisi da più chiavi usano la stessa texture, anche quando una chiave è un corpo in loop e l'altra è una clip evento. I frame GIF vengono riuniti in un atlas, caricato sulla GPU una sola volta; durante il gioco non vengono decodificate GIF né ricaricate texture. Le risorse GPU e le maschere alpha vengono liberate prima della chiusura della finestra.

- Manifest fino a 64 KiB, con un massimo di 19 associazioni: 11 corpi e 8 clip evento.
- File PNG/GIF fino a 16 MiB; massimo 128 frame e 8 milioni di pixel decodificati per file/atlas.
- Texture con lato massimo di 4096 pixel; budget complessivo di 32 milioni di pixel.
- Dimensioni visualizzate positive fino a 256 pixel per asse e velocità fino a 60 fps.

Dimensioni PNG e struttura GIF vengono controllate prima della decodifica. Manifest mancante, file non validi o configurazioni incompatibili conservano la grafica procedurale; un errore di un singolo sprite non impedisce il caricamento degli altri.

## Verifica grafica

```sh
odin run src -- --smoke-sprites
```

Il comando crea PNG e GIF di prova temporanei, verifica condivisione delle
texture fra corpi e clip, primo e ultimo frame di una clip leggendo i pixel
renderizzati sulla GPU, cambio di frame GIF, selezione trasparente e fallback, poi salva
`odin_pp_sprites.png` e chiude la finestra. Lo screenshot mostra anche la barra
di salute di un Ice Block danneggiato sopra lo sprite personalizzato. Le immagini
di prova vengono rimosse; non costituiscono un pacchetto grafico per la run.
