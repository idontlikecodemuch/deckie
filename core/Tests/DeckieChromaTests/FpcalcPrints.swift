// What fpcalc 1.6.2 (Chromaprint's official macOS build, chromaprint-fpcalc-1.6.2-macos-arm64 from
// github.com/acoustid/chromaprint/releases) printed for the test sounds of ChromaprintTests.swift, Nov 14, 2026.
// `fpcalc <file>` gives DURATION and FINGERPRINT; `fpcalc -raw` the raw frames.
enum FpcalcPrints {
    static let all: [String: (duration: Int, fingerprint: String)] = [
        "sweep": (12,
            "AQAAS14YSVqUYM5kCV8SKsUtD4-R7EGYZSZe40yOM1NWZEo-HEmOgccQ-Q-ehD2kteGG_ICPM8XTsMW3HI0uFhOSI8dyDP-DOcuF"
            + "nGkO_kgOP3hm4nWLU8dPpMmhHDmG5XiK3FkTjFnEQ6WRo0TDuXiPM4lMnJmOTMkPHdEx8JiRew0UqsfD5sgB73iW4mGLb0eW6Cx6"
            + "KMgBgbglSACnDQMCAA0sIQogqxgBgADABKaEKAGcp4oRATRBCAhGrGFEAaAhgUowqAA"),
        "clicks": (12,
            "AQAAS0mUaEkSZSqOEweOEweOEweO4ziO4ziO4ziO4ziO4ziO4ziO4ziO4ziO4ziO4ziO4ziO4ziO4ziO4ziO4ziOA-esc9Y566yz"
            + "zjrrrLPOOuuss84666yzzjrrrLPOOuuss84666yzzjrrrLPOAg"),
        "noise": (12,
            "AQAAS5GUJEoSJYmUKCB-HGJx_MZP4DhMgq-gw8IJ3XgPE7hhEjwO-IQ_4MRx4jh8HtdxuDh-yPpx-BCOw8dxgTguHITx44D14zjw"
            + "48WF4zqM3-CPQ9KJ7zjwXABEjRPSKXGCcBIZa4RWxhqOhHBOGGeEkEIk5RySziljhMVGOyekcMYYIwRzhgE"),
        "chords": (16,
            "AQAAbFISSZk1BceOHwd_4yd-bH9w9Mcz3DnCf3gD_8IB5MeBGziKH_lx7MfRQ0d-HAeO4_AvXOiB49aRj4dm7oQbECeAY9Zx_MDR"
            + "i3iDM0ePO0ceHNiPEwd_PGexHz56vMcZ5D7qLByuC34AHPnx4zhwFPlxHdiPXoGOH_kNHMdxHH4u9DgABZIlgSmEuDLUCYYAEAgg"
            + "RzgG7wAloTEUiWdgmkUtRAUqQhlBjlIIIKEI0cYxJSAZASMEkVdOMCMgAIJwgVh4BTBnDFEQAYrmIGoZxQA"),
    ]
    /// `fpcalc -raw` on the clicks: the first 24 frames.
    static let clicksRawHead: [UInt32] = [
        558758263, 558750071, 558889335, 558758263, 558758263, 558750071,
        558889335, 558758263, 558758263, 558750071, 558889335, 558758263,
        558758263, 558750071, 558881143, 558889335, 558758263, 558750071,
        558881143, 558889335, 558758263, 558750071, 558881143, 558889335,
    ]
}
