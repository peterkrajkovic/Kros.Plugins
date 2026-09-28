# Catalog distribution — analysis

Why the design in [catalog-distribution.md](catalog-distribution.md) looks the way it does: how the
thing is meant to work, in what order it arrives, and which alternatives were rejected and on what
grounds.

The design document says *what to build*. This one says *why*, and is the document to reread before
overturning any of it.

## How it should work

**Code ships with the plugin. Content does not.** The plugin version changes when hook logic changes,
which is rare. Tips reach people without anyone running a command.

From the developer's side, one session looks like this. At session start the hook reads three things
off the local disk — what is installed on the machine, what the current repository carries in
`.dev-tips/`, and the cached remote catalog — merges them, and delivers at most one tip. Nothing waits
on the network. During the session, the command ledger and skill usage are recorded as they are
today. At the end of a turn, if the cached catalog is older than its TTL, a detached process refreshes
it for the next session and the current turn is unaffected.

From the author's side it looks like this. Someone adds a skill or a command to `Kros.AiDevTools` and
writes a `tip.json` beside it in the same pull request; CI validates it against the tools that
actually exist, and the pull request merges. There is nothing to publish — that file is what the
machines read. Within a day it is on every machine. If the tip turns out to be wrong, the next
commit corrects it, or `enabled: false` silences everything until it is sorted out.

Which of the three sources a tip comes from is decided by one question: **does the developer already
have the thing the tip is about?**

- If they have it, nothing needs to be published at all. The skill is on their disk, its description
  says what it is for, and `usage.json` says whether they have ever invoked it. That yields *you have
  this and have never used it*, which is the strongest form of the tip and needs no catalog entry.
- If it belongs to the repository they are working in, it travels with that repository and arrives
  with `git pull`.
- Only a tool they do **not** have cannot be discovered, and only that case needs a published
  catalog.

## Why publishing has to change

Tip content is packaged inside the plugin, so publishing one tip means a version bump, a marketplace
update, a plugin update and a restart — and three of those four steps belong to the developer, not to
us. Somebody who never runs them reads a stale catalog indefinitely and neither side is told.

The same coupling makes the plugin un-silenceable: a tip that turns out to be wrong keeps being shown
until every person individually updates. For a plugin whose entire job is to announce things that
have just appeared, both of these are backwards.

## The order it should arrive in

| Stage | Work | What it unblocks | Depends on |
|---|---|---|---|
| 0 | Sane cooldowns in `catalog/config.json` | the plugin being tolerable at all | nothing |
| 1 | Channel A — local discovery | most tips stop needing a catalog entry | nothing |
| 2 | Channel B — `.dev-tips/` in product repositories | ADRs and conventions per repository | nothing |
| 3 | Channel C — background fetch of the source, validation in CI | tips about tools the developer lacks | CI access to `Kros.AiDevTools` |
| 4 | Hand-editing of `catalog/tips.json` stops | one source of truth | stages 1–3 |

The order is value per unit of risk. Channel A needs no CI, no network and no second repository, and
covers the largest share of what would otherwise have to be written by hand. Channel C is last
because it is the only part that requires changing a repository this plugin does not own.

Measurement — whether any of this changes behaviour — stays out of scope. Nothing leaves the machine.

## Decision register

Each row: what was chosen, what it was chosen over, and what would justify revisiting it.

### D1 — Tip content lives next to the tool it describes

**Chosen:** a `tip.json` beside the skill or command, in the tool's own repository.

**Over:**
- *A central hand-maintained catalog.* The person who renames a command is not the person who
  remembers the tip, so the catalog drifts and nobody notices — the only people who read a tip are
  those who do not know the tool and cannot tell that it is wrong.
- *`CLAUDE.md` or memory.* Both apply on every turn, cost context permanently, cannot be rate-limited,
  cannot be shown a fixed number of times and cannot be suppressed for someone who already uses the
  tool. A tip is a transient notice, not a standing instruction.

**Revisit if:** the catalog stops growing and tools stop being renamed, at which point central
curation is less machinery for the same result.

### D2 — Three channels rather than one

