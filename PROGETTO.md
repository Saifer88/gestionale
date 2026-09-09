# Gestionale personal trainer - Documento iniziale

Data: 8 settembre 2026
Stato: versione 0.4.0 in collaudo; attivazione iCloud ancora da configurare.
Nome provvisorio del progetto: Paola Gestionale.

## 1. Obiettivo

Realizzare un'applicazione nativa per gestire il lavoro quotidiano di un personal
trainer: clienti, agenda, prestazioni, pagamenti e riepiloghi economici.

Il Mac e' la postazione principale; l'iPhone permette di lavorare anche fuori
studio, mantenendo gli stessi dati sincronizzati.

Questo documento definisce il progetto e ne registra lo stato di realizzazione.
Le risposte originali del committente sono conservate nella sezione 13.
Le funzionalita' approvate non sono tutte gia' implementate: vedere la sezione 15.

## 2. Requisiti confermati

- Utilizzo da parte di un solo personal trainer.
- Applicazione nativa per macOS e iPhone, non una semplice pagina web.
- Dati sincronizzati tra un Mac e un iPhone.
- Gestione dell'agenda e delle anagrafiche di clienti/pazienti.
- Registrazione dei pagamenti.
- Produzione di estratti e riepiloghi.
- Stesso account Apple su Mac/iPhone e utilizzo di iCloud approvato.
- Clienti fitness; anamnesi e analisi fisica come testi riservati facoltativi,
  richiesti il 9 settembre 2026. Nessuna funzione di diagnosi o cartella clinica.
- Sedute per un solo cliente; lezioni singole e pacchetti da 10.
- Dal 9 settembre 2026 le nuove sedute in coppia sono eliminate. Lo storico
  delle versioni precedenti viene conservato senza conversioni distruttive.
- Pacchetti assegnati ai clienti con consumo degli utilizzi per sessione.
- Statistiche su incassi, ore lavorate, orari piu' scelti e media oraria.
- Nessuna importazione iniziale; installazione locale senza pubblicazione su store.
- Nessun dato personale del professionista sugli estratti.
- Supporto richiesto per le ultime tre versioni principali di macOS e iOS.

Nel documento e nell'applicazione viene usato il termine "cliente".

## 3. Impostazione proposta

- Un solo archivio personale, senza gestione di dipendenti o collaboratori.
- Interfaccia in italiano, importi in euro e date nel formato italiano.
- Uso locale anche senza connessione.
- Sincronizzazione tramite iCloud, con lo stesso account Apple sui due dispositivi.
- Nessun server dedicato e nessun account applicativo aggiuntivo nella prima versione.
- Prenotazioni inserite dal professionista, non direttamente dai clienti.
- Estratti conto non fiscali; fatturazione elettronica esclusa dalla prima versione.

La sincronizzazione iCloud e' approvata. La sua attivazione richiede ancora
configurazione Apple Developer, firma, verifica dei requisiti privacy e
collaudo offline su entrambi i dispositivi.

## 4. Funzioni della prima versione proposta (MVP)

### 4.1 Anagrafica clienti

- Nome e cognome, telefono ed email.
- Contatti e altri campi non essenziali facoltativi.
- Data di inizio rapporto, stato attivo/archiviato e note organizzative.
- Ricerca per nome e recapito; filtro per clienti attivi o archiviati.
- Scheda cliente con appuntamenti, prestazioni, pagamenti e saldo.
- Archiviazione senza perdere lo storico.
- Segnalazione di possibili duplicati, senza fusioni automatiche.
- Campi facoltativi "Anamnesi" e "Analisi fisica", separati dalle note organizzative.
- I testi riservati sono conservati nel backup cifrato, ma esclusi da ricerca
  generale, estratti economici e promemoria.

Indirizzo, codice fiscale e dati aggiuntivi saranno inclusi solo se necessari.
Nella prima versione non e' prevista una cartella clinica.

### 4.2 Agenda

- Vista giornaliera, settimana con sette colonne da lunedi' a domenica e
  riepilogo mensile. Le colonne sono scorrevoli sui dispositivi piu' stretti.
- Creazione e modifica di appuntamenti individuali.
- Il pulsante `+` apre direttamente il nuovo appuntamento. La creazione di
  pause e ferie rimane disponibile in Impostazioni, separata dal pulsante `+`.
- Il cliente e' la prima selezione obbligatoria: gli altri campi appaiono dopo.
- Per ogni cliente vengono riproposti servizio, orario, tariffa e pacchetto
  dell'ultimo appuntamento salvato con successo. Annullare una bozza o fallire
  un salvataggio non cambia le preferenze.
- Per i clienti provenienti dalle vecchie versioni, senza preferenze esplicite,
  si utilizza l'ultimo appuntamento creato, escludendo annullamenti e assenze.
- Se il servizio e' disattivato, il pacchetto esaurito/scaduto o la tariffa
  rimossa, la scheda mostra un avviso e propone solo alternative valide.
- Viene mantenuto l'orario abituale nel primo giorno feriale disponibile.
  Un orario storico manuale con minuti diversi da `00` resta selezionabile
  manualmente, ma non viene aggiunto ai pulsanti di selezione rapida.
- Partecipanti, data, ora, durata, servizio e note organizzative.
- Il campo luogo non viene piu' mostrato o richiesto. I valori storici restano
  nell'archivio e nei backup per evitare cancellazioni durante l'aggiornamento.
