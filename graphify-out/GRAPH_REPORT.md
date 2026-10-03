# Graph Report - paola_gestionale  (2026-10-03)

## Corpus Check
- 153 files · ~109,211 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 14 file(s) not represented in the graph (top: .xcscheme 5, .entitlements 3, (none) 1)

## Summary
- 2471 nodes · 6705 edges · 133 communities (108 shown, 25 thin omitted)
- Extraction: 87% EXTRACTED · 13% INFERRED · 0% AMBIGUOUS · INFERRED: 900 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Backup & Export
- App Infrastructure
- UI State & Views
- Accounting Logic
- Data Models & Drafts
- Persistence Layer
- Business Rules
- Session Management
- Calendar & Scheduling
- Client Management
- Package & Services
- Payment Processing
- Report Generation
- Invoice & Fiscal
- UI Components
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87
- Community 88
- Community 89
- Community 90
- Community 91
- Community 92
- Community 93
- Community 94
- Community 95
- Community 96
- Community 97
- Community 98
- Community 99
- Community 100
- Community 101
- Community 102
- Community 103
- Community 104
- Community 105
- Community 106
- Community 107
- Community 108
- Community 109
- Community 110
- Community 111
- Community 113
- Community 114
- Community 115
- Community 116
- Community 117
- Community 118
- Community 119
- Community 120
- Community 121
- Community 122
- Community 123
- Community 126
- Community 128
- Community 129
- Community 130
- Community 131
- Community 132

## God Nodes (most connected - your core abstractions)
1. `BusinessRepository` - 125 edges
2. `PaolaCore` - 78 edges
3. `SwiftData` - 70 edges
4. `OverviewView` - 55 edges
5. `LedgerEntry` - 55 edges
6. `PaymentMethod` - 54 edges
7. `AgendaContent` - 50 edges
8. `SessionEditor` - 49 edges
9. `ClientRepository` - 49 edges
10. `TrainingService` - 48 edges

## Surprising Connections (you probably didn't know these)
- `.existingInvoice` --references--> `Invoice`  [INFERRED]
  Sources/PaolaApp/BusinessViews/AgendaViews.swift → Sources/PaolaCore/Invoice.swift
- `.unpaidTotalCents` --references--> `UnpaidSession`  [INFERRED]
  Sources/PaolaApp/BusinessViews/BusinessSummaryViews.swift → Sources/PaolaCore/BusinessReports.swift
- `.packageUses` --references--> `PackageUse`  [INFERRED]
  Sources/PaolaApp/BusinessViews/PackagesViews.swift → Sources/PaolaCore/BusinessModels.swift
- `.existingInvoice` --references--> `Invoice`  [INFERRED]
  Sources/PaolaApp/BusinessViews/PackagesViews.swift → Sources/PaolaCore/Invoice.swift
- `.corrections` --references--> `LedgerEntry`  [INFERRED]
  Sources/PaolaApp/BusinessViews/PaymentsViews.swift → Sources/PaolaCore/BusinessModels.swift

## Import Cycles
- None detected.

## Communities (133 total, 25 thin omitted)

### Community 0 - "Backup & Export"
Cohesion: 0.05
Nodes (26): BackupDocument, .readableContentTypes, BackupView, .body, InternalBackup, .id, .isAutomatic, .label (+18 more)

### Community 1 - "App Infrastructure"
Cohesion: 0.07
Nodes (4): Foundation, ServiceTariffs, SwiftData, XCTest

### Community 2 - "UI State & Views"
Cohesion: 0.09
Nodes (14): UpcomingDay, .id, ConvCell, HoverTooltip, NetCell, OverviewView, .body, .conversionHeaderRow (+6 more)

### Community 3 - "Accounting Logic"
Cohesion: 0.09
Nodes (18): AccountingTotals, .total, AgendaContent, .body, .snapshotKey, .component, AgendaSnapshot, ClientSessionsView (+10 more)

### Community 4 - "Data Models & Drafts"
Cohesion: 0.13
Nodes (8): clients, BlockDraft, ParticipantDraft, PaymentDraft, SessionDraft, AutomaticIncomeTests, BusinessRepositoryTests, MultipleParticipantsTests

