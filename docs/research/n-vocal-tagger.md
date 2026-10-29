# Research N: a vocal tagger the PC and Linux engine can ship

Dated Oct 28, 2026. Brief: a per-bar vocal probability for `DeckieEngineOSS` (`docs/architecture/pc-linux-track.md`)
to replace the lab's Essentia Discogs-EffNet voice head, which is CC BY-NC-SA (NonCommercial, ShareAlike: no
commercial use, derivatives under the same terms). Code and weights (the trained numbers a model consists of) must be
MIT, BSD, Apache 2.0, ISC, zlib, public domain or CC0; the model runs in ONNX Runtime (Microsoft's MIT engine for
models in the ONNX file format) on CPU, offline, in seconds per 4-minute track. Builds on tracks J and L. [inf] marks
inference; not legal advice. zenodo.org, huggingface.co, arxiv.org and essentia.upf.edu were unreachable from this
session; facts from them come from search results or track J and are marked (2nd).

## 1. Summary

**Recommendation: two small models with explicit permissive weight licences.**
1. **Vocal: Spleeter's 2-stem vocal U-Net (Deezer), read as vocal-stem energy per bar.** Code and weights MIT ("source
   code and pre-trained models are ... distributed under a MIT license"), trained on Deezer's own catalogue. An ONNX
   export exists in sherpa-onnx (Apache 2.0). About 2 to 5 s per track [inf]. A stem hears the sampled and chopped
   vocals taggers miss (track J, Call on Me). Corrects track J, which found no weight licence and no route off TF1.
2. **Timbre embedding plus a second "Singing" opinion: EfficientAT mn10_as.** MIT code and weights, 4.9M parameters,
   under 1 s per track [inf]. YAMNet (Apache 2.0) is the drop-in alternative.

**Runner-up, one model for both: musicnn** (ISC code and weights), the closest match to the lab's design (a tiny music
tagger with vocal tags and a music embedding, under 1 s), held back because it was trained on MagnaTagATune, whose
audio is CC BY-NC-SA. Open question 1 decides it. **Out:** Essentia models, umxl, MERT, MuQ (NonCommercial weights);
CED code (GPL-3); singing-voice-detection checkpoints (none licensed); HTDemucs on time (1 to 4 min per track).

## 2. What the slot must produce

The lab's EffNet gives, per patch of about 1 s at 16 kHz, a 1280-number embedding (a vector describing how the audio
sounds) and a voice probability, averaged into bars (`mixer/analyze.py` 575 to 595); the mean embedding feeds
`score.py`'s timbre term (weight 0.12) as a percentile rank of cosine similarity. Needed: a 0-to-1 series at bar
resolution (a bar is about 2 s at 120 BPM), recalibrated on track J's listening set because 0.5, 0.6 and 0.75 were
tuned on a head averaging 0.87; and a track embedding whose pair ranking resembles the lab's (ranks, so scale-free).

## 3. Candidates

**3.1 Spleeter 2stems (Deezer), vocal stem.** A U-Net is a 12-layer convolutional encoder-decoder; here it turns a
stereo spectrogram (energy per frequency per short frame, from the STFT, the short-time Fourier transform) into a
soft mask, and mask times mix is the vocal spectrogram. Per bar: vocal over mix energy in dB, threshold from the
listening set. Code: "MIT License", "Copyright (c) 2019-present, Deezer SA." (deezer/spleeter LICENSE). Weights: the
JOSS paper, "source code and pre-trained models are available on github and distributed under a MIT license"; "The
models were trained on Deezer's internal datasets"; "we cannot release the training data for copyright reasons".
They are v1.4.0 release assets of the same repository; the README states only "The code of Spleeter is MIT-licensed"
and asks automated agents not to raise weight licensing with the maintainers, so the paper is the statement to cite.
Cost: 44.1 kHz, 4096-point STFT, hop 1024, 1024 bins (to about 11 kHz), 11.9 s splits; by layer count about 9.8M
parameters per stem (39 MB fp32, about 10 MB int8, i.e. 8-bit weights) and 6 G MACs per split (a MAC is a multiply
plus an add), about 130 G per track for vocals: 2 to 5 s on a 4 to 8-core laptop [inf]. ONNX: sherpa-onnx
`scripts/spleeter/` ("Apache License, Version 2.0, January 2004") goes TF checkpoint, frozen graph, PyTorch, ONNX at
opset 13 (the operator version), writing separate `vocals.onnx` and `accompaniment.onnx` in fp32, int8 and fp16. The
STFT stays outside, which suits our engine (PocketFFT); check parity against TensorFlow. Timbre: no. Inactive project.

