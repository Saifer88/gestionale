# Review Fase A (dominio) — M1+M2, test, signpost
Verdetto: APPROVED. Nessun blocker.

Evidenza (diff + progress, suite non rieseguite; 0 fallimenti registrati su ScopedValidation 11, HealthChecker 3, BusinessRepository 12, MultipleParticipants 3, AutomaticIncome 10, BusinessIntegrity 7, BusinessArchive 8, WritePerformance 1):
- M2: `BusinessArchiveRules` contiene le regole per-entità con messaggi invariati; `BusinessArchive.validate` e `ScopedValidation` le chiamano entrambe. Restano in `validate` le regole globali (unicità id, rettifiche cumulative, orfani, fatture, corsi, blocchi).
- M1: `.scoped([id])` solo in `setSessionStatus(.completed)`. `.archive` resta su deleteSession, savePackage, deletePackage, recordAdjustment (rimborsi/storni), fatture, saveBlock/Course/Expense/Service. Import/ripristino non toccati.
- Invarianti: scadenza/capienza/pacchetto di altro cliente verificati sia in `checkPackage` (operazione) sia nelle regole post-scrittura; addebito su lezione a pacchetto rifiutato da `sessionEconomics`; importi `Int64`; idempotenza: `status == status` ritorna senza modifiche; operazione + validazione + save nello stesso contesto writer (una transazione, nessuna scrittura parziale testata); sedute completate bloccate da `completedSessionLocked`; saldi non memorizzati.
- Test coprono: doppio completamento (singolo/pacchetto/3 partecipanti), saldi identici full vs scoped, esaurito/scaduto/altro cliente, multi-partecipante con rollback, sourceKey con importo diverso, corpus di mutazioni full vs scoped.
- Signpost: nomi `StaticString` costanti, nessun dato personale/finanziario.

Rischi residui non bloccanti (dichiarati):
- Il completamento non fa più il pre-check globale: incoerenze altrove sono segnalate da `ArchiveHealthChecker`, non bloccano. Comportamento documentato e testato.
- Lookup per `sourceKey` minuscola esatta (limite già presente da Q3; le chiavi sono generate minuscole).
