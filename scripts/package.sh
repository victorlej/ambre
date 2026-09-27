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

echo "== $(date +%T) installation"
rm -rf staging Libraries
# install-lib : seulement ce qu'il faut pour faire tourner des programmes (pas les bibliothèques
# d'import, qui prendraient des centaines de Mo pour rien).
make -C "${BUILD}" -j"$(sysctl -n hw.logicalcpu)" install-lib DESTDIR="${ROOT}/staging"
mkdir -p "staging${PREFIX}/share/wine/mono" "staging${PREFIX}/share/wine/gecko" Libraries/Wine
cp -R addons/mono/. "staging${PREFIX}/share/wine/mono/"
cp -R addons/gecko/. "staging${PREFIX}/share/wine/gecko/"
for d in bin lib share; do cp -R "staging${PREFIX}/${d}" "Libraries/Wine/${d}"; done

echo "== $(date +%T) DXMT (seulement le pont winemetal dans Wine) et composants par bouteille"
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

echo "== $(date +%T) nettoyage de la partie Windows (bibliothèques d'import, informations de débogage)"
find Libraries/Wine/lib/wine/*-windows -name '*.a' -delete
find Libraries/Wine/lib/wine/*-windows -type f -print0 \
    | xargs -0 -P "$(sysctl -n hw.logicalcpu)" -n 64 x86_64-w64-mingw32-strip --strip-debug 2>/dev/null || true

echo "== $(date +%T) chargeur"
# Wine 11 range le chargeur à côté de ntdll.so ; bin/ n'en garde que des liens (Allia lance bin/wine).
loader=Libraries/Wine/lib/wine/x86_64-unix/wine
[ -x "${loader}" ] || { echo "::error::pas de chargeur dans ${loader}"; exit 1; }
for n in wine wine64 wineloader; do ln -sf ../lib/wine/x86_64-unix/wine "Libraries/Wine/bin/${n}"; done

echo "== $(date +%T) bibliothèques tierces : copiées dans Wine/lib, références rendues relatives"
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

echo "   $(date +%T) gstreamer copié, recherche des dépendances"
# Dépendances à copier, dans un fichier (une longue chaîne de ~3 500 chemins prenait 40 min au
# bash 3.2 de macOS). Chargées par leur nom (dlopen), freetype et gnutls sont à nommer.
: > deps.txt
while read -r d; do
    for so in libfreetype.6.dylib libgnutls.30.dylib; do [ -f "${d}/lib/${so}" ] && echo "${d}/lib/${so}" >> deps.txt; done
done < store-outs.txt
for f in Libraries/Wine/lib/wine/*-unix/*.so "${LIBDIR}"/gstreamer-1.0/*.dylib; do
    [ -f "${f}" ] && scan "${f}" >> deps.txt
done
while [ -s deps.txt ]; do
    sort -u deps.txt > deps-round.txt
    : > deps.txt
    while read -r lib; do
        base="$(basename "${lib}")"
        [ -e "${LIBDIR}/${base}" ] && continue
        cp -L "${lib}" "${LIBDIR}/${base}"; chmod u+w "${LIBDIR}/${base}"
        scan "${LIBDIR}/${base}" >> deps.txt
    done < deps-round.txt
done
rm -f deps.txt deps-round.txt

echo "   $(date +%T) $(ls "${LIBDIR}" | wc -l) bibliothèques copiées, réécriture des liens"
# Un seul appel à install_name_tool par fichier (un appel par lien prenait 40 min sur ~700
# fichiers), et tous les cœurs en parallèle.
fixup() {
    local f="$1" rel ref args=() uses_system_iconv=0
    rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))' "${LIBDIR}" "${f}")"
    chmod u+w "${f}" 2>/dev/null || true
    case "${f}" in *.dylib*) args+=(-id "@loader_path/$(basename "${f}")") ;; esac
    # Deux iconv différents : _iconv vient de macOS, _libiconv de nix.
    nm -u "${f}" 2>/dev/null | grep -q '^ *_iconv$' && uses_system_iconv=1
    for ref in $(scan "${f}"); do
        if [[ "$(basename "${ref}")" == libiconv*.dylib ]] && [ "${uses_system_iconv}" = 1 ]; then
            args+=(-change "${ref}" /usr/lib/libiconv.2.dylib)
        else
            args+=(-change "${ref}" "@loader_path/${rel}/$(basename "${ref}")")
        fi
    done
    # Les modules de Wine chargent des bibliothèques par leur seul nom (dlopen("libgnutls.30.dylib"),
    # libMoltenVK, libfreetype) : macOS les cherche alors dans les rpath du module. Comme le moteur
    # d'origine, on y ajoute Wine/lib (sans ça : pas de connexions sécurisées, pas de Vulkan).
    case "${f}" in */lib/wine/*-unix/*.so)
        otool -l "${f}" | grep -q "@loader_path/../../ " || args+=(-add_rpath @loader_path/../../) ;;
    esac
    [ "${#args[@]}" -gt 0 ] && install_name_tool "${args[@]}" "${f}" 2>/dev/null || true
    codesign -f -s - "${f}" 2>/dev/null || true
}
export -f fixup scan
export LIBDIR
{
    for f in "${LIBDIR}"/*.dylib* "${LIBDIR}"/gstreamer-1.0/*.dylib*; do [ -f "${f}" ] && printf '%s\0' "${f}"; done
    find Libraries/Wine/bin -type f -print0
    find Libraries/Wine/lib/wine -name '*.so' -print0
} | xargs -0 -P "$(sysctl -n hw.logicalcpu)" -n 1 bash -c 'fixup "$1"' _

echo "== $(date +%T) identité de jeu du chargeur (Mode Jeu : macOS lit la signature)"
codesign --force --sign - --identifier app.allia.game "${loader}"
codesign -dvvv "${loader}" 2>&1 | grep -E 'Identifier|Info.plist'

echo "== $(date +%T) paquet « Allia Jeu.app » (Mode Jeu pour le programme du jeu)"
# macOS rattache un programme à l'app dont il est l'exécutable principal (Contents/MacOS/<nom>),
# d'après le chemin utilisé pour le lancer, même si c'est un lien. Allia lance Wine par ce lien et
# pose AMBRE_WINELOADER (correctif 0002) pour que Wine lance aussi les jeux par ce chemin :
# le jeu devient « Allia Jeu », déclaré comme jeu → Mode Jeu. Wine suit le lien pour trouver ntdll.
# LSUIElement : les programmes sans fenêtre (services de Wine) restent hors du Dock ; Wine passe au
# premier plan ceux qui ouvrent une fenêtre (vérifié : Bloc-notes « Foreground », services « UIElement »).
game="Libraries/Allia Jeu.app/Contents"
mkdir -p "${game}/MacOS" "${game}/Resources"
ln -sf ../../../Wine/lib/wine/x86_64-unix/wine "${game}/MacOS/wine"
cat > "${game}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>app.allia.game</string>
  <key>CFBundleName</key><string>Allia</string>
  <key>CFBundleDisplayName</key><string>Allia</string>
  <key>CFBundleExecutable</key><string>wine</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>GCSupportsGameMode</key><true/>
  <key>LSSupportsGameMode</key><true/>
  <key>LSUIElement</key><true/>
  <key>NSAppSleepDisabled</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST

echo "== $(date +%T) version"
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
  <key>gameBundle</key><true/>
  <key>gameDock</key><true/>
  <key>hudBridge</key><true/>
</dict>
</plist>
PLIST
cat Libraries/AmbreVersion.plist

echo "== $(date +%T) archive"
tar -czf Libraries.tar.gz Libraries
shasum -a 256 Libraries.tar.gz | tee Libraries.tar.gz.sha256
du -sh Libraries Libraries.tar.gz
