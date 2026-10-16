# Microsoft Store submission runbook — RunCat Lumina

End-to-end path from source to a published Store app. Prerequisites:
`docs/PARTNER-CENTER.md` done (account + name reserved + Publisher string).

## Step 0 — Prerequisites on the build machine (once)

- Python 3.9+ (64-bit) on PATH
- `pip install pyinstaller` (the build script installs it automatically if missing)
- Windows SDK → provides `makeappx.exe` + `signtool.exe`
  - Via **Visual Studio 2022 Build Tools** → workload *Desktop development with C++*
    → individual component **Windows 10/11 SDK**, or the standalone SDK installer
- The repo's packaging files (`packaging/windows/...`)

## Step 1 — Build the final Store package

On Windows, from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File packaging\windows\build-msix.ps1 -Publisher "CN=<your Partner Center Publisher ID>"
```

Output:

- `dist\msix\RunCatLumina-1.0.0.0-x64.msix` ← upload this
- `dist\msix\RunCatLumina-1.0.0.0-x64.cer`  ← local test certificate

CI alternative: GitHub Actions workflow **msix** (`.github/workflows/msix.yml`)
→ *Run workflow* → paste the same Publisher string → download the `RunCatLumina-msix`
artifact.

> The package is signed with a certificate whose subject equals the Publisher.
> Partner Center replaces the package signature with Microsoft's Store signature
> when the app is published — the Publisher string is what must match exactly.

## Step 2 — Local sanity check (recommended, 3 minutes)

```powershell
Import-Certificate -FilePath dist\msix\RunCatLumina-1.0.0.0-x64.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople
# Settings > Privacy & security > For developers > Developer Mode: On
Add-AppxPackage -Path dist\msix\RunCatLumina-1.0.0.0-x64.msix
```

Verify: Start menu tile **RunCat Lumina** → cat animates in tray → left-click opens
Settings → relaunch opens Settings → uninstall removes it
(`Get-AppxPackage AlAsarJadeed.RunCatLumina | Remove-AppxPackage`).

## Step 3 — Create the submission

1. https://partner.microsoft.com/dashboard → **Apps & games → Overview**
2. **+ New app** → **App** → packaging: **MSIX or PWA app** → name `RunCat Lumina`
3. Left navigation of the submission:

| Page | What to do |
|---|---|
| **Package** | Upload `RunCatLumina-1.0.0.0-x64.msix` (upload the `.cer` too if the form offers a signing certificate) |
| **Product properties** | Category: Utilities & tools (secondary: Personalization); hardware/other requirements: none |
| **Store listing** | Language: English — paste content from `STORE-LISTING.md`, upload `ProductLogo-512.png` + screenshots |
| **Pricing and availability** | Price **Free**, markets: All |
| **Notes for certification** | Paste the "Notes for certification" block from `STORE-LISTING.md` |
| **Overview** | Fix any errors the form flags, then **Submit** |

## Step 4 — Certification

- Status visible on the submission: **Pre-processing → Certification → Publishing**
- Typical duration: **1–3 business days** (up to 7)
- If Microsoft rejects or requests changes: **Resolved issues** tab shows the
  reason — fix, rebuild (bump version only if package changes are needed), re-upload, resubmit
- Common causes for this app type are listing-asset problems, not the app itself;
  the tray-app note in Step 3 prevents the "nothing launches" false rejection

## Step 5 — After publishing

- Verify: Microsoft Store → search **RunCat Lumina** → install → run
- The app is live in all markets selected in Step 3

## Step 6 — Publishing an update

1. Bump `VERSION` (e.g. `1.0.1`) — package version must always increase
2. Rebuild: `build-msix.ps1 -Publisher "CN=<same Publisher>"`
3. Partner Center → **Apps & games → your app → + New submission**
4. Upload the new package, update *What's new* text, Submit

## Troubleshooting

| Symptom | Fix |
|---|---|
| Upload rejected: publisher mismatch | Manifest Publisher ≠ Partner Center Publisher — rebuild with the exact string |
| `Add-AppxPackage` fails 0x800B0109 | Test certificate not trusted → import `.cer` into `LocalMachine\TrustedPeople` |
| `makeappx`/`signtool` not found | Install Windows SDK or pass `-SdkDir` |
| AV warning on the exe | Store spec already disables UPX; report is rare — resubmit with explanation |
| Console window flashes | You built `RunCat-Lumina.spec` instead of the store spec — use `build-msix.ps1` |
