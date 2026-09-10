@testable import PaolaCore
import XCTest

final class ArubaAPITests: XCTestCase {

    func testSigninRequestBuildsFormURLEncodedBodyAndRejectsMissingCredentials() throws {
        XCTAssertThrowsError(try ArubaAPI.signinRequest(environment: .demo, credentials: ArubaCredentials()))

        let request = try ArubaAPI.signinRequest(environment: .demo,
            credentials: ArubaCredentials(username: "123@aruba.it", password: "x"))
        XCTAssertEqual(request.httpMethod, "POST")
        // L'autenticazione usa il base URL dedicato (demoauth), non quello dei web service.
        XCTAssertEqual(request.url?.host, "demoauth.fatturazioneelettronica.aruba.it")
        XCTAssertTrue(request.url?.absoluteString.hasSuffix("/auth/signin") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded;charset=UTF-8")
        let body = try XCTUnwrap(request.httpBody)
        let string = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(string.contains("grant_type=password"))
        XCTAssertTrue(string.contains("username=123%40aruba.it"))
        XCTAssertTrue(string.contains("password=x"))
    }

    func testRefreshRequestUsesRefreshTokenGrant() throws {
        let request = ArubaAPI.refreshRequest(environment: .demo, refreshToken: "r123")
        let body = try XCTUnwrap(request.httpBody)
        let string = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(string.contains("grant_type=refresh_token"))
        XCTAssertTrue(string.contains("refresh_token=r123"))
    }

    func testEnvironmentBaseURLsDiffer() {
        XCTAssertNotEqual(ArubaEnvironment.demo.authBaseURL, ArubaEnvironment.production.authBaseURL)
        XCTAssertNotEqual(ArubaEnvironment.demo.wsBaseURL, ArubaEnvironment.production.wsBaseURL)
        XCTAssertTrue(ArubaEnvironment.production.wsBaseURL.absoluteString.contains("ws.fatturazioneelettronica.aruba.it"))
        XCTAssertTrue(ArubaEnvironment.production.authBaseURL.absoluteString.contains("auth.fatturazioneelettronica.aruba.it"))
        XCTAssertTrue(ArubaEnvironment.demo.wsBaseURL.absoluteString.contains("demows"))
        XCTAssertTrue(ArubaEnvironment.demo.authBaseURL.absoluteString.contains("demoauth"))
    }

    func testParseAuthResponseReadsAccessAndRefreshToken() throws {
        let tokens = try ArubaAPI.parseAuthResponse(Data(#"{"access_token":"abc","token_type":"bearer","expires_in":1800,"refresh_token":"r1"}"#.utf8))
        XCTAssertEqual(tokens.accessToken, "abc")
        XCTAssertEqual(tokens.refreshToken, "r1")
    }

    func testParseSigninResponseSupportsFlatAndNestedTokenAndOAuthError() throws {
        XCTAssertEqual(try ArubaAPI.parseSigninResponse(Data(#"{"access_token":"abc"}"#.utf8)), "abc")
        XCTAssertEqual(try ArubaAPI.parseSigninResponse(Data(#"{"value":{"access_token":"xyz"}}"#.utf8)), "xyz")
        XCTAssertThrowsError(try ArubaAPI.parseSigninResponse(Data(#"{"foo":"bar"}"#.utf8)))
        // Errore OAuth mappato a serviceError.
        XCTAssertThrowsError(try ArubaAPI.parseSigninResponse(Data(#"{"error":"invalid_grant","error_description":"bad"}"#.utf8))) { error in
            guard case ArubaAPIError.serviceError(let code, _) = error else {
                return XCTFail("Atteso serviceError, ricevuto \(error)")
            }
            XCTAssertEqual(code, "invalid_grant")
        }
    }

    func testUploadRequestEncodesXMLAsBase64DataFileOnWSBaseURL() throws {
        let xml = "<Fattura>test</Fattura>"
        let request = ArubaAPI.uploadRequest(environment: .demo, token: "tok", xml: xml, fileName: "IT123_00001.xml")
        XCTAssertEqual(request.url?.host, "demows.fatturazioneelettronica.aruba.it")
        XCTAssertTrue(request.url?.absoluteString.hasSuffix("/services/invoice/upload") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let dataFile = try XCTUnwrap(json["dataFile"] as? String)
        let decoded = try XCTUnwrap(Data(base64Encoded: dataFile))
        XCTAssertEqual(String(data: decoded, encoding: .utf8), xml)
        // Campi richiesti dal servizio anche se vuoti.
        XCTAssertNotNil(json["credential"])
        XCTAssertNotNil(json["domain"])
        XCTAssertNotNil(json["senderPIVA"])
        XCTAssertEqual(json["skipExtraSchema"] as? Bool, false)
    }

    func testStatusRequestUsesGetByFilenameQuery() {
        let request = ArubaAPI.statusRequest(environment: .demo, token: "tok", filename: "IT01879020517_kasxh.xml.p7m")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let url = request.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("/services/invoice/out/getByFilename"))
        XCTAssertTrue(url.contains("filename=IT01879020517"))
    }

    func testMapStatusPreservesTransmittedVsDeliveredDistinction() {
        XCTAssertEqual(ArubaAPI.mapStatus("Inviata"), .transmitted)
        XCTAssertEqual(ArubaAPI.mapStatus("Presa in carico"), .transmitted)
        XCTAssertEqual(ArubaAPI.mapStatus("Consegnata"), .delivered)
        XCTAssertEqual(ArubaAPI.mapStatus("Accettata"), .delivered)
        XCTAssertEqual(ArubaAPI.mapStatus("Scartata"), .rejected)
        XCTAssertEqual(ArubaAPI.mapStatus("Rifiutata"), .rejected)
        XCTAssertEqual(ArubaAPI.mapStatus("qualcosa-ignoto"), .transmitted)
    }

    func testParseStatusResponseReadsInvoicesArray() throws {
        XCTAssertEqual(try ArubaAPI.parseStatusResponse(Data(#"{"invoices":[{"status":"Consegnata"}]}"#.utf8)), .delivered)
        XCTAssertEqual(try ArubaAPI.parseStatusResponse(Data(#"{"value":{"invoices":[{"status":"Scartata"}]}}"#.utf8)), .rejected)
        // Compatibilità con forma piatta.
        XCTAssertEqual(try ArubaAPI.parseStatusResponse(Data(#"{"stato":"Inviata"}"#.utf8)), .transmitted)
        XCTAssertThrowsError(try ArubaAPI.parseStatusResponse(Data(#"{}"#.utf8)))
    }

    func testParseUploadResponseChecksErrorCode() throws {
        // Successo: errorCode "0000", legge uploadFileName.
        XCTAssertEqual(
            try ArubaAPI.parseUploadResponse(Data(#"{"errorCode":"0000","errorDescription":"Operazione effettuata - 123","uploadFileName":"IT01879020517_kasxh.xml.p7m"}"#.utf8)),
            "IT01879020517_kasxh.xml.p7m")
        // Fallback su idSdi annidato.
        XCTAssertEqual(try ArubaAPI.parseUploadResponse(Data(#"{"value":{"errorCode":"0000","idSdi":"999"}}"#.utf8)), "999")
        // Errore applicativo: errorCode diverso da 0000.
        XCTAssertThrowsError(try ArubaAPI.parseUploadResponse(Data(#"{"errorCode":"0002","errorDescription":"File non valido"}"#.utf8))) { error in
            guard case ArubaAPIError.serviceError(let code, _) = error else {
                return XCTFail("Atteso serviceError, ricevuto \(error)")
            }
            XCTAssertEqual(code, "0002")
        }
        XCTAssertThrowsError(try ArubaAPI.parseUploadResponse(Data(#"{"errorCode":"0000"}"#.utf8)))
    }
}