**3.2 EfficientAT (CP-JKU), AudioSet tagger and embedding.** AudioSet is Google's 2M YouTube clips labelled with 527
sound classes, incl. "Singing", "Male singing", "Female singing", "Rapping", "Choir", "Speech"; `preds, features =
model(spec)` also returns the embedding. Per bar: 2 s windows at 1 s hop (trained on 10 s; measure it). Code: "MIT
License", "Copyright (c) 2022 Florian Schmid"; weights "available in the Github Releases" of the same repository, no
separate licence; AudioSet labels CC BY 4.0, audio under each video's copyright (2nd). 32 kHz, 128 mel bands (a
pitch-shaped frequency scale); mn04_as 0.98M parameters, 0.11 G MACs per 10 s, mn10_as 4.88M, 0.54 G; AudioSet mAP
(mean average precision) 43.2 and 47.1; about 26 G MACs per track for mn10, under 1 s [inf]. ONNX: none published;
standard MobileNetV3, opset 14 or later for hard-swish [inf]. Timbre: yes, general-audio, music similarity untested.
Frame-level sibling: PretrainedSED ("MIT License", "Copyright (c) 2024 Florian Schmid") ships frame_mn06 (1.62M) and
frame_mn10 (3.83M), trained on AudioSet's time-stamped "strong" labels (447 classes incl. Singing, Rapping, Choir);
no windowing, but "trained with a similar knowledge distillation procedure", i.e. taught by larger models incl.
BEATs and M2D, whose weight licences are unclear.

**3.3 YAMNet (Google).** 521 classes per 0.96 s patch at 0.48 s hop, incl. "24,/m/015lz1,Singing", "Rapping",
"Choir"; 1024-number embedding. Code: tensorflow/models LICENSE, "All files in the following folders: ... /research
... Are licensed as follows:" Apache 2.0; `yamnet.h5` is served from Google Cloud Storage, and the TF Hub/Kaggle
listing says Apache 2.0 (2nd). 3.7M weights, "69.2M multiplies for each 960ms input frame": about 1 s per track
[inf]. ONNX: community tf2onnx conversions (audiomagic/yamnet-onnx). Timbre: yes; weaker (balanced mAP 0.306).

**3.4 musicnn (MTG, Universitat Pompeu Fabra), music tagger and embedding.** 50 tags per 3 s patch, 16 kHz, 96 mel
bands. MTT models: 'vocal', 'vocals', 'singing', 'voice', 'female vocal', 'male vocal', 'choir', and 'no vocal', 'no
vocals', 'no voice'; MSD models: 'female vocalists', 'male vocalists', 'instrumental'. Per bar: a fit of positive and
negative tags on the listening set, 1 s hop. Code and weights (checkpoints in the repository): LICENSE.md, "Copyright
(c) Music Technology Group, Universitat Pompeu Fabra 2019 ... Permission to use, copy, modify, and/or distribute this
software for any purpose with or without fee is hereby granted" (ISC; setup.py `license='ISC'`). Essentia's copies
are NonCommercial (2nd); only the GitHub originals are ISC. Training data: MTT is Magnatune audio under CC BY-NC-SA; MSD
tags are Last.fm, non-commercial (both 2nd). Small, under 1 s per track [inf]. ONNX: a TF1 graph via `tf.compat.v1`;
a PyTorch port (debuglevel/musicnn-pytorch, licence unchecked) then torch.onnx, or tf2onnx on the frozen graph; no
known export. Timbre: the best fit, `penultimate` (200) or `max_pool` (753) from a music-trained network as EffNet
is; MTT is indie and classical, little pop or dance [inf].

**3.5 Open-Unmix umxhq (sigsep), vocal stem.** Per-target models; the vocals one alone suffices. Code: "MIT License",
"Copyright (c) 2019 Inria (Fabian-Robert Stöter, Antoine Liutkus)"; weights: Zenodo 3370489 "MIT License" (track J);
umxl instead: "the weights are only licensed for non-commercial use (CC BY-NC-SA 4.0)". Data: MUSDB18-HQ, "for
educational purposes only ... should not be used for any commercial purpose without the express permission of the
copyright holders" (2nd). BiLSTM (a recurrent network read both ways), vocals SDR 6.25 dB (signal-to-distortion,
higher is cleaner), sequential, 5 to 15 s per track [inf]. ONNX: edgetools/umx-hq, vocals, 17.0 MiB. Timbre: no.

