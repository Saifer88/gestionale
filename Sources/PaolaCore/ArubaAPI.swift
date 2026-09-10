import Foundation

/// Ambiente del servizio di fatturazione elettronica Aruba.
/// Aruba usa due base URL distinti: uno per l'autenticazione e uno per gli altri metodi.
public enum ArubaEnvironment: Equatable, Sendable {
    case demo
    case production

    /// Base URL dei metodi di autenticazione (signin/refresh).
    public var authBaseURL: URL {
        switch self {
        case .production: return URL(string: "https://auth.fatturazioneelettronica.aruba.it")!
        case .demo: return URL(string: "https://demoauth.fatturazioneelettronica.aruba.it")!
        }
    }

    /// Base URL degli altri metodi (upload, ricerca fatture, ecc.).
    public var wsBaseURL: URL {
        switch self {
        case .production: return URL(string: "https://ws.fatturazioneelettronica.aruba.it")!
        case .demo: return URL(string: "https://demows.fatturazioneelettronica.aruba.it")!
        }
    }
}

public enum ArubaAPIError: Error, LocalizedError, Equatable {
    case notAuthenticated
    case invalidResponse
    case httpError(Int, String)
    case missingCredentials
    case decodeFailed
    /// Errore applicativo restituito dal servizio (errorCode != "0000").
    case serviceError(String, String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Autenticazione ad Aruba non riuscita. Verifica username e password del servizio."
        case .invalidResponse: return "Risposta del servizio Aruba non valida."
        case .httpError(let code, let message):
            return "Errore dal servizio Aruba (\(code)). \(message)"
        case .missingCredentials: return "Credenziali Aruba mancanti. Inseriscile nella sezione Credenziali."
        case .decodeFailed: return "Impossibile interpretare la risposta del servizio Aruba."
        case .serviceError(let code, let description):
            return "Il servizio Aruba ha rifiutato la fattura (\(code)). \(description)"
        }
    }
}

/// Costruzione delle richieste e parsing delle risposte per le API Aruba.
/// Parte pura, senza rete, così è interamente testabile. L'esecuzione HTTP
/// (URLSession) vive nel client dell'app.
///
/// Endpoint e formati derivano dalla documentazione ufficiale Aruba:
/// - autenticazione su `authBaseURL`, corpo `application/x-www-form-urlencoded`;
/// - upload e ricerca fatture su `wsBaseURL`, corpo JSON, header `Bearer`.
public enum ArubaAPI {

    // Percorsi degli endpoint, centralizzati.
    public static let signinPath = "/auth/signin"
    public static let uploadPath = "/services/invoice/upload"
    public static let statusPath = "/services/invoice/out/getByFilename"

    // MARK: - Signin

    /// Costruisce la richiesta di autenticazione (POST {authBaseURL}/auth/signin).
    /// Il corpo è `application/x-www-form-urlencoded` con grant_type=password.
    /// Il corpo non viene mai loggato.
    public static func signinRequest(environment: ArubaEnvironment,
                                     credentials: ArubaCredentials) throws -> URLRequest {
        guard credentials.isComplete else { throw ArubaAPIError.missingCredentials }
        var request = URLRequest(url: environment.authBaseURL.appendingPathComponent(signinPath))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formURLEncoded([
            "grant_type": "password",
            "username": credentials.username,
            "password": credentials.password
        ])
        return request
    }

    /// Costruisce la richiesta di refresh del token (grant_type=refresh_token).
    public static func refreshRequest(environment: ArubaEnvironment,
                                      refreshToken: String) -> URLRequest {
        var request = URLRequest(url: environment.authBaseURL.appendingPathComponent(signinPath))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formURLEncoded([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
        return request
    }

    /// Token estratti dalla risposta di signin/refresh.
    public struct AuthTokens: Equatable {
        public let accessToken: String
        public let refreshToken: String?
        public init(accessToken: String, refreshToken: String?) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
        }
    }

    /// Estrae il Bearer token (e l'eventuale refresh token) dalla risposta di signin.
    /// La risposta reale è JSON piatto: {access_token, token_type, expires_in, refresh_token}.
    public static func parseAuthResponse(_ data: Data) throws -> AuthTokens {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArubaAPIError.decodeFailed
        }
        // Errore OAuth: {error, error_description}.
        if let error = object["error"] as? String {
            let description = object["error_description"] as? String ?? error
            throw ArubaAPIError.serviceError(error, description)
        }
        if let token = object["access_token"] as? String, !token.isEmpty {
            return AuthTokens(accessToken: token, refreshToken: object["refresh_token"] as? String)
        }
        // Compatibilità con eventuale annidamento in "value".
        if let value = object["value"] as? [String: Any],
           let token = value["access_token"] as? String, !token.isEmpty {
            return AuthTokens(accessToken: token, refreshToken: value["refresh_token"] as? String)
        }
        throw ArubaAPIError.notAuthenticated
    }

