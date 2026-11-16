# Progresso M1–M4 — Fase A (dominio)

Nessun commit (richiesto). Base: Q1–Q7 non committati, preservati. Nessun gate `agenda-m1-m4-gate-domain.json` presente → implementazione.
Ambiente: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, Debug SwiftPM, archivio in memoria, dati inventati.

## Fase A

### Comandi eseguiti
- Prima (bundle `build/bench-after` costruito a fine Q, codice invariato):
  `xcrun xctest -XCTest AgendaWeeklyBenchmarkTests build/bench-after/debug/PaolaAppTests.xctest` e
  `xcrun xctest -XCTest WritePerformanceTests build/bench-after/debug/PaolaCoreTests.xctest` → `.agents/tasks/agenda-m1-m4/before.txt` (0 fallimenti). Nota: il bundle non si chiama `PaolaGestionalePackageTests.xctest`; sono due bundle (`PaolaAppTests`, `PaolaCoreTests`).
- Dopo: `xcrun swift build` → Build complete (0 errori/warning nuovi).
- `xcrun swift build --build-tests --scratch-path build/bench-after` → Build complete.
- `xcrun xctest -XCTest <Classe> build/bench-after/debug/PaolaCoreTests.xctest` per le classi di dominio, `PaolaAppTests.xctest` per il benchmark → `.agents/tasks/agenda-m1-m4/after-domain.txt`.

### Implementazione
- `PaolaSignpost.swift` (nuovo): `OSSignposter`, subsystem `local.paola.gestionale`, categoria `Performance`, `interval(_ name: StaticString, _:)`. Solo nomi costanti.
- Intervalli: `<nome operazione>` (es. `setSessionStatus`), `validation.pre`, `operation`, `validation.post`, `save`, `refetch` in `BusinessRepository.transact/save`; `archive.capture` (`BusinessArchive.uncanonicalizedCapture`); `integrityWarnings` (`BusinessReports`); `fullValidation` (`ArchiveHealthChecker`). `transact` ora riceve il nome dell'operazione da ogni chiamante.
- `BusinessArchiveRules.swift` (nuovo, M2): regole per-entità (`session`, `package`, `packageCapacity`, `participant`, `packageUse`+`registerUse`, `ledgerEntry`+`registerSource`+`adjustmentLink`, `sessionEconomics`, `expense`, `checkExpiry`) con messaggi invariati. `BusinessArchive.validate` le chiama; restano in `validate` solo le regole globali (unicità id/preferenze, tariffe, rettifiche cumulative, addebiti/incassi orfani, pacchetti-economia, fatture, corsi, blocchi, overflow). `BusinessArchive.checkExpiry` inoltra alla regola.
- `ScopedValidation.swift` (nuovo, M1): dopo l'operazione, sul `writer`, fetch con `#Predicate` di sessione, partecipanti, clienti, servizi, pacchetti, utilizzi (per sessione e per pacchetto), movimenti per `sourceKey` (addebito+incasso) e commissioni; applica le stesse regole.
- `BusinessRepository`: `Validation.scoped(Set<UUID>)`; usato solo da `setSessionStatus(.completed)`. Nessun pre-controllo globale. `forceFullValidation` (internal) per i test. `.archive` invariato su `deleteSession`, `savePackage`, `deletePackage`, rimborsi/storni (`recordAdjustment`), `createInvoice*`, `saveBlock/saveCourse/saveExpense/saveService`; import/ripristino invariati (`BusinessArchive.insert`, `ArchiveSnapshot`). `save` posta `Notification.Name.paolaEconomicDataDidChange` dopo il commit se toccati `LedgerEntry/PackageUse/LessonPackage/Expense`.
- `ArchiveHealthChecker.swift` (nuovo, M4 API): `@ModelActor public actor` con `integrityWarnings()` e `fullValidation() -> String?`. Per girare nell'actor ho tolto `@MainActor` da `BusinessArchive.capture/uncanonicalizedCapture` (nessuna dipendenza dal main; i chiamanti `@MainActor` compilano invariati).
- Uso API dalla UI (Fase B): `ArchiveHealthChecker(modelContainer:)`; ricalcolo su `.paolaEconomicDataDidChange`, al lancio e dopo ripristino.

### Comportamento cambiato (dichiarato)
Il completamento non controlla più l'archivio intero prima della scrittura: un'incoerenza altrove non lo blocca più; la segnalano `integrityWarnings()`/`fullValidation()`. Il test `testUnrelatedCorruptionDoesNotBlockScopedButIsReportedByHealthChecker` lo documenta.
Limite noto (da Q3, invariato): i movimenti sono cercati per `sourceKey` minuscola esatta.

