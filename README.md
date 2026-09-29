# Ambre

<p align="center"><img src="assets/logo/ambre-banniere.png" alt="Ambre, le moteur de jeu d'Allia" width="560"></p>

**Ambre** est le moteur d'Allia : il fait tourner les jeux Windows sur les Mac à puce Apple.

En grec ancien, *ēlektron* désignait à la fois l'ambre et l'électrum, l'alliage naturel d'or et d'argent. Allia vient d'« alliage » : son moteur porte le nom de l'ambre.

## Ce qu'il contient

- **Wine** : le code de CrossOver 26.3 reporté sur Wine 11.17, à partir de la branche `wine1117` de [dappermint/winecx](https://github.com/dappermint/winecx), commit indiqué dans `WINECX_COMMIT`.
- **Les correctifs d'Ambre** : `patches/`, appliqués dans l'ordre.
- **Graphismes** : [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) 1.10.3 (compilé par Ambre ; compteur et mesure dans Ambre Pro), [DXMT](https://github.com/3Shain/dxmt) 0.80, [MoltenVK](https://github.com/KhronosGroup/MoltenVK) 1.4.2.
- **wine-mono** et **wine-gecko**, aux versions demandées par le code de Wine.

Chaque composant téléchargé est vérifié par son empreinte SHA-256. Les bibliothèques tierces (freetype, gnutls, ffmpeg, gstreamer…) viennent d'une version figée de nixpkgs.

## Correctifs

| Correctif | Pourquoi |
|---|---|
| `0001-identite-de-jeu.patch` | Le chargeur se déclare comme un jeu (`app.allia.game`, catégorie jeux, `GCSupportsGameMode`) : macOS active le Mode Jeu. |
| `0002-mode-jeu-pour-le-jeu.patch` | Si `AMBRE_WINELOADER` est posé, Wine lance les nouveaux programmes par ce chemin (le lien `Allia Jeu.app/Contents/MacOS/wine`) : macOS rattache le jeu lui-même à l'app « Allia Jeu », déclarée comme jeu, et lui donne le Mode Jeu. |
| `0003-chaque-jeu-dans-le-dock.patch` | Si `AMBRE_GAME_BUNDLES` est posé, un programme dont le nom a un lien dans ce dossier (`skyrimse` → `<Nom du jeu>.app/Contents/MacOS/wine`) est lancé par ce chemin : macOS l'affiche dans le Dock sous le nom et la jaquette du jeu (paquets créés par Allia). |
| `0004-reseau-sans-dns-ipv4.patch` | `GetAdaptersAddresses` : une carte sans serveur DNS de la famille demandée (réseau IPv6 seul, partage de connexion) est listée sans DNS au lieu de faire échouer toute la liste ; taille de départ initialisée. Steam voit enfin sa carte réseau allumée et se connecte sans attendre 20 s (« Timed out waiting for network »). |
| `0005-fils-du-jeu-interactifs.patch` | Un jeu lancé par son lien Allia (correctif 0003) reçoit `AMBRE_GAME_PROCESS` : tous ses fils sont créés en priorité « interactive » (`QOS_CLASS_USER_INTERACTIVE`) ; macOS les garde sur les cœurs performants et monte leur fréquence plus vite. |
| `0006-cartes-internes-du-mac.patch` | Sur Mac, les interfaces internes d'Apple (awdl, llw, anpi, utun, gif, stf, bridge, ap, nan, ipsec) ne sont présentées aux programmes Windows que si elles ont une adresse IPv4 : 6 cartes au lieu d'environ 24. Steam ne lit que 10 cartes, rangées dans un ordre quelconque : la carte connectée en était souvent absente, d'où 20 s d'attente du réseau au démarrage. |
| `0007-dll-builtin-du-jeu.patch` | Si `AMBRE_LOCAL_BUILTINS` est posé, une DLL « builtin » placée dans le dossier d'un programme (hors dossiers système) est chargée telle quelle : DXMT (livré en DLL builtin) fonctionne jeu par jeu. Sans cela, Wine chargeait ses propres d3d11/dxgi (wined3d) et le jeu n'avait jamais DXMT. |
| `0008-reglages-par-jeu.patch` | Au lancement d'un programme de jeu (lien du correctif 0003), Wine applique le fichier `AMBRE_GAME_BUNDLES/<programme>.env` (« NOM=valeur », « NOM= » pour retirer) : réglages propres à un jeu (limite d'images, compteur, DXMT, MetalFX…) sans redémarrer Steam. |
| `0009-reglages-par-jeu-cote-windows.patch` | Les réglages du fichier `.env` du jeu (0008) passent aussi dans son environnement **Windows** : lancé par Steam, un jeu recevait celui de Steam, et DXMT (qui lit ses réglages côté Windows) ne voyait ni MetalFX, ni sa limite d'images, ni le compteur. |
| Ambre Pro (privé) | Les fonctions exclusives d'Ambre dans DXVK (compteur, mesure pour Allia, cache des shaders) sont dans un module privé, diffusé compilé. DXVK (licence zlib) le permet ; les modifications de Wine (LGPL), elles, sont toutes ici. |

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
| **1.6.1** | en compilation | **Ambre Metal sur la dernière version de DXMT** (commit e86484e de l'auteur) : ombres de Skyrim corrigées, 246 améliorations de l'auteur |
| **1.6.0** | ✅ publiée | Ambre Metal (notre DXMT : plantage de Skyrim corrigé, compteur Ambre dans l'image), réglages par jeu côté Windows (0009) |
| **1.5.0** | ✅ publiée (étape vers la 2.0) | Metal direct par jeu avec DXMT (0007), réglages par jeu sans redémarrer Steam (0008) ; avec Allia : MetalFX (agrandissement de DXMT), limite d'images de DXMT, cache des shaders de DXMT |
| **1.4.0** | ✅ publiée | Démarrage de Steam sans les 20 s d'attente (0006, avec 0004), fils du jeu en priorité interactive (0005) ; avec Ambre Pro 1.4.0 : nouveau compteur, mesure précise, cache des shaders |
| **1.3.0** | ✅ publiée | Démarrage de Steam plus rapide : Steam voit sa carte réseau sans DNS IPv4 et n'attend plus 20 s (correctif 0004) |
| **2.0** | prévue | DirectX 11 → Metal direct (DXMT corrigé), MetalFX Upscaling |
| **2.x** | prévue | Génération d'images, DirectX 12 |
| **Plus tard** | | Moteur arm64 natif avec émulation x86, si Apple l'autorise (Rosetta 2 réduite dès macOS 28) |

Compilation : ~35 min sur GitHub Actions (DXVK 6 min, Wine ~16 min avec le cache, assemblage ~3 min, contrôles ~5 min). Une étiquette `v*` compile et publie ; un lancement manuel avec « Publier » fait de même sans rien installer sur un Mac.

## Licence

Wine et les correctifs d'Ambre sont sous licence **GNU LGPL 2.1 ou ultérieure** (`COPYING.LIB`). DXVK, DXMT, MoltenVK, wine-mono et wine-gecko gardent leurs propres licences.

Merci à CodeWeavers, qui publie le code de CrossOver, aux auteurs de Wine, de DXVK, de DXMT et de MoltenVK, et à dappermint pour le report de CrossOver sur Wine 11.
