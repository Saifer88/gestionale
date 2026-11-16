# Report quick win agenda (Q1–Q7)

Richiesta: agenda lenta con molti appuntamenti, clienti, servizi e pacchetti. "Partiamo coi quick e vediamo se la cosa migliora".

Ambiente: build Debug SwiftPM, macOS arm64, archivio in memoria, dati inventati.
Dataset benchmark: 40 clienti, 30 servizi, 786 appuntamenti (35/settimana), 906 partecipanti, 39 pacchetti, 846 movimenti.
Baseline: `.agents/tasks/quickwins/baseline.md`. Dopo: `/tmp/paola-bench-after.txt`.
Tempi in secondi (mediana di 5 ripetizioni); `WritePerformanceTests` in ms (3200 lezioni, singola misura).

## Tempi prima/dopo

| Operazione | Validazione | Prima | Dopo | Variazione |
|---|---|---|---|---|
| fetch sessioni settimana | - | 0,0005 | 0,0005 | invariato |
| @Query non filtrate | - | 0,0061 | 0,0062 | invariato |
| makeSnapshot settimana | - | 0,0022 | 0,0023 | invariato |
| uncanonicalizedCapture | .archive | 0,0559 | 0,0567 | +1% (rumore) |
| validate(clientIDs:) | .archive | 0,0073 | 0,0076 | rumore |
| integrityWarnings | .archive | 0,0527 | 0,0570 | +8% (rumore) |
| completa 1 partecipante, senza pacchetto | .archive | 0,2065 | 0,1933 | -6% |
| completa 1 partecipante, con pacchetto | .archive | 0,2051 | 0,1930 | -6% |
| completa 2 partecipanti, senza pacchetto | .archive | 0,2159 | 0,1979 | -8% |
| completa 2 partecipanti, uno con pacchetto | .archive | 0,2180 | 0,1976 | -9% |
| completamento ripetuto (idempotenza) | .archive | 0,1187 | 0,1274 | +7% (rumore) |
| setParticipantPaid | .local | 0,0135 | 0,0008 | -94% |
| setSessionsPaid (10 lezioni) | .local | 0,0191 | 0,0023 | -88% |
| setSessionBlack | .local | 0,0079 | 0,0005 | -94% |
| recordRefund | .archive | 0,2145 | 0,2172 | invariato |
| rescheduleSession | .local | 0,0084 | 0,0010 | -88% |
| setSessionStatus cancelled | .local | 0,0078 | 0,0004 | -95% |
| saveSession (crea) | .local | 0,0145 | 0,0012 | -92% |
| savePackage (acquisto) | .archive | 0,1963 | 0,1965 | invariato |
| saveBlock (indisponibilità) | .archive | 0,1944 | 0,1981 | +2% (rumore) |

WritePerformanceTests (3200 lezioni):

| Operazione | Prima (ms) | Dopo (ms) | Variazione |
|---|---|---|---|
| setParticipantPaid | 58 | 1 | -98% |
| setSessionBlack | 33 | 0 | -100% |
| rescheduleSession | 33 | 1 | -97% |
| saveSession | 60 | 1 | -98% |
| setSessionStatus completed | 1046 | 983 | -6% |

Lettura: le scritture `.local` scendono di un ordine di grandezza (Q2: rilettura mirata nel contesto UI invece del fetch completo dei tipi, Q3: predicate). Le operazioni `.archive` e il completamento restano dominati dalla validazione globale (~0,19 s sul dataset; ~1 s con 3200 lezioni). Sono il prossimo collo di bottiglia e richiedono interventi più grandi (M*/G*), non quick win.
Q1, Q5, Q6, Q7 agiscono sulla UI (render, promemoria, panoramica, indicatore di avanzamento): i benchmark non li misurano.

## Modifiche per Qn

