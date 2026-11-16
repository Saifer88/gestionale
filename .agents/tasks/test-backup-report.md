# Backup di prova con archivio grande

Tutti i dati sono **inventati** (nomi "Prova1…Prova40", telefoni `300000xxxx`, email `@example.com`).
Nessuna modifica all'archivio reale dell'app né a iCloud; nulla installato in `/Applications`.

## File e password

- File: `/Users/pirrima001/coding/personal/paola_gestionale/build/test-backup/Paola-backup-TEST-grande.paolabackup` (1.217.775 byte)
- Password (di prova, dati finti): `Prova-Backup-2025-xK9!`
- Formato: `BackupCipher` v1 (AES-256-GCM, PBKDF2 600.000 iterazioni), payload `ArchiveSnapshot` versione 6, schema SwiftData V16.

## Contenuto

Periodo: 22 settimane (≈5 mesi) a partire da 18 settimane prima della settimana corrente
(16/11/2026 alla generazione), quindi settimana corrente + 3 settimane future.
Lunedì–sabato, slot orari 7:00–19:00; circa 1 appuntamento su 17 spostato di 30 minuti → sovrapposizioni.

| Dato | Quantità |
|---|---|
| Clienti | 40 |
| Servizi | 30 (durate 30/45/60/90 min) |
| Tariffe nominate | 103 (2–5 per servizio: Standard, Ridotta, Coppia, Studenti, Gruppo, Over 60) |
| Appuntamenti | 806 (≈36,6/settimana) |
| – completati | 560 |
| – programmati | 155 (futuri + qualche passato rimasto aperto) |
| – provvisori | 6 |
| – annullati | 48 |
| – assenze | 37 |
| Appuntamenti con 2 partecipanti | 127 |
| Partecipanti | 933 |
| Pacchetti | 54 (38 a lezioni da 10, 16 a tempo da 3 mesi) |
| Pacchetti a lezioni esauriti | 9 |
| Utilizzi pacchetto | 283 |
| Movimenti contabili | 786 (addebiti + incassi pacchetti e lezioni) |
| Indisponibilità | 7 (pause di 2 h ogni 4 settimane, ferie di 3 giorni ogni 9) |
| Record totali (`recordCount`) | 3042 |

Coerenza economica: importi in centesimi `Int64`; ogni pacchetto ha addebito + incasso con
`packageSource`/`packageIncomeSource`; ogni lezione completata senza pacchetto ha addebito
`sessionSource` (data = inizio lezione) e, nell'85% dei casi, incasso `sessionIncomeSource`
(le altre restano con saldo dovuto); le lezioni a pacchetto completate hanno un solo
`PackageUse` e nessun addebito. Saldi non memorizzati (calcolati dai movimenti).

## Generazione e verifica

Generatore: `Tests/PaolaAppTests/LargeTestBackupGeneratorTests.swift`
(`testGenerateLargeEncryptedBackup`), saltato di default, attivo con `PAOLA_GENERATE_TEST_BACKUP=1`.
Lavora su un container SwiftData V16 in memoria. Rigenerando cambiano gli UUID e le date seguono la settimana corrente.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift build --build-tests --scratch-path build/test-backup-build
PAOLA_GENERATE_TEST_BACKUP=1 xcrun xctest -XCTest LargeTestBackupGeneratorTests \
  build/test-backup-build/out/Products/Debug/PaolaAppTests.xctest
```

Nota ambiente: con `--scratch-path build/test-validation` il bundle di test non si carica
(dlopen bloccato da AppleSystemPolicy). Con `swift test` il test restava fermo, quindi l'ho
lanciato con `xcrun xctest` su uno scratch path nuovo. Esito: 1 test, 0 errori, 0,96 s.

Il test verifica:
- `ArchiveSnapshot.capture` + `validate` (quindi `BusinessArchive.validate`) e
  `BusinessReports.integrityWarnings` vuoto;
- cifratura, scrittura del file, rilettura da disco, `BackupCipher.decrypt` + `ArchiveSnapshot.decode`;
- `decrypt` con password errata fallisce;
- `restore(toNewStoreAt:)` in una cartella temporanea, con la verifica interna di uguaglianza dello snapshot;
- conteggi identici prima e dopo il ripristino; 40 clienti, 30 servizi, >30 appuntamenti/settimana, pacchetti a tempo presenti.

## Ripristino dall'app

1. Disattivare iCloud se attivo: con iCloud attivo il pulsante di ripristino è disabilitato.
2. Aprire **Impostazioni → Archivio → Backup e ripristino**.
3. Nel campo **"Password del backup (almeno 12 caratteri)"** inserire `Prova-Backup-2025-xK9!`
   **prima** di aprire il file: la password viene letta dal campo al momento dell'apertura
   (il campo "Ripeti password" serve solo per creare backup).
4. Premere **"Apri backup da ripristinare"** e scegliere il file `.paolabackup` indicato sopra.
5. Compare il dialogo "Ripristinare questo archivio?" con 40 clienti e 3042 record totali:
   premere **"Crea copia di sicurezza e ripristina"**.
6. L'app cifra una copia di sicurezza dell'archivio attuale **con la stessa password del backup**
   in `~/Library/Application Support/PaolaGestionale/Backups/prima-ripristino-<UUID>.paolabackup`
   (il percorso appare in fondo alla schermata), poi passa al nuovo archivio.

## Sostituisce o unisce?

**Sostituisce.** Nessuna unione. In `BackupView.restoreBackup()` lo snapshot viene scritto in un
**nuovo** store vuoto `Application Support/PaolaGestionale/Restored/<UUID>/Clienti-v1.store`.
`ArchiveSnapshot.restore(toNewStoreAt:)` rifiuta uno store esistente (`ArchiveError.existingStore`).
Poi `StorageCoordinator.installRestoredStore` → `StoreFactory.activateRestoredStore` salva il percorso
in `UserDefaults["storage.restoredStore"]` e l'app usa solo quel container.
L'archivio precedente **non viene cancellato né modificato**: resta su disco e ne esiste anche la
copia cifrata `prima-ripristino-…`. Per tornare ai dati precedenti si ripristina quella copia
(con la password del backup di prova).
Nota: il "Reset totale" cancella la chiave `storage.restoredStore`, quindi dopo un reset l'app torna allo store predefinito.

## App compilata

- App: `/Users/pirrima001/coding/personal/paola_gestionale/build/Paola Gestionale.app`
- Comando: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash scripts/build-macos.sh` (debug, firma ad hoc, bundle id `local.paola.gestionale.preview`).
- Esito: **riuscito**, nessun errore di compilazione. Log in `/tmp/paola-build.txt`. Test non eseguiti, nulla installato in `/Applications`.
- Avvio: `open "/Users/pirrima001/coding/personal/paola_gestionale/build/Paola Gestionale.app"`