**3.6 HTDemucs (Meta).** Code: "MIT License", "Copyright (c) Meta Platforms, Inc. and affiliates."; README "Demucs is
released under the MIT license", nothing separate for weights; archived Jan 1, 2025; trained on "MusDB + 800 songs".
41.4M parameters; CPU about 1.5 times track length (README), 4 min 9 s for a 4-minute song on 4 threads in
demucs.cpp (track L): 20 to 60 times over budget. ONNX: demucs.onnx ("MIT License", "Copyright (c) 2024 Sevag H")
moves the STFT out; no timings. An optional deep-analysis mode only.

**3.7 Others.** MERT: code Apache 2.0, checkpoints cc-by-nc-4.0 (2nd). MuQ: "The model weights ... are released under
the CC-BY-NC 4.0 license". MusicFM: no checkpoint licence. CLAP (LAION; contrastive language-audio pretraining, audio
embedded near matching text): "CC0 1.0 Universal" repository, larger_clap_music card apache-2.0 (2nd), but trained on
LAION-Audio-630K (Freesound clips, some NonCommercial, and BBC Sound Effects); 10 s clips; a strong timbre embedding
[inf] if question 1 allows. PANNs: "The MIT License", "Copyright (c) 2018-2020 Qiuqiang Kong"; weights "Creative
Commons Attribution 4.0 International" (track J); Cnn14 80.8M parameters, 42.2 G multiply-adds per 10 s, 10 to 30 s
per track [inf]. OpenL3: code MIT, "The model weights are made available under a Creative Commons Attribution 4.0
International (CC BY 4.0) License"; embedding only. CED: "GNU GENERAL PUBLIC LICENSE Version 3", weights tagged
apache-2.0 (2nd). Singing-voice detectors: f0k/ismir2015 and 2018 are MIT code without weights;
kyungyunlee/ismir2018-revisiting-svd has no LICENSE and trained on MedleyDB (CC BY-NC-SA); SingAlign weights CC
BY-NC. Speech activity detectors (Silero, pyannote) are another task.

## 4. Fallback: train our own tiny model

