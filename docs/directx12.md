# DirectX 12 dans Ambre Metal (plan du 2 octobre 2026)

Objectif : Clair Obscur: Expedition 33 (Unreal Engine 5, DirectX 12 seulement en Shader Model 6) jouable.

## Constat

- Le d3d12 de DXMT (auteur : 3Shain) ne traduit que les shaders DXBC (Shader Model 5, airconv).
  Les jeux Unreal 5 envoient du **DXIL** (Shader Model 6.6) : refusé (E_NOTIMPL).
- Correctif 0007 (diagnostic, `AMBRE_DXIL_DUMP`) : le jeu reste en DirectX 12 et envoie
  888 shaders (530 calcul, 358 sommets) avant de s'arrêter.
- **Metal Shader Converter d'Apple** (`metal-shaderconverter`, `libmetalirconverter.dylib`) :
  888 / 888 convertis, 0 échec (`tests/dxil-couverture.sh`).

## Pourquoi le convertisseur d'Apple se branche bien sur DXMT

| | DXMT (d3d12) | Metal Shader Converter |
|---|---|---|
| Arguments racine | tableau de mots de 64 bits (`SlotQwordOffsets`) | « argument buffer » de haut niveau, index 2 |
| Tas de descripteurs | tampon GPU, 32 octets par descripteur | `IRDescriptorTableEntry`, 24 octets (adresse, vue, métadonnées) |
| Résidence | `MTLResidencySet` global (tout est résident) | rien à faire de plus |
| Root signature | `D3D12_VERSIONED_ROOT_SIGNATURE_DESC` (désérialiseur de DXMT) | `IRVersionedRootSignatureDescriptor` : **même disposition en mémoire** |

## Étapes

1. **Pipelines DXIL** : winemetal charge `libmetalirconverter.dylib` (dlopen côté Mac,
   chemin `AMBRE_IRCONVERTER` ou à côté de winemetal.so ; aucun lien à la compilation, donc
   rien d'Apple dans le dépôt public hors des en-têtes Apache 2.0). d3d12 : DXIL → metallib avec
   la root signature, création des pipelines de calcul et de rendu (descripteur de sommets
   Metal à pas dynamique, index 6 + emplacement). Les dessins avec ces pipelines sont **sautés**
   tant que l'étape 2 n'est pas faite : le jeu doit aller plus loin sans planter (écran noir),
   et on capture les shaders de pixels.
2. **Liaison des ressources** : copie miroir des tas de descripteurs au format 24 octets
   (textures : identifiant de vue ; tampons : adresse + taille ; échantillonneurs), traduction
   des poignées GPU (index = (adresse − base) / 32 → base miroir + index × 24), argument buffer
   de haut niveau construit depuis la root signature (positions données par
   `IRRootSignatureGetResourceLocations`), tas liés aux index 0 et 1 (Shader Model 6.6 :
   `ResourceDescriptorHeap`), paramètres de dessin aux index 4 et 5. Premiers calculs justes.
3. **Rendu** : tampons de sommets, première image.
4. **Vitesse** : cache des pipelines convertis (disque), conversion en arrière-plan.

## Licences

- En-têtes du convertisseur (`metal_irconverter*.h`) : Apache 2.0 (Apple), publiables.
- `libmetalirconverter.dylib` : licence d'Apple (redistribution avec une app pour convertir
  des shaders sur matériel Apple, à faire valider par un juriste) ; distribuée à part, jamais
  dans ce dépôt.