**Chosen:** split by whether the developer already has the thing.

**Over:** *one remote catalog for everything.* Simpler to explain, but it requires an entry per tool
before anything can be said about it, and it cannot express the strongest tip available — that this
person has a tool and has never invoked it. The split also means most tips need no publishing
pipeline at all.

**Cost accepted:** three code paths and a merge step instead of one read.

### D3 — Discovery uses the `description` from `SKILL.md`

**Chosen:** generate tip copy from frontmatter when no `tip.json` exists.

**Over:** *requiring `tip.json` for everything.* Better copy, but a new skill then produces no tip
until someone writes one, which is exactly the lag this design exists to remove.

**Known weakness:** `description` is written to tell a model when a skill applies, not to persuade a
human to try it. Some will read badly. The mitigation is that `tip.json` overrides it, so bad copy is
fixable without changing the mechanism.

**Revisit if:** in practice most generated copy needs overriding anyway.

### D4 — Remote transport is `git`

**Chosen:** shallow fetch from a bare repository under the plugin's data directory.

**Over:**
- *Raw HTTP with a token.* `Kros.AiDevTools` is private, so this means shipping a credential inside a
  plugin installed on every developer's machine. Rejected outright.
- *A UNC file share.* Simplest on the corporate LAN and needs no credentials, but fails from home and
  over VPN, and carries no history. Held as a fallback if `git` proves awkward.
- *An internal HTTP service.* Hosting, deployment and monitoring for one JSON file.

**Why it works:** `git` reuses Git Credential Manager, which the developer must already have
configured — otherwise `plugin marketplace add` would not have worked for them either. Authentication
costs nothing.

### D5 — Nothing is published; the client reads the source

**Chosen:** no generated catalog at all. The refresh fetches `master` shallow and reads the authored
`tip.json` files out of the tree, deriving the rest itself.

**Over:**
- *An orphan branch holding a generated `tips.json`.* It works, but it is a build artifact to keep in
  step with its source, produced by a bot, carrying content the client can read from that source just
  as cheaply. Every problem it brought — the retrigger loop, branch protection, an artifact that can
  go stale — is a problem of having an artifact at all.
- *A generated file committed to `master`.* Either a bot pushes it, with the same loop and protection
  problems, or every contributor regenerates it by hand — friction placed exactly on the people
  writing tips voluntarily.
- *A GitHub release asset.* Needs an API token against a private repository, which is D4's rejected
  option again.
- *A separate repository.* One more repository to create, permission and keep in sync, for one file.

**Cost accepted:** deriving `id`, `ref` and `install` moves into the client, so changing those rules
needs a plugin release. They change far less often than content does, which was the entire criterion.

**Revisit if:** derivation grows past what is reasonable to do inside a hook, or the repository grows
large enough that a shallow fetch of its tree stops being cheap.

### D6 — The refresh runs from `Stop`, detached, on a TTL

**Chosen:** `Stop` checks the cache age and, when stale, spawns a detached process and exits.

**Over:**
- *Fetching in `SessionStart`.* Puts the network on the path to the first prompt. Refused: a second of
  startup latency will get the plugin uninstalled faster than any bad tip.
- *`SessionStart`, detached.* Would also cover sessions where no turn completes, at the cost of a
  process spawn at every session start. Marginal either way; `Stop` wins because bookkeeping already
  runs there.
- *An OS scheduled task.* The most reliable option and the most intrusive: a plugin that installs a
  Windows scheduled task is hard to uninstall and hard to justify.

### D7 — Tips are delivered at session start only

**Chosen:** accept that a newly fetched catalog is used by the *next* session.

**Over:** *mid-session delivery via `UserPromptSubmit`*, for which the machinery already exists in
`Show-Candidate.ps1`. Rejected because a scheduled tip interrupting work is more intrusive than one at
startup — a retrospective notice earns that interruption by reacting to what the developer just did,
a scheduled tip does not. Content on a 24-hour TTL gains nothing from arriving ninety seconds sooner.

### D8 — Policy travels in the fetched file, and is trusted

