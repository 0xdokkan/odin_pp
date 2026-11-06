# Laboratorio pagina: misure verificate

Ogni replica valida contiene quattro atti, ciascuno con 60 frame di riscaldamento esclusi e 600 misurati. Mediana e percentili sono calcolati sui singoli campioni di ciascun atto; p95/p99 usano il rango superiore (nearest rank).

I tempi sono in millisecondi. Frame è il tempo del fotogramma raylib; update e draw sono misure CPU interne al frame. Gli scope sono annidati e non sommabili. Draw misura la preparazione/invio dei comandi, non un timer GPU.

La completezza riguarda il protocollo presente nel log, non certifica l'exit code del processo, l'ottimizzazione della build o il sistema usato. Le repliche incomplete restano elencate e non contribuiscono a statistiche.

## Replica 1

Log: `/Users/dokkan/Dev/odin_pp/build/moonshot/fase1/bench-r1.log`

SHA-256: `f9aeedee13783f7864f7ec2fd7d5392bebaa77981223b5f777f055688803f54f`

Esito protocollo: **completo**.

RSS massima del processo: 128.359 MiB (134594560 byte), da `/usr/bin/time -l`; non è memoria esclusiva del modello.

Canvas logico e raster: 1920×1080. Risorse GPU possedute dal laboratorio: uno shader, zero mesh; le risorse condivise di host/raylib sono escluse dal conteggio.

| Atto | Scope | Campioni | Mediana | Media | p95 | p99 | Massimo |
|---|---|---:|---:|---:|---:|---:|---:|
| Still | frame | 600 | 10.977396 | 11.649588 | 16.184291 | 17.535375 | 18.105917 |
| Still | update | 600 | 2.897146 | 3.085877 | 3.881542 | 4.615792 | 4.709542 |
| Still | draw | 600 | 6.307271 | 6.768639 | 8.572833 | 10.213125 | 10.402167 |
| Walk | frame | 600 | 14.532875 | 14.668965 | 22.749333 | 26.225416 | 34.266248 |
| Walk | update | 600 | 3.636250 | 4.004039 | 6.691583 | 6.958833 | 7.299125 |
| Walk | draw | 600 | 7.747521 | 8.798817 | 13.929166 | 16.567917 | 17.968083 |
| Climb | frame | 600 | 17.863250 | 18.654698 | 25.644416 | 27.761292 | 48.439458 |
| Climb | update | 600 | 3.464459 | 3.379096 | 4.133458 | 4.358958 | 5.259083 |
| Climb | draw | 600 | 13.403541 | 13.730473 | 15.890000 | 18.870958 | 22.833042 |
| Flight | frame | 600 | 14.660520 | 13.913761 | 19.635625 | 24.605792 | 27.244708 |
| Flight | update | 600 | 2.951499 | 3.406855 | 5.893416 | 5.975750 | 6.125209 |
| Flight | draw | 600 | 6.314229 | 7.420202 | 12.929917 | 13.206500 | 13.570666 |

## Replica 2

Log: `/Users/dokkan/Dev/odin_pp/build/moonshot/fase1/bench-r2.log`

SHA-256: `43c2641b8e8ae4211bfef4b0943149be6807b883a7626fd63d1df2bd6129c680`

Esito protocollo: **completo**.

RSS massima del processo: 135.188 MiB (141754368 byte), da `/usr/bin/time -l`; non è memoria esclusiva del modello.

Canvas logico e raster: 1920×1080. Risorse GPU possedute dal laboratorio: uno shader, zero mesh; le risorse condivise di host/raylib sono escluse dal conteggio.

| Atto | Scope | Campioni | Mediana | Media | p95 | p99 | Massimo |
|---|---|---:|---:|---:|---:|---:|---:|
| Still | frame | 600 | 11.397833 | 12.753035 | 17.907083 | 20.709708 | 43.024793 |
| Still | update | 600 | 2.861292 | 3.109158 | 4.628750 | 5.976375 | 6.073042 |
| Still | draw | 600 | 6.290375 | 6.845474 | 10.267125 | 13.440708 | 13.972292 |
| Walk | frame | 600 | 14.542146 | 14.124368 | 23.030458 | 27.954459 | 48.625585 |
| Walk | update | 600 | 2.973229 | 3.378589 | 5.428209 | 6.967583 | 8.162083 |
| Walk | draw | 600 | 6.654834 | 7.474705 | 13.097083 | 16.000375 | 18.402791 |
| Climb | frame | 600 | 14.290146 | 14.104406 | 14.985542 | 15.285000 | 20.336876 |
| Climb | update | 600 | 2.680188 | 2.677016 | 2.737291 | 2.814292 | 2.882583 |
| Climb | draw | 600 | 11.257980 | 11.034453 | 11.854042 | 11.923000 | 12.172500 |
| Flight | frame | 600 | 8.303479 | 8.327762 | 8.486375 | 8.689083 | 9.608459 |
| Flight | update | 600 | 2.496750 | 2.501993 | 2.532209 | 2.595250 | 2.652708 |
| Flight | draw | 600 | 5.446917 | 5.453766 | 5.503042 | 5.584834 | 5.709458 |

## Replica 3

Log: `/Users/dokkan/Dev/odin_pp/build/moonshot/fase1/bench-r3.log`

SHA-256: `f8f8f459831031897b2f755478f600c3b8449bef5d8653a9e18eb601e502ed0d`

Esito protocollo: **completo**.

RSS massima del processo: 128.516 MiB (134758400 byte), da `/usr/bin/time -l`; non è memoria esclusiva del modello.

Canvas logico e raster: 1920×1080. Risorse GPU possedute dal laboratorio: uno shader, zero mesh; le risorse condivise di host/raylib sono escluse dal conteggio.

| Atto | Scope | Campioni | Mediana | Media | p95 | p99 | Massimo |
|---|---|---:|---:|---:|---:|---:|---:|
| Still | frame | 600 | 9.711250 | 11.812853 | 18.257709 | 22.982208 | 32.037374 |
| Still | update | 600 | 2.817438 | 3.049909 | 4.735833 | 6.005459 | 6.540958 |
| Still | draw | 600 | 6.234938 | 6.744472 | 10.903292 | 13.600875 | 15.815083 |
| Walk | frame | 600 | 12.246479 | 12.890512 | 17.521333 | 23.153167 | 28.637124 |
| Walk | update | 600 | 2.906855 | 3.107593 | 3.704250 | 6.738750 | 6.919542 |
| Walk | draw | 600 | 6.641750 | 6.836035 | 8.485041 | 15.162500 | 15.730083 |
| Climb | frame | 600 | 16.545937 | 17.024167 | 19.908125 | 33.379540 | 42.687874 |
| Climb | update | 600 | 2.726146 | 2.854828 | 3.277416 | 6.301583 | 6.377125 |
| Climb | draw | 600 | 11.569354 | 11.649776 | 12.934958 | 26.234041 | 34.171667 |
| Flight | frame | 600 | 8.288604 | 8.330027 | 8.478458 | 9.558625 | 10.008791 |
| Flight | update | 600 | 2.487667 | 2.490594 | 2.506167 | 2.572750 | 2.642292 |
| Flight | draw | 600 | 5.438688 | 5.442511 | 5.501084 | 5.533875 | 5.642417 |
