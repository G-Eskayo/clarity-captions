import CaptionCore
import Speech
import SwiftUI
import Translation

/// #37 / #53: the language people around her speak, chosen from every language Apple's speech engine has on this
/// device. Opened from Settings' "Caption language" row and from translation's "From" row: one setting, one list.
/// Same page style as Credits: a short intro, then a name and one line per entry, one thin line between them.
struct CaptionLanguagePage: View {
    let style: CaptionStyle
    let language: LanguageSettingsState
    let onBack: () -> Void
    var onChoose: ((Locale) -> Void)?
    @State private var rows: [CaptionLanguageList.Row] = []

    private var translatingInto: Locale? { language.translationOwned && language.translationOn ? language.target : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(style: style, title: String(localized: "Caption language"), backTitle: String(localized: "Settings"), onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(intro)
                        .font(.body)
                        .foregroundStyle(mutedColor(style))
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                    CaptionLanguageDownloadLine(style: style, phase: language.captionDownload)
                    CaptionLanguageRows(style: style, rows: rows, translatingInto: translatingInto, onChoose: onChoose)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(style.text.color)
        // Ticks move as soon as a language is on the device: the list follows the caption language.
        .task(id: CaptionLanguage.bcp47(language.captions)) { rows = await Self.loadRows(current: language.captions, into: translatingInto) }
    }

    private var intro: String {
        if let into = translatingInto {
            return String(format: String(localized: "Pick the language people around you speak. Seal captions it and translates it into %@."), LanguageSettingsState.name(into))
        }
        return String(localized: "Pick the language people around you speak. Seal captions it.")
    }

    /// What the engine has on this device. Debug demo launches use the list Apple reported on the Mini (2026-10-28),
    /// so screenshots don't depend on what the simulator has installed.
    static func loadRows(current: Locale, into: Locale?) async -> [CaptionLanguageList.Row] {
        var speech = await SpeechTranscriber.supportedLocales
        var installed = Array(await SpeechTranscriber.installedLocales)
        var translatable = await LanguageAvailability().supportedLanguages
        #if DEBUG
        if DemoMode.isOn || DemoMode.opensSettings || DemoMode.settingsPush != nil {
            speech = DemoLanguages.speech.map(Locale.init(identifier:))
            installed = DemoLanguages.installed.map(Locale.init(identifier:))
            translatable = DemoLanguages.translation.map(Locale.Language.init(identifier:))
        }
        #endif
        let rows = CaptionLanguageList.rows(speech: speech, installed: installed, current: current,
                                            translation: into.map { (into: $0, supported: translatable) })
        // The chosen language stays first; the rest keep their groups and read in her own alphabet inside each.
        guard let first = rows.first else { return rows }
        return [first] + rows.dropFirst().sorted {
            if $0.translation.listGroup != $1.translation.listGroup { return $0.translation.listGroup < $1.translation.listGroup }
            return LanguageSettingsState.name($0.locale).localizedStandardCompare(LanguageSettingsState.name($1.locale)) == .orderedAscending
        }
    }
}

/// #53: the language captions are translated into: every language Apple's Translation has on this device, except
/// the one being captioned. Each says whether its language pack is here, downloads once, or can't be done from the
/// caption language (said plainly, not hidden).
struct TranslationTargetPage: View {
    let style: CaptionStyle
    let language: LanguageSettingsState
    let onBack: () -> Void
    var onChoose: ((Locale) -> Void)?
    @State private var rows: [TranslationTargetList.Row] = []
    @State private var status: [String: LanguageAvailability.Status] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(style: style, title: String(localized: "Translate into"), backTitle: String(localized: "Settings"), onBack: onBack)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: String(localized: "Pick the language you read. Seal translates %@ into it, on this %@."),
                                LanguageSettingsState.name(language.captions), LanguageSettingsState.deviceWord))
                        .font(.body)
                        .foregroundStyle(mutedColor(style))
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { ThinRule(style: style) }
                        rowView(row)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(style.text.color)
        .task(id: language.target.map(CaptionLanguage.bcp47)) { await load() }
    }

    private func load() async {
        var supported = await LanguageAvailability().supportedLanguages
        #if DEBUG
        if DemoMode.isOn || DemoMode.opensSettings || DemoMode.settingsPush != nil {
            supported = DemoLanguages.translation.map(Locale.Language.init(identifier:))
        }
        #endif
        let list = TranslationTargetList.rows(supported: supported, from: language.captions, current: language.target)
        rows = list.sorted { a, b in
            if a.isCurrent != b.isCurrent { return a.isCurrent }
            return LanguageSettingsState.name(a.locale).localizedStandardCompare(LanguageSettingsState.name(b.locale)) == .orderedAscending
        }
        #if DEBUG && targetEnvironment(simulator)
        // The simulator has no Translation languages (every pair "unsupported"): demo runs show a device's view, the
        // current pack installed and the rest downloadable. Debug simulator builds only.
        if DemoMode.translate != nil || DemoMode.fakeStore {
            for row in rows { status[row.id] = row.isCurrent ? .installed : .supported }
            return
        }
        #endif
        let availability = LanguageAvailability()
        for row in rows { status[row.id] = await availability.status(from: language.captions.language, to: row.locale.language) }
    }

    private func rowView(_ row: TranslationTargetList.Row) -> some View {
        let unsupported = status[row.id] == .unsupported
        return Button { onChoose?(row.locale) } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: LanguageSettingsState.name(row.locale)).font(.headline.weight(.heavy))
                    Text(verbatim: detail(row)).font(.subheadline).foregroundStyle(mutedColor(style))
                }
                Spacer()
                if row.isCurrent {
                    Image(systemName: "checkmark").font(.body.weight(.heavy)).foregroundStyle(style.gear.color)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(unsupported)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
    }

    private func detail(_ row: TranslationTargetList.Row) -> String {
        var parts: [String] = []
        let own = row.locale.localizedString(forIdentifier: row.locale.identifier) ?? ""
        if own != LanguageSettingsState.name(row.locale) { parts.append(own) }
        switch status[row.id] {
        case .installed: parts.append(String(format: String(localized: "On this %@"), LanguageSettingsState.deviceWord))
        case .supported: parts.append(String(localized: "Downloads once"))
        case .unsupported: parts.append(String(format: String(localized: "can't translate from %@ yet"), LanguageSettingsState.name(language.captions)))
        default: break
        }
        return parts.joined(separator: " · ")
    }
}