### Community 5 - "Persistence Layer"
Cohesion: 0.08
Nodes (10): AppointmentQuickChoices, .body, SchedulingError, .errorDescription, invalidDate, invalidDuration, SchedulingSuggestions, .calendar (+2 more)

### Community 6 - "Business Rules"
Cohesion: 0.10
Nodes (27): ExpenseDraft, .method, LessonPackage, .kind, .paymentMethod, PackageDraft, PackageKind, .id (+19 more)

### Community 7 - "Session Management"
Cohesion: 0.07
Nodes (16): CourseEditor, .body, .eligibleClients, .isEditing, .orderedWeekdays, CourseDetailView, .body, .people (+8 more)

### Community 8 - "Calendar & Scheduling"
Cohesion: 0.10
Nodes (11): FatturaPAError, .errorDescription, incompleteBuyer, incompleteSeller, FatturaPAInput, FatturaPAParty, FatturaPAXMLBuilder, ForfettarioBreakdown (+3 more)

### Community 9 - "Client Management"
Cohesion: 0.15
Nodes (5): CourseDraft, BusinessRepository, Validation, archive, local

### Community 10 - "Package & Services"
Cohesion: 0.06
Nodes (36): .inactiveEntries, Field, activityStatus, anxietyPanic, boneJointIssues, cardioRespiratoryIssues, chronicConditions, circumferences (+28 more)

### Community 11 - "Payment Processing"
Cohesion: 0.11
Nodes (10): ArubaAPI, serviceError, ArubaEnvironment, .authBaseURL, demo, production, .wsBaseURL, AuthTokens (+2 more)

### Community 12 - "Report Generation"
Cohesion: 0.07
Nodes (18): BusinessError, alreadyInvoiced, amountExceeded, arithmeticOverflow, completedSessionLocked, .errorDescription, inconsistentData, invalidInput (+10 more)

### Community 13 - "Invoice & Fiscal"
Cohesion: 0.09
Nodes (6): AppLockView, .body, .isProtected, .privacyCover, Coordinator, PrivacyContentHost

### Community 14 - "UI Components"
Cohesion: 0.11
Nodes (8): CloudKit, CoreData, CoreGraphics, CoreText, PaolaCore, SwiftUI, UniformTypeIdentifiers, UserNotifications

### Community 15 - "Community 15"
Cohesion: 0.10
Nodes (20): BalanceLabel, ClientAllocationsView, .allocations, .body, .statement, LedgerCorrectionEditor, .isRefund, LedgerEntryDetailView (+12 more)

### Community 16 - "Community 16"
Cohesion: 0.19
Nodes (3): ClientDraft, ClientRepository, ClientRepositoryTests

### Community 17 - "Community 17"
Cohesion: 0.13
Nodes (11): AdditionalParticipantDraft, SessionEditor, .billingSection, .body, .cannotSave, .editorForm, .originalParticipants, .readError (+3 more)

### Community 18 - "Community 18"
Cohesion: 0.18
Nodes (4): ServiceDraft, ServiceRateDraft, AppointmentPreferencesTests, ServiceTariffsTests

### Community 19 - "Community 19"
Cohesion: 0.09
Nodes (10): CalendarAppointments, OverviewSummary, UpcomingItem, course, .end, .id, session, .start (+2 more)

### Community 20 - "Community 20"
Cohesion: 0.06
Nodes (31): CodingKeys, blocks, clientID, clientName, courseParticipants, courses, createdAt, durationMinutes (+23 more)

### Community 21 - "Community 21"
Cohesion: 0.07
Nodes (14): PaolaSchemaMigrationPlan, .schemas, PaolaSchemaV1, .models, .versionIdentifier, PaolaSchemaV14, .models, .versionIdentifier (+6 more)

### Community 22 - "Community 22"
Cohesion: 0.32
Nodes (15): BlockRecord, BusinessArchive, .recordCount, CourseParticipantRecord, CourseRecord, ExpenseRecord, InvoiceRecord, LedgerRecord (+7 more)

### Community 23 - "Community 23"
Cohesion: 0.12
Nodes (4): AppVersion, .description, ChecksumManifest, AppUpdateTests

### Community 24 - "Community 24"
Cohesion: 0.14
Nodes (4): AppointmentSelection, ClientAppointmentPreference, AppointmentSelectionTests, .calendar

