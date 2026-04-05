# SMS Cube Solving — Tracker
## Last updated: 2026-04-05 00:30

## Scoperta chiave: Progressive Global Cubing

smsg `--assignment-cutoff` genera l'**albero canonico globale** indipendentemente
dal contenuto di `--cube-file`. Questo significa che tutti i cubi a un dato livello
di cutoff sono identici, indipendentemente dal cubo genitore. Verificato via
confronto byte-per-byte dei file `.icnf` generati da genitori diversi.

**Implicazione**: il lavoro da fare è 425× meno di quanto stimato inizialmente
(5.439 sub-sub-cubi unici anziché ~2.3M ridondanti).

## Cubes overview (cutoff 50 → 11 canonical cubes)

| Cube | Status       | Method           | Result | Notes |
|------|-------------|------------------|--------|-------|
| 1    | **DONE**    | monolitico       | UNSAT  | 195s |
| 2    | **DONE**    | monolitico       | UNSAT  | 1s |
| 3    | **DONE***   | progressive cubing | —    | 4397 UNSAT + 85 hard → canonical SSC |
| 4    | **DONE**    | monolitico       | UNSAT  | 1.3s |
| 5    | **DONE**    | monolitico       | UNSAT  | 762s |
| 6    | **DONE***   | progressive cubing | —    | identico a cubo 3 |
| 7    | **DONE***   | progressive cubing | —    | identico a cubo 3 |
| 8    | **DONE**    | monolitico       | UNSAT  | 47s |
| 9    | **DONE***   | progressive cubing | —    | identico a cubo 3 |
| 10   | **DONE***   | progressive cubing | —    | identico a cubo 3 |
| 11   | **DONE**    | monolitico       | UNSAT  | 58s |

*\*Cubi 3,6,7,9,10 condividono gli stessi sub-cubi e sub-sub-cubi (progressive global cubing). Risoluzione tramite directory canonical unica.*

## Struttura progressive cubing (3 livelli)

| Livello | Cutoff | Cubi totali | Risolti diretto | Hard (timeout) |
|---------|--------|-------------|-----------------|----------------|
| 1       | 50     | 11          | 6 UNSAT         | 5 → livello 2  |
| 2       | 70     | 4.483       | 4.398 UNSAT     | 85 → livello 3 |
| 3       | 90     | 5.439       | in corso        | 11 TIMEOUT (finora) |

### Stato livello 3 — Solving canonico (IN CORSO)

Directory: `canonical_ssc/`

| Metrica | Valore |
|---------|--------|
| Totale sub-sub-cubi | 5.439 |
| UNSAT | ~1.360 (in crescita) |
| TIMEOUT | 11 |
| SAT | 0 |
| Rimanenti | ~4.070 |

**Worker attivi:**
- Locale: 14 worker (PID 3620461)
- Server (hatweb-server): 3 worker
- Sync bidirezionale ogni 10 min

**11 sub-sub-cubi TIMEOUT** (indici): 1053, 1077, 1095, 1108, 1109, 1183, 1185, 1186, 1187, 1189, 1273
→ Richiederanno livello 4 (cutoff ~110)

## Extension tension τ(G) — COMPLETATO

Tutti i 656 grafi R(5,5,42) analizzati via MaxSAT (exact_tension.csv).

| Statistica | Valore |
|-----------|--------|
| τ_min | 2 (G83, circolante) |
| τ_max | 49 (G155) |
| Mediana | ~28 |
| E[cost random N] | ≈125 |
| Grafi con τ=2 | 2 (G83 e complemento) |

**Teoremi dimostrati:**
- τ(G) = τ(Ḡ) (simmetria complemento)
- f_circ(43) ≡ 0 mod 43, quindi f_circ(43) = 43
- f(43) ≥ 2 (condizionato alla completezza del catalogo)

## File e directory

```
results/sat/
├── TRACKER.md                    ← questo file
├── canonical_ssc/                ← DIRECTORY PRINCIPALE DI LAVORO
│   ├── subsub.icnf               ← 5439 sub-sub-cubi canonici (cutoff 90)
│   └── results/                  ← risultati (ssc_*.result + ssc_*.log)
├── cubes_sms_43.icnf             ← 11 cubi originali (cutoff 50)
├── subcubes_{3,6,7,9,10}.icnf    ← sub-cubi (cutoff 70) — tutti identici
├── subcube_results_{3,6,7,9,10}/ ← risultati livello 2
├── hard_subcubes_{3,6,7,9,10}/   ← vecchie directory ridondanti
└── r55_43_sms.cnf                ← formula CNF principale
```

## Prossimi passi

1. **Completare livello 3**: ~4.070 SSC rimanenti (stima: 3-6 ore con 17 worker totali)
2. **Livello 4**: Decomporre gli 11 TIMEOUT a cutoff ~110
3. **Propagare risultati**: Copiare da canonical_ssc/ alle vecchie directory per compatibilità check_hard.sh
4. **Paper**: Aggiornare tabelle finali e chiudere quando tutti i risultati sono UNSAT

## Risultati possibili

| Risultato | Significato | Azione |
|-----------|-------------|--------|
| Tutti UNSAT | Nessun grafo R(5,5,43) esiste | R(5,5) ≤ 43 confermato (cond. catalogo) |
| SAT | **Grafo R(5,5,43) trovato!** | Scoperta storica |
| TIMEOUT residui | SSC troppo hard | Ulteriore decomposizione |