/// The rows of the caption language list: Settings' page and first run's question (#37).
struct CaptionLanguageRows: View {
    let style: CaptionStyle
    let rows: [CaptionLanguageList.Row]
    let translatingInto: Locale?
    var onChoose: ((Locale) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { ThinRule(style: style) }
                rowView(row)
            }
        }
    }

    private func rowView(_ row: CaptionLanguageList.Row) -> some View {
        Button { onChoose?(row.locale) } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: LanguageSettingsState.name(row.locale)).font(.headline.weight(.heavy))
                    Text(verbatim: detail(row)).font(.subheadline).foregroundStyle(mutedColor(style))
                }
                Spacer()
                if row.isCurrent {
                    Image(systemName: "checkmark").font(.body.weight(.heavy)).foregroundStyle(style.gear.color)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.supported)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
    }

    /// Its own name (so the other person can find theirs), then what choosing it means.
    private func detail(_ row: CaptionLanguageList.Row) -> String {
        var parts: [String] = []
        let own = row.locale.localizedString(forIdentifier: row.locale.identifier) ?? ""
        if own != LanguageSettingsState.name(row.locale) { parts.append(own) }
        if !row.supported {
            parts.append(String(format: String(localized: "Not on this %@ any more"), LanguageSettingsState.deviceWord))
        } else {
            parts.append(row.onDevice ? String(format: String(localized: "On this %@"), LanguageSettingsState.deviceWord)
                                      : String(localized: "Downloads once"))
        }
        switch row.translation {
        case .off, .translates: break
        case .captionsOnly:
            parts.append(String(format: String(localized: "can't be translated into %@ yet"), translatingInto.map(LanguageSettingsState.name) ?? ""))
        case .yourLanguage: parts.append(String(localized: "your language, nothing to translate"))
        }
        return parts.joined(separator: " · ")
    }
}

/// A caption language on its way (#37): real progress in plain words, or what went wrong (tapping the language again
/// tries again). Nothing when there's no download.
struct CaptionLanguageDownloadLine: View {
    let style: CaptionStyle
    let phase: CaptionLanguageSwitch.Phase

    var body: some View {
        switch phase {
        case .ready: EmptyView()
        case .downloading(let locale, let p):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: p).tint(style.gear.color)
                Text(String(format: String(localized: "Downloading %@ · %lld%%"), LanguageSettingsState.name(locale), Int(p * 100)))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(mutedColor(style))
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        case .failed(let locale, let why):
            Text(why.message(language: LanguageSettingsState.name(locale)))
                .font(.subheadline.weight(.semibold)).foregroundStyle(mutedColor(style))
                .padding(.vertical, 8)
        }
    }
}

#if DEBUG
/// `SpeechTranscriber.supportedLocales` and `LanguageAvailability().supportedLanguages` on the M4 Mac mini, macOS
/// 26.5, 2026-10-28 (evidence E24). Installed: what a phone set to English with Spanish captions would have.
enum DemoLanguages {
    static let speech = ["de-AT", "de-CH", "de-DE", "en-AU", "en-CA", "en-GB", "en-IE", "en-IN", "en-NZ", "en-SG", "en-US",
                         "en-ZA", "es-CL", "es-ES", "es-MX", "es-US", "fr-BE", "fr-CA", "fr-CH", "fr-FR", "it-CH", "it-IT",
                         "ja-JP", "ko-KR", "pt-BR", "pt-PT", "yue-CN", "zh-CN", "zh-HK", "zh-TW"]
    static let installed = ["en-US", "es-ES"]
    static let translation = ["ar-Arab-AE", "da-Latn-DK", "de-Latn-CH", "de-Latn-DE", "en-Latn-US", "en-Latn-GB",
                              "es-Latn-ES", "es-Latn-MX", "es-Latn-US", "fr-Latn-CA", "fr-Latn-FR", "hi-Deva-IN",
                              "id-Latn-ID", "it-Latn-CH", "it-Latn-IT", "ja-Jpan-JP", "ko-Kore-KR", "nb-Latn-NO",
                              "nl-Latn-NL", "pl-Latn-PL", "pt-Latn-BR", "pt-Latn-PT", "ru-Cyrl-RU", "sv-Latn-SE",
                              "th-Thai-TH", "tr-Latn-TR", "uk-Cyrl-UA", "vi-Latn-VN", "zh-Hans-CN", "zh-Hant-HK", "zh-Hant-TW"]
}
#endif
