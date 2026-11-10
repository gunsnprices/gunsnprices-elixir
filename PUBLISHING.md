# Publishing to Hex

Package: `gunsnprices` — https://hex.pm/packages/gunsnprices (the name was free on 2026-11-10:
`https://hex.pm/api/packages/gunsnprices` returned 404).

After publishing:

- package page: https://hex.pm/packages/gunsnprices (links: Website → https://gunsnprices.com, GitHub)
- documentation, uploaded by `mix hex.publish` together with the package: https://hexdocs.pm/gunsnprices
- the package also shows up on https://diff.hex.pm and in the Hex search; nothing else to register.

Publishing is permanent in practice: within the first hour (and within 24 hours for the first version of a new
package) `mix hex.publish --revert 0.1.0` removes a version; after that a version can only be *retired*
(`mix hex.retire gunsnprices 0.1.0 invalid --message "..."`), which warns users but keeps it downloadable.

## 1. Account

1. Create an account at https://hex.pm/signup (username, e-mail, password), for example with app@gunsnprices.com,
   and confirm the e-mail address from the link Hex sends. Or create it from the command line:
   `mix hex.user register`.
2. Optional, recommended: an organization-style owner. Hex packages are owned by users; add a second owner after the
   first publish so the package does not depend on one account: `mix hex.owner add gunsnprices <other-user-or-email>`.
3. Turn on two-factor authentication in the account settings (https://hex.pm/dashboard/security).

## 2. Authenticate this machine

```bash
mix local.hex --force       # install or update Hex
mix hex.user auth           # asks for username and password, then a local password that encrypts the stored key
mix hex.user whoami         # check
```

`mix hex.user auth` stores an API key in `~/.hex/hex.config` (encrypted with the local password). For CI instead
generate a key with only the publish permission: `mix hex.user key generate --key-name gh-actions --permission api:write`
and keep it as a secret (`HEX_API_KEY`); never commit it.

## 3. Publish

Requires Elixir 1.18+ on a clean checkout of `main` with the version in `mix.exs` and `CHANGELOG.md` already bumped. The
GitHub repository `gunsnprices/gunsnprices-elixir` should exist and be public first: the package page and the docs
("View source" links, `source_ref: "v0.1.0"`) point to it.

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test                      # golden: 1,150/1,150 titles, doctests
mix docs                      # builds doc/ with ExDoc; open doc/index.html to check
mix hex.build                 # builds gunsnprices-0.1.0.tar and lists the files and metadata; check them
mix hex.publish               # shows the same summary, asks for confirmation, uploads the package and the docs
git tag v0.1.0 && git push origin v0.1.0
```

`mix hex.build` passed on 2026-11-10 (see the file list it prints: `lib/`, `priv/data/*.json`, `tools/gen_tables.py`,
`mix.exs`, `README.md`, `CHANGELOG.md`, `LICENSE`, `LICENSE-DATA`, `.formatter.exs`). Hex checks the licenses against
the SPDX list: `MIT` and `CC-BY-4.0` are both valid identifiers.

`mix hex.publish docs` re-uploads only the documentation (for a docs fix without a new version).

## 4. Later releases from GitHub Actions (optional)

```yaml
name: Publish to Hex
on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+*']
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.19"
          otp-version: "28"
      - run: mix deps.get
      - run: mix hex.publish --yes
        env:
          HEX_API_KEY: ${{ secrets.HEX_API_KEY }}
```

Release: bump the version in `mix.exs` and `CHANGELOG.md`, commit, `git tag vX.Y.Z && git push origin vX.Y.Z`.
