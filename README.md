# Ambre

<p align="center"><img src="assets/logo/ambre-banniere.png" alt="Ambre, le moteur de jeu d'Allia" width="560"></p>

**Ambre** est le moteur d'Allia : il fait tourner les jeux Windows sur les Mac à puce Apple.

En grec ancien, *ēlektron* désignait à la fois l'ambre et l'électrum, l'alliage naturel d'or et d'argent. Allia vient d'« alliage » : son moteur porte le nom de l'ambre.

## Ce qu'il contient

- **Wine** : le code de CrossOver 26.3 reporté sur Wine 11.17, à partir de la branche `wine1117` de [dappermint/winecx](https://github.com/dappermint/winecx), commit indiqué dans `WINECX_COMMIT`.
- **Les correctifs d'Ambre** : `patches/`, appliqués dans l'ordre.
- **Graphismes** :
  - **Ambre Metal** : [DXMT](https://github.com/3Shain/dxmt) de 3Shain (DirectX 11 → Metal direct), au commit de l'auteur indiqué dans `.github/workflows/dxmt.yml`, avec les correctifs de `dxmt/patches/` ;
  - [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) 1.10.3, traducteur de secours (DirectX → Vulkan) ;
  - [MoltenVK](https://github.com/KhronosGroup/MoltenVK) 1.4.2 (Vulkan → Metal).
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
| `0007-dll-builtin-du-jeu.patch` | Si `AMBRE_LOCAL_BUILTINS` est posé, une DLL « builtin » placée dans le dossier d'un programme (hors dossiers système) est chargée telle quelle : DXMT (livré en DLL builtin) fonctionne jeu par jeu. Sans cela, Wine chargeait ses propres d3d11/dxgi (wined3d) et le jeu n'avait jamais DXMT. Depuis la 1.6.3 : jamais sous `C:\windows` (les pilotes de `system32\drivers` se chargeaient ainsi et Steam perdait le réseau). |
| `0008-reglages-par-jeu.patch` | Au lancement d'un programme de jeu (lien du correctif 0003), Wine applique le fichier `AMBRE_GAME_BUNDLES/<programme>.env` (« NOM=valeur », « NOM= » pour retirer) : réglages propres à un jeu (limite d'images, compteur, DXMT, MetalFX…) sans redémarrer Steam. |
| `0009-reglages-par-jeu-cote-windows.patch` | Les réglages du fichier `.env` du jeu (0008) passent aussi dans son environnement **Windows** : lancé par Steam, un jeu recevait celui de Steam, et DXMT (qui lit ses réglages côté Windows) ne voyait ni MetalFX, ni sa limite d'images, ni le compteur. |
| `0010-priorite-des-paquets-sur-mac.patch` | macOS rend la priorité d'un paquet reçu (TOS) sous le type `IP_RECVTOS`, et non `IP_TOS` comme Linux : Wine la jetait. La bibliothèque réseau de Steam intégrée aux jeux (SteamNetworkingSockets) échouait alors (« No control data returned even though we asked for TOS? ») ; How to Fish se figeait au lancement d'une partie. |
| Ambre Pro (privé) | Les fonctions exclusives d'Ambre (compteur, mesure pour Allia, cache des shaders dans DXVK ; compteur dans l'image et génération d'images pour Ambre Metal) sont dans un module privé, diffusé compilé ([ambre-pro-versions](https://github.com/victorlej/ambre-pro-versions)). Il se branche sur des prises génériques ; les modifications de Wine et de DXMT (LGPL), elles, sont toutes ici. |

## Ambre Metal

Ambre Metal est notre version de DXMT : DirectX 11 traduit directement en Metal, sans passer par Vulkan. Allia l'utilise par défaut pour les jeux DirectX 11 et garde DXVK en secours. Correctifs (`dxmt/patches/`, LGPL comme DXMT) :

| Correctif | Pourquoi |
|---|---|
| `0002-vues-reference-publique.patch` | Les vues gardent une référence publique sur leur ressource, comme Direct3D 11 et DXVK. |
| `0003-destruction-differee.patch` | Destruction différée des objets Direct3D 11 : Skyrim SE ne plante plus au bout de vingt secondes. |
| `0004-prise-present.patch` | Prise `AMBRE_PRESENT_PLUGIN_DIR` : un module d'extension est appelé à chaque image. |
| `0005-image-par-dessus.patch` | Image d'un module d'extension posée par-dessus le jeu (le compteur Ambre, dessiné dans l'image). |
| `0006-prise-affichage.patch` | Prise d'affichage `AMBRE_FRAME_PLUGIN` : un module macOS peut afficher l'image lui-même (génération d'images). |

Règle : ici seulement des correctifs de jeux et des prises génériques ; les fonctions d'Ambre Pro restent dans leur module privé. Compilation : `.github/workflows/dxmt.yml` (appelé par la compilation d'Ambre).

## Jeux certifiés

`compat/jeux.json` : la certification des jeux par Allia (lue par l'app, mise à jour sans nouvelle version).

| Niveau | Garantie |
|---|---|
| 🟢 Optimisé pour Allia | Jouable du début à la fin, ≥ 50 images/s en moyenne, images stables, manette et sauvegardes vérifiées, aux réglages recommandés |
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
| **1.1.0** | ✅ publiée | Compteur Ambre en jeu, Mode Jeu pour le programme du jeu (0002), DXVK compilé par Ambre |
| **1.2.0** | ✅ publiée | Chaque jeu sous son nom et sa jaquette dans le Dock (0003), processeur mesuré par macOS, pas d'App Nap |
| **1.3.0** | ✅ publiée | Steam voit sa carte réseau sans DNS IPv4 et n'attend plus 20 s (0004) |
| **1.4.0** | ✅ publiée | Démarrage de Steam en ~10 s (0006), fils du jeu en priorité interactive (0005) ; Ambre Pro : mesure image par image |
| **1.5.0** | ✅ publiée | Metal direct par jeu avec DXMT (0007), réglages par jeu sans redémarrer Steam (0008), MetalFX |
| **1.6.0** | ✅ publiée | **Ambre Metal** (plantage de Skyrim corrigé, compteur Ambre dans l'image), réglages par jeu côté Windows (0009) |
| **1.6.1** | ✅ publiée | Ambre Metal sur la dernière version de DXMT (commit e86484e) : ombres de Skyrim corrigées |
| **1.6.2** | ✅ publiée | Prise d'affichage (0006 de DXMT) pour la **génération d'images** d'Ambre Pro : 30 images calculées, 60 affichées |
| **1.6.3** | ✅ publiée | Correctif 0007 restreint aux dossiers des programmes ; avec Ambre Pro 1.6.3 : génération d'images plus régulière (grille rattrapée en douceur), vrai compteur d'images affichées |
| **1.6.4** | prête | Priorité des paquets réseau sur Mac (0010) : jeux qui utilisent le réseau de Steam (How to Fish) |
| **2.0** | prévue | MetalFX vérifié, cache des shaders Metal, choix automatique affiné |
| **2.x** | prévue | DirectX 12 en Metal direct |
| **Plus tard** | | Moteur arm64 natif avec émulation x86, si Apple l'autorise (Rosetta 2 réduite dès macOS 28) |

Compilation : ~35 min sur GitHub Actions (DXVK 6 min, Wine ~16 min avec le cache, assemblage ~3 min, contrôles ~5 min). Une étiquette `v*` compile et publie ; un lancement manuel avec « Publier » fait de même sans rien installer sur un Mac.

## Licence

Wine et les correctifs d'Ambre sont sous licence **GNU LGPL 2.1 ou ultérieure** (`COPYING.LIB`). DXVK, DXMT, MoltenVK, wine-mono et wine-gecko gardent leurs propres licences.

Merci à CodeWeavers, qui publie le code de CrossOver, aux auteurs de Wine, de DXVK, de DXMT et de MoltenVK, et à dappermint pour le report de CrossOver sur Wine 11.
