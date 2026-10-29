# Research O: alternatives for the vocal signal and the model runtime

Dated Oct 28, 2026. Evidence only, no decisions. Builds on N (vocal tagger), J (vocal tool) and M sections 3.1 to 3.3.
Tags: [2nd] = not read from a primary source, with where it came from; [inf] = my inference. Not legal advice.
"Weights" = the trained numbers inside a model. "ONNX" = a common file format for models. "MACs" = multiply-adds, a
rough measure of compute. "mAP" = a 0-to-1 accuracy score on AudioSet's 527 sound labels. Fetches were by page reader,
so licence text I could not see in full is marked "page shows only the name".

## Summary

**Area 1 (vocal signal).** Nothing found beats the current pick on licence and speed together, and the check turned up
two problems with it. (a) EfficientAT's README says "All models available are pre-trained on ImageNet by default"; the
ImageNet terms allow "non-commercial research and educational purposes" only [2nd: image-net.org FAQ, via search; the
page itself would not load], so under the fixed data rule mn10_as is in doubt. PANNs MobileNetV1/V2 (code MIT,
checkpoints CC BY 4.0, read on Zenodo) or YAMNet (Apache 2.0, trained on AudioSet alone) fill the same slot without that
issue. (b) Spleeter's weights are called MIT only in the JOSS paper; the LICENSE file, README and v1.4.0 release page say
nothing about models, and the paper says the training data is "Deezer's internal datasets" that "we cannot release ...
for copyright reasons" - it does not say Deezer owns the recordings. Every separator that has a stated weight licence
(Open-Unmix umxhq MIT, Demucs, SCNet, MDX-Net, RoFormer weights) was trained on MUSDB18-HQ, whose Zenodo licence reads
"Other (Non-Commercial)", so none qualifies. No singing-voice-detection checkpoint with a licence exists. One
weight-free route exists (vibrato and pitch rules, Regnier and Peeters 2009: 76.8% frame F-measure against 77.4% for a
trained baseline on their 90 songs) - lower accuracy, zero licence risk, a fallback not a replacement.

