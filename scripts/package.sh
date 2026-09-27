#!/bin/bash
# Ambre : assemble le moteur compilé en un dossier Libraries/ déplaçable, puis Libraries.tar.gz.
#   Libraries/Wine   : wine (bin, lib, share), bibliothèques tierces copiées dans Wine/lib
#   Libraries/DXVK   : DXVK-macOS (x64, x32), posé par Allia dans chaque bouteille
#   Libraries/DXMT   : DXMT (x64, x32), posé par Allia à côté d'un jeu qui le demande
# Usage : scripts/package.sh <dossier de compilation> <version d'Ambre>
# Prérequis : store-outs.txt (bibliothèques nix x86_64), addons/, payload/ (fetch-components.sh).
set -euo pipefail
BUILD="${1:?dossier de compilation}"
VERSION="${2:?version}"
PREFIX=/opt/ambre
ROOT="$PWD"
LIBDIR="${ROOT}/Libraries/Wine/lib"

echo "== installation"
rm -rf staging Libraries
# install-lib : seulement ce qu'il faut pour faire tourner des programmes (pas les bibliothèques
# d'import, qui prendraient des centaines de Mo pour rien).
make -C "${BUILD}" -j"$(sysctl -n hw.logicalcpu)" install-lib DESTDIR="${ROOT}/staging"
mkdir -p "staging${PREFIX}/share/wine/mono" "staging${PREFIX}/share/wine/gecko" Libraries/Wine
cp -R addons/mono/. "staging${PREFIX}/share/wine/mono/"
cp -R addons/gecko/. "staging${PREFIX}/share/wine/gecko/"
for d in bin lib share; do cp -R "staging${PREFIX}/${d}" "Libraries/Wine/${d}"; done

echo "== DXMT (seulement le pont winemetal dans Wine) et composants par bouteille"
dxmt="payload/v${DXMT_VERSION}"
cp -R "${dxmt}/x86_64-unix/." Libraries/Wine/lib/wine/x86_64-unix/
cp "${dxmt}/x86_64-windows/winemetal.dll" Libraries/Wine/lib/wine/x86_64-windows/
[ -f "${dxmt}/i386-windows/winemetal.dll" ] && cp "${dxmt}/i386-windows/winemetal.dll" Libraries/Wine/lib/wine/i386-windows/
mkdir -p Libraries/DXVK Libraries/DXMT
# DXVK compilé par Ambre (compteur Ambre) s'il est là, sinon celui de Gcenx.
if ls dxvk-build/*/x64/d3d11.dll >/dev/null 2>&1; then
    cp -R dxvk-build/*/. Libraries/DXVK/
    echo "DXVK : compilé par Ambre"
else
    cp -R "payload/dxvk-macOS-async-v${DXVK_VERSION}-20230507-repack/." Libraries/DXVK/
    echo "DXVK : Gcenx (sans compteur Ambre)"
fi
cp -R "${dxmt}/x86_64-windows" Libraries/DXMT/x64
cp -R "${dxmt}/i386-windows" Libraries/DXMT/x32

