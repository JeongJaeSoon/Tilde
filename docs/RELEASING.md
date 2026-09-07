# Releasing Tilde

Two channels: **direct download** (signed + notarized DMG via GitHub
Releases, fully automated) and the **App Store** (manual first submission
through Xcode Organizer; automate updates later if it earns its keep).

## Direct download (DMG)

### One-time setup

1. **Developer ID Application certificate**
   - Xcode → Settings → Accounts → Manage Certificates → `+` →
     Developer ID Application (or create via developer.apple.com with a CSR)
   - Keychain Access → export the certificate *with its private key* as
     `.p12`, choosing a password

2. **App Store Connect API key** (used by `notarytool`)
   - App Store Connect → Users and Access → Integrations → Keys → `+`
   - Role: Developer is enough. Download the `.p8` (one chance only) and
     note the **Key ID** and **Issuer ID**

3. **Repository secrets** (GitHub → Settings → Secrets and variables → Actions)

   | Secret | Value |
   | --- | --- |
   | `MACOS_CERT_P12` | `base64 -i cert.p12 \| pbcopy` |
   | `MACOS_CERT_PASSWORD` | the .p12 password |
   | `APPLE_TEAM_ID` | the team ID (Membership page) |
   | `ASC_KEY_P8` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
   | `ASC_KEY_ID` | the API key's Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID (Keys page header) |

4. **Enable Homebrew Tap updates** (one time)
   - Create a fine-grained GitHub token restricted to the
     `heyeuca/homebrew-tap` repository.
   - Give it only `Contents: Read and write` repository permission.
   - Add it to this repository as the Actions secret
     `HOMEBREW_TAP_TOKEN`. Do not reuse a broad personal token or the local
     `gh` login token.
   - On tagged releases, the workflow reads the tag and the final DMG hash,
     updates `homebrew-tap/Casks/tilde.rb`, and pushes the change.

5. **Test the pipeline without publishing**: Actions → Release →
   Run workflow. This builds, signs, notarizes, and staples, then uploads
   the DMG as an artifact instead of creating a release.

### Cutting a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

That's it. The Release workflow builds a signed, notarized, stapled DMG and
attaches it to a GitHub release with generated notes.

### What the pipeline does

build (hardened runtime + sandbox from project settings) → codesign with
Developer ID → `scripts/make_dmg.sh` → sign the DMG → `notarytool submit
--wait` → `stapler staple` → Gatekeeper check (`spctl`) → publish.

## App Store

- The sandbox and hardened runtime are already enabled, so the same target
  archives for the store.
- First submission: Xcode → Product → Archive → Distribute (App Store
  Connect) on the Xcode machine, then fill in the listing (screenshots,
  description, review notes) in App Store Connect.
- Version/build numbers live in the project (`MARKETING_VERSION`,
  `CURRENT_PROJECT_VERSION`); bump them per release.
