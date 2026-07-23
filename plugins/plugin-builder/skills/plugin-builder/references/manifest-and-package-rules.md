# Manifest & Package Rules (authoritative)

Verified against `Kros.Framework.Plugins.Core/Manifest/ManifestDocument.cs`, `Kros.Framework.Plugins.Admin/Validators/**`, `Kros.Framework.Plugins.Core/Package/PluginPackage.cs`, and the enum kebab-case converter + tests. JSON property matching is **case-insensitive**; unknown properties are ignored. Validate EVERY generated field against this before writing.

## Top level (all required, non-null)
`manifestVersion`, `plugin`, `display`, `partner`, `authentication`.
- `manifestVersion`: non-empty, SemVer 2.0. Always emit `"1.0.0"` (schema version).

## plugin
- `id`: required, max 50, regex `^sk\.[a-z0-9-]+\.[a-z0-9-]+$`, and the **middle segment must equal `partnerId`**.
- `partnerId`: required, max 50, regex `^[a-z0-9-]+$`.
- `name`: required, 3–50 chars, trimmed, no control chars.
- `version`: required, max 20, SemVer 2.0.
- `changelog`: if present 20–5000 chars (only `\n \r \t` + printable). First version → MUST be `null`; subsequent versions → REQUIRED.
- `requiresReconfiguration`: bool, default `false`.

## display
- `shortDescription`: required, 10–150 chars, trimmed.
- `categories`: required. Aktuálne nasadenie podporuje len jedinú kategóriu → musí byť presne `["invoicing"]` (viď category enum nižšie).
- `tags`: optional, ≤10, distinct (case-insensitive); each 2–30 chars, regex `^[a-z0-9-]+$`.
- `detail.description`: required, 50–20000 chars, trimmed (markdown).

## partner
- `name`: required, 3–50, trimmed, no control chars.
- `website`, `privacyPolicyUrl`: optional, max 500, **https**.
- `contact`: required. `license`: required.
- **≥1 contact channel required**: non-empty `contact.email` OR `contact.supportUrl` OR `website`.

### partner.contact (each a single optional string — NOT a list)
- `email`: valid email, max 200, trimmed.
- `phone`: regex `^\+?[0-9 ()-]+$`, 6–50 chars, ≥6 digits.
- `supportUrl`, `documentationUrl`: **https**, max 500.

### partner.license
- `type`: required, from the license enum below.
- `url`: optional, max 500, **https**; REQUIRED when `type` is `proprietary` or `other`.

## authentication (XOR)
- `method`: required — `token-broker` | `manual`.
- `token-broker` → `tokenBroker` present, `manual` MUST be null.
  - `tokenBroker.baseUrl`: required, max 500, **https**.
  - `tokenBroker.apiKey`: required, max 200. The partner's **real API key** — a plain string the partner supplies. NOT a secret-ref/placeholder like `Plugins:<id>:ApiKey`; the framework binds this value directly (JSON property `apiKey`).
- `manual` → `manual` present, `tokenBroker` MUST be null.
  - `manual.redirectUrl`: required, max 2048, **http or https**.

## Enums (kebab-case — NOT SPDX)
> ⚠️ **Enumy sú deployment-špecifické.** License a auth hodnoty nižšie sú z referenčného Frameworku, ale konkrétne nasadenie ich môže mať podmnožinu/inú sadu. **Pred generovaním over hodnoty proti zdroju nasadenia** — `…/Kros.Framework.Plugins.Core/Enums/PluginCategory.cs` — alebo dry-run cez `/validate` a podľa chyby `Value 'x' is not a recognized PluginCategory` oprav. Nikdy slepo nedôveruj širším zoznamom.
- **category**: aktuálne nasadenie podporuje **len `invoicing`**. `categories` teda musí byť presne `["invoicing"]`. (Framework enum môže časom pribrať ďalšie hodnoty — vtedy over voči `PluginCategory.cs` / `/validate`.)
- **license type**: `proprietary`, `mit`, `apache-20`, `gpl-30`, `bsd-3-clause`, `lgpl-30`, `other`.
  > The converter hyphenates on letter/digit boundaries only: `Apache20`→`apache-20`, `Gpl30`→`gpl-30`, `Lgpl30`→`lgpl-30`, `Bsd3Clause`→`bsd-3-clause`. Do NOT use `apache-2.0`/`gpl-3.0`.