**Chosen:** `ttlHours`, `cooldownDays` and `enabled` live in the catalog; the plugin's values only
bootstrap the first fetch. What the catalog says is what the hook does.

**Over:**
- *Policy in the plugin.* Every change to the cadence would need a release, and — the decisive point —
  there would be no way to silence a bad tip for everyone without asking each person to update.
- *Clamping fetched values to bounds in the hook.* Rejected. A bound is a guess at which value is
  wrong, made before anyone has seen the plugin misbehave in the field. The answer to a bad push is a
  corrected push, or `enabled: false` until it is corrected — both of which reach everyone within one
  TTL, which is faster than shipping a new client with different bounds. If real use shows the cadence
  needs a floor, that is the moment to learn what the floor is.

**Accepted consequence:** a bad push misconfigures every machine at once, until the next one fixes it.

### D9 — `published` is dropped in favour of a local `firstSeen`

**Chosen:** the hook records in `shown.json` when it first saw each `id`. There is no `published`
field at all.

**Over:**
- *Deriving it from git history.* A shallow fetch carries none, and keeping history around to date a
  tip is a large cost for a small field.
- *A hand-written date.* It drifts, it is forgotten, and nobody reviewing a pull request checks it.

**Why local is better and not merely cheaper:** the field exists to say how new an item is, and
newness is relative to the reader. To somebody who joined last week, a two-year-old skill they have
never heard of is new. `expires` stays an authored field — content going stale is a property of the
content, not of the reader.

### D10 — Repository-local tips never enter the central catalog

**Chosen:** read `.dev-tips/` live from the working directory.

**Over:** *collecting them into the catalog by CI.* That needs a cross-repo token and a second
publishing path for content that is already sitting on the disk, free to read, and correct per
worktree.

### D11 — Usage is read out of the transcripts, not only recorded forward

**Chosen:** the background refresh scans `~/.claude/projects/**/*.jsonl` for `Skill` invocations and
backfills `usage.json`, so a tool somebody already uses is never advertised to them.

**Over:**
- *Recording only from installation onwards*, which is what happens today. It makes a fresh install
  maximally irritating: the developer is pitched the commands they have been using for months. That
  is the single experience most likely to get the plugin switched off, and it lands on everyone
  exactly once — on day one.
- *Asking the developer what they already know.* A questionnaire at first run is friction in the worst
  possible place, and people under-report anyway.

**Limits, all accepted:** transcripts are retained for a bounded window, so *never used* really means
*not used lately* — which for this purpose is the better question to be answering. Skills invoked by
a subagent count as use. It is per machine, like every other signal here.

## Risks

| Risk | Severity | Response |
|---|---|---|
| A bad push to `dev-tips/config.json` misconfigures everyone | high | a corrected push, or `enabled: false`, within one TTL — deliberately not guarded client-side (D8) |
| Nobody writes `tip.json`, so the pipeline yields nothing | medium | channel A produces tips without any authoring |
| Generated copy reads poorly | medium | `tip.json` overrides per tip |
| Retrospective notices fire on false positives | medium | wording stays *next time you can*, never *you should have* |
| Desktop users get tips via the model, which may reword them | low | documented in `desktop-systemmessage-not-rendered.md`; upstream issue filed |
| The detached fetch hangs on a credential prompt | low | prompting disabled, hard timeout, lock with a stale timeout |

## Open questions

1. **Who can add a validation workflow to `Kros.AiDevTools`?** Stage 3 needs no branch and no bot any
   more, but it still needs somebody able to add CI there. Ownership is not established.
2. **Where is `655507-dev-tips-plugin.md`?** The README cites it as the design of record; it is not in
   any repository on this machine. Either link it or drop the reference.
3. **Is disabling GCM prompting sufficient in practice?** The failure mode — a hidden process hanging
   forever — is severe enough to deserve a deliberate test with a cleared credential, not an
   assumption.
4. **How would we ever know this works?** No measurement exists and none is planned. Accepted, but it
   means every decision here is argued from reasoning rather than evidence, and the way to correct
   them is to put the thing in front of people and watch what they switch off.
