# Report performance agenda (investigazione sola lettura)

Metodo: analisi statica del codice. Nessun tempo misurato in questa investigazione: `swift build` è andato in timeout a 120 s (build a freddo, nessun errore emerso) e il benchmark del workflow `wf_3a4f48708434af12` (`.agents/tasks/agenda-benchmark-report.md`) non esisteva ancora. Le stime di impatto sono quindi ragionate, da confermare con quel benchmark.

## 1. Risposta in sintesi

La lentezza ha tre cause, in ordine di peso:

1. **Validazione `.archive` su ogni operazione economica** (`BusinessRepository.transact`). Il completamento di un appuntamento (`setSessionStatus(.completed)`) legge e converte l'intero archivio più volte: `integrityWarnings`, una `validate` prima e una dopo la scrittura. Costo O(archivio) per ogni click sul "check" giallo dell'agenda. I test attuali accettano fino a 6 s per il completamento (3000 lezioni).
2. **Rilettura completa delle tabelle dopo il commit** (`BusinessRepository.save`, funzione `refresh`). Per ogni tipo toccato fa `context.fetch(FetchDescriptor<T>())` senza predicato sul contesto della UI. Anche le scritture `.local` (pagato, bianco/nero, sposta) rileggono tutte le `TrainingSession` e/o tutti i `SessionParticipant`. Tutto sul main thread.
3. **Viste sempre vive che ricalcolano sull'intero archivio a ogni cambio**:
   - `IntegrityStatusView` (in `AppNavigation`, `safeAreaInset(.top)`) fa `@Query` di tutti i `LedgerEntry`/`LessonPackage`/`PackageUse` e ricalcola `integrityWarnings` (con sort di `canonicalEntries`) a ogni modifica, **due volte per render** (la proprietà `warnings` viene letta in `!warnings.isEmpty` e di nuovo in `ForEach`/`count`).
   - `ReminderSchedulerView` (`.background` della root) fa `@Query` di tutte le sessioni e costruisce la stringa `signature` con una riga per sessione a ogni render.
   - `AgendaContent` limita le sessioni alla finestra visibile, ma `participants`, `clients`, `packages`, `blocks`, `courses`, `courseParticipants` restano `@Query` senza filtro. `makeSnapshot` raggruppa tutti i partecipanti a ogni ricalcolo.
   - `OverviewView` carica 9 tabelle intere e ricalcola `OverviewSummary` in un `TimelineView` ogni 60 s.

Ogni click quindi paga: validazione globale (1) + rifetch totale (2) + re-render/ricalcolo di 3-4 viste globali (3), tutto sincrono sul main thread.

## 2. Evidenze