### Community 25 - "Community 25"
Cohesion: 0.16
Nodes (4): .unpaid, LedgerEntry, BusinessReports, BusinessReportsTests

### Community 26 - "Community 26"
Cohesion: 0.13
Nodes (6): ArchiveSnapshotTests, ClientSaveFailureTests, SchemaUpgradeTests, SchemaV5UpgradeTests, StoreFactoryTests, withStoreFixture()

### Community 28 - "Community 28"
Cohesion: 0.14
Nodes (14): InvoicePhaseRow, .body, InvoiceStatusRow, .body, .body, InvoiceSender, .isBusy, Phase (+6 more)

### Community 29 - "Community 29"
Cohesion: 0.14
Nodes (8): ArubaCredentials, .isComplete, ArubaCredentialsStore, BackupPasswordStore, .isConfigured, InMemorySecretStore, SecretKey, SecretStore

### Community 30 - "Community 30"
Cohesion: 0.11
Nodes (9): AgendaCreationSlot, .id, AgendaDragPayload, AgendaHourRow, .hourLabel, .id, .isEmpty, AgendaScheduling (+1 more)

### Community 31 - "Community 31"
Cohesion: 0.12
Nodes (8): AutoBackupService, ApplicationRoot, .body, BackupPasswordPrompt, .body, PaolaApp, .body, .content

### Community 32 - "Community 32"
Cohesion: 0.12
Nodes (5): ArchiveSnapshot, .recordCount, ClientRecord, ArchiveV3Tests, InvoiceArchiveTests

### Community 33 - "Community 33"
Cohesion: 0.11
Nodes (13): day, .body, SessionDetailView, .body, .confirmationTitle, .conflicts, .detail, .invoiceableParticipants (+5 more)

### Community 34 - "Community 34"
Cohesion: 0.18
Nodes (11): .activitySection, .totalCents, BusinessStatistics, ClientRanking, .id, ClientTotals, PaymentAllocation, UnpaidClientSummary (+3 more)

### Community 35 - "Community 35"
Cohesion: 0.12
Nodes (12): .oneTime, .recurring, .feeSessionID, .isAutomaticFee, .kind, ExpenseKind, .id, monthlyRecurring (+4 more)

### Community 36 - "Community 36"
Cohesion: 0.13
Nodes (12): TaxBreakdown, .imponibileCents, .inpsFormula, .inpsSteps, .netFormula, .netSteps, .taxFormula, .taxSteps (+4 more)

### Community 37 - "Community 37"
Cohesion: 0.16
Nodes (7): CredentialsView, .body, SellerFiscalProfile, .isComplete, .validationIssues, SellerProfileStore, CredentialsTests

### Community 38 - "Community 38"
Cohesion: 0.23
Nodes (3): BusinessTestStore, .schema, SessionProvisionalRescheduleTests

### Community 39 - "Community 39"
Cohesion: 0.27
Nodes (6): .conversionInputRow, .conversionsCard, ConversionRates, .cardFormula, .stripeFormula, .whiteFormula

### Community 40 - "Community 40"
Cohesion: 0.19
Nodes (9): GitHubReleaseParser, GitHubRepository, .latestReleaseURL, InstallerKind, diskImage, zipArchive, ReleaseAsset, ReleaseInfo (+1 more)

### Community 41 - "Community 41"
Cohesion: 0.16
Nodes (6): ExpenseEditor, .body, ExpenseEditTarget, ExpensesView, .body, .content

### Community 42 - "Community 42"
Cohesion: 0.21
Nodes (5): IntegrityStatusView, .body, .warnings, PackageUse, BusinessIntegrityTests

### Community 43 - "Community 43"
Cohesion: 0.14
Nodes (17): AppNavigation, .navigation, AppSection, agenda, courses, expenses, .id, overview (+9 more)

### Community 44 - "Community 44"
Cohesion: 0.21
Nodes (4): AppUpdater, .currentVersionText, .isBusy, .isLocalBuild

### Community 45 - "Community 45"
Cohesion: 0.12
Nodes (9): ReportsView, .balanceSection, .filteredSessions, .readError, .reportWarnings, .start, .statement, .statistics (+1 more)

### Community 46 - "Community 46"
Cohesion: 0.15
Nodes (8): ClientDetailView, .anagraficaQuadrant, .archiveSection, .body, .informazioniQuadrant, .quickActionButtons, .quickActions, .saldiQuadrant