- Creando un appuntamento, pulsanti con i soli giorni feriali da oggi al venerdi'
  della settimana successiva, con etichette come "Mercoledi' 9" e "Giovedi' 10".
- Le ore rapide sono esattamente `7, 8, 9, 10, 13, 14, 15, 16, 17, 18, 19, 20`,
  sempre con minuti `00`, escludendo
  quelle gia' trascorse e quelle in cui una qualunque parte della durata
  occuperebbe un appuntamento programmato/completato o un'indisponibilita'.
- Disponibilita' ricalcolata per il giorno e la durata scelti, anche per sedute
  che terminano nel giorno successivo. Annullamenti e assenze non bloccano orari.
- Scelta manuale mantenuta per date e orari fuori dalle proposte.
- Stati: programmato, completato, annullato, assenza del cliente.
- Segnalazione di appuntamenti sovrapposti.
- Ricerca degli appuntamenti di un cliente.
- Blocchi di indisponibilita', ferie e pause.
- Promemoria locali facoltativi, previa autorizzazione alle notifiche.
- Collegamento dall'appuntamento alla scheda cliente e al relativo addebito.

Il prezzo concordato viene conservato sull'appuntamento o sulla prestazione:
modificare il listino non deve cambiare retroattivamente lo storico.

Annullamenti e assenze non generano penali automatiche. Non e' richiesta
una gestione dedicata di penali e recuperi.

### 4.3 Servizi e listino

- Servizi configurabili, per esempio allenamento individuale o valutazione iniziale.
- Durata e una o piu' tariffe nominate, ciascuna con il proprio prezzo per persona.
- La prima tariffa e' quella predefinita; ogni partecipante puo' selezionare
  una tariffa diversa o concordare un prezzo personalizzato.
- La lista dei servizi negli appuntamenti mostra anche il prezzo; con piu'
  prezzi diversi mostra l'intervallo minimo-massimo.
- Possibilita' di concordare un prezzo diverso per la singola prestazione.
- Disattivazione di servizi non piu' offerti, mantenendo lo storico.

I nomi degli esempi non implicano prestazioni sanitarie o qualifiche professionali.

### 4.3.1 Pacchetti da 10

- Assegnazione di un pacchetto da 10 utilizzi a un cliente.
- Prezzo concordato, data di acquisto, utilizzi residui e storico delle sedute.
- Consumo collegato al completamento della sessione, non alla prenotazione.
- Nessun doppio consumo se una sessione viene salvata o sincronizzata piu' volte.
- Acquisto contabilizzato una sola volta; utilizzo senza un secondo addebito.
- Evidenza dei pacchetti esauriti, senza rinnovi automatici.

Regola del gestionale: il cliente usa il proprio pacchetto oppure il prezzo
concordato della singola seduta. Il completamento scala un utilizzo del pacchetto
senza un ulteriore incasso. Il listino propone il prezzo della tariffa scelta,
modificabile prima del completamento.

Nella scheda appuntamento la scelta del pacchetto e' etichettata
"Pacchetto in uso"; "No" indica che si applica il prezzo della singola seduta.

### 4.4 Pagamenti e saldo cliente

- Gli incassi vengono creati automaticamente in due soli casi:
  registrazione di un nuovo pacchetto e completamento di una lezione singola
  non coperta da pacchetto.
- Il pacchetto registra addebito e incasso del prezzo totale alla data di
  acquisto selezionata; e' richiesta conferma esplicita prima del salvataggio.
- La lezione singola registra l'incasso alla data del completamento, mentre
  l'addebito conserva la data della prestazione. Le due date possono differire.
- Il metodo degli incassi automatici e' "Altro" (non indicato), senza inventare
  contanti, carta o bonifico. I metodi dei vecchi pagamenti restano invariati.
- La registrazione manuale di nuovi pagamenti e' disabilitata. Vecchi saldi,
  acconti, anticipi e pagamenti parziali restano consultabili e nei report.
- Collegamento di un pagamento a uno o piu' addebiti.
- Evidenza delle somme ancora da pagare e degli anticipi disponibili.
- Storico delle operazioni con note e riferimenti facoltativi.
- Registrazione esplicita di rimborsi e rettifiche.
- Filtri per cliente, periodo e metodo di pagamento.

La registrazione di un pagamento non esegue un pagamento reale: integrazioni
con POS, banche o servizi di incasso non fanno parte della prima versione.

### 4.5 Estratti e riepiloghi

- Estratto conto cliente per intervallo di date.
- Saldo iniziale, addebiti, pagamenti, rettifiche e saldo finale.
- Separata evidenza di importi da pagare e credito del cliente.
- Riepilogo degli incassi per periodo e metodo di pagamento.
- Elenco dei clienti con importi ancora da pagare.
- Ore effettivamente lavorate, senza duplicare eventuali appuntamenti storici
  con piu' partecipanti.
- Distribuzione delle prenotazioni per giorno della settimana e fascia oraria.
- Media incassi/ora del periodo, con formula indicata e valore non disponibile
  se le ore sono zero. Gli anticipi dei pacchetti possono alterare questo rapporto:
  non va confuso con il valore economico delle sole lezioni svolte.
- Esportazione PDF leggibile e stampabile.
- Esportazione CSV dei movimenti, utilizzabile con Excel o Numbers.
- Anteprima e scelta esplicita della destinazione prima di esportare o condividere.

