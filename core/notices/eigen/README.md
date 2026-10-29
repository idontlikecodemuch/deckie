# Eigen's notice material: ONNX Runtime's two patches

Eigen (a C++ maths library, Mozilla Public License 2.0) is built into the ONNX Runtime library Deckie ships
(DEPENDENCIES.md, section 6). ONNX Runtime's build applies these two patches of its own to Eigen's source on every
platform, Microsoft's builds included; Deckie changes nothing. The MPL asks that the source of modified files be
made available, so the patches ship beside Eigen's notice in the app's acknowledgements, and the wording there is
"unmodified by Deckie; carries ONNX Runtime's two published patches (IBM Z builds; nothing compiled on Linux, Windows
or macOS differs)" (the main session's decision, Oct 29, 2026, recorded on `main` as a note on D14).

| File | Bytes | SHA-256 | What it changes |
|---|---|---|---|
| `s390x-build.patch` | 17,794 | `6d41f4504f665bc591336c668a1aa16ffc5e0f02fe9c2f9c46c6f5660b54c849` | `Eigen/src/Core/arch/ZVector/{Complex,MathFunctions,PacketMath}.h`, used only on IBM Z (s390x), and `Eigen/src/Core/RandomImpl.h`, a branch for big-endian machines only |
| `s390x-build-werror.patch` | 610 | `a1a7b0ca8382cb00542587b6bc725f59abd59ad5bb491825f7876ad6e344ef0b` | `Eigen/src/Core/arch/ZVector/PacketMath.h`, a warning fix for the same builds |

Source: `https://raw.githubusercontent.com/microsoft/onnxruntime/41d4d61f14b9c1dd0b2ccda1e9b85dd415fd0496/cmake/patches/eigen/<file>`,
the commit Microsoft's 1.31.1 archives name as their `GIT_COMMIT_ID`, fetched Oct 29, 2026, unchanged. The patches are
ONNX Runtime's own files, MIT (section 6 quotes the licence). Eigen's MPL notice itself is in ONNX Runtime's
`ThirdPartyNotices.txt` (section 6 says where), which the acknowledgements also carry. On an ONNX Runtime update,
fetch the patches again from the new commit and update this table.
