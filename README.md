# Paola Gestionale

Applicazione nativa (macOS e iOS) per la gestione del lavoro di un singolo personal
trainer: anagrafica clienti, agenda/appuntamenti, servizi e listino, pacchetti,
pagamenti e saldo, riepiloghi economici, backup cifrato e fatturazione elettronica
(regime forfettario, tramite Aruba).

Interfaccia in italiano, importi in euro, date in formato italiano. Nessuna dipendenza
esterna e nessun backend proprietario: tutto gira in locale, con sincronizzazione
opzionale via CloudKit (database privato iCloud).

Questo documento spiega **come è fatta** l'app e **come modificarla**. La fonte di
verità funzionale resta `PROGETTO.md`; le regole per l'agente/collaboratori sono in
`.kiro/steering/`.

---

## 1. Stack e requisiti

- **Swift 5 / SwiftUI**, app realmente native (no web view).
- **Swift Package Manager** (`Package.swift`) per dominio e logica condivisa.
- Progetto **Xcode** (`PaolaGestionale.xcodeproj`) per la UI multipiattaforma e i test UI.
- **SwiftData** per l'archivio locale, con schema versionato e migrazioni.
- **CloudKit** per la sincronizzazione (codice presente, attivo solo in build Xcode
  firmata e configurata con un container proprio).
- Target di deployment: **macOS 14**, **iOS 17** (compatibili con SwiftData).

Prerequisito: **Xcode completo** installato e aperto almeno una volta. I soli Command
Line Tools non includono i macro plugin di SwiftData e non bastano per compilare.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

---

## 2. Struttura del repository

```
Package.swift              Manifesto SwiftPM (prodotti PaolaCore + PaolaGestionale)
PROGETTO.md                Documento di progetto (fonte di verità funzionale)
PaolaGestionale.xcodeproj  Progetto Xcode (UI multipiattaforma, test UI)
App/                       Info.plist, entitlements, icona
Config/                    Xcconfig (Local.xcconfig.example -> Local.xcconfig)
Sources/
  PaolaCore/               Dominio: modelli, regole economiche, persistenza, servizi puri
  PaolaApp/                Presentazione: SwiftUI, navigazione, coordinamento storage
Tests/
  PaolaCoreTests/          Test del dominio (SwiftPM)
  PaolaAppTests/           Test dell'app
UITests/                   Test UI XCTest (schema PaolaGestionale-iOS-UI)
scripts/                   build-macos.sh, package-macos-release.sh
build/                     Output build/release (artefatti non versionati)
.github/workflows/         Pipeline di release macOS
```

---

## 3. Architettura a livelli

Le dipendenze vanno in **una sola direzione**: la presentazione dipende dal dominio,
mai il contrario. `PaolaCore` non importa `PaolaApp` né SwiftUI.

- **Dominio + Persistenza** (`Sources/PaolaCore`): agenda, regole economiche,
  validazioni, report, modelli SwiftData, schemi versionati, migrazioni, backup.
  Puro e testabile senza UI.
- **Presentazione** (`Sources/PaolaApp`): schermate e componenti SwiftUI. Nessuna
  regola economica: istanzia `BusinessRepository(context:)` e chiama i suoi metodi
  `public`.
- **Servizi di piattaforma**: la logica pura (rete/XML fattura, calcolo forfettario,
  Keychain, profilo fiscale) vive in `PaolaCore`; l'orchestrazione con `URLSession` e
  la UI (es. `ArubaClient`, `InvoiceSender`, `CredentialsView`) vive in `PaolaApp`,
  protetta da `#if os(macOS) || os(iOS)`.

`Package.swift` definisce: library **PaolaCore** ← executable **PaolaGestionale**
(target `PaolaApp`), più i test target `PaolaCoreTests` e `PaolaAppTests`.

### PaolaCore — file principali