echo "== nettoyage de la partie Windows (bibliothèques d'import, informations de débogage)"
find Libraries/Wine/lib/wine/*-windows -name '*.a' -delete
find Libraries/Wine/lib/wine/*-windows -type f -print0 \
    | xargs -0 -P "$(sysctl -n hw.logicalcpu)" -n 64 x86_64-w64-mingw32-strip --strip-debug 2>/dev/null || true

echo "== chargeur"
# Wine 11 range le chargeur à côté de ntdll.so ; bin/ n'en garde que des liens (Allia lance bin/wine).
loader=Libraries/Wine/lib/wine/x86_64-unix/wine
[ -x "${loader}" ] || { echo "::error::pas de chargeur dans ${loader}"; exit 1; }
for n in wine wine64 wineloader; do ln -sf ../lib/wine/x86_64-unix/wine "Libraries/Wine/bin/${n}"; done

echo "== bibliothèques tierces : copiées dans Wine/lib, références rendues relatives"
scan() { otool -L "$1" 2>/dev/null | awk '/\/nix\/store/{print $1}'; }
mkdir -p "${LIBDIR}/gstreamer-1.0"
while read -r d; do
    [ -d "${d}/lib/gstreamer-1.0" ] || continue
    for p in "${d}/lib/gstreamer-1.0/"*.dylib; do
        [ -f "${p}" ] || continue
        cp -L "${p}" "${LIBDIR}/gstreamer-1.0/"; chmod u+w "${LIBDIR}/gstreamer-1.0/$(basename "${p}")"
    done
done < store-outs.txt
cp payload/libMoltenVK.dylib "${LIBDIR}/libMoltenVK.dylib"; chmod u+w "${LIBDIR}/libMoltenVK.dylib"

# Chargées par leur nom (dlopen), donc invisibles dans les dépendances : à nommer.
queue=""
while read -r d; do
    for so in libfreetype.6.dylib libgnutls.30.dylib; do [ -f "${d}/lib/${so}" ] && queue="${queue} ${d}/lib/${so}"; done
done < store-outs.txt
for f in Libraries/Wine/lib/wine/*-unix/*.so "${LIBDIR}"/gstreamer-1.0/*.dylib; do
    [ -f "${f}" ] && queue="${queue} $(scan "${f}" | tr '\n' ' ')"
done
while [ -n "${queue// /}" ]; do
    next=""
    for lib in ${queue}; do
        base="$(basename "${lib}")"
        [ -e "${LIBDIR}/${base}" ] && continue
        cp -L "${lib}" "${LIBDIR}/${base}"; chmod u+w "${LIBDIR}/${base}"
        next="${next} $(scan "${LIBDIR}/${base}" | tr '\n' ' ')"
    done
    queue=""
    for l in ${next}; do [ -e "${LIBDIR}/$(basename "${l}")" ] || queue="${queue} ${l}"; done
done

fixup() {
    local f="$1" rel ref
    rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))' "${LIBDIR}" "${f}")"
    chmod u+w "${f}" 2>/dev/null || true
    case "${f}" in *.dylib*) install_name_tool -id "@loader_path/$(basename "${f}")" "${f}" 2>/dev/null || true ;; esac
    for ref in $(scan "${f}"); do
        # Deux iconv différents : _iconv vient de macOS, _libiconv de nix.
        if [[ "$(basename "${ref}")" == libiconv*.dylib ]] && nm -u "${f}" 2>/dev/null | grep -q '^ *_iconv$'; then
            install_name_tool -change "${ref}" /usr/lib/libiconv.2.dylib "${f}" 2>/dev/null || true
        else
            install_name_tool -change "${ref}" "@loader_path/${rel}/$(basename "${ref}")" "${f}" 2>/dev/null || true
        fi
    done
    codesign -f -s - "${f}" 2>/dev/null || true
}
for f in "${LIBDIR}"/*.dylib* "${LIBDIR}"/gstreamer-1.0/*.dylib*; do [ -f "${f}" ] && fixup "${f}"; done
find Libraries/Wine/bin -type f | while read -r f; do fixup "${f}"; done
find Libraries/Wine/lib/wine -name '*.so' | while read -r f; do fixup "${f}"; done

echo "== identité de jeu du chargeur (Mode Jeu : macOS lit la signature)"
codesign --force --sign - --identifier app.allia.game "${loader}"
codesign -dvvv "${loader}" 2>&1 | grep -E 'Identifier|Info.plist'

echo "== version"
cat > Libraries/AmbreVersion.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>version</key><string>${VERSION}</string>
  <key>wine</key><string>$(Libraries/Wine/bin/wine --version 2>/dev/null || echo inconnu)</string>
  <key>winecxCommit</key><string>${WINECX_COMMIT}</string>
  <key>dxvkVersion</key><string>${DXVK_VERSION}</string>
  <key>dxmtVersion</key><string>${DXMT_VERSION}</string>
  <key>moltenvkVersion</key><string>${MOLTENVK_VERSION}</string>
  <key>hud</key><true/>
  <key>frameGeneration</key><false/>
</dict>
</plist>
PLIST
cat Libraries/AmbreVersion.plist

echo "== archive"
tar -czf Libraries.tar.gz Libraries
shasum -a 256 Libraries.tar.gz | tee Libraries.tar.gz.sha256
du -sh Libraries Libraries.tar.gz