### Community 47 - "Community 47"
Cohesion: 0.14
Nodes (10): ClientValidationError, .errorDescription, invalidDate, invalidEmail, invalidPreference, missingName, possibleDuplicate, staleRecord (+2 more)

### Community 48 - "Community 48"
Cohesion: 0.20
Nodes (5): AnamnesisEditor, .body, .existsInHistory, .legacyNote, values

### Community 49 - "Community 49"
Cohesion: 0.16
Nodes (5): .annualCents, .annualPersonalCents, .monthlyCents, .monthlyPersonalCents, ExpenseReports

### Community 50 - "Community 50"
Cohesion: 0.15
Nodes (12): Invoice, .paymentMethod, .status, InvoiceStatus, delivered, draft, failed, .id (+4 more)

### Community 51 - "Community 51"
Cohesion: 0.22
Nodes (8): Client, .fullName, LessonPackage, PaolaSchemaV7, .models, .versionIdentifier, TrainingSession, .status

### Community 52 - "Community 52"
Cohesion: 0.21
Nodes (8): .payload, AnamnesisAttachment, CodingKeys, attachments, date, id, title, Payload

### Community 53 - "Community 53"
Cohesion: 0.11
Nodes (17): AppRoute, backup, client, clientAllocations, clientPackages, clientPayments, clientReports, clientSessions (+9 more)

### Community 54 - "Community 54"
Cohesion: 0.16
Nodes (7): AdditionalParticipantEditor, .body, SessionPackageChoices, MoneyField, .body, .body, .availablePackages

### Community 55 - "Community 55"
Cohesion: 0.11
Nodes (18): CodingKeys, anamnesis, billingAddress, birthDate, createdAt, email, firstName, id (+10 more)

### Community 56 - "Community 56"
Cohesion: 0.23
Nodes (7): Client, .fullName, LessonPackage, PaolaSchemaV5, .models, .versionIdentifier, SessionParticipant

### Community 57 - "Community 57"
Cohesion: 0.15
Nodes (12): .filters, SessionStatus, cancelled, completed, .id, noShow, planned, provisional (+4 more)

### Community 58 - "Community 58"
Cohesion: 0.17
Nodes (10): ServicesView, .visibleServices, .selectableServices, .tariffOptions, ClientEditor, .availableRates, .body, .preferenceSection (+2 more)

### Community 59 - "Community 59"
Cohesion: 0.25
Nodes (7): .anamnesiQuadrant, Anamnesis, .isEmpty, AnamnesisHistory, .current, .isEmpty, AnamnesisTests

### Community 60 - "Community 60"
Cohesion: 0.18
Nodes (3): ClientDraftTests, ClientSensitiveFieldsTests, makeDraft()

### Community 61 - "Community 61"
Cohesion: 0.17
Nodes (7): ClientFilter, all, archived, .id, .title, ClientSearch, ClientSearchTests

### Community 62 - "Community 62"
Cohesion: 0.20
Nodes (4): BusinessExport, BusinessReportSnapshot, Movement, Unpaid

### Community 63 - "Community 63"
Cohesion: 0.18
Nodes (3): CloudNamespace, StoreFactory, CloudNamespaceTests

### Community 64 - "Community 64"
Cohesion: 0.24
Nodes (6): LessonPackage, PaolaSchemaV9, .models, .versionIdentifier, TrainingSession, .status

### Community 65 - "Community 65"
Cohesion: 0.16
Nodes (8): IncomeSummary, .annualEbitCents, .annualPersonalBalanceCents, .monthlyEbitCents, .monthlyPersonalBalanceCents, .weeklyEbitCents, IncomeSummaryTests, .calendar

### Community 67 - "Community 67"
Cohesion: 0.27
Nodes (5): Client, LessonPackage, PaolaSchemaV12, .models, .versionIdentifier

### Community 68 - "Community 68"
Cohesion: 0.23
Nodes (5): PaolaSchemaV15, .models, .versionIdentifier, SessionParticipant, TrainingSession

### Community 69 - "Community 69"
Cohesion: 0.14
Nodes (7): AppKit, Combine, CommonCrypto, CryptoKit, LocalAuthentication, Security, UIKit

