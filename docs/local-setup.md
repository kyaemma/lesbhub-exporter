# Linking an existing Windows folder

If `C:\dev\Lesbhub\lesbhub-exporter` is empty and **not already a Git repository**:

```powershell
cd C:\dev\Lesbhub\lesbhub-exporter
git clone --recurse-submodules https://github.com/kyaemma/lesbhub-exporter.git .
git remote -v
git status
```

If it **already contains a local Git repository**:

```powershell
cd C:\dev\Lesbhub\lesbhub-exporter
git remote -v
git remote add origin https://github.com/kyaemma/lesbhub-exporter.git
git fetch origin
git switch -c main --track origin/main
git submodule update --init --recursive
```

If `origin` already exists, use `git remote set-url origin https://github.com/kyaemma/lesbhub-exporter.git` instead of `git remote add`. If your local repository has unpublished commits or modified files, **do not** force-switch or reset; commit/back them up and reconcile first.

If the directory contains unrelated untracked files, move them out before cloning. Keep game exports **out of the public repository**.
