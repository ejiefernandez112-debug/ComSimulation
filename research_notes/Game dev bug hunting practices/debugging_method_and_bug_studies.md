# Debugging methodology and empirical studies of game bugs

Research date: 2 October 2026. Audience: a solo, non-programmer developer building a single-player Godot 4 (GDScript) tycoon/business sim with Claude Code. Source quality is flagged inline: [PEER] = peer-reviewed, [PREPRINT] = arXiv not confirmed peer-reviewed, [BOOK], [OFFICIAL DOCS], [PRACTITIONER] = developer blog/talk, [VENDOR] = commercial blog or vendor-funded study (lower quality).

---

## 1. What is the established step-by-step debugging method?

### Takeaway
The two standard references agree on one loop: **reproduce the failure reliably -> observe it directly (don't guess) -> narrow it down by halving -> change one thing at a time while keeping a written log -> fix the cause, not the symptom -> prove the fix by making it fail before and pass after.** Agans (2002) gives this as nine practical rules; Zeller (2005/2009) formalises it as the scientific method (hypothesis -> prediction -> experiment) plus the 7-step "TRAFFIC" workflow and automated narrowing (delta debugging).

### Cited Findings

**David Agans, *Debugging: The 9 Indispensable Rules* (book, 2002) [BOOK]**
- The nine rules: Understand the System; Make It Fail; Quit Thinking and Look; Divide and Conquer; Change One Thing at a Time; Keep an Audit Trail; Check the Plug; Get a Fresh View; If You Didn't Fix It, It Ain't Fixed. The book is about general fundamentals, not any one technology, and is aimed at novice to moderately experienced developers — [Embedded Artistry summary (2017)](https://embeddedartistry.com/blog/2017/9/6/debugging-9-indispensable-rules); [Goodreads listing](https://www.goodreads.com/book/show/237362109-debugging); [U. Washington CSE466 lecture slides (2015)](https://courses.cs.washington.edu/courses/cse466/15au/pdfs/lectures/DebuggingRules.pdf)
- Practical sub-advice per rule (as summarised by Embedded Artistry, 2017) — [Embedded Artistry](https://embeddedartistry.com/blog/2017/9/6/debugging-9-indispensable-rules):
  - *Understand the system*: read the documentation; know how it is designed and its limits.
  - *Make it fail*: reproduce reliably; pin down the exact triggering conditions; for intermittent bugs, use automation/amplification and control variables to find which condition matters.
  - *Quit thinking and look*: observe the actual failure with instrumentation (logs, debuggers) — "Keep looking until the failure you can see has a limited number of possible causes"; guess only to focus the search, never to justify a fix.
  - *Divide and conquer*: binary search — split the search space into working and broken halves and keep narrowing.
  - *Change one thing at a time*: one variable per test; back out changes that didn't help.
  - *Keep an audit trail*: write down what you did, in what order, and what happened; save and annotate logs.
  - *Check the plug*: verify basic assumptions — the right version/code is actually running, startup/config/default settings are what you think.
  - *Get a fresh view*: explain it to someone else; **report symptoms, not theories**, so you don't bias the helper.
  - *If you didn't fix it, it ain't fixed*: show broken -> fixed -> broken -> fixed by toggling the fix, under the same conditions that exposed the bug; intermittent bugs can come back without proper confirmation.

**Andreas Zeller, *Why Programs Fail: A Guide to Systematic Debugging* (book, 1st ed. 2005, 2nd ed. 2009; free online successor *The Debugging Book*) [BOOK]**
- Zeller frames debugging as the scientific method: formulate a question, invent a hypothesis, predict consequences, test the prediction by experiment, refine or reject; repeat until the hypothesis explains all observations — "we are treating bugs as if they were natural phenomena" — [The Debugging Book, "Introduction to Debugging" (Zeller, online)](https://www.debuggingbook.org/html/Intro_Debugging.html)
- He insists on a written **debugging logbook** ("Keep a Log") of hypotheses, test inputs, expected vs actual output, so work can be interrupted without losing context — [The Debugging Book](https://www.debuggingbook.org/html/Intro_Debugging.html); also [Elsevier book page](https://shop.elsevier.com/books/why-programs-fail/zeller/978-0-08-092300-0)
- **Fix the cause, not the symptom**: a proper diagnosis must show *causality* (how the defect causes the failure) and *incorrectness* (that the code really is wrong); after fixing, rerun previous tests and add new ones to prevent recurrence — [The Debugging Book](https://www.debuggingbook.org/html/Intro_Debugging.html)
- Vocabulary: mistake (human) -> defect (in code) -> infection/fault (bad program state) -> failure (visible). Not every defect causes an infection and not every infection causes a visible failure — [The Debugging Book](https://www.debuggingbook.org/html/Intro_Debugging.html); [Zeller, "How Failures Come to Be" (book chapter PDF)](https://www.st.cs.uni-saarland.de/whyprogramsfail/pdf/HowFailuresComeToBe.pdf)
- **TRAFFIC** workflow (7 steps): **T**rack the problem (file a report so it isn't lost), **R**eproduce, **A**utomate and simplify the test case, **F**ind possible infection origins, **F**ocus on the most likely origins, **I**solate the infection chain, **C**orrect the defect — [Saarland University "Systematic Debugging" lecture slides (2017)](https://www.st.cs.uni-saarland.de/edu/se/2017/files/slides/16-Systematic%20Debugging.pdf); [Symflower blog (2023) [VENDOR]](https://symflower.com/en/company/blog/2023/debugging-with-the-traffic-principle/)
- **Delta debugging** (Zeller, 1999): automatically narrows failure-inducing circumstances to a minimal set using a hypothesis-trial-result loop; applied to failure-inducing *inputs* (e.g. an HTML page that crashes a browser), *user interactions* (the keystrokes that make a program crash), and *code changes* (after a failing regression test) — [Wikipedia: Delta debugging](https://en.wikipedia.org/wiki/Delta_debugging); [Saarland delta-debugging page](https://www.st.cs.uni-saarland.de/dd?lang=en)

**Game-specific variants (talks/practitioners)**
- Mark Wesley (2K Marin), GDC 2013, "Implementing a Rewindable Instant Replay System for Temporal Debugging": argues traditional debugging is "far too low-level and cumbersome for most high-level code" and classic debuggers "lack any history and are unable to rewind time"; advocates an in-game rewindable replay as superior to deterministic replay for debugging and tuning; says a basic system can be built "in just a few days" — [GDC Vault (2013)](https://gdcvault.com/play/1017769/Implementing-a-Rewindable-Instant-Replay) [PRACTITIONER]
- Casey Muratori, Handmade Hero Day 23 (2014), "Looped Live Code Editing": records a snapshot of the whole game state plus every frame's input, then loops playback while code is hot-reloaded, treating the snapshot like "a save state in an emulator" — [Handmade Hero episode guide, Day 023](https://guide.handmadehero.org/code/day023/); implementation discussion in [Handmade Network forum](https://hero.handmade.network/forums/code-discussion/t/1428/p/8021) [PRACTITIONER]
- Bruce Dawson (Valve; formerly Humongous Entertainment, Xbox, Chrome) writes on crash investigation and argues for "crashing vigorously" and capturing crash dumps so failures are recorded instead of hidden — [Game Developer: "When Even Crashing Doesn't Work"](https://gamedeveloper.com/programming/in-depth-when-even-crashing-doesn-t-work); [Game Developer: "More Adventures in Failing to Crash Properly"](https://gamedeveloper.com/programming/in-depth-more-adventures-in-failing-to-crash-properly); [author page](https://www.gamedeveloper.com/author/bruce-dawson) [PRACTITIONER]

### Inferences
- A practical combined checklist for this project: (1) write the bug down (TRAFFIC "Track"; Agans "audit trail"); (2) make it fail on demand — ideally as a headless test; (3) shrink the reproduction to the fewest steps/smallest save; (4) look at actual values (logs, asserts, debugger) before theorising; (5) halve the search space (which system? which commit? which tick?); (6) one change at a time, logged; (7) fix the cause and show it fails-before / passes-after; (8) look for the same pattern elsewhere; (9) note the lesson.
- "Check the plug" maps to very common Godot/AI-assistant pitfalls: running an old export, a stale `.godot` import cache, editing a file the scene doesn't actually load, or the wrong save file being read.
- "Report symptoms, not theories" is directly useful for how the human should describe bugs to Claude: what was done, what was expected, what happened, with exact numbers/screens — not "I think the timer is broken".

### Gaps
- I did not access the full text of either book; rule details come from secondary summaries (Embedded Artistry, university slides) and Zeller's own online book. Exact publication years: Agans 2002 (AMACOM), Zeller 2005/2009 (Morgan Kaufmann/Elsevier) — from general knowledge, not verified on the publisher page in this session.
- No GDC talk specifically titled "Debugging Techniques" was located; no verified source found for Jonathan Blow's views on debugging methodology.

---

## 2. Game-specific diagnosis techniques and the evidence for them

### Takeaway
Games lean on techniques that capture or recreate *state over time*: deterministic input recording/replay, per-tick checksums to find the exact frame things diverge, save-state reproduction, rewindable replay, in-game debug overlays and consoles, assertions/logging, and `git bisect` to find the breaking commit. Evidence for these is mostly practitioner reports (GDC talks, dev blogs), not controlled studies — but the practitioner evidence is consistent: once you can replay the exact state, the fix is usually the easy part.

### Cited Findings

**Deterministic replay / checksums**
- Factorio (Wube Software), Friday Facts #47 (c. 2014): to debug multiplayer desyncs the game runs in a special mode that "makes a CRC from the whole map every tick" and saves the map with human-readable tags each tick (dropping play to a few FPS); the session is then replayed with the same CRC checks and the first differing tick throws a desync exception; comparing the two tagged saves from that tick, "the difference is usually very small - typically just a value of one variable"; fixing is "often the easiest part" — [Factorio FFF #47](https://www.factorio.com/blog/post/fff-47) [PRACTITIONER]
- Overwatch (Blizzard), GDC 2017, Philip Orwig, "Replay Technology in Overwatch: Kill Cam, Gameplay, and Highlights": the session description states replays "prove invaluable in reproducing bugs"; covers building the replay system alongside the network model — [GDC Vault](https://gdcvault.com/play/1024053/Replay-Technology-in-Overwatch-Kill) [PRACTITIONER]
- Handmade Hero Day 23 (2014): full-state snapshot + per-frame input recording and looped playback (see §1) — [Handmade Hero guide](https://guide.handmadehero.org/code/day023/) [PRACTITIONER]
- Rewindable replay (Wesley, GDC 2013) is argued to be better than deterministic replay for debugging/tuning because you can scrub back through recorded state rather than re-simulate — [GDC Vault](https://gdcvault.com/play/1017769/Implementing-a-Rewindable-Instant-Replay) [PRACTITIONER]

**Engine debugging tools (Godot 4)**
- Godot's built-in tools: Debugger panel and Output panel; breakpoints (click the script gutter; they persist across restarts); Break/Continue/Step Over/Step Into; **Remote scene tree** — "While using Remote you can inspect or change the nodes' parameters in the running project"; profilers and monitors; visual debug toggles (visible collision shapes, navigation, paths, avoidance, canvas redraw flashes); live sync of scene/script edits into a running game; running multiple instances — [Godot docs: Overview of debugging tools](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/overview_of_debugging_tools.html) [OFFICIAL DOCS]
- GDScript `assert()`: "the code inside assert() is only executed in debug builds or when running the project from the editor"; on failure "an error is generated and the current method returns a default value", and in the editor it also breaks into the debugger; docs warn "Don't include code that has side effects in an assert() call" because release builds will behave differently. Companion helpers: `print_debug()` (adds the stack frame), `print_stack()`, `get_stack()` (stack traces only in editor/debug builds unless `debug/settings/gdscript/always_track_call_stacks` is enabled) — [Godot docs: @GDScript](https://docs.godotengine.org/en/stable/classes/class_@gdscript.html) [OFFICIAL DOCS]

**Bisecting (finding the commit that broke it)**
- Godot's "Bisecting regressions" guide: bisecting is "a manual binary search to determine when a regression appeared", also usable for performance regressions; first narrow the range using official release builds, then `git bisect start` / `git bisect good <commit>` / `git bisect bad <commit>`, build and test each commit Git checks out, and mark it good or bad; "5 to 10 steps are usually sufficient to find most regressions"; advises making a backup of the project first — [Godot docs 4.4: Bisecting regressions](https://docs.godotengine.org/en/4.4/contributing/workflow/bisecting_regressions.html) [OFFICIAL DOCS]. (Note: this guide is written for bugs in the *engine*; compiling Godot can take up to an hour per build on slow hardware.)
- `git bisect run <script>` automates it: the script's exit code marks each commit — 0 = good, 1–127 except 125 = bad, 125 = cannot test/skip — [Git documentation: git-bisect](https://git-scm.com/docs/git-bisect) [OFFICIAL DOCS]

**Root-cause analysis ("5 Whys")**
- Originated with Sakichi Toyoda and was formalised by Taiichi Ohno in the Toyota Production System: ask "why" repeatedly until reaching a systemic cause. Criticised (including by a former Toyota managing director, Teruyuki Minoura) as too basic/arbitrarily shallow, and weak when several causes interact — [Wikipedia: Five whys](https://en.wikipedia.org/wiki/Five_whys) [secondary/encyclopedic]

**How hard reproduction is (general software, not games)**
- Joorabchi, Mirzaaghaei & Mesbah, MSR 2014, "Works For Me! Characterizing Non-reproducible Bug Reports": across one industrial and five open-source bug trackers (32K non-reproducible reports), non-reproducible reports were on average **17% of all bug reports**, stayed open about **three months longer**, were mostly (45%) caused by "inter-bug dependencies", and **66% of those eventually marked Fixed were in fact reproduced and fixed** — [paper PDF (UBC)](https://people.ece.ubc.ca/amesbah/resources/papers/mona-msr14.pdf) [PEER]
- In the game-specific survey by Truelove et al. (2021), 7 of 22 developer answers cited bug reproduction as a main obstacle — one said "Reproducing a bug often requires a large time investment to reach the state in which it is apparent" — [Truelove et al., ar5iv](https://ar5iv.labs.arxiv.org/html/2103.03997) [PEER]

### Inferences
- This project is unusually well set up for replay-style debugging *without* building a frame-by-frame recorder: the rules already require timestamp-based state (`started_at`/`finishes_at`), one clock (`TimeService.now()`), versioned JSON saves, and simulation separated from visuals. A bug can therefore be reproduced from **(a save file + a fixed clock value + a short list of player actions)** run headless. That is the save-state equivalent of Handmade Hero's "emulator save state" and Factorio's tagged saves.
- A **time-warp tool** (offsetting what `TimeService.now()` returns, in `scenes/debug/`) is the cheapest high-value debug tool for an idle/offline-production game: it reproduces offline catch-up, long timers and "clock set backwards" cases on demand.
- An **invariant/checksum check** (e.g. "money never negative", "warehouse stock never above capacity", "total goods conserved across a sell") run after each simulated step is the single-player analogue of Factorio's per-tick CRC: it pinpoints the first step where state goes wrong.
- For GDScript projects, `git bisect` needs no compile step, so `git bisect run` with the existing headless test command (exit code 0 = pass) can find the breaking commit fully automatically — something Claude Code can run alone.
- What the AI assistant can do alone: write failing headless tests, add asserts/invariant checks and logging, build debug overlays/time-warp/cheat menus behind `OS.is_debug_build()`, run `git bisect run`, read Godot's output/error logs, search the code for the same bug pattern. What needs the human: noticing the bug during play, judging visual/feel/"is this fun/fair" bugs, providing the save file and the exact steps, and confirming the fix in the real running game.

### Gaps
- No controlled study was found measuring how much deterministic replay or debug overlays speed up game debugging; evidence is practitioner testimony.
- Halo's replay/"Theater" system as a debugging tool was not researched in this session (no source fetched).
- Note: Undo's vendor-commissioned 2013 study claimed reversible debuggers cut debugging time 26% — see §5 for why this is weak evidence.

---

## 3. Fix verification and prevention

### Takeaway
The consistent advice is: before fixing, capture the bug as an automated failing test; fix the cause; prove the test now passes and the old tests still pass; then hunt for the same pattern elsewhere, because game studies show crash-type bugs especially tend to come back. Postmortem write-ups are standard in game development, but research shows the industry often fails to learn from them.

### Cited Findings
- Agans' Rule 9 — verify by toggling: make it fail, apply the fix, confirm it works, remove the fix and see it fail again, under the same conditions that exposed the bug — [Embedded Artistry summary](https://embeddedartistry.com/blog/2017/9/6/debugging-9-indispensable-rules) [BOOK summary]
- Zeller: TRAFFIC's "Automate" step turns the failure into an automatic, simplified test case; after the fix, rerun previously passing tests and add new tests to prevent recurrence — [Saarland slides (2017)](https://www.st.cs.uni-saarland.de/edu/se/2017/files/slides/16-Systematic%20Debugging.pdf); [The Debugging Book](https://www.debuggingbook.org/html/Intro_Debugging.html) [BOOK]
- Truelove et al. (ICSE 2021): **Crash bugs had the highest recurrence (38%)** across updates, followed by Game Graphics and Triggered Event bugs. Developers' explanation for recurring crashes: fixes target "the single caller that passed bad data" instead of making sure all callers pass good data, and games are highly "interconnected", so crashes resurface — [Truelove et al., ar5iv](https://ar5iv.labs.arxiv.org/html/2103.03997) [PEER]
- Same study: developers most associated bug recurrence with **testing** (16 mentions), then game design (4) and code quality/coding (4); main challenges were inadequate testing ("too many possibilities of interaction/combination", 8 answers), reproduction difficulty (7) and code quality (6) — [Truelove et al., ar5iv](https://ar5iv.labs.arxiv.org/html/2103.03997) [PEER]
- Pascarella et al. (MSR 2018), 60 open-source projects (games vs non-games): the game projects studied had **no test cases**, game developers reported mainly testing by manual play and found unit testing harder, and games showed more "Failure"-type faults — consistent with weaker testing in games — [Pascarella et al., TU Delft repository PDF](https://repository.tudelft.nl/file/File_6fbd34ec-fed2-473f-a097-22a5be2e634c); [MSR 2018 listing](https://2018.msrconf.org/details/msr-2018-papers/39/How-Is-Video-Game-Development-Different-from-Software-Development-in-Open-Source-) [PEER]
- Washburn et al. (ICSE 2016) note that in games "testing and quality assurance are approached completely differently (e.g. live testers and few automated tests)" — [Washburn et al. PDF](https://thomas-zimmermann.com/publications/files/washburn-icse-2016.pdf) [PEER]
- Postmortems: Washburn et al. analysed 155 public game postmortems (Gamasutra, 16 years) and distilled best practices and pitfalls; Politowski et al. analysed 200 postmortems (1997–2019) — the existence of these corpora shows postmortems are an established game-industry practice — [Washburn et al.](https://thomas-zimmermann.com/publications/files/washburn-icse-2016.pdf); [Politowski et al., arXiv](https://arxiv.org/abs/2009.02440) [PEER/PREPRINT]
- 5 Whys can be used for the postmortem root-cause step but is criticised as shallow for multi-cause problems — [Wikipedia: Five whys](https://en.wikipedia.org/wiki/Five_whys)

### Inferences
- For this project the prevention loop is concrete: every confirmed sim bug -> a new test in `tests/test_simulation.gd` (or an invariant in `tests/test_invariants.gd`) that fails before the fix and passes after. This is exactly what the project's CLAUDE.md already asks for and is fully automatable by Claude Code.
- The Truelove crash-recurrence finding argues for "fix all callers" sweeps: after a fix, have the assistant grep for every other place the same function/value is used (e.g. every place that reads a recipe timer or a stock count) and either fix them or add a guard/assert at the shared entry point.
- A short per-bug note (symptom, reproduction, root cause, fix, test added, "where else could this happen?") is a lightweight postmortem suited to a solo developer; it also doubles as Agans' audit trail and Zeller's logbook.

### Gaps
- No peer-reviewed study was found that measures, specifically for games, how much "write a failing test first" reduces recurrence; the evidence is general-software practice plus the correlational game findings above.

---

## 4. What academic studies say about game bug types and root causes

### Takeaway
Across studies, the most *frequently fixed* game bugs are **wrong information shown to the player, graphics bugs, and action/interaction bugs**; the most *severe and most recurring* are **crashes**; games have roughly **three times** the share of graphics faults of ordinary software and their faults are spread across more categories; and **reproduction difficulty and combinatorial interaction** are the main reasons bugs persist. At the project level, postmortem studies find that most problems have human/process root causes (scope, schedule, planning) rather than technical ones.

### Cited Findings

**Lewis, Whitehead & Wardrip-Fruin (2010), "What went wrong: a taxonomy of video game bugs", FDG 2010 [PEER]**
- Built from online videos, articles and player communities; divides failures into **temporal** (things that go wrong over time/in sequence) and **non-temporal** (wrong at a single moment) categories, meant to guide designers and testers — [ACM DOI 10.1145/1822348.1822363](https://doi.org/10.1145/1822348.1822363); summary in [Butt et al. 2023](https://arxiv.org/html/2311.16645v1)
- The Lewis categories (as adopted by Truelove et al.) include Action, Artificial Intelligence, Bounds, Context State, Event Occurrence, Game Graphics, Implementation Response, Information, Interrupted Event, Position of Object, and Value — [Truelove et al., ar5iv, Table of categories](https://ar5iv.labs.arxiv.org/html/2103.03997)

**Truelove, Santana de Almeida & Ahmed (2021), "We'll Fix It in Post: What Do Bug Fixes in Video Game Update Notes Tell Us?", ICSE 2021 [PEER]**
- Data: **12,122 bug fixes** in **723 updates** of **30 popular Steam games** (shooter, MOBA, survival, RPG, simulation, strategy, sports, fighting, etc.), plus a developer survey — [arXiv abstract](https://arxiv.org/abs/2103.03997); [ar5iv full text](https://ar5iv.labs.arxiv.org/html/2103.03997)
- Taxonomy of 20 categories: Lewis's plus 9 new ones — Audio, Camera, Collision of Objects, Crash, Exploit, Interaction Between Object Properties, Object Persistence, Triggered Event, User Interface — [ar5iv](https://ar5iv.labs.arxiv.org/html/2103.03997)
- **Most frequent**: Information bugs ("game world information not conveyed correctly"), then Game Graphics, then Action. **Rarest**: Camera, Interrupted Event, Exploit — [ar5iv](https://ar5iv.labs.arxiv.org/html/2103.03997)
- **Most recurring and most severe**: Crash (38% recurrence; 219 of 580 crash fixes appeared in urgent updates); Object Persistence and Triggered Event next in severity. Surveyed developers rated Crash, Action and Exploit bugs as most damaging to gameplay (though Exploit fixes were less often urgent in the data) — [ar5iv](https://ar5iv.labs.arxiv.org/html/2103.03997)
- Why types persist (developer explanations): Information bugs get "low priority" and may be "buried in data files" testers can't see; Action bugs multiply because games have many context-dependent actions, making exhaustive testing combinatorially impossible; graphics bugs recur because of inter-dependencies and high player visibility — [ar5iv](https://ar5iv.labs.arxiv.org/html/2103.03997)
- Caveat: this data is what studios *chose to list in patch notes*, so frequencies reflect reported fixes, not all bugs that exist.

**Butt, Sherin, Khan, Jilani & Iqbal (2023), "Deriving and Evaluating a Detailed Taxonomy of Game Bugs", arXiv [PREPRINT]**
- Multivocal literature review (78 academic + 111 grey-literature sources: postmortems, talks, blogs, videos) extending Lewis et al. to **8 top-level categories and 63 categories in total**: Gaming Balance (too easy/too hard/unwinnable), Implementation Response (collision, freeze, incorrect response, incorrect reward/punishment, unresponsive action), Network, Sound, Temporal (accelerated/delayed response, interrupted event, invalid context state, invalid event occurrence, invalid position), Unexpected Crash (after action, at shutdown, at startup, during non-play), Navigational, Non-Temporal (player stuck, artificial stupidity, invalid value change, faulty information, invalid position, faulty action, invalid graphical representation); validated by a survey of players and industry professionals — [arXiv HTML](https://arxiv.org/html/2311.16645v1)
- Notes sound faults are prevalent in industry sources but nearly absent from academic research (one study) — [arXiv HTML](https://arxiv.org/html/2311.16645v1)
- No numeric frequency per bug type is given — [arXiv HTML](https://arxiv.org/html/2311.16645v1)

**Pascarella, Palomba, Di Penta & Bacchelli (2018), "How Is Video Game Development Different from Software Development in Open Source?", MSR 2018 [PEER]**
- 60 open-source projects (games vs non-games) mined + survey of 45 game and 36 non-game developers. The **Graphic** fault category "absorbs about three times more malfunctions" in games than in traditional software; game faults are spread across many categories, whereas in non-games up to **62%** fall in "Programming"; games showed more Security issues and more Failure-type faults, which the authors link to the lack of testing (no test cases in the studied games); game faults were also harder to classify (the "Unknown" share was about a third higher) — [TU Delft PDF](https://repository.tudelft.nl/file/File_6fbd34ec-fed2-473f-a097-22a5be2e634c)

**Player perception — Backus (2025), arXiv [PREPRINT]**
- From observing YouTube/Twitch gameplay plus interviews: "the types of bugs matter less to the players than how frequently they occur, the context they occur, and the outcome of them" — [arXiv 2504.15408](https://arxiv.org/abs/2504.15408)

**Project-level root causes (postmortem studies)**
- Washburn, Sathiyanarayanan, Nagappan, Zimmermann & Bird (2016), ICSE SEIP, 155 Gamasutra postmortems: the most common "what went wrong" categories were **obstacles (37%)**, **schedule (25%)**, **development process (24%)** and **game design (22%)** (e.g. overly ambitious design). Testing was listed as going wrong in only 11–13% and tools in 17%; self-published teams listed testing as going *right* more often (30% vs 19%) — [Washburn et al. PDF](https://thomas-zimmermann.com/publications/files/washburn-icse-2016.pdf); [Microsoft Research page](https://www.microsoft.com/en-us/research/?p=238008) [PEER]
- Politowski, Petrillo, Ullmann & Guéhéneuc (arXiv 2020, revised 2021), "Game Industry Problems: an Extensive Analysis of the Gray Literature": 200 postmortems (1997–2019) -> 927 problems in 20 types; management and production problems equally common; **technical and game-design problems decreased over the years**; team problems rose in the last decade; marketing problems grew most; "the majority of the main root causes are related to people, not technologies" — [arXiv 2009.02440](https://arxiv.org/abs/2009.02440); [Concordia news release (2021)](https://www.concordia.ca/news/stories/2021/04/07/the-video-game-industrys-problems-are-mostly-due-to-people-not-technology-concordia-researchers-argue.html) [PREPRINT; also a peer-reviewed journal version exists per citations, not verified here]
- Politowski et al. also released a dataset of video game development problems (MSR 2020 data showcase) — [arXiv 2001.00491](https://arxiv.org/pdf/2001.00491)

### Inferences
- For a tycoon/business sim — a numbers-and-UI-heavy genre — the categories most likely to dominate are **Information** (the UI shows a wrong price, timer, stock or profit), **Value** (a variable set to the wrong amount), **Triggered/Event Occurrence and Context State** (production finishing at the wrong time, a building stuck in the wrong state after offline catch-up), and **Exploit** (buy/sell loops or rounding that create free money). Graphics/collision/camera/AI categories that dominate action games matter less here.
- The **most damaging** categories for this game are likely those that destroy progress or the economy: crashes, save corruption, and exploits — matching Truelove's severity ranking (Crash first) and Backus's finding that the *outcome* of a bug drives how players judge it. (This ranking for a tycoon game is an inference; no study covered the genre specifically.)
- The **hardest to reproduce** are temporal/state bugs (they depend on a particular moment or sequence) and anything that requires long play to reach the state — exactly what Truelove's developers complained about. Save files plus a controllable clock directly attack this.
- Truelove's note that Information bugs hide "in data files" testers can't see is relevant because this project keeps all tuning in `data/*.json`: a data-validation test (every recipe references real resources, no negative prices/timers, every building id has a sprite and icon) catches a whole class of Information/Value bugs automatically.
- The postmortem studies suggest a solo developer's biggest risks are scope and schedule, not individual bugs — a reason to keep the bug-hunting process lightweight and focused on high-damage categories.

### Gaps
- **No peer-reviewed study of bugs in Godot *game* projects** (as opposed to the Godot engine) was found. Studies of game-engine bugs exist in the wider literature but were not fetched in this session.
- **No study specifically on save-corruption bugs** in games was found; this remains unquantified.
- No study broke down bug types by genre (Truelove's games span genres but the paper gives no per-genre split); no tycoon/business-sim-specific data.
- Lewis et al. (2010) full text not accessed directly; category list taken via Truelove et al. and Butt et al.
- A 2025 arXiv paper classifying glitches in old games ("Super Mario in the Pernicious Kingdoms", [arXiv 2504.19010](https://www.arxiv.org/pdf/2504.19010)) surfaced but was not read.

---

## 5. Time spent debugging, and the cost of fixing bugs later vs earlier

### Takeaway
The famous "a bug costs 100x more to fix later" claim is **not a reliable universal law**: Boehm & Basili themselves (2001) said the ratio is closer to **5:1 for small, non-critical systems**, and the largest empirical test (Menzies et al., 171 projects) found **no consistent delayed-issue effect**. Claims that developers spend "50% of their time debugging" come from a vendor-commissioned survey; IDE-instrumented measurement found about 14% of IDE time in the debugger.

### Cited Findings
- Boehm & Basili (2001), "Software Defect Reduction Top 10 List", *IEEE Computer* 34(1): "Finding and fixing a software problem after delivery is often 100 times more expensive than finding and fixing it during the requirements and design phase", **but** "the cost-escalation factor for small, noncritical software systems is more like 5:1 than 100:1" — [U. Washington CSEP503 slide quoting the paper (2001)](https://courses.cs.washington.edu/courses/csep503/01wi/lectures/class10/tsld011.htm); [paper PDF (DePaul mirror)](https://condor.depaul.edu/dmumaugh/readings/handouts/SE425/J81.pdf); [UMIACS listing](https://umiacs.umd.edu/node/12156) [PEER]
- Menzies, Nichols, Shull & Layman (2017), "Are delayed issues harder to resolve? Revisiting cost-to-fix of defects throughout the lifecycle", *Empirical Software Engineering*: tested the "delayed issue effect" (DIE) on **171 software projects (2006–2014)**, the largest such study; found **no evidence** for it — "the effort to resolve issues in a later phase was not consistently or substantially greater than when issues were resolved soon after their introduction"; suggests DIE "might be an historical relic that occurs intermittently only in certain kinds of projects" — [arXiv 1609.04886](https://arxiv.org/abs/1609.04886) [PEER]
- Never Work in Theory review (2021): notes the exponential "Boehm curve" was based on careful analysis of decades-old data, that developers surveyed do believe in DIE, and that all four undergraduate SE textbooks the reviewer checked still teach the exponential claim — [Never Work in Theory (2021)](https://neverworkintheory.org/2021/09/26/are-delayed-issues-harder-to-resolve.html)
- Beller, Spruit, Spinellis & Zaidman (2018), "On the Dichotomy of Debugging Behavior Among Programmers", ICSE 2018: survey of 176 developers plus IDE instrumentation (WatchDog 2.0) of 458 developers in Eclipse/IntelliJ; debugging took **around 14% of developers' IDE time**; IDE debuggers are used less than expected and "printf debugging" remains common; advanced breakpoint features are little known or used; amount of testing or programming experience had limited to no effect on time spent debugging — [ICSE 2018 paper (Spinellis site)](https://www.spinellis.gr/pubs/conf/2018-ICSE-debugging-analysis/html/BSSZ18.pdf); [TU Delft SERG page](https://serg.ewi.tudelft.nl/publications/on-the-dichotomy-of-debugging-behavior-among-programmers/) [PEER]. (Caveat: this measures time with the IDE debugger active, so it likely understates total debugging effort such as reading logs and adding prints.)
- Britton et al. (2013), Cambridge Judge Business School MBA project **commissioned by Undo (a reversible-debugger vendor)**: claimed developers spend **50%** of programming time finding and fixing bugs, that reversible debugging users spent 26% less time debugging, and extrapolated a $312bn/year global cost — [Cambridge Judge Business School news (2013)](https://www.jbs.cam.ac.uk/2013/research-by-cambridge-mbas-for-tech-firm-undo-finds-software-bugs-cost-the-industry-316-billion-a-year/) [VENDOR — survey-based self-report, commissioned by a vendor, not peer-reviewed; treat as weak]
- Game-specific: in Truelove et al., Crash bugs appeared in urgent (hotfix) updates 38% of the time — evidence that some *post-release* game bugs force unplanned emergency work — [ar5iv](https://ar5iv.labs.arxiv.org/html/2103.03997) [PEER]

### Inferences
- For a small solo project the honest message is: fixing bugs early is cheaper mainly because the context is fresh and the cause is near the latest change (which also makes `git bisect` short) — not because of a guaranteed 100x multiplier. Boehm & Basili's own 5:1 figure for small systems is the more defensible number to quote, and even that is contested by Menzies et al.
- One category where "later is much worse" plausibly still holds for this game is **save-format and economy bugs**: once players' saves contain corrupted or exploited values, a fix needs a save migration as well as a code change (the project's "never break old saves" rule makes this explicit). This is an inference, not a measured finding.

### Gaps
- Laurent Bossavit's critique of the cost-of-defect curve (*The Leprechauns of Software Engineering*) was not fetched; I could not verify details.
- No game-industry-specific measurement of time spent debugging, or of cost-to-fix by phase, was found.
- The Menzies et al. project sample's process context (what kind of teams/processes the 171 projects used) was not verified in this session, which may limit generalisation.

---

## Source-quality notes for the report writer
- Strongest evidence (peer-reviewed, empirical): Truelove et al. 2021 (ICSE), Pascarella et al. 2018 (MSR), Washburn et al. 2016 (ICSE SEIP), Beller et al. 2018 (ICSE), Menzies et al. 2017 (EMSE), Joorabchi et al. 2014 (MSR), Boehm & Basili 2001 (IEEE Computer).
- Preprints: Butt et al. 2023, Backus 2025, Politowski et al. 2020/21 (arXiv version used).
- Practitioner sources (credible but anecdotal): Factorio FFF #47, Handmade Hero Day 23, GDC talks by Wesley (2013) and Orwig (2017), Bruce Dawson articles.
- Vendor/low quality: Britton/Undo 2013 "50% of time" figure; Symflower blog on TRAFFIC; bugnet.io appeared in searches but was not used.
