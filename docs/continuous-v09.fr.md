# Capture continue v0.9

La capture continue commence par le même pipeline que Full Export : scripts
clients reconstruits, métadonnées des services choisis, passes GUI et observation
passive lorsque Cobalt est disponible. Elle poursuit ensuite la surveillance
jusqu’au bouton **Stop & Save / Arrêter et sauvegarder**. L’exporteur fonctionne
seul ; le MCP sert uniquement au développement et aux tests.

## Utilisation

1. Choisir les cibles et options, puis **Start continuous capture**.
2. Laisser la capture initiale se terminer, puis jouer et ouvrir les interfaces
   souhaitées. L’exporteur ne provoque aucune action réseau.
3. Cliquer sur **Stop & Save** et attendre la finalisation.
4. Consulter `report.md`, `manifest.json` et `scripts/index.json` dans le dossier
   local affiché. Les fichiers `.luau` peuvent être mutualisés entre plusieurs
   scripts ; chaque Instance conserve son entrée propre dans l’index.

Les compteurs séparent objets inspectés, Instances uniques, modifications,
états GUI, transitions, occurrences réseau, événements écrits et files en
attente. Un rescan inchangé n’est pas un nouvel objet. Les répétitions réseau
réelles restent des occurrences distinctes. Une perte ou une erreur doit être
lue dans les compteurs, les couches du rapport et `partialReasons`.

## Données et relecture

Le format v0.9 porte `inspectionVersion: 2`. Les états GUI associent une
projection initiale à des deltas `upserts` / `removes` par InstanceId. Le retour
à un état déjà vérifié réutilise son contenu sur disque, tout en conservant la
nouvelle transition dans le journal. Les chemins et noms ne servent pas
d’identité unique. Un script renommé n’est pas décompilé à nouveau pour ce seul
motif. Deux sources ne partagent un fichier qu’après comparaison exacte de
leurs octets reconstruits.

Validation indépendante :

```sh
python scripts/validate_export.py "chemin/vers/export"
```

Les outils conservent la lecture des exports v0.5 à v0.8. Le
[contrat détaillé en anglais](continuous-v09.md) décrit les schémas, le lecteur
Python, les signatures de remotes et les limites de comparaison.

## Après une interruption

```sh
python scripts/recover_export.py "chemin/vers/capture-interrompue"
python scripts/recover_export.py "chemin/vers/capture-interrompue" --output "nouveau-dossier-vide"
```

L’outil teste les checksums et la cohérence de chaque checkpoint, du plus récent
au plus ancien, dans un dossier temporaire isolé. Cette vérification utilise de
l’espace disque et des entrées/sorties supplémentaires. La capture d’origine
reste intacte. Le résultat est marqué `partial` / `recovered_checkpoint` : les
données plus récentes peuvent manquer. Il faut lancer une nouvelle capture pour
enregistrer à nouveau ; la récupération ne rejoue pas les anciennes séquences
dans un enregistrement existant.

## Limites

Les fichiers Luau sont les sorties exactes du décompilateur, pas une preuve
d’équivalence avec les sources originales. Les scripts serveur et objets non
répliqués restent inaccessibles. Les états rapides entre observations et les
menus jamais ouverts peuvent manquer. Les buffers sont bornés, mais les index
croissent avec les nouvelles données réelles ; une session très active ne peut
pas garder une taille constante. Les mesures mémoire/FPS concernent tout le
client, y compris le jeu, Cobalt et l’exécuteur. Les captures peuvent contenir
des informations contextuelles : les conserver hors du dépôt public.
