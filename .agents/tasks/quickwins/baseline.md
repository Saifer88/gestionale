# Baseline benchmark (prima dei quick win)

Data: 2026-11-16. Build Debug SwiftPM, macOS arm64, archivio in memoria, dati inventati.
Nessuna modifica di produzione. Unica modifica: fix compilazione
`Tests/PaolaAppTests/AgendaWeeklyBenchmarkTests.swift` (`data.currentWeekStart` copiato
in `let weekStart` prima del `#Predicate`).

## Come riprodurre

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift build --build-tests --scratch-path build/bench-baseline   # o swift test --filter ...
xcrun xctest -XCTest AgendaWeeklyBenchmarkTests build/bench-baseline/out/Products/Debug/PaolaAppTests.xctest > /tmp/paola-bench-raw.txt 2>&1
xcrun xctest -XCTest WritePerformanceTests build/bench-baseline/out/Products/Debug/PaolaCoreTests.xctest > /tmp/paola-write-raw.txt 2>&1
grep -a '\[bench\]\|\[perf\]' /tmp/paola-*-raw.txt
```

Note ambiente:
- `build/test-validation` inutilizzabile: dlopen bloccato da AppleSystemPolicy
  (`code signature ... not valid for use in process: library load disallowed by system policy`).
  Con scratch path nuovo `build/bench-baseline` i test partono.
- `swift test` con output rediretto su file perde le `print` del test (righe `[bench]`/`[perf]`);
  lanciare `xcrun xctest` direttamente sul bundle per vederle.

## AgendaWeeklyBenchmarkTests (1 test, passed, 9,25 s)

Dataset: 40 clienti, 30 servizi, 786 appuntamenti (35/settimana, ~22 settimane),
906 partecipanti, 39 pacchetti, 846 movimenti. Generazione 0,19 s. 5 ripetizioni, secondi.

| Operazione | Validazione | min | mediana | max |
|---|---|---|---|---|
| agenda: fetch sessioni finestra settimana (49) | - | 0,0005 | 0,0005 | 0,0009 |
| agenda: @Query non filtrate (906 partecipanti, clienti, blocchi, pacchetti, corsi) | - | 0,0061 | 0,0061 | 0,0083 |
| agenda: makeSnapshot settimana (37 visibili) | - | 0,0021 | 0,0022 | 0,0023 |
| agenda: snapshotKey | - | 0,0000 | 0,0000 | 0,0000 |
| validazione: uncanonicalizedCapture (fetch archivio) | .archive | 0,0546 | 0,0559 | 0,0577 |
| validazione: validate(clientIDs:) | .archive | 0,0073 | 0,0073 | 0,0074 |
| validazione: integrityWarnings (fetch + calcolo) | .archive | 0,0520 | 0,0527 | 0,0549 |
| completa (1 partecipante, senza pacchetto) | .archive | 0,2060 | 0,2065 | 0,2124 |
| completa (1 partecipante, con pacchetto) | .archive | 0,2029 | 0,2051 | 0,2100 |
| completa (2 partecipanti, senza pacchetto) | .archive | 0,2116 | 0,2159 | 0,2435 |
| completa (2 partecipanti, uno con pacchetto) | .archive | 0,2137 | 0,2180 | 0,2241 |
| completamento ripetuto (idempotenza) | .archive | 0,1184 | 0,1187 | 0,1202 |
| setParticipantPaid | .local | 0,0002 | 0,0135 | 0,0139 |
| setSessionsPaid (10 lezioni) | .local | 0,0185 | 0,0191 | 0,0240 |
| setSessionBlack | .local | 0,0001 | 0,0079 | 0,0080 |
| recordRefund | .archive | 0,2125 | 0,2145 | 0,2227 |
| rescheduleSession | .local | 0,0082 | 0,0084 | 0,0085 |
| setSessionStatus cancelled | .local | 0,0078 | 0,0078 | 0,0082 |
| saveSession (crea) | .local | 0,0144 | 0,0145 | 0,0146 |
| savePackage (acquisto) | .archive | 0,1955 | 0,1963 | 0,1979 |
| saveBlock (indisponibilità) | .archive | 0,1871 | 0,1944 | 0,1982 |

## WritePerformanceTests (1 test, passed, 2,05 s; 3200 lezioni)

| Operazione | Tempo |
|---|---|
| setParticipantPaid | 58 ms |
| setSessionBlack | 33 ms |
| rescheduleSession | 33 ms |
| saveSession | 60 ms |
| setSessionStatus completed | 1046 ms |