### Community 70 - "Community 70"
Cohesion: 0.16
Nodes (4): BusinessExportDocument, .readableContentTypes, BusinessInputError, .errorDescription

### Community 71 - "Community 71"
Cohesion: 0.23
Nodes (3): CourseOccurrence, .id, CourseOccurrences

### Community 72 - "Community 72"
Cohesion: 0.18
Nodes (7): .days, .availableLessons, BusinessDates, .monthStart, .visiblePackages, .end, .conflicts

### Community 73 - "Community 73"
Cohesion: 0.22
Nodes (4): InvoiceFiscalReadiness, .fiscalIssues, .fiscalIssues, KeychainSecretStore

### Community 74 - "Community 74"
Cohesion: 0.21
Nodes (7): PackageEditor, .isEditing, .usedLessons, PackageSummaryRow, .body, PackagesView, .body

### Community 76 - "Community 76"
Cohesion: 0.26
Nodes (6): .plainText, BusinessFormatting, .body, .body, .scheduleSection, .body

### Community 79 - "Community 79"
Cohesion: 0.20
Nodes (5): ClientBusinessSection, .body, .clientPackages, .unpaidSessions, .unpaidTotalCents

### Community 81 - "Community 81"
Cohesion: 0.23
Nodes (5): Client, .fullName, PaolaSchemaV3, .models, .versionIdentifier

### Community 82 - "Community 82"
Cohesion: 0.20
Nodes (7): .body, ReminderError, denied, .errorDescription, ReminderSchedulerView, .body, .signature

### Community 83 - "Community 83"
Cohesion: 0.18
Nodes (5): .body, UpdateCheck, .release, updateAvailable, upToDate

### Community 84 - "Community 84"
Cohesion: 0.20
Nodes (6): AgendaPeriod, .id, month, week, AgendaView, .body

### Community 85 - "Community 85"
Cohesion: 0.24
Nodes (4): EditableServiceRate, ServiceEditor, .body, .body

### Community 89 - "Community 89"
Cohesion: 0.20
Nodes (6): AnamnesisAttachmentError, .errorDescription, fileTooLarge, ClientPersistenceError, .errorDescription, refreshAfterSaveFailed

### Community 90 - "Community 90"
Cohesion: 0.22
Nodes (6): PackageInvoiceSection, .alreadySent, .breakdown, .existingInvoice, .lineDescription, .sourceKey

### Community 91 - "Community 91"
Cohesion: 0.20
Nodes (5): .header, ClientAvatar, .body, .initials, FormError

### Community 92 - "Community 92"
Cohesion: 0.22
Nodes (5): ClientsView, .body, .clientList, .filteredClients, .unpaidByClient

### Community 93 - "Community 93"
Cohesion: 0.22
Nodes (6): ReminderManager, SettingsView, .appVersion, .body, LocalStorageNotice, .body

### Community 95 - "Community 95"
Cohesion: 0.33
Nodes (4): AppRouteView, .body, ResolvedModelView, View

### Community 97 - "Community 97"
Cohesion: 0.22
Nodes (8): Phase, checking, downloading, failed, idle, localBuild, ready, upToDate

### Community 98 - "Community 98"
Cohesion: 0.25
Nodes (6): BusinessClientPicker, .body, BusinessPeriodPicker, .body, View, .filterSection

### Community 100 - "Community 100"
Cohesion: 0.22
Nodes (9): .kind, LedgerKind, charge, credit, .id, payment, refund, .title (+1 more)

### Community 101 - "Community 101"
Cohesion: 0.29
Nodes (4): AppUpdatePromptModifier, AppUpdateSection, .statusView, View

### Community 102 - "Community 102"
Cohesion: 0.36
Nodes (3): CalendarSessionRow, .body, .people

### Community 103 - "Community 103"
Cohesion: 0.25
Nodes (7): ArubaAPIError, decodeFailed, .errorDescription, httpError, invalidResponse, missingCredentials, notAuthenticated

### Community 104 - "Community 104"
Cohesion: 0.39
Nodes (3): Client, .fullName, .stages

### Community 107 - "Community 107"
Cohesion: 0.29
Nodes (4): SessionSummaryRow, PackageDetailView, .body, .packageUses

