# Struttura e architettura

## Layout del repository

```
Package.swift              Manifesto SwiftPM (prodotti PaolaCore + PaolaGestionale)
PROGETTO.md                Documento di progetto completo (fonte di verità)
PaolaGestionale.xcodeproj  Progetto Xcode (UI multipiattaforma, test UI)
App/                       Info.plist e risorse dell'app
Config/                    Xcconfig (Local.xcconfig.example da copiare in Local.xcconfig)
Sources/
  PaolaCore/               Dominio: modelli, regole economiche, persistenza, report
  PaolaApp/                Presentazione: SwiftUI, navigazione, coordinamento storage
Tests/
  PaolaCoreTests/          Test del dominio (SwiftPM)
  PaolaAppTests/           Test dell'app
UITests/                   Test UI XCTest (schema PaolaGestionale-iOS-UI)
scripts/                   build-macos.sh, package-macos-release.sh
build/                     Output delle build e release (non versionare gli artefatti)
.github/workflows/         Pipeline di release macOS
```

## Livelli architetturali

L'architettura segue quattro livelli. Mantenere le dipendenze in una sola direzione:
la presentazione dipende dal dominio, non viceversa.

- **Presentazione** (`Sources/PaolaApp`): schermate e componenti SwiftUI specifici
  Mac/iPhone. Non contiene regole economiche.
- **Dominio** (`Sources/PaolaCore`): agenda, regole economiche, validazioni, report.
  Puro e testabile senza UI.
- **Persistenza** (`Sources/PaolaCore`): archivio locale SwiftData, schemi versionati,
  migrazioni, sincronizzazione.
- **Servizi di piattaforma**: notifiche, esportazioni PDF/CSV, backup cifrato.

## PaolaCore — dominio (dove vivono le regole)

Ogni nuova regola economica, di scheduling o di validazione va qui, con test associati.

- `Money.swift` — parsing/formatting importi in **centesimi** (`Int64`). Usare sempre
  questo tipo per il denaro, mai `Double`/`Float`.
- `BusinessModels.swift`, `BusinessRepository.swift`, `BusinessReports.swift`,
  `BusinessArchive.swift` — modelli, repository, report e archivio del dominio economico.
- `Client.swift`, `ClientDraft.swift`, `ClientRepository.swift`, `ClientSearch.swift` —
  anagrafica cliente, bozza di modifica, ricerca e duplicati.
- `ServiceRate.swift`, `AppointmentPreferences.swift`, `SchedulingSuggestions.swift` —
  listino/tariffe, preferenze e proposte di giorni/orari liberi.
- `SchemaV2.swift` … `SchemaV5.swift` — schemi SwiftData versionati. Ogni nuovo schema
  aggiunge una versione e la relativa migrazione, senza ricreare incassi o inventare dati.
- `StoreFactory.swift`, `CloudNamespace.swift` — creazione del container e namespace
  per account CloudKit (archivio locale distinto per account).
- `BackupCipher.swift`, `ArchiveSnapshot.swift` — cifratura backup e snapshot per ripristino.

## PaolaApp — presentazione

- `PaolaApp.swift`, `AppNavigation.swift` — entry point e navigazione (barra laterale su Mac).
- `OverviewView.swift` — panoramica a quattro righe.
- `ClientsView.swift`, `ClientDetailView.swift`, `ClientEditor.swift` — clienti.
- `BusinessViews/` — agenda, pagamenti, report, listino.
- `BackupView.swift`, `ReminderSchedulerView.swift`, `SettingsView.swift` — backup, promemoria, impostazioni.
- `Protection/` — blocco app con autenticazione di sistema.
- `StorageCoordinator.swift`, `SharedViews.swift` — coordinamento storage e componenti condivisi.

## Convenzioni

- Un file per tipo principale, nome file = nome del tipo.
- Tipi pubblici del dominio marcati `public` per l'uso da `PaolaApp` e dai test.
- Modifiche tramite **bozza** (draft): Annulla non deve alterare l'archivio.
- Scrittura in un **nuovo contesto SwiftData** con autosave disabilitato; il contesto
  osservato dalla UI non viene modificato durante il tentativo di salvataggio; si rileggono
  i dati solo dopo il commit. Un fallimento non deve lasciare modifiche parziali visibili.
- Il completamento di un appuntamento (anche con più partecipanti) registra addebiti,
  incassi e utilizzi in **un'unica transazione**; idempotente su ripetizione.
- Saldi e totali sono **calcolati** dai movimenti, mai modificabili a mano.
- Ogni record ha un identificativo stabile e metadati per la sincronizzazione;
  evitare vincoli di unicità incompatibili con CloudKit.

## Testing

- Regole del dominio: aggiungere test in `Tests/PaolaCoreTests`, eseguibili con `swift test`.
- Test isolati: archivi in memoria o cartelle temporanee, mai l'archivio dell'app né iCloud.
- Non aggiungere test automaticamente se non richiesto, ma le regole economiche e le
  migrazioni sono aree ad alto rischio: coprire idempotenza, saldi e migrazioni quando si tocca il dominio.
- **Non eseguire i test dopo aver sviluppato una funzionalità.** La suite è lenta e
  spesso non parte nell'ambiente dell'agente: lanciarla fa perdere tempo senza esito
  affidabile. Verifica con la sola compilazione (`xcrun swift build` o `./build-app.sh`)
  ed esegui `xcrun swift test` solo se l'utente lo chiede o prima di una release.
