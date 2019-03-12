import argparse
import glob
import logging
import os
import sys
import time

import numpy as np
import onnx
import onnx.numpy_helper
import onnxruntime as rt


def load_test_data(data_dir, input_names, output_names):
    inout_values = []
    for kind, names in [('input', input_names), ('output', output_names)]:
        names = list(names)
        values = []
        for pb in sorted(glob.glob(os.path.join(data_dir, '%s_*.pb' % kind))):
            with open(pb, 'rb') as f:
                tensor = onnx.TensorProto()
                tensor.ParseFromString(f.read())
            if tensor.name in names:
                name = tensor.name
                names.remove(name)
            else:
                name = names.pop(0)
            values.append((name, onnx.numpy_helper.to_array(tensor)))
        inout_values.append(values)
    return tuple(inout_values)


def compile(symbol, target, input_names, inputs, params, opt_level):
    shape_dict = {}
    dtype_dict = {}
    for name, value in zip(input_names, inputs.values()):
        shape_dict[name] = value.shape
        dtype_dict[name] = value.dtype
    for name, value in params.items():
        shape_dict[name] = value.shape
        dtype_dict[name] = value.dtype
    with nnvm.compiler.build_config(opt_level=opt_level):
        graph, lib, params = nnvm.compiler.build(symbol, target,
                                                 shape=shape_dict,
                                                 dtype=dtype_dict,
                                                 params=params)
    return graph, lib, params


def onnx_input_output_names(onnx_filename):
    onnx_model = onnx.load(onnx_filename)
    initializer_names = set()
    for initializer in onnx_model.graph.initializer:
        initializer_names.add(initializer.name)

    input_names = []
    for input in onnx_model.graph.input:
        if input.name not in initializer_names:
            input_names.append(input.name)

    output_names = []
    for output in onnx_model.graph.output:
        output_names.append(output.name)

    return input_names, output_names


def run(args):
    onnx_filename = os.path.join(args.test_dir, 'model.onnx')
    input_names, output_names = onnx_input_output_names(onnx_filename)
    test_data_dir = os.path.join(args.test_dir, 'test_data_set_0')
    inputs, outputs = load_test_data(test_data_dir, input_names, output_names)

    sess = rt.InferenceSession(onnx_filename)

    inputs = dict(inputs)
    outputs = [v for n, v in outputs]

    actual_outputs = sess.run(output_names, inputs)

    for i, (name, expected, actual) in enumerate(
            zip(output_names, outputs, actual_outputs)):
        np.testing.assert_allclose(expected, actual,
                                   rtol=1e-3, atol=1e-4), name
        print('%s: OK' % name)
    print('ALL OK')

    if args.iterations > 1:
        num_iterations = args.iterations - 1
        start = time.time()
        for t in range(num_iterations):
            sess.run(output_names, inputs)
        elapsed = time.time() - start
        print('Elapsed: %.3f msec' % (elapsed * 1000 / num_iterations))


def main():
    parser = argparse.ArgumentParser(description='Run ONNX by TensorRT')
    parser.add_argument('test_dir')
    parser.add_argument('--backend', '-b', default='CPU')
    parser.add_argument('--debug', '-g', action='store_true')
    parser.add_argument('--iterations', '-I', type=int, default=1)
    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    run(args)


if __name__ == '__main__':
    main()