Gli estratti devono riportare chiaramente "Documento non fiscale".
Non sostituiscono fatture, ricevute fiscali o consulenza contabile.

### 4.6 Schermata iniziale

- Appuntamenti di oggi e prossimi appuntamenti.
- Riquadri per incassi annuali, mensili e settimanali, con lo stesso stile dei
  riquadri clienti. Periodi correnti di calendario; settimana da lunedi' a domenica.
- I riquadri mostrano gli incassi lordi; i rimborsi sono riportati separatamente.
- Totale ancora da incassare.
- Accessi rapidi a nuovo cliente e appuntamento.
- Stato della sincronizzazione ed eventuali errori da risolvere.

Gli incassi non devono essere presentati come utile: nella prima versione
non vengono calcolate spese, imposte e contributi.

## 5. Funzioni successive candidate

Da ordinare in base all'uso reale, senza includerle automaticamente nel MVP.

### Priorita' alta

- Abbonamenti con regole esplicite su durata, rinnovo e sospensione.
- Appuntamenti ricorrenti con modifica della singola occorrenza o della serie.
- Lista d'attesa e gestione dei recuperi.
- Importazione clienti e movimenti da CSV con anteprima e controllo duplicati.
- Spese professionali e riepilogo economico distinto dagli incassi.

Per i pacchetti, l'acquisto genera l'addebito economico; l'utilizzo di una
lezione scala il residuo senza addebitare nuovamente la stessa prestazione.
Eventuali eccedenze, rimborsi e scadenze richiedono regole concordate.

### Evoluzioni possibili

- Sedute di gruppo con piu' di due partecipanti e capienza.
- Ulteriori statistiche su frequenza, assenze e andamento dell'attivita'.
- Obiettivi e misurazioni, previa valutazione della natura dei dati e della privacy.
- Allegati e documentazione, con requisiti di protezione e conservazione dedicati.
- Integrazione con Calendario Apple, evitando duplicazioni e definendo la direzione
  della sincronizzazione.
- Preparazione di messaggi email o WhatsApp con invio sempre confermato dall'utente.
- Collegamento a un servizio di fatturazione elettronica.

### Fuori ambito iniziale

- Portale clienti, prenotazione autonoma e pagamenti online.
- Accessi multiutente e gestione di piu' professionisti.
- Applicazioni Android o Windows.
- Diagnosi, prescrizioni, suggerimenti clinici o gestione sanitaria specialistica.

## 6. Esperienza su Mac e iPhone

### Mac: gestione completa

Navigazione proposta:

1. Panoramica
2. Agenda
3. Clienti
4. Pagamenti
5. Report ed estratti
6. Impostazioni

Interfaccia con barra laterale, tabelle filtrabili, ricerca, scorciatoie da
tastiera e supporto alla stampa.

### iPhone: operazioni quotidiane

- Consultare e aggiornare l'agenda.
- Creare e modificare clienti e appuntamenti.
- Segnare una seduta come completata.
- Registrare pacchetti, completare lezioni e consultare incassi e saldo.
- Consultare lo storico cliente e visualizzare/condividere un estratto.
- Visualizzare lo stato della sincronizzazione.

Agenda, nuovi appuntamenti e incassi automatici sono disponibili anche su
iPhone. Configurazioni avanzate, esportazioni complete e ripristino dell'archivio
possono inizialmente restare sul Mac.

Su entrambe le piattaforme: testo leggibile, supporto a VoiceOver, navigazione
accessibile e stati distinguibili anche senza affidarsi solo ai colori.

## 7. Regole economiche da rispettare

- Separare prestazioni/addebiti, pagamenti e relative associazioni.
- Usare importi esatti in centesimi, non numeri a virgola mobile.
- Definire una convenzione unica: saldo positivo = importo dovuto dal cliente;
  saldo negativo = credito del cliente.
- Calcolare il saldo come addebiti netti meno incassi netti.
- Gli addebiti netti includono eventuali storni; gli incassi netti sono pagamenti
  meno rimborsi. Un rimborso non annulla da solo un addebito.
- Un anticipo riduce il saldo senza inventare una prestazione.
- Le associazioni non possono superare l'importo disponibile del pagamento
  o quello ancora aperto dell'addebito.
- Registrare separatamente la data della prestazione e quella dell'incasso.
- Conservare il prezzo storico e il riferimento alla prestazione di origine.
- Completare o sincronizzare due volte la stessa seduta non deve duplicare l'addebito.
- Correzioni economiche tramite operazioni tracciate, non cancellazioni silenziose.
- Distinguere la data economica del movimento dalla data tecnica di registrazione.

Esempio di verifica:

| Operazione | Addebiti netti | Incassi netti | Saldo cliente |
| --- | ---: | ---: | ---: |
| Due sedute da EUR 50 | EUR 100 | EUR 0 | EUR 100 da pagare |
| Pagamento parziale di EUR 60 | EUR 100 | EUR 60 | EUR 40 da pagare |
| Ulteriore pagamento di EUR 60 | EUR 100 | EUR 120 | EUR 20 a credito |
| Rimborso del credito di EUR 20 | EUR 100 | EUR 100 | EUR 0 |

I report di incasso seguono la data del pagamento, non quella dell'appuntamento.
Gli estratti per periodo includono il saldo dei movimenti precedenti come saldo
iniziale, senza confonderlo con gli incassi del periodo.

## 8. Architettura tecnica proposta

### Tecnologie

