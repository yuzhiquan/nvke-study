# Draft: comment on dsx-ai-factory/nvke#2022

**Status: UNPOSTED.** Drafted 2026-11-11 against upstream `487f5110`.
**Before posting:** `gh auth status` must show `yuzhiquan`; re-read #2022 and #2072 (≈11 merges/day,
either may have moved); re-check that #2072 still adds no duplicate-endpoint check.

---

@xdu31 #2072 adds the second site, which is the case this issue was waiting for. Are you adding the
duplicate-endpoint check in `Decode` to #2072, or is it better as a follow-up?

If a follow-up, I can take it once #2072 merges: map each site's `Endpoint()` to its key, fail on a
duplicate naming both keys, and add a trailing-slash table case.

---

Notes (not for posting): short on purpose (see memory `keep-pr-comments-short`). One ask, tag the
person who can answer. `jedimt` already triaged and gave the recipe, so no design rationale.
