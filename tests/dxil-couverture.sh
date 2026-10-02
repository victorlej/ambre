#!/bin/bash
# Passe chaque shader DXIL capturé dans le convertisseur d'Apple ; compte réussites et échecs.
src="${1:?dossier des .dxil}"; out="${2:-/tmp/msc-out}"; mkdir -p "$out"
here="${MSC_DIR:?dossier du Metal Shader Converter (bin/ et lib/)}"; ok=0; ko=0
for f in "$src"/*.dxil; do
  n=$(basename "$f" .dxil)
  if DYLD_LIBRARY_PATH="$here/lib" "$here/bin/metal-shaderconverter" "$f" -o "$out/$n.metallib" >"$out/$n.txt" 2>&1; then ok=$((ok+1)); else ko=$((ko+1)); echo "échec : $n"; fi
done
echo "réussis : $ok, échecs : $ko"