- Swift e SwiftUI per applicazioni realmente native.
- Modelli e logica condivisi, interfacce adattate alle due piattaforme.
- SwiftData come candidato per l'archivio locale.
- CloudKit con database privato iCloud come candidato per la sincronizzazione.
- API native Apple per notifiche, PDF, stampa ed esportazioni.
- Nessun backend personalizzato nella prima proposta.

Deployment target iniziale: macOS 14 e iOS 17, compatibile con SwiftData.
Il requisito delle ultime tre versioni principali richiede un collaudo dedicato:
il deployment target da solo non certifica la compatibilita'.

Prima di confermare SwiftData + CloudKit serve un piccolo prototipo che verifichi
relazioni, migrazioni, conflitti, gestione degli errori e protezione dei dati.
Gli eventuali limiti non devono essere aggirati con perdita di dati o saldi errati.

### Struttura logica

- Presentazione: schermate e componenti specifici Mac/iPhone.
- Dominio: agenda, regole economiche, validazioni e generazione dei report.
- Persistenza: archivio locale, sincronizzazione e migrazioni.
- Servizi di piattaforma: notifiche, esportazioni e backup.

### Entita' principali

| Entita' | Scopo |
| --- | --- |
| Cliente | Anagrafica, contatti e stato di archiviazione |
| Servizio | Listino, durata e prezzo predefiniti |
| Appuntamento | Cliente, orario, stato e condizioni concordate |
| Indisponibilita' | Intervalli non prenotabili |
| Addebito | Importo dovuto e riferimento alla prestazione |
| Pagamento | Incasso ricevuto e metodo |
| Allocazione | Quota di pagamento associata a un addebito |
| Rettifica / rimborso | Correzione collegata al movimento originale |
| Impostazioni | Preferenze e dati del professionista |
| Pacchetto e utilizzo | Evoluzione successiva per lezioni prepagate |

Ogni record ha un identificativo stabile e metadati utili alla sincronizzazione.
Saldi e totali sono calcolati dai movimenti, non modificabili a mano.

## 9. Sincronizzazione e funzionamento offline

- Le operazioni vengono prima salvate localmente.
- L'assenza di rete non impedisce di consultare l'archivio o registrare operazioni.
- La propagazione tra dispositivi e' asincrona: non promettere aggiornamenti istantanei.
- Distinguere chiaramente dati salvati in locale e sincronizzazione in sospeso,
  nei limiti degli stati effettivamente osservabili tramite le API.
- Mostrare errori di account, spazio o sincronizzazione con azioni comprensibili.
- Non perdere modifiche in caso di chiusura o riavvio dell'applicazione.
- Definire e testare una politica di conflitto prima dell'implementazione completa.
- Non usare silenziosamente l'ultima modifica per risolvere conflitti economici.
- Rendere idempotenti gli addebiti derivati dagli appuntamenti.
- Segnalare anche sovrapposizioni di agenda emerse dopo la sincronizzazione:
  offline non e' possibile garantire un blocco globale delle prenotazioni.
- Gestire esplicitamente uscita o cambio dell'account iCloud, senza mescolare
  archivi di account differenti.

La sincronizzazione non e' un backup: una cancellazione o un errore potrebbero
propagarsi a entrambi i dispositivi.

## 10. Privacy, protezione e backup

- Raccogliere solo i dati necessari al servizio.
- Anamnesi e analisi fisica possono contenere dati sulla salute: inserirli
  solo se necessari e con una base giuridica, informativa e conservazione
  adeguate alla propria attivita'. La presenza dei campi non attesta conformita'.
- Le note organizzative rimangono separate dalle informazioni riservate.
- I campi riservati sono inizialmente chiusi nella scheda cliente e leggibili
  tramite espansione; sono modificabili solo nel modulo della scheda.
- Nessuna telemetria contenente dati personali o finanziari dei clienti.
- Non scrivere recapiti, note o dettagli dei pagamenti nei log diagnostici.
- Usare Keychain per eventuali segreti; non salvarli in file di configurazione.
- Valutare blocco dell'app con autenticazione di sistema e timeout configurabile.
- Verificare le protezioni effettive di archivio locale e cloud: iCloud da solo
  non equivale a conformita' GDPR o a una promessa di cifratura end-to-end.
- Definire informativa, conservazione, accesso, esportazione e cancellazione
  dei dati con un consulente, se necessario.
- Distinguere archiviazione operativa e cancellazione definitiva; eventuali
  obblighi di conservazione dei movimenti vanno chiariti prima di implementarla.
- Limitare i dettagli dei promemoria sulla schermata bloccata.

### Backup proposto

- Backup completo manuale dal Mac, separato dagli estratti PDF e CSV.
- Backup protetto con cifratura tramite strumenti/API consolidati, senza
  algoritmi personalizzati e senza password incorporate nell'app.
- Indicazione della data dell'ultimo backup riuscito.
- Archivio versionato con tutti i dati e le relazioni necessari al ripristino.
- Ripristino con verifica del contenuto, anteprima e conferma esplicita.
- Nessuna sovrascrittura distruttiva senza una copia di sicurezza preventiva.
- Procedura di ripristino coordinata con iCloud per evitare duplicazioni,
  ricomparsa di dati rimossi o propagazione accidentale di dati incompleti.
- Test di recupero effettivo prima di utilizzare dati reali.

Il CSV e' un formato di scambio, non un backup completo dell'applicazione.

## 11. Percorso di realizzazione

