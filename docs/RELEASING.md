# Releasing to App Store Connect

Releases are archived and uploaded to **TestFlight** by the
[`Release to TestFlight`](../.github/workflows/release.yml) GitHub Actions
workflow, driven by [fastlane](../fastlane/Fastfile). Signing assets are managed
with **fastlane match**; authentication uses an **App Store Connect API key**.

## One-time setup

### 1. App Store Connect API key
App Store Connect → **Users and Access → Integrations → App Store Connect API**
→ create a key with the **App Manager** role. Download the `.p8` (you only get
one chance). Note the **Key ID** and the team **Issuer ID**.

Base64-encode the key for the secret:

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

### 2. match signing repo
Create a **separate, empty private git repo** (e.g. `fm-rodeo/televista-certs`).
It's an encrypted storage backend for the distribution certificate and
provisioning profile — **nothing else goes in it**. Do *not* copy the `Gemfile`,
`fastlane/` config, or any app code into it; `match` populates it for you.

Run the commands below **from this (televista) project root** — that's where the
`Gemfile` and `fastlane/Matchfile` live. `match` reads `MATCH_GIT_URL`, then
reaches over and commits encrypted signing files into the certs repo itself:

```sh
# in the televista repo (NOT the certs repo)
bundle install
export MATCH_GIT_URL="git@github.com:KevM/20four7-certs.git"   # SSH is fine locally
export DEVELOPMENT_TEAM="6HQGHHRK87"
bundle exec fastlane match appstore   # prompts you to set MATCH_PASSWORD
```

