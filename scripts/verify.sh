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
    file -b "${f}" | grep -q Mach-O || continue
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

echo "== 4. la partie 32 bits existe (sinon tout programme 32 bits échoue en c0000135)"
[ -s "${W}/lib/wine/i386-windows/ntdll.dll" ] || bad "pas de i386-windows/ntdll.dll"

echo "== 5. la partie Windows est allégée (sans informations de débogage)"
size="$(stat -f %z "${W}/lib/wine/x86_64-windows/ntdll.dll")"
[ "${size}" -lt 1500000 ] || bad "ntdll.dll pèse ${size} octets : pas allégé"

echo "== 6. identité de jeu (Mode Jeu)"
codesign -dvvv "${W}/lib/wine/x86_64-unix/wine" 2>&1 | grep -q 'Identifier=app.allia.game' || bad "chargeur non signé app.allia.game"
strings "${W}/lib/wine/x86_64-unix/wine" | grep -q 'public.app-category.games' || bad "catégorie jeux absente du chargeur"

echo "== 7. composants graphiques"
[ -f Libraries/DXVK/x64/d3d11.dll ] || bad "DXVK absent"
strings Libraries/DXVK/x64/d3d11.dll | grep -q AMBRE_VERSION || bad "compteur Ambre absent de DXVK (x64)"
strings Libraries/DXVK/x32/d3d11.dll | grep -q AMBRE_VERSION || bad "compteur Ambre absent de DXVK (x32)"
[ -f Libraries/DXMT/x64/d3d11.dll ] || bad "DXMT absent"
[ -f "${W}/lib/libMoltenVK.dylib" ] || bad "MoltenVK absent"

if [ "${fail}" -ne 0 ]; then echo "❌ contrôles échoués"; exit 1; fi
echo "✅ tous les contrôles passent"
