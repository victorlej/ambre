#!/usr/bin/env python3
"""Execute Ambre's typed descriptor encoder against Apple's runtime helper.

Usage: python3 tests/check-dx12-buffer-view.py /path/to/patched/dxmt
Requires macOS, clang++, and Metal Shader Converter's runtime headers.
"""
import pathlib
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]) / "src/d3d12/d3d12_descriptor_heap.cpp"
text = source.read_text()
start = text.index("inline uint64_t\nIRBufferMetadata(")
end = text.index("\n}", start) + 2
metadata = text[start:end]
case = text.index("case ShaderVisibleDescriptorType::UAVTexelBuffer:")
start = text.index("      auto &texel = cpu.UAVTexelBuffer;", case)
end = text.index("\n      break;\n    }", start)
body = text[start:end]
fixture = pathlib.Path(__file__).with_suffix(".mm").read_text()
with tempfile.TemporaryDirectory(prefix="ambre-buffer-view-") as directory:
    directory = pathlib.Path(directory)
    unit = directory / "contract.mm"
    unit.write_text(fixture.replace("/* METADATA_FUNCTION */", metadata)
                   .replace("/* TYPED_DESCRIPTOR_BODY */", body))
    binary = directory / "contract"
    subprocess.run([
        "clang++", "-std=c++17", "-fobjc-arc", "-Wno-deprecated-declarations",
        "-I/usr/local/include", str(unit), "-framework", "Foundation",
        "-framework", "Metal", "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