### Fase 0 - Conferma del progetto

- Confermare priorita', flussi quotidiani e regole economiche.
- Verificare modelli di Mac/iPhone e versioni dei sistemi operativi.
- Scegliere sincronizzazione e modalita' di installazione.
- Preparare pochi esempi inventati di clienti, appuntamenti e pagamenti.

### Fase 1 - Fondamenta e prova di sincronizzazione

- Creare i target Mac e iPhone e il codice condiviso.
- Realizzare un primo flusso anagrafico con salvataggio locale.
- Validare iCloud su dispositivi reali, offline, conflitti e cambio account.
- Definire schema, migrazioni e strategia di backup/ripristino.

### Fase 2 - Clienti e agenda

- Completare anagrafiche, servizi, appuntamenti individuali e indisponibilita'.
- Collegare scheda cliente, calendario e stati degli appuntamenti.
- Verificare flussi principali su entrambe le piattaforme.

### Fase 3 - Gestione economica

- Implementare addebiti, pagamenti, allocazioni, anticipi, rettifiche e rimborsi.
- Collegare le sedute completate alla posizione economica del cliente.
- Introdurre pacchetti da 10, assegnazione ai clienti e consumo idempotente.
- Testare calcoli e idempotenza anche dopo la sincronizzazione.

### Fase 4 - Estratti e protezione dell'archivio

- Realizzare riepiloghi, statistiche su ore/incassi, PDF, CSV e stampa.
- Implementare e collaudare backup, ripristino e misure di protezione concordate.
- Completare accessibilita', notifiche ed errori visibili.

### Fase 5 - Utilizzo pilota

- Provare scenari realistici con dati inventati.
- Verificare installazione e aggiornamenti su Mac e iPhone.
- Passare ai dati reali solo dopo validazione dei conti e del recupero dati.
- Raccogliere feedback prima di introdurre abbonamenti o altre estensioni.

## 12. Criteri di accettazione della prima versione

- Un cliente creato sul Mac compare su iPhone e viceversa dopo la sincronizzazione.
- Un appuntamento conserva data e ora corrette, anche nei passaggi di ora legale.
- Un'interruzione di rete non impedisce il salvataggio locale.
- Le modifiche offline vengono recuperate alla riconnessione senza duplicazioni.
- I conflitti non causano perdite silenziose o doppi addebiti.
- Il cambio account non carica dati nell'archivio di un altro account.
- Un cliente archiviato non perde appuntamenti e movimenti.
- Pagamenti parziali, anticipi e rimborsi producono i saldi dell'esempio economico.
- Un appuntamento completato genera al massimo un addebito.
- Un annullamento segue la regola concordata e non introduce penali implicite.
- L'estratto include saldo iniziale e finale corretti per il periodo selezionato.
- PDF e CSV coincidono con i dati mostrati nell'app e gestiscono nomi e note
  con accenti, separatori e ritorni a capo.
- Un backup ripristinato ricostruisce clienti, agenda, movimenti e saldi,
  senza duplicarli alla successiva sincronizzazione.
- Un aggiornamento dello schema conserva correttamente i dati esistenti.
- Errori di salvataggio, esportazione o sincronizzazione sono visibili all'utente.

I controlli automatici useranno gli strumenti del progetto Swift/Xcode; le prove
di sincronizzazione e installazione comprenderanno anche dispositivi reali.

## 13. Decisioni da prendere prima dello sviluppo

1. Quali modelli e versioni di macOS/iOS devono essere supportati? Vanno bene le ultime tre versioni di macosx e ios
2. Mac e iPhone usano lo stesso account Apple ed e' accettabile usare iCloud? Si
3. Su iPhone bastano le operazioni quotidiane proposte o servono tutte le funzioni? Tutte le funzioni per vedere l'agentda, registrare i pagamenti e fissare nuovi appuntamenti
4. Si lavora con sedute singole, pacchetti, abbonamenti o una combinazione? O sedute singole o pacchetti da 10, sessioni singole o in coppia
5. Come devono essere trattati annullamenti, assenze, recuperi e penali? Non importano
6. Per "estratti" bastano estratti conto cliente e riepiloghi di incasso non fiscali? Anche ore lavorate, orari più scelti, media guadagno oraria, totale incasso e tutto ciò che riguarda incassi e tempi lavorati. Inoltre i pacchetti da 10 vengono assegnati ai clienti e bisogna scalare un utilizzo ad ogni sessione
7. Esistono dati da importare da fogli di calcolo o altri gestionali? no
8. Si gestiscono solo clienti fitness o anche pazienti in un contesto sanitario? solo clienti fitness
9. Quale modalita' di distribuzione adottare: sviluppo personale, TestFlight
   per il collaudo o distribuzione stabile tramite App Store? nessuna distribuzione, saranno installate in locale
10. Quale nome definitivo e quali dati del professionista mostrare sugli estratti? nessun dato personale

Firma, provisioning, disponibilita' di un account Apple Developer e relativi
costi/requisiti vanno verificati prima di promettere un'installazione stabile.
TestFlight e' un canale di collaudo, non la soluzione definitiva di distribuzione.

## 14. Prossimo passo

Collaudare la versione operativa con dati inventati su Mac e iPhone.
Prima di passare ai dati reali, verificare il ripristino di un backup e,
se si desidera la sincronizzazione, configurare la firma iCloud e provare
trasferimenti, conflitti e cambio account sui due dispositivi fisici.