### Test aggiunti (`Tests/PaolaCoreTests`)
- `ScopedValidationTests` (11): doppio completamento (singolo, pacchetto, 3 partecipanti) con conteggi e archivio identici e sourceKey univoche; saldi/totali/usi/commissioni identici tra `forceFullValidation` e scoped + `validate`/`integrityWarnings` ok; pacchetto esaurito (nessuna scrittura parziale), scaduto, di altro cliente; multipartecipante con cliente archiviato (nessun movimento, stato invariato); addebito su lezione a pacchetto rifiutato; stessa sourceKey con importo diverso rifiutata; parità full/scoped su corpus di 6 mutazioni; incoerenza non correlata (spesa negativa); lezione completata congelata e `deleteSession` (`.archive`) che rimuove addebito/incasso/uso/commissione.
- `ArchiveHealthCheckerTests` (3): archivio sano; archivio corrotto; notifica postata dopo completamento, non dopo `setSessionBlack`.
- `WritePerformanceTests`: soglia completamento 6 s → 0,3 s. `AgendaWeeklyBenchmarkTests`: etichette completamento `.scoped`, nuova misura `ArchiveHealthChecker.fullValidation`.

### Risultati test (solo classi filtrate, 0 fallimenti)
ScopedValidationTests 11, ArchiveHealthCheckerTests 3, BusinessRepositoryTests 12, MultipleParticipantsTests 3, AutomaticIncomeTests 10, BusinessIntegrityTests 7, BusinessArchiveTests 8 (riga `Code=513` attesa), WritePerformanceTests 1, AgendaWeeklyBenchmarkTests 1.

### Tempi prima/dopo (Debug, mediana di 5; WritePerformanceTests singola misura)
| Operazione | Prima | Dopo | Variazione |
|---|---|---|---|
| completa 1 partecipante, senza pacchetto | 0,1826 s (.archive) | 0,0018 s (.scoped) | ~100× |
| completa 1 partecipante, con pacchetto | 0,1836 | 0,0019 | ~97× |
| completa 2 partecipanti, senza pacchetto | 0,1849 | 0,0022 | ~84× |
| completa 2 partecipanti, uno con pacchetto | 0,1862 | 0,0024 | ~78× |
| completamento ripetuto | 0,1187 | 0,0001 | no-op |
| WritePerformanceTests completamento (3200 lezioni) | 917 ms | 2 ms | ~450× |
| `ArchiveHealthChecker.fullValidation` (costo spostato) | – | 0,0650 | background |
| recordRefund / savePackage / saveBlock (.archive, invariati) | 0,2201 / 0,1870 / 0,1868 | 0,2106 / 0,1942 / 0,1945 | invariato |
| scritture `.local`, snapshot, @Query | – | – | invariate (rumore) |

Atteso dal piano: < 0,03 s e < 0,3 s → raggiunto con ampio margine.

### Non fatto / fuori scope fase A
UI (B1–B5), `docs/PERFORMANCE.md`, build app, esecuzione suite intera. Nessuna modifica a `project.pbxproj`: i nuovi file sono in `Sources/PaolaCore` (SwiftPM).

## Fase B (UI)
Nessun commit. Nessun gate `agenda-m1-m4-gate-ui.json` → implementazione.
### Comandi
- `xcrun swift build` → Build complete (dopo correzione di un errore: `PaolaSignpost.interval` è sincrono, in `IntegrityStatusView` uso `signposter.beginInterval/endInterval` attorno all'`await`).
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-macos.sh` → exit 0, app `build/Paola Gestionale.app`.
- Dominio non toccato in Fase B → nessun test eseguito (nessuna suite). `AgendaWeeklyBenchmarkTests` replica ancora la vecchia `makeSnapshot`: non misura il nuovo codice UI.
### Modifiche
- `AgendaViews.swift`: rimosse `@Query` di partecipanti/clienti/pacchetti/corsi/partecipanti corso; `blocks` con predicato di sovrapposizione alla finestra; `makeSnapshot() throws` con fetch mirati (`agenda.fetchWindow`) e `snapshotError`; `SnapshotKey` (periodo, inizio, stato, ricerca, `sessions.count`, max `updatedAt`, `blocks.count`, `revision`); `revision` incrementata da `.paolaEconomicDataDidChange`, chiusura editor e dopo ogni operazione agenda; signpost `agenda.makeSnapshot/fetchWindow/complete/togglePaid/toggleBlack/setStatus/reschedule`. `SessionDetailView` e viste di dettaglio invariate (query ampie).
- `SessionEditor.swift`: signpost `agenda.create`.
- `SharedViews.swift`: `IntegrityStatusView` senza `@Query`; `.task(id: revision)` con debounce (300 ms al lancio, 800 ms dopo), `ArchiveHealthChecker` in `Task.detached`, `fullValidation` solo al primo calcolo (lancio; dopo ripristino la vista è ricreata da `.id(storage.generation)`); signpost `integrity.refresh`. Stato solo in `@State`.
- `AppNavigation.swift`: nessuna modifica necessaria.
- `docs/PERFORMANCE.md` (nuovo).

### Fase B, giro correzione gate UI
- Finding: `IntegrityStatusView.refresh` perdeva l'avviso `fullValidation` dopo il primo refresh. Fix: `@State fullValidationMessage` conservato e riaggiunto a ogni refresh (`SharedViews.swift`).
- `xcrun swift build` → Build complete.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-macos.sh` → exit 0. App: `build/Paola Gestionale.app`.
- Nessun test eseguito (dominio non toccato). Nessun commit.
