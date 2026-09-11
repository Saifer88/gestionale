import Foundation

/// Anagrafica di una parte (cedente o cessionario) per la FatturaPA.
public struct FatturaPAParty: Equatable, Sendable {
    public var name: String
    public var taxCode: String        // Codice fiscale
    public var vatNumber: String?     // Partita IVA (solo cedente forfettario)
    public var address: String        // Indirizzo (via e civico)
    public var postalCode: String     // CAP
    public var city: String           // Comune
    public var province: String       // Provincia (sigla), opzionale
    public var country: String        // Nazione (IT)

    public init(name: String, taxCode: String, vatNumber: String? = nil,
                address: String, postalCode: String, city: String,
                province: String = "", country: String = "IT") {
        self.name = name; self.taxCode = taxCode; self.vatNumber = vatNumber
        self.address = address; self.postalCode = postalCode; self.city = city
        self.province = province; self.country = country
    }
}

/// Dati necessari a generare l'XML FatturaPA di una singola fattura forfettaria.
public struct FatturaPAInput: Equatable, Sendable {
    public var seller: FatturaPAParty
    public var buyer: FatturaPAParty
    public var breakdown: ForfettarioBreakdown
    public var issueDate: Date
    public var paymentMethod: PaymentMethod
    public var lineDescription: String
    /// Progressivo di invio del file (identificativo tecnico della trasmissione).
    public var transmissionProgressive: String
    /// Codice destinatario SDI (per privati senza PEC: 0000000).
    public var recipientCode: String

    public init(seller: FatturaPAParty, buyer: FatturaPAParty, breakdown: ForfettarioBreakdown,
                issueDate: Date, paymentMethod: PaymentMethod, lineDescription: String,
                transmissionProgressive: String,
                recipientCode: String = ForfettarioTax.defaultRecipientCode) {
        self.seller = seller; self.buyer = buyer; self.breakdown = breakdown
        self.issueDate = issueDate; self.paymentMethod = paymentMethod
        self.lineDescription = lineDescription
        self.transmissionProgressive = transmissionProgressive
        self.recipientCode = recipientCode
    }
}

public enum FatturaPAError: Error, LocalizedError, Equatable {
    case incompleteSeller([String])
    case incompleteBuyer(String)

    public var errorDescription: String? {
        switch self {
        case .incompleteSeller(let issues):
            return "Dati del cedente incompleti: " + issues.joined(separator: " ")
        case .incompleteBuyer(let field):
            return "Dati del cliente incompleti: \(field)."
        }
    }
}

/// Genera l'XML FatturaPA v1.2 per una fattura in regime forfettario.
/// Nessuna IVA (Natura N2.2), rivalsa INPS 4% come cassa previdenziale TC22, nessun bollo.
public enum FatturaPAXMLBuilder {

    /// Mappa il metodo di pagamento sui codici ModalitaPagamento FatturaPA.
    /// Stripe e carta -> MP08 (carta di pagamento); bonifico -> MP05; contanti -> MP01.
    static func paymentCode(_ method: PaymentMethod) -> String {
        switch method {
        case .stripe, .card, .paypal: return "MP08"
        case .bankTransfer: return "MP05"
        case .cash: return "MP01"
        case .other: return "MP08"
        }
    }

