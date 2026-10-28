// `AudioBuffer` lives in DeckieAudio so the analysers in DeckieCore can take audio without depending on the
// decoder. Re-exported here so code that imports DeckieDecode sees it as before.
@_exported import DeckieAudio