## 15. Implementazione - versione 0.4.0

### Prototipo locale compilato

- App SwiftUI nativa con navigazione Mac e interfaccia iPhone condivisa.
- Panoramica con conteggi reali dei clienti e accesso alle schede recenti.
- Inserimento e modifica clienti, recapiti facoltativi e note organizzative.
- Ricerca per nome, telefono o email; filtri attivi, archiviati e tutti.
- Archiviazione e riattivazione senza cancellazione dei dati.
- Validazione dei campi e avviso per possibili duplicati.
- Modifica tramite bozza: Annulla non modifica l'archivio.
- Salvataggio locale esplicito con SwiftData e schema versionato.
- Errori di apertura e salvataggio visibili; nessun ripiego su archivi temporanei.
- Swift Package senza dipendenze esterne e progetto Xcode multipiattaforma.
- Agenda con selezione giorno, settimana e mese; nuove sedute individuali.
- Selezione iniziale del cliente e ultime preferenze persistenti.
- Settimana in colonne e selezione rapida di giorni/orari liberi a minuti 00.
- Listino con piu' tariffe per servizio e prezzi storici per partecipante.
- Anamnesi e analisi fisica facoltative, incluse nel backup cifrato.
- Indisponibilita', segnalazione sovrapposizioni e stati delle sedute.
- Pacchetti da 10 con scadenza facoltativa, acquisto e storico degli utilizzi.
- Incassi automatici, storico pagamenti, rimborsi e storni collegati ai movimenti originali.
- Riquadri incassi per anno, mese e settimana.
- Saldi cliente e allocazioni automatiche dei pagamenti agli addebiti.
- Statistiche su incassi, tempi lavorati e fasce orarie.
- Estratti non fiscali con anteprima ed esportazione CSV/PDF.
- Backup completo cifrato e ripristino locale in un nuovo archivio.
- Blocco facoltativo con autenticazione di sistema.
- Promemoria locali facoltativi e senza dati personali nel testo.

### Limiti e attivazioni esterne

- La build locale da terminale usa sempre un archivio locale.
- Il codice di sincronizzazione CloudKit si attiva solo in una build Xcode
  configurata e firmata per il proprio container. Non e' stato creato alcun
  account Developer o container remoto e non e' stato acquistato alcun servizio.
- Installazione e sincronizzazione su dispositivi fisici non sono ancora
  certificate; il collaudo locale/simulatore non le sostituisce.
- Il ripristino sostitutivo e' bloccato nelle build iCloud, per non propagare
  cancellazioni o duplicazioni. Gli archivi locali e iCloud non vengono uniti
  automaticamente all'attivazione del servizio.
- Le evoluzioni della sezione 5 rimangono fuori dal MVP approvato: abbonamenti,
  liste d'attesa, importazioni, gruppi oltre due persone, integrazioni esterne
  e fatturazione elettronica non sono incluse nella versione 0.4.0.

Il modello clienti evita vincoli di unicita' incompatibili con la futura
sincronizzazione CloudKit. Questo non equivale a una sincronizzazione gia'
collaudata su dispositivi reali. Non esiste un interruttore che abiliti
iCloud senza configurazione della firma e delle capability.

### Regole operative

- Le sedute completate sono congelate: orari, partecipanti e prezzi non vengono
  modificati retroattivamente. Le correzioni economiche sono movimenti di storno,
  non cancellazioni dello storico.
- Annullamento e assenza non generano penali automatiche.
- Il consumo del pacchetto e l'eventuale addebito sono registrati insieme al
  completamento; una ripetizione dell'operazione non deve contarli due volte.
- Il prezzo di un nuovo pacchetto e' addebitato e incassato alla registrazione.
  Le lezioni che usano il pacchetto consumano il residuo senza duplicare l'incasso.
- Le lezioni singole generano l'incasso al completamento, nella stessa
  transazione dell'addebito e del cambio stato; un secondo completamento
  non genera altri movimenti. Gli importi zero non creano pagamenti fittizi.
- Non vengono aggiunti incassi retroattivi ai pacchetti o alle lezioni
  gia' completate nelle versioni precedenti.
- Gli appuntamenti storici con due partecipanti restano consultabili e possono
  essere completati/annullati, ma non modificati o convertiti in sedute singole.
- I pagamenti sono ripartiti automaticamente sugli addebiti aperti, in ordine
  cronologico. Il residuo non allocato e' un anticipo.
- I rimborsi fanno riferimento a un incasso; gli storni a un addebito.
  Importi oltre il residuo correggibile sono rifiutati.
- Il rapporto incassi/ora non e' un utile fiscale o il valore delle sole sedute
  del periodo: gli anticipi lo possono alterare. Con zero ore il rapporto
  non viene calcolato. Le sedute storiche con piu' persone contano una volta.
- Le esportazioni comprendono dati personali dei clienti: scegliere una
  destinazione protetta e condividere solo quando necessario.

### Migrazione e recupero

Lo schema 4 aggiunge le ultime preferenze di appuntamento per cliente.
Conserva i campi riservati e le tariffe dello schema 3, le anagrafiche e tutti
i movimenti degli schemi precedenti, senza ricreare incassi. I servizi
precedenti propongono una tariffa "Standard" con il prezzo gia' salvato.
I vecchi backup senza i nuovi campi restano importabili: i testi mancanti
vengono inizializzati vuoti, non inventati. Il percorso storico del database
resta valido. Dopo l'aggiornamento
non aprire lo stesso archivio con una versione precedente dell'app.

