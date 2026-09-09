import LocalAuthentication
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
struct AppLockView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("privacy.appLockEnabled") private var isEnabled = false
    @State private var isUnlocked = false
    @State private var authenticationID: UUID?
    @State private var authenticationContext: LAContext?
    @State private var authenticationTask: Task<Void, Never>?
    @State private var errorMessage: String?
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var isProtected: Bool {
        isEnabled && (!isUnlocked || scenePhase == .background)
    }

    var body: some View {
        ZStack {
            PrivacyContentHost(content: content, hidden: isProtected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isProtected {
                privacyCover.transition(.identity).zIndex(1)
            }
        }
        .transaction(value: isProtected) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: break
            case .inactive:
                #if os(macOS)
                if !NSApplication.shared.isActive && authenticationID == nil { isUnlocked = false }
                #else
                if authenticationID == nil { isUnlocked = false }
                #endif
            case .background: lockAndCancelAuthentication()
            @unknown default: lockAndCancelAuthentication()
            }
        }
        .onChange(of: isEnabled) { _, _ in lockAndCancelAuthentication() }
        .onDisappear(perform: lockAndCancelAuthentication)
    }

    private var privacyCover: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44)).foregroundStyle(.teal).accessibilityHidden(true)
            Text("Paola Gestionale").font(.title2.bold())
            Text("I tuoi dati sono protetti.").foregroundStyle(.secondary)
            if scenePhase == .active {
                if authenticationID != nil { ProgressView("Autenticazione in corso...") }
                if let errorMessage {
                    Text(errorMessage).font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                Button("Sblocca", action: authenticate)
                    .buttonStyle(.borderedProminent).disabled(authenticationID != nil)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Rectangle().fill(.background).ignoresSafeArea() }
        .accessibilityElement(children: .contain)
    }

    private func authenticate() {
        guard isEnabled, scenePhase == .active, authenticationID == nil else { return }
        let context = LAContext()
        context.localizedCancelTitle = "Annulla"
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            errorMessage = authenticationMessage(for: availabilityError)
            return
        }
        let attemptID = UUID()
        authenticationID = attemptID
        authenticationContext = context
        errorMessage = nil
        authenticationTask = Task { @MainActor in
            do {
                let accepted = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Sblocca Paola Gestionale per accedere ai tuoi dati."
                )
                guard authenticationID == attemptID, isEnabled, scenePhase != .background else { return }
                isUnlocked = accepted
                if !accepted { errorMessage = "Autenticazione non riuscita. Riprova." }
            } catch {
                guard authenticationID == attemptID else { return }
                isUnlocked = false
                errorMessage = authenticationMessage(for: error)
            }
            guard authenticationID == attemptID else { return }
            authenticationID = nil
            authenticationContext = nil
            authenticationTask = nil
        }
    }

    private func lockAndCancelAuthentication() {
        isUnlocked = false
        authenticationID = nil
        authenticationContext?.invalidate()
        authenticationContext = nil
        authenticationTask?.cancel()
        authenticationTask = nil
        errorMessage = nil
    }

    private func authenticationMessage(for error: Error?) -> String {
        guard let error = error as? LAError else {
            return "Autenticazione non disponibile. Verifica le impostazioni del dispositivo e riprova."
        }
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return "Autenticazione annullata. Premi Sblocca per riprovare."
        case .passcodeNotSet:
            return "Configura un codice o una password nelle impostazioni del dispositivo, poi riprova."
        case .biometryNotAvailable, .biometryNotEnrolled:
            return "Configura l'autenticazione nelle impostazioni del dispositivo, poi riprova."
        case .biometryLockout:
            return "Autenticazione biometrica bloccata. Riprova con la credenziale del dispositivo."
        case .notInteractive:
            return "Mantieni l'app attiva e riprova."
        default:
            return "Autenticazione non riuscita. Premi Sblocca per riprovare."
        }
    }
}

#if os(iOS)
private struct PrivacyContentHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let hidden: Bool

    final class Coordinator {
        var coveredViews: [(view: UIView, hidden: Bool, accessibilityHidden: Bool)] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        UIHostingController(rootView: AnyView(
            content.disabled(hidden).accessibilityHidden(hidden).environment(\.self, context.environment)
        ))
    }

    func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        controller.rootView = AnyView(
            content.disabled(hidden).accessibilityHidden(hidden).environment(\.self, context.environment)
        )
        // Native navigation and sheet controls must be hidden too, without discarding draft state.
        controller.view.isHidden = hidden
        controller.view.accessibilityElementsHidden = hidden
        if hidden {
            coverPresentedControllers(controller, coordinator: context.coordinator)
        } else {
            for item in context.coordinator.coveredViews {
                item.view.isHidden = item.hidden
                item.view.accessibilityElementsHidden = item.accessibilityHidden
            }
            context.coordinator.coveredViews.removeAll()
        }
    }

    private func coverPresentedControllers(_ controller: UIViewController, coordinator: Coordinator) {
        if let presented = controller.presentedViewController {
            if let view = presented.view {
                if !coordinator.coveredViews.contains(where: { $0.view === view }) {
                    coordinator.coveredViews.append((view, view.isHidden, view.accessibilityElementsHidden))
                }
                view.isHidden = true
                view.accessibilityElementsHidden = true
            }
            coverPresentedControllers(presented, coordinator: coordinator)
        }
        for child in controller.children { coverPresentedControllers(child, coordinator: coordinator) }
    }
}
#else
private struct PrivacyContentHost<Content: View>: NSViewRepresentable {
    let content: Content
    let hidden: Bool

    final class Coordinator {
        var coveredSheets: [NSWindow] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        NSHostingView(rootView: AnyView(
            content.disabled(hidden).accessibilityHidden(hidden).environment(\.self, context.environment)
        ))
    }

    func updateNSView(_ view: NSHostingView<AnyView>, context: Context) {
        view.rootView = AnyView(
            content.disabled(hidden).accessibilityHidden(hidden).environment(\.self, context.environment)
        )
        view.isHidden = hidden
        view.setAccessibilityHidden(hidden)
        if hidden {
            for sheet in view.window?.sheets ?? [] where sheet.isVisible {
                if !context.coordinator.coveredSheets.contains(where: { $0 === sheet }) {
                    context.coordinator.coveredSheets.append(sheet)
                }
                sheet.orderOut(nil)
            }
        } else {
            for sheet in context.coordinator.coveredSheets where sheet.sheetParent != nil { sheet.orderFront(nil) }
            context.coordinator.coveredSheets.removeAll()
        }
    }
}
#endif
