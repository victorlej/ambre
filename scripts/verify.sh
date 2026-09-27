#!/bin/bash
# Ambre : contrôles avant publication. Chacun vise un défaut qui passerait inaperçu à la
# compilation et casserait le moteur chez l'utilisateur.
# Usage : scripts/verify.sh   (depuis le dossier qui contient Libraries/)
set -uo pipefail
W=Libraries/Wine
fail=0
bad() { echo "::error::$*"; fail=1; }

echo "== 1. déplaçable : aucune référence au dossier de compilation (/nix/store, /opt/ambre)"
while IFS= read -r f; do
    case "$(file -b "${f}")" in *Mach-O*) ;; *) continue ;; esac
    refs="$(otool -L "${f}" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -E '^/(nix|opt|Users|private|tmp)' || true)"
    [ -n "${refs}" ] && bad "${f} dépend de ${refs}"
    id="$(otool -D "${f}" 2>/dev/null | tail -n +2 | grep -E '^/(nix|opt)' || true)"
    [ -n "${id}" ] && bad "${f} se nomme ${id}"
done < <(find "${W}" -type f \( -name '*.dylib*' -o -name '*.so' -o -perm -111 \))

echo "== 2. chaque bibliothèque se charge (sans le dossier de compilation)"
python_x86="/usr/bin/arch -x86_64 /usr/bin/python3"
while IFS= read -r f; do
    ${python_x86} -c 'import ctypes,sys; ctypes.CDLL(sys.argv[1])' "${f}" 2>/tmp/ambre-dlopen.txt \
        || bad "$(basename "${f}") ne se charge pas : $(head -c 300 /tmp/ambre-dlopen.txt)"
done < <(find "${W}/lib" -maxdepth 1 -name '*.dylib*' -type f)

echo "== 3. le moteur démarre"
v="$(WINEPREFIX="${PWD}/verify-prefix" WINEDEBUG=-all "${W}/bin/wine" --version 2>&1)" || bad "wine --version a échoué : ${v}"
echo "   ${v}"

echo "== 3b. bibliothèques chargées par leur nom : gnutls (connexions sécurisées de Steam), MoltenVK"
for so in secur32 winevulkan winemac; do
    otool -l "${W}/lib/wine/x86_64-unix/${so}.so" | grep -q "@loader_path/../../ " || bad "${so}.so ne cherche pas dans Wine/lib (rpath)"
done
sec="$(WINEPREFIX="${PWD}/verify-prefix" WINEDEBUG=err+all "${W}/bin/wine" rundll32 secur32.dll,InitSecurityInterfaceW 2>&1 || true)"
case "${sec}" in *"Failed to load libgnutls"*) bad "gnutls ne se charge pas : Steam ne pourra pas se connecter" ;; esac

echo "== 4. la partie 32 bits existe (sinon tout programme 32 bits échoue en c0000135)"
[ -s "${W}/lib/wine/i386-windows/ntdll.dll" ] || bad "pas de i386-windows/ntdll.dll"

echo "== 5. la partie Windows est allégée (sans informations de débogage)"
size="$(stat -f %z "${W}/lib/wine/x86_64-windows/ntdll.dll")"
[ "${size}" -lt 1500000 ] || bad "ntdll.dll pèse ${size} octets : pas allégé"

echo "== 6. identité de jeu (Mode Jeu)"
codesign -dvvv "${W}/lib/wine/x86_64-unix/wine" 2>&1 | grep -c 'Identifier=app.allia.game' >/dev/null || bad "chargeur non signé app.allia.game"
LC_ALL=C grep -aqF 'public.app-category.games' "${W}/lib/wine/x86_64-unix/wine" || bad "catégorie jeux absente du chargeur"

echo "== 6b. paquet « Allia Jeu.app » : Wine démarre par ce chemin, correctif 0002 présent"
bundle="Libraries/Allia Jeu.app/Contents/MacOS/wine"
[ -L "${bundle}" ] || bad "pas de lien ${bundle}"
vb="$(WINEPREFIX="${PWD}/verify-prefix" WINEDEBUG=-all AMBRE_WINELOADER="${PWD}/${bundle}" "${bundle}" --version 2>&1)" \
    || bad "wine --version par le paquet a échoué : ${vb}"
[ "${vb}" = "${v}" ] || bad "version différente par le paquet : ${vb}"
plutil -extract CFBundleIdentifier raw "Libraries/Allia Jeu.app/Contents/Info.plist" | grep -qx app.allia.game || bad "identifiant du paquet"
LC_ALL=C grep -aqF AMBRE_WINELOADER "${W}/lib/wine/x86_64-unix/ntdll.so" || bad "correctif 0002 absent de ntdll.so"
LC_ALL=C grep -aqF AMBRE_GAME_BUNDLES "${W}/lib/wine/x86_64-unix/ntdll.so" || bad "correctif 0003 absent de ntdll.so"
LC_ALL=C grep -aqF AMBRE_GAME_PROCESS "${W}/lib/wine/x86_64-unix/ntdll.so" || bad "correctif 0005 absent de ntdll.so"
LC_ALL=C grep -aqF anpi "${W}/lib/wine/x86_64-unix/nsiproxy.so" || bad "correctif 0006 absent de nsiproxy.so"

echo "== 7. composants graphiques"
[ -f Libraries/DXVK/x64/d3d11.dll ] || bad "DXVK absent"
LC_ALL=C grep -aqF AMBRE_VERSION Libraries/DXVK/x64/d3d11.dll || bad "compteur Ambre absent de DXVK (x64)"
LC_ALL=C grep -aqF AMBRE_VERSION Libraries/DXVK/x32/d3d11.dll || bad "compteur Ambre absent de DXVK (x32)"
LC_ALL=C grep -aqF ambrepanel Libraries/DXVK/x64/d3d11.dll || bad "compteur complet absent de DXVK (x64)"
LC_ALL=C grep -aqF frames.txt Libraries/DXVK/x64/d3d11.dll || bad "mesure image par image absente de DXVK (x64)"
LC_ALL=C grep -aqF mvk-cache Libraries/DXVK/x64/d3d11.dll || bad "cache des shaders absent de DXVK (x64)"
[ -f Libraries/DXMT/x64/d3d11.dll ] || bad "DXMT absent"
[ -f "${W}/lib/libMoltenVK.dylib" ] || bad "MoltenVK absent"

if [ "${fail}" -ne 0 ]; then echo "❌ contrôles échoués"; exit 1; fi
echo "✅ tous les contrôles passent"
