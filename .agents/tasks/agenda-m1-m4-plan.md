# Piano M1–M4 + signpost (agenda)

Base: checkout corrente con Q1–Q7 NON committati (BusinessRepository, AgendaViews, OverviewView, ReminderSchedulerView, SharedViews, test bench). Preservare. Niente commit/push. Niente suite intera.

Vincoli di progetto (tech/structure): dominio in `PaolaCore`, UI in `PaolaApp`; `validate`/`integrityWarnings` O(n); nessuna cache persistente; scrittura in nuovo contesto, un'unica transazione; centesimi `Int64`.

Env comune:
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```
Test: `xcrun swift build --build-tests --scratch-path build/bench-after` poi
`xcrun xctest -XCTest <Classe> build/bench-after/debug/PaolaGestionalePackageTests.xctest`
(controllare il nome reale del bundle con `ls build/bench-after/debug | grep xctest`). `build/test-validation` NON usabile per i test (AppleSystemPolicy). Build lunghe: `run_in_background` + redirect su file (`> /tmp/x.txt 2>&1`), timeout ≥ 1200 s.

Classi ammesse: nuove (`ScopedValidationTests`, `ArchiveHealthCheckerTests`), `BusinessRepositoryTests`, `MultipleParticipantsTests`, `AutomaticIncomeTests`, `BusinessIntegrityTests`, `BusinessArchiveTests`, `WritePerformanceTests`, `AgendaWeeklyBenchmarkTests`.

## Decisioni

- Nuovo livello `Validation.scoped(sessionIDs)` (caso con payload) usato SOLO da `setSessionStatus(.completed)`. Controllo post-scrittura, sul contesto `writer`, limitato a sessione/partecipanti/clienti/pacchetti coinvolti/movimenti con le loro `sourceKey`/utilizzi/commissione. Niente pre-controllo globale: la coerenza di partenza è garantita da validazione globale al lancio, dopo ripristino e in background (M4). Conseguenza dichiarata: un archivio già incoerente altrove non blocca più il completamento; lo segnala `IntegrityStatusView`.
- Regole per-entità estratte da `BusinessArchive.validate` in un unico enum interno `BusinessArchiveRules`; `validate` e lo scoped le chiamano entrambi → non divergono. Test di parità lo dimostra.
- Restano `.archive`: `deleteSession`, `savePackage`, `deletePackage`, `recordRefund/Credit` (`recordAdjustment`), import/ripristino (`BusinessArchive.insert`, `ArchiveSnapshot.validate`), `createInvoice*`, `saveBlock/saveCourse/saveExpense/saveService` (invariati: la sez. 4 li dà come "possibile .local" ma NON richiesti dal task; non toccare). La sez. 4 non dimostra sicura una `.scoped` per `deleteSession` (storni collegati) → resta `.archive`.
- M4 su `@ModelActor` (contesto separato, fuori dal main): calcolo effimero, nessuna cache persistente.
- Signpost: `OSSignposter`, subsystem `local.paola.gestionale`, categoria dedicata `Performance`, solo `StaticString` costanti (nessun dato cliente/importo/nome). Categoria dedicata → visibile nello strumento "os_signpost" (non in Points of Interest, che mostra solo categoria `PointsOfInterest`); documentare.

---

# FASE A — Dominio (`Sources/PaolaCore`, `Tests/PaolaCoreTests`)

- [ ] A0. Baseline prima.
      Con il codice attuale (nessuna modifica): `swift build --build-tests --scratch-path build/bench-before` (background); eseguire `AgendaWeeklyBenchmarkTests` e `WritePerformanceTests` → `.agents/tasks/agenda-m1-m4/before.txt` (righe `[bench]`/`[perf]`). Se `/tmp/paola-bench-after.txt` (fine Q) è ancora valido, tenerlo come riferimento aggiuntivo.
      Verify: file `before.txt` contiene `completa appuntamento` con `.archive` e `setSessionStatus completed`; 0 fallimenti.

- [ ] A1. Signpost di dominio (prerequisito di tutto il resto: A2/A3 li usano).
      Nuovo `Sources/PaolaCore/PaolaSignpost.swift`: `public enum PaolaSignpost` con `public static let subsystem = "local.paola.gestionale"`, `category = "Performance"`, `signposter = OSSignposter(subsystem:category:)`, e helper `@discardableResult public static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T` (begin/end interval + `emitEvent` opzionale). Nome fisso, nessuna interpolazione di dati. `import os`.
      Instrumentare `BusinessRepository.transact` (intervalli: `transact`, `validation.pre`, `operation`, `validation.post`, `save`, `refetch` in `save(_:)`), aggiungendo a `transact` un parametro `_ name: StaticString` passato da ogni chiamante (`setSessionStatus`, `setParticipantPaid`, `setSessionsPaid`, `setSessionBlack`, `rescheduleSession`, `saveSession`, `deleteSession`, `savePackage`, `deletePackage`, `recordAdjustment`, …): così coprono completamento, pagato, sposta, crea, cambio stato senza toccare la UI. Intervalli anche in `BusinessReports.integrityWarnings` (`integrityWarnings`) e `BusinessArchive.uncanonicalizedCapture` (`archive.capture`).
      Files: `PaolaSignpost.swift` (nuovo), `BusinessRepository.swift`, `BusinessReports.swift`, `BusinessArchive.swift`.
      Verify: `xcrun swift build` → Build complete.

- [ ] A2. M2: estrarre regole per-entità (nessun cambio di comportamento).
      Nuovo `Sources/PaolaCore/BusinessArchiveRules.swift`: `enum BusinessArchiveRules` (internal) con static funcs che lanciano `BusinessError.inconsistentData`, spostate da `validate` (BusinessArchive.swift L104-~330) con gli stessi messaggi:
      - `session(_:serviceIDs:participants:)` (date, durata, stato, servizio, ≥1 partecipante senza duplicati)
      - `package(_:clientIDs:)` (cliente, capienza se non `.timed`, importo, scadenza ≥ acquisto)
      - `participant(_:session:package:clientIDs:)` (cliente, importo, pacchetto di altro cliente, `checkExpiry`)
      - `packageUse(_:session:package:sessionParticipants:)` → ritorna sourceKey (origine, pacchetto/cliente, sessione completata, partecipante corrispondente)
      - `ledgerEntry(_:clientIDs:)` (cliente, date, importo/segno, tipo/metodo, sourceKey non vuota) e `sameSource(_:_:)` (stessa sourceKey ⇒ stessi valori)
      - `adjustment(_:original:)` (refund→payment, credit→charge, stesso cliente, data ≥)
      - `sessionEconomics(session:participants:sources:useSources:)` (completata: pacchetto ⇒ un uso e nessun addebito; altrimenti addebito coerente e incasso opzionale coerente; non completata: nessun movimento/uso)
      - `packageCapacity(_:usedCount:)` (usi ≤ capienza, tempo escluso)
      - `expense(_:)`.
      `BusinessArchive.validate` chiama questi helper nei propri cicli. Restano in `validate` solo le regole globali: unicità id/preferenze, tariffe, rettifiche cumulative, addebiti/incassi orfani, fatture, corsi, blocchi, somme overflow. `checkExpiry` diventa statica in `BusinessArchiveRules`; l'istanza `BusinessArchive.checkExpiry` la inoltra (usata da `BusinessRepository.checkPackage`).
      Files: `BusinessArchiveRules.swift` (nuovo), `BusinessArchive.swift`.
      Verify: `xcrun swift build`; poi `xctest` su `BusinessArchiveTests`, `BusinessIntegrityTests`, `AutomaticIncomeTests` → 0 fallimenti (comportamento invariato, incluso corpus di mutazioni in `BusinessArchiveTests`).

- [ ] A3. M1: validazione mirata + integrazione in `transact`.
      1. Nuovo `Sources/PaolaCore/ScopedValidation.swift`: `enum ScopedValidation { static func validate(sessionIDs: Set<UUID>, in writer: ModelContext) throws }`. Con fetch a `#Predicate` (mai tabelle intere): `TrainingSession` per id; `SessionParticipant` per `sessionID`; `Client` per id partecipanti; `LessonPackage` per `packageID` partecipanti; `PackageUse` per `packageID` (capienza) e per `sessionID`; `LedgerEntry` per `sourceKey` in {addebito, incasso} di ogni partecipante (chiavi minuscole, come `fetchEntries`); `Expense` per `sourceKey` commissione. Costruire record (`*Record.init`) solo per quei sottoinsiemi e applicare `BusinessArchiveRules` (session, participant, package, packageUse, ledgerEntry+sameSource, sessionEconomics, packageCapacity, expense). Verifica anche: ≤ 1 addebito e ≤ 1 incasso per sourceKey (duplicati con valori diversi rifiutati), nessun addebito se il partecipante ha pacchetto, importi in centesimi (`BusinessRules.amount`).
      2. `BusinessRepository.transact`: `private enum Validation { case archive, local, scoped(Set<UUID>) }`. Ramo `.scoped`: esegue `operation`, se `writer.hasChanges` chiama `ScopedValidation.validate` (signpost `validation.post`), poi `save(writer)`; nessun fetch globale. Ramo `.archive` invariato. `setSessionStatus`: `validation: status == .completed ? .scoped([id]) : .local`. Idempotenza: `if session.status == status { return }` resta prima; nessuna modifica.
      3. Seam per test: `internal var forceFullValidation = false` su `BusinessRepository`; se true, `.scoped` usa il ramo `.archive`.
      4. Validazione globale disponibile: `ArchiveHealthChecker` (nuovo `Sources/PaolaCore/ArchiveHealthChecker.swift`): `@ModelActor public actor ArchiveHealthChecker` con `public func integrityWarnings() throws -> [String]` (fetch `LedgerEntry/LessonPackage/PackageUse` + `BusinessReports.integrityWarnings`) e `public func fullValidation() throws -> String?` (clienti duplicati, `uncanonicalizedCapture`, `validate`; ritorna messaggio o nil). Rimuovere `@MainActor` da `BusinessArchive.uncanonicalizedCapture`/`capture` se non necessario (i record init non richiedono main) così gira nell'actor; se il compilatore lo impone, aggiungere variante `nonisolated`. Aggiungere `public extension Notification.Name { static let paolaEconomicDataDidChange }` e postarla in `BusinessRepository.save` dopo il commit se tra i tipi toccati ci sono `LedgerEntry`, `PackageUse`, `LessonPackage`, `Expense`.
      Files: `ScopedValidation.swift`, `ArchiveHealthChecker.swift` (nuovi), `BusinessRepository.swift`, `BusinessArchive.swift`.
      Verify: `xcrun swift build` → Build complete; `BusinessRepositoryTests`, `MultipleParticipantsTests`, `AutomaticIncomeTests` → 0 fallimenti.

