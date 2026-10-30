import CaptionCore
import Foundation
import OSLog
import StoreKit
import SwiftUI
import UIKit
import Translation

/// Live translation (#53): the one-time purchase (StoreKit 2), on or off, the language it goes into, Apple's
/// on-device Translation (picked in #159), and the translated text for each caption line. Settings, the Into list and
/// the captions all read this one object.
@MainActor
final class TranslationCenter: ObservableObject {
    static let shared = TranslationCenter()
    private static let log = Logger(subsystem: "com.gileskayo.captions", category: "translation")

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
    /// #60 face to face, the second direction: her words (the language she reads) into the other person's language.
    @Published private(set) var reverseTranslations = CaptionTranslations()
    @Published private(set) var reverseConfiguration: TranslationSession.Configuration?
    private var faceToFace = false
    /// #208: the two languages the split's halves picked (the other person's, hers); nil until both have picked.
    private var faceToFacePair: (partner: Locale, owner: Locale)?
    private var reverseWake: AsyncStream<Void>.Continuation?
    private var latestReverse: [CaptionLine] = []

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
        if DemoMode.fakeStore { price = "$4.99"; purchase.entitlementChanged(owned: DemoMode.fakeStoreOwned); refreshConfiguration(); return }
        #endif
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    if case .verified(let t) = result { await t.finish() }
                    await self?.refreshEntitlement()
                }
            }
        }
        do {
            product = try await Product.products(for: [TranslationPurchase.productID]).first
            if product == nil { Self.log.error("the App Store has no product \(TranslationPurchase.productID, privacy: .public)") }
        } catch {
            Self.log.error("products failed: \(String(describing: error), privacy: .public)")
        }
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
        #if DEBUG
        // `-ClarityDemoFakeStore`: no App Store on a command-line simulator run; the purchase succeeds after a moment.
        if DemoMode.fakeStore {
            try? await Task.sleep(for: .seconds(1.5))
            purchase.buyFinished(.bought); DemoMode.fakeStoreOwned = true; setOn(true); return
        }
        #endif
        if product == nil { product = try? await Product.products(for: [TranslationPurchase.productID]).first; price = product?.displayPrice }
        guard let product else { purchase.buyFinished(.failed); return }
        do {
            // Apple's sheet is shown over Seal's window (iOS 18.2+ wants the scene it confirms in).
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let result = if let scene { try await product.purchase(confirmIn: scene) } else { try await product.purchase() }
            switch result {
            case .success(.verified(let t)):
                await t.finish()
                purchase.buyFinished(.bought)
                // Bought to use it: turn it on.
                setOn(true)
            case .success(.unverified(_, let why)):
                Self.log.error("purchase unverified: \(String(describing: why), privacy: .public)")
                purchase.buyFinished(.failed)
            case .userCancelled: purchase.buyFinished(.cancelled)
            case .pending: purchase.buyFinished(.pending)
            @unknown default: purchase.buyFinished(.failed)
            }
        } catch {
            Self.log.error("purchase failed: \(String(describing: error), privacy: .public)")
            purchase.buyFinished(.failed)
        }
        refreshConfiguration()
    }

    func restore() async {
        guard purchase.restoreTapped() else { return }
        #if DEBUG
        if DemoMode.fakeStore {
            try? await Task.sleep(for: .seconds(1.5))
            purchase.restoreFinished(found: DemoMode.fakeStoreOwned); refreshConfiguration(); return
        }
        #endif
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

    /// The split opened or closed (#60), or its halves picked (#208): the second direction runs only while it's open,
    /// and in the split both directions are between the two picked languages, none until both halves have picked.
    func faceToFaceChanged(_ on: Bool, pair: LanguagePair?) {
        let before = (forwardSource?.minimalIdentifier, forwardTarget?.minimalIdentifier)
        let reverseBefore = faceToFacePair.map { $0.owner.identifier + ">" + $0.partner.identifier }
        faceToFace = on
        faceToFacePair = on ? pair.map { ($0.partner, $0.owner) } : nil
        if (forwardSource?.minimalIdentifier, forwardTarget?.minimalIdentifier) != before { translations.reset() }
        if !on || faceToFacePair.map({ $0.owner.identifier + ">" + $0.partner.identifier }) != reverseBefore {
            reverseTranslations.reset(); latestReverse = []
        }
        refreshConfiguration()
    }

    /// What the captions are translated from and into: one-way, the caption language into hers; in the split, the
    /// other person's picked language into hers.
    private var forwardSource: Locale.Language? {
        faceToFace ? faceToFacePair?.partner.language : CaptionLanguageCenter.engineLocale.language
    }
    private var forwardTarget: Locale.Language? { faceToFace ? faceToFacePair?.owner.language : target?.language }

    /// A new session for the current pair, or none. Also reads whether the pair needs its language pack.
    func refreshConfiguration() {
        defer { refreshReverseConfiguration() }
        #if DEBUG && targetEnvironment(simulator)
        // Lines that landed before translation was bought or turned on get their stand-in now.
        defer { if usesDemoTranslator { demoFill(latest) } }
        // No session for the stand-in: on the simulator Apple's sheet only says translation isn't supported, and it
        // covered the screenshots (#60).
        if usesDemoTranslator { configuration = nil; return }
        #endif
        guard purchase.isOwned, isOn, let source = forwardSource, let target = forwardTarget else {
            configuration = nil; preparing = false; unsupportedPair = false; return
        }
        let wanted = TranslationSession.Configuration(source: source, target: target)
        if configuration?.source != wanted.source || configuration?.target != wanted.target { configuration = wanted }
        Task {
            let status = await LanguageAvailability().status(from: source, to: target)
            unsupportedPair = status == .unsupported
            #if DEBUG && targetEnvironment(simulator)
            if usesDemoTranslator { unsupportedPair = false }
            #endif
            if unsupportedPair { configuration = nil }
        }
    }

    private func refreshReverseConfiguration() {
        #if DEBUG && targetEnvironment(simulator)
        if usesDemoTranslator { reverseConfiguration = nil; return }
        #endif
        guard faceToFace, purchase.isOwned, isOn, let pair = faceToFacePair, !unsupportedPair else { reverseConfiguration = nil; return }
        let wanted = TranslationSession.Configuration(source: pair.owner.language, target: pair.partner.language)
        if reverseConfiguration?.source != wanted.source || reverseConfiguration?.target != wanted.target { reverseConfiguration = wanted }
    }

    // MARK: the captions

    /// The caption lines changed: wake the session's loop. A new conversation starts clean. Face to face (#60), `lines`
    /// are the other person's (into her language) and `reverse` hers (into theirs).
    func linesChanged(_ lines: [CaptionLine], reverse: [CaptionLine] = []) {
        if lines.isEmpty && reverse.isEmpty { translations.reset(); reverseTranslations.reset() }
        latest = lines
        latestReverse = reverse
        #if DEBUG && targetEnvironment(simulator)
        if usesDemoTranslator { demoFill(lines); demoFillReverse(reverse); return }
        #endif
        wake?.yield()
        reverseWake?.yield()
    }

    #if DEBUG && targetEnvironment(simulator)
    /// The iOS Simulator has no Translation languages (every pair reports unsupported, 2026-10-28), so a demo launch
    /// with `-ClarityDemoTranslate` fills in the demo conversation's own English lines, to show the layout. Debug
    /// simulator builds only; a device always uses Apple's Translation.
    private var usesDemoTranslator: Bool { DemoMode.translate != nil || DemoMode.fakeStore }

    private func demoFill(_ lines: [CaptionLine]) {
        guard isOn, purchase.isOwned, !faceToFace || faceToFacePair != nil else { return }
        for work in translations.take(from: lines) {
            translations.finished(lineID: work.lineID, source: work.text,
                                  translation: DemoMode.englishLine(for: work.text) ?? DemoMode.faceToFaceTranslation(of: work.text) ?? work.text)
        }
    }

    private func demoFillReverse(_ lines: [CaptionLine]) {
        guard isOn, purchase.isOwned, faceToFace, faceToFacePair != nil else { return }
        for work in reverseTranslations.take(from: lines) {
            reverseTranslations.finished(lineID: work.lineID, source: work.text,
                                         translation: DemoMode.faceToFaceTranslation(of: work.text) ?? work.text)
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
        if let source = forwardSource, let target = forwardTarget, await LanguageAvailability().status(from: source, to: target) != .installed {
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

    /// The second direction (#60), inside its own `.translationTask`: her finished lines into the other person's
    /// language, while the split is open. Its language pack comes the same way, through Apple's own sheet.
    func runReverse(_ session: TranslationSession) async {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        reverseWake = continuation
        defer { continuation.finish() }
        if let pair = faceToFacePair, await LanguageAvailability().status(from: pair.owner.language, to: pair.partner.language) != .installed {
            do { try await session.prepareTranslation() } catch { return }
        }
        continuation.yield()
        for await _ in stream {
            if Task.isCancelled { return }
            for work in reverseTranslations.take(from: latestReverse) {
                do {
                    let response = try await session.translate(work.text)
                    reverseTranslations.finished(lineID: work.lineID, source: work.text, translation: response.targetText)
                } catch {
                    reverseTranslations.failed(lineID: work.lineID, source: work.text)
                    if Task.isCancelled { return }
                }
            }
        }
    }

}
