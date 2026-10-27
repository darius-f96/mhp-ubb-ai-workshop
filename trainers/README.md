# For the teaching team

Everything in this directory is **trainer-to-trainer**, not student-facing. Students cloning the repo can ignore it entirely; nothing here is referenced from the playbooks, exercises or slides.

The rest of the repository — `docs/`, `exercises/`, `slides/`, `configs/`, `scripts/` — is written in one voice: **us (the teaching team) talking to students.** Keep it that way. If you are tempted to add session timings, "say this out loud" cues, or a teach/skip list to a student page, it belongs here instead.

## What is in here

| File | Purpose |
|------|---------|
| [runbook.md](runbook.md) | Minute-by-minute plan for the 45-minute hands-on block, the pre-day checklist, failure modes ranked by how much session time each consumes, and the teaching beats worth protecting |

## Keeping the two in sync

When a student-facing page changes in a way that affects delivery — a new failure mode, a step that overruns, a demo that stops working — update `runbook.md` in the same commit. The runbook's value is that it encodes what actually happened in a room, so it rots faster than the playbooks and needs tending after every session.

See the *Afterwards* checklist at the end of [runbook.md](runbook.md) for the post-session pass.
