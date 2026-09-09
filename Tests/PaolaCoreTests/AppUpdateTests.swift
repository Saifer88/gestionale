import PaolaCore
import XCTest

final class AppUpdateTests: XCTestCase {

    // MARK: - AppVersion

    func testVersionParsingAcceptsMajorMinorMajorMinorPatchAndTagPrefix() {
        XCTAssertEqual(AppVersion("0.6"), AppVersion(major: 0, minor: 6, patch: 0))
        XCTAssertEqual(AppVersion("0.6.42"), AppVersion(major: 0, minor: 6, patch: 42))
        XCTAssertEqual(AppVersion("v0.6.42"), AppVersion(major: 0, minor: 6, patch: 42))
        XCTAssertEqual(AppVersion(" V1.2.3 "), AppVersion(major: 1, minor: 2, patch: 3))
    }

    func testVersionParsingRejectsMalformedStrings() {
        XCTAssertNil(AppVersion("0"))
        XCTAssertNil(AppVersion("0.6.42.1"))
        XCTAssertNil(AppVersion("0.x"))
        XCTAssertNil(AppVersion("-1.0.0"))
        XCTAssertNil(AppVersion(""))
    }

    func testVersionOrderingIsNumericNotLexicographic() {
        XCTAssertLessThan(AppVersion("0.6.9")!, AppVersion("0.6.10")!)
        XCTAssertLessThan(AppVersion("0.6.42")!, AppVersion("0.7.0")!)
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("1.0.0")!)
        XCTAssertEqual(AppVersion("0.6")!, AppVersion("0.6.0")!)
    }

    // MARK: - GitHubReleaseParser

    private func releaseJSON(tag: String, includeChecksums: Bool = true, draft: Bool = false) -> Data {
        var assets = """
        {"name":"PaolaGestionale-macOS-universal-\(tag)-build.42.zip",
         "browser_download_url":"https://example.com/app.zip","size":1234}
        """
        if includeChecksums {
            assets += """
            ,{"name":"SHA256SUMS.txt",
              "browser_download_url":"https://example.com/SHA256SUMS.txt","size":80}
            """
        }
        let json = """
        {"tag_name":"\(tag)","draft":\(draft),"body":"Note di rilascio","assets":[\(assets)]}
        """
        return Data(json.utf8)
    }

    func testParseLatestReleaseExtractsVersionNotesAndAssets() throws {
        let release = try GitHubReleaseParser.parseLatestRelease(releaseJSON(tag: "v0.6.42"))
        XCTAssertEqual(release.tag, "v0.6.42")
        XCTAssertEqual(release.version, AppVersion("0.6.42"))
        XCTAssertEqual(release.notes, "Note di rilascio")
        XCTAssertTrue(release.appArchive.name.hasSuffix(".zip"))
        XCTAssertEqual(release.appArchive.downloadURL.absoluteString, "https://example.com/app.zip")
        XCTAssertEqual(release.checksums?.name, "SHA256SUMS.txt")
    }

    func testParseLatestReleaseRejectsDraftAndMissingAssets() {
        XCTAssertThrowsError(try GitHubReleaseParser.parseLatestRelease(releaseJSON(tag: "v0.6.42", draft: true)))
        let noAsset = Data(#"{"tag_name":"v0.6.42","assets":[]}"#.utf8)
        XCTAssertThrowsError(try GitHubReleaseParser.parseLatestRelease(noAsset)) { error in
            XCTAssertEqual(error as? UpdateError, .noCompatibleAsset)
        }
    }

    func testParseLatestReleaseWithoutChecksumsStillParses() throws {
        let release = try GitHubReleaseParser.parseLatestRelease(releaseJSON(tag: "v0.7.0", includeChecksums: false))
        XCTAssertNil(release.checksums)
        XCTAssertEqual(release.version, AppVersion("0.7.0"))
    }

    func testEvaluateReportsUpdateOnlyForNewerVersion() throws {
        let release = try GitHubReleaseParser.parseLatestRelease(releaseJSON(tag: "v0.6.42"))
        if case .updateAvailable(_, let found) = GitHubReleaseParser.evaluate(current: AppVersion("0.6.0")!, release: release) {
            XCTAssertEqual(found.version, AppVersion("0.6.42"))
        } else {
            XCTFail("Attesa una versione più recente disponibile.")
        }
        XCTAssertEqual(GitHubReleaseParser.evaluate(current: AppVersion("0.6.42")!, release: release),
                       .upToDate(current: AppVersion("0.6.42")!))
        XCTAssertEqual(GitHubReleaseParser.evaluate(current: AppVersion("0.9.0")!, release: release),
                       .upToDate(current: AppVersion("0.9.0")!))
    }

    // MARK: - ChecksumManifest

    func testChecksumManifestFindsExpectedHashForFile() {
        let hash = String(repeating: "a", count: 64)
        let manifest = "\(hash)  PaolaGestionale-macOS-universal-v0.6.42-build.42.zip\n"
        XCTAssertEqual(ChecksumManifest.expectedHash(
            for: "PaolaGestionale-macOS-universal-v0.6.42-build.42.zip", manifest: manifest), hash)
    }

    func testChecksumManifestHandlesBinaryStarPrefixAndReturnsNilWhenAbsent() {
        let hash = String(repeating: "b", count: 64)
        let manifest = "\(hash) *app.zip\nother  README.txt\n"
        XCTAssertEqual(ChecksumManifest.expectedHash(for: "app.zip", manifest: manifest), hash)
        XCTAssertNil(ChecksumManifest.expectedHash(for: "missing.zip", manifest: manifest))
    }

    func testChecksumManifestRejectsNonHexOrWrongLengthHashes() {
        let manifest = "zzzz  app.zip\n" + String(repeating: "a", count: 63) + "  app.zip\n"
        XCTAssertNil(ChecksumManifest.expectedHash(for: "app.zip", manifest: manifest))
    }
}
