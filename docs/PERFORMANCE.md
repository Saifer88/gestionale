# Misure di prestazione (os_signpost)

Subsystem `local.paola.gestionale`, categoria `Performance`. Solo nomi costanti: nessun dato di
cliente, importo o nota nei messaggi.

## Marcatori

| Nome | Dove |
|---|---|
| `<operazione>` (`setSessionStatus`, `setParticipantPaid`, `rescheduleSession`, `saveSession`, `deleteSession`, `savePackage`, …) | `BusinessRepository.transact` |
| `validation.pre`, `operation`, `validation.post`, `save`, `refetch` | `BusinessRepository.transact` / `save` |
| `archive.capture`, `integrityWarnings`, `fullValidation` | dominio |
| `agenda.complete`, `agenda.togglePaid`, `agenda.toggleBlack`, `agenda.setStatus`, `agenda.reschedule`, `agenda.create` | operazioni UI agenda |
| `agenda.makeSnapshot`, `agenda.fetchWindow` | `AgendaContent` |
| `integrity.refresh` | `IntegrityStatusView` (background) |

## Come misurare

1. Xcode → Product → Profile → template **os_signpost** (o "Logging"). La categoria è dedicata, quindi
   non compare in *Points of Interest*.
2. Filtra per subsystem `local.paola.gestionale` e categoria `Performance`; la vista *Intervals* mostra
   durata per nome.
3. Da terminale: `log stream --signpost --predicate 'subsystem == "local.paola.gestionale"'`.
