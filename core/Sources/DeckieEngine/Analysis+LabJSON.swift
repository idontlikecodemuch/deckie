import Foundation
import DeckieCore

extension Analysis {
    /// The record as a lab feature file (mixer/features/<id>.json): the keys of mixer/analyze.py's `out` dict, in its
    /// order, rounded as it rounds them, bars 1-based, followed by `local_tempo` (as the lab appends it) and one block
    /// of the engine's own, `deckie`, which the lab's tools do not read. So the Mac can put an engine record beside the
    /// lab's file for the same track and compare them with the lab's own code.
    ///
    /// What the engine cannot produce, and how it is written (the lab's own way of writing a missing value wherever it
    /// has one):
    /// - `bpm_essentia`, `essentia_confidence`: null, as the lab writes them when Essentia's tempo fails; then
    ///   `essentia_agree` is false, as the lab computes it then. Essentia is not ported (the key and tempo come from
    ///   the engine's own estimators).
    /// - `bpm_madmom`, `madmom_downbeats_s`, `madmom_reason`: null, `madmom_ran`: false, and `grid_candidates` holds
    ///   `beatthis` alone, as when the lab's madmom does not run: the madmom fallback is non-commercial and not ported.
    ///   (`deckie.madmom_would_run` says when the lab would have run it.) `grid.source` is `beat-this-final0`, the
    ///   checkpoint's name, where the lab writes `beatthis`.
    /// - `key.essentia_edma`, `key.essentia_bgate`, `key.madmom_cnn`, `key.camelot_edma`, `key.camelot_bgate`,
    ///   `key.camelot_madmom`: null, as the lab writes madmom's when it fails. `key.camelot`, `key.confidence` and
    ///   `key.confidence_rule` come from the engine's key vote (`KeyVote`, `KeyConfidence`: the lab's B.9 rule on three
    ///   profiles over the engine's chroma); each vote's key, correlation and margin, the edma estimate's mix windows
    ///   and key segments are in `deckie.key`. `key.madmom_error` is left out, as the lab leaves it out when madmom
    ///   ran.
    /// - Without a vocal tagger: `vocal`, `per_bar.vocal_prob` and `embedding_effnet` are left out (the lab has no way
    ///   to write them missing); each section's `vocal` and each mix window's `vocal_free_bars` are null, and
    ///   `mix_in.first_vocal_bar` and `mix_out.last_vocal_bar` are null as the lab writes them for a track with no
    ///   vocal bar; the flags end with `vocal_unknown`. With a tagger, all of these are written as the lab writes
    ///   them, except `embedding_effnet`, which is never written (non-commercial; kept out of every crate); the
    ///   tagger's own detail (its rule, its singing, rapping, choir, speech and music scores per bar, four readings of
    ///   its class scores per bar with the classes each read, its style vector) goes in
    ///   `deckie.vocal` (`vocalBlock()`), null without a tagger, and the vocal structure and the hook candidates in
    ///   `deckie.vocal_structure` and `deckie.hooks` (the crate's proposed blocks, same fields and values), null
    ///   without a tagger. The lab's tools do not read the `deckie` block, so they read the file unchanged.
    /// - `meta` (the pool's bookkeeping from mixer/candidates.json): every key null.
    /// - `beatthis_device`: `cpu`. `timing_s` has the engine's stages (`Analyser`), named as the lab's where a stage
    ///   matches one.
    /// - `loudness.integrated_lufs` of digital silence is minus infinity, which Python writes as `-Infinity`; this
    ///   writes null.
    public func labJSON() -> JSONValue {
        typealias J = JSONValue
        func m(_ k: String, _ v: J) -> J.Member { J.Member(k, v) }
        let r3 = { (x: Double) in J.round(x, 3) }
        let n = bars.nBars
        let vocalKnown = vocal != nil

        let gridOut: J = .object([
            m("source", .string(Analysis.gridSource)), m("bpm", r3(bpm)),
            m("first_downbeat_s", J.round(bars.firstDownbeatS, 4)), m("beat_s", J.round(bars.beatS, 5)),
            m("bar_s", J.round(bars.barS, 5)), m("fit_mad_ms", J.round(grid.fitMadMs, 2)),
            m("inlier_frac", r3(grid.inlierFrac)), m("downbeat_agree", r3(grid.downbeatAgree)),
            m("confidence", r3(grid.confidence)), m("n_bars", .int(n)),
        ])
        let candidates: J = .object([m("beatthis", .object([
            m("bpm", r3(grid.bpm)), m("fit_mad_ms", J.round(grid.fitMadMs, 2)), m("confidence", r3(grid.confidence)),
            m("tag_dev_pct", J.round(gridTagDevPct, 2)),
        ]))])
        let octave: J = octaveFix.map { f in
            var members = [m("mode", .string(f.mode.rawValue)), m("from_bpm", .number(f.fromBpm))]
            if let p = f.parity { members.append(m("parity", .int(p))) }
            return .object(members)
        } ?? .null
        let ibis = zip(detectedBeats.dropFirst(), detectedBeats).map { $0 - $1 }
        let medianIBI: J = detectedBeats.count > 2 ? r3(60 / Py.median(ibis)) : .null

        let sectionsOut: J = .array(sections.map { s in
            .object([m("start_bar", .int(s.startBar)), m("end_bar", .int(s.endBar)), m("label", .string(s.label)),
                     m("energy", .string(s.energy)), m("lufs", J.round(s.lufs, 2)),
                     m("vocal", vocalKnown ? r3(s.vocal) : .null)])
        })
        let peaks = noveltyPeaks.sorted { ($0.bar, $0.value) < ($1.bar, $1.value) }
        let mixInOut: J = .object([
            m("start_bar", .int(mixIn.startBar)), m("end_bar", .int(mixIn.endBar)), m("bars", .int(mixIn.bars)),
            m("start_s", r3(mixIn.startS)), m("end_s", r3(mixIn.endS)),
            m("vocal_free_bars", vocalKnown ? .int(mixIn.vocalFreeBars) : .null),
            m("first_vocal_bar", J.integer(mixIn.firstVocalBar)),
        ])
        let mixOutOut: J = .object([
            m("start_bar", .int(mixOut.startBar)), m("end_bar", .int(mixOut.endBar)), m("bars", .int(mixOut.bars)),
            m("start_s", r3(mixOut.startS)), m("end_s", r3(mixOut.endS)),
            m("vocal_free_bars", vocalKnown ? .int(mixOut.vocalFreeBars) : .null),
            m("last_vocal_bar", J.integer(mixOut.lastVocalBar)), m("fade_out", .bool(mixOut.fadeOut)),
        ])
        let keyOut: J = .object([
            m("essentia_edma", .null), m("essentia_bgate", .null), m("madmom_cnn", .null),
            m("camelot_edma", .null), m("camelot_bgate", .null), m("camelot_madmom", .null),
            m("camelot", .string(keyVote.camelot)), m("confidence", .number(keyConfidence.value)),
            m("confidence_rule", .string(keyConfidence.rule)),
        ])
        var perBarMembers = [
            m("lufs_st", J.roundList(perBar.lufsSt, 2)), m("low_db", J.roundList(perBar.lowDb, 2)),
            m("high_db", J.roundList(perBar.highDb, 2)), m("onset_density", J.roundList(perBar.onsetDensity, 3)),
        ]
        if let v = perBar.vocalProb { perBarMembers.append(m("vocal_prob", J.roundList(v, 3))) }

        var out: [J.Member] = [
            m("schema", .int(Analysis.labSchema)),
            m("id", .string(id)), m("title", J.text(title)), m("ver", J.text(version)),
            m("path", .string(source.path)), m("sr", .int(Analysis.sampleRate)), m("duration_s", r3(duration)),
            m("bpm_tag", J.num(bpmTag)),
            m("bpm_beatthis", r3(grid.bpm)), m("bpm_beatthis_median_ibi", medianIBI),
            m("bpm_essentia", .null), m("essentia_confidence", .null), m("essentia_agree", .bool(false)),
            m("bpm_madmom", .null), m("madmom_ran", .bool(false)), m("madmom_reason", .null),
            m("bpm", r3(bpm)), m("bpm_agree", .bool(bpmAgree)),
            m("multiplier_vs_tag", .string(Tempo.label(multiplierVsTag))),
            m("multiplier_vs_tag_value", J.round(multiplierVsTag, 4)), m("tag_dev_pct", J.round(tagDevPct, 2)),
            m("octave_fix", octave),
            m("grid", gridOut), m("grid_candidates", candidates),
            m("beats_s", J.roundList(bars.beatTimes, 3)), m("downbeats_s", J.roundList(bars.barTimes, 3)),
            m("detected_beats_s", J.roundList(detectedBeats, 3)),
            m("detected_downbeats_s", J.roundList(detectedDownbeats, 3)),
            m("madmom_downbeats_s", .null),
            m("phrase", .object([
                m("lattice_phase_bar", .int(phrase.latticePhaseBar)), m("phrase_len_bars", .int(phrase.phraseLenBars)),
                m("confidence", r3(phrase.confidence)), m("phase_novelty", J.roundList(phrase.phaseNovelty, 3)),
                m("snap_phase_bar", .int(phrase.snapPhaseBar)),
            ])),
            m("boundaries_bars", .array(boundariesBars.map { .int($0) })),
            m("novelty_peaks", .array(peaks.map { .array([.int($0.bar), r3($0.value)]) })),
            m("sections", sectionsOut),
            m("first_sound_s", r3(firstSound)), m("last_sound_s", r3(lastSound)),
            m("fade_out", .bool(fade.fadeOut)), m("fade_drop_lu", J.round(fade.fadeDropLu, 2)),
            m("end_lufs_st", .object([m("t-20", J.round(endLoudness.t20, 2)), m("t-10", J.round(endLoudness.t10, 2)),
                                      m("t-4", J.round(endLoudness.t4, 2))])),
            m("tail_bars", J.round(fade.tailBars, 2)),
            m("fade_start_bar", J.integer(fade.fadeStartBar)),
            m("mix_in", mixInOut), m("mix_out", mixOutOut),
            m("key", keyOut),
            m("loudness", .object([m("integrated_lufs", J.round(loudness.integratedLufs, 2)),
                                   m("lra", J.round(loudness.lra, 3)), m("true_peak_db", J.round(loudness.truePeakDb, 2))])),
            m("per_bar", .object(perBarMembers)),
            m("onset_pattern_16", J.roundList(onsetPattern16, 4)),
        ]
        if let v = vocal {
            out.append(m("vocal", .object([
                m("mean_prob", J.round(v.meanProbability, 4)), m("vocal_heavy", .bool(v.meanProbability > 0.75)),
                m("patch_hop_s", J.round(v.frameHopSeconds, 4)), m("n_patches", .int(v.frameCount)),
            ])))
        }
        out += [
            m("flags", .array(flags.map { .string($0) })),
            m("meta", .object(["secs", "on_disc", "disc", "folder", "hal", "kind", "era", "cut_key", "is_longest"]
                .map { m($0, .null) })),
            m("timing_s", .object(timings.map { m($0.stage, J.round($0.seconds, 2)) })),
            m("beatthis_device", .string(Analysis.beatTrackerDevice)),
            m("local_tempo", Analysis.labJSON(localTempo)),
            m("deckie", deckieBlock()),
        ]
        return .object(out)
    }