| File | Ruolo |
| --- | --- |
| `Money.swift` | Parsing/formatting importi in **centesimi `Int64`** (mai floating point). |
| `BusinessModels.swift` | Modelli `@Model` correnti + enum (`SessionStatus`, `PaymentMethod`, `LedgerKind`), `BusinessError`, `BusinessRules`, i `Draft`. |
| `BusinessRepository.swift` | Repository transazionale del dominio economico (vedi §5). |
| `BusinessReports.swift` | Estratti/saldi/statistiche + `integrityWarnings(...)`. |
| `BusinessArchive.swift` | Snapshot in memoria dell'archivio: `capture(context:)` + `validate(clientIDs:)` (invarianti economiche). |
| `Client.swift` | Modello `Client` (`typealias Client = PaolaSchemaV7.Client`), `PaolaSchemaV1` e il **piano di migrazione** `PaolaSchemaMigrationPlan`. |
| `ClientDraft/Repository/Search.swift` | Bozza, repository e ricerca/duplicati clienti. |
| `ServiceRate.swift`, `AppointmentPreferences.swift`, `SchedulingSuggestions.swift` | Listino/tariffe, preferenze, proposte di giorni/orari liberi. |
| `SchemaV2.swift` … `SchemaV9.swift` | Schemi SwiftData versionati (vedi §4). |
| `StoreFactory.swift` | `makeContainer(...)` (schema corrente + migration plan), URL dello store, store ripristinati. |
| `CloudNamespace.swift` | Namespace archivio per account CloudKit. |
| `BackupCipher.swift`, `ArchiveSnapshot.swift` | Backup cifrato (AES-256-GCM / PBKDF2) e snapshot di ripristino. |
| `Invoice.swift` | `@Model Invoice` + `InvoiceStatus`, `sourceKey` per l'idempotenza. |
| `ForfettarioInvoice.swift` | `ForfettarioTax` (costanti fiscali) e `ForfettarioBreakdown` (imponibile/rivalsa 4%). |
| `FatturaPAXML.swift` | `FatturaPAXMLBuilder` + `FatturaPAInput/Party` (XML FatturaPA FPR12). |
| `ArubaAPI.swift` | Logica **pura** di richieste/parsing Aruba (signin/upload/status), `ArubaEnvironment`, `ArubaAPIError`. |
| `SecretStore.swift`, `KeychainSecretStore.swift` | Astrazione segreti + `ArubaCredentials`/`ArubaCredentialsStore`; implementazione Keychain. |
| `SellerFiscalProfile.swift` | Profilo fiscale del cedente + `SellerProfileStore`. |
| `AppUpdate.swift` | Logica pura per il controllo aggiornamenti (release GitHub). |

### PaolaApp — file principali

- `PaolaApp.swift` (entry `@main`), `AppNavigation.swift`, `StorageCoordinator.swift`,
  `SharedViews.swift`.
- `OverviewView.swift`, `ClientsView.swift`, `ClientDetailView.swift`,
  `ClientEditor.swift`, `SettingsView.swift`, `BackupView.swift`,
  `ReminderSchedulerView.swift`, `AppUpdater.swift`, `AppUpdateView.swift`.
- `Protection/` — blocco app con autenticazione di sistema.
- `BusinessViews/` — agenda e calendario, pagamenti, report, listino, pacchetti e
  fatturazione:
  - `AgendaViews.swift` — vista agenda (giorno/settimana/mese), griglia oraria 7–21,
    drag & drop, totale € del periodo, dettaglio appuntamento.
  - `AgendaDragDrop.swift` — modello griglia oraria (`AgendaHourRow`,
    `AgendaScheduling`) e primitive di drag & drop (`HourDropModifier`,
    `AgendaDragPayload`, `AgendaCreationSlot`).
  - `CalendarSessionRow.swift`, `SessionEditor.swift` — cella appuntamento ed editor.
  - `InvoiceSender.swift`, `CredentialsView.swift`, `ArubaClient.swift` — fatturazione.
  - `AppEnvironment.swift` — ambiente demo/produzione in base al tipo di build.

---

## 4. Persistenza SwiftData e migrazioni

- Ogni versione dello schema è un `enum … : VersionedSchema` con `versionIdentifier`
  `Schema.Version(N, 0, 0)` e l'elenco `models`. Schema corrente: **`PaolaSchemaV9`**
  (aggiunge il flag `isPaid` a `TrainingSession`). V8 aveva introdotto `Invoice` e il
  campo opzionale `invoiceDate` su `TrainingSession`/`LessonPackage`.