Il backup usa AES-256-GCM e una chiave derivata dalla password con
PBKDF2-HMAC-SHA256 (600.000 iterazioni, sale casuale). Password minima:
12 caratteri; non viene memorizzata. Limiti del formato: payload 64 MB,
file cifrato 100 MB. Una password errata o dati alterati impediscono il recupero.

Il ripristino valida prima l'archivio, crea una copia cifrata dei dati correnti,
scrive in una cartella nuova e attiva il risultato solo dopo verifica.
Il database precedente e la copia di sicurezza rimangono sul dispositivo.
La selezione dell'archivio ripristinato viene conservata anche al riavvio.

### Verifiche eseguite e correzione del salvataggio

Xcode 26.6 e' installato. Sono riuscite la build Swift Package per Mac,
le build Xcode per Mac e simulatore iPhone e la creazione del bundle locale
`build/Paola Gestionale.app`, con firma ad hoc verificata.

Il test dell'interfaccia su simulatore iPhone 17 Pro / iOS 26.5 e' passato:
creazione cliente, validazione, persistenza dopo riavvio, annullamento della
bozza, modifica del telefono con aggiornamento della scheda, archiviazione
persistente e riattivazione.

La prima esecuzione dei 33 test del dominio ha rilevato un problema nel test
di errore di persistenza (32 test passati, un test con cinque asserzioni fallite).
La scrittura nel contesto osservato dalla UI, seguita da un errore,
poteva rendere inefficace `ModelContext.rollback()` e lasciare visibili
modifiche non salvate.

Correzione verificata l'8 settembre 2026:

- Ogni operazione scrive in un nuovo contesto SwiftData con autosave disabilitato.
- Il contesto della UI non viene modificato durante il tentativo di salvataggio.
- Solo dopo il commit si rileggono i dati, aggiornando le istanze gia' osservate.
- Se la scrittura fallisce, l'errore originale viene mostrato e il tentativo
  non altera clienti, metadati, archiviazione o elenco visibile.
- La bozza rimane disponibile per correggere i dati o ritentare l'operazione.
- Un eventuale errore di aggiornamento della schermata dopo un commit riuscito
  viene distinto dal fallimento della scrittura: l'app avvisa che i dati
  sono salvati e impedisce di reinviare la stessa scheda.

Collaudo della versione 0.3.0, 9 settembre 2026:

- 119 test SwiftPM superati: include migrazioni V1/V2 verso V3, nuovi campi
  cliente, tariffe multiple, prezzi storici, vecchi backup e disponibilita'.
- 4 flussi UI iPhone superati nello stesso collaudo, compreso il nuovo percorso
  con anamnesi e analisi fisica conservate dopo riavvio, due tariffe, prezzo
  selezionato, colonne settimanali ed esclusione degli orari occupati.
- Verificato il caso seduta 10:00-11:00: per una nuova durata di 90 minuti
  non vengono proposte le 09:00 e le 10:00, mentre le 11:00 sono disponibili.
- Verificati cambi di settimana e anno, ora legale, ore gia' trascorse,
  assenze/annullamenti, pause e occupazioni che attraversano la mezzanotte.
- Build native Mac/iPhone riuscite; bundle Mac 0.3.0 firmato ad hoc e avviato
  con un archivio temporaneo separato. Nessun dato utente usato nel collaudo.

Collaudo precedente della versione 0.2.0 (prima delle modifiche del 9 settembre):

- 96 test SwiftPM superati: anagrafica, conti, pacchetti, errori di scrittura,
  conflitti, migrazione, backup cifrato, ripristino esatto e PDF/CSV.
- 3 test dell'interfaccia iPhone superati nello stesso collaudo: ciclo clienti,
  blocco dei controlli protetti e percorso servizio/pacchetto/coppia/pagamenti/report.
- Build macOS e iPhone Simulator riuscite; app Mac avviata con finestra visibile
  e database temporaneo separato da quello dell'utente.
- Esportazione PDF multipagina e CSV verificati con tutti i movimenti presenti,
  accenti, note multilinea, virgolette e protezione delle celle testuali da formule.

Non sono stati modificati gli archivi reali durante i test. Autenticazione
biometrica e consegna delle notifiche devono essere provate sui propri dispositivi:
non sono stati accettati permessi di sistema al posto del proprietario.

Installazione su iPhone fisico e sincronizzazione iCloud non sono ancora
state collaudate. Utilizzare dati inventati fino alla verifica finale sui
propri dispositivi.

Usare solo dati inventati. La build locale da terminale e la futura app firmata
sandboxed possono utilizzare percorsi di archivio differenti: nessun trasferimento
automatico dei dati tra le due installazioni e' previsto in questa fase.

## 16. Avvio e sviluppo

### Prerequisito: Xcode completo

Installare Xcode, aprirlo almeno una volta e completare il download dei componenti
richiesti. I soli Command Line Tools non includono tutti i componenti SwiftData.
Non e' stata modificata la selezione globale degli strumenti sul Mac.

Con Xcode nel percorso standard, si puo' selezionarlo per il solo terminale
corrente, senza cambiare l'impostazione globale:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

### Mac: prima prova locale

La nuova build viene preparata in `build/releases/0.4.0/Paola Gestionale.app`.
Chiudere prima la vecchia app: non usare contemporaneamente due versioni sullo
stesso archivio. Aprire la nuova app attiva la migrazione automatica dello schema.
La vecchia applicazione aperta non e' stata chiusa o sostituita durante lo sviluppo.