    /// The lab's feature JSON as compact UTF-8 text.
    public func labJSONData() -> Data { labJSON().data }

    /// The engine's own block: the file's hash, the decoder, the key estimator's detail (the edma estimate as `whole`,
    /// each key vote under its name in `votes`, the decided key and the lab's rule words as `vote` and `vote_rule`,
    /// the song key the windows were judged against, the windows and the segments), where the lab would have run
    /// madmom, whether the vocal information is missing, the tagger's detail, the vocal structure and the hooks.
    func deckieBlock() -> JSONValue {
        typealias J = JSONValue
        func m(_ k: String, _ v: J) -> J.Member { J.Member(k, v) }
        func estimate(_ e: KeyEstimate) -> J {
            .object([m("camelot", .string(e.camelot)), m("key", .string(e.key)), m("scale", .string(e.mode)),
                     m("r", J.round(e.r, 3)), m("margin", J.round(e.margin, 3))])
        }
        func window(_ w: WindowKey?) -> J {
            guard let w else { return .null }
            return .object([m("camelot", .string(w.camelot)), m("r", J.round(w.estimate.r, 3)),
                            m("song_key_r", J.round(w.songKeyR, 3)), m("gain", J.round(w.gain, 2)),
                            m("flag", .bool(w.flag))])
        }
        return .object([
            m("engine", .string("\(Analysis.engineFamily)-\(Analysis.engineVersion)")),
            m("family", .string(Analysis.engineFamily)), m("version", .string(Analysis.engineVersion)),
            m("sha256", .string(source.sha256)), m("bytes", .int(source.bytes)),
            m("format", .string(source.format)), m("source_sr", .int(source.sampleRate)),
            m("source_channels", .int(source.channels)),
            m("madmom_would_run", J.text(madmomWouldRun)),
            m("vocal_unknown", .bool(vocalUnknown)), m("vocal_model", J.text(vocalModel)),
            m("vocal", vocalBlock()),
            m("vocal_structure", vocalStructureBlock()),
            m("hooks", hooksBlock()),
            m("key", .object([
                m("estimator", .string("fft-chroma-edma")), m("whole", estimate(key.whole)),
                m("votes", .object(keyVote.votes.map { m($0.name, estimate($0.estimate)) })),
                m("vote", .string(keyVote.camelot)), m("vote_rule", .string(keyVote.rule)),
                m("song_key", .string(key.songKey)), m("mix_in", window(key.mixIn)), m("mix_out", window(key.mixOut)),
                m("segments", .array(key.segments.map {
                    .array([.number($0.start), .string($0.camelot), .number($0.meanR)])
                })),
            ])),
        ])
    }

