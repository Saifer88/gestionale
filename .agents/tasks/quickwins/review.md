# Quick win Q1–Q7: review

Le modifiche implementano Q1–Q7 senza toccare M*/G*. Invarianti rispettate: nessun `Double` per il denaro, nessuna modifica a saldi o prezzi congelati, scritture ancora in nuovo contesto con rilettura dopo il commit. Il comportamento resta identico, salvo il punto sulle chiavi minuscole sotto.

Watch for: i predicate nuovi (`persistentModelID`, `keys.contains`, `originalEntryID != nil`) compilano ma non sono verificati a runtime (possible). Il confronto delle `sourceKey` ora è esatto (likely, vedi sotto).

**Verdict**: APPROVED

## High-level view

Q1 calcola i warning di integrità una volta per render. Q3/Q4 sostituiscono i fetch totali con predicate in setSessionStatus, deleteSession, savePackage, deletePackage, fatture e `client()`; il fetch `Invoice` di deleteSession è unico fuori dal ciclo. Q2 rilegge nel contesto UI per id gli inseriti/modificati e l'intero tipo solo se ci sono cancellazioni; aggiunto `Expense`. Q5 limita la `@Query` dei promemoria a pianificati futuri (limit 100). Q6 indicizza la riga "prossimi appuntamenti" con lo stesso sweep di `AgendaSnapshot.conflicts`. Q7 mostra un indicatore, blocca il doppio tocco e passa gli errori a `operation.capture`.

<details>
<summary>Issues (4)</summary>

1. **Predicate non verificati a runtime** (possible) — eseguire `WritePerformanceTests`, `AgendaWeeklyBenchmarkTests` e la suite completa prima della release; in particolare `ids.contains($0.persistentModelID)` in `save`.
2. **Confronto sourceKey esatto** (likely) — prima `lowercased()` su entrambi i lati, ora uguaglianza con chiave minuscola. Le chiavi generate dall'app sono minuscole (`BusinessModels`, `Expense`, `Invoice`), ma archivi importati/ripristinati con maiuscole non verrebbero più trovati (duplicato commissione, cancellazioni). Non bloccante; aggiungere un test di ripristino se serve.
3. **Q7 resta sincrono sul main** (confirmed) — l'indicatore compare grazie ai 50 ms di attesa, ma la UI si blocca durante la scrittura finché non si fa G1. Atteso dal piano.
4. **Fetch completo residuo in `BusinessRepository` L804 (LedgerEntry)** (confirmed) — fuori dall'elenco Q3 ma sul percorso di scrittura; candidato per M*.

</details>

<details>
<summary>Details</summary>

### Rilettura mirata in `save`
Gli id sono letti dopo `saveChanges`, quindi gli inseriti hanno già l'identificatore permanente. Le cancellazioni mantengono il fetch completo del tipo perché gli id cancellati non sono più recuperabili. Aggiungere `Expense` corregge un'omissione. Rischio residuo: la visibilità in `@Query` di inserimenti/modifiche/cancellazioni va confermata in app.

### Chiavi sourceKey in minuscolo
`fetchEntries`/`fetchExpenses` usano `keys.contains($0.sourceKey)`. Tutti i generatori di chiavi usano `uuidString.lowercased()`, quindi per dati creati dall'app il risultato è identico. Il rischio riguarda solo dati con chiavi in maiuscolo.

### Promemoria (Q5)
Il filtro `planned && startDate > now` è fissato a `init`. Una sessione che esce dalla finestra viene comunque rimossa dalla signature e i promemoria si riallineano. Il limite 100 copre il `prefix(60)` più quelli scartati per anticipo.

### Panoramica (Q6)
Il criterio di conflitto replica `BusinessDates.conflicts`: stato attivo, sovrapposizione con altre sessioni attive (sweep) o con blocchi. Nessuna differenza trovata.

</details>

<details>
<summary>File map</summary>

- `Sources/PaolaCore/BusinessRepository.swift`: predicate, helper fetch, rilettura mirata, Expense
- `Sources/PaolaApp/SharedViews.swift`: warnings nel body
- `Sources/PaolaApp/ReminderSchedulerView.swift`: Query filtrata e limitata
- `Sources/PaolaApp/OverviewView.swift`: UpcomingIndex
- `Sources/PaolaApp/BusinessViews/AgendaViews.swift`: stato in corso, anti doppio tocco, errori mostrati

Diff completo: `git diff` nel checkout.

</details>
