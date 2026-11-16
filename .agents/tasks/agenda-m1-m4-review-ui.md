# Review UI Fase B (M3, M4, signpost, report) - giro 2
Verdetto: APPROVED. Nessuna build/suite rieseguita; evidenza da progress.md (swift build ok, build-macos.sh exit 0 dopo il fix).
## Fix verificato
- `SharedViews.swift` `IntegrityStatusView.refresh`: `fullValidationMessage` in `@State`, impostato al primo calcolo (solo se `runFull` completa), riaggiunto a ogni refresh (`warnings = result + fullValidationMessage`). L'avviso di incoerenza globale non sparisce più dopo operazioni economiche. Se il primo task è annullato, `didRunFullValidation` resta false e la validazione si ripete.
## Confermato dal giro 1
- M3: sessioni con margine ±3 gg, blocchi per sovrapposizione, fetch mirati per partecipanti/clienti/pacchetti/corsi, chiave snapshot leggera, conflitti invariati.
- M4: nessuna @Query, checker su contesto separato (Task.detached), debounce, solo su `.paolaEconomicDataDidChange`, stato effimero in @State, nessuna cache persistente.
- Signpost: nomi costanti, nessun dato personale/finanziario.
- UI senza regole economiche.
- Report: tempi prima/dopo, M1-M4, operazioni ancora `.archive` con motivo, rischi, Instruments, percorso app presenti.
## Blocker
Nessuno.