**Area 2 (runtime).** ONNX Runtime's ThirdPartyNotices.txt (all 333,679 characters read) names exactly one MPL 2.0
component, Eigen; no LGPL, GPL, AGPL or NonCommercial component appears. It also lists the "JSON License" ("shall be used
for Good, not Evil", json.org / JSON_checker), which is off our licence list. The CMake files show no option to build
without Eigen (the fetch runs unconditionally), and ORT applies its own patch to Eigen's source, which matters for the
"MPL unmodified" rule. Alternatives that avoid Eigen exist but each costs something: ncnn (BSD-3, C API, Linux and
Windows x64 packages, release 20261020) is the closest drop-in; LiteRT/TFLite does carry Eigen (its CMake requires
Eigen3); OpenVINO is clean in the part of its notices I read but is Intel-tuned and large [inf]; ggml, tract and rten
have no ONNX-model C API of the kind needed. Nothing clearly beats ONNX Runtime; ncnn is the one to test if Eigen is
unacceptable.

## 1. Vocal signal

Rules applied: code, weights and training data each checked; "data NC" = out; "data unknown" = out unless the trainer
owns it. Speeds are estimates from published compute unless a source is named.

| Candidate | Code | Weights | Training data | CPU speed (4-min track) | Size | ONNX | Verdict |
|---|---|---|---|---|---|---|---|
| Spleeter 2stems (pick) | MIT | MIT only in paper | Deezer internal, rights unstated | 2-5 s [inf, from N] | ~39 MB fp32 [N] | sherpa-onnx (Apache 2.0) | Keep, but data rights open |
| EfficientAT mn10_as (pick) | MIT | none stated | ImageNet then AudioSet | <1 s [inf] | 4.88M params, 0.54 G MACs | not read; PyTorch export easy [inf] | ImageNet step is a flag |
| PANNs MobileNetV1/V2 | MIT | CC BY 4.0 | AudioSet | <1 s [inf] | 23.6 / 20.8 MB | community [inf] | Best swap for EfficientAT |
| YAMNet | Apache 2.0 | not stated on page | AudioSet | ~1-2 s [inf] | 3.7M weights | exists (N) | Clean, 521 classes |
| CED tiny/mini | GPL-3 | Apache 2.0 (HF card) | AudioSet + teacher ensemble | <1 s [inf] | 5.5M / 9.6M params | yes, in repo | Code/weight conflict; user rule says out |
| BEATs / AST / PaSST / HTS-AT | MIT? / BSD-3 / Apache / MIT | none stated | AudioSet (+ImageNet init for AST) | slow (transformers) [inf] | ~30-90M params | no | Out: unlicensed weights, heavy |
| Open-Unmix umxhq / umx | MIT | MIT (umxhq, Zenodo) | MUSDB18-HQ / MUSDB18 | 5-15 s [inf, N] | ~35 MB [inf] | exists (N) | Out: data non-commercial |
| umxl | MIT | CC BY-NC-SA 4.0 | private stems | - | - | - | Out |
| Demucs / HTDemucs | MIT | none separate | MUSDB-HQ (+800 songs) | README: ~1.5x track length on CPU | large | demucs.onnx (N) | Out: data, speed; repo archived |
| MDX-Net (KUIELab) | MIT | not stated | MUSDB18-HQ | needs GPU per README | n/a | n/a | Out |
| SCNet (starrytong) | MIT | none stated (Google Drive) | MUSDB | not stated | not stated | no | Out |
| BS/Mel-Band RoFormer | MIT (lucidrains) | none stated | MUSDB-only or private | GPU-class [inf] | large | no | Out |
| Schluter SVD (ismir2015/2018) | MIT | none shipped | Jamendo corpus (licence not stated) | small CNN, fast [inf] | tiny | n/a | Recipe only |
| Vibrato/pitch rules | published method | none | n/a | seconds [inf] | none | n/a | Weight-free fallback |

### Notes per candidate

**Spleeter.** LICENSE file: "MIT License", "Copyright (c) 2019-present, Deezer SA." - no word on models
(https://raw.githubusercontent.com/deezer/spleeter/master/LICENSE). README: "The code of Spleeter is MIT-licensed"; no
licence for the pretrained models; it also carries a line telling automated agents not to ask the maintainers about
weight licensing (I did not contact them) (https://github.com/deezer/spleeter). Release v1.4.0 ("First public release",
2, 4 and 5 stem models; 9 assets, names not shown) has no licence text
(https://github.com/deezer/spleeter/releases/tag/v1.4.0). Paper: "source code and pre-trained models are available on
github and distributed under a MIT license"; "The models were trained on Deezer's internal datasets"; "we cannot release
the training data for copyright reasons"
(https://raw.githubusercontent.com/openjournals/joss-papers/master/joss.02154/10.21105.joss.02154.jats). Reading:
Deezer states MIT for the weights in a peer-reviewed paper (a clear grant); whether Deezer owns or licensed the
recordings it trained on is not stated, which is the "trainer must be the rights-holder" test. The sherpa-onnx
conversion scripts exist (https://github.com/k2-fsa/sherpa-onnx/tree/master/scripts/spleeter) but the page shows only
file names; its docs page for Spleeter returned 404, so converted-model licence and size are [2nd: N].

**EfficientAT.** LICENSE: "MIT License", "Copyright (c) 2022 Florian Schmid"
(https://raw.githubusercontent.com/fschmid56/EfficientAT/main/LICENSE). README: "Pre-trained models are available in
the Github Releases"; "All models available are pre-trained on ImageNet [9] by default" then trained on AudioSet;
mn10_as: 4.88M parameters, 0.54B MACs, 47.1 mAP; no speed figures given
(https://github.com/fschmid56/EfficientAT). No separate checkpoint licence found. Which ImageNet weights seed it is
not said. Only variants named `*_no_im_pre` skip ImageNet.

**AudioSet.** "The dataset is made available by Google Inc. under a Creative Commons Attribution 4.0 International (CC
BY 4.0) license"; the ontology (class names) is "Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA
4.0)"; the audio is not licensed there (the page offers only 128-number features)
(https://research.google.com/audioset/download.html). So: label names are ShareAlike (the class word "Singing" in our
output is hard to call a derivative, but ShareAlike is on the never list), and the clips are YouTube videos under their
makers' rights. Google is not the rights-holder of the clips, so strict reading of the data rule also touches
YAMNet, PANNs, CED and EfficientAT. N chose to accept this; it is Chris's call.

**PANNs.** Code "MIT license" (https://github.com/qiuqiangkong/audioset_tagging_cnn). Checkpoints: Zenodo record 3987831
licence "Creative Commons Attribution 4.0 International"; MobileNetV1 mAP 0.389, 23.6 MB; MobileNetV2 0.383, 20.8 MB;
Cnn14 0.431, 327 MB; Cnn10 25 MB (https://zenodo.org/records/3987831). Trained on AudioSet (from scratch [inf]). No
speed figures on the page. Accuracy below EfficientAT (0.383 vs 0.471).

**YAMNet.** "the classifier has 3.7M weights and performs 69.2M multiplies for each 960ms input frame"; 521 classes;
"We dropped the gendered versions (Male/Female) of Speech and Singing"; MobileNet v1 design, 16 kHz, 64 mel bands
(https://github.com/tensorflow/models/tree/master/research/audioset/yamnet). Page states no licence; Apache 2.0 comes
from the repo LICENSE per N [2nd]. About 35 G multiply-adds per track at 0.48 s hop [inf].

**CED.** README: GPL-3.0 code, LICENSE text is GPLv3 (https://raw.githubusercontent.com/RicherMans/CED/main/LICENSE);
sizes tiny 5.5M, mini 9.6M, small 22M, base 86M; ONNX export script included; trained with teacher logits from an
ensemble (https://github.com/RicherMans/CED). Model card header "License: apache-2.0", 48.1 mAP on AS-2M
(https://huggingface.co/mispeech/ced-tiny). Code and weights disagree; the teacher models' licences are unread.

**Transformers.** AST: BSD-3-Clause code, weights on Dropbox with no terms, uses ImageNet pretrained option
(https://github.com/YuanGongND/ast). PaSST: Apache-2.0 code, checkpoints in releases with no stated terms
(https://github.com/kkoutini/PaSST). HTS-AT: MIT, 30M parameters, no checkpoint terms
(https://github.com/RetroCirce/HTS-Audio-Transformer). BEATs: "licensed under the license found in the LICENSE file",
checkpoints on OneDrive, no terms (https://github.com/microsoft/unilm/tree/master/beats). All fail on unstated weights.

**Separators.** Open-Unmix: code MIT; umxl "only licensed for non-commercial use (CC BY-NC-SA 4.0)"; umxhq/umx
"trained on MUSDB18-HQ" / "MUSDB18", page states no weight licence
(https://github.com/sigsep/open-unmix-pytorch); Zenodo lists umxhq as "MIT License"
(https://zenodo.org/records/3370489). MUSDB18-HQ: licence "Other (Non-Commercial)", "should not be used for any
commercial purpose without the express permission of the copyright holders"; parts from MedleyDB CC BY-NC-SA 4.0
(https://zenodo.org/records/3338373). Demucs: "released under the MIT license"; htdemucs "trained on the MUSDB HQ
dataset + an extra training dataset of 800 songs"; CPU "roughly equal to 1.5 times the duration of the track"; "archived
by the owner on Jan 1, 2025" (https://github.com/facebookresearch/demucs). ZFTurbo training repo: MIT code, models
"trained only on MUSDB18HQ" or unstated, no weight licences
(https://github.com/ZFTurbo/Music-Source-Separation-Training,
https://github.com/ZFTurbo/Music-Source-Separation-Training/blob/main/docs/pretrained_models.md). Mel-Band RoFormer
vocal model: no LICENSE file, dataset "contributed" by named people, terms unstated
(https://github.com/KimberleyJensen/mel-band-roformer-vocal-model). BS-RoFormer: MIT code, no weights
(https://github.com/lucidrains/BS-RoFormer). SCNet: MIT code, checkpoint "trained on the MUSDB dataset"
(https://github.com/starrytong/SCNet). MDX-Net: MIT code, no weight statement, needs four GPUs to train
(https://github.com/kuielab/mdx-net). Demucs v3 light variants: not found on the README.

**Singing-voice detection.** Schluter's repos are MIT but "None are provided" as weights; you train on the Jamendo
corpus, whose own terms the README does not state (https://github.com/f0k/ismir2015, https://github.com/f0k/ismir2018).
Other repos (kyungyunlee, Raylogic) showed no licence in search results [2nd]. Training our own small CNN on
CC-licensed music is the N fallback.

**Weight-free methods.** Regnier and Peeters (ICASSP 2009) detect singing from vibrato and tremolo of tracked partials:
76.8% frame F-measure vs 77.4% for a trained MFCC baseline on a 90-song set; thresholds were tuned on labelled data
(http://recherche.ircam.fr/anasyn/peeters/ARTICLES/Regnier_2009_ICASSP_SingingVibrato.pdf, figures from search
summary [2nd]). Search also showed US patent documents on vibrato detection (unread; could matter). Rocamora's thesis
builds pitch salience without training (https://www.fing.edu.uy/sites/default/files/biblio/9451/singing%20voice%20detection%20in%20polyphonic%20music_2011.pdf,
snippet only [2nd]). Tooling would be our own code on the engine's FFT; libraries I did not verify: librosa (ISC [inf]),
Essentia's MELODIA (AGPL [inf], would be out). Expect weaker accuracy on sampled or chopped vocals [inf].

## 2. Model runtime

Binary sizes below are mostly unverified; the pages I could read gave few figures.

| Runtime | Licence / bundled | C API | Linux + Windows x64 | Size | Ops (attention, conv, transposed conv, depthwise) | Maintenance | Verdict |
|---|---|---|---|---|---|---|---|
| ONNX Runtime (pick) | MIT; Eigen MPL 2.0 (patched) | yes | yes | zip 55 MB (1.16.1) [2nd] | full ONNX [inf] | v1.31.1, 26 Oct; Microsoft | Keep; Eigen caveat |
| LiteRT / TFLite | Apache 2.0; TFLite build needs Eigen | C++ SDK page; C API [2nd] | prebuilt 2.3.1 both | not found | TFLite op set, conversion needed [inf] | v2.3.2, 26 Oct; Google | Eigen likely present |
| ncnn | BSD-3; zlib/BSD parts | yes | ubuntu + windows x64 zips | not found | via pnnx/ONNX converter, ops unread | tag 20261020; Tencent | Best Eigen-free test |
| MNN | Apache 2.0 | not on page | AVX2/AVX512 CPU | ~800 KB Android core | unread | 3.6.1; Alibaba | Unclear C API |
| OpenVINO | Apache 2.0; no MPL in 100k chars read | yes | Windows x64 yes | not found | ONNX import, wide | Intel | Heavy, Intel-tuned |
| ggml | MIT | C library, hand-built graphs | portable | small [inf] | no ONNX loader | ggml-org | Rewrite models |
| tract | Apache 2.0 or MIT | none | workstation | n/a | ONNX, count unstated | Sonos | Needs C shim |
| rten | Apache 2.0 or MIT | none | AVX2/AVX-512 | n/a | "most standard ONNX operators" | one owner | Needs C shim |
| TVM / IREE | Apache 2.0 (IREE + LLVM exception) | not on pages | unstated | none stated | compile ahead | active | Heavy toolchain |
| ExecuTorch | BSD | C++ | Windows x86-64 wheels | right-sizable | PyTorch export | Meta | C++ only |

### ONNX Runtime notices
Source: https://raw.githubusercontent.com/microsoft/onnxruntime/main/ThirdPartyNotices.txt, read in four slices. Listed:
BSD/MIT/Apache/Boost/zlib/ISC/HPND/public-domain components (protobuf, zlib, onnx, oneDNN, XNNPACK, abseil, re2, Dawn,
KleidiAI, mimalloc and so on); LLVM under the NCSA licence; Mbed TLS "dual-licensed with GPL-2.0-or-later" but taken
as Apache 2.0; JSON License (json.org). MPL: Eigen only. This file covers the whole repository (training, JS, other
accelerators), not the CPU build alone, and says nothing about what is test-only; which entries reach the shipped CPU
binary needs a symbol or build inspection [inf]. Eigen's entry quotes "This Source Code Form is subject to the terms of
the Mozilla Public License, v. 2.0."

Eigen-free build: `cmake/CMakeLists.txt` has `onnxruntime_USE_PREINSTALLED_EIGEN` (changes where Eigen comes from, not
whether), `onnxruntime_DONT_VECTORIZE` ("Do not vectorize operations in Eigen") and `EIGEN_USE_THREADS` set on every
target; `cmake/external/eigen.cmake` fetches Eigen with `PATCH_COMMAND ... ${PATCH_EIGEN_S390X}` and no off switch
(https://raw.githubusercontent.com/microsoft/onnxruntime/main/cmake/CMakeLists.txt,
https://raw.githubusercontent.com/microsoft/onnxruntime/main/cmake/external/eigen.cmake). Docs: preinstalled
packages get none of ORT's local patches, "advanced users" only
(https://onnxruntime.ai/docs/build/dependencies.html). Conclusion: no supported Eigen-free CPU build; the prebuilt
binary probably contains ORT-patched Eigen code (the patch is named for s390x but is applied at fetch [inf]), which
bears on "MPL files unmodified". A self-built ORT against stock Eigen would keep the files unmodified at some risk of
breakage. Whether MPL obligations are met by shipping Eigen's notice and offering its source is a legal question.

### Notes per candidate
**LiteRT.** "LiteRT is licensed under the Apache-2.0 License"; Linux x86_64 and Windows x86_64 CPU listed
(https://github.com/google-ai-edge/LiteRT). Prebuilt `libLiteRt.so` / `libLiteRt.dll` version 2.3.1, documented as a
C++ SDK (https://developers.google.com/edge/litert/next/cpp_sdk); a C API exists in the repo per DeepWiki [2nd:
https://deepwiki.com/google-ai-edge/LiteRT/4.1-c-api]. TFLite's CMake does `find_package(Eigen3 REQUIRED)` and links
`Eigen3::Eigen` (https://raw.githubusercontent.com/tensorflow/tensorflow/master/tensorflow/lite/CMakeLists.txt); the
LiteRT WORKSPACE lists no eigen, so the new runtime may differ from TFLite - not settled.
**ncnn.** "BSD 3-Clause"; "Pure C++ implementation with C API"; Ubuntu 22.04/24.04/26.04 and Windows packages;
release 20261020, ncnn-ubuntu.zip x86_64 only
(https://github.com/Tencent/ncnn, https://github.com/Tencent/ncnn/releases). LICENSE lists zlib (mathfun headers),
BSD-2 (squeezenet, caffe.proto), BSD-3 (android toolchain) only
(https://github.com/Tencent/ncnn/blob/master/LICENSE.txt). Model conversion tools ship in the zips; op coverage tables
are linked, not read.
**MNN.** Apache 2.0 text (https://github.com/alibaba/MNN/blob/master/LICENSE.txt); README shows a Python API, no C API;
MNN 3.6.1; Alibaba teams (https://github.com/alibaba/MNN).
**OpenVINO.** "licensed under Apache License Version 2.0"; APIs "C++, Python, C"; Windows x64 build documented
(https://github.com/openvinotoolkit/openvino, docs/dev/build_windows.md). `runtime-third-party-programs.txt`: first
100,000 of 119,227 characters show oneDNN, TBB, OpenCV, pugixml, XByak, kleidiai, ONNX Runtime and the same JSON
License; no MPL, LGPL, GPL or Eigen seen
(https://raw.githubusercontent.com/openvinotoolkit/openvino/master/licensing/runtime-third-party-programs.txt).
**ggml.** "MIT License", "Copyright (c) 2023-2026 The ggml authors"; "Plain C/C++ implementation without any
dependencies" (https://github.com/ggml-org/ggml). Models must be rebuilt by hand in code; conv op coverage unread.
**tract / rten.** Both Apache 2.0 or MIT, Rust, no C API stated; tract ONNX ops "not quantified"; rten "supports
most standard ONNX operators" (https://github.com/sonos/tract, https://github.com/robertknight/rten). A thin C wrapper
would be our own work and Swift on Windows would link a Rust library.
**TVM / IREE / ExecuTorch.** Apache-2.0 (https://github.com/apache/tvm), "Apache 2.0 License with LLVM Exceptions"
(https://github.com/iree-org/iree), "BSD licensed" with Windows x86-64 wheels and a C++ API
(https://github.com/pytorch/executorch). TVM and IREE compile each model ahead of time; none fits "any DJ drops in
a model" but they could ship fixed models.
**Idea [inf]:** XNNPACK (BSD, C API, listed in ORT's notices) can run convolution and matrix kernels directly with no
Eigen, but then we write the graph ourselves.

## Open questions
1. Spleeter: does Deezer own or hold rights to its "internal datasets"? Only the paper grants the MIT; the README and
   release page are silent. Deezer would have to say; contacting the maintainers is not something I did.
2. ImageNet: do the model weights inherit "non-commercial research" terms? The terms page itself would not load; this
   is also a legal reading, not a fact.
3. Which ImageNet weights seed EfficientAT mn10_as, and is there an AudioSet-only checkpoint? Not stated.
4. Does Chris accept AudioSet-trained weights given clips are YouTube-owned and the ontology is CC BY-SA?
5. YAMNet, PANNs and EfficientAT: real CPU time per 4-minute track and per-bar accuracy; none of the pages give
   timings. Needs a run on the Mac.
6. CED: code GPL-3 but weights Apache-2.0 on the card; teacher models' licences unread.
7. Whether ONNX Runtime's prebuilt binary contains patched Eigen files, and which notices entries actually reach the
   CPU binary; binary sizes for ORT, ncnn, LiteRT, OpenVINO.
8. LiteRT: is a C API shipped in the prebuilt, and does libLiteRt contain Eigen?
9. MNN C API; ncnn and OpenVINO operator coverage for GELU, layer norm, attention, transposed conv, depthwise conv.
10. Last 19,227 characters of OpenVINO's notices unread.
11. Patents around vibrato-based singing detection, and any permissive Jamendo-trained detector: not found.
12. BEATs' LICENSE file and checkpoint terms; Spleeter v1.4.0 asset names and sizes; sherpa-onnx's converted-model
    licence.
13. Newer light taggers (M2D, Dasheng, EAT variants): only seen in a search summary, not checked.