- **Q1** `SharedViews.swift`, `IntegrityStatusView`: rimossa la proprietà calcolata `warnings`. Il calcolo avviene una volta nel body.
- **Q2** `BusinessRepository.save`: raccoglie inserted/changed/deleted prima del commit. Dopo `saveChanges` rilegge nel contesto UI: fetch completo del tipo solo se ci sono cancellazioni, fetch con `#Predicate { ids.contains($0.persistentModelID) }` per inserimenti/modifiche. Aggiunto `Expense` all'elenco dei tipi.
- **Q3** `BusinessRepository`: helper privati `fetchParticipants(ofSession:)`, `fetchEntries(withSourceKeys:)`, `fetchExpenses(withSourceKeys:)`. Predicate al posto di "fetch tutto + filtro" in `setSessionStatus`, `deleteSession`, `setSessionsPaid`, `addTransactionFeeExpense`, `savePackage`, `deletePackage`, `createInvoiceForSession`, `ensureNotAlreadyInvoiced`, `checkPackage`, `client()`.
- **Q4** `deleteSession`: un solo fetch `Invoice` fuori dal ciclo sui partecipanti.
- **Q5** `ReminderSchedulerView`: `Query` con filtro `statusRaw == planned && startDate > now`, ordinata, `fetchLimit` 100. `signature` usa solo quelle sessioni.
- **Q6** `OverviewView`: `UpcomingIndex` (partecipanti per sessione, clienti per id, conflitti con sweep ordinato, blocchi) calcolato una volta e passato a `dayColumn`/`upcomingRow`/`upcomingName`.
- **Q7** `AgendaViews.swift`, `completedIcon`: stato `completingSessionIDs`, `ProgressView` al posto del pulsante, `complete(_:)` in `Task { @MainActor }` dopo 50 ms, errori via `operation.capture`, blocco del doppio tocco. L'operazione resta sincrona sul main (G1 non fatto).

## Qn non fatti

Nessuno. M* e G* non toccati.

## Esito build e test

- `DEVELOPER_DIR=… xcrun swift build --scratch-path build/test-validation`: Build complete, exit 0.
- `swift build --build-tests --scratch-path build/bench-after`: Build complete.
- Test eseguiti con `xcrun xctest -XCTest <Classe>` sul bundle (solo classi filtrate, mai la suite intera), 0 fallimenti:
  - AgendaWeeklyBenchmarkTests: 1 test
  - WritePerformanceTests: 1 test (setSessionStatus completed < 5 s, scritture locali < 0,5 s)
  - BusinessRepositoryTests: 12
  - MultipleParticipantsTests: 3
  - AutomaticIncomeTests: 10
  - BusinessIntegrityTests: 7
  - BusinessArchiveTests: 8
  - InvoiceCreationTests: 7
  - SessionProvisionalRescheduleTests: 10
  - ServiceTariffsTests: 7
  - BusinessReportsTests: 9
  - InvoiceArchiveTests: 2
  - OverviewSummaryTests: 5
  - AgendaSchedulingTests: 1
- Nel log di BusinessArchiveTests e ServiceTariffsTests compaiono righe `SwiftData.DefaultStore save failed ... Code=513`. Sono attese: i test simulano un salvataggio fallito e risultano passati.
- Nessuna correzione di codice di produzione necessaria.
- Nota ambiente: `build/test-validation` non si può usare per i test (dlopen bloccato da AppleSystemPolicy), per questo i test usano `build/bench-after`.

## Rischi residui

- **Q2 (principale)**: la rilettura mirata per `persistentModelID` e il fetch completo solo con cancellazioni non sono verificati nell'app reale. Rischio: una vista basata su `@Query` potrebbe non riflettere subito un inserimento/modifica/cancellazione (agenda, pagamenti, pacchetti). I test di dominio usano contesti separati e non coprono la UI. Da provare a mano: crea, modifica e cancella appuntamento, pagamento, pacchetto, spesa, blocco.
- **Q3**: i confronti `sourceKey.lowercased() == key` sono diventati uguaglianze esatte con chiave minuscola. Le chiavi generate dall'app sono minuscole. Dati importati con maiuscole non sarebbero più trovati (duplicato commissione, cancellazioni collegate).
- **Q5/Q6**: logica di filtro promemoria e conflitti in panoramica riscritta. Nessun test UI specifico; OverviewSummaryTests passa ma non copre `UpcomingIndex`.
- **Q7**: la UI si aggiorna con 50 ms di ritardo, ma il completamento blocca ancora il main thread (~0,2 s sul dataset, ~1 s con 3200 lezioni). Il vero guadagno richiede G1 e una validazione meno costosa.
- Le misure sono Debug, singola macchina, mediane di 5 ripetizioni. Le variazioni sotto il 10% sulle operazioni `.archive` sono nel rumore.
- Suite completa (~230 test) non eseguita, come da regole di progetto. Eseguirla prima della release.
