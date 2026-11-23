# Relier le dossier Windows existant au dépôt GitHub

Dossier utilisateur : `C:\dev\Lesbhub\lesbhub-exporter`.

Le dossier **contient déjà `reference\`**, même s'il est vide. `git clone ... .` peut refuser d'utiliser ce dossier non vide. La procédure suivante fonctionne sans devoir supprimer `reference\`.

## Dossier local sans .git (nouveau dépôt vide)

```powershell
cd C:\dev\Lesbhub\lesbhub-exporter
git init
git remote add origin https://github.com/kyaemma/lesbhub-exporter.git
git fetch origin main
git switch -C main --track origin/main
git submodule update --init --recursive
git remote -v
git status
```

**Attention :** `git switch -C main` convient ici parce que le dépôt vient d'être initialisé **et n'a aucun commit local à préserver**. Si le dossier contient des fichiers de projet non suivis, inspecte-les et déplace-les/engage-les avant de changer de branche.

## Dossier déjà initialisé avec Git

```powershell
cd C:\dev\Lesbhub\lesbhub-exporter
git status
git remote -v
```

Si `origin` n'existe pas :

```powershell
git remote add origin https://github.com/kyaemma/lesbhub-exporter.git
git fetch origin
git switch -c main --track origin/main
git submodule update --init --recursive
```

Si `origin` existe déjà, vérifie d'abord son URL ; pour la corriger :

```powershell
git remote set-url origin https://github.com/kyaemma/lesbhub-exporter.git
```

**Ne fais pas de `reset --hard`, `clean -fd` ou de suppression du dossier** s'il contient du travail local. Les sous-modules dans `reference/` sont des liens vers les deux projets externes, pas des copies gérées par le dépôt principal.

## Si le dossier est réellement vide

On peut aussi utiliser `git clone --recurse-submodules https://github.com/kyaemma/lesbhub-exporter.git .` depuis ce dossier.

Conserve les captures générées **hors du dépôt public**.
