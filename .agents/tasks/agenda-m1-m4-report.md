# Report M1–M4 + signpost (agenda)

Nessun commit. Dati inventati, Debug SwiftPM, archivio in memoria.

## Tempi prima/dopo (misurati in Fase A, Debug, mediana di 5; 3200 lezioni: singola misura)
| Operazione | Prima | Dopo |
|---|---|---|
| completa 1 partecipante, senza pacchetto | 0,1826 s | 0,0018 s |
| completa 1 partecipante, con pacchetto | 0,1836 s | 0,0019 s |
| completa 2 partecipanti, senza pacchetto | 0,1849 s | 0,0022 s |
| completa 2 partecipanti, uno con pacchetto | 0,1862 s | 0,0024 s |
| completamento ripetuto | 0,1187 s | 0,0001 s |
| completamento con 3200 lezioni | 917 ms | 2 ms |
| `fullValidation` (spostata in background) | – | 0,0650 s |
| rimborso / pacchetto / blocco (`.archive`, invariati) | 0,2201 / 0,1870 / 0,1868 s | 0,2106 / 0,1942 / 0,1945 s |

Non misurato: `makeSnapshot` e rendering UI dopo M3/M4 (il benchmark replica la versione vecchia; nessuna misura in app). Il guadagno M3/M4 va verificato con Instruments (sotto).

## Modifiche
- **M1** `Validation.scoped` solo per `setSessionStatus(.completed)`: controllo post-scrittura su sessione, partecipanti, clienti, pacchetti, utilizzi, movimenti e commissione coinvolti. Nessun pre-controllo globale.
- **M2** regole per-entità in `BusinessArchiveRules`, usate da `validate` e dallo scoped (test di parità).
- **M3** `AgendaContent`: niente `@Query` illimitate; fetch mirati alla finestra visibile per partecipanti, clienti, pacchetti del periodo, corsi attivi, partecipanti corso e relativi pacchetti; `blocks` filtrati per sovrapposizione; chiave snapshot leggera (`SnapshotKey` + `revision`); errori in `snapshotError`.
- **M4** `IntegrityStatusView` calcola con `ArchiveHealthChecker` (`@ModelActor`, `Task.detached`) con debounce, dopo `.paolaEconomicDataDidChange`; validazione completa solo al lancio/dopo ripristino. Risultato solo in `@State`, nessuna cache persistente.
- **Signpost** (`local.paola.gestionale` / `Performance`): vedi `docs/PERFORMANCE.md`. UI: `agenda.complete`, `agenda.togglePaid`, `agenda.toggleBlack`, `agenda.setStatus`, `agenda.reschedule`, `agenda.create`, `agenda.makeSnapshot`, `agenda.fetchWindow`, `integrity.refresh`. Dominio: nome operazione, `validation.pre/post`, `operation`, `save`, `refetch`, `archive.capture`, `integrityWarnings`, `fullValidation`.

## Ancora `.archive` e perché
`deleteSession` (storni collegati: non dimostrata sicura una validazione mirata), `savePackage`, `deletePackage`, rimborsi/storni (`recordAdjustment`), `createInvoice*`, `saveBlock/saveCourse/saveExpense/saveService` (fuori dal task), import/ripristino. `.local` per pagato, bianco/nero, spostamento, creazione/modifica non completati, cambi di stato diversi da completato.

## Comportamento cambiato
Il completamento non blocca più per incoerenze altrove nell'archivio; le segnala `IntegrityStatusView` (avviso con ritardo di ~0,3–0,8 s).

## Rischi residui
- Aggiornamento viste agenda dopo modifiche: provare a mano crea/modifica/sposta/completa/pagato/elimina, cambio settimana, ricerca, corsi, indisponibilità. Modifiche a corsi/clienti da altre schermate si vedono al ritorno (`onAppear`).
- `SessionDetailView` e viste di dettaglio hanno ancora `@Query` ampie; `ReminderSchedulerView` invariata.
- Il completamento gira ancora sul main thread.
- Nessun test UI eseguito; nessuna suite intera.

## Misurare con Instruments
Product → Profile → template **os_signpost** (la categoria `Performance` non è in *Points of Interest*). Filtro subsystem `local.paola.gestionale`, categoria `Performance`; vista *Intervals*. Da terminale: `log stream --signpost --predicate 'subsystem == "local.paola.gestionale"'`. Marcatori: `agenda.*`, `agenda.makeSnapshot`, `agenda.fetchWindow`, `integrity.refresh`, `transact` e nomi operazione, `validation.pre`, `validation.post`, `operation`, `save`, `refetch`, `archive.capture`, `integrityWarnings`, `fullValidation`.

## App compilata
`/Users/pirrima001/coding/personal/paola_gestionale/build/Paola Gestionale.app` (Debug, firma ad hoc; `bash scripts/build-macos.sh`, exit 0).

## Nota correzione gate UI
`IntegrityStatusView` conserva in `@State` l'ultimo esito di `fullValidation` (eseguita al lancio/dopo ripristino) e lo riaggiunge a ogni refresh: l'avviso di incoerenza globale non sparisce dopo operazioni economiche finché non si rilancia la validazione. Build: `swift build` e `scripts/build-macos.sh` ok.