    /// Estrae solo il Bearer token (comodità).
    public static func parseSigninResponse(_ data: Data) throws -> String {
        try parseAuthResponse(data).accessToken
    }

    // MARK: - Upload

    /// Costruisce la richiesta di upload della fattura (POST {wsBaseURL}/services/invoice/upload).
    /// L'XML viene inviato in base64 nel campo `dataFile`.
    public static func uploadRequest(environment: ArubaEnvironment, token: String,
                                     xml: String, fileName: String) -> URLRequest {
        var request = URLRequest(url: environment.wsBaseURL.appendingPathComponent(uploadPath))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let base64 = Data(xml.utf8).base64EncodedString()
        let body: [String: Any] = [
            "dataFile": base64,
            "credential": "",
            "domain": "",
            "senderPIVA": "",
            "skipExtraSchema": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Esito dell'upload: il servizio restituisce errorCode/errorDescription e,
    /// in caso di successo (errorCode "0000"), il nome file assegnato.
    public struct UploadResult: Equatable {
        public let uploadFileName: String
        public init(uploadFileName: String) { self.uploadFileName = uploadFileName }
    }

    /// Esito dell'upload: nome file assegnato da Aruba (per il successivo polling).
    /// Lancia `serviceError` se `errorCode` è diverso da "0000".
    public static func parseUploadResponse(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArubaAPIError.decodeFailed
        }
        let container = (object["value"] as? [String: Any]) ?? object
        if let code = container["errorCode"] as? String, code != "0000" {
            let description = container["errorDescription"] as? String ?? code
            throw ArubaAPIError.serviceError(code, description)
        }
        if let name = container["uploadFileName"] as? String, !name.isEmpty { return name }
        // Fallback: alcuni ambienti restituiscono un identificativo SDI.
        if let id = container["idSdi"] as? String, !id.isEmpty { return id }
        throw ArubaAPIError.invalidResponse
    }

    // MARK: - Stato SDI

    /// Costruisce la richiesta di interrogazione dello stato tramite nome file
    /// (GET {wsBaseURL}/services/invoice/out/getByFilename?filename=...).
    public static func statusRequest(environment: ArubaEnvironment, token: String,
                                     filename: String) -> URLRequest {
        var components = URLComponents(url: environment.wsBaseURL.appendingPathComponent(statusPath),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "filename", value: filename)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Mappa lo stato testuale restituito da Aruba/SDI su `InvoiceStatus`.
    /// Stati reali: Presa in carico, Errore elaborazione, Inviata, Scartata,
    /// Non consegnata, Recapito impossibile, Consegnata, Accettata, Rifiutata,
    /// Decorrenza termini.
    /// Uno stato "inviata/trasmessa" non equivale a "consegnata": distinzione preservata.
    public static func mapStatus(_ raw: String) -> InvoiceStatus {
        switch raw.uppercased() {
        case "CONSEGNATA", "DELIVERED", "ACCETTATA", "DECORRENZA TERMINI":
            return .delivered
        case "PRESA IN CARICO", "INVIATA", "TRASMESSA", "SENT", "PENDING",
             "NON CONSEGNATA", "RECAPITO IMPOSSIBILE":
            return .transmitted
        case "SCARTATA", "RIFIUTATA", "REJECTED", "ERRORE ELABORAZIONE", "ERROR_SDI":
            return .rejected
        default:
            return .transmitted
        }
    }

    /// Estrae lo stato dalla risposta di interrogazione.
    /// La risposta reale contiene `invoices: [{status: "..."}]`.
    public static func parseStatusResponse(_ data: Data) throws -> InvoiceStatus {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArubaAPIError.decodeFailed
        }
        let container = (object["value"] as? [String: Any]) ?? object
        if let invoices = container["invoices"] as? [[String: Any]],
           let first = invoices.first,
           let state = first["status"] as? String {
            return mapStatus(state)
        }
        // Compatibilità con forme piatte.
        if let state = container["stato"] as? String ?? container["status"] as? String {
            return mapStatus(state)
        }
        throw ArubaAPIError.invalidResponse
    }

    // MARK: - Helper

    /// Codifica un dizionario come corpo application/x-www-form-urlencoded.
    static func formURLEncoded(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = parameters.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
