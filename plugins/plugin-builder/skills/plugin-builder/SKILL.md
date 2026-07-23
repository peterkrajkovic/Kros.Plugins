---
name: plugin-builder
description: Create or package a plugin for the KROS plugin store (the business app marketplace) — building a manifest.json and/or an upload-ready .zip (manifest + icon + optional media) that passes the Framework's validation. NOT for creating Claude Code skills/plugins. Triggers on phrases like "vytvor plugin do KROS", "nový plugin do KROS aplikácie", "priprav plugin zip", "plugin manifest", "create a KROS plugin", "build plugin package".
---

# Plugin Package Builder

Interactive workflow that produces a valid, upload-ready plugin package for the KROS plugin store. Ask the user questions (in Slovak), auto-generate everything derivable, validate locally against the reference, and optionally confirm against a running endpoint.

**Before generating anything, read `references/manifest-and-package-rules.md` — it is the authoritative contract.** Validate every field against it as you go and re-ask on any violation, citing the specific rule.

## Step 0 — Scope
Ask: *"Chceš vygenerovať len `manifest.json`, alebo rovno celý `.zip` pripravený na upload?"*
Warn: *"Pozn.: upload endpoint akceptuje výhradne `.zip`, ktorý v roote obsahuje `manifest.json`. Samotný manifest sa nahrať nedá."*

## Step 1 — Authentication method (ask FIRST, it branches later questions)
Ask: *"Akú autentifikáciu plugin používa?"*
- `token-broker` — plugin sa otvára vnútri appky cez server-to-server token exchange (má vlastný backend).
- `manual` — len presmerovanie do externého okna (žiadna inštalácia, žiadny token).

## Step 2 — Collect human-input fields (validate each; re-ask on failure)
Go through **every** field below — do not skip the optional ones, explicitly offer them. Group the questions so the user sees the full surface of the manifest.

**A. Plugin identity (`plugin`)**
- **name** (3–50, trimmed, no control chars) → derive `id` = `sk.<partnerId>.<slug(name)>`; show and confirm.
- **version** (SemVer 2.0, max 20).
- *"Je toto prvá verzia tohto pluginu v store?"* — if **not** first → ask **changelog** (20–5000 znakov). If first → `changelog` stays `null`.
- `partnerId` (auto from partner name), `id` (auto), `requiresReconfiguration` (auto `false`, ask only if the user wants `true`).

**B. Display (`display`)**
- **shortDescription** (10–150, trimmed).
- **detail.description** (markdown, 50–20000, trimmed).
- **categories** — aktuálne nasadenie podporuje **len `invoicing`**, takže nastav presne `["invoicing"]` (nepýtaj sa používateľa na výber kategórie). ⚠️ Enum je deployment-špecifický a môže časom pribrať ďalšie hodnoty — v prípade pochybností over voči `…/Kros.Framework.Plugins.Core/Enums/PluginCategory.cs` alebo dry-run cez `/validate`. Viď poznámku „Enumy sú deployment-špecifické" v referencii.
- **tags** (optional, ≤10, each 2–30, `[a-z0-9-]`) — propose from name + description, let the user edit or drop.

**C. Partner (`partner`)**
- **name** (3–50, trimmed) → also derive `partnerId` = slug to `[a-z0-9-]` (e.g. "Numera Analytics s.r.o." → `numera`); show and confirm.
- **website** (optional, https, max 500).
- **privacyPolicyUrl** (optional, https, max 500).

**D. Partner contact (`partner.contact`)** — each field is a **single string** (NOT a list). At least one channel required: non-empty `email` **OR** `supportUrl` **OR** `website`. Offer each explicitly:
- **email** (single, valid email, max 200).
- **phone** (single, optional, `^\+?[0-9 ()-]+$`, 6–50 chars, ≥6 digits).
- **supportUrl** (single, optional, https, max 500).
- **documentationUrl** (single, optional, https, max 500).

**E. License (`partner.license`)**
- **type** (proprietary, mit, apache-20, gpl-30, bsd-3-clause, lgpl-30, other).
- **url** (optional generally, https, max 500) — **required** if `type` is `proprietary` or `other`.