    /// The vocal tagger's detail, null without one: its model and rule, its frame timing, its other per-bar series
    /// as `<name>_prob` (YAMNet: `singing_prob`, `rapping_prob`, `choir_prob`, `speech_prob`, `music_prob`; 3 decimals,
    /// as `per_bar.vocal_prob`), the four readings of its class scores (`readingsMembers`),
    /// a second model's opinion if there is one, the style vector (4 decimals) and the tagger's own step times.
    func vocalBlock() -> JSONValue {
        typealias J = JSONValue
        func m(_ k: String, _ v: J) -> J.Member { J.Member(k, v) }
        guard let v = vocal else { return .null }
        var members = [
            m("model", J.text(vocalModel)), m("rule", J.text(v.rule)),
            m("patch_hop_s", J.round(v.frameHopSeconds, 4)), m("patch_centre_s", J.round(v.frameCentreSeconds, 4)),
            m("n_patches", .int(v.frameCount)),
        ]
        for name in v.seriesPerBar.keys.sorted() {
            members.append(m("\(name)_prob", J.roundList(v.seriesPerBar[name]!, 3)))
        }
        members += readingsMembers(v.readings)
        members.append(m("second_opinion", v.secondOpinion.map {
            .object([m("model", .string($0.model)), m("mean_prob", J.round($0.meanProbability, 4)),
                     m("per_bar", J.roundList($0.perBar, 3))])
        } ?? .null))
        members.append(m("style_model", J.text(v.style == nil ? nil : v.styleModel)))
        members.append(m("style", v.style.map { J.roundList($0, 4) } ?? .null))
        members.append(m("timing_s", .object(v.stages.map { m($0.name, J.round($0.seconds, 3)) })))
        return .object(members)
    }

