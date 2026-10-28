#!/usr/bin/env python3
"""Write a tiny ONNX model for the tests of DeckieInference's ONNX Runtime wrapper, so they need only the library,
not the 82 MB beat tracker. Needs the onnx package (and onnxruntime, to check it); see DEPENDENCIES.md section 7.

  python3 core/Tools/make_onnx_fixture.py        # from anywhere

The model, "affine": inputs x (float32, shape [n, 3], n free) and bias (float32, shape [3]); outputs
scaled = 2 x (shape [n, 3]) and shifted = 2 x + bias (shape [n, 3]). Opset 17, IR version 8.

Output: core/Tests/DeckieInferenceTests/Fixtures/affine.onnx (a few hundred bytes; the same bytes on every run)
"""
import os

import numpy as np
import onnx
from onnx import TensorProto, helper
import onnxruntime as ort

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "Tests", "DeckieInferenceTests", "Fixtures", "affine.onnx")


def main():
    two = helper.make_tensor("two", TensorProto.FLOAT, [], [2.0])
    graph = helper.make_graph(
        [helper.make_node("Mul", ["x", "two"], ["scaled"]), helper.make_node("Add", ["scaled", "bias"], ["shifted"])],
        "affine",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, ["n", 3]),
         helper.make_tensor_value_info("bias", TensorProto.FLOAT, [3])],
        [helper.make_tensor_value_info("scaled", TensorProto.FLOAT, ["n", 3]),
         helper.make_tensor_value_info("shifted", TensorProto.FLOAT, ["n", 3])],
        initializer=[two],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)], producer_name="deckie")
    model.ir_version = 8
    onnx.checker.check_model(model)
    data = model.SerializeToString(deterministic=True)
    sess = ort.InferenceSession(data, providers=["CPUExecutionProvider"])
    x = np.arange(6, dtype=np.float32).reshape(2, 3)
    scaled, shifted = sess.run(None, {"x": x, "bias": np.array([0.5, -1, 10], dtype=np.float32)})
    assert np.array_equal(scaled, 2 * x) and np.array_equal(shifted, 2 * x + [0.5, -1, 10])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(data)
    print(f"wrote {OUT} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
