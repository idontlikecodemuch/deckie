# The pinned model files, for publication

This branch exists to carry the two pinned ONNX exports to the release `models-1` (Christopher's approval, Oct 29,
2026): the pinned Beat This! bytes exist only on the machine that exported them (the export is not reproducible
byte for byte across torch builds, DEPENDENCIES.md section 7), and this session may not create releases directly,
so `.github/workflows/models-publish.yml` checks the files against the hashes pinned in the export scripts and
publishes them with the workflow's own token. The files are not part of the code branches; `core/.models/` stays
ignored there and is filled by `core/Tools/fetch-models.sh`.
