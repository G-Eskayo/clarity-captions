import CaptionCore
import Foundation
import StoreKit
import SwiftUI
import Translation

/// Live translation (#53): the one-time purchase (StoreKit 2), on or off, the language it goes into, Apple's
/// on-device Translation (picked in #159), and the translated text for each caption line. Settings, the Into list and
/// the captions all read this one object.
@MainActor
final class TranslationCenter: ObservableObject {
    static let shared = TranslationCenter()

    @Published private(set) var purchase = TranslationPurchase()
    /// The App Store's price, as StoreKit formats it for her storefront.
    @Published private(set) var price: String?
    @Published private(set) var isOn: Bool
    @Published private(set) var target: Locale?
    /// The language pack for this pair isn't on the device yet: Apple's sheet is showing or its download is running.
    @Published private(set) var preparing = false
    /// The pair can't be translated (Cantonese, 2026-10-28), said plainly in Settings.
    @Published private(set) var unsupportedPair = false
    @Published private(set) var translations = CaptionTranslations()
    /// Handed to `.translationTask`; a new value starts a new session, nil stops it.
    @Published private(set) var configuration: TranslationSession.Configuration?

    private let store: CaptionLanguageStore
    private var product: Product?
    private var updates: Task<Void, Never>?
    private var wake: AsyncStream<Void>.Continuation?

    init(store: CaptionLanguageStore = CaptionLanguageStore()) {
        self.store = store
        isOn = store.translationOn
        target = store.translationTarget ?? CaptionLanguage.translationTarget(captions: CaptionLanguageCenter.engineLocale,
                                                                              preferred: Locale.preferredLanguages)
        #if DEBUG
        if let id = DemoMode.translate { isOn = true; target = Locale(identifier: id) }
        #endif
    }

    /// Whether captions are translated right now: bought, on, and somewhere to translate into.
    var isActive: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if usesDemoTranslator { return purchase.isOwned && isOn }
        #endif
        return purchase.isOwned && isOn && target != nil && !unsupportedPair
    }

    // MARK: purchase

    /// At launch: the product's price, what she owns, and a listener for approvals, refunds and other devices.
    func start() async {
        #if DEBUG
        if DemoMode.translate != nil || DemoMode.translationOwned { purchase.entitlementChanged(owned: true); refreshConfiguration(); return }
        #endif
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    if case .verified(let t) = result { await t.finish() }
                    await self?.refreshEntitlement()
                }
            }
        }
        product = try? await Product.products(for: [TranslationPurchase.productID]).first
        price = product?.displayPrice
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == TranslationPurchase.productID, t.revocationDate == nil { owned = true }
        }
        purchase.entitlementChanged(owned: owned)
        refreshConfiguration()
    }

    func unlock() async {
        guard purchase.unlockTapped() else { return }
        if product == nil { product = try? await Product.products(for: [TranslationPurchase.productID]).first; price = product?.displayPrice }
        guard let product else { purchase.buyFinished(.failed); return }
        do {
            switch try await product.purchase() {
            case .success(.verified(let t)):
                await t.finish()
                purchase.buyFinished(.bought)
                // Bought to use it: turn it on.
                setOn(true)
            case .success(.unverified): purchase.buyFinished(.failed)
            case .userCancelled: purchase.buyFinished(.cancelled)
            case .pending: purchase.buyFinished(.pending)
            @unknown default: purchase.buyFinished(.failed)
            }
        } catch { purchase.buyFinished(.failed) }
        refreshConfiguration()
    }

    func restore() async {
        guard purchase.restoreTapped() else { return }
        do {
            try await AppStore.sync()
        } catch { purchase.restoreFailed(); return }
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == TranslationPurchase.productID, t.revocationDate == nil { found = true }
        }
        purchase.restoreFinished(found: found)
        refreshConfiguration()
    }

    // MARK: settings

    func setOn(_ on: Bool) {
        isOn = on
        store.translationOn = on
        if !on { translations.reset() }
        refreshConfiguration()
    }

    func setTarget(_ locale: Locale) {
        target = locale
        store.translationTarget = locale
        translations.reset()
        refreshConfiguration()
    }

    /// The caption language changed (#37): translate from the new one.
    func captionLanguageChanged() {
        translations.reset()
        refreshConfiguration()
    }

    /// A new session for the current pair, or none. Also reads whether the pair needs its language pack.
    func refreshConfiguration() {
        let source = CaptionLanguageCenter.engineLocale.language
        guard purchase.isOwned, isOn, let target else { configuration = nil; preparing = false; unsupportedPair = false; return }
        let wanted = TranslationSession.Configuration(source: source, target: target.language)
        if configuration?.source != wanted.source || configuration?.target != wanted.target { configuration = wanted }
        Task {
            let status = await LanguageAvailability().status(from: source, to: target.language)
            unsupportedPair = status == .unsupported
            #if DEBUG && targetEnvironment(simulator)
            if usesDemoTranslator { unsupportedPair = false }
            #endif
            if unsupportedPair { configuration = nil }
        }
    }

    // MARK: the captions

    /// The caption lines changed: wake the session's loop. A new conversation starts clean.
    func linesChanged(_ lines: [CaptionLine]) {
        if lines.isEmpty { translations.reset() }
        latest = lines
        #if DEBUG && targetEnvironment(simulator)
        if usesDemoTranslator { demoFill(lines); return }
        #endif
        wake?.yield()
    }

    #if DEBUG && targetEnvironment(simulator)
    /// The iOS Simulator has no Translation languages (every pair reports unsupported, 2026-10-28), so a demo launch
    /// with `-ClarityDemoTranslate` fills in the demo conversation's own English lines, to show the layout. Debug
    /// simulator builds only; a device always uses Apple's Translation.
    private var usesDemoTranslator: Bool { DemoMode.translate != nil }

    private func demoFill(_ lines: [CaptionLine]) {
        guard isOn, purchase.isOwned else { return }
        for work in translations.take(from: lines) {
            translations.finished(lineID: work.lineID, source: work.text, translation: DemoMode.englishLine(for: work.text) ?? work.text)
        }
    }
    #endif

    private var latest: [CaptionLine] = []

    /// Runs inside `.translationTask`: makes sure the language pack is there (Apple's own sheet, the one system
    /// pop-up Seal allows, #159), then translates each finished line as it lands, until the session is replaced.
    func run(_ session: TranslationSession) async {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        defer { continuation.finish() }
        if let target, await LanguageAvailability().status(from: CaptionLanguageCenter.engineLocale.language, to: target.language) != .installed {
            preparing = true
            do { try await session.prepareTranslation() } catch { preparing = false; return }
            preparing = false
        }
        continuation.yield()
        for await _ in stream {
            if Task.isCancelled { return }
            for work in translations.take(from: latest) {
                do {
                    let response = try await session.translate(work.text)
                    translations.finished(lineID: work.lineID, source: work.text, translation: response.targetText)
                } catch {
                    translations.failed(lineID: work.lineID, source: work.text)
                    if Task.isCancelled { return }
                }
            }
        }
    }

}
