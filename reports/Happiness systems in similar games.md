# Happiness systems in similar games

Research done 2026-10-08. The question: how do other city builders and colony games handle happiness, and what could we borrow (with a tweak) for our island village?

Our system today (plan.md §5.6, §5.23) already follows Tropico. There are seven needs (Food, Jobs, Housing, Health, Fun, Faith, Safety), each wealth class weighs them its own way, and expectations rise as the village grows. Happiness = 50% + needs met − expected. No food caps happiness at 40%. Happiness changes **births, migrant workers and people leaving**, and nothing else.

---

## 1. What each game does

| Game | How happiness is built | What happiness *does* | The interesting idea |
|---|---|---|---|
| **Anno 1800** | Needs are split in two. **Basic needs** add residents to a house (more people = more workers and taxes). **Luxury needs** only add happiness. Happiness is a point score made of Luxury ±20, Working conditions ±20, Pollution +5/−20, News ±5, Peace ±5 | 5 named levels: Angry (< −50), Unhappy, Content (−20…+19), Happy (+20…+49), Euphoric (> +50). Happy: more taxes, fewer riots, and the town can **hold festivals**. Angry: strikes stop production | You can grow without happy people (a "sweatshop" island works), but happiness pays extra. **Festivals** last ~30 min and give island-wide boosts (Beer Festival +50% beer, Harvest Festival +10% taxes). **Working conditions**: overtime gives more output but −happiness; shorter shifts give the opposite |
| **Anno 117: Pax Romana** (2025) | Each class has **need categories** (Food, Fashion, Household, Public Service). Any item in a category counts toward it. Each met need adds to population, income, happiness, health or fire safety | Low happiness: unrest, slower work, less tax, people abandon homes | **Rising expectations**: raising your city's status *lowers* happiness, health and fire safety, so growth costs you something |
| **Against the Storm** | "Resolve" per species = base + housing (+3) + complex food + clothing + services (+8 to +10, the biggest) − hostility/storm | **At 0, one villager of that species leaves.** Above a threshold, the species earns **Reputation** (= you win) | **Decadence**: each reputation point raises the bar for the next, so you always need more. Players save one-off boosts for a final "**resolve party**" |
| **Timberborn** | Well-being = points from every need met (food types, drinks, fun, decoration, spirituality…) | **Rewards only, in steps**: every well-being milestone gives +20% work speed (up to +260%), plus faster growth, movement and longer life | Happiness is purely a bonus. There's no punishment, so players chase it because it pays |
| **Civilization VI** | Each city needs "amenities" from luxury goods and entertainment. The first 2 citizens need none, then 1 more for every 2 citizens | Ecstatic +20% everything, Happy +10%, Content 0, Displeased −10% and −15% growth, Unrest −30% and rebels | Clear named steps, with a **% bonus to everything** at the top |
| **Manor Lords** | Approval from food variety, clothing, fuel, church level, taxes | **> 50%: 1 new family a month, > 75%: 2.** Low approval: families leave | Very simple thresholds that feed only migration. Close to what we do now |
| **Foundation** | **Essential needs** (must have or people get angry and leave) and **additional needs** (bonus). An additional need becomes **essential once people have had it**. Needs grow with rank (serf → commoner → citizen) | Immigration waves depend on happiness *and* unemployment: no newcomers with ~10 jobless | "Once you give it, they expect it." Anger from a missed need **fades gradually** after the supply comes back |
| **RimWorld** | Each colonist's mood = base + "thoughts". A thought is a +/− with **its own duration** ("ate a fine meal +5 for 1 day", "saw a corpse −4 for 2 days") | Low mood: mental breaks at 35/20/5%. High mood: inspirations (bonus work) | **Expectations follow colony wealth**: a poor colony gets +30 mood for free, a rich one +0. And **temporary thoughts with an end time** |
| **Oxygen Not Included** | Morale from food quality, decor, rooms, recreation | Each skill a colonist learns raises the morale they need | Expectations grow with the colonist's **level**: better workers want better lives |
| **Cities: Skylines 2** | Happiness = well-being (power, water, garbage, pollution, crime, services, a home that fits the family) + health (clinic nearby) | Affects whether people work, move in or move out | Fully per-citizen. Too heavy for phones |
| **Frostpunk** | Two bars: **Hope** and **Discontent**. Laws, events and **promises** to the people move them | Too low or too high for too long = you're overthrown, game over | **Promises**: "I'll build a clinic within 2 days." Keeping one gives hope, breaking it gives discontent |
| **Farthest Frontier** | 11 needs: food, health, shelter, desirability, shoes, clothes, family, beer, entertainment, luxuries, spirituality | Unhappy: fewer immigrants, lower productivity and fertility | Houses only upgrade when their **needs and surroundings** are good enough |
| **Caesar III / Pharaoh** | No happiness bar. Each **house evolves** when goods and services reach it and **devolves** when they stop | Better houses hold more people and pay more tax | Happiness you can *see*: the houses themselves change |
| **Kingdoms and Castles** | Food variety, church, tavern, neighbours, **taxes** | Happy villages tolerate higher taxes | Happiness is a "budget" you can spend on taxes |
| **Banished** | Chapel, tavern, cemetery, a dead family member | Unhappy people work less | **Grief fades over years**: a temporary penalty |
| **SimCity BuildIt** (mobile) | Service coverage (fire, police, health) plus "specialisation" buildings (parks, worship, entertainment) | Happy: more taxes, bigger population boost. Unhappy: people leave | Mobile-friendly: shows a **"+population" bar while you place** a park |
| **Tropico 6** (ours is based on this) | 8–10 needs, per-citizen, plus factions, liberty and respect | Votes in elections, immigration, crime | Edicts like "free food" before an election |

