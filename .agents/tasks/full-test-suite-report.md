# Report suite di test completa

## Comando
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift test --scratch-path build/full-tests > /tmp/paola-full-tests.txt 2>&1   # in background
```
`swift test` ha funzionato al primo tentativo (nessun blocco, nessun ripiego su xctest). Checkout con modifiche non committate (Q1-Q7, M1-M4, signpost). Nessun codice modificato, nessun commit. `PAOLA_GENERATE_TEST_BACKUP` non impostata.

## Risultati

| Target | Eseguiti | Passati | Falliti | Saltati | Durata |
|---|---|---|---|---|---|
| PaolaCoreTests | 230 | 230 | 0 | 0 | 5,235 s |
| PaolaAppTests | 21 | 20 | 0 | 1 | 4,933 s |
| **Totale** | **251** | **250** | **0** | **1** | ~10,2 s (test) |

Test saltato: `LargeTestBackupGeneratorTests.testGenerateLargeEncryptedBackup` (atteso: richiede `PAOLA_GENERATE_TEST_BACKUP=1`).

`AgendaWeeklyBenchmarkTests.testWeeklyAgendaDatasetAndOperations`: passato in 4,633 s.

## Fallimenti
Nessuno. Nessuna riga `failed (` nell'output. Output completo: `/tmp/paola-full-tests.txt`.

Nota: la riga finale "Test run with 0 tests" è del runner Swift Testing (nessun test in quel formato), non un errore.
