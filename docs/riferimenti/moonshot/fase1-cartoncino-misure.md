# Laboratorio pagina: misure verificate

Ogni replica valida contiene quattro atti, ciascuno con 60 frame di riscaldamento esclusi e 600 misurati. Mediana e percentili sono calcolati sui singoli campioni di ciascun atto; p95/p99 usano il rango superiore (nearest rank).

I tempi sono in millisecondi. Frame è il tempo del fotogramma raylib; update e draw sono misure CPU interne al frame. Gli scope sono annidati e non sommabili. Draw misura la preparazione/invio dei comandi, non un timer GPU.

La completezza riguarda il protocollo presente nel log, non certifica l'exit code del processo, l'ottimizzazione della build o il sistema usato. Le repliche incomplete restano elencate e non contribuiscono a statistiche.

## Replica 1

Log: `/Users/dokkan/Dev/odin_pp/build/moonshot/capacity-cardboard/bench-r1.log`

SHA-256: `1fa19ed54a9a536d6aecb178e28465849c2ab8c5d94d0d36bd9922b4c10433f8`

Esito protocollo: **completo**.

RSS massima del processo: 134.938 MiB (141492224 byte), da `/usr/bin/time -l`; non è memoria esclusiva del modello.

Canvas logico e raster: 1920×1080. Risorse GPU possedute dal laboratorio: uno shader, zero mesh; le risorse condivise di host/raylib sono escluse dal conteggio.

Atlas della stampa: una texture, 4672512 byte dichiarati costanti. Il contatore cumulativo print_uploads resta 1 ai checkpoint dopo 660, 1320, 1980 e 2640 frame (oltre i primi 13): nessun nuovo caricamento segnalato. Il log non contiene un checksum dei pixel.

| Atto | Scope | Campioni | Mediana | Media | p95 | p99 | Massimo |
|---|---|---:|---:|---:|---:|---:|---:|
| Still | frame | 600 | 15.590229 | 13.838311 | 18.938251 | 24.139667 | 30.816209 |
| Still | update | 600 | 0.031438 | 0.032539 | 0.051667 | 0.086500 | 0.294333 |
| Still | draw | 600 | 11.964333 | 11.824572 | 16.399791 | 19.491833 | 27.832125 |
| Walk | frame | 600 | 13.374229 | 14.079738 | 17.732374 | 18.734708 | 20.437583 |
| Walk | update | 600 | 4.003770 | 4.021127 | 4.203041 | 4.456500 | 4.707667 |
| Walk | draw | 600 | 7.337271 | 7.226192 | 7.683875 | 7.906542 | 8.949875 |
| Climb | frame | 600 | 16.701542 | 17.516854 | 21.218292 | 40.379874 | 69.131956 |
| Climb | update | 600 | 3.743250 | 3.857347 | 4.120166 | 7.812125 | 9.601750 |
| Climb | draw | 600 | 12.348500 | 12.475815 | 13.704750 | 27.637167 | 34.757833 |
| Flight | frame | 600 | 9.788625 | 9.901544 | 10.321708 | 11.497458 | 16.044542 |
| Flight | update | 600 | 3.290750 | 3.316676 | 3.470375 | 3.550167 | 3.615667 |
| Flight | draw | 600 | 6.096501 | 6.117162 | 6.283042 | 6.433750 | 6.515584 |

## Replica 2

Log: `/Users/dokkan/Dev/odin_pp/build/moonshot/capacity-cardboard/bench-r2.log`

SHA-256: `9fac1051bd7077f16d6693c8ade9b2e61d3e4c412cce69e9851f401a83e85580`

Esito protocollo: **completo**.

RSS massima del processo: 145.312 MiB (152371200 byte), da `/usr/bin/time -l`; non è memoria esclusiva del modello.

Canvas logico e raster: 1920×1080. Risorse GPU possedute dal laboratorio: uno shader, zero mesh; le risorse condivise di host/raylib sono escluse dal conteggio.

Atlas della stampa: una texture, 4672512 byte dichiarati costanti. Il contatore cumulativo print_uploads resta 1 ai checkpoint dopo 660, 1320, 1980 e 2640 frame (oltre i primi 13): nessun nuovo caricamento segnalato. Il log non contiene un checksum dei pixel.