- [ ] A4. Test dominio (aree ad alto rischio: economia).
      Nuovo `Tests/PaolaCoreTests/ScopedValidationTests.swift` (usa `BusinessTestStore`, `@testable import PaolaCore`):
      1. doppio completamento: singolo senza pacchetto, con pacchetto, 3 partecipanti misti → conteggi `LedgerEntry`/`PackageUse`/`Expense` invariati alla 2ª chiamata.
      2. saldi identici: due store con stesso seed; uno completato con `forceFullValidation = true` (.archive), uno scoped; confrontare `BusinessReports` saldi per cliente, totali, usi residui, e `BusinessArchive.capture(...).validate` ok su entrambi, `integrityWarnings` vuoti.
      3. pacchetto esaurito (capienza 1, due lezioni): 2ª → `packageExhausted`, nessuna scrittura parziale.
      4. pacchetto scaduto alla data lezione → errore; pacchetto di altro cliente (partecipante inserito direttamente) → errore.
      5. multipartecipante: un partecipante con cliente archiviato → tutto annullato (nessun movimento dell'altro), stato sessione invariato.
      6. addebito per lezione a pacchetto preesistente (corruzione seminata) → rifiutato; stessa sourceKey con importo diverso → rifiutato.
      7. parità regole: corpus di mutazioni sul singolo completamento; per ognuna `forceFullValidation` e scoped devono entrambi lanciare o entrambi riuscire.
      8. incoerenza non correlata altrove (es. fattura con importo negativo seminata) non blocca lo scoped, ma `ArchiveHealthChecker.fullValidation()` la segnala.
      9. sessione completata resta congelata (`completedSessionLocked`) e `deleteSession` usa ancora `.archive` (regressione: storni rimossi coerentemente).
      Nuovo `ArchiveHealthCheckerTests.swift`: archivio sano → `integrityWarnings` vuoto e `fullValidation == nil`; archivio corrotto → messaggio non nil; notifica `paolaEconomicDataDidChange` postata dopo completamento e non dopo `setSessionBlack`.
      `WritePerformanceTests`: lasciare la soglia 5 s finché non si misura; dopo A5 abbassarla a ~3× il valore misurato (obiettivo < 0,3 s).
      Verify (solo classi filtrate): `ScopedValidationTests`, `ArchiveHealthCheckerTests`, `BusinessRepositoryTests`, `MultipleParticipantsTests`, `AutomaticIncomeTests`, `BusinessIntegrityTests`, `BusinessArchiveTests`, `WritePerformanceTests` → 0 fallimenti. Righe `Code=513` in alcuni log sono attese.

- [ ] A5. Misura dopo (dominio).
      In `AgendaWeeklyBenchmarkTests` (`benchmarkWrites`) cambiare le etichette del completamento da `.archive` a `.scoped`; aggiungere misura `ScopedValidation.validate` e `ArchiveHealthChecker.fullValidation` (costo spostato, non eliminato). Build in `build/bench-after`, eseguire `AgendaWeeklyBenchmarkTests` + `WritePerformanceTests` → `.agents/tasks/agenda-m1-m4/after-domain.txt`. Atteso: completamento dataset da ~0,19 s a < 0,03 s; 3200 lezioni da ~1 s a < 0,3 s; stesse asserzioni di idempotenza.
      Verify: tabella prima/dopo scritta in `.agents/tasks/agenda-m1-m4/report.md` (Fase B la completa). Se il guadagno < 3× → indagare prima di proseguire (fetch residui in `addTransactionFeeExpense`, `checkOverlap` blocchi).

---

# FASE B — UI (`Sources/PaolaApp`) e report

- [ ] B1. Signpost UI + M3 AgendaContent (`BusinessViews/AgendaViews.swift`).
      - Rimuovere `@Query` illimitate di `participants`, `clients`, `packages`, `courses`, `courseParticipants`. Restano `sessions` (finestra, già) e `blocks` con predicato di sovrapposizione alla finestra (`endDate > lower && startDate < upper`; verificare i nomi dei campi in `Unavailability`).
      - `makeSnapshot()` legge dal `context` (`@Environment(\.modelContext)`) con fetch mirati, risultato effimero nello snapshot (non cache): partecipanti `#Predicate { ids.contains($0.sessionID) }` con `ids` = id delle sessioni nella finestra; clienti per id dei partecipanti; per i corsi: `Course` con `weekdaysMask != 0`, `CourseParticipant` con `courseID` in corsi attivi, `LessonPackage` solo per `packageID` dei partecipanti corso. La ricerca per cliente usa i partecipanti già caricati della finestra (stesso risultato di prima: solo sessioni visibili).
      - Gestione errori: sostituire `_participants.fetchError ?? …` con `snapshotError: Error?` @State (mostra `ArchiveReadErrorView`).
      - Chiave snapshot leggera: `struct SnapshotKey: Equatable` (periodo, inizio, status, search, `sessions.count`, max `updatedAt` delle sessioni in finestra, `blocks.count`) + contatore `@State revision` incrementato da `.onReceive(NotificationCenter … .paolaEconomicDataDidChange)` e dopo ogni operazione agenda; `.onChange(of: key)`. Verificare che crea/modifica partecipanti, pagato, cambio stato, sposta aggiornino `session.updatedAt` (altrimenti la `revision` copre il caso; `setParticipantPaid` non tocca `updatedAt` → usa `revision`/osservazione dell'oggetto).
      - Signpost: `PaolaSignpost.interval("agenda.makeSnapshot")` attorno a `makeSnapshot`; `agenda.fetchWindow` attorno ai fetch.
      - Fuori ambito: `SessionDetailView`/L783-990 (`@Query` illimitate di dettaglio) NON toccate, salvo dire nel report che restano (rischio noto).
      Verify: `xcrun swift build` → ok. Test UI non eseguibili; verifica funzionale manuale elencata in B5.

- [ ] B2. M4 `IntegrityStatusView` (`SharedViews.swift`, `AppNavigation.swift`).
      Rimuovere `@Query` e calcolo nel body. Stato `@State warnings: [String]`, `@State failure: String?`. `.task(id: trigger)` con `trigger` = (id del container, `revision`): attende ~800 ms (`Task.sleep`, cancellabile ⇒ debounce), crea `ArchiveHealthChecker(modelContainer:)` e chiama `integrityWarnings()` + (solo al lancio e dopo ripristino) `fullValidation()` aggiungendo l'eventuale messaggio come avviso. `revision` cresce su `.onReceive(NotificationCenter.default.publisher(for: .paolaEconomicDataDidChange))`. Nessuna sostituzione dei dati in SwiftData, nessuna persistenza dei risultati. Lancio e `installRestoredStore` ricreano `container` → `trigger` cambia → ricalcolo (nessun codice extra in `StorageCoordinator`). Segnale `PaolaSignpost.interval("integrity.refresh")`. Mantenere stesso testo/layout dell'avviso.
      Verify: `xcrun swift build` ok.

- [ ] B3. Signpost UI restanti + documentazione Instruments.
      - `AgendaViews.swift`: `PaolaSignpost.interval` attorno a `complete(_:)` (nome `agenda.complete`), toggle pagato (`agenda.togglePaid`), cambio stato (L982 `agenda.setStatus`), spostamento drag (`agenda.reschedule`, L762-767), creazione (`SessionEditor.swift` salvataggio, `agenda.create`). Nomi costanti.
      - Nuovo `docs/PERFORMANCE.md` (la cartella non esiste: crearla) oppure sezione in `PROGETTO.md`: elenco nomi intervallo (`transact`, `validation.pre/post`, `operation`, `save`, `refetch`, `archive.capture`, `integrityWarnings`, `agenda.*`, `agenda.makeSnapshot`, `integrity.refresh`), subsystem `local.paola.gestionale`, categoria `Performance`; uso: Xcode → Product → Profile → template "os_signpost" (o "Logging"/"Time Profiler" + strumento os_signpost), filtro subsystem/categoria, vista "Intervals" per durata per nome; da terminale `log stream --signpost --predicate 'subsystem == "local.paola.gestionale"'`; nota: non appare in "Points of Interest" perché categoria dedicata; nessun dato personale/finanziario nei messaggi (solo nomi costanti).
      Verify: `xcrun swift build`.

- [ ] B4. Build app e misura finale.
      `DEVELOPER_DIR=… bash scripts/build-macos.sh` in background (timeout 1800 s) → Build ok. `swift build --build-tests --scratch-path build/bench-after`; eseguire `AgendaWeeklyBenchmarkTests`, `WritePerformanceTests`, e classi A4 → `after-final.txt`. Se i test UI-dipendenti non partono, dirlo.
      Verify: nessun errore; 0 fallimenti nelle classi filtrate.

- [ ] B5. Report `.agents/tasks/agenda-m1-m4/report.md` (+ copia sintetica in `.agents/tasks/agenda-m1-m4-report.md`).
      Contenuto: tabella prima/dopo (A0 vs A5/B4: completamento 4 varianti, ripetuto, 3200 lezioni, `makeSnapshot`, `@Query` non filtrate → fetch mirati), modifiche per M1–M4/signpost, regole preservate, comportamento cambiato (nessun pre-controllo globale sul completamento; validazione globale in `ArchiveHealthChecker`), rischi residui: M3 aggiornamento viste dopo modifiche (prova manuale: crea/modifica/sposta/completa/pagato/cancella appuntamento, cambio settimana, ricerca, corsi), `SessionDetailView`/`ReminderSchedulerView` ancora con query ampie, completamento ancora sul main thread (G1 non fatto), build Xcode (`project.pbxproj`) richiede di aggiungere a mano i nuovi file in `Sources/PaolaApp` radice (se ne aggiungi) — nuovi file sono in `PaolaCore`/`BusinessViews/` (cartella sincronizzata), quindi nessuna modifica a `project.pbxproj` (verificare che `PaolaCore` sia pacchetto SwiftPM e includa i file automaticamente).
      Verify: il report cita comandi eseguiti e output reali; nessun numero stimato presentato come misurato.

## Ordine e dipendenze
A0 → A1 → A2 → A3 → A4 → A5 → B1 (usa `PaolaSignpost`, notifica) → B2 (usa `ArchiveHealthChecker`) → B3 → B4 → B5. Ogni passo lascia `swift build` verde.

## Digest

| File | Blocco | Test | Verificato oggi |
|---|---|---|---|
| `Sources/PaolaCore/BusinessRepository.swift` | `private enum Validation { archive, local }` (L~896) e `transact(validation:_:)` (L~903); `setSessionStatus` L202 (`validation: status == .completed ? .archive : .local`); `save(_:)` con `refresh` per tipo (Q2) | `ScopedValidationTests`, `BusinessRepositoryTests`, `MultipleParticipantsTests`, `AutomaticIncomeTests`, `WritePerformanceTests` | `transact` ha 2 rami; `.archive` = fetch Client + `integrityWarnings` + 2× `uncanonicalizedCapture().validate` |
| `Sources/PaolaCore/BusinessArchive.swift` | `uncanonicalizedCapture` (L86, `@MainActor`), `validate(clientIDs:)` (L104-~330), `checkExpiry` (istanza), `insert(into:)` (L361) | `BusinessArchiveTests`, `BusinessIntegrityTests`, `AutomaticIncomeTests` | letto; `validate` usa dizionari, già O(n) |
| `Sources/PaolaCore/BusinessReports.swift` | `BusinessReports.integrityWarnings(entries:packages:uses:)` L164 (non isolata, pura) | `BusinessIntegrityTests` | letto |
| `Sources/PaolaApp/BusinessViews/AgendaViews.swift` | `AgendaContent` L62: 7 `@Query`, `init` L86 (finestra ±3 gg), `snapshotKey` L108, `makeSnapshot` L112, `.onAppear/.onChange` L185; `complete(_:)` ~L598; stato L644/650/762/982 | benchmark `AgendaWeeklyBenchmarkTests` (replica di `makeSnapshot`) | letto |
| `Sources/PaolaApp/SharedViews.swift` | `IntegrityStatusView` L64 (3 `@Query`, `integrityWarnings` nel body, Q1) | nessun test UI; benchmark replica | letto |
| `Sources/PaolaApp/AppNavigation.swift` | `IntegrityStatusView()` in `safeAreaInset` L61 | – | letto |
| `Sources/PaolaApp/StorageCoordinator.swift` | `open()` L57 e `installRestoredStore` L114 ricreano `container` | – | letto |
| `Tests/PaolaAppTests/AgendaWeeklyBenchmarkTests.swift` | `testWeeklyAgendaDatasetAndOperations` L194, `benchmarkWrites` L312 (etichette `.archive`) | stesso | passava a fine Q (0 fallimenti) |
| `Tests/PaolaCoreTests/WritePerformanceTests.swift` | `testLocalWritesOnLargeArchiveStayFast` L48 (soglie 0,5 s locali / 5 s completamento) | stesso | passava a fine Q |
| Nuovi | `PaolaSignpost.swift`, `BusinessArchiveRules.swift`, `ScopedValidation.swift`, `ArchiveHealthChecker.swift`, `ScopedValidationTests.swift`, `ArchiveHealthCheckerTests.swift`, `docs/PERFORMANCE.md` | – | – |

Comandi verificati nei report precedenti: `xcrun swift build --scratch-path build/test-validation` (ok); `swift build --build-tests --scratch-path build/bench-after` + `xcrun xctest -XCTest <Classe>` (ok). Non verificato in questo passo: nessuna build/test eseguiti (solo lettura codice).
