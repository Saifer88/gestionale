# Prodotto - Paola Gestionale

Applicazione nativa per la gestione del lavoro quotidiano di un singolo personal trainer:
clienti, agenda, prestazioni, pagamenti e riepiloghi economici.

Stato attuale: versione 0.6.0 compilata e collaudata. Pipeline di release macOS
predisposta. Sincronizzazione iCloud approvata ma non ancora configurata/collaudata
su dispositivi reali.

## Utenti e piattaforme

- Un solo personal trainer (nessun multiutente, nessun collaboratore).
- App native macOS (postazione principale) e iPhone (lavoro fuori studio).
- Dati sincronizzati tra un Mac e un iPhone con lo stesso account Apple, via iCloud.
- Supporto alle ultime tre versioni principali di macOS e iOS.
- Interfaccia in italiano, importi in euro, date in formato italiano.
- Solo clienti fitness. Nessuna diagnosi, cartella clinica o gestione sanitaria.

## Funzioni principali (MVP)

- **Anagrafica clienti**: recapiti, stato attivo/archiviato, note organizzative,
  campi riservati facoltativi (anamnesi, analisi fisica), servizio e tariffa preferiti,
  ricerca e segnalazione duplicati.
- **Agenda**: viste giorno/settimana/mese, appuntamenti con uno o più partecipanti,
  stati (programmato, completato, annullato, assenza), indisponibilità/ferie/pause,
  proposte rapide di giorni e orari liberi, segnalazione sovrapposizioni.
- **Servizi e listino**: servizi con durata e più tariffe nominate per persona;
  prezzo storico congelato sulla prestazione.
- **Pacchetti**: assegnati ai clienti, utilizzi configurabili (rapidi 5/10, default 10),
  consumo idempotente al completamento della sessione senza secondo incasso.
- **Pagamenti e saldo**: incassi automatici (nuovo pacchetto e lezione singola non coperta),
  allocazione automatica agli addebiti aperti, rimborsi e storni tracciati.
- **Estratti e riepiloghi**: estratto conto cliente, incassi per periodo/metodo,
  ore lavorate, orari più scelti, media incassi/ora, esportazione PDF e CSV.
- **Panoramica**: quattro righe fisse (incassi periodici e previsti, contatori settimanali,
  appuntamenti del giorno, scorciatoie).

## Regole invarianti (da non violare mai)

- Importi esatti in **centesimi** (`Int64`), mai floating point.
- Convenzione saldo: positivo = dovuto dal cliente; negativo = credito.
  Saldo = addebiti netti − incassi netti.
- Prezzo storico congelato: modificare il listino non cambia lo storico.
- Completare o sincronizzare due volte la stessa seduta non deve duplicare l'addebito.
- Correzioni economiche tramite movimenti tracciati (storni/rimborsi), mai cancellazioni silenziose.
- Data della prestazione e data dell'incasso registrate separatamente.
- Sedute completate congelate: orari, partecipanti e prezzi non cambiano retroattivamente.
- La sincronizzazione non è un backup: una cancellazione può propagarsi ai dispositivi.

## Privacy

- Solo dati necessari. Campi riservati (salute) separati dalle note organizzative
  ed esclusi da ricerca generale, estratti e promemoria.
- Nessun dato personale del professionista sugli estratti; questi riportano
  "Documento non fiscale".
- Nessuna telemetria con dati personali/finanziari. Nessun recapito, nota o
  dettaglio di pagamento nei log diagnostici.
- Segreti solo in Keychain, mai in file di configurazione.
- Usare **solo dati inventati** durante lo sviluppo e il collaudo.

## Fuori ambito (prima versione)

- Portale clienti, prenotazioni autonome e pagamenti online.
- Multiutente e più professionisti.
- Android/Windows.
- Abbonamenti, ricorrenze, importazioni CSV, fatturazione elettronica (candidati futuri).
- Diagnosi, prescrizioni o gestione sanitaria specialistica.

Il documento di riferimento completo è `PROGETTO.md` nella radice del repository.
