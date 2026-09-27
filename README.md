# Ambre

**Ambre** est le moteur d'Allia : il fait tourner les jeux Windows sur les Mac à puce Apple.

En grec ancien, *ēlektron* désignait à la fois l'ambre et l'électrum, l'alliage naturel d'or et d'argent. Allia vient d'« alliage » : son moteur porte le nom de l'ambre.

## Ce qu'il contient

- **Wine** : le code de CrossOver 26.3 reporté sur Wine 11.17, à partir de la branche `wine1117` de [dappermint/winecx](https://github.com/dappermint/winecx), commit indiqué dans `WINECX_COMMIT`.
- **Les correctifs d'Ambre** : `patches/`, appliqués dans l'ordre.
- **Graphismes** : [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) 1.10.3 (compilé par Ambre, avec son compteur), [DXMT](https://github.com/3Shain/dxmt) 0.80, [MoltenVK](https://github.com/KhronosGroup/MoltenVK) 1.4.2.
- **wine-mono** et **wine-gecko**, aux versions demandées par le code de Wine.

Chaque composant téléchargé est vérifié par son empreinte SHA-256. Les bibliothèques tierces (freetype, gnutls, ffmpeg, gstreamer…) viennent d'une version figée de nixpkgs.

## Correctifs

| Correctif | Pourquoi |
|---|---|
| `0001-identite-de-jeu.patch` | Le chargeur se déclare comme un jeu (`app.allia.game`, catégorie jeux, `GCSupportsGameMode`) : macOS active le Mode Jeu. |
| `0002-mode-jeu-pour-le-jeu.patch` | Si `AMBRE_WINELOADER` est posé, Wine lance les nouveaux programmes par ce chemin (le lien `Allia Jeu.app/Contents/MacOS/wine`) : macOS rattache le jeu lui-même à l'app « Allia Jeu », déclarée comme jeu, et lui donne le Mode Jeu. |
| `0003-chaque-jeu-dans-le-dock.patch` | Si `AMBRE_GAME_BUNDLES` est posé, un programme dont le nom a un lien dans ce dossier (`skyrimse` → `<Nom du jeu>.app/Contents/MacOS/wine`) est lancé par ce chemin : macOS l'affiche dans le Dock sous le nom et la jaquette du jeu (paquets créés par Allia). |
| `0004-reseau-sans-dns-ipv4.patch` | `GetAdaptersAddresses` : une carte sans serveur DNS de la famille demandée (réseau IPv6 seul, partage de connexion) est listée sans DNS au lieu de faire échouer toute la liste ; taille de départ initialisée. Steam voit enfin sa carte réseau allumée et se connecte sans attendre 20 s (« Timed out waiting for network »). |
| `dxvk/patches/0001-compteur-ambre.patch` | Compteur d'images d'Ambre dans DXVK (`DXVK_HUD=ambre,lows,cpu,…`) : nom et version du moteur, images/s moyennes, 1 % et 0,1 % les plus lentes, temps d'image, charge du processeur. |

## Jeux certifiés

`compat/jeux.json` : la certification des jeux par Allia (lue par l'app, mise à jour sans nouvelle version).

| Niveau | Garantie |
|---|---|
| 🟢 Optimisé pour Allia | Jouable du début à la fin, ≥ 55 images/s en moyenne, peu de saccades, manette et sauvegardes vérifiées, sur Mac M4 aux réglages recommandés |
| 🟡 Fonctionne | Jouable, performances ou détails pas encore au niveau « optimisé » |
| ⚪ Pas encore testé | Aucune vérification |
| 🔴 Ne fonctionne pas | Ne démarre pas ou se bloque |

## Compilation

La compilation se fait sur un Mac de GitHub (`.github/workflows/build.yml`) :

1. sources de Wine au commit figé, puis correctifs d'Ambre ;
2. outils de compilation en natif, moteur en x86_64 (Rosetta 2), partie Windows avec mingw-w64 gcc ;
3. assemblage d'un dossier `Libraries/` déplaçable (`scripts/package.sh`) ;
4. contrôles (`scripts/verify.sh`) : aucune référence au Mac de compilation, chaque bibliothèque se charge, le moteur démarre, la partie 32 bits existe, l'identité de jeu est présente ;
5. publication de `Libraries.tar.gz` et de son empreinte : sur une étiquette `v*`, ou sur un lancement manuel avec **Publier** coché.

Lancer une compilation à la main : onglet **Actions** → « Ambre — compilation du moteur » → **Run workflow**, depuis `main`. Pour publier une version, remplir le **numéro** (ex. `1.3.0`), cocher **Publier** et écrire les **nouveautés** (une par ligne ou séparées par « | »). Le numéro est vérifié avant la compilation (forme `1.3.0`, version pas encore publiée) ; la version n'est créée que si tous les contrôles passent, au commit compilé. Allia la propose ensuite dans Réglages → Moteur.

## Feuille de route

| Version | État | Contenu |
|---|---|---|
| **1.0.0** | ✅ publiée | Wine de CrossOver 26.3 sur Wine 11.17 compilé par nous, identité de jeu, contrôles automatiques |
| **1.1.0** | ✅ publiée | Compteur Ambre en jeu (images/s, 1 % et 0,1 % bas, temps d'image, processeur), Mode Jeu pour le programme du jeu (paquet `Allia Jeu.app`, correctif 0002), DXVK compilé par Ambre |
| **1.2.0** | ✅ publiée | Chaque jeu sous son nom et sa jaquette dans le Dock (correctif 0003), processeur du compteur mesuré par macOS (via Allia), pas d'App Nap |
| **1.3** | en compilation | Démarrage de Steam plus rapide : Steam voit la carte réseau et n'attend plus 20 s (correctif 0004) ; plus tard : cache des shaders conservé, priorité des fils du jeu, corrections réseau (How to Fish) |
| **2.0** | prévue | DirectX 11 → Metal direct (DXMT corrigé), MetalFX Upscaling |
| **2.x** | prévue | Génération d'images, DirectX 12 |
| **Plus tard** | | Moteur arm64 natif avec émulation x86, si Apple l'autorise (Rosetta 2 réduite dès macOS 28) |

Compilation : ~35 min sur GitHub Actions (DXVK 6 min, Wine ~16 min avec le cache, assemblage ~3 min, contrôles ~5 min). Une étiquette `v*` compile et publie ; un lancement manuel avec « Publier » fait de même sans rien installer sur un Mac.

## Licence

Wine et les correctifs d'Ambre sont sous licence **GNU LGPL 2.1 ou ultérieure** (`COPYING.LIB`). DXVK, DXMT, MoltenVK, wine-mono et wine-gecko gardent leurs propres licences.

Merci à CodeWeavers, qui publie le code de CrossOver, aux auteurs de Wine, de DXVK, de DXMT et de MoltenVK, et à dappermint pour le report de CrossOver sur Wine 11.
