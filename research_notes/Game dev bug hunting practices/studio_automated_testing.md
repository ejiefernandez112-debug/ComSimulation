# Automated testing and CI at named game studios: practices and measured results

Research date: 2 October 2026. Every source has its year next to it. The strongest primary source found is Rare's GDC 2019 slide deck. Its speaker notes are embedded in the PDF, and they include the full numbers: test counts, coverage, bug counts, tester counts and days to verify a build. Many write-ups of these talks are only previews with no numbers in them. Those previews were checked and left out wherever they added nothing.

Source quality legend: **[P]** = primary (the studio's own talk, slides, blog or paper). **[S]** = secondary journalism or a summary. **[M]** = vendor or marketing material, low quality, not relied on.

---

## 1. Rare / Sea of Thieves (GDC 2019 Masella; Unreal Fest Europe 2019 Baker; follow-ups)

### Takeaway
Rare built Sea of Thieves (2015–2018, live after that) around automated tests from day one. By March 2019 they had just over 23,000 tests, or more than 100,000 counting asset-audit checks. Coverage was 60% decision coverage and 70% function coverage. Every test ran at least every 20 minutes, with a pre-commit gate. Rare reports these results against its own earlier games: the peak open-bug count was 214, against nearly 3,000 on Banjo-Kazooie: Nuts & Bolts. Full-time testers fell from 50 to 17 compared with Kinect Sports Rivals, and verifying a build took 1.5 days instead of 10. Rare also says it became "more pragmatic over time". It introduced cheap "actor tests", kept slow map-based integration tests only for "golden paths", auto-retried flaky tests, and quarantined and then deleted tests that kept failing.

### Cited Findings
**Why they did it, and the baseline**
- Rare's motivation was "bad experiences with testing on our previous projects". On Sea of Thieves, "Instead of relying on manual testing, we used automated testing to check every part of the codebase, including gameplay features." — [P] [Masella, GDC 2019 slides + speaker notes (PDF)](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Rare had about 200 staff in 2019. The game was open-world and multiplayer, run as a live service, and the aim was to be able to ship an update "with a week's notice if necessary". On Kinect Sports Rivals, verifying an update took about two weeks. — [P] [Masella 2019 slides](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Worked example of the problem: Masella himself broke the skeleton AI's target memory during the beta. Manual testers did not notice. Players reported it on the forums weeks later, and by then "thousands of changes" made it hard to find which one caused it. An automated test would have flagged it straight away. — [P] [Masella 2019 slides](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)

**Test types (all in a heavily modified Unreal Automation System, comparable to the Unity Test Runner)**
- **Unit tests** check one code function, in the pattern "set up → run the operation → assert". They take up to about 0.1 s each. — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- **Integration tests** are small purpose-built Unreal maps. Example: a player, a platform and a ship's wheel, with no ship. The logic is written in Blueprint and fakes input, and each map reports pass or fail. They take about 20 s each because of asset loading and network setup. A networked variant switches execution between the server and several clients inside one test. — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- **Actor tests** were invented midway through production. They sit between unit and integration tests: a "unit test for game code" that spawns real actors in a minimal world and ticks them by hand. Example: a shadow skeleton changes from Dark to Light state when the world time is set to midday. The downside is that the object runs outside its normal update loop. The upside is that the test runs "incredibly quickly". — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- **Other test types:**
  - Asset audit tests check data setup.
  - Screenshot tests compare a percentage of differing pixels against "last good" images. A human checks the non-deterministic ones only every 1–2 weeks.
  - Performance tests track trends in load time, memory and framerate.
  - Bootflow tests check that client, server and services can talk, for example a client joining a server.
  — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Tommy Thompson's 2019 account, based on interviews with Rare, adds AI behaviour-tree tests, multiplayer integration tests, network-latency tests (poor or unstable connections) and platform tests (PC versus Xbox One). — [S] [Game Developer, "How Rare Automates Testing for AI (and More) in Sea of Thieves (Part 4 of 4)", Tommy Thompson, June 2019](https://www.gamedeveloper.com/design/how-rare-automates-testing-for-ai-and-more-in-sea-of-thieves-part-4-of-4-)

**Test counts and mix (March 2019)**
- 70% of tests were actor tests and only 5% were integration tests, about half of them networked. There were "relatively small" numbers of performance, screenshot and bootflow tests because these were the slowest.
- In total there were "just over 23 thousand tests", or "over 100 thousand" if asset-audit checks are counted.
- Coverage was "60% decision and 70% function coverage".
- The ratio of actor tests to integration tests was about 12:1.
— [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- By 2024 Rare describes the Sea of Thieves project as having "hundreds of thousands of automated tests", now including tests for shader code (the Rare Shader Test framework). — [P] [Microsoft Pure Virtual C++ 2024, Keith Stockdale (Rare), session description](https://learn.microsoft.com/en-us/shows/pure-virtual-cpp-2024/automated-testing-of-shader-code)

**How often tests run, and the submit gate**
- CI ran on TeamCity with a build farm. "How often we run each individual test varies based on how long the test takes, but in general all our tests are run at least once every 20 minutes." A failure turns the build "red". Screens around the studio show the build status and the name of whoever last changed something the failing job covers. — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Submit rules:
  - (1) Nobody may submit unless the build is green, and a change that breaks the build is backed out fast.
  - (2) "Every change must be covered by some kind of automated testing if it makes sense." The person who made the change writes the test and submits it with the change. Rare has no dedicated test engineers, and asset changes are covered by the asset audits.
  - (3) Every submit must pass a "pre commit" job on the build system. It builds the change and runs a subset of related tests, because running everything would be too slow.
  — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- A wider set of tests also runs regularly to catch intermittent problems and slow trends such as loading time. Manual testers then check builds that are "almost certain" to have no show-stoppers. Insider beta players are asked for feedback on the game itself, not for bug finding. — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Jessica Baker, a Rare software engineer, wrote in 2018: the team used continuous delivery with "a stable production-ready build at all times", tests run "round the clock", and "Every time we check in a change to the build, it has to run against the current build and pass all the tests." Her post is about writing testable code (orthogonal design, mocking, dependency injection) and contains no metrics. — [P] [Jessica Baker, "Tests and Testability", March 2018](https://jessicabaker.co.uk/2018/03/11/tests-and-testability/)
- Thompson (2019) reports automated runs about every 20 minutes, with the larger multiplayer and performance tests run overnight. The game was deployed internally more than 100 times before launch. — [S] [Game Developer, Thompson 2019](https://www.gamedeveloper.com/design/how-rare-automates-testing-for-ai-and-more-in-sea-of-thieves-part-4-of-4-)

**Measured results (all compared with Rare's own earlier games)**
- Days to verify a build: **10 on Kinect Sports Rivals → 1.5 on Sea of Thieves**. — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf). The speaker note also says "a full two weeks" for Kinect Sports Rivals, which matches 10 working days.
- Full-time testers at release: **50 on Kinect Sports Rivals → 17 on Sea of Thieves**. The smaller team also worked "more closely with the rest of the development team to assess the game from a player's perspective." — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Peak bug count: **214 on Sea of Thieves against "nearly 3000" on Banjo-Kazooie: Nuts & Bolts**. The open-bug curve "remained fairly steady" instead of growing until a crunch at the end of the project. There was also a policy that "bugs should be prioritised before feature work". — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Crunch: "I don't have concrete stats for this unfortunately, but anecdotally developers … worked much less overtime", which Masella attributes to the automated testing. — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Rare later ran Sea of Thieves with continuous delivery, releasing "weekly" to players with "a tiny manual test team". — [S/P] [Henry Golding (led test framework teams on Sea of Thieves and Minecraft), LinkedIn summary of his GDC 2021 talk, Dec 2021](https://www.linkedin.com/pulse/gdc-2021-lessons-learned-adapting-sea-thieves-testing-henry-golding)

**Problems and what did not work ("how we became more pragmatic over time")**
- In full production the tests became "quite a burden":
  - Writing them took longer than hoped.
  - The pre-commit gate was meant to take under 1 hour. Slow tests pushed it past that, and developers waited "in a queue for half a day or more."
  - Engineers spent "more time than was bearable fixing flaky tests", and the worst offenders were long or complex tests.
  — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Fixes:
  - Move gameplay logic checks down from integration tests (about 20 s) to actor tests.
  - Use integration tests only for the "golden path" (the success case), and actor tests for failure and edge cases.
  - Combine several related checks into one integration test, deliberately breaking "one behaviour per test" to save start-up cost.
  - Keep the expensive player object loaded while moving from one test map to the next.
  — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Brittle tests: tests that depended on implementation details, such as an exact frame or a fixed delay, failed when that code was refactored. The fix was to poll each frame for the expected state, with a long timeout. — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Flaky tests: the causes were infrastructure, the network, and state leaking from earlier tests. Policy:
  - A failing test is automatically retried once, and only a second failure turns the build red.
  - A weekly "top intermittent failures" list decides which tests an engineer investigates.
  - A test that keeps failing is quarantined: it still runs but no longer blocks, and its owner is notified. "If the test is not fixed by a certain amount of time, the test is automatically deleted," on the reasoning that if nobody prioritises fixing it, what it tests "is probably not important enough."
  — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Limits of automation: people are better at spotting visual and audio defects, at exploratory testing, and at judging "how the game feels to play". — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Lessons:
  - Over the long term "speed of development will be about the same," because less time goes on bugs that keep coming back. This needed producers and managers to agree.
  - Training the team and building stable infrastructure takes real time. "Adding testing to just one part of your game project to begin with, may be easier."
  - Automated testing is "more of a hindrance than a help if you're still iterating on your game to find if its fun." Rare kept a separate prototype branch with no tests.
  - Rare "rarely created tests first in the test driven development style". The usual workflow was to make a change, see it work, then add tests "to pin down its behaviour".
  - "Focus on creating tests for areas that are likely to have bugs and avoid creating tests that will need a lot of work to maintain." "Perfect testing coverage is a worthy goal, but unachievable in practice."
  — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Culture: test failures were handled collaboratively, "avoiding blame culture", because "all programmers…still make bugs". — [S] [Game Developer, Thompson 2019](https://www.gamedeveloper.com/design/how-rare-automates-testing-for-ai-and-more-in-sea-of-thieves-part-4-of-4-)
- Moving the method to Minecraft (Mojang, GDC 2021):
  - Have "a small team to own the transition".
  - "Meet the codebase where it is." Use a "middle ground" framework that allows "unit-like tests to be written for game code without decoupling the code under test", the same idea as actor tests.
  - Bias "first for adoption … then shifting focus to scaling".
  - Treat developers as allies, and get support from leadership.
  — [S/P] [Golding, Dec 2021](https://www.linkedin.com/pulse/gdc-2021-lessons-learned-adapting-sea-thieves-testing-henry-golding); talk page: [GDC Vault 2021](https://gdcvault.com/play/1027345/Lessons-Learned-in-Adapting-the)

### Inferences
- The best-supported results here (verification 10 → 1.5 days, testers 50 → 17, peak bugs ~3,000 → 214) come from the studio comparing itself with its own earlier, different games. They are not controlled experiments. The games differ in genre and scope, and the bug-first policy and continuous delivery changed at the same time as the tests. Treat them as strong case-study evidence, not a measured effect size.
- The single most transferable pattern is cheap logic tests for most of the code (70% actor tests), plus a few slow end-to-end "golden path" tests (5%). This is the "testing pyramid" applied to games.
- Rare's lesson against testing a prototype means testing should follow the point where a feature's design settles, not come before it.

### Gaps
- Could not get the content of Jessica Baker's Unreal Fest Europe 2019 talk, "Automated Testing at Scale in Sea of Thieves". The event page returned 403, and no transcript or slides were found. The video exists at [YouTube](https://www.youtube.com/watch?v=KmaGxprTUfI). Any numbers specific to that talk (infrastructure scale, run counts per day) are unverified.
- There is no published figure for how much engineering time Rare spent on tests, and no direct cost-benefit calculation.

---

## 2. Factorio / Wube (Friday Facts)

### Takeaway
Wube is a small studio. It started a real test framework in late 2014 (FFF #60/#62), mainly to make deterministic multiplayer safe. It runs the tests around the clock after each commit on a build server (FFF #186, 2017), added graphical GUI tests after a bad release (FFF #288, 2019), and in 2021 adopted the rule that "any discovered bug is first covered by a test before it gets actually fixed" (FFF #366). Their determinism tooling compares a checksum (CRC) of the whole map every tick between a run and its replay (FFF #47). No Friday Facts post found gives a total test count.

### Cited Findings
- **FFF #47 (15 Aug 2014), determinism and desyncs:** in a special mode "the game runs … [and] makes a CRC from the whole map every tick". It also saves the map "with some useful human readable tags to a new file every tick", then replays the game doing the same CRC checks. When the checksums diverge, they binary-diff the paired saves at "the first tick of desynchronization", where "the difference is usually very small - typically just a value of one variable." This mode slows the game to "units of FPS". At the time it worked for desyncs they could reproduce locally, but not yet for player-reported multiplayer desyncs. — [P] [Factorio FFF #47, 2014](https://factorio.com/blog/post/fff-47)
- **FFF #60 (14 Nov 2014), "Tests all around":** the earlier test suite was "just ridiculous (meaning not doing much)". The new framework has three levels:
  - Unit tests with mocked objects, "really fast to run … they don't load any graphics nor any prototypes". Examples are multiplayer synchronisation and floating-point consistency across CPU architectures.
  - Integration tests that create "a small map, places couple of objects on the map, runs updates and then verifies that expected conditions are met", including CRC checks against presaved values to catch inconsistencies between platforms.
  - Emerging black-box tests that drive the Factorio binary from outside, for multiplayer edge cases and the GUI.
  — [P] [Factorio FFF #60, 2014](https://factorio.com/blog/post/fff-60)
- **FFF #62 (28 Nov 2014):**
  - Test counts were "slowly rising" and coverage was "still pretty small". They covered "the most tricky situations and the most complicated parts of the code first".
  - The tests cover multiplayer, the campaign, replay integrity and desyncs across configurations. They "helped to find lot of problems already", and "without the automated tests, the stable multiplayer release date would be delayed a lot". 8 desync bugs had been fixed by 0.11.4.
  - They were also building a build server to automate daily test releases and packaging.
  — [P] [Factorio FFF #62, 2014](https://factorio.com/blog/post/fff-62)
- Wube's build server runs the automated test suites on all systems and configurations, and a release needs a 100% pass. — [P, via search snippet of FFF #62] [Factorio FFF #62](https://cf-www.factorio.com/blog/post/fff-62). This was not re-verified in the full fetch, so treat it as likely but not confirmed.
- **FFF #186 (14 Apr 2017):**
  - Over 2 years and 4 major versions "we've added quite significantly to our suite of tests".
  - The server is "constantly running all these tests 24/7". On a failure "it sends out a sternly worded email to the developers who made the latest commits".
  - "Sometimes surprising how some innocent change can break some wholly unrelated tests, but it certainly helps us catch these issues before they make it out the door."
  — [P] [Factorio FFF #186, 2017](https://factorio.com/blog/post/fff-186)
- **FFF #288 (29 Mar 2019):** "We had a rough release earlier this week related to some GUI logic not working correctly." That release prompted Rseding to make the test system run automatic graphics/GUI tests, with many test windows running in parallel in a grid. — [P] [Factorio FFF #288, 2019](https://factorio.com/blog/post/fff-288)
- **FFF #366 (18 Jun 2021), "The only way to go fast is to go well!":**
  - When QA lead Boskid joined, the policy became "any discovered bug is first covered by a test before it gets actually fixed". The post credits this with fewer regressions and more confidence at release.
  - Kovarex (the studio founder) adopted test-driven development: "constant fast switching between extending the tests and making them pass continuously."
  - GUI tests simulate clicks, with "a mode in which the testing environment is created with GUI (even when tests are run without graphics)."
  - They prefer tests that cut through several layers over strict unit isolation.
  - A custom test-dependency system runs the simplest tests first, so developers debug the most basic failure first.
  - Coverage is measured with OpenCppCoverage to find untested or dead code.
  - The post gives no test counts.
  — [P] [Factorio FFF #366, 2021](https://factorio.com/blog/post/fff-366)

### Inferences
- Factorio and Rare disagree on test-first. Factorio's founder moved to TDD and to test-before-fix. Rare "rarely" wrote tests first, but did require a test with every change. Both agree that a regression test must exist once a bug is known.
- Wube built its testing around determinism: CRC checks, replays and comparing saves. Deterministic game logic makes "replay a scenario and compare the end state" tests cheap and exact. A deterministic simulation with timestamps, like a tycoon game's economy, is the same kind of system.

### Gaps
- No Friday Facts post found states the size of Wube's test suite or how long it takes to run. If a number circulates elsewhere, it was not verified here.
- Wube's team size during each phase is not stated in the posts that were fetched.

---

## 3. Other studios with sourced detail (Riot, Ubisoft, EA SEED, King, Croteam, others)

### Takeaway
The studios with real numbers are Riot (2016): about 100,000 test cases a day, about 5,500 per build in about 18 minutes, and automation-found bugs fixed 8x faster. Ubisoft La Forge's CLEVER (2018) reached 79% precision and 65% recall on 12 systems. Its "70% of costs" figure is a Ubisoft press claim with no published method. EA SEED (2021–2023) reports 601 features and about 0.5M manual test hours on Battlefield V. King (2018) cut level-difficulty estimation from 7 days of human playtesting to under 1 minute. Croteam (2015) had a bot that plays the whole game in 20 minutes. No sourced detail was found for Supercell, Larian, Insomniac or Valve. For Bungie, only a GDC roundtable mention was found, with no detail.

### Cited Findings
**Riot Games, League of Legends (Feb 2016, Jim "Anodoin" Merrill, tech captain of the Build Verification System team)**
- "Well over 100 code and content changes" were checked in every day, with a patch every 2 weeks. The Build Verification System (BVS) ran on CI and reported "within about an hour of check-in". — [P] [Riot Games, "Automated Testing for League of Legends", 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)
- Scale: "approximately 100,000 test cases a day", and "~5500 test cases in approximately 18 minutes for every new build". Results are kept for about 6 months. — [P] [Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)
- Test types: functional tests in Python that talk to the game client and server over RPC endpoints. They are organised into test sets, tests and test cases. Suites include BVSBlocker (smoke tests), BVSCore (champion abilities) and LoadChampsAndSkins. — [P] [Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)
- Results: bugs found by automation were resolved "eight times faster than the average bug". The BVS caught "50 percent of all critical or blocker level bugs". The rest were found by internal QA or on the PBE public test server. — [P] [Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)
- What did not work: early tests used fixed sleeps, which made "fragile tests" whose timing depended on the hardware. The fix: "All waits in the standard library are conditional waits." New tests "must demonstrate stability for at least one week before being promoted" into the blocking suites. — [P] [Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)

**Ubisoft La Forge: Commit Assistant / CLEVER (2018)**
- The research paper is CLEVER: "Combining Code Metrics with Clone Detection for Just-In-Time Fault Prevention and Resolution in Large Industrial Projects" by Mathieu Nayrolles and Abdelwahab Hamou-Lhadj (Ubisoft La Forge and Concordia), presented at MSR 2018.
  - It works in two phases to intercept risky commits before they reach the central repository.
  - On 12 Ubisoft systems: **79% precision, 65% recall**, better than the Commit-guru baseline.
  - It proposed useful fixes in **66.7%** of cases.
  — [P] [Ubisoft La Forge news page for the CLEVER paper, Mar 2018](https://www.ubisoft.com/en-us/studio/laforge/news/69mh5FECbj12vBfL4HGC5C/clever-combining-code-metrics-with-clone-detection-for-justintime-fault-prevention-and-resolution-in-large-industrial-projects); [paper PDF](https://montreal.ubisoft.com/wp-content/uploads/2018/05/ICSE-CE-MSR-165.pdf). The figures come from the search-result summary of these pages; the PDF itself was not opened.
- "Commit Assistant" was the product name announced at the Ubisoft Developer Conference in Montreal in March 2018. It was trained on about 10 years of Ubisoft code and its bug fixes, and flags code similar to code that was later fixed. — [S] [MIT Technology Review, 5 Mar 2018](https://www.technologyreview.com/2018/03/05/144928/ai-can-help-spot-coding-mistakes-before-they-happen/), which cites Wired UK as its source.
- **The "70%" claim:** MIT Technology Review writes "Finding and fixing bugs … Ubisoft says it soaks up 70 percent of development budget for a game." The claim comes from Ubisoft itself (Yves Jacquier, head of La Forge, speaking to Wired UK in March 2018). Other outlets soften it to "as much as 70 percent of costs". No study or method behind the number was found. — [S] [MIT Technology Review 2018](https://www.technologyreview.com/2018/03/05/144928/ai-can-help-spot-coding-mistakes-before-they-happen/); [S] [Push Square, Mar 2018](https://www.pushsquare.com/news/2018/03/ubisoft_is_breaking_ground_with_ai_that_helps_game_developers_fix_bugs)
- The trade press reported that Commit Assistant catches "6 out of 10 bugs" with about "30% false alarm" (and a 20% programmer time saving). — [S] [Push Square 2018](https://www.pushsquare.com/news/2018/03/ubisoft_is_breaking_ground_with_ai_that_helps_game_developers_fix_bugs); [S] [etcentric 2018](https://www.etcentric.org/ubisofts-new-ai-assistant-helps-catch-bugs-in-video-games/). These are press-conference figures, not the peer-reviewed numbers. Note that 60% detection is close to the paper's 65% recall.

**Ubisoft Reflections: The Division "Client Bots" (GDC 2019)**
- AI-controlled players use the normal player input to:
  - play missions automatically and generate reports,
  - act as "follow bots" so one tester or designer can test multiplayer missions alone,
  - wander the streets to gather performance data,
  - help reproduce bugs.
- The talk was by Jose Paredes and Pete Jones. — [P/S] [GDC Vault talk page, 2019](https://gdcvault.com/play/1026382/Automated-Testing-Using-AI-Controlled); [80.lv preview, 2019](https://80.lv/articles/gdc-using-ai-controlled-players-to-test-the-division). The previews contain no numbers.

**EA SEED: ML playtesting agents (2021–2023)**
- Battlefield V had **601 features** to test, about **0.5M hours** of manual testing, roughly **300 work-years**. — [P] [EA SEED, "SEED Applies Machine Learning Research to the Growing Demands of AAA Game Testing" (c. 2023)](https://www.ea.com/seed/news/seed-ml-research-aaa-game-testing)
- Scripted test bots "require manual recoding when features change". This is the motivation for reinforcement-learning (RL) and imitation-learning agents. RL agents were deployed alongside the existing scripted-bot test system in Battlefield 2042 and Dead Space (2023), and the paper documents the deployment problems. — [P] [EA SEED page](https://www.ea.com/seed/news/seed-ml-research-aaa-game-testing); paper: [Gillberg et al., "Technical Challenges of Deploying RL Agents for Game Testing in AAA Games", arXiv 2023](https://arxiv.org/abs/2307.11105v1)
- Imitation learning trained in **20 minutes, against 5 hours** for RL, and designers need no "deep machine learning knowledge". Curiosity-driven agents (CCPT) find "glitches and oversights that other methods miss". — [P] [EA SEED page](https://www.ea.com/seed/news/seed-ml-research-aaa-game-testing); see also [Gordillo et al., "Improving Playtesting Coverage via Curiosity Driven RL Agents", arXiv 2021](https://arxiv.org/pdf/2103.13798)

**King: Candy Crush (2018)**
- A convolutional neural network (CNN) was trained on player data to predict the most "human" move. It predicts level difficulty better than Monte Carlo Tree Search (MCTS) in a fraction of the compute time. It estimates a new level's difficulty in **under a minute, against 7 days** of human playtesting per 15-level episode. It was used for **more than a year on more than 1,000 new Candy Crush Saga levels**. — [P] [Gudmundsson et al. (King), "Human-Like Playtesting with Deep Learning", IEEE CIG 2018 (PDF)](https://www.Gwern.net/doc/reinforcement-learning/imitation-learning/2018-gudmundsson.pdf)

**Croteam: The Talos Principle (2014–2015)**
- Croteam needed to test every day because "minor design changes could break carefully planned puzzle concepts very easily," but lacked the people to do it by hand. They built "The Bot".
  - Hand-placed navigation and behaviour markers ("pick up a hexahedron…") plus pathfinding let it solve every puzzle and report the ones it could not solve.
  - A human playthrough takes 4–5 h. The bot, with rendering turned off ("time-lapse"), plays the whole game in **20 minutes**.
  - Several bots ran in parallel after each level-designer change.
  - In total it played **80,000 human-hours** equivalent across the base game and the Road to Gehenna expansion.
  - "There will always be a place for standard human testers."
  — [P] [Damjan Mravunac (Croteam), PlayStation Blog, 25 Sep 2015](https://blog.playstation.com/archive/2015/09/25/how-croteam-built-a-bot-to-beat-its-ps4-puzzler-the-talos-principle/)

**Others (thin evidence)**
- Activision gave a GDC talk on its proprietary CI system for Call of Duty ("Automated Testing and Profiling for 'Call of Duty'"). No numbers were retrieved. — [GDC Vault](https://www.gdcvault.com/play/1025064/Automated-Testing-and-Profiling-for)
- Bungie: a Staff SDET (software development engineer in test) took part in the GDC 2022 test-automation roundtables (out-of-process automation, visual testing). There are no Bungie numbers. — [S] [LinkedIn, GDC 2022 roundtables takeaways](https://www.linkedin.com/pulse/gdc-2022-takeaways-test-automation-roundtables-michael-johnson)
- Not relied on: modl.ai's "What is Modern Game Testing?" is a vendor page ([M] [modl.ai](https://modl.ai/what-is-modern-game-testing)). It describes the Masella talk as having "the most astounding bug count graph in GDC history". The primary slide deck above supersedes it.

### Inferences
- In every case the measured wins come from repetitive, deterministic checks running far more often than people could run them: Riot's per-build smoke tests, Croteam's nightly playthrough, King's difficulty estimation. ML agents (EA, King) are a big-studio investment aimed at content volume. A solo developer does not need them.
- Riot's "8x faster to fix" mostly reflects how quickly a bug is caught after the change that caused it. That matches Rare's skeleton-AI example: a bug caught minutes after the change is easy to pin on that change.
- Treat the "70% of development costs" figure as a quote from Ubisoft's press event, not a measured industry statistic.

### Gaps
- No sourced, detailed public accounts of automated-testing practice were found for **Supercell, Larian, Insomniac or Valve**. Bungie appears only as a roundtable participant. These studios were left out rather than filled in from memory.
- The Division bots talk: run frequency and results (bugs found, time saved) were not retrievable without the GDC Vault video.
- Riot's figures are from 2016, and no more recent Riot testing metrics were found.
- No sourced numbers were found for how often Commit Assistant was actually used in production after 2018.

---

## 4. Practices that recur across studios, and what did not work

### Takeaway
The pattern that repeats across studios: many fast logic tests and a few slow end-to-end tests. Tests run automatically after every change, or at least every 20–60 minutes, with someone notified when they fail. Each bug gets a regression test. Deterministic replays or scripted bots play through the whole game. A human still judges feel, visuals and exploration. The recurring failures are flaky or timing-based tests, slow end-to-end tests clogging the pipeline, tests tied to implementation details, and testing before a design has settled.

### Cited Findings
**What recurs**
- **Fast feedback after each change.**
  - Rare ran all tests at least every 20 minutes and gated each commit with a pre-commit run ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
  - Riot reported within about 1 hour of check-in and ran about 5,500 cases per build ([Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)).
  - Factorio runs tests "24/7" and emails whoever made the latest commits when one fails ([FFF #186, 2017](https://factorio.com/blog/post/fff-186)).
- **Regression test for every bug or change.**
  - Factorio: "any discovered bug is first covered by a test before it gets actually fixed" ([FFF #366, 2021](https://factorio.com/blog/post/fff-366)).
  - Rare: "every change must be covered by some kind of automated testing if it makes sense", written by whoever made the change ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
- **Many cheap tests, few expensive ones.**
  - Rare: about 70% actor tests and 5% integration tests. Unit tests take about 0.1 s and integration tests about 20 s ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
  - Factorio: fast unit tests "don't load any graphics nor any prototypes", alongside small-map integration tests ([FFF #60, 2014](https://factorio.com/blog/post/fff-60)).
- **Small scenario tests: set up a tiny world, run it, check the result.**
  - Rare: test maps containing just a player, a platform and a wheel ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
  - Factorio: "a small map, places couple of objects… runs updates and then verifies" ([FFF #60](https://factorio.com/blog/post/fff-60)).
- **Determinism, replay and checksum checks.**
  - Factorio checks a CRC every tick and compares a run against its replay ([FFF #47, 2014](https://factorio.com/blog/post/fff-47)).
  - Factorio also checks integration-test CRCs against presaved values to catch differences between platforms ([FFF #60](https://factorio.com/blog/post/fff-60)).
- **Full-game playthrough bots and smoke tests.**
  - Croteam's bot ran in 20 minutes headless ([PlayStation Blog 2015](https://blog.playstation.com/archive/2015/09/25/how-croteam-built-a-bot-to-beat-its-ps4-puzzler-the-talos-principle/)).
  - The Division used client bots for mission playthroughs ([GDC Vault 2019](https://gdcvault.com/play/1026382/Automated-Testing-Using-AI-Controlled)).
  - Riot's BVSBlocker smoke suite ([Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)).
  - Rare's bootflow tests ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
- **Data and asset validation.** Rare's asset-audit checks cover designer and artist changes so they need no hand-written tests, and they make up most of the "over 100 thousand" total ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
- **Screenshot comparison and performance-trend tests**, used sparingly because they are slow ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)). Factorio added graphical GUI tests after a broken GUI release ([FFF #288, 2019](https://factorio.com/blog/post/fff-288)).
- **Coverage measurement as a guide, not a target.**
  - Rare: 60% decision and 70% function coverage, and "perfect testing coverage … unachievable" ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
  - Factorio uses OpenCppCoverage to find untested or dead code ([FFF #366](https://factorio.com/blog/post/fff-366)).
- **Humans still needed.**
  - Rare: humans are better at visuals, audio, exploration and feel ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
  - Croteam: "there will always be a place for standard human testers" ([PlayStation Blog 2015](https://blog.playstation.com/archive/2015/09/25/how-croteam-built-a-bot-to-beat-its-ps4-puzzler-the-talos-principle/)).

**What did not work, and the fixes**
- **Timing-based waits made tests flaky.**
  - Riot: fixed sleeps made "fragile tests". Fix: only conditional waits ([Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)).
  - Rare: fixed frame delays broke after refactors. Fix: poll each frame with a long timeout ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
- **Flaky tests block the whole team.**
  - Rare: auto-retry once, keep a weekly list of the flakiest tests, quarantine repeat offenders, and auto-delete them if nobody fixes them ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
  - Riot: a test must be stable for 1 week before it is promoted to a blocking suite ([Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends)).
- **Slow end-to-end tests overloaded CI.** Rare's pre-commit runs went from under 1 h to waits of "half a day or more". Fix: move logic checks down to actor tests, golden-path-only integration tests, and combined tests ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
- **Tests tied to implementation details** fail when correct code is refactored (false failures, which Rare calls "false negatives"). "Test for behaviour", not implementation ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
- **Testing during prototyping is a hindrance.** Rare kept a prototype branch with no tests ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)).
- **Scripted bots break when features change**, which is why EA invested in learning agents ([EA SEED c. 2023](https://www.ea.com/seed/news/seed-ml-research-aaa-game-testing)).
- **Too few GUI tests caused a rough release** at Factorio, which led to automated graphics/GUI tests ([FFF #288, 2019](https://factorio.com/blog/post/fff-288)). Rare used screenshot tests sparingly because they are slow and partly non-deterministic, with manual checks every 1–2 weeks ([Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)). The two studios weigh UI testing differently: Factorio added more after being burned, and Rare kept it minimal.

### Inferences
- A brittle test that is never fixed has negative value. Rare's view that a test which keeps failing is "worse than having no test at all" is the most important maintenance lesson for anyone with limited time.
- Neither primary source supports the idea that heavy UI testing is a good investment. Both automate GUI checks only for flows that actually broke, or keep them few.

### Gaps
- No studio published a controlled comparison of the cost of test maintenance against bugs prevented. Every cost claim is qualitative ("same speed long-term", "less crunch").

---

## 5. How small teams and solo developers scale this down (relevance to a solo Godot 4 tycoon/sim project)

### Takeaway
The cheapest high-value practices are all things a solo developer can do with one headless test script:
- fast tests of the simulation rules, no rendering needed (Factorio unit tests, Rare actor tests);
- a regression test before each bug fix (Factorio);
- a deterministic "run N simulated hours, compare the result" scenario check (Factorio CRC and replays);
- a headless fast-forward smoke run that plays the main loop (Croteam's 20-minute bot);
- validation of the data files (Rare's asset audits);
- run everything after every change, and fix or delete flaky tests instead of tolerating them.

Machine-learning agents, screenshot farms and build farms do not transfer.

### Cited Findings
- Small-team evidence:
  - Croteam built a bot precisely because it "couldn't afford the manpower" for daily manual testing of a long game. Hand-placed markers plus pathfinding were enough, and turning off rendering gave a full playthrough in 20 minutes. — [P] [PlayStation Blog 2015](https://blog.playstation.com/archive/2015/09/25/how-croteam-built-a-bot-to-beat-its-ps4-puzzler-the-talos-principle/)
  - Factorio started small, testing "the most tricky situations and the most complicated parts of the code first", and that alone "helped to find lot of problems already". — [P] [FFF #62, 2014](https://factorio.com/blog/post/fff-62)
- Fast simulation tests skip graphics: Factorio's unit tests are fast because they "don't load any graphics nor any prototypes". Its GUI tests can even run "without graphics". — [P] [FFF #60, 2014](https://factorio.com/blog/post/fff-60); [FFF #366, 2021](https://factorio.com/blog/post/fff-366)
- Start small: "adding testing to just one part of your game project to begin with, may be easier." Avoid tests that need heavy maintenance, and focus on bug-prone areas. — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Adopt first, scale later: "biasing first for adoption of test frameworks, and then shifting focus to scaling them". Use a "middle ground" that lets tests call game code without first restructuring it. — [S/P] [Golding, GDC 2021 summary](https://www.linkedin.com/pulse/gdc-2021-lessons-learned-adapting-sea-thieves-testing-henry-golding)
- Don't test the fun-finding phase: Rare used a separate prototype branch without tests and added tests once behaviour was settled ("make a change, see if it works and then create tests to pin down its behaviour"). — [P] [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)
- Test first, at least for bugs: Factorio's founder found TDD meant "constant fast switching between extending the tests and making them pass continuously". The studio requires a failing test before any bug fix. — [P] [FFF #366, 2021](https://factorio.com/blog/post/fff-366)
- Determinism makes cheap exact tests possible: CRC or state comparison between a run and its replay finds the first diverging tick, "typically just a value of one variable". — [P] [FFF #47, 2014](https://factorio.com/blog/post/fff-47)
- Avoid fixed sleeps or delays in tests; wait on conditions instead. — [P] [Riot 2016](https://www.riotgames.com/en/news/automated-testing-league-legends); [Masella 2019](https://media.gdcvault.com/gdc2019/presentations/Masella_Robert_AutomatedTestingOf.pdf)

### Inferences
These are mappings from the sourced practices to a one-person Godot project. They are not separately sourced.
- **Practices that transfer directly:**
  - (a) Keep pure game-rule logic testable without scenes. This is the equivalent of Rare's actor tests and Factorio's unit tests, and the project's `scripts/sim/` split already does it.
  - (b) Add a test reproducing each bug before fixing it. With an AI coding assistant, "write the failing test first, then fix" is easy to ask for.
  - (c) A few "golden path" scenario tests, for example: start a new game, build farm → mill → bakery, fast-forward X simulated hours via the clock service, assert stock and money. Use smaller logic tests for edge cases such as a clock moved backwards, an empty warehouse or a full warehouse.
  - (d) A data-file validator, like Rare's asset audits. It checks every recipe references existing resources and buildings, every price and timer is positive, and so on, so editing JSON needs no new hand-written test.
  - (e) A save round-trip and migration test: save, load, compare state. This is the equivalent of Factorio's replay comparison, applied to versioned saves.
  - (f) A headless "fast-forward bot" smoke run of a long simulated session that asserts no errors and no impossible values such as negative stock. This is the Croteam idea at minimal cost.
- **Frequency for a solo developer:** run the headless suite after every change, or have the AI assistant run it before each commit. That is the equivalent of Rare's pre-commit gate and Factorio's post-commit runs. A hosted CI service is optional for one person, because the "team blocked by a red build" problem Rare solved does not exist.
- **Do not bother with:** ML playtesting agents (EA, King), screenshot-diff farms, performance-trend dashboards, or automated retry and quarantine machinery. For one person, the lesson behind quarantine is simply "fix or delete a flaky test immediately".
- **Main risk for a beginner:** tests tied to implementation details, such as exact frame counts, node paths or UI layout. These break with every refactor and become a maintenance burden (Rare, Riot). Asking for tests of rules and outcomes, not of scene structure, avoids most of this.

### Gaps
- No sourced case study was found of a solo or very small indie (1–3 people) publishing test counts or measured bug reductions. The scaled-down advice above is inferred from Rare, Factorio and Croteam, not observed in a one-person studio.
- No Godot-specific studio testing case study was searched or found in this pass. Godot tooling (GUT, GdUnit4, headless `-s` scripts) is outside this note's scope.
