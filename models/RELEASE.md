The two model files Deckie's engine runs through ONNX Runtime, exported once and pinned by hash so that every
machine (the Linux and Windows builds, the Mac bench, CI) uses the exact graphs the parity tests were run on,
instead of re-exporting with whatever torch or TensorFlow it has.

- `beat_this_final0.onnx`, 82,098,829 bytes, SHA-256 `f1d932049c9344ae3b1192673ef895c97807ba59fc1aa3d4e8d3d17c43c9b8dc`:
  Beat This! (Foscarin, Schlüter, Widmer, ISMIR 2024), checkpoint `final0`, exported by `core/Tools/export_beat_this.py`
  with its pinned requirements. Licence MIT (the authors' repository, `LICENSE`); training sets recorded in
  DEPENDENCIES.md, section 7.
- `yamnet.onnx`, 14,938,528 bytes, SHA-256 `96bb0dc54745dbbc95ef3f289830c94eec92a6914c4ab711a821bc8aa1c93cfd`:
  YAMNet (Google, tensorflow/models, commit a6e25e2), exported by `core/Tools/export_yamnet.py` with its pinned
  requirements. Licence Apache 2.0; trained on AudioSet (labels CC BY 4.0; attribution in DEPENDENCIES.md, section 8).

Both licences permit redistribution of the weights with their notices, which DEPENDENCIES.md carries. Each file has a
`.sha256` beside it. `core/Tools/fetch-models.sh` fetches them by these hashes; the export scripts remain the fallback
and the way to make the next version. Recorded in DEPENDENCIES.md, sections 7 and 8, and in the PC and Linux track's
status log, entry 16.
