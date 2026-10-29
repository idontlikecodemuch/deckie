import Foundation

// The key profiles of the whitened-HPCP key method (`HPCPKey`), with where each number comes from. A key profile is
// twelve weights, one per semitone above the tonic, saying how much of each pitch class a key in that mode tends to
// have; the method rotates each to the 24 keys and correlates it with the track's pitch-class profile.
//
// Sources (DEPENDENCIES.md, "Key profiles and the HPCP: numbers from the literature", says how each was checked):
// - edma: Faraldo, Gomez, Jorda and Herrera, "Key estimation in electronic dance music", ECIR 2016 (LNCS 9626,
//   pp. 335-347), the median of the averaged chromagrams of 925 EDM tracks. The paper draws the profiles (its figure 3,
//   scaled to sum to 1) without printing numbers; the numbers are printed above the bars of figure 6.5 (p. 150) of
//   Faraldo's thesis, "Tonality estimation in electronic dance music: a computational and musically informed
//   examination" (Universitat Pompeu Fabra, 2017; Zenodo, doi 10.5281/zenodo.1154586), two decimals, tonic 1.00.
// - braw: Faraldo, Jorda and Herrera, "A multi-profile method for key estimation in EDM", AES Semantic Audio 2017,
//   the median profile of 600 Beatport tracks (half major, half minor); the paper draws them (figure 2), the thesis
//   prints them to two decimals above the bars of figure 6.12 (p. 158) and plots them to four, which the PDF's
//   vector data give: the four-decimal values below.
// - bgate: braw with its four weakest degrees set to zero (major: minor second, minor third, tritone, minor sixth;
//   minor: minor second, major third, tritone, major sixth; the AES paper's section 3.1), the rest rounded to two
//   decimals; thesis figure 6.12 (p. 158), printed and plotted alike.
//
// `KeyProfile` (KeyEstimator.swift) keeps mixer/key_light.py's copy of the same profiles, transcribed there from
// Essentia's key.cpp, for the STFT estimator and the quick vote, which are ported from that file. The two agree in
// every number but one: edma major at the minor sixth, 0.32 in the thesis (its plotted point reads 0.3159) and 0.31
// in key.cpp. The literature wins for the engine's key; key_light's value stays for parity with mixer/key_parity.py,
// whose per-track sheet (mixer/key_parity_keys.tsv) was made with it (`HPCPKey.Table.keyLight`).

/// One key profile pair of the HPCP key method: its name and twelve weights per mode, tonic first, rising by semitone.
public struct HPCPProfile: Sendable, Equatable {
    public var name: String
    public var major: [Double]
    public var minor: [Double]

    public init(name: String, major: [Double], minor: [Double]) {
        precondition(major.count == 12 && minor.count == 12, "a key profile has 12 weights per mode")
        self.name = name
        self.major = major
        self.minor = minor
    }
}

extension HPCPKey {
    /// Which numbers the three profiles take.
    public enum Table: String, Sendable, CaseIterable {
        /// As the literature prints them (above); the engine's key is decided with these.
        case literature
        /// As mixer/key_light.py carries them (`KeyProfile`, from Essentia's key.cpp): the stage fixtures carry both
        /// tables' decisions (`make_key_parity_fixtures.py`); the engine no longer decides with these.
        case keyLight = "key_light"

        /// edma, bgate and braw, in research R's order (key_parity.py's `FARALDO`).
        public var profiles: [HPCPProfile] {
            switch self {
            case .literature: return HPCPKey.literatureProfiles
            case .keyLight:
                return [KeyProfile.edma, .bgate, .braw].map { HPCPProfile(name: $0.rawValue, major: $0.major, minor: $0.minor) }
            }
        }
    }

    /// The three profiles as the literature prints them, tonic first.
    public static let literatureProfiles: [HPCPProfile] = [
        // Faraldo et al., ECIR 2016 (drawn, figure 3); numbers printed in Faraldo's thesis (2017), figure 6.5, p. 150.
        // Major, minor sixth: 0.32 here, 0.31 in key.cpp and key_light.py (the thesis plots 0.3159).
        HPCPProfile(name: "edma",
                    major: [1.00, 0.29, 0.50, 0.40, 0.60, 0.56, 0.32, 0.80, 0.32, 0.45, 0.42, 0.39],
                    minor: [1.00, 0.31, 0.44, 0.58, 0.33, 0.49, 0.29, 0.78, 0.43, 0.29, 0.53, 0.32]),
        // Faraldo, Jorda and Herrera, AES Semantic Audio 2017, section 3.1 and figure 2 (drawn); Faraldo's thesis
        // (2017), figure 6.12, p. 158 (printed to two decimals, plotted to these four).
        HPCPProfile(name: "bgate",
                    major: [1.00, 0.00, 0.42, 0.00, 0.53, 0.37, 0.00, 0.77, 0.00, 0.38, 0.21, 0.30],
                    minor: [1.00, 0.00, 0.36, 0.39, 0.00, 0.38, 0.00, 0.74, 0.27, 0.00, 0.42, 0.23]),
        // As bgate, before the gate: figure 6.12's upper panel; four decimals from the plotted points, which round
        // to the two printed above the bars.
        HPCPProfile(name: "braw",
                    major: [1.0000, 0.1573, 0.4200, 0.1570, 0.5296, 0.3669, 0.1632, 0.7711, 0.1676, 0.3827, 0.2113, 0.2965],
                    minor: [1.0000, 0.2330, 0.3615, 0.3905, 0.2925, 0.3777, 0.1961, 0.7425, 0.2701, 0.2161, 0.4228, 0.2272]),
    ]
}