    /// Importo in centesimi -> stringa decimale con due cifre (es. 5769 -> "57.69").
    static func amount(_ cents: Int64) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = cents.magnitude
        return "\(sign)\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
    }

    /// Escaping XML dei caratteri riservati.
    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }

    private static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func build(_ input: FatturaPAInput) throws -> String {
        let sellerIssues = SellerFiscalProfile(
            vatNumber: input.seller.vatNumber ?? "", taxCode: input.seller.taxCode,
            name: input.seller.name, addressStreet: input.seller.address,
            addressPostalCode: input.seller.postalCode, addressCity: input.seller.city,
            addressProvince: input.seller.province.isEmpty ? "XX" : input.seller.province
        ).validationIssues.filter { !$0.contains("provincia") || !input.seller.province.isEmpty }
        guard input.seller.vatNumber?.isEmpty == false else {
            throw FatturaPAError.incompleteSeller(["Partita IVA del cedente mancante."])
        }
        if !sellerIssues.isEmpty { throw FatturaPAError.incompleteSeller(sellerIssues) }

        guard !input.buyer.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FatturaPAError.incompleteBuyer("nome")
        }
        guard !input.buyer.taxCode.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FatturaPAError.incompleteBuyer("codice fiscale")
        }
        guard !input.buyer.address.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FatturaPAError.incompleteBuyer("indirizzo di fatturazione")
        }

        let s = input.seller
        let b = input.buyer
        let bk = input.breakdown
        let taxable = amount(bk.taxableCents)
        let contribution = amount(bk.contributionCents)
        let total = amount(bk.totalCents)
        let cassaPercent = "\(ForfettarioTax.cassaPercent).00"

        // CAP e Comune del cliente: FatturaPA li richiede. Per i privati usiamo i valori
        // disponibili; se mancano, valori minimi tecnicamente accettati (00000 / n.d.).
        let buyerCap = b.postalCode.isEmpty ? "00000" : b.postalCode
        let buyerCity = b.city.isEmpty ? "n.d." : b.city

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:FatturaElettronica versione="FPR12" xmlns:p="http://ivaservizi.agenziaentrate.gov.it/docs/xsd/fatture/v1.2">
          <FatturaElettronicaHeader>
            <DatiTrasmissione>
              <IdTrasmittente>
                <IdPaese>IT</IdPaese>
                <IdCodice>\(escape(ForfettarioTax.arubaTransmitterCode))</IdCodice>
              </IdTrasmittente>
              <ProgressivoInvio>\(escape(input.transmissionProgressive))</ProgressivoInvio>
              <FormatoTrasmissione>FPR12</FormatoTrasmissione>
              <CodiceDestinatario>\(escape(input.recipientCode))</CodiceDestinatario>
            </DatiTrasmissione>
            <CedentePrestatore>
              <DatiAnagrafici>
                <IdFiscaleIVA>
                  <IdPaese>IT</IdPaese>
                  <IdCodice>\(escape(s.vatNumber ?? ""))</IdCodice>
                </IdFiscaleIVA>
                <CodiceFiscale>\(escape(s.taxCode))</CodiceFiscale>
                <Anagrafica>
                  <Denominazione>\(escape(s.name))</Denominazione>
                </Anagrafica>
                <RegimeFiscale>RF19</RegimeFiscale>
              </DatiAnagrafici>
              <Sede>
                <Indirizzo>\(escape(s.address))</Indirizzo>
                <CAP>\(escape(s.postalCode))</CAP>
                <Comune>\(escape(s.city))</Comune>
                <Provincia>\(escape(s.province))</Provincia>
                <Nazione>\(escape(s.country))</Nazione>
              </Sede>
            </CedentePrestatore>
            <CessionarioCommittente>
              <DatiAnagrafici>
                <CodiceFiscale>\(escape(b.taxCode))</CodiceFiscale>
                <Anagrafica>
                  <Denominazione>\(escape(b.name))</Denominazione>
                </Anagrafica>
              </DatiAnagrafici>
              <Sede>
                <Indirizzo>\(escape(b.address))</Indirizzo>
                <CAP>\(escape(buyerCap))</CAP>
                <Comune>\(escape(buyerCity))</Comune>
                <Nazione>\(escape(b.country))</Nazione>
              </Sede>
            </CessionarioCommittente>
          </FatturaElettronicaHeader>
          <FatturaElettronicaBody>
            <DatiGenerali>
              <DatiGeneraliDocumento>
                <TipoDocumento>TD01</TipoDocumento>
                <Divisa>EUR</Divisa>
                <Data>\(date(input.issueDate))</Data>
                <Numero>\(escape(input.transmissionProgressive))</Numero>
                <DatiCassaPrevidenziale>
                  <TipoCassa>\(ForfettarioTax.cassaType)</TipoCassa>
                  <AlCassa>\(cassaPercent)</AlCassa>
                  <ImportoContributoCassa>\(contribution)</ImportoContributoCassa>
                  <ImponibileCassa>\(taxable)</ImponibileCassa>
                  <Natura>\(ForfettarioTax.naturaCode)</Natura>
                </DatiCassaPrevidenziale>
              </DatiGeneraliDocumento>
            </DatiGenerali>
            <DatiBeniServizi>
              <DettaglioLinee>
                <NumeroLinea>1</NumeroLinea>
                <Descrizione>\(escape(input.lineDescription))</Descrizione>
                <Quantita>1.00</Quantita>
                <PrezzoUnitario>\(taxable)</PrezzoUnitario>
                <PrezzoTotale>\(taxable)</PrezzoTotale>
                <Natura>\(ForfettarioTax.naturaCode)</Natura>
              </DettaglioLinee>
              <DatiRiepilogo>
                <AliquotaIVA>0.00</AliquotaIVA>
                <Natura>\(ForfettarioTax.naturaCode)</Natura>
                <ImponibileImporto>\(taxable)</ImponibileImporto>
                <Imposta>0.00</Imposta>
                <RiferimentoNormativo>\(escape(ForfettarioTax.riferimentoNormativo))</RiferimentoNormativo>
              </DatiRiepilogo>
            </DatiBeniServizi>
            <DatiPagamento>
              <CondizioniPagamento>TP02</CondizioniPagamento>
              <DettaglioPagamento>
                <ModalitaPagamento>\(paymentCode(input.paymentMethod))</ModalitaPagamento>
                <ImportoPagamento>\(total)</ImportoPagamento>
              </DettaglioPagamento>
            </DatiPagamento>
          </FatturaElettronicaBody>
        </p:FatturaElettronica>
        """
        return xml
    }
}
