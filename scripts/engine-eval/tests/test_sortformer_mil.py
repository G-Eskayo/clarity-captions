"""The MIL text parser that rebuilds the shipped Sortformer .mlmodelc as an editable program (#271 step 2).

Pure Python: no coremltools here, so these run anywhere. The coremltools half is checked by the parity gate
(`sortformer_mil.cli parity`), which compares the rebuilt model's outputs with the shipped one's.
"""
import math

import pytest

from sortformer_mil.parse import Blob, MilParseError, parse_function, parse_literal, parse_type

HEADER = """program(1.0)
[buildInfo = dict<tensor<string, []>, tensor<string, []>>({{"coremltools-version", "9.0"}})]
{
"""


def test_types():
    assert parse_type("tensor<fp16, [1, 242, 512]>") == ("fp16", (1, 242, 512))
    assert parse_type("tensor<int32, []>") == ("int32", ())
    with pytest.raises(MilParseError):
        parse_type("list<int32>")


def test_hex_floats_are_exact():
    assert parse_literal("fp16", (), "0x1.388p+13") == 10000.0
    assert parse_literal("fp16", (), "-0x1.388p+13") == -10000.0
    assert parse_literal("fp32", (), "0x0p+0") == 0.0
    assert parse_literal("fp16", (), "0x1.5p-17") == float.fromhex("0x1.5p-17")
    assert math.isinf(parse_literal("fp32", (), "-inf"))


def test_nested_lists_bools_and_strings():
    assert parse_literal("int32", (1, 3), "[[0, 1, 2]]") == [[0, 1, 2]]
    assert parse_literal("bool", (4,), "[true, true, true, false]") == [True, True, True, False]
    assert parse_literal("bool", (), "false") is False
    assert parse_literal("string", (), '"valid"') == "valid"
    assert parse_literal("fp16", (2,), "[-0x1.fc4p-4, 0x1p-1]") == [float.fromhex("-0x1.fc4p-4"), 0.5]


def test_a_literal_must_match_its_declared_shape():
    with pytest.raises(MilParseError):
        parse_literal("int32", (3,), "[1, 2]")
    with pytest.raises(MilParseError):
        parse_literal("int32", (), "[1]")


def test_a_function_with_consts_ops_multiple_outputs_and_tuples():
    text = HEADER + """    func main<ios16>(tensor<fp32, [1, 4]> x, tensor<int32, [1]> n) {
            tensor<int32, []> var_1 = const()[name = tensor<string, []>("op_1"), val = tensor<int32, []>(-1)];
            tensor<fp32, [4, 4]> w = const()[name = tensor<string, []>("w"), val = tensor<fp32, [4, 4]>(BLOBFILE(path = tensor<string, []>("@model_path/weights/0-weight.bin"), offset = tensor<uint64, []>(64)))];
            tensor<fp32, [1, 4]> y = linear(weight = w, x = x)[name = tensor<string, []>("linear_0")];
            tensor<fp32, [1, 2]> a_0, tensor<fp32, [1, 2]> a_1 = split(axis = var_1, num_splits = var_1, x = y)[name = tensor<string, []>("a")];
            tensor<fp32, [1, 4]> z = concat(axis = var_1, interleave = var_1, values = (a_1, a_0))[name = tensor<string, []>("cat")];
        } -> (z, n);
}"""
    fn = parse_function(text)
    assert fn.opset == "ios16"
    assert fn.inputs == [("x", "fp32", (1, 4)), ("n", "int32", (1,))]
    assert fn.outputs == ["z", "n"]
    kinds = [(s.op, s.outputs) for s in fn.statements]
    assert kinds == [("const", ["var_1"]), ("const", ["w"]), ("linear", ["y"]), ("split", ["a_0", "a_1"]),
                     ("concat", ["z"])]
    assert fn.statements[0].value == -1
    assert fn.statements[1].value == Blob("weights/0-weight.bin", 64, "fp32", (4, 4))
    assert fn.statements[3].op_name == "a"
    assert fn.statements[3].output_types == [("fp32", (1, 2)), ("fp32", (1, 2))]
    assert fn.statements[4].args == {"axis": "var_1", "interleave": "var_1", "values": ("a_1", "a_0")}


def test_an_unknown_line_is_an_error_not_skipped():
    text = HEADER + """    func main<ios16>(tensor<fp32, [1]> x) {
            this is not mil;
        } -> (x);
}"""
    with pytest.raises(MilParseError):
        parse_function(text)


def test_an_undefined_argument_is_an_error():
    text = HEADER + """    func main<ios16>(tensor<fp32, [1]> x) {
            tensor<fp32, [1]> y = relu(x = nope)[name = tensor<string, []>("y")];
        } -> (y);
}"""
    with pytest.raises(MilParseError):
        parse_function(text)
