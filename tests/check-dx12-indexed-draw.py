#!/usr/bin/env python3
"""Compare the patched DrawIndexedInstanced with Apple's installed runtime.

Usage: python3 tests/check-dx12-indexed-draw.py /path/to/patched/dxmt
Requires macOS, clang++, and Metal Shader Converter's runtime headers.
"""
import pathlib
import subprocess
import sys
import tempfile

source = pathlib.Path(sys.argv[1]) / "src/d3d12/d3d12_command_list.cpp"
text = source.read_text()
start = text.index("  void STDMETHODCALLTYPE\n  DrawIndexedInstanced(")
end = text.index("\n  };", start) + len("\n  };")
method = text[start:end].replace("STDMETHODCALLTYPE", "")
fixture = pathlib.Path(__file__).with_suffix(".mm").read_text()
with tempfile.TemporaryDirectory(prefix="ambre-indexed-draw-") as directory:
    directory = pathlib.Path(directory)
    unit = directory / "contract.mm"
    unit.write_text(fixture.replace("/* DRAW_INDEXED_METHOD */", method))
    binary = directory / "contract"
    subprocess.run([
        "clang++", "-std=c++17", "-fobjc-arc", "-Wno-deprecated-declarations",
        "-I/usr/local/include", str(unit), "-framework", "Foundation",
        "-framework", "Metal", "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