This creates the cert/profile in your Apple account and commits encrypted copies
to the certs repo (you'll see it gain `certs/` and `profiles/` folders). CI pulls
them in `readonly` mode and can never mint/revoke.

> **SSH locally, HTTPS in CI.** Locally `match` clones the certs repo over SSH
> using your key. The CI runner has no SSH key, so the `MATCH_GIT_URL` *secret*
> must be the **HTTPS** URL and auth goes through `MATCH_GIT_BASIC_AUTHORIZATION`
> (see below). The local `Matchfile`/env and the CI secret can legitimately
> differ in scheme.

### 3. GitHub repo secrets
Settings → **Secrets and variables → Actions** → add:

| Secret | base64? | Value |
| --- | --- | --- |
| `DEVELOPMENT_TEAM` | no | `6HQGHHRK87` |
| `ASC_KEY_ID` | no | App Store Connect API Key ID — short ~10 chars, e.g. `2X9R4HXF34` |
| `ASC_ISSUER_ID` | no | App Store Connect Issuer ID — a **UUID** (`8-4-4-4-12`) |
| `ASC_KEY_CONTENT` | **yes** | base64 of the `.p8` (from step 1) |
| `MATCH_GIT_URL` | no | **HTTPS** URL: `https://github.com/KevM/20four7-certs.git` |
| `MATCH_PASSWORD` | **no** | the raw match passphrase from step 2 — *not* encoded |
| `MATCH_GIT_BASIC_AUTHORIZATION` | **yes** | base64 of `KevM:<PAT>` so CI can clone the private certs repo |

**The PAT for `MATCH_GIT_BASIC_AUTHORIZATION`** must actually have access to the
certs repo, or CI fails the clone with exit 128 ("make sure you have read
access"). Create a **fine-grained token**:

- **Resource owner:** `KevM`
- **Repository access:** **Only select repositories** → `KevM/20four7-certs`
  *(the default "Public repositories" can't see a private repo — this is the
  step that's easy to miss; a token that can authenticate but returns 404 on the
  repo means this wasn't set)*
- **Permissions:** Repository → **Contents: Read-only** (CI runs match readonly)

Then base64 `username:token` (the `-n` matters — a trailing newline breaks auth):

```sh
echo -n "KevM:github_pat_xxxxxxxx" | base64
```

Verify the PAT before saving the secret — this mirrors exactly what match does:

```sh
git -c http.extraheader="Authorization: Basic $(echo -n 'KevM:github_pat_xxxxxxxx' | base64)" \
  ls-remote https://github.com/KevM/20four7-certs.git
```

A list of refs = good. An error = the repo-access checkbox isn't set.

## Cutting a release

1. Make sure the build number is current. It auto-increments on every merged PR
   via [`bump-build.yml`](../.github/workflows/bump-build.yml); bump
   `MARKETING_VERSION` in [`project.yml`](../project.yml) by hand for a new
   marketing version.
2. Tag and push:

   ```sh
   git tag v1.0.1      # match MARKETING_VERSION
   git push origin v1.0.1
   ```

   (Or trigger **Release to TestFlight** manually from the Actions tab.)
3. The workflow archives a signed build and uploads it to TestFlight. Once Apple
   finishes processing (a few minutes), it appears under TestFlight in App Store
   Connect.

## Promoting to the App Store

This pipeline stops at TestFlight. To push a build to App Store review, either do
it in App Store Connect, or add a `release` lane to the Fastfile using
`upload_to_app_store` (deliver) with metadata/screenshots — ask and it can be
wired up.

## Running locally

```sh
bundle install
export $(grep -v '^#' .env | xargs)   # DEVELOPMENT_TEAM, etc.
export ASC_KEY_ID=... ASC_ISSUER_ID=... MATCH_GIT_URL=...
export ASC_KEY_CONTENT="$(base64 -i AuthKey_XXXXXXXXXX.p8)"
read -rs MATCH_PASSWORD; export MATCH_PASSWORD   # type it; avoids shell mangling
bundle exec fastlane beta
```

macOS will prompt **twice for your keychain password** during the archive — that's
`codesign` accessing the distribution key. Normal locally; CI never prompts
(`setup_ci` uses a throwaway keychain).

## Troubleshooting

Hard-won notes from the initial setup:

- **"Invalid password passed via 'MATCH_PASSWORD'."** The passphrase you supplied
  ≠ the one that encrypted the repo. `MATCH_PASSWORD` is **raw, never base64**. The
  usual cause is *shell mangling*: `export MATCH_PASSWORD="p$ass!word"` lets the
  shell eat `$ass` / `!word`. Set it with single quotes, or better `read -rs`
  (above). In the GitHub UI, paste the raw value — no quotes, no trailing newline.
  The passphrase is **not stored anywhere recoverable** if you used an env var on
  first run, so keep it in a password manager. Prefer a passphrase with no
  shell-special characters (e.g. `openssl rand -base64 24` — the output *is* the
  password, you don't encode it again).
- **"Authentication credentials are missing or invalid" (API key).** One of the
  three `ASC_*` values is wrong. Most common: `ASC_KEY_CONTENT` is the *raw* `.p8`
  but the Fastfile sets `is_key_content_base64: true`, so it must be **base64**.
  Raw key starts with `-----BEGIN PRIVA…`; correct base64 starts with `LS0tLS1…`.
  Also check `ASC_KEY_ID` (short) and `ASC_ISSUER_ID` (UUID) aren't swapped, and
  that the `.p8` belongs to that Key ID (filename is `AuthKey_<KEYID>.p8`).
- **Clone fails, exit 128 / "make sure you have read access."** The
  `MATCH_GIT_BASIC_AUTHORIZATION` PAT lacks access to the certs repo — see the
  fine-grained token setup in step 3.
- **"Could not create another Distribution certificate…maximum reached."** Apple
  caps distribution certs (usually 2). Either `bundle exec fastlane match nuke
  distribution` then re-run `match appstore`, or revoke a stray cert in the Apple
  Developer portal. Already-uploaded TestFlight builds are unaffected by revoking.
- **"Build already exists" on upload.** The build number (`CURRENT_PROJECT_VERSION`)
  was already used. It auto-bumps on PR merge via `bump-build.yml`; a **local
  `fastlane beta` consumes a number out-of-band**, so the next upload must be
  higher.
