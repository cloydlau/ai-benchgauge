# macOS status-bar presentation latency

The popover repeatedly derived a preferred width by traversing every category,
ranking company rows and measuring text. Both SwiftUI body evaluation and every
published state change repeated that work. Height measurement also created new
native header/footer hosts, including when a burst of quota updates had already
made an earlier queued measurement obsolete. Source refreshes additionally
encoded and atomically saved the complete snapshot on the main thread.

Panel measurements now reuse one bounded width entry per snapshot revision and
language, plus one height entry for the actual geometry inputs. Quota wrapping,
filtering, grouping, language, source visibility, width and minute-boundary
changes invalidate the relevant measurements. Snapshot revisions avoid comparing
the whole metadata graph on every cache lookup. Same-turn presentation updates
coalesce into one task. Menu refresh work is enqueued after the native reveal.

Snapshot persistence uses one background serial writer and the existing atomic
cache format. A write in progress retains only the latest pending snapshot.
An older write cannot overwrite a newer completed write. This is a rebuildable
cache: a process terminated before background persistence completes may restart
with the previous complete snapshot, which will be refreshed normally.

## Local measurements, 2026-10-25

The debug `--popover-performance` harness uses the production AppKit controller
and a frozen public leaderboard cache: 30,049,839 bytes, 12 boards, 1,242 entries.
Eight synthetic quota cards replace account data. It starts no account clients,
timers or network refreshes. Both runs use the same frozen input and host.

| Probe | Before | After |
| --- | ---: | ---: |
| First presentation to visible, without prewarming | 5,653 ms | 729 ms |
| Subsequent presentation, two samples | 240 / 232 ms | 114 / 107 ms |
| Repeated size calculation, three samples | 105 / 105 / 104 ms | 0.031 / 0.010 / 0.008 ms |
| Main queue after twelve synchronous quota updates | 5,269 ms | 122 ms |
| Cache enqueue on main thread | synchronous encoding/write, 427 ms | 0.008 ms |

The background write still takes about 442 ms; it no longer blocks presentation.
Initial snapshot decoding remains about 1.5 seconds and is outside the measured
open path. The first-presentation samples are single cold native-host runs, not
a broad latency distribution or physical click-to-photon measurement.

Ignored `work/status-popover-performance/` retains the measurements, input/source
hashes, build/test logs and before/after native originals. Both native popovers
are 1920×823 pixels on macOS 27.0.1 (26A434), actual 1× backing scale, Chinese/light.
The separate 1100-point sizing probe remains exactly 1100×823 before and after.
Reviewed originals retain the same columns, controls, complete quota row and
alignment. Pixel differences are retained in `frame-comparison.json`; animated
timestamp/row rendering was not frozen for the performance capture.

Regression tests check measurement invalidation, unchanged-input reuse,
off-main-thread writing, burst coalescing and final atomic-format round trips.
The stable-input full `./test.sh --coverage` run passed with no skipped checks;
the script and shared Swift coverage gates remain at 100%. The local Release
bundle passed strict deep code-signature verification and was rebuilt/restarted.
No Windows performance/native capture, other locale/theme native capture,
source-matched CI visual artifact or protected release approval is claimed.
