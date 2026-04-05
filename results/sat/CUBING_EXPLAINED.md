# SMS Cube-and-Conquer: Cutoff, Cubi e Sub-cubi

## Il modello mentale: un albero di decisioni

Lo spazio di ricerca SMS è un **albero binario**. Ogni nodo è una decisione: "l'arco (i,j) del grafo su 43 vertici è rosso o blu?". Ci sono 903 archi possibili, quindi l'albero completo ha profondità 903.

```
                        [root]                    profondità 0
                       /      \
                  e₁=R          e₁=B              profondità 1
                 /    \        /    \
              e₂=R   e₂=B  e₂=R   e₂=B           profondità 2
              ...     ...   ...    ...
```

Ma SMS non è un albero binario bilanciato — applica:

1. **Propagazione unitaria**: se un'assegnazione forza altre variabili (per evitare K₅), queste vengono fissate automaticamente
2. **Rottura di simmetria**: se due rami sono isomorfi (graficamente equivalenti), ne esplora uno solo
3. **Pruning**: se un ramo porta inevitabilmente a un K₅ monocromatico, viene potato

## Il cutoff = "dove tagli l'albero"

Il **cutoff** è il numero di **variabili assegnate** (profondità nell'albero) al quale smsg smette di esplorare e dice: "da qui in poi, salva questa posizione come un cubo da risolvere dopo".

```
Cutoff 50:          ────── taglia qui ──────
                    11 foglie (cubi)
                    Alcune enormi, alcune minuscole

Cutoff 70:          ──────────── taglia qui ────────────
                    4483 foglie (sub-cubi)
                    Più uniformi, ma 85 ancora troppo grandi

Cutoff 90:          ──────────────────── taglia qui ──────────────────
                    ~5439 foglie per sotto-ramo hard
                    Ancora più piccole
```

## Cos'è un "cubo" concretamente

Un cubo è un **assegnamento parziale** — una lista di letterali tipo:

```
a -1 22 23 -24 25 ...
```

Dove `22` significa "variabile 22 = VERO (arco rosso)" e `-24` significa "variabile 24 = FALSO (arco blu)". È il **percorso dalla radice alla foglia** nell'albero di ricerca.

## Visualizzazione grafica

È come una mappa geografica a zoom crescente:

```
┌─────────────────────────────────────────┐
│              SPAZIO TOTALE              │  R(5,5,43) completo
│  "Esistono grafi su 43 vertici senza   │  903 variabili libere
│   K₅ monocromatici?"                   │
└─────────────────────────────────────────┘
         │ cutoff 50 → 11 regioni
         ▼
┌──┬──┬──┬──────────┬──┬──┬───┬──┬──┬──┬──┐
│1 │2 │3 │    5     │4 │6 │ 7 │8 │9 │10│11│  ← cubi (non uniformi!)
│✓ │✓ │██│    ✓     │✓ │██│ ██│✓ │██│██│✓ │  ✓=UNSAT facile
└──┴──┴──┴──────────┴──┴──┴───┴──┴──┴──┴──┘  ██=hard
         │ cutoff 70 → 4483 sotto-regioni per cubo hard
         ▼
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬▓┬─┐
│ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │▓│ │  4483 sotto-regioni
│✓│✓│✓│✓│✓│✓│✓│✓│✓│✓│✓│✓│✓│✓│✓│✓│✓│▓│✓│  4398 facili, 85 hard (▓)
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴▓┴─┘
         │ cutoff 90 → ~5439 per sub-cubo hard
         ▼
┌┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┐
│││││││││││││││││││││││││││││││││││││││││  5439 micro-regioni
│✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓│  (sperabilmente tutte facili)
└┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┴┘
```

## Perché la dimensione non è uniforme

L'albero SMS non è bilanciato. Alcune regioni dello spazio vengono eliminate quasi completamente dalla simmetria e dalla propagazione → cubi piccoli, risolvibili in 1s. Altre regioni hanno meno simmetria → cubi enormi, il solver deve esplorare moltissimi rami.

I nostri 85 sub-cubi hard sono regioni con **poca simmetria e poca propagazione** — lo spazio di ricerca residuo è vasto. Il sub-sub-cubing a cutoff 90 li spezza ulteriormente.

## La garanzia matematica

La proprietà fondamentale è la **partizione esaustiva**:

> L'unione di tutti i cubi = lo spazio totale, e i cubi sono disgiunti.

Formalmente, se lo spazio di ricerca è S e i cubi sono C₁, C₂, ..., Cₖ:

- **Copertura**: S = C₁ ∪ C₂ ∪ ... ∪ Cₖ
- **Disgiunzione**: Cᵢ ∩ Cⱼ = ∅ per ogni i ≠ j

Quindi se TUTTI i sub-sub-cubi sono UNSAT → il sub-cubo è UNSAT → il cubo è UNSAT → R(5,5,43) = 0 soluzioni.

## Dati del nostro esperimento

| Livello | Cutoff | Cubi | Tempo generazione | Note |
|---------|--------|------|-------------------|------|
| 1 | 50 | 11 | 26 min | 6 facili, 5 hard |
| 2 | 70 | 4483 per cubo hard | ~40 min | 4398 facili (~1s), 85 hard (>1h) |
| 3 | 90 | ~5439 per sub-cubo hard | ~27 min | da verificare |
