# Android APK signing for GitHub releases

The `Release` workflow (`.github/workflows/release.yml`) builds and signs the
Android APK automatically when you push a tag like `v1.2.0`.

There are two modes:

| Mode | When | Effect on updates |
|---|---|---|
| **Persistent keystore** (recommended) | Repository secrets are set | Every release shares one signature, so a new APK installs **over** the old one and keeps app data/settings. |
| **Ephemeral keystore** (default) | No secrets set | Each release is signed with a fresh key, so Android refuses in-place updates — you must **uninstall** the old version first. |

A Google Play developer account is **not** required. These releases are signed
APKs attached to GitHub Releases, not Play Store uploads.

## 1. Create a keystore (once)

You need a JDK installed (`keytool` ships with it).

macOS/Linux:

```bash
keytool -genkeypair -v \
  -keystore parakeet-release.p12 \
  -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias release
```

Windows PowerShell:

```powershell
keytool -genkeypair -v `
  -keystore parakeet-release.p12 `
  -storetype PKCS12 `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias release
```

It asks for a keystore password and your name/org (any value is fine for a
personal build). Keep the same value for the key password when prompted
(press Enter to reuse the store password).

**Back up the keystore and passwords.** Losing them means you can never ship an
in-place update under the same app identity again.

## 2. Base64-encode the keystore

GitHub secrets store text, so encode the binary keystore.

macOS:

```bash
base64 -i parakeet-release.p12 | pbcopy
```

Linux:

```bash
base64 -w0 parakeet-release.p12 > keystore.base64.txt
```

Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("parakeet-release.p12")) `
  | Out-File -Encoding ascii keystore.base64.txt
```

## 3. Add the four repository secrets

Using the GitHub CLI from the repo folder:

```bash
gh secret set RELEASE_KEYSTORE_BASE64 < keystore.base64.txt
gh secret set RELEASE_KEYSTORE_PASSWORD   # paste the keystore password
gh secret set RELEASE_KEY_ALIAS           # type: release
gh secret set RELEASE_KEY_PASSWORD        # paste the key password
```

Or via the web UI: **Settings → Secrets and variables → Actions → New repository secret**.

| Secret | Value |
|---|---|
| `RELEASE_KEYSTORE_BASE64` | base64 contents of `parakeet-release.p12` |
| `RELEASE_KEYSTORE_PASSWORD` | the keystore password |
| `RELEASE_KEY_ALIAS` | `release` |
| `RELEASE_KEY_PASSWORD` | the key password |

The workflow defaults to PKCS12. If your keystore is an older JKS file, set the
optional repository variable `RELEASE_KEYSTORE_TYPE` to `JKS`.

## 4. Build a release

```bash
git tag v1.2.0
git push origin v1.2.0
```

The workflow:

- sets `versionName` from the tag (`v1.2.0` → `1.2.0`)
- sets `versionCode` from the workflow run number
- signs with the persistent keystore when secrets are present
- uploads `ParakeetFlow-v1.2.0.apk` to a GitHub Release

Install it on your phone (requires “install from unknown sources”).

> **Switching from the old ephemeral key:** uninstall the previously installed
> APK once, then install the first persistent-key build. After that, updates
> install in place.

> **Keep versionCode increasing.** The workflow uses `github.run_number`, which
> normally increases on every release. If you ever recreate the workflow or
> publish from multiple places, use a tag-derived or timestamp-derived value
> instead so `versionCode` never goes backwards.

Delete `parakeet-release.p12` and `keystore.base64.txt` from any synced/cloud
folder after uploading — they are your signing identity.