### 2.1 `transact(.archive)` — `Sources/PaolaCore/BusinessRepository.swift` ~L882-908
- Fetch di tutti i `Client`, poi `integrityWarnings(entries, packages, uses)` su tutti i movimenti (`BusinessReports.swift` L164: ordina in `canonicalEntries`, legge molte proprietà `@Model` per riga, `lowercased()` sulle `sourceKey`).
- `BusinessArchive.uncanonicalizedCapture(context:)` (`BusinessArchive.swift` L86) fa 13 fetch di tabelle intere e converte ogni `@Model` in un record. Viene chiamata **due volte** (prima e dopo l'operazione), e `validate(clientIDs:)` (L104) ripassa su tutto, comprese fatture, spese e corsi che il completamento di una lezione non tocca.
- `validate` è O(n) (usa dizionari), ma con costante alta: letture di proprietà SwiftData, `Calendar.current.startOfDay` per partecipante con pacchetto, `lowercased()` ripetuto. Il guadagno più grande sta nel non eseguirla, non nell'ottimizzarla.
- Il pre-controllo è ridondante rispetto al post-controllo per lo scopo dell'operazione: serve solo a non peggiorare un archivio già incoerente.

### 2.2 Completamento — `setSessionStatus` (L202-257)
- Valida con `.archive` solo quando `status == .completed`.
- `writer.fetch(FetchDescriptor<SessionParticipant>()).filter { $0.sessionID == id }`: fetch totale invece di `#Predicate` (già usato in `saveSession`).
- Per ogni partecipante: `client(_:in:)` (L846) fa fetch di **tutti i clienti** + `first(where:)`; `checkPackage` (L817) fa fetch di **tutti i `PackageUse`** e `BusinessReports.used` filtra `uses` ricostruendo la `sourceKey` per ciascuno. `addTransactionFeeExpense` (L447) fa fetch di **tutte le `Expense`** e confronta `sourceKey.lowercased()` per cercare un duplicato. Costo O(partecipanti × archivio).
- `checkOverlap` è già a finestra, ma rifetcha tutte le `Unavailability`.

### 2.3 Rilettura dopo il salvataggio — `save` (L910-930)
`refresh` esegue `context.fetch(FetchDescriptor<T>())` completo per ogni tipo modificato. Per `setSessionStatus(.completed)` tocca `TrainingSession`, `LedgerEntry`, `PackageUse`, `Expense`... e `Expense` non è nemmeno nell'elenco dei `refresh`. Il fetch totale materializza migliaia di oggetti nel contesto principale, poi ogni `@Query` attiva si rivaluta.

### 2.4 Altre scritture con fetch totale
- `deleteSession` (L259): `.archive`, fetch di `SessionParticipant`, `LedgerEntry`, `PackageUse`, `Expense`, e `Invoice` **dentro il ciclo sui partecipanti**.
- `setSessionsPaid` (L367, `.local`): fetch di tutti i partecipanti.
- `saveSession` (`.local`): fetch di tutte le `ServiceRate`, tutte le `ClientAppointmentPreference` (con `delete` per cliente), `client()` per partecipante, `checkPackage`.
- `savePackage` (L459), `deletePackage` (L577): fetch totali di `PackageUse`, `LedgerEntry`, `Expense`; `.archive`.
- `ensureNotAlreadyInvoiced` (L673): fetch totale `Invoice`.
- `recordAdjustment` (rimborsi/storni, L794): `.archive` e fetch totale di `LedgerEntry` più `canonicalEntries`.
- `recordPayment` è disabilitato (`manualPaymentsDisabled`): l'incasso nasce solo dal completamento o dal pacchetto. "Registrazione pagamento" lenta = completamento o `setParticipantPaid` o rimborso.

### 2.5 UI — dove si rifiltra l'archivio
| Dove | Problema |
|---|---|
| `SharedViews.swift` `IntegrityStatusView` | `@Query` 3 tabelle intere; `warnings` calcolato 2×/render |
| `ReminderSchedulerView.swift` | `@Query` tutte le sessioni ordinate; `signature` concatena una riga per sessione a ogni render; `.task(id:)` rieseguito a ogni cambio |
| `AgendaViews.swift` `AgendaContent` | 6 `@Query` illimitate; `snapshotKey` è una stringa ricostruita a ogni body; `makeSnapshot` fa `Dictionary(grouping: participants)` su tutta la tabella e `conflicts(in: sessions)` |
| `AgendaViews.swift` `SessionDetailView` | `@Query` illimitate di `participants`, `clients`, `sessions`; `people` = `participants.filter { sessionID }` per ogni accesso |
| `AgendaViews.swift` `session(_:)` | `sessions.first { $0.id == id }` nel drag (anche per ogni `hourRows`) |
| `OverviewView.swift` | 9 `@Query` intere; `upcomingRow` filtra `participants` e chiama `BusinessDates.conflicts(sessions, blocks)` **per riga**; `upcomingName` fa `clients.first(where:)` per partecipante |
| `ClientsView`, `ClientDetailView`, `PackagesView`, `CoursesViews` | `@Query` intere e `filter`/`remaining(package:uses:)` per riga (O(pacchetti × utilizzi)) |
| `AppRoute.swift` | `@Query` del modello intero per risolvere un solo id con `first(where:)` |
| `CourseOccurrences.expand` | `participants.filter { courseID }` per corso; accettabile con pochi corsi |

`snapshotKey` non include lo stato delle sessioni né i valori dei movimenti: lo snapshot si rigenera solo su cambio di conteggi. Funziona perché lo snapshot tiene riferimenti a oggetti `@Observable`, ma è fragile e non evita il costo del `body`.

### 2.6 Cosa misura `WritePerformanceTests.swift`
Seed: 60 clienti, 3200 lezioni (3000 completate con addebito+incasso), 1 partecipante per lezione. Misura `setParticipantPaid`, `setSessionBlack`, `rescheduleSession`, `saveSession` (soglia 0,8 s) e un solo `setSessionStatus(.completed)` (soglia 6 s).
Manca:
- servizi, tariffe, pacchetti (lezioni e a tempo), `PackageUse`, spese, fatture, corsi, blocchi;
- lezioni a pacchetto e con più partecipanti;
- il tempo del **rifetch nel contesto UI** (`save()` con un `ModelContext` osservato che ha già caricato i dati);
- il costo delle viste (`AgendaContent.makeSnapshot`, `IntegrityStatusView.warnings`, `OverviewSummary`);
- `deleteSession`, `savePackage`, `recordRefund`, `setSessionsPaid`.
La soglia di 6 s per il completamento è molto permissiva: un utente la percepisce come blocco.

## 3. Interventi prioritari

Regole rispettate: nessuna cache persistente di dati; nessuna modifica a idempotenza, saldi, prezzi congelati, sedute completate congelate.

### Quick win (basso rischio)
| # | Intervento | File/funzioni | Impatto | Rischio | Sforzo |
|---|---|---|---|---|---|
| Q1 | `IntegrityStatusView`: calcolare `warnings` una volta per render (`let warnings = ...` nel body). | `SharedViews.swift` | Medio (dimezza il costo per ogni scrittura economica) | Basso | 5 min |
| Q2 | `save()`: sostituire il rifetch completo con rifetch mirato agli id toccati (`#Predicate { ids.contains($0.id) }`) oppure, per le sole modifiche, nessun rifetch (le entità osservate si aggiornano con `context.processPendingChanges` / il refetch per id che oggi serve a fondere i valori). Mantenere il rifetch completo solo per inserimenti/cancellazioni. Aggiungere `Expense` all'elenco. | `BusinessRepository.save` | Alto su archivi grandi | Medio: la regola di progetto "rileggere solo dopo il commit" va mantenuta; verificare che le `@Query` vedano le modifiche | 2-3 h |
| Q3 | Sostituire i fetch totali con `#Predicate`: `SessionParticipant` per `sessionID` (L212, L262, L372, L616), `Client` per id in `client()`, `PackageUse` per `packageID` in `checkPackage`/`savePackage`/`deletePackage`, `LedgerEntry` e `Expense` per `sourceKey` (`addTransactionFeeExpense`, `deletePackage`, `deleteSession`), `Invoice` per `sourceKey`, `PackageUse` per `sessionID`. | `BusinessRepository.swift` | Alto sul completamento e sulle eliminazioni | Basso (stesso risultato, già usato in `find`/`saveSession`) | 3-4 h |
| Q4 | Portare `client()` fuori dal ciclo e usare `find`-style con predicato; spostare il fetch `Invoice` di `deleteSession` fuori dal ciclo partecipanti. | `BusinessRepository.swift` | Medio | Basso | 1 h |
| Q5 | `ReminderSchedulerView`: `@Query` con predicato `status == planned && startDate > now` e limite (`fetchLimit` 60), `signature` basata su quei soli elementi. | `ReminderSchedulerView.swift` | Medio (rimuove O(sessioni) da ogni render) | Basso | 1 h |
| Q6 | `OverviewView.upcomingRow`: usare indici (`Dictionary(grouping:)` dei partecipanti, dizionario clienti, conflitti calcolati una volta) invece di filtri per riga. | `OverviewView.swift` | Medio | Basso | 2 h |
| Q7 | Eseguire il completamento fuori dal gesto sincrono: mostrare uno stato "in corso" e bloccare il doppio click (idempotenza già garantita dalle `sourceKey`). | `AgendaViews.swift` `completedIcon`; oggi `try?` ingoia anche gli errori: usare `operation.capture`. | Percepito alto | Basso | 1 h |

### Refactor medi
| # | Intervento | File/funzioni | Impatto | Rischio | Sforzo |
|---|---|---|---|---|---|
| M1 | **Validazione mirata per il completamento**: sostituire `.archive` con un livello `.scoped` che controlla solo le regole toccabili: sessione e partecipanti, cliente attivo, pacchetto (scadenza, capienza, appartenenza), unicità `sourceKey` di addebito/incasso/uso, importo, commissione. Le regole globali (duplicati, rettifiche) non cambiano con un completamento. Lasciare `.archive` solo a `deleteSession`, `savePackage`, `deletePackage`, rimborsi/storni, import/ripristino. Eseguire la validazione globale in background (e al lancio/dopo restore) invece che a ogni click. | `BusinessRepository.transact`, `setSessionStatus`, nuovo tipo `Validation.scoped`; test di idempotenza e saldo da estendere | **Molto alto**: elimina il costo O(archivio) dal percorso più usato | Medio-alto (area economica ad alto rischio): servono test su doppio completamento, pacchetto esaurito/scaduto, partecipanti multipli, arrotondamenti | 1-2 gg |
| M2 | Estrarre da `BusinessArchive.validate` regole per-entità riusabili (es. `validateSession(_:participants:)`, `validatePackageUse`) usate sia da `.scoped` sia dalla validazione completa, così non divergono. | `BusinessArchive.swift` | Abilita M1 | Medio | 1 gg |
| M3 | `AgendaContent`: sostituire `@Query` illimitate di partecipanti/clienti/corsi con query filtrate sulla finestra (`sessionID in visibleSessionIDs` non è esprimibile in `#Predicate` con grandi insiemi; alternativa: caricare i partecipanti della finestra via fetch dopo aver letto le sessioni, in `makeSnapshot`). Calcolare la chiave dello snapshot da un contatore leggero. | `AgendaViews.swift` | Alto con molti clienti/partecipanti | Medio | 1 gg |
| M4 | `IntegrityStatusView`: eseguire `integrityWarnings` in un `Task` su un `ModelContext` separato, con debounce, solo dopo operazioni economiche (non a ogni cambio di `@Query`). Non è una cache persistente: è un calcolo derivato effimero. | `SharedViews.swift`, `AppNavigation.swift` | Alto | Medio | 0,5-1 gg |
| M5 | `PackagesView`/`ClientDetailView`: calcolare utilizzi per pacchetto con un indice (`Dictionary(grouping: uses, by: \.packageID)`) una volta per render; `BusinessReports.used` accetta già un array filtrato. | `PackagesViews.swift`, `ClientDetailView.swift`, `BusinessReports.used` | Medio | Basso | 0,5 gg |

### Refactor grandi
| # | Intervento | Impatto | Rischio | Sforzo |
|---|---|---|---|---|
| G1 | Spostare le scritture pesanti su un `ModelActor`/contesto in background e rendere l'API del repository `async`; la UI mostra avanzamento e si aggiorna al merge. | Alto (UI sempre reattiva) | Alto: `BusinessRepository` è `@MainActor`, il test usa contesti sincroni; cambia tutta la UI chiamante | 3-5 gg |
| G2 | `OverviewSummary` incrementale per periodo (query per mese invece di tabelle intere), con `@Query` filtrate su `selectedMonth`. | Medio-alto | Medio (report economici) | 2-3 gg |

Ordine consigliato: Q3 + Q4 → Q1 → Q2 → M1/M2 → Q5/Q6/M3/M4/Q7 → M5 → G2/G1 solo se serve ancora.
Per il caso d'uso (cambio stato a completato), Q3+Q4+M1 eliminano la parte dominante; Q2 e M3/M4 eliminano la lentezza residua dopo il commit.

## 4. Operazioni e validazione

| Operazione | Oggi | Possibile |
|---|---|---|
| `setSessionStatus(.completed)` | `.archive` | `.scoped` (M1) |
| `setSessionStatus` altri stati | `.local` | invariato |
| `setParticipantPaid`, `setSessionsPaid`, `setSessionBlack`, `setPackageBlack`, `rescheduleSession`, `saveSession` | `.local` | invariato; ridurre fetch (Q3) e rifetch (Q2) |
| `deleteSession` | `.archive` | `.scoped` solo se si limita alle entità della sessione e alle rettifiche che le referenziano; rimborsi/storni collegati rendono il rischio medio |
| `savePackage`, `deletePackage`, `saveBlock`, `saveCourse`, `saveService`, `saveExpense` | `.archive` (default) | `saveBlock`/`saveCourse`/`saveExpense`/`saveService` non toccano movimenti: `.local` con controlli propri (verificare che nessuna regola di `validate` possa violarsi) |
| `recordRefund`/`recordCredit` | `.archive` | `.scoped` sul solo movimento originale e i suoi storni |
| `createInvoice*` | `.archive` | `.local`: la validazione delle fatture è solo di integrità di base |

Nota: nessuna di queste scelte indebolisce le invarianti, se la validazione mirata mantiene i controlli su `sourceKey` univoca, importi in centesimi, pacchetto cliente/scadenza/capienza e assenza di addebito per lezioni a pacchetto.

## 5. Misure e benchmark da aggiungere

Estendere `WritePerformanceTests` (o riusare i file del workflow `wf_3a4f48708434af12`):
1. Seed realistico: 300 clienti, 30-60 servizi con tariffe, 100-200 pacchetti (lezioni e a tempo) con `PackageUse`, 30% delle sessioni a pacchetto, sessioni con 2-3 partecipanti, spese con commissioni, fatture, corsi, blocchi.
2. Un `ModelContext` UI già popolato (fetch iniziale) per misurare `save()` incluso il rifetch.
3. Tempi separati per: `integrityWarnings`, `uncanonicalizedCapture`, `validate`, `refresh`.
4. Operazioni: completamento singolo, completamento a pacchetto, con 3 partecipanti, `deleteSession`, `savePackage`, `recordRefund`, `setSessionsPaid` su 50 sessioni.
5. Soglie realistiche: completamento < 0,5 s a regime (oggi 6 s), scritture locali < 0,3 s.
6. Test di crescita: stessa operazione con N e 2N record, per intercettare comportamenti quadratici (rapporto < 2,5).
7. Test di correttezza per M1: doppio completamento idempotente; saldo identico con `.archive` e `.scoped`; pacchetto esaurito/scaduto rifiutato.
8. App: misura del `body` di `AgendaContent`/`IntegrityStatusView`/`OverviewView` con Instruments (SwiftUI, Time Profiler) o `os_signpost` su `makeSnapshot` e `warnings`.

## 6. Limiti
- Nessun tempo misurato: priorità e impatti derivano dalla lettura del codice.
- Build non completata entro 120 s nel mio ambiente; nessun file modificato.
