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

5. **Sparkle update signing key** (in-app updates, #27)
   - Sparkle installs an update only if it is signed with the private half
     of an EdDSA key whose public half ships in the app. Lose the private
     key and existing installs can never update in-app again, so back it up
     like the Developer ID `.p12`.
   - Generate it once, on a Mac you trust (the private key goes into your
     login keychain):

     ```bash
     scripts/fetch_sparkle.sh
     build/Sparkle/bin/generate_keys            # prints the public key
     build/Sparkle/bin/generate_keys -x sparkle_private_key
     ```

   - Paste the printed public key into `PUBLIC_ED_KEY` in
     `scripts/build_direct.sh` and commit it (it's public by design).
   - Add the contents of `sparkle_private_key` as the Actions secret
     `SPARKLE_ED_PRIVATE_KEY`, then delete the file.
   - Secrets can't be read back, so keep a backup you can read (e.g. a
     password manager). To check a backup, or to recover the public key
     once the key is gone from the keychain, run the backup through
     `swift scripts/sparkle_public_key.swift < backup-file`; it must print
     `PUBLIC_ED_KEY`.

6. **Homebrew cask**: add `auto_updates true` to
   `heyeuca/homebrew-tap/Casks/tilde.rb`, so `brew upgrade` leaves Tilde to
   its own updater instead of both trying to replace the app.

7. **Test the pipeline without publishing**: Actions → Release →
   Run workflow. This builds, signs, notarizes, and staples, then uploads
   the DMG and its appcast as an artifact instead of creating a release.

### Cutting a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

That's it. The Release workflow builds a signed, notarized, stapled DMG and
attaches it to a GitHub release with generated notes.

The DMG is attached twice: as `Tilde-vX.Y.Z.dmg` (referenced by the Homebrew
cask) and as a fixed-name `Tilde.dmg`, so the landing page can link to
`https://github.com/heyeuca/Tilde/releases/latest/download/Tilde.dmg` and
always get the newest release. Note that `latest/download/Tilde.dmg` 404s for
releases cut before this was added (v1.0.1 and earlier).

### What the pipeline does

`scripts/build_direct.sh` (hardened runtime + sandbox from project
settings, plus Sparkle) → codesign Sparkle's nested code, then the app,
with Developer ID → `scripts/make_dmg.sh` → sign the DMG → `notarytool
submit --wait` → `stapler staple` → Gatekeeper check (`spctl`) →
`scripts/make_appcast.sh` → publish.

### In-app updates (Sparkle)

The DMG build has **Tilde → Check for Updates…**, backed by
[Sparkle](https://sparkle-project.org) (#27). The App Store build doesn't:

- Sparkle isn't in the Xcode project. `scripts/build_direct.sh` fetches a
  pinned release (`scripts/fetch_sparkle.sh`, SHA-256 checked), links it
  through `FRAMEWORK_SEARCH_PATHS`, embeds it, and adds the `SU*` keys to
  the built app's Info.plist. `Tilde/App/Updater.swift` compiles only
  `#if canImport(Sparkle)`, so every other build skips it. CI checks both
  sides: the plain build has no Sparkle, the DMG build links it.
- The sandbox exception Sparkle needs (`mach-lookup` for
  `co.euca.Tilde-spks` / `-spki`) lives in `Tilde/Distribution.entitlements`,
  which only the DMG build uses.
- Checks happen only when the user picks the menu item:
  `SUEnableAutomaticChecks` and `SUAllowsAutomaticUpdates` are off
  (PRODUCT.md §29).
- The feed is `appcast.xml`, attached to each release and read from
  `releases/latest/download/appcast.xml`, so it lists only the newest
  release. Its release notes are the body of `docs/releases/vX.Y.Z-draft.md`
  up to `## Install`.
- Sparkle compares `CFBundleVersion` (`CURRENT_PROJECT_VERSION`), so bump it
  for every release, as already required for the App Store.
- To bump Sparkle, change `SPARKLE_VERSION` and `SPARKLE_SHA256` in
  `scripts/fetch_sparkle.sh` (the hash is listed on the GitHub release
  asset).

## App Store

- The sandbox and hardened runtime are already enabled, so the same target
  archives for the store.
- First submission: Xcode → Product → Archive → Distribute (App Store
  Connect) on the Xcode machine, then fill in the listing (screenshots,
  description, review notes) in App Store Connect.
- Version/build numbers live in the project (`MARKETING_VERSION`,
  `CURRENT_PROJECT_VERSION`); bump them per release.