**F. Authentication (`authentication`)** — based on Step 1:
- `token-broker`: ask **baseUrl** (https, max 500) and **apiKey** (the partner's real API key — required, plain string, max 200). Do NOT auto-generate a secret-ref placeholder; the framework binds `apiKey` directly.
- `manual`: ask **redirectUrl** (http/https, max 2048).

## Step 3 — Generate `manifest.json`
Build the JSON exactly as in the reference samples. Re-check every field against the rules. Print a **summary table** of all fields, marking auto-generated ones (`id`, `partnerId`, `manifestVersion`, `requiresReconfiguration`, proposed `tags`). Get confirmation.

If scope = **manifest only**: write `manifest.json` to a path the user chooses, then **show the target ZIP structure** the manifest must eventually live in (so the user can assemble the upload package later), and stop (offer to package it into a zip now or later):

```
<pluginId>.zip
├── manifest.json          # povinné, v roote
├── icon.<png|jpg|jpeg|webp|svg>   # povinné, práve jeden, štvorcový 64–1024 px (svg bez rozmerov)
└── media/                 # nepovinné, ploché (bez podpriečinkov), ≤10 súborov
    ├── 01-*.<png|jpg|jpeg|webp>   # 320×180 až 1920×1080, bez svg
    └── ...
```

Remind the user: the upload endpoint accepts **only** this `.zip` (limits: ≤25 entries, ≤5 MB/súbor, ≤15 MB spolu) — a bare `manifest.json` cannot be uploaded.

## Step 4 — Package (only if scope = full zip)
Ask for the **icon** path; ask whether there are **media** images (paths). Then run the script:

```powershell
pwsh -NoProfile -File "<skill-dir>/scripts/New-PluginPackage.ps1" `
  -ManifestPath <manifest.json> -IconPath <icon> [-MediaPaths a.png,b.png] -OutputZip <pluginId>.zip
```

If the script prints `ASSET VALIDATION FAILED`, relay each error to the user (e.g. icon not square, wrong dimensions, unsupported extension) and ask them to fix or replace the file, then re-run.

## Step 5 — Optional live actions against a running app (bonus)
The skill can work against the **real application** when the user supplies its **root URL** + a **bearer token**. Make this explicit:
*"Ak mi dáš root URL aplikácie a bearer token, viem plugin overiť — prípadne aj nahrať — voči reálnej aplikácii. Čo chceš spraviť?"*

Offer three options:
- **Preskočiť** — local checks already passed; finish, the user keeps the `.zip`.
- **Len overiť (validate)** — dry-run validation, nič sa neuloží.
- **Overiť a nahrať (validate + deploy)** — validate first, and on success upload the plugin.

If the user picks validate or validate+deploy, ask for:
- **gateway root URL** — **iba koreňová adresa gatewaye**, napr. `https://localhost:5001`. **Nezadáva celú cestu** — gateway prefix `/api` aj `/admin/plugins/validate` (resp. `/admin/plugins`) doplní skript/skill sám.
- **bearer token**.

**Validate** — re-run the script adding the gateway root URL: `-ValidateUrl <gatewayRootUrl> -Token <token>` (the script appends `/api/admin/plugins/validate`).
- On `valid` → if mode is *len overiť* → done; if *overiť a nahrať* → go to deploy below.
- On `invalid` → relay each server error, fix the manifest, rebuild, and re-validate.

**Deploy** (only when mode = *overiť a nahrať* **and** validation passed):
First **inform** the user: *"Nahraním sa plugin vytvorí v stave **Draft** a bude viditeľný iba pre teba."*
Then confirm explicitly (this is a real upload): *"Pokračovať v nahratí?"* — only on a clear yes, POST the same zip to the gateway upload endpoint, reusing the same gateway root URL + token.

**Run this in PowerShell (`pwsh`), NOT bash** — it is PowerShell syntax and will fail with a shell parse error in bash. Use exactly this documented call; do **not** re-implement it with `HttpClient`, manual redirect handling, etc. (that complexity is unnecessary and only obscures the real cause when something fails):

```powershell
$root = $gatewayRootUrl.TrimEnd('/')
Invoke-RestMethod -Uri "$root/api/admin/plugins" -Method Post -InFile "<pluginId>.zip" `
  -ContentType 'application/zip' -Headers @{ Authorization = "Bearer $token" }
```

  - `201` → success; report `pluginId`, `version`, and `outcome` (`created` for a first version, `updated` for a re-upload). The plugin is now a **Draft** visible only to the uploader.
  - `400` → relay the `errors.manifest[]` list, fix, rebuild, and retry.
  - `401` (often body `Authorization service forbidden this request.`) → **token problem, not a route/call problem. Diagnose, don't guess:** re-run the SAME token against `/validate`. If `/validate` now ALSO returns 401 → the token expired/invalid → ask the user for a fresh token and retry the documented call unchanged. If `/validate` still returns 200 but upload returns 401 → it is a genuine upload-specific issue → investigate (do NOT conclude "expired token" and do NOT change the call mechanics). **Never** change both the token and the call method at once — you then can't tell which fixed it.
  - `403` → the partner is owned by a different uploader (the `partnerId` is taken) — stop and tell the user.
  - `409` → version conflict (incoming version must be greater than the published one) — bump `plugin.version` and retry.

## Notes
- The script only validates package/binary rules and assembles the zip; YOU enforce the manifest field rules from the reference while collecting input.
- Media files are packaged as `media/NN-<originalname>` — the script auto-prefixes each with a zero-padded ordinal (`01-`, `02-`, …) in the order given, so two source files with the same base name never collide.
- Two package rules are **server-side only** (the script does not check them, because it never produces a violation itself): the compression ratio ≤100 cap and the "no `..` / no rooted paths" rule — the script generates every entry name, so paths are always safe.
- Script exit codes: `1` = local asset validation failed (`ASSET VALIDATION FAILED`); `2` = live `/validate` returned `invalid` (server errors follow); `3` = the `/validate` request itself failed (network/auth/route). `0` = package built (and, if `-ValidateUrl` was passed, validated).
- License types are kebab-case, NOT SPDX: `apache-20`, `gpl-30`, `lgpl-30` (not `apache-2.0`).
- The `/validate` and `/admin/plugins` endpoints require a bearer token (the user supplies it).