- I tipi correnti (`TrainingSession`, `SessionParticipant`, …) vivono in
  `BusinessModels.swift`; gli schemi **precedenti congelano** le versioni storiche
  delle classi (es. `PaolaSchemaV7.TrainingSession`, `PaolaSchemaV5.LessonPackage`).
  Questo evita "Duplicate version checksums" / "backing data" durante le migrazioni.
- Il piano è `PaolaSchemaMigrationPlan` (in `Client.swift`): `schemas` elenca V1→V9,
  `stages` sono 8 migrazioni **`.lightweight`** consecutive.
- Il container si crea in `StoreFactory.makeContainer(...)` con
  `Schema(versionedSchema: PaolaSchemaV9.self)` e `migrationPlan:
  PaolaSchemaMigrationPlan.self`; `mainContext.autosaveEnabled = false`.
- Store locale: `~/Library/Application Support/PaolaGestionale/Clienti-v1.store`
  (supporto a store ripristinati sotto `Restored/` via `UserDefaults`).

### Aggiungere un nuovo campo/entità (nuova versione schema)

1. Crea `Sources/PaolaCore/SchemaV10.swift` con `enum PaolaSchemaV10: VersionedSchema`
   (`versionIdentifier = Schema.Version(10,0,0)`, `models: [...]`). Riusa le classi
   congelate delle versioni precedenti per i modelli **non** cambiati; introduci la
   nuova forma solo per i modelli modificati.
2. Aggiorna i **tipi correnti** in `BusinessModels.swift` (nuovo campo/entità) e
   congela nella versione precedente (`SchemaV9`) la forma storica della classe
   modificata (come fatto per `TrainingSession` in `SchemaV8`).
3. In `StoreFactory.makeContainer` cambia lo schema corrente a `PaolaSchemaV10.self`.
4. In `PaolaSchemaMigrationPlan` aggiungi `PaolaSchemaV10.self` a `schemas` e lo stage
   `.lightweight(fromVersion: PaolaSchemaV9.self, toVersion: PaolaSchemaV10.self)` a
   `stages` (usa `.custom` solo se serve trasformare i dati).
5. Aggiorna i test che verificano `schemas.count`/`stages.count` e i `versionIdentifier`
   (in `StoreFactoryTests`), e i test store che devono usare lo schema corrente.

Un nuovo **valore di enum** (es. un nuovo `SessionStatus`) **non** richiede una nuova
versione di schema: lo stato è salvato come stringa libera (`statusRaw`) con fallback,
quindi basta aggiungere il caso e i relativi rami `switch`.

---

## 5. Dominio: `BusinessRepository`

`@MainActor public final class BusinessRepository`. Costruttori:
`init(context:)` (produzione) e `init(context:saveChanges:)` (per i test, inietta il
salvataggio). Disabilita l'autosave.

### Il pattern `transact`

Ogni scrittura passa da `transact { writer in … }`:

1. Crea un **nuovo `ModelContext`** ("writer") sullo stesso container, separato dal
   contesto osservato dalla UI (autosave off).
2. Pre-validazione: nessun cliente duplicato, `BusinessReports.integrityWarnings` vuoto,
   `BusinessArchive.capture(writer).validate(clientIDs:)`.
3. Esegue l'operazione; se ci sono modifiche rivalida con `BusinessArchive`, poi salva.
4. Rilegge il contesto UI (fetch) per invalidarlo/aggiornarlo. Un fallimento **non
   lascia modifiche parziali** visibili (mappato in `ClientPersistenceError`).

### Metodi pubblici principali

- `saveService` / `deleteService`
- `saveSession(_:allowOverlap:)`, `setSessionStatus(_:to:completionDate:)`,
  `rescheduleSession(_:to:allowOverlap:)`
- `savePackage` / `deletePackage`
- `createInvoiceForSession(sessionID:clientID:issueDate:)`,
  `createInvoiceForPackage(packageID:issueDate:)`
- `recordRefund(...)`, `recordCredit(...)`, `saveBlock` / `deleteBlock`

### Regole invarianti (da non violare)

- Importi esatti in **centesimi `Int64`**, mai floating point (`BusinessRules.add/
  subtract/multiply/amount`).
- Saldo = addebiti netti − incassi netti; positivo = dovuto dal cliente.
- **Idempotenza**: completare o sincronizzare due volte la stessa seduta non duplica
  addebito/incasso (chiavi `sourceKey` deterministiche). Creare due volte la fattura
  dello stesso incasso lancia `alreadyInvoiced`.
