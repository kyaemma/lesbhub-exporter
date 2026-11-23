# External references

This directory contains two **Git submodules**. They are reference material only; the Lesbhub exporter does **not** execute them, load them at runtime, or use them as dependencies.

- [EdgeIY / infiniteyield](https://github.com/EdgeIY/infiniteyield) — examples of client Roblox scripting conventions.
- [patangation / roblox-script-exporter](https://github.com/patangation/roblox-script-exporter) — examples of `.rbxl` (Lune) object export, property serialization, and per-service manifest layout. This uses a different runtime than our live Roblox client exporter.

Both currently advertise MIT licensing. Copyright and license files remain in the respective upstream repositories.

To populate the directories after cloning:

```powershell
git submodule update --init --recursive
```

To follow upstream changes deliberately (requires review):

```powershell
git submodule update --remote reference/infiniteyield reference/roblox-script-exporter
```

Do not blindly copy source from references into the V1 runtime; audit license notices and safety considerations first.
