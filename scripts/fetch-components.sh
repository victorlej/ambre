#!/bin/bash
# Ambre : télécharge les composants livrés avec le moteur, chacun vérifié par son empreinte SHA-256.
#   addons/  : wine-mono (.NET) et wine-gecko (moteur web), aux versions demandées par le code de Wine
#   payload/ : DXVK-macOS, DXMT, MoltenVK (x86_64)
# Usage : scripts/fetch-components.sh <dossier des sources winecx>
set -euo pipefail
SRC="${1:?dossier des sources winecx}"
: "${DXVK_VERSION:?}" "${DXMT_VERSION:?}" "${MOLTENVK_VERSION:?}"

fetch() { # url fichier sha256
    curl -fsSL --retry 3 -o "$2" "$1"
    local got
    got="$(shasum -a 256 "$2" | cut -d' ' -f1)"
    if [ "${got}" != "$3" ]; then
        echo "::error::empreinte inattendue pour $2 : ${got} au lieu de $3"
        exit 1
    fi
}

mono="$(sed -n 's/^#define MONO_VERSION "\(.*\)"/\1/p' "${SRC}/dlls/appwiz.cpl/addons.c")"
gecko="$(sed -n 's/^#define GECKO_VERSION "\(.*\)"/\1/p' "${SRC}/dlls/appwiz.cpl/addons.c")"
case "${mono}" in
    11.3.0) mono_sha=54a1b0111c3fe4b785eae688af94d27e64995707ad648b6fee8000381b80d298 ;;
    *) echo "::error::wine-mono ${mono} : pas d'empreinte connue, ajoute-la ici"; exit 1 ;;
esac
case "${gecko}" in
    2.47.4) gecko32_sha=2cfc8d5c948602e21eff8a78613e1826f2d033df9672cace87fed56e8310afb6
            gecko64_sha=fd88fc7e537d058d7a8abf0c1ebc90c574892a466de86706a26d254710a82814 ;;
    *) echo "::error::wine-gecko ${gecko} : pas d'empreinte connue, ajoute-la ici"; exit 1 ;;
esac
echo "wine-mono ${mono}, wine-gecko ${gecko}"

mkdir -p addons/mono addons/gecko payload
fetch "https://dl.winehq.org/wine/wine-mono/${mono}/wine-mono-${mono}-x86.tar.xz" mono.tar.xz "${mono_sha}"
fetch "https://dl.winehq.org/wine/wine-gecko/${gecko}/wine-gecko-${gecko}-x86.tar.xz" gecko32.tar.xz "${gecko32_sha}"
fetch "https://dl.winehq.org/wine/wine-gecko/${gecko}/wine-gecko-${gecko}-x86_64.tar.xz" gecko64.tar.xz "${gecko64_sha}"
tar -xJf mono.tar.xz -C addons/mono
tar -xJf gecko32.tar.xz -C addons/gecko
tar -xJf gecko64.tar.xz -C addons/gecko

case "${DXVK_VERSION}" in
    1.10.3) dxvk_sha=acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477 ;;
    *) echo "::error::DXVK ${DXVK_VERSION} : pas d'empreinte connue"; exit 1 ;;
esac
case "${DXMT_VERSION}" in
    0.80) dxmt_sha=8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d ;;
    *) echo "::error::DXMT ${DXMT_VERSION} : pas d'empreinte connue"; exit 1 ;;
esac
case "${MOLTENVK_VERSION}" in
    1.4.2) mvk_sha=f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e ;;
    *) echo "::error::MoltenVK ${MOLTENVK_VERSION} : pas d'empreinte connue"; exit 1 ;;
esac
fetch "https://github.com/Gcenx/DXVK-macOS/releases/download/v${DXVK_VERSION}-20230507-repack/dxvk-macOS-async-v${DXVK_VERSION}-20230507-repack.tar.gz" dxvk.tar.gz "${dxvk_sha}"
fetch "https://github.com/3Shain/dxmt/releases/download/v${DXMT_VERSION}/dxmt-v${DXMT_VERSION}-builtin.tar.gz" dxmt.tar.gz "${dxmt_sha}"
fetch "https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/MoltenVK-macos.tar" moltenvk.tar "${mvk_sha}"
tar -xzf dxvk.tar.gz -C payload
tar -xzf dxmt.tar.gz -C payload
tar -xf moltenvk.tar -C payload MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
lipo -thin x86_64 payload/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib -output payload/libMoltenVK.dylib
ls payload