```bash
open "build/releases/0.4.0/Paola Gestionale.app"
```

Per ricompilare separatamente la versione completa:

```bash
PAOLA_APP_OUTPUT="$PWD/build/releases/0.4.0/Paola Gestionale.app" \
  bash scripts/build-macos.sh
```

Lo script compila il pacchetto, crea un bundle macOS e applica una firma ad hoc
per il solo sviluppo locale. Non installa nulla in Applicazioni, non abilita
iCloud e non produce una release notarizzata. L'app rimane nella cartella `build`.

L'archivio della build da terminale risiede in
`~/Library/Application Support/PaolaGestionale/Clienti-v1.store`
con eventuali file SQLite associati. Non cancellare o spostare questi file
mentre l'app e' aperta; la loro copia manuale non sostituisce il futuro backup.

### Test

```bash
xcrun swift test
```

I test usano archivi in memoria o cartelle temporanee isolate, senza modificare
l'archivio dell'app e senza account iCloud. Il test di riapertura verifica che
i dati salvati su disco siano letti da un nuovo container.

### Test dell'interfaccia iPhone

Lo schema `PaolaGestionale-iOS-UI` esegue XCTest UI su un simulatore iPhone:
validazione dei campi, creazione cliente, riapertura dell'app, annullamento
delle modifiche, archiviazione persistente e riattivazione, protezione dei
controlli e percorso con cliente iniziale, preferenze, pacchetto, completamento
lezione e incassi automatici.
Un quarto flusso verifica colonne settimanali, scelte rapide, tariffe multiple
e salvataggio dei campi riservati.

Ogni test UI apre un archivio isolato tramite un identificativo casuale.
Il codice di selezione degli archivi di collaudo e' disponibile solo in Debug.
I riavvii all'interno dello stesso test mantengono il medesimo archivio.

Usare un simulatore dedicato e senza dati reali: il test crea clienti inventati.
Dopo averlo selezionato in Xcode, usare Product > Test. Da terminale:

```bash
xcodebuild -project PaolaGestionale.xcodeproj \
  -scheme PaolaGestionale-iOS-UI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

Il nome della destinazione va adattato al simulatore disponibile.
Per evitare ambiguita' tra il prodotto Swift Package e il bundle nativo,
il target Xcode dell'app si chiama `PaolaGestionaleApp`; lo schema principale
e il nome dell'app rimangono `PaolaGestionale`.

### Xcode: Mac e iPhone

1. Installare Xcode completo con gli SDK per i dispositivi da usare.
2. Aprire `PaolaGestionale.xcodeproj`.
3. Copiare `Config/Local.xcconfig.example` in `Config/Local.xcconfig`.
4. Impostare il proprio `DEVELOPMENT_TEAM` e un bundle identifier univoco.
   Il file locale e' escluso dal controllo versione.
5. Selezionare lo schema `PaolaGestionale` e la destinazione Mac o iPhone.
6. Per iPhone fisico, completare pairing, Developer Mode e provisioning in Xcode.
7. Eseguire l'app. Con la configurazione predefinita i dati restano locali
   a ciascun dispositivo.

Lo schema app compila la UI; i test del dominio si eseguono dal pacchetto con
`swift test` oppure aprendo `Package.swift` in Xcode.

Anche senza pubblicazione su App Store, iPhone richiede firma e provisioning.
Un Personal Team gratuito ha limitazioni e non e' sufficiente per il percorso
iCloud previsto: occorre verificare un'iscrizione Apple Developer adeguata.

### Passaggio a iCloud

1. Nel proprio team Apple Developer, creare un container CloudKit e associarlo
   all'identificativo dell'app su entrambe le piattaforme.
2. Nel file locale di configurazione, impostare il proprio team e bundle ID.
3. Abilitare le righe di esempio `PAOLA_CLOUD_ENABLED`, `PAOLA_CLOUD_CONTAINER`,
   `PAOLA_MAC_ENTITLEMENTS` e `PAOLA_IOS_ENTITLEMENTS`, usando lo stesso
   container per Mac e iPhone.
4. Verificare in Signing & Capabilities la configurazione iCloud/CloudKit,
   Background Modes e il provisioning. Per installazioni di produzione,
   verificare anche la distribuzione dello schema CloudKit nel relativo ambiente.
5. Compilare con Xcode e provare inizialmente con dati inventati.

All'apertura viene verificato l'account CloudKit. Ogni account usa un archivio
locale distinto, identificato da un hash dell'identificativo account/container;
un cambio account chiude il contenuto corrente prima di aprire un altro archivio.
Non viene usato un account precedente come ripiego quando la verifica fallisce.
La verifica iniziale dell'account puo' richiedere connettivita'; una volta aperto,
SwiftData salva localmente e trasferisce i dati in modo asincrono.

Gli stati mostrati derivano dagli eventi del container CloudKit: trasferimento
in corso, ultimo trasferimento completato o errore. Un trasferimento completato
non garantisce che tutti i dispositivi siano gia' aggiornati.

Il collegamento a iCloud apre un archivio dedicato, non carica automaticamente
le copie locali preesistenti. Prima di questa transizione esportare un backup
e definire quale copia debba essere la sorgente iniziale; non importare due volte
gli stessi dati su dispositivi diversi.