---

## 2. What almost every game does that we don't

**A happy village pays the player back.** In Anno, Civ, Timberborn, Against the Storm, SimCity BuildIt and Kingdoms and Castles, high happiness gives more money, more production or a way to win. In our game:

- Above 50% the only reward is births ×1.5 (at 80%+). Migrant workers come at the same speed whether happiness is 21% or 100%.
- Happiness never touches money or production (plan.md: "Nobody works slower").

So once the village is at "good enough", the player has no reason to build a Chapel or a Tavern. Most of the ideas below fix that.

The second common thing we lack is **memory and events**: thoughts with an end time in RimWorld, festivals in Anno, promises in Frostpunk, fading anger in Foundation and Banished. We turned down a "slow mood" before because it makes time away hard to calculate. But a modifier with an **end timestamp** is just another moment the settle already splits on (like a building finishing), so it fits our one-calculation offline rule.

---

## 3. Ideas for our game, best fit first

Each idea keeps our rules: numbers in `data/*.json`, game rules in `scripts/sim/`, offline time stays one calculation, nothing per-person.

### A. Named moods with a reward at the top *(from Anno 1800, Civ VI, Timberborn)*: **recommended first**
Give the bands names and make the top ones pay:

| Shown % | Mood | New reward |
|---|---|---|
| 85–100 | Thrilled | +10% (placeholder) |
| 70–84 | Happy | +5% |
| 50–69 | Content | — |
| 21–49 | Unhappy | — (people already leave) |
| 0–20 | Angry | — |

**The tweak (what the bonus is):** the simplest choice that stays offline-safe is a bonus to **Retailer sale prices** ("happy shoppers spend more"). It's worked out at the moment of sale, so nothing else changes. The other choice is an **output bonus fixed when a batch starts**, the same way our long-batch bonus works. That's also safe, because the bonus is locked in at the start. A speed bonus *during* a batch (like Timberborn) would mean recalculating `finishes_at` each time happiness moves, so I'd avoid it.
*Size:* small. One more column in `happiness.growth_speeds`, one rule, a mood name on the HUD.

### B. Timed "memories" with an end time *(from RimWorld thoughts, Foundation and Banished fading anger)*
Store a short list in the state: `{id, amount, ends_at}`. Happiness = today's formula + active memories. Examples:
- A store's shelf **sells out**: "Empty shelves −8% for 6 h". People remember a shortage even after you restock (Foundation's "reassure them first").
- **A service building opens**: "New clinic +5% for 12 h" (a small celebration).
- **People left the island**: "Neighbours left −3% for 6 h".

Offline-safe because each `ends_at` is a known moment the settle can split on. *Size:* medium. A save change (bump `SAVE_VERSION` plus a migration that adds an empty list), and Statistics → People lists the memories.

### C. Festivals *(from Anno 1800 festivals, the Against the Storm "resolve party", Tropico edicts)*
A button at City Hall: **"Hold a festival"**. It costs cash plus goods from the warehouse (e.g. 40 bread), and can only be held at Content or better. It adds a memory (idea B): "+15% for 12 h". After that there's a cooldown (e.g. 3 days).
*Why it's good for us:* it gives the player something to *do* with happiness, a use for goods, and a way to push past a band edge before a growth spurt. It's also a classic mobile "come back and tap" moment. Needs B first.

### D. Essential vs extra needs, for every need *(from the Anno 1800 split and Foundation)*
We already have "no food → at most 40%". Make `max_happiness_when_unmet` work for **any** need in `game_config.json`, not just food. Then the data decides which needs are essential. For example, Housing could cap the Rich at 50% while they live in Public Housing.
*Size:* small. Mostly the same code as the food cap, plus a test.

### E. Working conditions: "Overtime" *(from Anno 1800)*
Add a fourth option to the Staffing choice: **Overtime**, with +20% speed and that building's workers counting as a worse job (lower Jobs quality, like a wage-bonus step down). It's the reverse of the wage bonus: money now, happiness later. It fits the Staffing and wage-bonus screens we already have.
*Size:* medium. It touches production speed, so the offline tests matter.

### F. Goods needs for the richer classes *(from Anno 117 need categories, Farthest Frontier, Foundation)*
A need called **"Comforts"** that only Well off, Rich and Filthy rich weigh. It's met by how many *different* non-food goods are selling (clothes, furniture, drinks), the same way Food counts different foods. This is our planned "luxury needs for the rich" idea in Anno 117's simpler form: any item in the category counts.
*When:* after production chains Wave 2 adds non-food goods. No point before.

