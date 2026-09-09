import XCTest

final class ClientWorkflowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    override func tearDownWithError() throws {
        guard let run = testRun, run.failureCount + run.unexpectedExceptionCount > 0 else { return }
        let app = XCUIApplication()
        if app.state == .runningForeground {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Albero UI al fallimento"
            tree.lifetime = .keepAlways
            add(tree)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Schermata al fallimento"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testClientCreationCancellationArchiveAndRelaunch() throws {
        let app = testApplication()
        app.launchArguments = ["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()

        let surname = "Collaudo-\(UUID().uuidString.prefix(8))"
        let fullName = "Cliente \(surname)"
        let emailAddress = "\(surname.lowercased())@example.it"
        let newClient = app.buttons["Nuovo cliente"].firstMatch
        XCTAssertTrue(newClient.waitForExistence(timeout: 10))
        newClient.tap()
        app.buttons["client.save"].tap()
        let validation = app.alerts["Impossibile salvare"]
        XCTAssertTrue(validation.waitForExistence(timeout: 3))
        validation.buttons["OK"].tap()

        let firstName = app.textFields["client.firstName"]
        firstName.tap()
        firstName.typeText("Cliente")
        let lastName = app.textFields["client.lastName"]
        lastName.tap()
        lastName.typeText(surname)
        let email = app.textFields["client.email"]
        email.tap()
        email.typeText(emailAddress)
        app.buttons["client.save"].tap()

        XCTAssertTrue(app.staticTexts[fullName].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        let persistedClient = app.staticTexts[fullName].firstMatch
        XCTAssertTrue(persistedClient.waitForExistence(timeout: 10))
        persistedClient.tap()
        XCTAssertTrue(app.buttons["Modifica"].waitForExistence(timeout: 5))
        app.buttons["Modifica"].tap()
        let editName = app.textFields["client.firstName"]
        XCTAssertTrue(editName.waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["client.email"].value as? String, emailAddress)
        editName.tap()
        editName.typeText("Bozza")
        app.buttons["Annulla"].tap()
        XCTAssertTrue(app.staticTexts[fullName].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["ClienteBozza \(surname)"].exists)

        app.buttons["Modifica"].tap()
        let phone = app.textFields["client.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 3))
        phone.tap()
        phone.typeText("3330001234")
        app.buttons["client.save"].tap()
        XCTAssertTrue(app.buttons["Modifica"].waitForExistence(timeout: 5))
        app.buttons["Modifica"].tap()
        XCTAssertTrue(app.textFields["client.phone"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["client.phone"].value as? String, "3330001234")
        app.buttons["Annulla"].tap()

        tapArchiveButton(in: app)
        app.buttons["Archivia"].tap()
        XCTAssertTrue(app.buttons["client.archive"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["client.archive"].label, "Riattiva cliente")
        app.terminate()
        app.launch()
        app.tabBars.buttons["Clienti"].tap()
        app.segmentedControls.buttons["Archiviati"].tap()
        let archivedClient = app.staticTexts[fullName].firstMatch
        XCTAssertTrue(archivedClient.waitForExistence(timeout: 5))
        archivedClient.tap()
        XCTAssertTrue(app.staticTexts["Cliente archiviato"].waitForExistence(timeout: 3))
        tapArchiveButton(in: app)
        app.buttons["Riattiva"].tap()
        let reactivated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Archivia cliente"),
            object: app.buttons["client.archive"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reactivated], timeout: 5), .completed)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Scheda cliente dopo il collaudo"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func tapArchiveButton(in app: XCUIApplication) {
        tap(app.buttons["client.archive"], in: app)
    }

    @MainActor
    func testLockBlocksAccessToClientControls() throws {
        let app = testApplication()
        app.launchArguments = [
            "-AppleLanguages", "(it)", "-AppleLocale", "it_IT",
            "-privacy.appLockEnabled", "YES"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Sblocca"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Nuovo cliente"].firstMatch.isHittable)
        XCTAssertFalse(app.tabBars.buttons["Clienti"].isHittable)
        XCTAssertFalse(app.buttons["Nuovo cliente"].firstMatch.isEnabled)
        app.terminate()
        app.launchArguments = [
            "-AppleLanguages", "(it)", "-AppleLocale", "it_IT",
            "-privacy.appLockEnabled", "NO"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Nuovo cliente"].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testClientFirstDefaultsAutomaticIncomeAndReport() throws {
        let app = testApplication()
        app.launchArguments = ["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let suffix = String(UUID().uuidString.prefix(6))
        let firstName = "Uno Operativo-\(suffix)"
        let secondName = "Due Operativo-\(suffix)"
        for first in ["Uno", "Due"] {
            let newClient = app.buttons["Nuovo cliente"].firstMatch
            XCTAssertTrue(newClient.waitForExistence(timeout: 10))
            newClient.tap()
            replace(app.textFields["client.firstName"], with: first)
            replace(app.textFields["client.lastName"], with: "Operativo-\(suffix)")
            app.buttons["client.save"].tap()
            XCTAssertTrue(newClient.waitForExistence(timeout: 5))
        }

        app.tabBars.buttons["Impostazioni"].tap()
        app.buttons["Servizi e listino"].tap()
        tap(app.buttons["services.new"], in: app)
        replace(app.textFields["service.name"], with: "Sessione-\(suffix)")
        replace(app.textFields["service.price"], with: "50")
        tap(app.buttons["service.addRate"], in: app)
        replace(app.textFields["service.rateName.1"], with: "Ridotta")
        replace(app.textFields["service.ratePrice.1"], with: "35")
        app.buttons["service.save"].tap()
        XCTAssertTrue(app.buttons["services.new"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Impostazioni"].tap()

        app.buttons["Pacchetti da 10"].tap()
        tap(app.buttons["packages.new"], in: app)
        choose("package.client", label: firstName, in: app)
        replace(app.textFields["package.price"], with: "400")
        app.buttons["package.save"].tap()
        app.buttons["package.confirmIncome"].firstMatch.tap()
        XCTAssertTrue(app.buttons["packages.new"].waitForExistence(timeout: 5))
        assertIncomeCards("400,00", in: app)

        app.tabBars.buttons["Agenda"].tap()
        app.buttons["agenda.add"].tap()
        XCTAssertTrue(app.buttons["session.client1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["agenda.newBlock"].exists)
        XCTAssertFalse(app.buttons["session.service"].exists)
        XCTAssertFalse(app.switches["session.pair"].exists)
        choose("session.client1", label: firstName, in: app)
        XCTAssertTrue(app.buttons["session.service"].label.contains("Sessione-\(suffix)"))
        choosePrefix("session.tariff1", prefix: "Ridotta ·", in: app)
        tap(app.buttons["session.package1"], in: app)
        let package = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pacchetto del")).firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 3))
        package.tap()
        let nextDay = try nextWeekday()
        tap(app.buttons[italianDayLabel(nextDay)].firstMatch, in: app)
        tap(app.buttons["session.quickHour.13:00"], in: app)
        app.buttons["session.save"].tap()
        XCTAssertTrue(app.buttons["agenda.add"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        assertIncomeCards("400,00", in: app)
        app.tabBars.buttons["Agenda"].tap()
        app.buttons["agenda.add"].tap()
        choose("session.client1", label: firstName, in: app)
        XCTAssertTrue(app.buttons["session.service"].label.contains("Sessione-\(suffix)"))
        reveal(app.buttons["session.package1"], in: app)
        XCTAssertTrue(app.buttons["session.package1"].label.contains("Pacchetto del"))
        reveal(app.textFields["session.price1"], in: app)
        XCTAssertEqual(app.textFields["session.price1"].value as? String, "35,00")
        let time = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "session.selectedTime", "13:00")
        ).firstMatch
        for _ in 0..<5 where !time.exists { app.swipeDown() }
        XCTAssertTrue(time.exists)
        choose("session.client1", label: secondName, in: app)
        reveal(app.buttons["session.package1"], in: app)
        XCTAssertTrue(app.buttons["session.package1"].label.contains("No"))
        reveal(app.textFields["session.price1"], in: app)
        XCTAssertEqual(app.textFields["session.price1"].value as? String, "50,00")
        app.buttons["Annulla"].tap()
        completeFirstSession(clientName: firstName, serviceName: "Sessione-\(suffix)", in: app)
        assertIncomeCards("400,00", in: app)

        app.tabBars.buttons["Agenda"].tap()
        app.buttons["agenda.add"].tap()
        choose("session.client1", label: secondName, in: app)
        tap(app.buttons[italianDayLabel(nextDay)].firstMatch, in: app)
        tap(app.buttons["session.quickHour.16:00"], in: app)
        app.buttons["session.save"].tap()
        XCTAssertTrue(app.buttons["agenda.add"].waitForExistence(timeout: 5))
        completeFirstSession(clientName: secondName, serviceName: "Sessione-\(suffix)", in: app)
        assertIncomeCards("450,00", in: app)

        app.tabBars.buttons["Pagamenti"].tap()
        XCTAssertFalse(app.buttons["payments.new"].exists)
        app.tabBars.buttons["Impostazioni"].tap()
        app.buttons["Statistiche ed estratti"].tap()
        tap(app.buttons["reports.document"], in: app)
        app.buttons["reports.preview"].firstMatch.tap()
        XCTAssertTrue(app.buttons["reports.preview.close"].waitForExistence(timeout: 5))
        let reportText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "DOCUMENTO NON FISCALE")).firstMatch
        XCTAssertTrue(reportText.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Estratto con incasso pacchetto e lezione completata"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["reports.preview.close"].tap()
    }

    @MainActor
    func testWeeklyColumnsQuickSlotsTariffsAndClientFields() throws {
        let app = testApplication()
        app.launchArguments = ["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        tap(app.buttons["Nuovo cliente"].firstMatch, in: app)
        replace(app.textFields["client.firstName"], with: "Cliente")
        replace(app.textFields["client.lastName"], with: "Nuove funzioni")
        let anamnesis = app.textViews["client.anamnesis"]
        reveal(anamnesis, in: app)
        anamnesis.tap()
        anamnesis.typeText("Anamnesi inventata per collaudo")
        let analysis = app.textViews["client.physicalAnalysis"]
        reveal(analysis, in: app)
        analysis.tap()
        analysis.typeText("Analisi inventata per collaudo")
        app.buttons["client.save"].tap()
        app.terminate()
        app.launch()
        let client = app.staticTexts["Cliente Nuove funzioni"].firstMatch
        reveal(client, in: app)
        client.tap()
        tap(app.buttons["Modifica"], in: app)
        reveal(app.textViews["client.anamnesis"], in: app)
        XCTAssertEqual(app.textViews["client.anamnesis"].value as? String, "Anamnesi inventata per collaudo")
        reveal(app.textViews["client.physicalAnalysis"], in: app)
        XCTAssertEqual(app.textViews["client.physicalAnalysis"].value as? String, "Analisi inventata per collaudo")
        app.buttons["Annulla"].tap()

        app.tabBars.buttons["Impostazioni"].tap()
        app.buttons["Servizi e listino"].tap()
        tap(app.buttons["services.new"], in: app)
        replace(app.textFields["service.name"], with: "Allenamento tariffe")
        replace(app.textFields["service.price"], with: "50")
        tap(app.buttons["service.addRate"], in: app)
        replace(app.textFields["service.rateName.1"], with: "Ridotta")
        replace(app.textFields["service.ratePrice.1"], with: "35")
        app.buttons["service.save"].tap()
        XCTAssertTrue(app.buttons["services.new"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Agenda"].tap()
        XCTAssertTrue(app.scrollViews["agenda.weekColumns"].waitForExistence(timeout: 5))
        let monday = app.otherElements["agenda.weekColumn.2"].firstMatch
        let tuesday = app.otherElements["agenda.weekColumn.3"].firstMatch
        XCTAssertTrue(monday.exists)
        XCTAssertTrue(tuesday.exists)
        XCTAssertLessThan(monday.frame.minX, tuesday.frame.minX)
        XCTAssertEqual(monday.frame.minY, tuesday.frame.minY, accuracy: 2)
        let weekScreenshot = XCTAttachment(screenshot: app.screenshot())
        weekScreenshot.name = "Agenda settimanale in colonne"
        weekScreenshot.lifetime = .keepAlways
        add(weekScreenshot)

        app.buttons["agenda.add"].tap()
        choose("session.client1", label: "Cliente Nuove funzioni", in: app)
        XCTAssertTrue(app.buttons["session.service"].label.contains("Allenamento tariffe"))
        let tomorrow = try nextWeekday()
        let dayLabel = italianDayLabel(tomorrow)
        tap(app.buttons[dayLabel].firstMatch, in: app)
        tap(app.buttons["session.quickHour.10:00"], in: app)
        let quickButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session.quickHour."))
        XCTAssertGreaterThan(quickButtons.count, 0)
        XCTAssertTrue(quickButtons.allElementsBoundByIndex.allSatisfy { $0.label.hasSuffix(":00") })
        XCTAssertEqual(Set(quickButtons.allElementsBoundByIndex.map(\.label)),
                       Set(["07:00", "08:00", "09:00", "10:00", "13:00", "14:00", "15:00", "16:00", "17:00", "18:00", "19:00", "20:00"]))
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session.quickDay."))
        XCTAssertFalse(days.allElementsBoundByIndex.contains { $0.label.hasPrefix("Sabato") || $0.label.hasPrefix("Domenica") })
        let packageChoice = app.buttons["session.package1"]
        reveal(packageChoice, in: app)
        XCTAssertTrue(packageChoice.label.contains("Pacchetto in uso"))
        XCTAssertTrue(packageChoice.label.contains("No"))
        choosePrefix("session.tariff1", prefix: "Ridotta ·", in: app)
        XCTAssertEqual(app.textFields["session.price1"].value as? String, "35,00")
        XCTAssertFalse(app.textFields["session.location"].exists)
        app.buttons["session.save"].tap()
        XCTAssertTrue(app.buttons["agenda.add"].waitForExistence(timeout: 5))

        app.buttons["agenda.add"].tap()
        choose("session.client1", label: "Cliente Nuove funzioni", in: app)
        reveal(app.textFields["session.price1"], in: app)
        XCTAssertEqual(app.textFields["session.price1"].value as? String, "35,00")
        for _ in 0..<5 where !app.buttons["session.duration-Increment"].exists { app.swipeDown() }
        reveal(app.buttons["session.duration-Increment"], in: app)
        for _ in 0..<6 { app.buttons["session.duration-Increment"].tap() }
        tap(app.buttons[dayLabel].firstMatch, in: app)
        reveal(app.buttons["session.quickHour.13:00"], in: app)
        XCTAssertFalse(app.buttons["session.quickHour.09:00"].exists)
        XCTAssertFalse(app.buttons["session.quickHour.10:00"].exists)
        XCTAssertFalse(app.buttons["session.quickHour.11:00"].exists)
        XCTAssertFalse(app.buttons["session.quickHour.12:00"].exists)
        XCTAssertTrue(app.buttons["session.quickHour.13:00"].exists)
        let slotsScreenshot = XCTAttachment(screenshot: app.screenshot())
        slotsScreenshot.name = "Orari rapidi liberi a minuti 00"
        slotsScreenshot.lifetime = .keepAlways
        add(slotsScreenshot)
        app.buttons["Annulla"].tap()
    }

    @MainActor
    private func assertIncomeCards(_ amount: String, in app: XCUIApplication) {
        app.tabBars.buttons["Panoramica"].tap()
        let annual = app.descendants(matching: .any).matching(identifier: "overview.income.year").firstMatch
        for _ in 0..<8 where !annual.exists || annual.frame.minY < 80 { app.swipeDown() }
        for period in ["year", "month", "week"] {
            let card = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@", "overview.income.\(period)", amount
            )).firstMatch
            reveal(card, in: app)
            XCTAssertTrue(card.exists)
        }
    }

    @MainActor
    private func completeFirstSession(clientName: String, serviceName: String, in app: XCUIApplication) {
        app.tabBars.buttons["Clienti"].tap()
        if app.navigationBars.buttons["Clienti"].exists { app.navigationBars.buttons["Clienti"].tap() }
        let person = app.staticTexts[clientName].firstMatch
        reveal(person, in: app)
        person.tap()
        tap(app.buttons["Storico appuntamenti"], in: app)
        tap(app.staticTexts[serviceName].firstMatch, in: app)
        tap(app.buttons["session.complete"], in: app)
        app.buttons["session.confirmStatus"].firstMatch.tap()
        for _ in 0..<5 where !app.staticTexts["Completata"].firstMatch.exists { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Completata"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
    }

    private func nextWeekday() throws -> Date {
        var next = Date()
        repeat {
            next = try XCTUnwrap(italianCalendar.date(byAdding: .day, value: 1, to: next))
        } while italianCalendar.isDateInWeekend(next)
        return next
    }

    @MainActor
    func testClientPreferredServiceAndRateOverrideLastAppointment() throws {
        let app = testApplication()
        app.launchArguments = ["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        app.tabBars.buttons["Impostazioni"].tap()
        app.buttons["Servizi e listino"].tap()
        for (name, price) in [("Alternativo", "70"), ("Preferito", "50")] {
            tap(app.buttons["services.new"], in: app)
            replace(app.textFields["service.name"], with: name)
            replace(app.textFields["service.price"], with: price)
            if name == "Preferito" {
                tap(app.buttons["service.addRate"], in: app)
                replace(app.textFields["service.rateName.1"], with: "Ridotta")
                replace(app.textFields["service.ratePrice.1"], with: "35")
            }
            app.buttons["service.save"].tap()
            XCTAssertTrue(app.buttons["services.new"].waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["Clienti"].tap()
        tap(app.buttons["Nuovo cliente"].firstMatch, in: app)
        replace(app.textFields["client.firstName"], with: "Cliente")
        replace(app.textFields["client.lastName"], with: "Preferenze")
        choose("client.preferredService", label: "Preferito", in: app)
        choosePrefix("client.preferredRate", prefix: "Ridotta ·", in: app)
        app.buttons["client.save"].tap()
        app.terminate()
        app.launch()

        app.tabBars.buttons["Agenda"].tap()
        app.buttons["agenda.add"].tap()
        choose("session.client1", label: "Cliente Preferenze", in: app)
        XCTAssertTrue(app.buttons["session.service"].label.contains("Preferito"))
        reveal(app.buttons["session.tariff1"], in: app)
        XCTAssertTrue(app.buttons["session.tariff1"].label.contains("Ridotta"))
        reveal(app.textFields["session.price1"], in: app)
        XCTAssertEqual(app.textFields["session.price1"].value as? String, "35,00")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Servizio e tariffa preferiti preselezionati"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for _ in 0..<5 where !app.buttons["session.service"].exists { app.swipeDown() }
        choosePrefix("session.service", prefix: "Alternativo ·", in: app)
        app.buttons["session.save"].tap()
        XCTAssertTrue(app.buttons["agenda.add"].waitForExistence(timeout: 5))

        app.buttons["agenda.add"].tap()
        choose("session.client1", label: "Cliente Preferenze", in: app)
        XCTAssertTrue(app.buttons["session.service"].label.contains("Preferito"))
        reveal(app.buttons["session.tariff1"], in: app)
        XCTAssertTrue(app.buttons["session.tariff1"].label.contains("Ridotta"))
        app.buttons["Annulla"].tap()

        app.tabBars.buttons["Clienti"].tap()
        tap(app.staticTexts["Cliente Preferenze"].firstMatch, in: app)
        app.buttons["Modifica"].tap()
        choose("client.preferredService", label: "Nessuno · usa le ultime scelte", in: app)
        XCTAssertFalse(app.buttons["client.preferredRate"].exists)
        app.buttons["client.save"].tap()
        XCTAssertTrue(app.buttons["Modifica"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Agenda"].tap()
        app.buttons["agenda.add"].tap()
        choose("session.client1", label: "Cliente Preferenze", in: app)
        XCTAssertTrue(app.buttons["session.service"].label.contains("Alternativo"))
        reveal(app.textFields["session.price1"], in: app)
        XCTAssertEqual(app.textFields["session.price1"].value as? String, "70,00")
        app.buttons["Annulla"].tap()
    }

    private var italianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "it_IT")
        calendar.firstWeekday = 2
        return calendar
    }

    private func italianDayLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEEE d"
        let text = formatter.string(from: day)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    @MainActor
    private func choosePrefix(_ identifier: String, prefix: String, in app: XCUIApplication) {
        tap(app.buttons[identifier], in: app)
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }

    @MainActor
    private func testApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PAOLA_UI_TEST_NAMESPACE"] = UUID().uuidString
        return app
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let value = field.value as? String ?? ""
        if !value.isEmpty && value != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 55 { break }
            if element.exists && element.frame.maxY < 100 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func choose(_ identifier: String, label: String, in app: XCUIApplication) {
        tap(app.buttons[identifier], in: app)
        let option = app.buttons[label].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }
}
