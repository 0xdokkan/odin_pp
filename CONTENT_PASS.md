# Content Pass

Questo incremento usa soltanto primitive gia presenti per verificare il gioco,
non per ampliare il framework. Le cinque carte nuove combinano danno, status,
area, cleanup e ciclo del deck; insieme a `Shove`, `Dash` e `Grappling Hook`
formano un pass di otto carte con cui cercare limiti reali prima di M4D.

## Indice

- [Catalogo](#catalogo)
- [Economia dei pulse](#economia-dei-pulse)
- [Primitive esercitate](#primitive-esercitate)
- [Domande di playtest](#domande-di-playtest)
- [Criteri per la prossima milestone](#criteri-per-la-prossima-milestone)
- [Verifica](#verifica)

## Catalogo

| Carta | Rarita | Energia | Target | Effetto base |
|---|---|---:|---|---|
| `Heavy Blow` | Common | 2 | melee adiacente | 5 danni, +1 per upgrade |
| `Venom Needle` | Common | 1 | Chebyshev 1-3, LoS | 1 danno, +1 per upgrade; Poison 1 per 3 pulse |
| `Caustic Bloom` | Uncommon | 2 | anchor 1-3, area 3x3 | Poison 2, +1 per upgrade, per 2 pulse |
| `Purifying Guard` | Uncommon | 1 | player | Shield 2, +1 per upgrade, per 3 pulse; rimuove Poison se presente |
| `Volatile Study` | Rare | 2 | player | crea 1 `Spark`; pesca 1, +1 per upgrade; Ethereal ed Exhaust |

`Purifying Guard` non richiede che Poison sia presente. Il resolver applica lo
Shield e salta soltanto il cleanup non valido. `Volatile Study` crea prima la
`Spark` e poi pesca: ordine, capienza della mano e lifecycle restano osservabili
nel log eventi.

## Economia dei pulse

Un comando accettato costa una risposta nemica; l'energia si rigenera di uno a
ogni pulse fino a tre. Il confronto melee rende esplicita questa economia:

| Azione | Danno | Energia | Pulse | Ruolo |
|---|---:|---:|---:|---|
| bump attack | 2 | 0 | 1 | fallback sempre disponibile |
| `Strike` | 3 | 1 | 1 | danno efficiente e ciclo della mano |
| `Heavy Blow` | 5 | 2 | 1 | comprime piu danno in una sola risposta nemica |

`Heavy Blow` non deve vincere per danno/energia: il vantaggio e usare un solo
pulse quando il tempo e piu scarso dell'energia. `Venom Needle` scambia danno
immediato per valore futuro; `Caustic Bloom` scambia precisione per pressione su
un gruppo. Queste differenze vanno misurate in pulse e danni subiti, non soltanto
nel numero stampato sulla carta.

## Primitive esercitate

| Famiglia | Carte | Contratto sotto prova |
|---|---|---|
| danno diretto | `Heavy Blow`, `Venom Needle` | scaling upgrade, range, LoS e ordine effetti |
| status spaziale | `Venom Needle`, `Caustic Bloom` | applicazione singola/area e durata in pulse |
| effetto opzionale | `Purifying Guard` | un template invalido non annulla gli altri validi |
| ciclo del deck | `Volatile Study` | Create, Draw, Ethereal, Resolving ed Exhaust |
| movimento | `Shove`, `Dash`, `Grappling Hook` | query condivisa, hazard e intenti stale |

Nessuna carta introduce uno switch speciale in `play_card` o nel renderer di
targeting. Le definizioni compilano normali `Action`; la UI legge gli stessi dati
usati da preview e resolver.

## Domande di playtest

1. Quante volte un player sceglie bump, `Strike` o `Heavy Blow` quando tutti e
   tre sono disponibili? Registrare pulse, energia sprecata e danni subiti.
2. Quanto spesso `Venom Needle` ottiene almeno due tick di Poison prima che il
   bersaglio muoia? Se accade raramente, il problema puo essere durata o pacing.
3. Quanti nemici colpisce mediamente `Caustic Bloom`? Un valore quasi sempre uno
   indica layout troppo aperti o range non interessante.
4. Quante giocate di `Purifying Guard` rimuovono davvero Poison? Se la cleanse e
   quasi sempre morta, deve diventare un bonus piu ampio o un'altra carta.
5. `Volatile Study` viene giocata, exhaustata da Refocus o lasciata Ethereal?
   Confrontare carte create, carte pescate e pulse con `Battle Focus`.
6. Quanto spesso Push/Pull fanno scattare una trappola o invalidano un intento?
   Il movimento deve produrre decisioni, non soltanto animazioni.
7. Refocus viene usato per cercare una risposta o solo quando la mano e pessima?
   La frequenza decide se servono premi allo scarto prima di nuovi selettori UI.

## Criteri per la prossima milestone

M4D va aperta con una nuova primitiva solo se i playtest mostrano un bisogno
ripetuto. Esempi validi sono Root/Slow per spezzare il kiting, un cono per piu
carte realmente progettate attorno a quella forma, o costi dinamici richiesti da
un archetipo di deck. Una singola carta ipotetica non basta a giustificare
infrastruttura condivisa.

## Verifica

I test dedicati sono in `src/game/content_card_test.odin`. Lo smoke visuale crea
una mano con le cinque carte, trascina `Caustic Bloom` e mostra il 3x3 senza la
carta sopra la griglia:

```sh
odin run src -- --smoke-content
```

Il comando salva `odin_pp_content_pass.png` e chiude la finestra dopo tre frame.
