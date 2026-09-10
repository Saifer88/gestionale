#if os(macOS) || os(iOS)
import Foundation
import PaolaCore

/// Client di rete per il servizio di fatturazione elettronica Aruba.
/// Usa la logica pura di `ArubaAPI` (costruzione richieste/parsing) e `URLSession`.
/// L'ambiente (demo/produzione) dipende dal tipo di build (`AppEnvironment`).
/// Le credenziali arrivano dal Keychain; nessun segreto viene loggato.
actor ArubaClient {
    private let environment: ArubaEnvironment
    private let session: URLSession
    private let credentials: ArubaCredentials
    private var token: String?

    init(environment: ArubaEnvironment = AppEnvironment.usesArubaDemo ? .demo : .production,
         credentials: ArubaCredentials,
         session: URLSession = .shared) {
        self.environment = environment
        self.credentials = credentials
        self.session = session
    }

    /// Autentica e memorizza il Bearer token per le chiamate successive.
    func authenticate() async throws {
        let request = try ArubaAPI.signinRequest(environment: environment, credentials: credentials)
        let data = try await send(request, expectingAuth: false)
        token = try ArubaAPI.parseSigninResponse(data)
    }

    /// Invia l'XML della fattura e ritorna l'identificativo assegnato da Aruba.
    func upload(xml: String, fileName: String) async throws -> String {
        let token = try await validToken()
        let request = ArubaAPI.uploadRequest(environment: environment, token: token,
                                              xml: xml, fileName: fileName)
        let data = try await send(request, expectingAuth: true)
        return try ArubaAPI.parseUploadResponse(data)
    }

    /// Interroga lo stato SDI della fattura trasmessa, usando il nome file
    /// restituito dall'upload.
    func status(filename: String) async throws -> InvoiceStatus {
        let token = try await validToken()
        let request = ArubaAPI.statusRequest(environment: environment, token: token, filename: filename)
        let data = try await send(request, expectingAuth: true)
        return try ArubaAPI.parseStatusResponse(data)
    }

    // MARK: - Interno

    private func validToken() async throws -> String {
        if let token { return token }
        try await authenticate()
        guard let token else { throw ArubaAPIError.notAuthenticated }
        return token
    }

    private func send(_ request: URLRequest, expectingAuth: Bool) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ArubaAPIError.invalidResponse }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            if expectingAuth {
                // Token scaduto: riautentica una volta.
                token = nil
            }
            throw ArubaAPIError.notAuthenticated
        default:
            // Non includere il corpo della richiesta (può contenere dati): solo un estratto della risposta.
            let message = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw ArubaAPIError.httpError(http.statusCode, message)
        }
    }
}
#endif
