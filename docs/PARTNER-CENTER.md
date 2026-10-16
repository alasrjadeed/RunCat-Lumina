# Microsoft Partner Center — account & setup (RunCat Lumina)

Partner Center dashboard: **https://partner.microsoft.com/dashboard**
Store section: **Apps & games** (an account already exists for this project — this
file covers everything needed *before* submitting.)

## 1. Get your exact Publisher string

Every MSIX package declares a `Publisher` that must match your Partner Center
account **byte-for-byte**, or the package upload is rejected.

1. Sign in to https://partner.microsoft.com/dashboard
2. Open **Account settings** (gear icon / your name menu)
3. Find the **Publisher ID** shown for your account (it looks like `CN=...`)
4. Use it as-is, e.g.:

```powershell
powershell -File packaging\windows\build-msix.ps1 -Publisher "CN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

If the label is not visible on the main Account settings page, check the
publisher/identity details section of your account profile. The string is also
echoed by Partner Center whenever you create a Windows package submission —
**copy it exactly, including `CN=`**.

> Local test builds default to `CN=AL ASAR JADEED`; only the final Store build
> needs the Partner Center value.

## 2. Reserve the product name

1. **Apps & games → Overview → Reserve app name** (or **+ New app**)
2. App type: **App** (not Game)
3. Packaging type: choose **MSIX or PWA app**
4. Display name: `RunCat Lumina`

Reserving early keeps the name yours. The listing display name
(`RunCat Lumina`) is independent of the internal package identity
(`AlAsarJadeed.RunCatLumina`).

## 3. New product form — what to pick

| Question | Answer |
|---|---|
| App or Game | **App** |
| Packaging | **MSIX or PWA app** (not "EXE or MSI app") |
| Internal package Identity Name | `AlAsarJadeed.RunCatLumina` (built into the .msix) |

**Why MSIX, not EXE/MSI:** the MSIX route lets the Store host, install, update
and uninstall the package cleanly. The EXE/MSI route only publishes your
installer — keep it as a fallback in case certification ever rejects the MSIX,
which is not expected for this app (no drivers, no services, no elevation).

## 4. Store policy checklist (this app)

- ✅ Runs full-trust but requires **no administrator rights**
- ✅ Uninstalls completely via Windows (MSIX removes all package files)
- ✅ No network calls, no telemetry, no account — simplifies privacy/age forms
- ✅ No bundled installers/adware/upsell
- ✅ Cat sprites are Apache-2.0 attributed in `README.md` and the listing credits
- ✅ Store build disables UPX and the console window (avoids AV heuristics)

## 5. Costs, review time, account state

- One-time registration fee: already paid when the account was created
- Tax/banking info: only required for **paid** apps; this app is free
- Certification after each submission: typically **1–3 days** (up to 7)
- Free apps can be published in all markets with no payout profile

## 6. Where things live in the dashboard

| Task | Location |
|---|---|
| Create submission | Apps & games → Overview → **+ New app** |
| Upload package | Submission → **Package** |
| Listing text/images | Submission → **Store listing** |
| Price/markets | Submission → **Pricing and availability** |
| Reviewer instructions | Submission → **Notes for certification** |
| Send for review | Submission → **Overview → Submit** |
| Reviewer feedback | Submission → **Resolved issues** |
| Publish an update | Apps & games → your app → **+ New submission** |

Next: follow `STORE-SUBMISSION.md` (runbook) and use the copy in
`STORE-LISTING.md`.
