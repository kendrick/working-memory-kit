# Changelog

Notable changes to working-memory-kit, grouped by type. release-please writes each release's section from the Conventional Commit history when its release PR merges. The kit installs from `main`, and each tagged release appears as a dated section.

## [0.4.0](https://github.com/kendrick/working-memory-kit/compare/v0.3.0...v0.4.0) (2026-11-18)


### Features

* **hooks:** nudge toward ltm promote for new decisionLog entries in a Bank-connected repo ([#63](https://github.com/kendrick/working-memory-kit/issues/63)) ([1199929](https://github.com/kendrick/working-memory-kit/commit/11999291b388fae38e038b77fedaa34c85ff2f71))
* **hooks:** put activeContext.md and the on-demand table into Claude Code's session context ([#62](https://github.com/kendrick/working-memory-kit/issues/62)) ([232735e](https://github.com/kendrick/working-memory-kit/commit/232735ede6ba6274142f140f2c49d280bebb1d8d))
* **hooks:** suggest a Stack review when a root manifest changed ([#4](https://github.com/kendrick/working-memory-kit/issues/4)) ([#83](https://github.com/kendrick/working-memory-kit/issues/83)) ([c3a3cdf](https://github.com/kendrick/working-memory-kit/commit/c3a3cdf7f163e411ee49715319b8aefb52e16d6e))
* **hydrate:** send findings that span repos to ltm propose ([#57](https://github.com/kendrick/working-memory-kit/issues/57)) ([3624453](https://github.com/kendrick/working-memory-kit/commit/36244530e21d6a4acde77f71a5fa07cc582240da))
* **installer:** detect a long-term-memory-kit Bank and point the hydration guide at ltm promote ([#55](https://github.com/kendrick/working-memory-kit/issues/55)) ([378d6b4](https://github.com/kendrick/working-memory-kit/commit/378d6b439b46acacc8904fce55936509ad844680))
* **installer:** offer a Prettier/oxfmt override that keeps metadata lines whole ([#66](https://github.com/kendrick/working-memory-kit/issues/66)) ([57f1c24](https://github.com/kendrick/working-memory-kit/commit/57f1c24da4be484a77d66de38b5722e0b88f8ed5))
* **plugin:** ship the kit as a Claude Code plugin whose init skill runs the installer ([#90](https://github.com/kendrick/working-memory-kit/issues/90)) ([75afe77](https://github.com/kendrick/working-memory-kit/commit/75afe77ae74591bd51b9cb23f964b5c786358ba2))
* **plugin:** warn at session start when a project's kit is older than the plugin ([#96](https://github.com/kendrick/working-memory-kit/issues/96)) ([a6aa7f9](https://github.com/kendrick/working-memory-kit/commit/a6aa7f9e603188eea26fd09309949d943debac2d))
* **template:** add per-entry status and superseded_by lines to both logs ([#61](https://github.com/kendrick/working-memory-kit/issues/61)) ([f3e2826](https://github.com/kendrick/working-memory-kit/commit/f3e2826d6e18f52c1d7db7ce7c15f7afbd17aa0a))


### Bug Fixes

* **hooks:** count work committed during the session in the session-end nudge ([#60](https://github.com/kendrick/working-memory-kit/issues/60)) ([69b2f12](https://github.com/kendrick/working-memory-kit/commit/69b2f12cbf6fec4ff1e7d1fbc93e627391dea3a6))
* **hooks:** escape the hooks' systemMessage JSON ([#47](https://github.com/kendrick/working-memory-kit/issues/47)) ([d431314](https://github.com/kendrick/working-memory-kit/commit/d431314498d649abb3dab5e862ca03db152b58e6))
* **hydrate-propose:** print the ltm propose command for PowerShell too ([#65](https://github.com/kendrick/working-memory-kit/issues/65)) ([a229e97](https://github.com/kendrick/working-memory-kit/commit/a229e977632c49e883bf8f953f9ed2caf673ccb4))
* **init.sh:** keep a leading BOM first when adding the .kitnew pointer ([#78](https://github.com/kendrick/working-memory-kit/issues/78)) ([#79](https://github.com/kendrick/working-memory-kit/issues/79)) ([69a9704](https://github.com/kendrick/working-memory-kit/commit/69a9704f28fd70a2609983062ef42ca32e22043a))
* **init.sh:** keep a leading BOM when editing CLAUDE.md and settings.json ([#72](https://github.com/kendrick/working-memory-kit/issues/72)) ([#77](https://github.com/kendrick/working-memory-kit/issues/77)) ([95496ee](https://github.com/kendrick/working-memory-kit/commit/95496eef3bd683ea005d276735870324ec1c20c6))
* **init.sh:** put the .kitnew pointer on its own line after an unterminated shebang or --- ([#84](https://github.com/kendrick/working-memory-kit/issues/84)) ([#88](https://github.com/kendrick/working-memory-kit/issues/88)) ([3db89e7](https://github.com/kendrick/working-memory-kit/commit/3db89e70c436d861952311dd26e957f419a2cba7))
* **installer:** collapse doubled slashes in the formatter override glob ([#67](https://github.com/kendrick/working-memory-kit/issues/67)) ([#75](https://github.com/kendrick/working-memory-kit/issues/75)) ([586f98d](https://github.com/kendrick/working-memory-kit/commit/586f98d39688ca89ea620d624f3ae686bbfec8ba))
* **installer:** install Claude Code session hooks into .claude/settings.json ([#53](https://github.com/kendrick/working-memory-kit/issues/53)) ([4a62cb0](https://github.com/kendrick/working-memory-kit/commit/4a62cb07b44b42a12cc30587c593053c780d9274))
* **installer:** keep a user file's bytes and BOM under Windows PowerShell 5.1 ([#70](https://github.com/kendrick/working-memory-kit/issues/70)) ([#71](https://github.com/kendrick/working-memory-kit/issues/71)) ([d7baf22](https://github.com/kendrick/working-memory-kit/commit/d7baf224708db235770eb8480504a68643b12456))
* **installer:** keep case-variant settings.json keys apart in init.ps1 ([#54](https://github.com/kendrick/working-memory-kit/issues/54)) ([#74](https://github.com/kendrick/working-memory-kit/issues/74)) ([9233753](https://github.com/kendrick/working-memory-kit/commit/923375367ff0fba65449c0a3d13d040c21e29a04))
* **installer:** keep internal spaces in .working-memoryrc values ([#42](https://github.com/kendrick/working-memory-kit/issues/42)) ([#46](https://github.com/kendrick/working-memory-kit/issues/46)) ([756ce02](https://github.com/kendrick/working-memory-kit/commit/756ce02ecf16e4498ce87835748de4565d615099))
* **installer:** remember a custom working-memory dir in .working-memoryrc ([#49](https://github.com/kendrick/working-memory-kit/issues/49)) ([b861bf8](https://github.com/kendrick/working-memory-kit/commit/b861bf8d4f4a80b54d4824a1ea0890d8bdebfd5a))
* **installer:** start an appended rc key on its own line ([#50](https://github.com/kendrick/working-memory-kit/issues/50)) ([#64](https://github.com/kendrick/working-memory-kit/issues/64)) ([5c50368](https://github.com/kendrick/working-memory-kit/commit/5c50368d239023f953e5f871e65e5308e84bdc66))
* **template:** give antipatterns.md decisionLog's heading grammar ([#56](https://github.com/kendrick/working-memory-kit/issues/56)) ([82e8309](https://github.com/kendrick/working-memory-kit/commit/82e8309ee016d0ee50a0cbb4b26807f9f5a61598))


### Documentation

* add a root AGENTS.md pointing at CLAUDE.md ([a647314](https://github.com/kendrick/working-memory-kit/commit/a64731498d14abf11ad633d13480e0851e254f11))
* **guide:** describe hydrate-propose's org-scope handoff to ltm propose ([#58](https://github.com/kendrick/working-memory-kit/issues/58)) ([#68](https://github.com/kendrick/working-memory-kit/issues/68)) ([8ccde42](https://github.com/kendrick/working-memory-kit/commit/8ccde42805b21b327684017a9f20f7f7dda41cd0))
* **rc:** say a rejected WORKING_MEMORY_DIR stays in .working-memoryrc, and pin it ([#52](https://github.com/kendrick/working-memory-kit/issues/52)) ([#73](https://github.com/kendrick/working-memory-kit/issues/73)) ([7cc839b](https://github.com/kendrick/working-memory-kit/commit/7cc839b4ac704f8ae810fecfa9e20143593794ac))
* **readme:** correct the file count and surface the test suite ([3aa9787](https://github.com/kendrick/working-memory-kit/commit/3aa978754601265a0891881a700ffcb5a87a178f))


### Testing

* **evals:** add claude plugin eval cases for the on-demand table and the hydrate trigger ([#85](https://github.com/kendrick/working-memory-kit/issues/85)) ([f91be29](https://github.com/kendrick/working-memory-kit/commit/f91be2989408def8d02f93433402a30f52590404))
* **pester:** drive init.ps1's typed working-memory-dir prompt through a pty ([#51](https://github.com/kendrick/working-memory-kit/issues/51)) ([#76](https://github.com/kendrick/working-memory-kit/issues/76)) ([4cb1917](https://github.com/kendrick/working-memory-kit/commit/4cb191719a1fd403176d3187f06189e1bfccc5c8))


### CI & Build

* bump actions/checkout from 4 to 7 ([1504cfb](https://github.com/kendrick/working-memory-kit/commit/1504cfb807552bda5409d7fea49f270b7c425eee))
* bump actions/checkout from 4 to 7 ([61bba77](https://github.com/kendrick/working-memory-kit/commit/61bba771b9d70b9eac5e10fdc19a91e7345052c8))
* bump actions/upload-artifact from 4 to 7 ([#94](https://github.com/kendrick/working-memory-kit/issues/94)) ([b31eb9a](https://github.com/kendrick/working-memory-kit/commit/b31eb9af90e704e88feff0594d1b062739129be7))
* let dependabot watch the pinned action versions ([5a1c1e9](https://github.com/kendrick/working-memory-kit/commit/5a1c1e9784002d8e9c9a9c01f3ec105d446393c1))
* make Windows PowerShell 5.1 the supported floor and test it ([#69](https://github.com/kendrick/working-memory-kit/issues/69)) ([e732bd2](https://github.com/kendrick/working-memory-kit/commit/e732bd2364d5bf88f9f1a7f7c816a444ce02c231))
* **release:** cut releases with release-please so both plugin.json versions bump ([#92](https://github.com/kendrick/working-memory-kit/issues/92)) ([617baa9](https://github.com/kendrick/working-memory-kit/commit/617baa9d5df1c8927318b7e80bbc166d7e39f5e3))
* **test:** limit the workflow token to contents: read ([#95](https://github.com/kendrick/working-memory-kit/issues/95)) ([8aa9828](https://github.com/kendrick/working-memory-kit/commit/8aa982880881806b86ace21c21e4fd49535e01de))


### Chores

* **deps-dev:** bump the npm_and_yarn group across 1 directory with 2 updates ([a83ff61](https://github.com/kendrick/working-memory-kit/commit/a83ff6165d8b070c38535fedd9084252ecdef99b))
* **deps-dev:** bump the npm_and_yarn group across 1 directory with 2 updates ([6c3a37e](https://github.com/kendrick/working-memory-kit/commit/6c3a37e76e262160ea0829f5f37c7f16684849f8))
* stop tracking the maintainer's .claude/settings.json ([#45](https://github.com/kendrick/working-memory-kit/issues/45)) ([410a289](https://github.com/kendrick/working-memory-kit/commit/410a28992401173062680e0bd22dbdee52958937))

## 0.3.0 (2026-07-24)

### Features
- *(codex)* Add local working-memory integration

### Documentation
- Add Codex support to README
- Document local Codex workflows

### Testing
- *(codex)* Cover installed Codex machinery

## 0.2.0 (2026-07-08)

### Features
- *(installer)* Reconcile kit machinery on re-run without clobbering your edits

### Bug Fixes
- *(hydrator)* Repoint the pipeline link at the vendored skills (#26)

### Documentation
- *(changelog)* Correct the stale "not versioned yet" prose
- *(readme)* Document the upgrade and reconcile flow

### Testing
- *(installer)* Cover the upgrade flow on both bats and Pester
## 0.1.0 (2026-06-12)

### Features
- *(installer)* Register external spec tooling via flags and .working-memoryrc (#14)
- *(installer)* Detect spec-driven neighbors and wire the coexistence boundary (#13)
- *(installer)* Fence the working-memory section so re-installs stay collision-safe (#12)

### Bug Fixes
- *(installer)* Preserve line endings outside the working-memory fence (#22)
- *(installer)* Normalize line endings so Windows re-installs stay idempotent (#21)
- *(installer)* Repair PowerShell legacy migration and stack pre-fill (#19)
- *(installer)* Make init.ps1 path-portable and headless-drivable (#18)
- *(installer)* Make init.ps1 prompts non-interactive-safe and smoke it on Windows CI (#15)
- *(hooks)* Skip session-end nudge during an in-progress merge or rebase (#6)

### Documentation
- Refresh the roadmap and generate the changelog with git-cliff (#23)
- Retire scaffold-prompt.md in favor of the installer (#17)
- *(templates)* Surface the decisionLog format and sharpen the on-demand table (#8)

### Testing
- Add a Pester suite for the PowerShell installer and hooks (#20)
- Add a bats harness and CI for the installer and hooks (#11)

### CI & Build
- Run shellcheck on installer & hooks (#16)

## Initial development

The kit's foundation, before it adopted Conventional Commits. Summarized from git history rather than listed commit by commit.

- A two-tier working memory (`AGENTS.md` plus `_working-memory/`) installed by parallel bash and PowerShell scripts, with thin `CLAUDE.md` and `copilot-instructions.md` pointers.
- The hydration pipeline (the `hydrator` agent and five `hydrate-*` skills) ships into every install, so brownfield projects get the one-time onboarding surface, not just ongoing maintenance.
- Session hooks: a session-start directive so agents register the kit early, and a session-end nudge to refresh working memory after substantial work, with broken-pointer detection riding along.
- One canonical location per artifact that Claude Code and Copilot both read natively: `.claude/` for cross-tool agents and skills, `.github/` reserved for Copilot-only formats.
- Installers run under `curl | bash` and `iex (irm ...)`, reading prompts from the terminal rather than the piped script body.
