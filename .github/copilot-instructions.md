# Istruzioni per Copilot — Paola Gestionale

App nativa SwiftUI + SwiftData (macOS 14 / iOS 17) per la gestione di clienti, agenda e
conti di una personal trainer. Rispondere in italiano. Contesto completo in
`.kiro/steering/` (`product.md`, `tech.md`, `structure.md`) e `PROGETTO.md`.

## Architettura

- `Sources/PaolaCore`: dominio, regole economiche, persistenza, report. Ogni regola nuova
  va qui, con test in `Tests/PaolaCoreTests`.
- `Sources/PaolaApp`: sola presentazione SwiftUI, nessuna regola economica.
- Denaro sempre in centesimi `Int64` (`Money`), mai `Double`.
- Le scritture passano da `BusinessRepository`, che usa un nuovo `ModelContext` con
  autosave disabilitato; il contesto della UI non si tocca durante il tentativo.

## Validazione delle scritture

`BusinessRepository.transact(validation:)`:

- `.archive` (default): valida l'intero archivio prima e dopo. Obbligatorio per
  operazioni su movimenti, utilizzi pacchetto, pacchetti, fatture, spese, servizi, corsi,
  blocchi e per il completamento di una lezione.
- `.local`: nessuna validazione globale; l'operazione deve controllare da sé tutte le
  regole di `BusinessArchive.validate` che può violare (es. `rescheduleSession` verifica
  la scadenza dei pacchetti). Usato per `isPaid`, `isBlack`, spostamento, creazione e
  modifica di appuntamenti non completati, stati diversi da "completato".

## Performance (regressioni già viste: >50 s per scrittura)

- `validate` e `integrityWarnings` devono restare O(n): niente `filter`/`contains`
  annidati in un ciclo; indicizzare con `Dictionary(grouping:)` o mappe per id/sourceKey.
- Leggere proprietà di un `@Model` costa: estrarre le chiavi una volta prima di ordinare.
- Preferire fetch con `#Predicate` a fetch completo + filtro. Durata massima di una
  lezione 1440 minuti: le sovrapposizioni si cercano in `[start − 24 h, end)`.
- Viste: `@Query` limitate al periodo mostrato (vedi `AgendaContent`); indici derivati
  calcolati una volta per render (`AgendaSnapshot`); niente cache persistenti (diventano
  obsolete con iCloud).
- Benchmark: `Tests/PaolaCoreTests/WritePerformanceTests.swift`.

## Build e test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test --scratch-path build/test-validation
```

- Serve Xcode completo, non i soli Command Line Tools.
- Non eseguire i test automaticamente dopo una modifica: verificare con la compilazione,
  lanciare la suite solo se richiesto o prima di una release.
- Se il terminale non restituisce output, eseguire in background redirigendo su file.
- Nel progetto Xcode solo `BusinessViews/` e `Protection/` sono cartelle sincronizzate:
  i nuovi file nella radice di `Sources/PaolaApp/` vanno aggiunti a `project.pbxproj`.
