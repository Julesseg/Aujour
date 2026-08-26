# 0006 — The identity's ink and accents are held to a contrast floor, above what the design files specify

The visual identity in `docs/design/identity/Aujour.dc.html` is a paper-and-ink
one, and its softness is the point: `--ink-3` is specified at `.38` alpha in
light and `.34` in dark, and the accent set includes several deliberately
faded earth tones. Composited, that lands `--ink-3` at **2.28:1** in light and
**2.83:1** in dark against `--bg`, and puts Terracotta at **3.57:1** and Ochre
at **3.70:1** as text on `--sheet`. Aujour ships them raised — `--ink-3` at
roughly `.52` light and `.46` dark, with Terracotta and Ochre darkened — so
that anything which is a sentence clears 4.5:1 and anything which is a marker
or a chevron clears 3:1.

The trade is real and we are on the losing side of it aesthetically: the
design file is prettier than the app will be. It went the other way because
`--ink-3` is not decorative in this design. It carries "Writing opens at your
rollover hour.", "Nothing is saved until you write.", every settings row's
value, the `##` and `- [ ]` markers, and the unanswered `{{name}}` tokens —
prose and controls, not ornament. A journal is used in bed, at night, by
people who have had a long day, which is the worst case for a low-contrast
serif on cream.

## Consequences

The app will not match the design files pixel-for-pixel on these tokens, and
the mismatch is intentional. Anyone diffing the two should not "correct" the
app back to the file's values. If the identity is ever re-cut, the floor is
the constraint the new palette must satisfy — not a rounding error to be
tuned away.

The design files' own token board is separately wrong about its light values
and should not be used as a reference: it advertises `--ink-2` as `#8B857F`
where the CSS composites to `#746F6A`, and `--ink-3` as `#B5AFA9` where it
composites to `#A6A29D`.

## What the raised values measured, once there was a palette to measure

Building the token layer put numbers on the alphas above, and two of them did
not land where this ADR expected. The floor is unchanged — it is the decision,
and it is what the tests assert. What changed is which token is licensed for
which job.

`--ink-3` at `.52` light and `.46` dark measures **3.31:1** and **3.93:1** on
the worst ground it can be drawn on. That is the marker floor and not the
sentence one, so the raise did what it could and stopped short of what the
paragraph above claimed for it. Held to 4.5:1 instead it would need roughly
`.63` light, which is `--ink-2` — the identity would have three inks and two
steps. So `--ink-3` stays where it is and carries markers, chevrons and the
small capitals over a section, and **a sentence takes `--ink-2`**, however
quiet the design file draws it. The sentences named above move with it.

`--ink-2` at the identity's `.62` measures **4.45:1** in light, which misses
the floor by a rounding error nobody would have caught by eye. It ships at
`.64`.

The floor also applies on every ground and not only on `--bg`: `--card` in
dark is the lightest surface in the app, and an accent-tinted pill is a ground
of its own. Reading it that way costs four of the nine accents another ~3% of
their light value, and adds a second accent shade — `--accent-ink`, which the
design file already names — for accent-coloured words on an accent-coloured
wash, where the accent on its own wash lands between 3.6:1 and 4.4:1.

`App/AujourTests/IdentityTests.swift` is where all of this is enforced. The
numbers here are a record of why; that file is what fails if a value drifts.