- **auth method**: `token-broker`, `manual`.

## ZIP package layout & limits
- Root must contain `manifest.json` + exactly one `icon.<ext>` (ext ∈ png, jpg, jpeg, webp, svg). Optional `media/` folder, flat (no nested subfolders). Nothing else allowed.
- `media/`: ≤10 files; ext ∈ png, jpg, jpeg, webp (NO svg).
- Limits: ≤25 file entries; ≤5 MB/entry uncompressed; ≤15 MB total; compression ratio ≤100; no `..`; no rooted paths.
- Icon content: magic-byte MIME must match extension; svg → dimensions not enforced; else 64–1024 px both sides AND square.
- Media content: MIME must match extension (no svg); dimensions 320×180 min, 1920×1080 max.
- MIME/ext: `.png`→image/png, `.jpg`/`.jpeg`→image/jpeg, `.webp`→image/webp, `.svg`→image/svg+xml (icon only).

## Endpoints
The user supplies the **gateway root URL** (e.g. `https://localhost:5001`); the skill targets the gateway forms (Ocelot `/api` prefix). Direct-service forms (without `/api`) exist but the skill does not use them.
- `POST {gatewayRoot}/api/admin/plugins/validate` — body raw `application/zip`. Returns `200 {"valid":bool,"errors":[string]}`. Requires `Authorization: Bearer <token>` (401 otherwise). Dry-run, no persistence.
- `POST {gatewayRoot}/api/admin/plugins` — upload → `201 {pluginId,version,outcome}` (`outcome` = `created` | `updated`) | `400 {errors:{manifest:[...]}}` | `403` | `409`.

## Sample — token-broker
```json
{
  "manifestVersion": "1.0.0",
  "plugin": { "id": "sk.numera.cashflow-insight", "partnerId": "numera", "name": "Cashflow Insight", "version": "1.2.0", "requiresReconfiguration": false },
  "display": {
    "shortDescription": "Prediktívna analýza cashflow s 90-dňovým výhľadom.",
    "categories": ["invoicing"],
    "tags": ["cashflow", "forecasting", "analytics"],
    "detail": { "description": "## Cashflow Insight\n\nMarkdown popis dlhý aspoň 50 znakov ..." }
  },
  "partner": {
    "name": "Numera Analytics s.r.o.",
    "website": "https://numera-analytics.example.com",
    "privacyPolicyUrl": "https://numera-analytics.example.com/privacy",
    "contact": { "email": "support@numera-analytics.example.com", "supportUrl": "https://numera-analytics.example.com/support" },
    "license": { "type": "proprietary", "url": "https://numera-analytics.example.com/eula" }
  },
  "authentication": { "method": "token-broker", "tokenBroker": { "baseUrl": "https://samplePlugin.localhost", "apiKey": "numera-live-api-key-abc123" } }
}
```

## Sample — manual
```json
{
  "manifestVersion": "1.0.0",
  "plugin": { "id": "sk.payhub.merchant-portal", "partnerId": "payhub", "name": "PayHub Merchant Portal", "version": "3.0.0", "requiresReconfiguration": false },
  "display": {
    "shortDescription": "Externý portál pre obchodníkov akceptujúcich kartové platby.",
    "categories": ["invoicing"],
    "tags": ["payments", "gateway", "merchant"],
    "detail": { "description": "## PayHub Merchant Portal\n\nMarkdown popis dlhý aspoň 50 znakov ..." }
  },
  "partner": {
    "name": "PayHub Slovensko s.r.o.",
    "website": "https://payhub.example.com",
    "contact": { "email": "support@payhub.example.com" },
    "license": { "type": "proprietary", "url": "https://payhub.example.com/terms" }
  },
  "authentication": { "method": "manual", "manual": { "redirectUrl": "https://merchant.payhub.example.com/login?ref=kros-invoicing" } }
}
```
