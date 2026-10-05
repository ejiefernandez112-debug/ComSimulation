# Game-industry QA process and bug lifecycle (and how a solo dev scales it down)

Research date: 2 October 2026. Each source is tagged with its publication year. Vendor-marketing sources (bug-tracker / QA-outsourcing / plugin sellers: bugnet.io, BetaHub, QATestLab, Forge Logger, Wayline) are marked **[VENDOR]** and used only where nothing better was found.

Reader context: solo developer, no coding experience, single-player Godot 4 business/tycoon sim (Android + PC), working with an AI coding assistant. The project already has a headless rules test (`tests/test_simulation.gd`) and local JSON saves.

---

## 1. Severity / priority scales studios actually use, and how severity is separated from priority

### Takeaway
The most widely documented game-industry scale is a three-class **A / B / C** severity scheme (A = crash/freeze/can't finish or can't ship; B = feature broken but playable; C = cosmetic/minor). Severity (how bad the bug is for the player) is set by the tester, while **priority (when to fix it) is a separate decision made by the producer/lead at triage**. P0–P3 and "blocker/critical/major/minor/trivial" labels show up mostly in tool vendors' material, and I found no public primary document of the exact console-certification bug classes. Those documents are under NDA.

### Cited Findings
- Bob Bates' classes, as quoted on Wikipedia: **A bugs** are "critical bugs that prevent the game from being shipped, for example, they may crash the game". **B bugs** are "essential problems that require attention; however, the game may still be playable. Multiple B bugs are equally severe to an A bug". **C bugs** are "small and obscure problems, often in form of recommendation rather than bugs" (Bates, *Game Design*, 2004, pp. 178–179). Source: [Wikipedia: Game testing](https://en.wikipedia.org/wiki/Game_testing) (accessed 2026)
- A veteran producer (Activision, Disney, 3DO and others) gives the same three classes with blocker labels: **A (Blocker/Critical)** "Fatal flaw. Crashes, freezes, can't finish game." **B (Major/Normal)** "Serious flaw. Features don't work properly." **C (Minor/Trivial)** "Minor flaw. Glitches in artwork, typos, minor annoyances." He also says the **producer determines priority, not QA**. Source: [David Mullich, "Tracking Down Game Bugs" (2015)](https://davidmullich.com/2015/06/01/tracking-down-game-bugs/)
- MIT's game-dev course handout keeps **frequency** ("How common is the bug?… every 2 seconds, or under a blue moon") separate from **severity** ("when it occurs, how badly does it disturb the player's game? Does it crash the system, or does it mean that the player has to go pick up a different red jewel to go on?"). Source: [MIT OCW CMS.611J "Bugs and Bug Reporting" (Fall 2014)](https://ocw.mit.edu/courses/cms-611j-creating-video-games-fall-2014/77735532cada1b978e3545dbe5b57da0_MITCMS_611JF14_BugReportng.pdf)
- Console platform holders publish technical requirement checklists that act as a release gate: **Sony TRC** (Technical Requirements Checklist), **Microsoft XR** (Xbox Requirements) and **Nintendo "Lotcheck"**. A violation can get the game rejected, "possibly incurring additional costs in further testing and resubmission". Source: [Wikipedia: Game testing](https://en.wikipedia.org/wiki/Game_testing)
- Microsoft (general software, not games only) uses a tightening "bug bar" near release. After Zero Bug Bounce, teams moved to a "recall class only bug bar until RTM", meaning only bugs bad enough to justify a recall may still be fixed. Source: [Raymond Chen, The Old New Thing (2018)](https://devblogs.microsoft.com/oldnewthing/20180508-00/?p=98705)
- **[VENDOR]** bugnet.io describes P0–P3 as "the most widely adopted system in game development". Its P0 (Blocker) is a bug that "makes the game unplayable for any player who encounters it with no workaround", with examples such as crashes when loading save files, save corruption, infinite loading and progression blockers. Source: [bugnet.io blog (undated, c. 2025–26)](https://bugnet.io/blog/bug-severity-classification-for-game-developers). The "most widely adopted" claim is unsupported marketing.
- **[VENDOR]** The same vendor says console certification bugs override severity: "any bug that would fail platform certification is a ship-blocker regardless of severity". Source: [bugnet.io triage guides (c. 2025–26)](https://bugnet.io/blog/bug-triage-meeting-guide-for-game-teams)

### Inferences
- A practical solo scheme: **severity = A/B/C** (crash / data-loss / soft-lock vs. broken feature vs. cosmetic) plus a separate **priority = "fix now / fix before next release / someday / won't fix"**. Keeping them separate lets a rare-but-catastrophic bug (for example, a corrupted save) outrank a frequent cosmetic one.
- For a tycoon game with offline progress and JSON saves, **save corruption, wrong offline-catch-up money, and soft-locks** (for example, the player can't afford any action and can't recover) belong in class A, even when they are rare.
- Bates' rule that "multiple B bugs are equally severe to an A bug" is useful for a solo dev. A pile of small broken features hurts as much as one crash.

### Gaps
- I could not access the actual severity definitions in *Game Testing: All in One* (Schultz & Bryant, 3rd ed. 2016). Search results gave only catalogue pages, so nothing is quoted from that book here.
- Microsoft XR, Sony TRC and Nintendo Lotcheck bug categories are confidential partner documents. No primary public text was found. One search summary said console QA approves a game when there are "no known class A bugs, few or no class B bugs, and a reasonable sum of class C bugs, with class D bugs not affecting releases". It appeared to come from a QA-outsourcing vendor page (QATestLab **[VENDOR]**) and could not be verified against a platform-holder source, so treat it as hearsay.
- "S1–S4" scales: I found no named game studio publicly documenting one.

---

## 2. What a good game bug report contains (fields and templates)

### Takeaway
Sources agree on a core set: **one-line summary, steps to reproduce, expected vs. actual result, reproduction rate, severity, build/version, platform/hardware, and attachments (screenshot/video, logs, crash dump, save file)**, plus a duplicate check before filing. Modern in-game reporters capture most of this automatically, and the save file is the single most valuable attachment for repro.

### Cited Findings
- Joel Spolsky's minimum for any bug database: "complete steps to reproduce the bug", "expected behavior", "observed (buggy) behavior", "who it's assigned to", and "whether it has been fixed or not". Source: [Joel Spolsky, "The Joel Test" (2000)](https://www.joelonsoftware.com/2000/08/09/the-joel-test-12-steps-to-better-code/)
- The MIT course template gives this order:
  1. Check for duplicates.
  2. Steps to reproduce, including reliability (for example "2 out of 3 times", or "did it once but then couldn't get it to happen again after 10 times"), with a confirmation pass.
  3. Compatibility issues (OS, hardware, browser).
  4. Frequency.
  5. Severity.
  6. Description of actual and *expected* behaviour.
  7. Supporting data: screenshots, error popups, "crashdump log".

  Low-severity bugs need little verification ("One screenshot… is enough"). Crashes and hangs "usually need a second pass to check on the repeatability". Source: [MIT OCW CMS.611J (2014)](https://ocw.mit.edu/courses/cms-611j-creating-video-games-fall-2014/77735532cada1b978e3545dbe5b57da0_MITCMS_611JF14_BugReportng.pdf)
- Mullich's studio-style report fields: bug number, summary/headline, location/component, description, expected vs. actual, steps to reproduce, **reproduction rate (percentage)**, severity, priority. Source: [Mullich (2015)](https://davidmullich.com/2015/06/01/tracking-down-game-bugs/)
- In-game bug reporter for *Industries of Titan* (Brace Yourself Games). It auto-captures system specs ("Windows version, CPU, GPU, RAM"), "Log files", the "Current save file", screenshots and "All configuration files". It sits as a button on-screen or on the pause screen and gives each report "a player-facing unique ID", with search for duplicates and filtering by game version. Volume: "a couple of hundred reports a day". Source: [Ben Humphreys, Game Developer (2022)](https://www.gamedeveloper.com/game-platforms/in-game-bug-reporter-best-practices)
- **[VENDOR]** A Godot plugin, Forge Logger, binds an in-game report to F8 and attaches a screenshot, the log file, and the scene, build and environment. It is MIT-licensed, and its hosted dashboard has a free tier (100 reports/month). Source: [Godot Asset Library listing (2026)](https://www.godotengine.org/asset-library/asset/5321). I have not evaluated its quality.

### Inferences
- For this project, a "good report" template the developer or the AI assistant can fill in:
  - Title
  - Build/commit
  - Platform (Android model / PC)
  - Steps
  - Expected
  - Actual
  - How often (x of y tries)
  - Severity A/B/C
  - Attachments: screenshot, `user://logs/godot.log` (desktop), and **a copy of the save JSON**

  Because saves are plain JSON with timestamps, attaching the save plus the device clock time is often enough to reproduce offline-catch-up bugs exactly.
- An in-game "Report bug" button that zips the save and log is the high-leverage feature once outside players exist. Per the project rules it belongs in `scenes/debug/` or behind a setting, not core gameplay.

### Gaps
- No public AAA studio bug-report template (for example a Jira template from a named studio) was found. The templates above come from a course, a veteran producer's blog and one mid-size studio.

---

## 3. Triage: who, how often, bug bashes, Zero Bug Bounce, bug-count release gates, Joel Test #5

### Takeaway
At AAA scale, triage is run by producers and leads, **daily or several times a day near ship** (The Coalition ran "several triage meetings daily" on *Gears of War 4*). Each bug leaves triage with a priority, an owner and a milestone, or a "won't fix / known shippable" label. Release readiness is judged from the bug-count trend. "Zero Bug Bounce" (no active bugs older than ~48 hours) is the classic Microsoft milestone, and release candidates must "hold" through testing before going to certification. The Joel Test's "fix bugs before writing new code" is well known, but I found no game studio that publicly says it follows that rule literally.

### Cited Findings
- *Gears of War 4* / The Coalition (2016):
  - "Triage": the studio holds **several triage meetings daily** with key staff from each division, who decide bug priority and fixes.
  - "Wnf (Will Not Fix)" is a low-priority bug "you don't plan to fix because it's too risky or not a smart use of resources". These are "sometimes known as 'KS,' meaning known, shippable bugs".
  - "RC" is "A build of the game that a development team would consider sending to cert after testing".
  - Passing certification means the game has "gone gold".

  Source: [Emanuel Maiberg, Vice, "AAA Game Development: A Glossary" (2016)](https://www.vice.com/en/article/aaa-game-development-a-glossary)
- Lifecycle statuses a developer can set: FIXED (QA retests in the next build), CAN'T REPRODUCE, NEED MORE INFORMATION, NOT A BUG / WORKS AS DESIGNED, WILL NOT FIX ("approved for shipping"). The producer decides priority. Source: [Mullich (2015)](https://davidmullich.com/2015/06/01/tracking-down-game-bugs/)
- **Zero Bug Bounce:** "the moment that, even for only a brief shining moment, there were no active bugs in the database more than 48 hours old". Management plots a predicted "bug glide path" down to ZBB, then moves to a "recall class only bug bar until RTM". Source: [Raymond Chen, Microsoft (2018)](https://devblogs.microsoft.com/oldnewthing/20180508-00/?p=98705). This is Microsoft general practice; Xbox game teams inherited the vocabulary, but this source is not game-specific.
- Post-launch patch pipeline at a console studio: leadership rates bugs by severity. Non-emergency patches typically take "1-4 weeks for patch development, 1-2 weeks for testing, one week for certification, and then up to six days until the next Tuesday", so at least three weeks. Teams keep "lists of bugs hundreds deep" after launch. Source: [@askagamedev (anonymous AAA developer), Tumblr (undated, c. 2017)](https://www.tumblr.com/askagamedev/155303210216/why-does-it-take-game-developers-so-long-to-make)
- Joel Test #5, "Do you fix bugs before writing new code?": "In general, the longer you wait before fixing a bug, the costlier (in time and money) it is to fix." He illustrates the opposite, an "infinite defects methodology", with Microsoft Word for Windows, where a programmer "simply wrote 'return 12;' and waited for the bug report". Source: [Joel Spolsky (2000)](https://www.joelonsoftware.com/2000/08/09/the-joel-test-12-steps-to-better-code/). University of Washington's software-engineering course still teaches it with this rationale: you are "familiar with the code now", bugs get harder to find later, and later code "may depend on this code". Source: [UW CSE 403 lecture slides (2019)](https://courses.cs.washington.edu/courses/cse403/19wi/lectures/lecture10-process-JoelTest.pdf)
- Wube (*Factorio*) shows the trend-as-health-signal idea. After the 0.17 release, they tracked crash reports plus bug-forum count, and reported that "we are fixing bugs faster than they are reported". Source: [Factorio Friday Facts #285, "Bugs, bugs, bugs" (8 March 2019)](https://factorio.com/blog/post/fff-285)
- **[VENDOR]** For a 2–10 person studio, bugnet.io recommends a "daily 10-15 minute triage session" whose outputs per bug are severity, milestone and owner, or close it. It also says shipping on the first day the blocker graph hits zero is risky because "new bugs typically emerge during final testing phases". Source: [bugnet.io (c. 2025–26)](https://bugnet.io/blog/game-bug-triage-guide-for-small-teams)

### Inferences
- Solo scale-down: triage is a **once-a-week, 15-minute review of the bug list**. Label each new item A/B/C and fix-now / next-release / later / won't-fix. A-class bugs (crash, save loss, wrong money) are fixed immediately; that is Joel Test #5 applied only to severe bugs.
- A solo version of a release gate: **no open A-class bugs, and no new A/B bugs found in the last full playthrough of the release-candidate build**. That is the solo equivalent of an RC that "holds".
- "Known shippable" is a legitimate category. Writing down why a bug is acceptable (for example "cosmetic, rare") stops it from being re-triaged every week.

### Gaps
- I found no named game studio publicly documenting a formal "bug bash" day. The term is common in general software, but I have no game-specific primary source.
- Evidence that literal Joel #5 ("fix all bugs before any new code") is policy at any named game studio was not found.

---

## 4. Crash reporting and telemetry (Sentry for Godot, Steam, Android vitals), and evidence that telemetry finds bugs testers miss

### Takeaway
Automatic crash and error reporting is standard and finds problems testers can't, because real players have hardware, clocks and play patterns QA never sees. The strongest data points are Microsoft's 2002 finding that **1% of bugs caused half of all errors** and Wube receiving **12,000+ automatic crash reports** after one release. For Godot specifically, **Sentry has an official Godot SDK** covering Windows, Linux, macOS, Android, iOS and Web that captures GDScript errors with stack traces. Steam's built-in error reporting is end-of-life and 32-bit-only, so it is not an option for Godot 4. On Android, **Google Play's Android vitals** collects crash/ANR rates for free and penalises apps above 1.09% crash or 0.47% ANR rates.

### Cited Findings
- **Sentry Godot SDK (official, github.com/getsentry/sentry-godot):**
  - Current stable version per the docs: **2.3.0**, installed into `addons/sentry`; minimum config is a DSN.
  - Platforms: Windows and Linux (via the Native SDK), macOS 12+, iOS 15+, Android, Web.
  - Captures native crashes, "Godot runtime errors, such as script and shader errors", GDScript stack traces with optional local variables, structured logs and `print()` output, breadcrumbs, scene tree and screenshot attachments, and session/crash-free metrics.

  Source: [Sentry docs, Godot platform page (accessed Oct 2026)](https://docs.sentry.io/platforms/godot/)
- **Godot's built-in logging:**
  - File logging is on by default on **desktop**, written to `user://logs/godot.log`, keeping 5 files (`debug/file_logging/max_log_files`).
  - In release builds, stdout is only flushed on exit or crash.
  - Since **Godot 4.5**, a custom `Logger` subclass registered with `OS.add_logger()` can capture engine messages and errors for an in-game console or "Remote error reporting to servers". It must be thread-safe.
  - Crash backtraces are only useful with debug symbols, which official Godot binaries lack.

  Source: [Godot docs, Logging (stable, accessed 2026)](https://docs.godotengine.org/en/stable/tutorials/scripting/logging.html)
- **Steam Error Reporting** uploads minidumps "after 10 similar exceptions are thrown", but it "is nearing its End-Of-Lifetime and only limited support is available", and "the error reporting API currently only supports 32-bit applications on Windows". Source: [Steamworks docs, Error Reporting (accessed 2026)](https://partner.steamgames.com/doc/features/error_reporting)
- **Android vitals (Google Play):**
  - Bad-behaviour thresholds: user-perceived crash rate **1.09%** overall / **8%** per phone model; user-perceived ANR rate **0.47%** overall / **8%** per phone model.
  - If an app exceeds them, "Play may reduce the visibility of your title" and may show a warning on the store listing.
  - Play uses the last **28 days** of data, and "emerging issues" get **21 days** to fix.
  - Memory thresholds may affect visibility from February 2027.

  Source: [Android Developers, Android vitals (accessed Oct 2026)](https://developer.android.com/topic/performance/vitals)
- **Telemetry finds what testers miss (Microsoft, 2002):** Ballmer said error reporting showed "about 20 percent of the bugs cause 80 percent of all errors, and one percent of bugs cause half of all errors", calling it "stunning to me". Error reporting let Microsoft fix 29% of Windows XP errors in SP1 and more than half of Office XP errors in SP2. Source: [Redmond Magazine / MCPmag (Oct 2002)](https://redmondmag.com/articles/2002/10/03/microsoft-error-reporting-drives-bug-fixing-efforts.aspx). Not a game, but it is the canonical public data point.
- **Games:** Wube received "over 12,000 crash reports automatically sent in for 0.17", alongside 372 bug-forum reports at the time. Source: [Factorio FFF #285 (2019)](https://factorio.com/blog/post/fff-285)
- **Valve:** "Playtesting continues after we ship", with gameplay stats, forum responses and fan feedback as data sources. The 2009 talk shows a TF2 "Heatmap of Death Concentrations" from stat collection, and lists stats' weaknesses: "Averages hide extreme examples", "Miss nuance". Source: [Mike Ambinder, "Valve's Approach to Playtesting", GDC 2009](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf)

### Inferences
- For this game (Android + PC, single-player), the cheapest stack is:
  1. **Google Play Console's Android vitals**: free, automatic, and the metric Google judges the app on.
  2. **Godot's desktop log file** for PC players to attach.
  3. Optionally the **Sentry Godot SDK** (or a 4.5+ custom `Logger`) to collect GDScript errors from real players.

  Even one Sentry error report with a stack trace can be pasted straight to the AI assistant.
- Logs and telemetry from players' devices raise privacy and consent questions (GDPR, Google Play Data safety form). A single-player game should send only error data, ideally opt-in.
- The Pareto finding (1% of bugs cause about half of errors) means a solo dev should **sort crash reports by how many players hit them** and fix the top few. Every report does not need a fix.

### Gaps
- Unity Cloud Diagnostics and Backtrace were not researched in depth. They are not relevant to Godot, and time was prioritised elsewhere.
- Sentry's minimum supported Godot version and its current free-tier limits were not on the fetched page. Check them on sentry.io pricing and the SDK README before adopting.
- Whether Godot's file logging works on Android by default is not stated in the docs page fetched.
- No game-specific study quantifying "bugs found by telemetry vs. by testers" was found. The Microsoft figures are general software.

---

## 5. Playtesting cadence (Valve, Portal) and bugs vs. design problems

### Takeaway
Valve's famous cadence is **weekly**. The *Portal* team playtested "every single week", sometimes starting only a week into development, and turned level changes around in 2–5 days. However, Valve's own 2009 GDC talk states that playtesting's goal is "Fun", "Not bug testing", "Not game balancing". Playtests surface **design and comprehension problems**; bug-finding is QA's job, done separately.

### Cited Findings
- Kim Swift and Erik Wolpaw on *Portal*:
  - "We playtested our game every single week."
  - Once a level is decided, "in two to five days we'll have it up and running".
  - Testers were watched ("very deliberately watching our players") and asked afterwards to "tell us everything that you remember about the story".
  - Exposition that playtesters missed was cut or moved into the environment.

  Source: [Game Developer (Gamasutra), "Still Alive: Kim Swift and Erik Wolpaw Talk Portal" (25 March 2008)](https://www.gamedeveloper.com/business/still-alive-kim-swift-and-erik-wolpaw-talk-portal)
- Secondary summary: the *Portal* team began playtesting after one week with only "one half-finished room", and ran a **Friday playtest → Monday discussion → fix during the week → test again Friday** loop. Source: [Mark Brown, GMTK newsletter, "Valve's Secret Weapon" (c. 2024)](https://gmtk.substack.com/p/valves-secret-weapon). This is a secondary source; I did not trace the Friday/Monday detail to a primary interview.
- Mike Ambinder (Valve experimental psychologist), GDC 2009:
  - "Game designs are hypotheses / Playtests are experiments".
  - "Get data early, get data often / Iterate constantly".
  - Playtesting goal: "Fun / Not bug testing / Not game balancing / DEFINITELY not focus testing".
  - Methods: direct observation, think-aloud verbal reports, Q&A (survey → individual → group), stats collection, design experiments, surveys, physiological measures.
  - Summary slide: "Do your QA early".
  - The deck itself does **not** state a weekly cadence.

  Source: [Ambinder, GDC 2009 slides (PDF)](https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf)
- Testers' design feedback should be a "critique" ("a statement of opinion… backed up by facts, examples"), not a criticism. Testers play longer than designers, so they notice repetitive UI friction (for example "clicking through eight levels of menu"). Source: [MIT OCW CMS.611J (2014)](https://ocw.mit.edu/courses/cms-611j-creating-video-games-fall-2014/77735532cada1b978e3545dbe5b57da0_MITCMS_611JF14_BugReportng.pdf)

### Inferences
- Keep two lists: **bugs** (the game does something other than intended) and **design notes** (works as intended, but players are confused or bored). Valve's own framing supports not mixing them.
- Solo scale-down: a **weekly (or per-feature) playtest** with one or two outside people (friends or family, on their own phone) using silent observation plus "tell me what you think is happening". For a tycoon game this mostly catches confusing economy and UI, not crashes.
- The developer plays a full session of the latest build each week, which acts as a lightweight regression pass.

### Gaps
- No primary source found giving Valve's typical number of playtesters per session.
- No specific playtest cadence data was found for tycoon or management-sim studios.

---

## 6. Regression bugs: preventing fixed bugs from coming back

### Takeaway
The lifecycle ends with **verification**. The tester (usually the original reporter) confirms the fix in a build that actually contains it, and reopens it if not. Studios that ship continuously add **automated tests**; Rare built *Sea of Thieves* with gameplay automated tests from the start. Fixes themselves cause new bugs: Wube saw the severe post-release bugs come from "non-trivial fixes later on".

### Cited Findings
- MIT lifecycle: bugs "are found, reported in the database, assigned to a fixer, fixed, and then confirmed as fixed in the current build. Testers are responsible for confirming that a bug has been fixed, so all bugs (eventually) return to their initial reporter."
  - Before verifying, "make sure the bug fix is in the build you are testing"; the developer should state the build in which it is fixed.
  - If it isn't fixed, update it and "assign it back to the developer who 'fixed' it".
  - The course advises against long "database conversations" and says to talk face to face.

  Source: [MIT OCW CMS.611J (2014)](https://ocw.mit.edu/courses/cms-611j-creating-video-games-fall-2014/77735532cada1b978e3545dbe5b57da0_MITCMS_611JF14_BugReportng.pdf)
- Status flow at a traditional studio: FIXED → "QA retests in next build". Source: [Mullich (2015)](https://davidmullich.com/2015/06/01/tracking-down-game-bugs/)
- The verification stage confirms "that fixes resolve issues without introducing new problems". Source: [Wikipedia: Game testing](https://en.wikipedia.org/wiki/Game_testing)
- Wube found that severe bugs appeared not right after the 0.17 release but as "a reaction to non-trivial fixes later on". Source: [Factorio FFF #285 (2019)](https://factorio.com/blog/post/fff-285)
- Rare's GDC 2019 talk "Automated Testing of Gameplay Features in Sea of Thieves" (Robert Masella) covered why automated testing was the right choice for *Sea of Thieves*, the in-house framework that "easily let team members create automated tests", test types, coverage, and best practices. Source: [GDC news preview (2019)](https://gdconf.com/news/sea-thieves-devs-share-automated-testing-tips-gdc-2019); [GDC Vault talk page](https://gdcvault.com/play/1026366/Automated-Testing-of-Gameplay-Features). A search snippet attributed to Unreal Fest Europe 2019 says the project has "hundreds of thousands of automated tests", but I could not fetch that page (HTTP 403) to verify it.

### Inferences
- **For this project:** the existing headless `tests/test_simulation.gd` is the right regression tool. The habit to adopt is that **every fixed rules bug gets a test that would have caught it**, written before or with the fix and run after every change to `scripts/sim/`. This is cheap to ask the AI assistant for, and it is exactly what CLAUDE.md already requires.
- Keep a few **"golden" save files** (an old-version save, a save with huge offline time, a save with the clock set backwards) and load them as part of testing. That is how save migrations and offline-catch-up regressions get caught.
- Verification for a solo dev means re-doing the original repro steps in the new build *before* marking the bug closed, not just trusting that the code change looks right.

### Gaps
- Quantitative data from *Sea of Thieves* on regression reduction (bug counts, QA hours saved) was not retrievable from the pages fetched.
- No game-specific statistic on what share of bugs are regressions was found.

---

## 7. How solo and small indie developers run this lightweight

### Takeaway
The real indie accounts found show three practices:
- a **public bug channel** (forum, Discord or Steam) plus **automatic crash reports** (Wube/*Factorio*);
- an **in-game report button that attaches the save and log** (Brace Yourself Games, *Industries of Titan*);
- a **fixed patch rhythm** (for example a weekly "Bugfix Friday"), or very rapid hotfixing right after launch (solo dev *Parcel Game*).

Tool choice (GitHub Issues, Trello, spreadsheet) matters much less than having one list. Most "what tool should solo devs use" content online is vendor marketing.

### Cited Findings
- *Factorio* (Wube, small/mid studio) tracks two signals, automatic crash reports and a public bug-report forum (372 open reports at the time), and publishes the trend in its weekly dev blog. Source: [FFF #285 (2019)](https://factorio.com/blog/post/fff-285). Community members note that Wube's patch notes list every minor fix and link back to the forum thread that reported it. Source: [r/factorio discussion via search result (2024)](https://redlib.hbubli.cc/r/factorio/comments/1ge6frz/version_2012). This is community commentary only.
- *Industries of Titan* has a pause-screen bug button that auto-attaches the save, logs, configs, specs and a screenshot, and gets "a couple of hundred reports a day". Source: [Ben Humphreys, Game Developer (2022)](https://www.gamedeveloper.com/game-platforms/in-game-bug-reporter-best-practices)
- Solo developer Dan Davison (*Parcel Game*, an incremental game) shipped **40+ patches in the first three days**, driven by 1,500 day-one players and 50+ reports. He said a solo dev doesn't wait for "a chain of approvals" and can fix things straight away. Source: [ModDB press release (c. 2025)](https://www.moddb.com/news/after-1500-day-one-players-parcel-game-received-40-patches-during-its-launch-week-as-player-feedb). This is the developer's own self-promotional press release.
- An itch.io devlog titled "Bugfix Fridays and weekly progress updates" describes releasing a bug-fix patch every Friday with a list of fixed bugs *and* known-but-unfixed bugs. Source: [itch.io devlog 179596](https://itch.io/devlog/179596/bugfix-fridays-and-weekly-progress-updates). This comes from the search snippet only; the page returned 404 when fetched, and the author and date are unverified.
- Console patch reality (contrast): AAA patches take at least about three weeks because of QA plus certification. Source: [@askagamedev (c. 2017)](https://www.tumblr.com/askagamedev/155303210216/why-does-it-take-game-developers-so-long-to-make). On PC and Android, a solo dev is not bound by certification, which is why cadences like *Parcel Game*'s are possible.
- **[VENDOR]** bugnet.io: a spreadsheet "is perfectly adequate" for a solo dev pre-launch with a dozen self-found bugs. Past about 20–30 bugs, or once player reports arrive, a tracker (GitHub Issues, Trello or their product) saves time. Source: [bugnet.io (c. 2025–26)](https://bugnet.io/blog/should-i-use-a-spreadsheet-for-bug-tracking). The advice is plausible, but the vendor has an obvious interest.
- **[VENDOR]** BetaHub, Wayline and similar sites recommend centralising Discord, Steam, email and crash reports into one tracker. Source: [betahub.io (2025–26)](https://www.betahub.io). This is marketing only.

### Inferences
A minimal solo process for this game:
1. **One list** of bugs and design notes. GitHub Issues fits because the project is already a Git repo, and the AI assistant can read and close issues from commits. A `bugs.md` in the repo also works.
2. **Severity A/B/C + priority**, triaged weekly in about 15 minutes.
3. **Fix A-class immediately.** Each fix gets a regression test in `tests/` where it is a rules bug.
4. **Weekly self-playtest** of the latest build on both PC and an Android phone, plus occasional outside testers.
5. **Before each release:** no open A bugs, a full playthrough of the release build with no new A/B bugs, and old saves load correctly.
6. **After release:** Android vitals (free) plus an in-game "copy save + log" or "send report" button, and optionally the Sentry Godot SDK. Patch on a predictable rhythm (for example weekly) except for hotfixes of A-class bugs.

### Gaps
- I found few first-person, non-vendor accounts from *solo* developers describing their bug-tracking tool and weekly routine. Search results were dominated by vendor blogs (bugnet.io, Wayline, BetaHub). Godot-forum or Reddit threads were not reviewed for lack of time.
- No sourced data on what share of indie devs use GitHub Issues vs. Trello vs. text files.