    /// Decimals the readings are written to: more than `vocal_prob`'s 3, since on a full mix most bars of `max11` and
    /// `voice_sum` lie below 0.02, where 3 decimals leave a score a few dozen steps; all four alike, so they compare
    /// like with like.
    public static let readingsDecimals = 5

    /// The readings' members of `deckie.vocal` (null each without readings): `readings`, the four per-bar series by
    /// name in `VocalReadings.names`' order (`readingsDecimals` decimals); `readings_classes`, for each reading the
    /// classes it read (name and column) and the names asked for that the model does not have (`voice_vs_music`
    /// lists its voice and music classes apart); `readings_note`, one sentence a reading.
    func readingsMembers(_ r: VocalReadings?) -> [JSONValue.Member] {
        typealias J = JSONValue
        func m(_ k: String, _ v: J) -> J.Member { J.Member(k, v) }
        guard let r else { return [m("readings", .null), m("readings_classes", .null), m("readings_note", .null)] }
        func list(_ cs: [VocalReadings.Class]) -> J {
            .array(cs.map { .object([m("name", .string($0.name)), m("index", .int($0.index))]) })
        }
        func names(_ ns: [String]) -> J { .array(ns.map { .string($0) }) }
        let c = r.classes
        let voice: J = .object([m("classes", list(c.voice)), m("missing", names(c.missingVoice))])
        return [
            m("readings", .object(r.series.map { m($0.name, J.roundList($0.values, Self.readingsDecimals)) })),
            m("readings_classes", .object([
                m("max11", .object([m("classes", list(c.max)), m("missing", names(c.missingMax))])),
                m("voice_sum", voice),
                m("voice_logit_sum", voice),
                m("voice_vs_music", .object([m("voice", list(c.voice)), m("music", list(c.music)),
                                             m("missing", names(c.missingVoice + c.missingMusic))])),
            ])),
            m("readings_note", .object(VocalReadings.notes.map { m($0.name, .string($0.note)) })),
        ]
    }

