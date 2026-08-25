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
