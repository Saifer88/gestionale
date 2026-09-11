# Stack tecnico

## Tecnologie

- **Swift 5** e **SwiftUI**, app realmente native (no web view).
- **Swift Package Manager** (`Package.swift`) per dominio e logica condivisa.
- Progetto **Xcode** (`PaolaGestionale.xcodeproj`) per la UI multipiattaforma e i test UI.
- **SwiftData** per l'archivio locale, con schema versionato e migrazioni.
- **CloudKit** (database privato iCloud) per la sincronizzazione — codice presente,
  attivo solo in build Xcode firmata e configurata per un container proprio.
- API native Apple per notifiche, PDF, stampa ed esportazioni.
- **Nessuna dipendenza esterna** e nessun backend personalizzato.

## Target di deployment

- macOS 14, iOS 17 (compatibili con SwiftData).
- Requisito: ultime tre versioni principali di macOS e iOS (richiede collaudo dedicato).

## Prerequisiti

- Xcode completo installato e aperto almeno una volta (i soli Command Line Tools
  non bastano per SwiftData).
- Per selezionare Xcode nel solo terminale corrente:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

## Comandi

### Test del dominio (Swift Package)

```bash
xcrun swift test
```

I test usano archivi in memoria o cartelle temporanee isolate, mai l'archivio
dell'app e mai un account iCloud.

> **Non eseguire i test automaticamente dopo aver sviluppato una funzionalità.**
> La suite è lenta e spesso non si avvia nell'ambiente dell'agente: eseguirla fa
> perdere tempo senza dare un esito affidabile. Verifica il lavoro con la sola
> compilazione (`xcrun swift build` o `./build-app.sh`). Esegui `xcrun swift test`
> solo quando l'utente lo chiede esplicitamente o prima di preparare una release
> (in quel caso: `PAOLA_RUN_TESTS=1 ./build-app.sh`).

### Build locale macOS (Debug + firma ad hoc)

```bash
bash scripts/build-macos.sh
```

Variabili supportate: `PAOLA_BUILD_CONFIGURATION=release`, `PAOLA_UNIVERSAL=1`,
`PAOLA_BUILD_NUMBER`, `PAOLA_BUILD_PATH`, `PAOLA_APP_OUTPUT`.

### Release universale (Intel + Apple Silicon)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PAOLA_RELEASE_OUTPUT="$PWD/build/releases/0.6.0" \
  bash scripts/package-macos-release.sh
```

Produce app, ZIP universale, `SHA256SUMS.txt` e note della release. Verifica:

```bash
shasum -a 256 --check SHA256SUMS.txt
```

### Test UI iPhone (simulatore)

```bash
xcodebuild -project PaolaGestionale.xcodeproj \
  -scheme PaolaGestionale-iOS-UI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

Adattare il nome della destinazione al simulatore disponibile. Usare un simulatore
dedicato senza dati reali.

## Note di sviluppo

- Il target Xcode dell'app si chiama `PaolaGestionaleApp` per evitare ambiguità
  con il prodotto SwiftPM; schema e nome app restano `PaolaGestionale`.
- Configurazione locale: copiare `Config/Local.xcconfig.example` in
  `Config/Local.xcconfig` (escluso dal versionamento) e impostare `DEVELOPMENT_TEAM`
  e un bundle identifier univoco.
- Bundle identifier della build locale/preview: `local.paola.gestionale.preview`.
- Le release sono firmate **ad hoc**, non con Developer ID e **non notarizzate**.
- Archivio della build da terminale:
  `~/Library/Application Support/PaolaGestionale/Clienti-v1.store`.
- **Non usare comandi long-running** (server/watch) in modo bloccante; preferire
  esecuzioni singole.

## Backup e cifratura

- Backup completo cifrato con AES-256-GCM; chiave derivata via PBKDF2-HMAC-SHA256
  (600.000 iterazioni, sale casuale). Password minima 12 caratteri, mai memorizzata.
- Limiti formato: payload 64 MB, file cifrato 100 MB.
- Nessun algoritmo crittografico personalizzato, nessuna password incorporata nell'app.

## CI/Release

- Workflow `.github/workflows/release-macos.yml`: parte su push a `main` (o avvio manuale),
  esegue `swift test`, compila Release universale, firma ad hoc, calcola SHA-256 e
  pubblica una GitHub Release. Job di build con `contents: read`, pubblicazione con
  `contents: write`, `GITHUB_TOKEN` automatico. Azioni ufficiali pinnate a commit specifici.