    /// The vocal structure (memo Q's items A1 to A6), null without a tagger: the crate's proposed `vocal_structure`
    /// block (`crateVocalStructure()`), its fields in the order crate-format.md lists them and its values as rounded
    /// there.
    func vocalStructureBlock() -> JSONValue {
        typealias J = JSONValue
        func m(_ k: String, _ v: J) -> J.Member { J.Member(k, v) }
        guard let vs = crateVocalStructure() else { return .null }
        let rule = vs.rule
        func stretch(_ start: Int, _ end: Int) -> J { .object([m("start_bar", .int(start)), m("end_bar", .int(end))]) }
        return .object([
            m("source", .string(vs.source)), m("frame_hop_s", .number(vs.frameHopS)),
            m("lattice_phase_bar", .int(vs.latticePhaseBar)),
            m("spans", .array(vs.spans.map {
                .object([m("start_bar", .int($0.startBar)), m("start_beat", .int($0.startBeat)),
                         m("start_s", .number($0.startS)), m("end_bar", .int($0.endBar)), m("end_beat", .int($0.endBeat)),
                         m("end_s", .number($0.endS)), m("start_offset_beats", .int($0.startOffsetBeats)),
                         m("end_offset_beats", .int($0.endOffsetBeats))])
            })),
            m("first", vs.first.map {
                .object([m("bar", .int($0.bar)), m("beat", .int($0.beat)), m("time_s", .number($0.timeS)),
                         m("pickup", .bool($0.pickup))])
            } ?? .null),
            m("last", vs.last.map {
                .object([m("bar", .int($0.bar)), m("beat", .int($0.beat)), m("time_s", .number($0.timeS))])
            } ?? .null),
            m("intro_free_bars", .int(vs.introFreeBars)), m("intro_kind", .string(vs.introKind)),
            m("outro_free_bars", .int(vs.outroFreeBars)), m("outro_kind", .string(vs.outroKind)),
            m("free_gaps", .array(vs.freeGaps.map {
                .object([m("start_bar", .int($0.startBar)), m("end_bar", .int($0.endBar)), m("bars", .int($0.bars))])
            })),
            m("exposed_proxy", .array(vs.exposedProxy.map { stretch($0.startBar, $0.endBar) })),
            m("rule", .object([
                m("threshold", .number(rule.threshold)), m("score_p95", .number(rule.scoreP95)),
                m("threshold_fraction", .number(rule.thresholdFraction)),
                m("threshold_floor", .number(rule.thresholdFloor)), m("bridge_beats", .int(rule.bridgeBeats)),
                m("min_span_beats", .int(rule.minSpanBeats)), m("pickup_beats", .int(rule.pickupBeats)),
                m("min_gap_bars", .int(rule.minGapBars)), m("kind_bars", .int(rule.kindBars)),
                m("beat_density_ratio", .number(rule.beatDensityRatio)),
                m("bright_margin_db", .number(rule.brightMarginDb)),
                m("exposed_low_drop_db", .number(rule.exposedLowDropDb)),
                m("exposed_density_ratio", .number(rule.exposedDensityRatio)),
                m("exposed_min_bars", .int(rule.exposedMinBars)),
            ])),
        ])
    }