A two-class CNN on mel patches (under 0.5M parameters), 2 to 4 weeks, gated by data [inf]. Pseudo-labels (a teacher
model's output used as targets) from Spleeter's vocal energy on permissive audio keep the chain clean. Usable after
per-track filtering: FMA, 106,574 tracks (879 GiB full), metadata CC BY 4.0, audio "under the license chosen by the
artist", per track (keep CC BY, CC0, public domain); OpenMIC-2018, 20,000 10-s FMA clips, partial voice labels, CC BY
4.0, audio licences per clip; MUSAN music, 42.5 h, CC or public domain, each track vocals yes or no; Jamendo SVD, 93
CC songs with voice segments (test set); VocalSet (10.1 h solo singing) and Slakh2100 (145 h, no vocals), reported
CC BY 4.0 (unverified), for synthetic mixes. Not usable: MUSDB18-HQ, MedleyDB, DSD100, RWC, DALI, MTG-Jamendo
(non-commercial; Jamendo sued NVIDIA in June 2026, refiled in October, alleging training breached CC BY-NC).

## 5. Ranking

| # | Candidate | Vocal per bar | Timbre | Code / weights / data | CPU per track | ONNX |
|---|---|---|---|---|---|---|
| 1 | Spleeter vocals + EfficientAT mn10 | stem energy + Singing | yes | MIT / MIT / own, AudioSet | 3 to 6 s [inf] | sherpa-onnx; ours |
| 2 | musicnn MTT alone | vocal tags, 3 s | music-trained | ISC / ISC / CC BY-NC-SA | under 1 s [inf] | port, then export |
| 3 | YAMNet or frame_mn06 for EfficientAT | Singing | yes | Apache, MIT / same / AudioSet | about 1 s [inf] | community; ours |
| 4 | Open-Unmix umxhq | stem energy | no | MIT / MIT / educational only | 5 to 15 s [inf] | exists |
| 5 | HTDemucs, optional mode | best stem | no | MIT / MIT (repo) / MUSDB + 800 | 1 to 4 min | demucs.onnx |
| 6 | Own tiny CNN, fallback | bar-level | no | ours / ours / filtered CC | under 1 s [inf] | ours |

Choose on the Mac, where the audio is: track J's 40-track listening set plus the lab's strong bars (under 0.2, over
0.9); first-vocal-bar error and vocal-free intro and outro within 2 bars, sung and sampled reported apart; for timbre,
Spearman correlation (agreement of rankings) of pair similarities with the lab's EffNet over the 373 tracks.

## 6. Open questions for the main session

1. **Training data.** Accept permissive weights trained on data we could not ship? Proposed: yes when the weights'
   licence is explicit and the data has no licence forbidding commercial use (Spleeter's own catalogue; AudioSet's
   YouTube audio with CC BY labels); no when it is NonCommercial (musicnn's MTT, umxhq's MUSDB18-HQ, CLAP). This
   one call decides musicnn and CLAP.
2. **CC BY 4.0 weights (PANNs, OpenL3).** Attribution only, as permissive as MIT in practice, but not on the list.
   It adds options the recommendation does not need. No candidate is MPL.

Still open from track J: does "vocal" include sampled hooks? A stem says yes, a tagger no.

## 7. Sources

Spleeter https://github.com/deezer/spleeter (README, LICENSE, release v1.4.0); JOSS paper
https://github.com/openjournals/joss-papers/blob/master/joss.02154/10.21105.joss.02154.jats ; sherpa-onnx
https://github.com/k2-fsa/sherpa-onnx/tree/master/scripts/spleeter and its LICENSE. EfficientAT
https://github.com/fschmid56/EfficientAT (LICENSE, `inference.py`); PretrainedSED https://github.com/fschmid56/PretrainedSED
(LICENSE, release v0.0.1, `data_util/audioset_classes.py`). YAMNet https://github.com/tensorflow/models/blob/master/LICENSE ,
https://github.com/tensorflow/models/tree/master/research/audioset/yamnet , https://huggingface.co/audiomagic/yamnet-onnx .
musicnn https://github.com/jordipons/musicnn (LICENSE.md, `setup.py`, `musicnn/configuration.py`, `extractor.py`),
https://huggingface.co/debuglevel/musicnn-pytorch ; MTT https://mirg.city.ac.uk/datasets/magnatagatune/index1.html .
Open-Unmix https://github.com/sigsep/open-unmix-pytorch , https://zenodo.org/records/3370489 ,
https://huggingface.co/edgetools/umx-hq ; MUSDB18-HQ https://zenodo.org/records/3338373 . Demucs
https://github.com/facebookresearch/demucs , https://github.com/sevagh/demucs.onnx . MERT https://github.com/yizhilll/MERT ;
MuQ https://github.com/tencent-ailab/MuQ ; MusicFM https://github.com/minzwon/musicfm ; CLAP https://github.com/LAION-AI/CLAP ,
https://huggingface.co/laion/larger_clap_music , https://huggingface.co/datasets/Meranti/CLAP_freesound . PANNs
https://github.com/qiuqiangkong/audioset_tagging_cnn , https://zenodo.org/records/3987831 , https://arxiv.org/abs/1912.10211 ;
OpenL3 https://github.com/marl/openl3 ; CED https://github.com/RicherMans/CED ; SVD
https://github.com/kyungyunlee/ismir2018-revisiting-svd , https://huggingface.co/pymaster/SingAlign . Datasets: AudioSet
https://research.google.com/audioset/download.html ; FMA https://github.com/mdeff/fma ; OpenMIC-2018
https://zenodo.org/records/1432913 ; MUSAN https://arxiv.org/abs/1510.08484 ; Jamendo SVD https://zenodo.org/records/2585988 ;
VocalSet https://zenodo.org/records/1442513 ; Slakh2100 https://zenodo.org/records/4603870 ; Jamendo v. NVIDIA
https://www.digitalmusicnews.com/2026/06/23/jamendo-nvidia-lawsuit/ . Local: `mixer/analyze.py`, `mixer/score.py`,
`mixer/README.md`, `docs/architecture/pc-linux-track.md`, `docs/research/j-vocal-tool.md`, `docs/research/l-non-apple.md`.