### G. Expectations that also follow wealth *(from RimWorld, ONI, Anno 117, Against the Storm decadence)*
Right now, expectations rise with **population** only. A tweak: also raise them a little with the share of Rich and Filthy rich, so a richer village wants more. Low priority. The current rule works, and changing it means re-checking idle growth (see the memory note: settle an idle game for 3 days after any retune).

### H. Happiness earns XP *(from Against the Storm reputation)*
In Phase 1b, when XP exists: at Happy or better, the village gives a trickle of XP per hour (rate × time, so it's offline-safe). This ties happiness to unlocks. Park it until Phase 1b.

---

## 4. What not to copy

- **Per-citizen simulation** (Cities: Skylines 2, RimWorld, Patron, Tropico): too heavy for phones and breaks the one-calculation offline rule. Our class groups already give most of the feel.
- **Revolution / game over** (Frostpunk): too harsh for a game you leave running while away.
- **Service radius / coverage maps** (SimCity, Banished, Kingdoms and Castles): we already chose capacity-only. It's still a "later" idea in plan.md.
- **Resident taxes** (Kingdoms and Castles, Pocket City): the player is a company, not a mayor. Idea A's price bonus gives the same "happy = money" link.
- **Houses that evolve and devolve on their own** (Caesar, Pharaoh): lovely, but it changes our "player builds the house type" design.

---

## Sources
- Anno 1800: [Happiness wiki](https://anno1800.fandom.com/wiki/Happiness), [Population wiki](https://anno1800.fandom.com/wiki/Population?oldid=3313), [DevBlog: Happiness](https://www.anno-union.com/en/devblog-happiness/), [DevBlog: Working Conditions](https://www.anno-union.com/en/devblog-working-conditions), [SegmentNext happiness guide](https://segmentnext.com/2019/04/18/anno-1800-happiness-guide)
- Anno 117: [Population wiki](https://anno117.fandom.com/wiki/Population), [GameRant attributes guide](https://gamerant.com/anno-117-pax-romana-how-increase-attribute-happiness-health-fire-safety/), [Money and economy guide](https://intoindiegames.com/walkthroughs/anno-117-pax-romana-money-and-economy-guide/)
- Against the Storm: [Resolve (official wiki)](https://wiki.hoodedhorse.com/Against_the_Storm/Resolve), [Resolve Threshold](https://wiki.hoodedhorse.com/Against_the_Storm/Resolve_Threshold), [Species](https://against-the-storm.fandom.com/wiki/Species), [Benedict Jacka strategy guide](https://benedictjacka.co.uk/other-writing/against-the-storm-strategy-guide/), [Hostility, resolve and impatience](https://casualgameguides.com/walkthroughs/against-the-storm/manage-hostility-resolve-impatience)
- Timberborn: [Well-being](https://timberborn.wiki.gg/wiki/Well-being), [Work speed](https://timberborn.wiki.gg/wiki/Work_Speed)
- Civilization VI: [Amenity (Civ6)](https://civilization.fandom.com/wiki/Amenity_(Civ6))
- Manor Lords: [Approval (official wiki)](https://wiki.hoodedhorse.com/Manor_Lords/Special:MyLanguage/approval), [GameSpot approval guide](https://Gamespot.com/articles/manor-lords-increase-approval-population-guide/1100-6523010/)
- Foundation: [Needs](https://wiki.polymorph.games/foundation/Needs), [Immigration](https://wiki.polymorph.games/foundation/Immigration)
- RimWorld: [Mood](https://mail.rimworldwiki.com/wiki/Mood), [Expectations](https://rimworldwiki.com/wiki/Expectations), [Thoughts](https://rimworldwiki.com/wiki/Thoughts)
- Oxygen Not Included: [Morale](https://oxygennotincluded.wiki.gg/wiki/Morale)
- Cities: Skylines 2: [Citizen simulation (Paradox)](https://www.paradoxinteractive.com/games/cities-skylines-ii/features/citizen-simulation-lifepath)
- Frostpunk: [Wikipedia](https://en.wikipedia.org/wiki/Frostpunk)
- Farthest Frontier: [Happiness guide](https://www.farthestfrontier.com/guide/villagers/happiness/), [Spirituality](https://www.farthestfrontier.com/guide/villagers/spirituality/)
- Caesar III / Pharaoh: [Housing desirability](https://www.caesar3augustus.com/book/housingdesirability/start), [Pharaoh housing](https://strategywiki.org/wiki/Pharaoh/Housing)
- Kingdoms and Castles: [Steam discussion](https://steamcommunity.com/app/569480/discussions/0/1458455461487995179)
- Banished: [Chapel](https://banished.fandom.com/wiki/Chapel), [Cemetery](https://banished-wiki.com/wiki/Cemetery)
- SimCity BuildIt: [EA beginner guide](https://help.ea.com/en/articles/simcity/simcity-buildit/beginner-guide/)
- Tropico 6: [Steam discussion](https://steamcommunity.com/app/492720/discussions/0/1751276319485280606)
- Patron: [Overseer Games](https://www.overseer-games.com/patron)