    /// The hook candidates (memo Q's item B7), null without a tagger: the crate's proposed `hooks` block
    /// (`crateHooks()`), fields in crate-format.md's order, values as rounded there.
    func hooksBlock() -> JSONValue {
        typealias J = JSONValue
        func m(_ k: String, _ v: J) -> J.Member { J.Member(k, v) }
        guard let h = crateHooks() else { return .null }
        let rule = h.rule
        return .object([
            m("source", .string(h.source)), m("lattice_phase_bar", .int(h.latticePhaseBar)),
            m("candidates", .array(h.candidates.map {
                .object([m("start_bar", .int($0.startBar)), m("end_bar", .int($0.endBar)),
                         m("strength", .number($0.strength)), m("sung", .bool($0.sung)),
                         m("repetition", .number($0.repetition)), m("loudness_score", .number($0.loudnessScore)),
                         m("vocal_density", .number($0.vocalDensity)), m("repeat_start_bar", .int($0.repeatStartBar))])
            })),
            m("rule", .object([
                m("lengths_bars", .array(rule.lengthsBars.map { .int($0) })), m("step_bars", .int(rule.stepBars)),
                m("weight_repetition", .number(rule.weightRepetition)),
                m("weight_loudness", .number(rule.weightLoudness)), m("weight_vocal", .number(rule.weightVocal)),
                m("min_repetition", .number(rule.minRepetition)), m("short_margin", .number(rule.shortMargin)),
                m("sung_share", .number(rule.sungShare)), m("max_hooks", .int(rule.maxHooks)),
            ])),
        ])
    }

    /// The lab's `local_tempo` block (mixer/local_tempo.py, `compute`), keys in its order; the values are already
    /// rounded as the lab rounds them.
    static func labJSON(_ lt: LocalTempo) -> JSONValue {
        typealias J = JSONValue
        func m(_ k: String, _ v: J) -> J.Member { J.Member(k, v) }
        func window(_ w: LocalTempo.Window?) -> J {
            guard let w else { return .null }
            return .object([m("bpm", .number(w.bpm)), m("bpm_raw", .number(w.bpmRaw)), m("mult", .number(w.mult)),
                            m("n_beats", .int(w.nBeats)), m("resid_ms", .number(w.residMs)), m("t0", .number(w.t0)),
                            m("t1", .number(w.t1))])
        }
        return .object([
            m("ref_bpm", .number(lt.refBpm)),
            m("first30", window(lt.first30)), m("last30", window(lt.last30)),
            m("mix_in", window(lt.mixIn)), m("mix_out", window(lt.mixOut)),
            m("grid_dev_in_ms", J.num(lt.gridDevInMs)), m("grid_dev_out_ms", J.num(lt.gridDevOutMs)),
            m("bpm_in", .number(lt.bpmIn)), m("in_trusted", .bool(lt.inTrusted)), m("in_rule", .string(lt.inRule.rawValue)),
            m("bpm_out", .number(lt.bpmOut)), m("out_trusted", .bool(lt.outTrusted)),
            m("out_rule", .string(lt.outRule.rawValue)),
            m("drift_pct", .number(lt.driftPct)),
            m("profile", .array(lt.profile.map { .array([.number($0.start), .number($0.bpm), .bool($0.trusted)]) })),
            m("range_pct", J.num(lt.rangePct)), m("untrusted_segments", .int(lt.untrustedSegments)),
            m("steady_in_s", J.num(lt.steadyInS)), m("steady_in_bar", J.integer(lt.steadyInBar)),
            m("steady_out_s", J.num(lt.steadyOutS)), m("steady_out_bar", J.integer(lt.steadyOutBar)),
            m("first_downbeat_in_s", J.num(lt.firstDownbeatInS)), m("first_downbeat_out_s", J.num(lt.firstDownbeatOutS)),
            m("tempo_change", .bool(lt.tempoChange)), m("transition_track", .bool(lt.transitionTrack)),
            m("in_half_time", .bool(lt.inHalfTime)), m("out_half_time", .bool(lt.outHalfTime)),
            m("intro_no_steady_beat", .bool(lt.introNoSteadyBeat)),
            m("outro_no_steady_beat", .bool(lt.outroNoSteadyBeat)),
        ])
    }
}