- Completare un appuntamento registra addebito + incasso (o consumo pacchetto) in
  **un'unica transazione**.
- Prezzo storico congelato: modificare il listino non cambia lo storico.
- Sovrapposizioni **bloccanti solo per lo stato `.planned`**; i provvisori sono
  prenotazioni tentative e non bloccano; `allowOverlap` forza (usato dallo scambio in
  drag & drop).
- Correzioni economiche via **movimenti tracciati** (storni/rimborsi), mai cancellazioni.

### Stati dell'appuntamento

`SessionStatus`: `provisional` (provvisorio), `planned` (programmato), `completed`
(completato, congelato), `cancelled`, `noShow`. Provvisorio e programmato si impostano
da `saveSession`; il completamento e la chiusura passano da `setSessionStatus`.

---

## 6. Agenda e calendario

- Viste **Giorno / Settimana / Mese**. La settimana mostra sabato e domenica solo se
  hanno appuntamenti.
- **Griglia oraria fissa 7–21** (`AgendaScheduling.gridHours`): ogni ora è una riga;
  gli appuntamenti compaiono nella fascia della loro ora di inizio. Le fasce vuote
  mostrano un **`+`** che apre l'editor con data e ora preimpostate.
- **Totale € del periodo** in alto a destra (somma dei prezzi concordati dei
  partecipanti agli appuntamenti visibili, esclusi annullati/assenze).
