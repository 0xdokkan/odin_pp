[← Odin PP](../../README.md)

# Licenze dei suoni

Quasi tutti i suoni e le musiche del gioco sono **fatti da codice** (`tools/audio`, vedi
[SOUND_SPEC.md](../../tools/audio/SOUND_SPEC.md)) e appartengono al progetto.

Fanno eccezione alcuni suoni di **«Benvenuti a Napoli»** ([piano](../../docs/piano-napoli.md), Fase 6):
l'utente ha scelto di usare file **CC0** (pubblico dominio, uso completo e libero anche a scopo di
lucro, nessun obbligo di citare l'autore) quando se ne trovano. Ogni file viene da
[Freesound](https://freesound.org), e la licenza **Creative Commons 0** è stata controllata sulla
pagina di ciascuno il 3 novembre 2026. È stata scaricata l'anteprima di alta qualità (mp3 a
128 kbit/s), senza account. Da ognuna è stato tagliato un pezzo, salvato in `tools/audio/cc0/`
come WAV mono a 44,1 kHz. Da lì `tools/audio/sfx_napoli.py` costruisce il suono del gioco, che ha
lo stesso volume e la stessa eco della sala di pietra degli altri suoni, e lo salva in
`assets/audio/lab/` come .ogg.

| Suono del gioco | Pezzo in `tools/audio/cc0/` | File originale | Autore | Licenza | Tratto usato |
|---|---|---|---|---|---|
| `napoli_club_hit`, `napoli_club_floor` | `napoli_whack.wav` | [Wooden Stick Whacks Medicine Ball.wav](https://freesound.org/people/bmacphail/sounds/569541/) | bmacphail | CC0 | 18,39-19,08 s |
| `napoli_boing` | `napoli_boing.wav` | [Boing 2](https://freesound.org/people/magnuswaker/sounds/540790/) | magnuswaker | CC0 | tutto (1,15 s) |
| `napoli_coins` | `napoli_purse.wav` | [purse_coin](https://freesound.org/people/cupido-1/sounds/519645/) | cupido-1 | CC0 | 27,98-29,25 s |
| `napoli_feast` | `napoli_plate.wav` | [plate.wav](https://freesound.org/people/Closetwalrus/sounds/370298/) | Closetwalrus | CC0 | 0,53-1,62 s |
| `napoli_step_a`, `napoli_step_b` | `napoli_step_a.wav`, `napoli_step_b.wav` | [footsteps.wav](https://freesound.org/people/brumxyz/sounds/560728/) | brumxyz | CC0 | 0,39-0,78 s e 1,01-1,40 s |
| `napoli_laugh` | `napoli_laugh.wav` | [Crazy old man laugh.wav](https://freesound.org/people/Cavernstones/sounds/148915/) | Cavernstones | CC0 | 0,10-2,62 s |

Sono fatti da codice anche gli altri suoni della carta (`napoli_swing`, `napoli_stars`,
`napoli_pocket`, `card_napoli`) e la sua **tarantella** (`assets/audio/music/tarantella.ogg`,
`tools/audio/music_tarantella.py`). Per la tarantella non si è trovata una registrazione CC0
pulita: l'unica, «Neapolitan tarantella» di davidebug, è registrata per strada, con auto e voci.