| Atto | Scope | Campioni | Mediana | Media | p95 | p99 | Massimo |
|---|---|---:|---:|---:|---:|---:|---:|
| Still | frame | 600 | 8.450167 | 9.537184 | 16.395541 | 19.059792 | 25.313666 |
| Still | update | 600 | 0.013916 | 0.018573 | 0.038166 | 0.045458 | 0.051875 |
| Still | draw | 600 | 7.913813 | 8.532231 | 14.724625 | 15.277458 | 24.236000 |
| Walk | frame | 600 | 11.805646 | 12.387869 | 16.408417 | 16.869541 | 17.129250 |
| Walk | update | 600 | 3.969125 | 4.050612 | 4.486500 | 4.576833 | 4.730542 |
| Walk | draw | 600 | 7.374958 | 7.307391 | 8.285208 | 8.520916 | 8.863625 |
| Climb | frame | 600 | 16.731083 | 16.843322 | 19.229708 | 22.156084 | 24.665833 |
| Climb | update | 600 | 3.741521 | 3.815000 | 4.380125 | 4.969000 | 5.099500 |
| Climb | draw | 600 | 12.422042 | 12.261846 | 14.078959 | 16.213208 | 16.589500 |
| Flight | frame | 600 | 9.757375 | 9.886457 | 10.446209 | 12.874417 | 19.393958 |
| Flight | update | 600 | 3.282063 | 3.300431 | 3.400542 | 3.535000 | 3.736208 |
| Flight | draw | 600 | 6.083063 | 6.103122 | 6.238291 | 6.445833 | 6.547042 |

## Replica 3

Log: `/Users/dokkan/Dev/odin_pp/build/moonshot/capacity-cardboard/bench-r3.log`

SHA-256: `6e3ecaa7226fb1b3feb57673c5782183b125da9b6850459310c109cd258e3058`

Esito protocollo: **completo**.

RSS massima del processo: 141.344 MiB (148209664 byte), da `/usr/bin/time -l`; non è memoria esclusiva del modello.

Canvas logico e raster: 1920×1080. Risorse GPU possedute dal laboratorio: uno shader, zero mesh; le risorse condivise di host/raylib sono escluse dal conteggio.

Atlas della stampa: una texture, 4672512 byte dichiarati costanti. Il contatore cumulativo print_uploads resta 1 ai checkpoint dopo 660, 1320, 1980 e 2640 frame (oltre i primi 13): nessun nuovo caricamento segnalato. Il log non contiene un checksum dei pixel.

| Atto | Scope | Campioni | Mediana | Media | p95 | p99 | Massimo |
|---|---|---:|---:|---:|---:|---:|---:|
| Still | frame | 600 | 8.389521 | 9.592120 | 16.338084 | 19.099666 | 32.336917 |
| Still | update | 600 | 0.014021 | 0.019588 | 0.040875 | 0.046958 | 0.079125 |
| Still | draw | 600 | 7.708229 | 8.737698 | 14.866000 | 15.319500 | 30.206708 |
| Walk | frame | 600 | 11.692396 | 11.699689 | 12.490000 | 15.252958 | 17.247749 |
| Walk | update | 600 | 3.990521 | 4.004209 | 4.183000 | 4.250000 | 4.344000 |
| Walk | draw | 600 | 7.258667 | 7.177187 | 7.640459 | 7.902417 | 8.088708 |
| Climb | frame | 600 | 16.504999 | 16.247599 | 17.291624 | 18.766126 | 21.050625 |
| Climb | update | 600 | 3.716626 | 3.717415 | 3.970125 | 4.107916 | 4.252667 |
| Climb | draw | 600 | 12.310583 | 12.028735 | 12.753833 | 12.917083 | 14.167333 |
| Flight | frame | 600 | 9.807729 | 10.238179 | 12.255875 | 14.425292 | 18.843584 |
| Flight | update | 600 | 3.295563 | 3.408163 | 3.915875 | 4.421709 | 4.604917 |
| Flight | draw | 600 | 6.116979 | 6.280903 | 7.090333 | 8.243417 | 8.334208 |