- **Drag & drop**: ogni appuntamento non completato ha una **maniglia** (icona grip)
  da cui parte il trascinamento. Il drop su una fascia libera sposta l'orario; su una
  occupata **scambia** i due appuntamenti. Il trasporto usa `.onDrag`/`.onDrop` con
  `NSItemProvider` di testo (solo l'UUID, nessun dato personale) — più affidabile di
  `.draggable`/`.dropDestination` dentro liste e scroll view.
- Le regole di disponibilità/proposte (editor) sono in `SchedulingSuggestions`
  (giorni e ore libere), concettualmente distinte dalla griglia del calendario.

---

## 7. Backup cifrato

- Backup completo cifrato **AES-256-GCM**; chiave derivata via **PBKDF2-HMAC-SHA256**
  (600.000 iterazioni, sale casuale). Password minima 12 caratteri, mai memorizzata.
- Limiti: payload 64 MB, file cifrato 100 MB. Nessun algoritmo crittografico
  personalizzato, nessuna password incorporata.
- La sincronizzazione **non è un backup**: una cancellazione può propagarsi ai
  dispositivi. Le fatture (`Invoice`) sono incluse nello snapshot/round-trip
  dell'archivio.

---

## 8. Fatturazione elettronica Aruba (forfettario)

Flusso end-to-end (solo incassi con **Stripe / carta / bonifico**, mai contanti):

1. UI (`SessionInvoiceSection` / `PackageInvoiceSection`) → `InvoiceSender`
   (`@MainActor`, `#if os(macOS) || os(iOS)`).
2. Validazione dati fiscali: `SellerFiscalProfile` + `ArubaCredentials` (Keychain) +
   codice fiscale e indirizzo del cliente.
3. Creazione **idempotente** dell'`Invoice` in bozza via
   `BusinessRepository.createInvoiceForSession/Package`.
4. Costruzione `FatturaPAInput` (cedente/cliente/`ForfettarioBreakdown`) e generazione
   XML con `FatturaPAXMLBuilder` (FPR12).
5. `ArubaClient.authenticate()` + `upload(xml:fileName:)`; aggiornamento di
   `invoice.status` (`.transmitted` / `.failed`).

Dettagli fiscali (in `ForfettarioInvoice.swift`): Natura **N2.2**, cassa previdenziale
**TC22 4%** (rivalsa INPS che concorre all'imponibile), riferimento normativo
L.190/2014, `CodiceDestinatario` `0000000` (clienti senza PEC). L'`IdTrasmittente`
dell'XML è il CF dell'intermediario Aruba (`ForfettarioTax.arubaTransmitterCode`),
richiesto dal controllo SDI 0094 — non è la P.IVA del cedente.

**Ambiente demo vs produzione** (`AppEnvironment`): `isLocalBuild` è vero quando
`Info.plist["PaolaLocalBuild"] == "YES"`. Le **build locali** (`./build-app.sh`) usano
l'ambiente **demo** di Aruba (`demoauth`/`demows`), le **release** la **produzione**.
Le credenziali si inseriscono nella sezione **Credenziali** e restano solo nel
**Keychain** (mai in file o nel codice, mai nei log). L'autenticazione demo ha un
limite di ~1 richiesta/minuto per IP.

> Nota: `ArubaClient.status(filename:)` (polling stato SDI) e
> `BusinessRepository.recordPayment` (pagamenti manuali, guardia `manualPaymentsDisabled`)
> sono predisposizioni volutamente non collegate alla UI. Sono coperti/documentati:
> non rimuoverli senza aggiornare i test.

---

## 9. Build ed esecuzione

### App locale macOS (Debug, firma ad hoc)

```bash
./build-app.sh                 # Debug, architettura corrente
PAOLA_BUILD_CONFIGURATION=release ./build-app.sh
PAOLA_UNIVERSAL=1 ./build-app.sh    # binario universale Intel + Apple Silicon
PAOLA_OPEN=1 ./build-app.sh         # apre l'app al termine
```

Lo script seleziona Xcode (`DEVELOPER_DIR`), compila via SwiftPM
(`scripts/build-macos.sh`), assembla il bundle `.app`, inietta versione/flag
nell'Info.plist, imposta `PaolaLocalBuild=YES`, CloudKit off, e firma ad hoc.
Bundle id build locale: `local.paola.gestionale.preview`.

### Verifica rapida (senza test)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift build
```

### Release universale

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PAOLA_RELEASE_OUTPUT="$PWD/build/releases/0.6.0" bash scripts/package-macos-release.sh
```

Produce app, ZIP universale, `SHA256SUMS.txt` e note di release.

---

## 10. Test

```bash
xcrun swift test                    # suite del dominio (SwiftPM)
PAOLA_RUN_TESTS=1 ./build-app.sh    # test + build dell'app
```

- I test usano archivi **in memoria o cartelle temporanee isolate**, mai l'archivio
  dell'app e mai un account iCloud.
- I test store devono usare lo **schema corrente** (`PaolaSchemaV9.self`).
- `BusinessError` **non** è `Equatable`: nei test usa `guard case BusinessError.x = error`.
- Le aree ad alto rischio (regole economiche, migrazioni, idempotenza, saldi) vanno
  coperte quando si tocca il dominio.

> Convenzione di lavoro (vedi `.kiro/steering/`): **non** eseguire la suite
> automaticamente dopo ogni modifica di UI (è lenta e nell'ambiente dell'agente spesso
> non parte). Verifica con `xcrun swift build` / `./build-app.sh` ed esegui i test solo
> su richiesta o prima di una release.

---

## 11. Come fare modifiche (guida rapida)

- **Nuova regola economica / di scheduling / validazione** → in `PaolaCore` (di norma
  `BusinessRepository` o un file di dominio dedicato), con test in `PaolaCoreTests`.
  Passa sempre da `transact` per le scritture; usa `Int64` centesimi e `sourceKey`
  idempotenti.
- **Nuova schermata / componente UI** → in `PaolaApp` (o `PaolaApp/BusinessViews`).
  Nessuna regola economica nella UI: chiama i metodi `public` del dominio. I file nuovi
  di `PaolaApp` vanno in `Sources/PaolaApp/BusinessViews/` per l'auto-sync del gruppo
  nel progetto Xcode.
- **Nuovo campo persistito** → segui §4 (nuova versione di schema + migrazione + test).
- **Convenzioni**: un file per tipo principale, nome file = nome del tipo; tipi di
  dominio consumati dalla UI marcati `public`; modifiche tramite **bozza** (Annulla non
  altera l'archivio); scrittura in un contesto separato con autosave off.

---

## 12. Privacy e sicurezza

- Solo dati necessari; i campi riservati (salute) sono separati dalle note e fuori da
  ricerca/estratti/promemoria.
- Nessun dato personale del professionista sugli estratti ("Documento non fiscale").
- Nessuna telemetria con dati personali/finanziari; niente recapiti/pagamenti nei log.
- Segreti **solo in Keychain**. In sviluppo e collaudo usare **solo dati inventati**.
