import Foundation

// #247: Static calibration table for Apple voices, measured once at setup (spike commit 4b53310).
// Currently Spanish (es-ES) only; other languages measured and added as needed.

public enum VoiceCalibrationTable {
    /// Returns calibrations for the given language code, or empty array if unmeasured.
    public static func calibrations(for languageCode: String) -> [VoiceCalibration] {
        let base = languageCode.split(separator: "-").first.map(String.init) ?? languageCode
        switch base.lowercased() {
        case "es": return spanishCalibrations
        default: return []
        }
    }

    private static let spanishCalibrations: [VoiceCalibration] = [
        VoiceCalibration(
            id: "com.apple.voice.compact.es-ES.Monica",
            pitchHz: 174.62760470146674,
            syllablesPerSecond: 5.9880239520958085,
            rateCurve: [
                .init(0.4, 5.434782608695652),
                .init(0.45, 5.434782608695652),
                .init(0.5, 5.9880239520958085),
                .init(0.55, 7.731958762886598),
                .init(0.6, 9.523809523809522),
            ],
            pitchCurve: [
                .init(0.7, 160.5782765125641),
                .init(0.8, 165.98559428785418),
                .init(0.9, 169.59016498601932),
                .init(1, 174.62760470146674),
                .init(1.1, 192.03043389821485),
                .init(1.25, 218.34357162311008),
                .init(1.4, 244.77512997558898),
            ]
        ),
        VoiceCalibration(
            id: "com.apple.eloquence.es-ES.Eddy",
            pitchHz: 123.14651714282843,
            syllablesPerSecond: 6.185567010309278,
            rateCurve: [
                .init(0.4, 5.10204081632653),
                .init(0.45, 5.504587155963303),
                .init(0.5, 6.185567010309278),
                .init(0.55, 7.8125),
                .init(0.6, 9.966777408637872),
            ],
            pitchCurve: [
                .init(0.7, 104.1073575799344),
                .init(0.8, 110.86086588214643),
                .init(0.9, 113.63387442328361),
                .init(1, 123.14651714282843),
                .init(1.1, 137.20474736333628),
                .init(1.25, 156.49981228499598),
                .init(1.4, 187.0168537127295),
            ]
        ),
        VoiceCalibration(
            id: "com.apple.eloquence.es-ES.Flo",
            pitchHz: 254.24303899105004,
            syllablesPerSecond: 6.211180124223603,
            rateCurve: [
                .init(0.4, 5.110732538330494),
                .init(0.45, 5.514705882352941),
                .init(0.5, 6.211180124223603),
                .init(0.55, 7.83289817232376),
                .init(0.6, 10.06711409395973),
            ],
            pitchCurve: [
                .init(0.7, 189.37645466231282),
                .init(0.8, 211.73987860252936),
                .init(0.9, 225.26635514018691),
                .init(1, 254.24303899105004),
                .init(1.1, 281.08187539289475),
                .init(1.25, 335.85267857142857),
                .init(1.4, 415.0943396226415),
            ]
        ),
        VoiceCalibration(
            id: "com.apple.eloquence.es-ES.Grandma",
            pitchHz: 122.30908291612599,
            syllablesPerSecond: 6.198347107438017,
            rateCurve: [
                .init(0.4, 5.208333333333333),
                .init(0.45, 5.571428571428571),
                .init(0.5, 6.198347107438017),
                .init(0.55, 7.894736842105263),
                .init(0.6, 10.15873015873016),
            ],
            pitchCurve: [
                .init(0.7, 102.46863469387756),
                .init(0.8, 109.75903614457831),
                .init(0.9, 114.60396039603959),
                .init(1, 122.30908291612599),
                .init(1.1, 137.66739839005092),
                .init(1.25, 156.50902884615386),
                .init(1.4, 189.7590361445783),
            ]
        ),
        VoiceCalibration(
            id: "com.apple.eloquence.es-ES.Grandpa",
            pitchHz: 93.09296630324215,
            syllablesPerSecond: 6.224066390041493,
            rateCurve: [
                .init(0.4, 5.154639175257732),
                .init(0.45, 5.56),
                .init(0.5, 6.224066390041493),
                .init(0.55, 7.905694150420949),
                .init(0.6, 10.15873015873016),
            ],
            pitchCurve: [
                .init(0.7, 80.39115646258503),
                .init(0.8, 85.30316742081448),
                .init(0.9, 88.5057471264369),
                .init(1, 93.09296630324215),
                .init(1.1, 103.95348837209302),
                .init(1.25, 124.8),
                .init(1.4, 154.40298507462686),
            ]
        ),
        VoiceCalibration(
            id: "com.apple.eloquence.es-ES.Reed",
            pitchHz: 109.36179272612327,
            syllablesPerSecond: 6.211180124223603,
            rateCurve: [
                .init(0.4, 5.102040816326531),
                .init(0.45, 5.529411764705883),
                .init(0.5, 6.211180124223603),
                .init(0.55, 7.868852459016393),
                .init(0.6, 10.101010101010102),
            ],
            pitchCurve: [
                .init(0.7, 90.15789473684211),
                .init(0.8, 98.94117647058823),
                .init(0.9, 103.01369863013698),
                .init(1, 109.36179272612327),
                .init(1.1, 121.35483870967742),
                .init(1.25, 145.02083333333334),
                .init(1.4, 183.16091954022989),
            ]
        ),
        VoiceCalibration(
            id: "com.apple.eloquence.es-ES.Rocko",
            pitchHz: 81.8177140979941,
            syllablesPerSecond: 6.211180124223603,
            rateCurve: [
                .init(0.4, 5.102040816326531),
                .init(0.45, 5.5),
                .init(0.5, 6.211180124223603),
                .init(0.55, 7.826086956521739),
                .init(0.6, 10.101010101010102),
            ],
            pitchCurve: [
                .init(0.7, 71.23457943925233),
                .init(0.8, 75.37037037037037),
                .init(0.9, 77.9005524861878),
                .init(1, 81.8177140979941),
                .init(1.1, 89.58904109589041),
                .init(1.25, 106.44),
                .init(1.4, 133.67088607594937),
            ]
        ),
        VoiceCalibration(
            id: "com.apple.eloquence.es-ES.Sandy",
            pitchHz: 285.72485258003223,
            syllablesPerSecond: 6.25,
            rateCurve: [
                .init(0.4, 5.208333333333333),
                .init(0.45, 5.56),
                .init(0.5, 6.25),
                .init(0.55, 7.894736842105263),
                .init(0.6, 10),
            ],
            pitchCurve: [
                .init(0.7, 214.29289617486338),
                .init(0.8, 241.6487919463087),
                .init(0.9, 258.2710280373831),
                .init(1, 285.72485258003223),
                .init(1.1, 319.04545454545453),
                .init(1.25, 386.71),
                .init(1.4, 481.11),
            ]
        ),
        VoiceCalibration(
            id: "com.apple.eloquence.es-ES.Shelley",
            pitchHz: 191.3503737028535,
            syllablesPerSecond: 6.198347107438017,
            rateCurve: [
                .init(0.4, 5.208333333333333),
                .init(0.45, 5.59375),
                .init(0.5, 6.198347107438017),
                .init(0.55, 7.826086956521739),
                .init(0.6, 9.944751131221718),
            ],
            pitchCurve: [
                .init(0.7, 155.50505050505052),
                .init(0.8, 171.79625282051282),
                .init(0.9, 181.47959183673472),
                .init(1, 191.3503737028535),
                .init(1.1, 210.82191780821918),
                .init(1.25, 246.175),
                .init(1.4, 300.4),
            ]
        ),
    ]
}