### Community 108 - "Community 108"
Cohesion: 0.38
Nodes (4): ReportPreviewView, .body, .body, .reportList

### Community 109 - "Community 109"
Cohesion: 0.29
Nodes (6): StorageError, .errorDescription, invalidCloudConfiguration, resetWithoutArchive, restoreWhileCloudEnabled, unavailableAccount

### Community 110 - "Community 110"
Cohesion: 0.29
Nodes (7): UpdateError, checksumMismatch, checksumMissing, .errorDescription, invalidResponse, noCompatibleAsset, unreadableVersion

### Community 113 - "Community 113"
Cohesion: 0.33
Nodes (5): SessionStatusLabel, .body, .color, .icon, .body

### Community 114 - "Community 114"
Cohesion: 0.33
Nodes (5): CredentialsTestState, failure, idle, success, testing

### Community 115 - "Community 115"
Cohesion: 0.33
Nodes (6): Kind, boolean, date, integer, longText, shortText

### Community 116 - "Community 116"
Cohesion: 0.33
Nodes (5): ArchiveError, .errorDescription, existingStore, invalidArchive, verificationFailed

### Community 117 - "Community 117"
Cohesion: 0.33
Nodes (3): PaolaSchemaV10, .models, .versionIdentifier

### Community 118 - "Community 118"
Cohesion: 0.33
Nodes (3): PaolaSchemaV11, .models, .versionIdentifier

### Community 119 - "Community 119"
Cohesion: 0.33
Nodes (3): PaolaSchemaV13, .models, .versionIdentifier

### Community 120 - "Community 120"
Cohesion: 0.33
Nodes (3): PaolaSchemaV16, .models, .versionIdentifier

### Community 121 - "Community 121"
Cohesion: 0.33
Nodes (3): PaolaSchemaV4, .models, .versionIdentifier

### Community 122 - "Community 122"
Cohesion: 0.33
Nodes (3): PaolaSchemaV8, .models, .versionIdentifier

### Community 123 - "Community 123"
Cohesion: 0.40
Nodes (3): AppEnvironment, .isLocalBuild, .usesArubaDemo

## Knowledge Gaps
- **420 isolated node(s):** `PackageDescription`, `.readableContentTypes`, `fileTooLarge`, `.errorDescription`, `overview` (+415 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 755 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **25 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `App Infrastructure` to `Persistence Layer`, `Business Rules`, `Calendar & Scheduling`, `Payment Processing`, `UI Components`, `Community 21`, `Community 29`, `Community 34`, `Community 36`, `Community 37`, `Community 39`, `Community 40`, `Community 47`, `Community 49`, `Community 59`, `Community 61`, `Community 69`, `Community 71`, `Community 106`, `Community 117`, `Community 118`, `Community 119`, `Community 120`, `Community 122`, `Community 123`?**
  _High betweenness centrality (0.074) - this node is a cross-community bridge._
- **Why does `BusinessRepository` connect `Client Management` to `App Infrastructure`, `UI State & Views`, `Accounting Logic`, `Data Models & Drafts`, `Business Rules`, `Session Management`, `Report Generation`, `Community 17`, `Community 18`, `Community 26`, `Community 28`, `Community 33`, `Community 38`, `Community 41`, `Community 58`, `Community 60`, `Community 74`, `Community 75`, `Community 85`, `Community 87`, `Community 88`, `Community 94`, `Community 107`?**
  _High betweenness centrality (0.067) - this node is a cross-community bridge._
- **Why does `PaolaCore` connect `UI Components` to `App Infrastructure`, `UI State & Views`, `Community 101`, `Community 69`, `Community 71`, `Community 106`, `Community 123`, `Community 95`?**
  _High betweenness centrality (0.062) - this node is a cross-community bridge._
- **Are the 82 inferred relationships involving `BusinessRepository` (e.g. with `.completedIcon()` and `.confirmProvisional()`) actually correct?**
  _`BusinessRepository` has 82 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `.readableContentTypes`, `fileTooLarge` to the rest of the system?**
  _420 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Backup & Export` be split into smaller, more focused modules?**
  _Cohesion score 0.05006839945280438 - nodes in this community are weakly interconnected._
- **Should `App Infrastructure` be split into smaller, more focused modules?**
  _Cohesion score 0.06954997077732321 - nodes in this community are weakly interconnected._