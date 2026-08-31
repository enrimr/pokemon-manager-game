extends RefCounted
## Inbox piece: the PEOPLE & MEDIA layer — messages from persons, not club ops.
##
##   mind:<fid>      rival manager mind-games before our fixtures, with brief
##                   reply choices that genuinely nudge squad morale
##   press:<fid>     media reaction pieces after notable results (upsets,
##                   streaks, cup progress) with REAL star ratings from the
##                   deterministic fixture replays (Season.fixture_detail)
##   mon:*           coach notes on individual squad members — delighted with
##                   development / unhappy at a lack of battles — with replies
##                   that mutate that mon's real morale value
##   pledge:*        follow-ups on promises the manager made (e.g. "you'll get
##                   battles") — kept or broken, with real morale consequences
##   roundup:<YYYY-MM>  monthly league round-up column with awards (Pokémon of
##                   the Month computed from real per-battle ratings)
##
## WRITING SYSTEM
##   * every tone/kind has a bank of 8-12 structurally different templates
##   * each generated message records which template ids it used ("tids"), so
##     the recently-used registry is persisted with the save itself; lines used
##     within RECENT_WINDOW days are excluded from selection
##   * rival manager quotes are conditioned on a per-manager PERSONA (verbal
##     tic, how they refer to their squad, their arena idiom, their sign-off),
##     and a career-wide verbatim guard re-rolls any quote that would exactly
##     match one already published — no two managers share word-for-word prose
##   * facts (form, table positions, morale) are SNAPSHOTTED into the message
##     payload at publication time — never recomputed at read time
##
## Everything is deterministic (career_seed + ids), duplicate-guarded by uid,
## generated only via the documented GameState.add_inbox_message API, and all
## extra keys stored on messages are JSON-safe so they persist in the save.

const PAPER := "The Indigo Gazette"
const JOURNALISTS := ["Marin Kessler", "Tobias Wren", "Ada Okafor", "Ren Kowalski",
	"Petra Lindqvist", "Hugo Beaumont"]

const C_GOOD := "57c979"
const C_BAD := "e06060"
const C_WARN := "e0b050"
const C_DIM := "8b91a8"
const C_ACC := "9d92ff"
const C_WHITE := "e8ebf5"

## Coach note cadence: one welfare check every N days from season start.
const NOTE_PERIOD := 12
## An unreplied welfare complaint goes stale after this many days.
const NOTE_WINDOW := 14
## A used line is excluded from re-selection for this many days.
const RECENT_WINDOW := 75
## Promised-battles pledge: appearances owed and days allowed.
const PLEDGE_TARGET := 3
const PLEDGE_DAYS := 28

var news: RefCounted   # news_gen.gd (money/display helpers, assistant names)
var _used_lines: Array = []   # [{tid, date}] rebuilt from the inbox each pass


func _init(news_gen: RefCounted) -> void:
	news = news_gen


# ==================================================================== personas
## Each rival manager gets a stable verbal identity derived from their name.
## Every quote template weaves in at least two persona slots, so two managers
## never phrase the same thought the same way.

const P_TICS := ["Look,", "Let me be clear:", "I'll say this once:", "Honestly,",
	"You can print this:", "It's very simple:", "I won't dress it up —",
	"Ask anyone in my dugout —", "Between us and the record:", "Here's the truth of it:"]
const P_CROWD := ["my squad", "my battlers", "this group", "my lads", "our roster",
	"the group I've built", "my trainers", "my front six", "my people",
	"the battlers I trust"]
const P_ARENA := ["on the field", "when the battles start", "on matchday",
	"between the lines", "once the first Poké Ball opens", "under the lights",
	"when it counts", "in the arena"]
const P_CLOSER := ["That's all I'll say.", "Take that however you like.",
	"We'll see on the day.", "The rest is noise.", "Book it.",
	"And I don't say that lightly.", "End of story.", "Nothing more to add.",
	"Quote me on that.", "The rest is for Saturday."]


func persona(mgr: String) -> Dictionary:
	return {
		"tic": I18n.t(P_TICS[absi((mgr + "|tic").hash()) % P_TICS.size()]),
		"crowd": I18n.t(P_CROWD[absi((mgr + "|crowd").hash()) % P_CROWD.size()]),
		"arena": I18n.t(P_ARENA[absi((mgr + "|arena").hash()) % P_ARENA.size()]),
		"closer": I18n.t(P_CLOSER[absi((mgr + "|closer").hash()) % P_CLOSER.size()]),
	}


# ==================================================================== line banks

## Rival mind-game quotes. Slots: {pc} {pcs} = player club name/short,
## {club} {clubs} = the speaker's own club, plus persona slots.
const MIND_QUOTES := {
	"dismissive": [
		"{tic} {pc} are a tidy side, but tidy doesn't beat us. {crowd} have trained all week like it's a final — it won't be one. {closer}",
		"I respect what {pc} are building. Building takes years. Winning is now — and {arena}, now belongs to {club}.",
		"People keep asking me about {pcs}. What is there to say? We are the bigger club, and {arena} everyone will see why. {closer}",
		"We scouted {pcs} for ninety minutes and stopped taking notes after twenty. {crowd} know what's coming. So does their manager.",
		"If we perform at even eighty percent, {pc} cannot live with us. {tic} that's not arrogance, it's arithmetic.",
		"My only job this week was keeping {crowd} focused, because nobody here is nervous about {pcs}. {closer}",
		"{pc}? A good story for the neutrals. Stories end — and this one ends quickly {arena}.",
		"You want a bold prediction? I don't do bold. I do obvious: {club} win, and {pcs} go home wondering what hit them.",
		"There are ties that keep a manager up at night. {tic} this is not one of them. {crowd} could handle it half-asleep — they won't need to.",
		"Every league has a gap between where clubs think they are and where they actually are. This weekend, {pcs} learn which side of that gap they live on. {closer}",
	],
	"wary": [
		"Everything favours {pc} — the budget, the depth, the expectation. {tic} that suits me fine. The pressure is all theirs; {crowd} travel with nothing to lose.",
		"{pcs} should win. The table says it, their wage bill says it. But 'should' is a dangerous word {arena}.",
		"I've watched more of {pc} this week than of my own family. Brilliant squad. But brilliance can be organised against, and {crowd} are organised. {closer}",
		"Nobody outside {club}'s walls gives us a chance against {pcs}. Good. The best afternoons of my career started exactly like that.",
		"If {pc} are half a percent off their level, we will be standing on their throat. {tic} they know it too.",
		"Ask their manager how relaxed they are about facing {club}. Watch their face before you write down the answer. {closer}",
		"We're not coming to admire {pcs}. {crowd} have a plan, and plans have beaten reputations {arena} plenty of times before.",
		"{pc} carry the expectation, and expectation is heavy. We carry nothing. Light teams run faster. {closer}",
		"Their board expects a win. Their fans expect a rout. All I expect is {crowd} making this the longest afternoon of {pcs}' season.",
		"David and Goliath is a tired line, so try this one: {club} don't need a miracle, just forty good minutes {arena}.",
	],
	"spiky": [
		"We've done our homework on {pcs}. There are holes in that lineup — {crowd} know exactly where. {closer}",
		"Two clubs at the same level, so it comes down to nerve. {tic} I know my dugout holds its nerve. I can't speak for theirs.",
		"{pcs} talk a good game in the press. Battles aren't won in the press — they're won {arena}. {closer}",
		"I hear {pc} fancy this one. Confidence is lovely. {crowd} prefer evidence, and we'll present ours {arena}.",
		"There is no gap between these squads on paper. There will be one by full time — and {club} will be on the right side of it.",
		"Everyone calls this one fifty-fifty. {tic} matches like that go to whoever wants it more, and I've watched {crowd} train this week.",
		"Their manager and I want the same three points, and only one of us leaves with them. I like my side of that argument. {closer}",
		"This fixture always has an edge, and I won't pretend otherwise. Edges suit {crowd}. They rarely suit {pcs}.",
		"You can throw a blanket over {club} and {pc} in the table. Fine — but {arena}, tables don't battle.",
		"No mind games from me — just a promise: {crowd} will make {pcs} uncomfortable from the first exchange to the last. {closer}",
	],
}

## Mind-game mail titles. Slots: {mgr} {short} (the rival), {clubs}.
const MIND_TITLES := {
	"dismissive": [
		"Press: {mgr} writes us off ahead of the {short} tie",
		"Press: {mgr} sees only one winner in our {short} meeting",
		"Press: {mgr} laughs off our chances this week",
		"Press: 'Not a tie that worries me' — {mgr} on facing us",
		"Press: {mgr} calls {short} clear favourites",
		"Press: {mgr} dismisses all talk of an upset",
		"Press: {mgr} barely rates us, and says so",
	],
	"wary": [
		"Press: {mgr} piles the pressure on us before {short} clash",
		"Press: {mgr} plays the underdog card ahead of our tie",
		"Press: 'All the pressure is on them' — {mgr} speaks out",
		"Press: {mgr} insists {short} have nothing to lose",
		"Press: {mgr} turns the spotlight onto our expectations",
		"Press: {mgr} relishes the outsider role against us",
		"Press: {mgr} says the burden is ours to carry",
	],
	"spiky": [
		"Press: {mgr} stokes the fire ahead of our meeting",
		"Press: {mgr} claims to know where we're weak",
		"Press: {mgr} sharpens the knives before {short} clash",
		"Press: 'It comes down to nerve' — {mgr} on our tie",
		"Press: {mgr} refuses to give an inch before {short} battle",
		"Press: war of words — {mgr} has plenty to say about us",
		"Press: {mgr} lights the fuse for the {short} meeting",
	],
}

## Mind-game plain body (list preview). Slots: {mgr} {paper}.
const MIND_BODIES := [
	"Speaking to {paper}, {mgr} had plenty to say about the upcoming tie.",
	"{mgr} went on the record with {paper} ahead of the meeting.",
	"The back pages belong to {mgr} this morning — and the subject is us.",
	"{paper} carries some pointed pre-match comments from {mgr}.",
	"{mgr} used a {paper} interview to talk about our tie.",
	"Pre-match noise: {mgr} has been talking, and {paper} printed every word.",
]

## Press reaction prose. Slots: {pc} {pcs} {prep} {mgr} (ours), {opp} {opps}
## {orep} (theirs), {us} {them}, {streak}, {round} {next_round}, {gap}.
const PRESS_PROSE := {
	"upset": [
		"Nobody outside the {pcs} dressing room saw this coming. A club with a reputation of {prep}/20 dismantling [b]{opp}[/b] ({orep}/20) by {us}-{them} is the kind of result that changes how a league talks about you. {mgr}'s side played without fear — and the giants blinked first.",
		"Put the coffee down and read that scoreline again: {pcs} {us}, {opp} {them}. The reputation charts say this should not happen. It happened, and {opp} have no complaints worth printing.",
		"Giant-killing is a craft, and [b]{pc}[/b] just published a masterclass. {opp} arrived as heavy favourites and left {us}-{them} losers, out-planned in every exchange that mattered.",
		"The bigger the name, the louder the fall. {opp} — reputation {orep}/20, wage bill to match — were beaten {us}-{them} by a {pcs} side that refused to be a footnote. {mgr} will not say 'I told you so'. This column will.",
		"There are wins, and there are statements. {pcs} {us}-{them} {opp} is a statement — the kind that makes every manager in the league re-read their scouting file on {pc}.",
		"How do you beat a club {gap} reputation points above you? Ask {mgr}, because {pc} just wrote the manual against {opp}: discipline early, courage late, and a scoreline — {us}-{them} — that will follow the favourites around for months.",
		"{opp} were supposed to be a class apart. For long stretches they could not get near {pcs}, and the {us}-{them} result flattered nobody — least of all the favourites.",
		"Upsets usually need luck. This one needed none. {pc} beat {opp} {us}-{them} on merit, on preparation and on nerve — and the league table suddenly reads very differently.",
	],
	"flop": [
		"There is no dressing this up. [b]{pc}[/b] (reputation {prep}/20) were beaten {them}-{us} by {opp} ({orep}/20) — a side they were built, budgeted and expected to beat. Questions travel fast in this league, and today they are all pointed at {mgr}'s office.",
		"Supporters will use stronger words than this column is allowed to. {pcs} lost {them}-{us} to {opp}, a club they out-rank, out-earn and — on this evidence — cannot out-battle.",
		"Reputation {prep}/20. Resources to match. And a {them}-{us} defeat to {opp} that nobody at {pc} can explain, least of all the manager paid to prevent it.",
		"Bad days happen. What happened to {pcs} against {opp} was not a bad day — it was a warning. {them}-{us}, second-best in every exchange, and a dressing room with plenty to think about.",
		"If you want to know how a season unravels, it starts with afternoons like this: {pc} beaten {them}-{us} by {opp}, favourites in name only, and a manager suddenly answering questions instead of asking them.",
		"The league table does not care about reputations, and neither, evidently, do {opp}. Their {them}-{us} win over {pcs} was thoroughly earned — which is precisely what should worry {mgr}.",
		"Call it a shock if you like. Around {opps} they are calling it inevitable — they saw a flat {pc} side coming, and took them for {them}-{us}.",
		"Some defeats are noise. This one — {them}-{us} to {opp}, a club {pc} are supposed to look down on — is signal. The board will say the right things publicly. Privately, they counted every battle.",
	],
	"cupwin": [
		"The cup run is alive. [b]{pc}[/b] saw off {opp} {us}-{them} in the {round}, and the draw for the {next_round} suddenly matters a great deal in this corner of the league.",
		"Cup battles reward nerve, and {pcs} showed plenty of it — {opp} dispatched {us}-{them}, a place in the {next_round} secured, and a support daring to whisper about silverware.",
		"Tick another round off. {pc} handled {opp} {us}-{them} in the {round}, and handled is the right word: professional, controlled, never truly threatened.",
		"The romance of the cup usually belongs to someone else. Not this year, perhaps: {pcs} beat {opp} {us}-{them} and march into the {next_round} with genuine momentum.",
		"Knockout ties have a way of exposing soft squads. {pc} are not one of them — {opp} were beaten {us}-{them} in the {round}, and the {next_round} awaits.",
		"A {us}-{them} win over {opp}, a spot in the {next_round}, and a manager refusing to talk about the final. Managers always refuse. Supporters never do.",
		"The {round} is where cup runs usually go to die. {pcs} walked out of theirs with a {us}-{them} win over {opp} and the sound of a support starting to believe.",
		"Write it down: {pc} are in the {next_round}. {opp} pushed, probed and were seen off {us}-{them} — the mark of a side that has decided this competition is worth winning.",
	],
	"streak": [
		"[b]{streak} wins in a row.[/b] Streaks like this are not luck — they are structure, squad depth and a dugout that trusts itself. {pc} made it {streak} straight by beating {opp} {us}-{them}, and the chasing pack has noticed.",
		"The number of the week is {streak}. That is how many consecutive matches {pcs} have now won after seeing off {opp} {us}-{them}, and nobody else in the league is enjoying the arithmetic.",
		"Form is temporary, they say. Somebody should tell {pc}, whose {us}-{them} win over {opp} stretched the run to {streak} — and whose battlers look sharper with every week.",
		"Ask around the league who nobody wants to face right now and you get one answer: {pcs}. Victory number {streak} in succession arrived {us}-{them} against {opp}, and it barely raised a sweat.",
		"Win one, fine. Win two, form. Win {streak} in a row — as {pc} just did by beating {opp} {us}-{them} — and you are officially a problem the rest of the league has to solve.",
		"There is a hum around the {pcs} training ground these days, and results like this are why: {opp} beaten {us}-{them}, a {streak}-match winning run, and a squad that plainly believes.",
		"Consistency is the rarest currency in this league, and {pc} are printing it: {streak} wins on the spin after a {us}-{them} handling of {opp}.",
		"The streak lives. {pcs} {us}-{them} {opp} makes it {streak} straight wins — and the conversation around the league has quietly shifted from 'good run' to 'genuine contenders'.",
	],
	"champions": [
		"They will sing about this one for years. [b]{pc}[/b] beat {opp} {us}-{them} in the Indigo Cup Final and the trophy is theirs. Whatever happens in the league now, this season is already immortal.",
		"Champions. Say it slowly, {pcs} supporters — you have waited long enough. {opp} were beaten {us}-{them} in the Final, and the Indigo Cup is coming home.",
		"The Indigo Cup Final asked every question a final can ask, and {pc} answered all of them. {opp} beaten {us}-{them}; a trophy lifted; a place in club history sealed.",
		"Forget the tactics board for one night. {pcs} are cup winners — {us}-{them} over {opp} — and the celebrations you can hear from three districts away are entirely earned.",
		"Finals are won by squads that hold their nerve, and nobody held it better than {pc}. The {us}-{them} defeat of {opp} crowns a run this column doubted more than once. We were wrong.",
		"One day this squad will be grainy footage and fond exaggeration. Tonight it is simply the best knockout side in the league: {pcs} {us}-{them} {opp}, Indigo Cup winners.",
		"The medal does not care how you got there. But the manner of it — {opp} beaten {us}-{them} in the Final — means {pc} will be remembered as worthy champions, not lucky ones.",
		"Every trophy tells a story. This one tells of a {pcs} side that refused to blink on the biggest stage, beating {opp} {us}-{them} to lift the Indigo Cup.",
	],
}

const PRESS_TITLES := {
	"upset": [
		"Gazette: {pcs} stun {opp} in the shock of the season",
		"Gazette: giant-killing — {pcs} topple {opp}",
		"Gazette: {opp} humbled by fearless {pcs}",
		"Gazette: the upset nobody saw coming — {pcs} beat {opp}",
		"Gazette: {pcs} tear up the script against {opp}",
	],
	"flop": [
		"Gazette verdict: {pcs} humbled by {opps}",
		"Gazette verdict: no excuses for {pcs} after {opps} defeat",
		"Gazette verdict: alarm bells at {pcs} after {opps} loss",
		"Gazette verdict: {opps} expose a flat {pcs}",
		"Gazette verdict: a defeat {pcs} cannot explain away",
	],
	"cupwin": [
		"Cup fever: {pcs} march into the {next_round}",
		"Cup fever: {pcs} book their place in the {next_round}",
		"Cup fever: {pcs} keep the run alive against {opps}",
		"Cup fever: {pcs} through — and dreaming of more",
		"Cup fever: no slip-ups as {pcs} reach the {next_round}",
	],
	"streak": [
		"{streak} and counting — the league is talking about {pc}",
		"Make it {streak} straight: {pcs} roll on",
		"Unstoppable? {pcs} win number {streak} in a row",
		"The {pcs} machine: {streak} consecutive wins",
		"Who stops {pcs}? The winning run hits {streak}",
	],
	"champions": [
		"\"Immortals\" — {pc} lift the Indigo Cup",
		"Champions! {pc} win the Indigo Cup",
		"Glory night: {pc} are Indigo Cup winners",
		"History made — the Indigo Cup belongs to {pc}",
		"{pc} crowned: the Indigo Cup Final was theirs",
	],
}

const PRESS_BODIES := [
	"{jn} reacts to the result in {paper}.",
	"{jn}'s verdict on the result, in {paper}.",
	"The morning-after column from {jn} in {paper}.",
	"{paper} devotes its back page to our result — byline: {jn}.",
	"{jn} files a pointed reaction piece for {paper}.",
]

## Coach welfare note prose. Slots: {name} {species} {level} {apps} {cm}.
const UNHAPPY_PROSE := [
	"Boss — a quiet word before this becomes a loud one. [b]{name}[/b] ({species}, Lv {level}) has featured in [b]{apps} of our {cm}[/b] matches this season. The mood around the training pens is turning: less appetite in drills, snapping at the younger battlers. In my experience this only goes one way if it's left alone.",
	"Boss — you pay me to flag problems early, so here it is. [b]{name}[/b] ({species}, Lv {level}) has made just [b]{apps} appearances in {cm}[/b] matches, and it shows: half-effort in sparring, first out of the gym every evening. We are close to losing the room on this one.",
	"Boss — {name} cornered me after training today. [b]{apps} of {cm}[/b] matches is the number they keep repeating, and frankly I ran out of answers. A {species} of that level expects to battle, and the rest of the squad is watching how you handle it.",
	"Boss — I don't like carrying tales, but this one matters. [b]{name}[/b] ({species}, Lv {level}) has gone [b]{apps} for {cm}[/b] on selection this season, and the sulk has moved from the pens to the canteen. Left alone, this infects the whole group.",
	"Boss — short version: [b]{name}[/b] wants battles. Long version: [b]{apps} appearances from {cm}[/b] matches, a training intensity that has dropped two notches, and a {species} temper the younger ones are starting to copy.",
	"Boss — the physios noticed it first, the coaches second: [b]{name}[/b] ({species}, Lv {level}) has downed tools. You can trace it straight to the team sheets — [b]{apps} of {cm}[/b] this season. They feel forgotten, and honestly, the numbers back them up.",
	"Boss — before the press smell it: [b]{name}[/b] is unhappy. [b]{apps} matches out of {cm}[/b] is thin for a battler of that standing, and the mood has curdled from patient to pointed. Whatever you decide, decide it soon.",
	"Boss — I'll give it to you straight. [b]{name}[/b] ({species}, Lv {level}) believes the club has moved on without saying so — [b]{apps} of {cm}[/b] matches tells its own story. A word from you, either way, beats this silence.",
]

const UNHAPPY_TITLES := [
	"{name} is unhappy at the lack of battles",
	"{name} wants more battles — coach asks for a steer",
	"Squad concern: {name} frustrated by selection",
	"{name} growing restless on the bench",
	"Coach flags {name}'s frustration",
]

const UNHAPPY_BODIES := [
	"{coach} has asked to speak with you about a member of the squad.",
	"{coach} flags a growing selection problem.",
	"A welfare note from {coach} — one of the squad is unsettled.",
	"{coach} wants a decision on an unhappy battler.",
]

## Coach development note prose. Slots: {name} {species} {level} {n} {kos} {rating}.
const STAR_PROSE := [
	"Boss — thought you'd want this one in writing. [b]{name}[/b] ({species}, Lv {level}) has been outstanding. Across the last [b]{n}[/b] matches: [b]{kos} KOs[/b] and an average match rating of [b]{rating}[/b]. Technique, timing, temperament — everything we drill is showing up on matchday.",
	"Boss — some weeks this job is a pleasure. [b]{name}[/b] ({species}, Lv {level}) is flying: [b]{kos} KOs[/b] over the last [b]{n}[/b] matches and a [b]{rating}[/b] average rating. The whole staff room has noticed.",
	"Boss — a quick note for the file. If you're wondering who sets the standard in training right now, it's [b]{name}[/b]. The numbers agree: [b]{n}[/b] matches, [b]{kos} KOs[/b], rating [b]{rating}[/b]. That's not a purple patch, that's a level.",
	"Boss — I've coached a lot of {species}, and [b]{name}[/b] is doing things most of them never manage. Last [b]{n}[/b] matches: [b]{kos} KOs[/b], average rating [b]{rating}[/b]. Composure under pressure is the part you can't teach — and they have it.",
	"Boss — credit where it's due, and this is due. [b]{name}[/b] (Lv {level}) has turned good training into great matchdays: [b]{kos} KOs[/b] in [b]{n}[/b] outings, rating [b]{rating}[/b]. The rest of the squad raises its game just watching.",
	"Boss — you asked us to develop battlers, not just select them. Exhibit A: [b]{name}[/b]. Over [b]{n}[/b] recent matches — [b]{kos} KOs[/b], a [b]{rating}[/b] rating, and decision-making that has jumped a level.",
	"Boss — file this under 'good problems'. [b]{name}[/b] ({species}) is now performing like a headline battler: [b]{n}[/b] matches, [b]{kos} KOs[/b], average rating [b]{rating}[/b]. Other clubs will notice soon, if they haven't already.",
	"Boss — the data crew and the old heads finally agree on something: [b]{name}[/b] is in the form of their career. [b]{kos} KOs[/b] across [b]{n}[/b] matches at a [b]{rating}[/b] average. Whatever you're doing with them, keep doing it.",
]

const STAR_TITLES := [
	"{coach} is delighted with {name}'s development",
	"{name} in the form of their career, says {coach}",
	"Progress report: {name} flying in training and matches",
	"{coach} singles out {name} for praise",
	"{name}'s development is turning heads",
]

const STAR_BODIES := [
	"A glowing progress note from the coaching staff.",
	"{coach} puts a standout run of form on the record.",
	"Development report: the coaching staff are delighted.",
	"{coach} singles out a battler in top form.",
]

## Pledge follow-ups. Slots: {name} {species} {apps} {target}.
const PLEDGE_KEPT_PROSE := [
	"Boss — pledge honoured. You promised [b]{name}[/b] a run of battles and delivered: [b]{apps}[/b] appearances since your word was given. The mood swung the moment the team sheets proved you meant it.",
	"Boss — good news travels slowly in this game, so I'll speed it up: [b]{name}[/b] has had the battles you promised ({apps} since your pledge) and the sulk is gone. Trust like that spreads through a squad.",
	"Boss — remember the promise you made {name}? Kept, and noticed. [b]{apps}[/b] matches later the appetite in training is back, and the younger battlers saw the manager keep their word.",
	"Boss — closing the loop on {name}: promised battles, delivered battles ([b]{apps}[/b] of them). Morale is up, edges have softened, and I owe you an apology for doubting the plan.",
	"Boss — {name} asked me to pass on a rare thing in this business: thanks. The promised run of battles ([b]{apps}[/b] appearances) landed, and so has the message that this club keeps its word.",
	"Boss — for the file: your pledge to [b]{name}[/b] is settled — [b]{apps}[/b] battles inside the window. The whole pens took note. Promises kept are the cheapest morale tool we have.",
]

const PLEDGE_KEPT_TITLES := [
	"Promise kept: {name} has had their battles",
	"Pledge honoured: {name} back on side",
	"{name}: promised battles delivered",
	"Coach's note: your promise to {name} is settled",
]

const PLEDGE_BROKEN_PROSE := [
	"Boss — we have a problem of our own making. You promised [b]{name}[/b] a run of battles; the window has closed with only [b]{apps}[/b] of the [b]{target}[/b] delivered. They found out from the team sheets, which is the worst way. Morale has taken a real hit — and the squad saw it happen.",
	"Boss — I warned you they'd hold you to it. The pledge to [b]{name}[/b] has lapsed — [b]{apps}[/b] appearances against the [b]{target}[/b] you promised — and the trust we bought that day has been handed back with interest.",
	"Boss — a hard mail to write. [b]{name}[/b] kept their side: trained hard, waited, said nothing. The promised battles never came ({apps} of {target} before the deadline). Around the pens they're calling it what it is — a broken promise.",
	"Boss — the deadline on your pledge to [b]{name}[/b] passed quietly last night. [b]{apps}[/b] battles delivered of the [b]{target}[/b] promised. There was no scene, which worries me more than a scene would.",
	"Boss — you asked me to tell you these things straight: {name} feels lied to. The promised run of battles didn't materialise ({apps}/{target} inside the window), and the word 'promise' now gets air-quotes in the canteen.",
	"Boss — a promise made in this office died on the training ground this week. [b]{name}[/b] got {apps} of the {target} battles you pledged. Next time the manager gives their word, the squad will remember this.",
]

const PLEDGE_BROKEN_TITLES := [
	"Promise broken: {name} never got those battles",
	"Pledge lapsed: {name} feels let down",
	"{name}: the promised battles never came",
	"Coach's warning: broken promise to {name}",
]

const ROUNDUP_POM_QUOTES := [
	"{name} was simply a level above everything else on the circuit this month.",
	"Ask any coach in the league who they'd steal first right now: {name}, every time.",
	"Months like {name}'s are why the ratings column exists.",
	"There was the field, and then there was {name}.",
	"If {name} keeps this up, the end-of-season awards are a formality.",
	"{club} supporters, enjoy {name} while you can — form like this gets noticed.",
	"The numbers flatter nobody: {name} earned every decimal of that rating.",
	"Somewhere a scout is underlining {name}'s name three times.",
]

const ROUNDUP_BODIES := [
	"{paper}'s monthly column: awards, the table and the stories of {month}.",
	"Awards, storylines and the state of the race — {month} reviewed in {paper}.",
	"{paper} closes the books on {month}: winners, shocks and the table.",
	"The {month} review in {paper}: who rose, who fell, who ruled.",
]

## Reply feedback notes (player-triggered; varied per fixture/mon).
const REPLY_FIRE_GOOD := [
	"Your response makes the back page — the squad walks taller in training (morale +3 across the squad).",
	"You give as good as we got, and the dressing room loves it (morale +3 across the squad).",
	"Your counter-punch lands cleanly in print — training crackles the next morning (morale +3 across the squad).",
	"The papers call it 'a manager defending their own' — the squad noticed (morale +3 across the squad).",
]
const REPLY_FIRE_BAD := [
	"The exchange rattles the dressing room — some battlers look tense in training (morale -2 across the squad).",
	"It reads worse in print than it sounded in your head — a few heads drop (morale -2 across the squad).",
	"The row escalates and the squad feels the heat meant for you (morale -2 across the squad).",
	"Your reply hands them tomorrow's headline too — the group tightens up (morale -2 across the squad).",
]
const REPLY_CALM := [
	"You turn the question into public praise of your own squad (morale +1 across the squad). {mgr} got no reaction.",
	"You sidestep the bait and talk up your battlers instead (morale +1 across the squad). {mgr} is left shadow-boxing.",
	"Classy, measured, and quietly pointed — your squad appreciates it (morale +1 across the squad). {mgr} got nothing back.",
	"You make it about your own group, not the noise (morale +1 across the squad). {mgr}'s jab dies unanswered.",
]
const REPLY_NONE := [
	"No comment. The story dies by the weekend — and the squad takes its cue from the match, not the papers.",
	"You let silence do the talking. By the weekend it's yesterday's news.",
	"Not a word. Some fights aren't worth the ink.",
]
const REPLY_PROMISE := [
	"You promise {name} a proper run — {target} battles inside the next four weeks. Morale {b} » {a}. The coaches will hold you to it, and so will this inbox.",
	"Your word is given: {target} battles for {name} within four weeks (morale {b} » {a}). Break it and the whole squad will know.",
	"{name} leaves your office with a promise: {target} battles by {deadline}. Morale {b} » {a}. Promises here are tracked.",
]
const REPLY_PATIENT := [
	"You tell {name} to earn the shirt in training. Morale {b} » {a} — a gamble on their character.",
	"No guarantees, you say — form picks the team. {name} takes it badly for now (morale {b} » {a}).",
	"You back the coaches' selection and tell {name} so. Morale {b} » {a}; time will judge the call.",
]
const REPLY_PRAISE := [
	"You pass on the praise personally. {name}'s morale {b} » {a}.",
	"A word from the manager, delivered in front of the group — {name} beams (morale {b} » {a}).",
	"You make sure {name} hears it from you, not the corridor. Morale {b} » {a}.",
]
const REPLY_GROUNDED := [
	"You keep the praise in-house — no complacency here. Morale {b} » {a}.",
	"Quiet approval, nothing more; standards stay standards. Morale {b} » {a}.",
	"You bank the praise for when it's needed. Morale {b} » {a}.",
]


# ==================================================================== used-line registry
## Persisted implicitly: every generated message stores the template ids it
## used under "tids", and the registry is rebuilt from the saved inbox each
## pass. A line used within RECENT_WINDOW days of a publication date is
## excluded from selection for that date.

func _load_used_lines() -> void:
	_used_lines.clear()
	for m in GameState.inbox:
		var date := str(m.get("date", ""))
		for t in m.get("tids", []):
			_used_lines.append({"tid": str(t), "date": date})


func _line_recent(tid: String, date: String) -> bool:
	for e in _used_lines:
		if str(e["tid"]) == tid and absi(Season.days_between(str(e["date"]), date)) <= RECENT_WINDOW:
			return true
	return false


func _mark_used(tid: String, date: String) -> void:
	_used_lines.append({"tid": tid, "date": date})


## Pick a variant index from bank `key` of size `n` for a message published on
## `date`: prefer variants unused within the window; else least-recently used.
func _pick_line(key: String, n: int, rng: RandomNumberGenerator, date: String) -> int:
	var fresh: Array = []
	for i in n:
		if not _line_recent("%s.%d" % [key, i], date):
			fresh.append(i)
	if not fresh.is_empty():
		return int(fresh[rng.randi_range(0, fresh.size() - 1)])
	var best := 0
	var best_last := "9999-99-99"
	for i in n:
		var last := ""
		for e in _used_lines:
			if str(e["tid"]) == "%s.%d" % [key, i] and str(e["date"]) > last:
				last = str(e["date"])
		if last < best_last:
			best_last = last
			best = i
	return best


func _fmt(tpl: String, params: Dictionary) -> String:
	# Localization point: template banks stay English (stable ids); the
	# catalog (i18n/translations.csv) carries the Spanish line for each.
	return I18n.t(tpl).format(params)


## Capitalize the first letter of every sentence — persona slots ("my squad",
## "when the battles start") are lowercase and may land at a sentence start.
func _sentence_case(t: String) -> String:
	var out := ""
	var boundary := true
	for i in t.length():
		var c := t[i]
		if boundary and c.to_lower() != c.to_upper():   # first letter of a sentence
			out += c.to_upper()
			boundary = false
		else:
			out += c
			if c == "." or c == "?" or c == "!":
				boundary = true
			elif boundary and c != " " and c != "\"" and c != "'" and c != "—":
				boundary = false   # sentence began with a digit/symbol
	return out


## Career-wide verbatim guard: has this exact quote ever been published?
func _quote_exists(text: String) -> bool:
	for m in GameState.inbox:
		if str(m.get("quote", "")) == text:
			return true
	return false


# ==================================================================== generate

func generate() -> void:
	_load_used_lines()
	var have := {}
	for m in GameState.inbox:
		if m.has("uid"):
			have[m["uid"]] = true
	_gen_mind_games(have)
	_gen_press_reactions(have)
	_gen_coach_notes(have)
	_gen_monthly_roundups(have)
	_check_pledges(have)
	_refresh_flags()


func _add(have: Dictionary, uid: String, date: String, title: String, body: String, extra: Dictionary) -> void:
	if have.has(uid):
		return
	GameState.add_inbox_message(date, title, body)
	var m: Dictionary = GameState.inbox[0]
	m["uid"] = uid
	for k in extra:
		m[k] = extra[k]
	if date < GameState.current_date and not m.get("urgent", false):
		m["read"] = true
	have[uid] = true


## Keep decision flags honest: mind-games stop demanding a reply once the
## match kicks off; welfare notes go stale after their window.
func _refresh_flags() -> void:
	for m in GameState.inbox:
		var uid := str(m.get("uid", ""))
		if uid.begins_with("mind:"):
			if m.get("replied", "") != "":
				m["urgent"] = false
				continue
			var f := _fixture(uid.trim_prefix("mind:"))
			m["urgent"] = not f.is_empty() and not f.get("played", false)
		elif uid.begins_with("monlow:"):
			if m.get("replied", "") != "":
				m["urgent"] = false
				continue
			m["urgent"] = Season.days_between(str(m["date"]), GameState.current_date) <= NOTE_WINDOW


# ------------------------------------------------------------- rival mind-games

func _gen_mind_games(have: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	for f in GameState.player_fixtures():
		var uid := "mind:%s" % f["id"]
		if have.has(uid):
			continue
		var msg_date: String = Season.date_add(str(f["date"]), -2)
		if msg_date < GameState.season_start:
			msg_date = GameState.season_start
		if msg_date > GameState.current_date:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = GameState.career_seed + absi(("mind" + str(f["id"])).hash())
		var we_home: bool = GameState.is_player_club(f["home"])
		var opp: Dictionary = GameState.club(str(f["away"] if we_home else f["home"]))
		if opp.is_empty():
			continue
		var big_tie: bool = str(f["comp"]) == "cup" and int(f.get("round", 1)) >= 3
		var chance := 0.40 + (0.18 if int(opp["reputation"]) >= int(pc["reputation"]) else 0.0)
		if not big_tie and rng.randf() > chance:
			continue
		var tone := _mind_tone(opp, pc)
		var mgr := str(opp["manager"])
		var pers := persona(mgr)
		var qparams := {
			"pc": str(pc["name"]), "pcs": str(pc["short"]),
			"club": str(opp["name"]), "clubs": str(opp["short"]),
			"tic": pers["tic"], "crowd": pers["crowd"],
			"arena": pers["arena"], "closer": pers["closer"],
		}
		var q := _compose_quote(tone, qparams, rng, msg_date)
		var t_bank: Array = MIND_TITLES[tone]
		var t_idx := _pick_line("mind.t." + tone, t_bank.size(), rng, msg_date)
		var title := _fmt(t_bank[t_idx], {"mgr": mgr, "short": str(opp["short"])})
		var b_idx := _pick_line("mind.b", MIND_BODIES.size(), rng, msg_date)
		var body := _fmt(MIND_BODIES[b_idx], {"mgr": mgr, "paper": PAPER})
		var tids := [str(q["tid"]), "mind.t.%s.%d" % [tone, t_idx], "mind.b.%d" % b_idx]
		for tid in tids:
			_mark_used(str(tid), msg_date)
		_add(have, uid, msg_date, title, body,
			{"cat": "media", "sender": I18n.t("%s (%s Manager)") % [mgr, opp["name"]],
				"fid": str(f["id"]), "opp_id": str(opp["id"]), "tone": tone,
				"quote": str(q["text"]), "tids": tids,
				"facts": _snapshot_facts(pc, opp, msg_date),
				"urgent": not f.get("played", false)})


## Compose a persona-conditioned quote, excluding recently-used templates and
## re-rolling anything that would exactly match a quote already published.
func _compose_quote(tone: String, params: Dictionary, rng: RandomNumberGenerator, date: String) -> Dictionary:
	var bank: Array = MIND_QUOTES[tone]
	var idx := _pick_line("mind.q." + tone, bank.size(), rng, date)
	var text := _sentence_case(_fmt(str(bank[idx]), params))
	var tries := 0
	while _quote_exists(text) and tries < bank.size():
		idx = (idx + 1) % bank.size()
		text = _sentence_case(_fmt(str(bank[idx]), params))
		tries += 1
	if _quote_exists(text):
		text += " " + str(params["closer"])   # hard guarantee of uniqueness
	return {"text": text, "tid": "mind.q.%s.%d" % [tone, idx]}


func _mind_tone(opp: Dictionary, pc: Dictionary) -> String:
	var gap := int(opp["reputation"]) - int(pc["reputation"])
	if gap >= 2:
		return "dismissive"
	if gap <= -2:
		return "wary"
	return "spiky"


## Publication-time snapshot: form, table positions and squad morale as they
## stood when the piece went to print. Rendered verbatim forever after.
func _snapshot_facts(pc: Dictionary, opp: Dictionary, pub_date: String) -> Dictionary:
	var pre: Array = GameState.fixtures.filter(func(x):
		return x.get("played", false) and str(x["date"]) < pub_date)
	var table := Season.compute_table(GameState.club_ids(), pre)
	var our_pos := 0
	var their_pos := 0
	var their_played := 0
	for i in table.size():
		var cid := str(table[i]["club_id"])
		if cid == str(pc["id"]):
			our_pos = i + 1
		if cid == str(opp["id"]):
			their_pos = i + 1
			their_played = int(table[i].get("played", 0))
	return {
		"as_of": pub_date,
		"our_form": Season.club_form(str(pc["id"]), pre, 5),
		"their_form": Season.club_form(str(opp["id"]), pre, 5),
		"our_pos": our_pos, "their_pos": their_pos,
		"their_pos_text": (I18n.t("yet to play in the league") if their_played == 0
			else I18n.t("%s in the league") % _ordinal(their_pos)),
		"morale": _avg_squad_morale(pc),
	}


## The manager's reply to a mind-game — a real, morale-moving decision.
func mind_replies(msg: Dictionary) -> Array:
	var f := _fixture(str(msg.get("fid", "")))
	if f.is_empty() or f.get("played", false) or msg.get("replied", "") != "":
		return []
	return [
		{"kind": "reply", "reply": "fire", "style": "warn", "label": I18n.t("Fire Back in the Press")},
		{"kind": "reply", "reply": "calm", "style": "good", "label": I18n.t("Praise Your Squad Instead")},
		{"kind": "reply", "reply": "none", "style": "bad", "label": I18n.t("No Comment")},
	]


# ------------------------------------------------------------- media reactions

func _gen_press_reactions(have: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	var played: Array = GameState.player_fixtures().filter(func(f): return f.get("played", false))
	played.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	var streak := 0
	for f in played:
		var we_home: bool = GameState.is_player_club(f["home"])
		var us := int(f["score_home"] if we_home else f["score_away"])
		var them := int(f["score_away"] if we_home else f["score_home"])
		var won := us > them
		streak = streak + 1 if won else 0
		var uid := "press:%s" % f["id"]
		if have.has(uid):
			continue
		var opp: Dictionary = GameState.club(str(f["away"] if we_home else f["home"]))
		if opp.is_empty():
			continue
		var gap := int(opp["reputation"]) - int(pc["reputation"])
		var kind := ""
		if str(f["comp"]) == "cup" and won and int(f.get("round", 1)) >= 4:
			kind = "champions"
		elif won and gap >= 3:
			kind = "upset"
		elif str(f["comp"]) == "cup" and won and int(f.get("round", 1)) >= 2:
			kind = "cupwin"
		elif won and (streak == 3 or streak == 5 or streak == 8):
			kind = "streak"
		elif not won and gap <= -3:
			kind = "flop"
		if kind == "":
			continue
		var msg_date: String = Season.date_add(str(f["date"]), 1)
		if msg_date > GameState.current_date:
			msg_date = GameState.current_date
		var jn := _journalist(str(f["id"]))
		var rng := RandomNumberGenerator.new()
		rng.seed = GameState.career_seed + absi(("press" + str(f["id"])).hash())
		var rnd := int(f.get("round", 1))
		var params := {
			"pc": str(pc["name"]), "pcs": str(pc["short"]),
			"prep": int(pc["reputation"]), "mgr": str(pc["manager"]),
			"opp": str(opp["name"]), "opps": str(opp["short"]),
			"orep": int(opp["reputation"]), "gap": absi(gap),
			"us": us, "them": them, "streak": streak,
			"round": I18n.cup_round_prose(rnd),
			"next_round": I18n.cup_round_prose(mini(rnd + 1, 4)),
		}
		var p_bank: Array = PRESS_PROSE[kind]
		var p_idx := _pick_line("press.p." + kind, p_bank.size(), rng, msg_date)
		var prose := _fmt(str(p_bank[p_idx]), params)
		var t_bank: Array = PRESS_TITLES[kind]
		var t_idx := _pick_line("press.t." + kind, t_bank.size(), rng, msg_date)
		var title := _fmt(str(t_bank[t_idx]), params)
		var b_idx := _pick_line("press.b", PRESS_BODIES.size(), rng, msg_date)
		var body := _fmt(PRESS_BODIES[b_idx], {"jn": jn, "paper": PAPER})
		var tids := ["press.p.%s.%d" % [kind, p_idx], "press.t.%s.%d" % [kind, t_idx],
			"press.b.%d" % b_idx]
		for tid in tids:
			_mark_used(str(tid), msg_date)
		# publication-time table position (after this result, before anything later)
		var upto: Array = GameState.fixtures.filter(func(x):
			return x.get("played", false) and str(x["date"]) <= str(f["date"]))
		var table := Season.compute_table(GameState.club_ids(), upto)
		var pos_at_pub := 0
		for i in table.size():
			if GameState.is_player_club(str(table[i]["club_id"])):
				pos_at_pub = i + 1
		_add(have, uid, msg_date, title, body,
			{"cat": "media", "sender": "%s — %s" % [jn, PAPER], "fid": str(f["id"]),
				"press_kind": kind, "streak": streak, "prose": prose,
				"pos_at_pub": pos_at_pub, "tids": tids})


func _journalist(salt: String) -> String:
	return JOURNALISTS[absi((str(GameState.career_seed) + salt).hash()) % JOURNALISTS.size()]


# ------------------------------------------------------------- coach mon notes

func _gen_coach_notes(have: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	var days := Season.days_between(GameState.season_start, GameState.current_date)
	var checkpoint := NOTE_PERIOD
	while checkpoint <= days:
		var date := Season.date_add(GameState.season_start, checkpoint)
		var idx := int(round(float(checkpoint) / NOTE_PERIOD))
		if idx % 2 == 1:
			_gen_unhappy_note(have, date, pc)
		else:
			_gen_delighted_note(have, date, pc)
		checkpoint += NOTE_PERIOD


func _played_club_fixtures(club_id: String, upto: String) -> Array:
	return GameState.fixtures.filter(func(f):
		return f.get("played", false) and str(f["date"]) <= upto \
			and (str(f["home"]) == club_id or str(f["away"]) == club_id))


func _appearances(club_id: String, uid: String, upto: String) -> int:
	var n := 0
	for f in _played_club_fixtures(club_id, upto):
		var d: Dictionary = Season.fixture_detail(f)
		if not d.is_empty() and (d["players"] as Dictionary).has(uid):
			n += 1
	return n


## Chronological dates on which a mon appeared for its club in (after, upto].
func _appearance_dates(club_id: String, mon_uid: String, after: String, upto: String) -> Array:
	var fs: Array = GameState.fixtures.filter(func(f):
		return f.get("played", false) and str(f["date"]) > after and str(f["date"]) <= upto \
			and (str(f["home"]) == club_id or str(f["away"]) == club_id))
	fs.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	var out: Array = []
	for f in fs:
		var d: Dictionary = Season.fixture_detail(f)
		if not d.is_empty() and (d["players"] as Dictionary).has(mon_uid):
			out.append(str(f["date"]))
	return out


## "Unhappy at the lack of battles" — the coach flags the most starved mon.
func _gen_unhappy_note(have: Dictionary, date: String, pc: Dictionary) -> void:
	var uid := "monlow:%s" % date
	if have.has(uid):
		return
	var club_matches := _played_club_fixtures(str(pc["id"]), date).size()
	if club_matches < 3:
		return
	var worst: Dictionary = {}
	var worst_apps := 99999
	for inst in pc["squad"]:
		var apps := _appearances(str(pc["id"]), str(inst["uid"]), date)
		if apps < worst_apps or (apps == worst_apps and int(inst["level"]) > int(worst.get("level", 0))):
			worst_apps = apps
			worst = inst
	if worst.is_empty() or float(worst_apps) > float(club_matches) / 3.0:
		return  # everyone is getting minutes — no complaint to pass on
	# don't nag about the same mon while an earlier complaint is still open
	for m in GameState.inbox:
		if str(m.get("uid", "")).begins_with("monlow:") and str(m.get("mon_uid", "")) == str(worst["uid"]) \
			and Season.days_between(str(m["date"]), date) < 28:
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + absi(("monlow" + date).hash())
	var params := {"name": news.display_name(worst), "species": str(worst["species"]),
		"level": int(worst["level"]), "apps": worst_apps, "cm": club_matches,
		"coach": _coach_name(pc)}
	var p_idx := _pick_line("monlow.p", UNHAPPY_PROSE.size(), rng, date)
	var t_idx := _pick_line("monlow.t", UNHAPPY_TITLES.size(), rng, date)
	var b_idx := _pick_line("monlow.b", UNHAPPY_BODIES.size(), rng, date)
	var tids := ["monlow.p.%d" % p_idx, "monlow.t.%d" % t_idx, "monlow.b.%d" % b_idx]
	for tid in tids:
		_mark_used(str(tid), date)
	_add(have, uid, date,
		_fmt(UNHAPPY_TITLES[t_idx], params),
		_fmt(UNHAPPY_BODIES[b_idx], params),
		{"cat": "staff", "sender": _coach_name(pc), "mon_uid": str(worst["uid"]),
			"apps": worst_apps, "club_matches": club_matches,
			"prose": _fmt(UNHAPPY_PROSE[p_idx], params), "tids": tids, "urgent": true})


## "Delighted with development" — the coach singles out the form battler.
func _gen_delighted_note(have: Dictionary, date: String, pc: Dictionary) -> void:
	var uid := "monstar:%s" % date
	if have.has(uid):
		return
	var best: Dictionary = {}
	var best_rating := 0.0
	var best_log: Array = []
	for inst in pc["squad"]:
		var log := Season.pokemon_match_log(str(inst["uid"]), str(pc["id"]),
			GameState.fixtures.filter(func(f): return str(f["date"]) <= date))
		if log.size() < 2:
			continue
		var recent: Array = log.slice(maxi(0, log.size() - 4))
		var avg := 0.0
		for e in recent:
			avg += float(e["rating"])
		avg /= recent.size()
		if avg > best_rating:
			best_rating = avg
			best = inst
			best_log = recent
	if best.is_empty() or best_rating < 6.9:
		return
	for m in GameState.inbox:
		if str(m.get("uid", "")).begins_with("monstar:") and str(m.get("mon_uid", "")) == str(best["uid"]) \
			and Season.days_between(str(m["date"]), date) < 35:
			return
	var kos := 0
	for e in best_log:
		kos += int(e["kos"])
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + absi(("monstar" + date).hash())
	var params := {"name": news.display_name(best), "species": str(best["species"]),
		"level": int(best["level"]), "n": best_log.size(), "kos": kos,
		"rating": I18n.decimal(best_rating, 2), "coach": _coach_first_name(pc)}
	var p_idx := _pick_line("monstar.p", STAR_PROSE.size(), rng, date)
	var t_idx := _pick_line("monstar.t", STAR_TITLES.size(), rng, date)
	var b_idx := _pick_line("monstar.b", STAR_BODIES.size(), rng, date)
	var tids := ["monstar.p.%d" % p_idx, "monstar.t.%d" % t_idx, "monstar.b.%d" % b_idx]
	for tid in tids:
		_mark_used(str(tid), date)
	_add(have, uid, date,
		_fmt(STAR_TITLES[t_idx], params),
		_fmt(STAR_BODIES[b_idx], {"coach": _coach_name(pc)}),
		{"cat": "staff", "sender": _coach_name(pc), "mon_uid": str(best["uid"]),
			"rating": snappedf(best_rating, 0.01), "recent_kos": kos, "recent_n": best_log.size(),
			"prose": _fmt(STAR_PROSE[p_idx], params), "tids": tids})


func _coach_name(pc: Dictionary) -> String:
	for s in pc.get("staff", []):
		if str(s["role"]) == "coach":
			return I18n.t("%s (Coach)") % s["name"]
	return I18n.t("Head Coach")


func _coach_first_name(pc: Dictionary) -> String:
	var full := _coach_name(pc).split(" (")[0]
	return full.split(" ")[0]


# ------------------------------------------------------------- pledges
## Promised-battles pledges are REAL state with deadlines. The pledge lives on
## the originating monlow message ({mon_uid, made_on, deadline, target,
## status}); this pass resolves it against actual appearances in the fixture
## replays and generates follow-up mail plus genuine morale consequences.

func _check_pledges(have: Dictionary) -> void:
	var pc: Dictionary = GameState.player_club()
	var resolved := false
	for m in GameState.inbox.duplicate():
		var pl_v: Variant = m.get("pledge", {})
		if not (pl_v is Dictionary):
			continue
		var pl: Dictionary = pl_v
		if pl.is_empty() or str(pl.get("status", "")) != "open":
			continue
		var mon_uid := str(pl["mon_uid"])
		var inst := GameState.squad_member(mon_uid)
		if inst.is_empty():
			pl["status"] = "void"   # battler left the club — pledge dissolves
			resolved = true
			continue
		var target := int(pl.get("target", PLEDGE_TARGET))
		var deadline := str(pl["deadline"])
		var upto := deadline if deadline < GameState.current_date else GameState.current_date
		var dates := _appearance_dates(str(pc["id"]), mon_uid, str(pl["made_on"]), upto)
		if dates.size() >= target:
			pl["status"] = "kept"
			pl["apps"] = dates.size()
			pl["resolved_on"] = str(dates[target - 1])
			_pledge_mail(have, m, pl, inst, pc, true)
			resolved = true
		elif GameState.current_date > deadline:
			pl["status"] = "broken"
			pl["apps"] = dates.size()
			pl["resolved_on"] = deadline
			_pledge_mail(have, m, pl, inst, pc, false)
			resolved = true
	if resolved:
		GameState.save_game()


func _pledge_mail(have: Dictionary, src: Dictionary, pl: Dictionary, inst: Dictionary,
		pc: Dictionary, kept: bool) -> void:
	var date := Season.date_add(str(pl["resolved_on"]), 1)
	if date > GameState.current_date:
		date = GameState.current_date
	var before := int(inst.get("morale", 70))
	var after: int
	if kept:
		after = mini(100, before + 7)
		inst["morale"] = after
	else:
		after = maxi(0, before - 12)
		inst["morale"] = after
		# a broken promise is squad news — everyone else takes a small knock
		for other in pc["squad"]:
			if str(other["uid"]) != str(inst["uid"]):
				other["morale"] = clampi(int(other.get("morale", 70)) - 1, 0, 100)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + absi(("pledge" + str(src.get("uid", "")) + date).hash())
	var key := "pledge.kept" if kept else "pledge.broken"
	var titles: Array = PLEDGE_KEPT_TITLES if kept else PLEDGE_BROKEN_TITLES
	var proses: Array = PLEDGE_KEPT_PROSE if kept else PLEDGE_BROKEN_PROSE
	var params := {"name": news.display_name(inst), "species": str(inst["species"]),
		"apps": int(pl.get("apps", 0)), "target": int(pl.get("target", PLEDGE_TARGET))}
	var t_idx := _pick_line(key + ".t", titles.size(), rng, date)
	var p_idx := _pick_line(key + ".p", proses.size(), rng, date)
	var tids := ["%s.t.%d" % [key, t_idx], "%s.p.%d" % [key, p_idx]]
	for tid in tids:
		_mark_used(str(tid), date)
	_add(have, "pledge:%s:%s" % [str(src.get("uid", "")), "kept" if kept else "broken"], date,
		_fmt(titles[t_idx], params),
		I18n.t("%s reports back on the promise you made.") % _coach_name(pc),
		{"cat": "staff", "sender": _coach_name(pc), "mon_uid": str(inst["uid"]),
			"pledge_kept": kept, "apps": int(pl.get("apps", 0)),
			"target": int(pl.get("target", PLEDGE_TARGET)),
			"made_on": str(pl.get("made_on", "")), "deadline": str(pl.get("deadline", "")),
			"morale_before": before, "morale_after": after,
			"prose": _fmt(proses[p_idx], params), "tids": tids})


# ------------------------------------------------------------- monthly round-up

func _gen_monthly_roundups(have: Dictionary) -> void:
	var boundary := "%s-01" % str(GameState.season_start).substr(0, 7)
	for i in 14:
		boundary = "%s-01" % Season.date_add(boundary, 32).substr(0, 7)
		if boundary > GameState.current_date:
			return
		_gen_roundup(have, boundary, Season.date_add(boundary, -1).substr(0, 7))


func _gen_roundup(have: Dictionary, boundary: String, month_key: String) -> void:
	var uid := "roundup:%s" % month_key
	if have.has(uid):
		return
	var in_month: Array = GameState.fixtures.filter(func(f):
		return f.get("played", false) and str(f["date"]).begins_with(month_key))
	var league_n := in_month.filter(func(f): return str(f["comp"]) == "league").size()
	if league_n < 4:
		return

	# ---- club-of-the-month records (league only) + biggest upset
	var recs := {}
	var upset := {}
	var upset_gap := 0
	for f in in_month:
		var h := str(f["home"])
		var a := str(f["away"])
		var hw: bool = int(f["score_home"]) > int(f["score_away"])
		if str(f["comp"]) == "league":
			for cid in [h, a]:
				if not recs.has(cid):
					recs[cid] = {"won": 0, "lost": 0, "bf": 0, "ba": 0}
			recs[h]["bf"] += int(f["score_home"])
			recs[h]["ba"] += int(f["score_away"])
			recs[a]["bf"] += int(f["score_away"])
			recs[a]["ba"] += int(f["score_home"])
			recs[h]["won" if hw else "lost"] += 1
			recs[a]["lost" if hw else "won"] += 1
		var wc: Dictionary = GameState.club(h if hw else a)
		var lc: Dictionary = GameState.club(a if hw else h)
		if not wc.is_empty() and not lc.is_empty():
			var gap := int(lc["reputation"]) - int(wc["reputation"])
			if gap > upset_gap:
				upset_gap = gap
				upset = {"winner": str(wc["name"]), "loser": str(lc["name"]), "gap": gap,
					"score": "%d-%d" % [int(f["score_home"]), int(f["score_away"])],
					"date": str(f["date"]), "comp": str(f["comp"])}
	var totm_id := ""
	for cid in recs:
		if totm_id == "":
			totm_id = cid
			continue
		var x: Dictionary = recs[cid]
		var y: Dictionary = recs[totm_id]
		var dx: int = x["won"] * 3 + (x["bf"] - x["ba"])
		var dy: int = y["won"] * 3 + (y["bf"] - y["ba"])
		if dx > dy or (dx == dy and str(cid) < totm_id):
			totm_id = cid
	var totm := {}
	if totm_id != "":
		totm = {"club": str(GameState.club(totm_id)["name"]), "club_id": totm_id,
			"won": int(recs[totm_id]["won"]), "lost": int(recs[totm_id]["lost"])}

	# ---- Pokémon of the Month: aggregate the REAL replay ratings of every
	# battler in every fixture played this month, league and cup alike
	var agg := {}
	for f in in_month:
		var d: Dictionary = Season.fixture_detail(f)
		if d.is_empty():
			continue
		var players: Dictionary = d["players"]
		for puid in players:
			var p: Dictionary = players[puid]
			var cid := str(f["home"] if int(p["side"]) == 0 else f["away"])
			if not agg.has(puid):
				agg[puid] = {"name": str(p["name"]), "species": str(p["species"]),
					"club_id": cid, "battles": 0, "kos": 0, "dmg": 0, "rating_sum": 0.0}
			var a2: Dictionary = agg[puid]
			a2["battles"] += int(p["battles"])
			a2["kos"] += int(p["kos"])
			a2["dmg"] += int(p["dmg"])
			a2["rating_sum"] += float(p["rating_sum"])
	var ranked: Array = []
	for puid in agg:
		var a3: Dictionary = agg[puid]
		if int(a3["battles"]) >= 4:
			ranked.append(a3)
	if ranked.is_empty():
		for puid in agg:
			ranked.append(agg[puid])
	ranked.sort_custom(func(x, y):
		var rx: float = float(x["rating_sum"]) / maxi(int(x["battles"]), 1)
		var ry: float = float(y["rating_sum"]) / maxi(int(y["battles"]), 1)
		if not is_equal_approx(rx, ry):
			return rx > ry
		return int(x["kos"]) > int(y["kos"]))
	var podium: Array = []
	for a4 in ranked.slice(0, 3):
		var club: Dictionary = GameState.club(str(a4["club_id"]))
		podium.append({"name": str(a4["name"]), "species": str(a4["species"]),
			"club": str(club.get("short", "?")), "club_name": str(club.get("name", "?")),
			"mine": GameState.is_player_club(str(a4["club_id"])),
			"battles": int(a4["battles"]), "kos": int(a4["kos"]), "dmg": int(a4["dmg"]),
			"rating": snappedf(float(a4["rating_sum"]) / maxi(int(a4["battles"]), 1), 0.01)})

	# ---- our month + the leader when the books closed
	var pid: String = str(GameState.world["meta"]["player_club_id"])
	var our: Dictionary = recs.get(pid, {"won": 0, "lost": 0, "bf": 0, "ba": 0})
	var upto: Array = GameState.fixtures.filter(func(f):
		return f.get("played", false) and str(f["date"]) < boundary)
	var table := Season.compute_table(GameState.club_ids(), upto)
	var leader := ""
	var our_pos := 0
	if not table.is_empty():
		leader = str(GameState.club(str(table[0]["club_id"]))["name"])
		for i in table.size():
			if GameState.is_player_club(str(table[i]["club_id"])):
				our_pos = i + 1

	var mname: String = _month_name(month_key)
	var pom_line := ""
	var pom_quote := ""
	var tids: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + absi(("roundup" + month_key).hash())
	if not podium.is_empty():
		pom_line = "%s (%s)" % [podium[0]["name"], podium[0]["club"]]
		var q_idx := _pick_line("roundup.q", ROUNDUP_POM_QUOTES.size(), rng, boundary)
		pom_quote = _fmt(ROUNDUP_POM_QUOTES[q_idx],
			{"name": str(podium[0]["name"]), "club": str(podium[0]["club_name"])})
		tids.append("roundup.q.%d" % q_idx)
	var b_idx := _pick_line("roundup.b", ROUNDUP_BODIES.size(), rng, boundary)
	tids.append("roundup.b.%d" % b_idx)
	for tid in tids:
		_mark_used(str(tid), boundary)
	_add(have, uid, boundary,
		I18n.t("League Review — %s: Pokémon of the Month is %s") % [mname, pom_line],
		_fmt(ROUNDUP_BODIES[b_idx], {"paper": PAPER, "month": mname}),
		{"cat": "media", "sender": "%s — %s" % [_journalist("roundup" + month_key), PAPER],
			"month": month_key, "podium": podium, "totm": totm, "upset": upset,
			"our_won": int(our["won"]), "our_lost": int(our["lost"]),
			"leader": leader, "our_pos": our_pos, "league_n": league_n,
			"pom_quote": pom_quote, "tids": tids})


func _month_name(month_key: String) -> String:
	var names := ["", "January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December"]
	return "%s %s" % [I18n.t(names[int(month_key.split("-")[1])]), month_key.substr(0, 4)]


# ==================================================================== replies

## Apply a reply choice to a people message. Mutates real morale values and
## records the outcome on the message. Returns {note, good}.
func apply_reply(msg: Dictionary, action: Dictionary) -> Dictionary:
	if msg.get("replied", "") != "":
		return {"note": I18n.t("You have already responded to this."), "good": false}
	var choice := str(action.get("reply", ""))
	var uid := str(msg.get("uid", ""))
	var out := {"note": "", "good": true}
	if uid.begins_with("mind:"):
		out = _apply_mind_reply(msg, choice)
	elif uid.begins_with("monlow:"):
		out = _apply_unhappy_reply(msg, choice)
	elif uid.begins_with("monstar:"):
		out = _apply_star_reply(msg, choice)
	msg["replied"] = choice
	msg["reply_note"] = str(out["note"])
	msg["reply_good"] = bool(out["good"])
	msg["urgent"] = false
	GameState.save_game()
	return out


func _pick_reply_line(bank: Array, salt: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.career_seed + absi(salt.hash())
	return I18n.t(str(bank[rng.randi_range(0, bank.size() - 1)]))


func _apply_mind_reply(msg: Dictionary, choice: String) -> Dictionary:
	var pc: Dictionary = GameState.player_club()
	var opp: Dictionary = GameState.club(str(msg.get("opp_id", "")))
	var opp_name := str(opp.get("manager", I18n.t("the rival manager")))
	var salt := "reply" + str(msg.get("fid", ""))
	match choice:
		"fire":
			var rng := RandomNumberGenerator.new()
			rng.seed = GameState.career_seed + absi(salt.hash())
			if rng.randf() < 0.65:
				_shift_squad_morale(pc, 3)
				return {"note": _pick_reply_line(REPLY_FIRE_GOOD, salt + "fg"), "good": true}
			_shift_squad_morale(pc, -2)
			return {"note": _pick_reply_line(REPLY_FIRE_BAD, salt + "fb"), "good": false}
		"calm":
			_shift_squad_morale(pc, 1)
			return {"note": _fmt(_pick_reply_line(REPLY_CALM, salt + "c"), {"mgr": opp_name}), "good": true}
		_:
			return {"note": _pick_reply_line(REPLY_NONE, salt + "n"), "good": true}


func _apply_unhappy_reply(msg: Dictionary, choice: String) -> Dictionary:
	var inst := GameState.squad_member(str(msg.get("mon_uid", "")))
	if inst.is_empty():
		return {"note": I18n.t("That battler is no longer at the club."), "good": false}
	var before := int(inst.get("morale", 70))
	var salt := "unhappy" + str(msg.get("uid", ""))
	match choice:
		"promise":
			inst["morale"] = mini(100, before + 8)
			var deadline := Season.date_add(GameState.current_date, PLEDGE_DAYS)
			# a REAL pledge: tracked, deadlined, enforced by _check_pledges()
			msg["pledge"] = {"mon_uid": str(msg.get("mon_uid", "")),
				"made_on": GameState.current_date, "deadline": deadline,
				"target": PLEDGE_TARGET, "status": "open"}
			return {"note": _fmt(_pick_reply_line(REPLY_PROMISE, salt),
				{"name": news.display_name(inst), "target": PLEDGE_TARGET,
					"deadline": I18n.pretty_date(deadline),
					"b": before, "a": int(inst["morale"])}), "good": true}
		_:
			inst["morale"] = maxi(0, before - 5)
			return {"note": _fmt(_pick_reply_line(REPLY_PATIENT, salt),
				{"name": news.display_name(inst), "b": before, "a": int(inst["morale"])}), "good": false}


func _apply_star_reply(msg: Dictionary, choice: String) -> Dictionary:
	var inst := GameState.squad_member(str(msg.get("mon_uid", "")))
	if inst.is_empty():
		return {"note": I18n.t("That battler is no longer at the club."), "good": false}
	var before := int(inst.get("morale", 70))
	var salt := "star" + str(msg.get("uid", ""))
	match choice:
		"praise":
			inst["morale"] = mini(100, before + 4)
			return {"note": _fmt(_pick_reply_line(REPLY_PRAISE, salt),
				{"name": news.display_name(inst), "b": before, "a": int(inst["morale"])}), "good": true}
		_:
			inst["morale"] = maxi(0, before - 1)
			return {"note": _fmt(_pick_reply_line(REPLY_GROUNDED, salt),
				{"name": news.display_name(inst), "b": before, "a": int(inst["morale"])}), "good": true}


func _shift_squad_morale(pc: Dictionary, delta: int) -> void:
	for inst in pc["squad"]:
		inst["morale"] = clampi(int(inst.get("morale", 70)) + delta, 0, 100)


# ==================================================================== render

## -> {"bbcode": String, "actions": Array, "banner": Dictionary}
func render(msg: Dictionary) -> Dictionary:
	var uid := str(msg.get("uid", ""))
	if uid.begins_with("mind:"):
		return _render_mind(msg)
	if uid.begins_with("press:"):
		return _render_press(msg)
	if uid.begins_with("monlow:"):
		return _render_unhappy(msg)
	if uid.begins_with("monstar:"):
		return _render_star(msg)
	if uid.begins_with("pledge:"):
		return _render_pledge(msg)
	if uid.begins_with("roundup:"):
		return _render_roundup(msg)
	return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))],
		"actions": [], "banner": {}}


func _reply_block(msg: Dictionary) -> String:
	if msg.get("replied", "") == "":
		return ""
	var col := C_GOOD if msg.get("reply_good", true) else C_WARN
	return I18n.t("\n[color=#%s][b]YOUR RESPONSE[/b][/color]\n[color=#%s]%s[/color]\n") % \
		[C_DIM, col, str(msg.get("reply_note", ""))]


# ------------------------------------------------------------- mind-games

func _render_mind(msg: Dictionary) -> Dictionary:
	var f := _fixture(str(msg.get("fid", "")))
	var opp: Dictionary = GameState.club(str(msg.get("opp_id", "")))
	if f.is_empty() or opp.is_empty():
		return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))], "actions": [], "banner": {}}
	var pc: Dictionary = GameState.player_club()
	var we_home: bool = GameState.is_player_club(f["home"])
	var comp_line: String = ("%s · %s" % [I18n.t(GameState.world["meta"]["league_name"]), I18n.t("Matchday %d") % int(f["round"])]) \
		if str(f["comp"]) == "league" else ("%s · %s" % [I18n.t("Indigo Cup"), I18n.cup_round(int(f["round"]))])

	# facts as they stood at publication — snapshotted, never recomputed
	var facts: Dictionary = msg.get("facts", {})
	var our_form: Array
	var their_form: Array
	var morale: int
	var opp_pos_text: String
	if facts.is_empty():   # legacy message from an older save
		our_form = Season.club_form(str(pc["id"]), GameState.fixtures, 5)
		their_form = Season.club_form(str(opp["id"]), GameState.fixtures, 5)
		morale = _avg_squad_morale(pc)
		opp_pos_text = _pos_text(str(opp["id"]))
	else:
		our_form = facts.get("our_form", [])
		their_form = facts.get("their_form", [])
		morale = int(facts.get("morale", 70))
		opp_pos_text = str(facts.get("their_pos_text", I18n.t("unranked")))

	var bb := "[color=#%s]%s · %s · %s[/color]\n\n" % \
		[C_DIM, comp_line, I18n.pretty_date(str(f["date"])), I18n.t("we host") if we_home else I18n.t("we travel")]
	bb += I18n.t("[color=#%s]Speaking to %s ahead of the tie, [b]%s[/b] (%s, %s, reputation %d/20) went on the record:[/color]\n\n") % \
		[C_WHITE, PAPER, opp["manager"], opp["name"], opp_pos_text, int(opp["reputation"])]
	bb += "[color=#%s][b]\"%s\"[/b][/color]\n\n" % [C_ACC, str(msg.get("quote", ""))]

	var facts_hdr := I18n.t("THE FACTS")
	if facts.has("as_of"):
		facts_hdr = I18n.t("THE FACTS — at publication, %s") % I18n.pretty_date(str(facts["as_of"]))
	bb += "[color=#%s][b]%s[/b][/color]\n" % [C_DIM, facts_hdr]
	bb += I18n.t("[color=#%s]%s form:[/color]  %s\n") % [C_DIM, pc["short"], _form_bb(our_form)]
	bb += I18n.t("[color=#%s]%s form:[/color]  %s\n") % [C_DIM, opp["short"], _form_bb(their_form)]
	bb += I18n.t("[color=#%s]Squad morale:[/color] [color=#%s][b]%d/100[/b][/color]\n") % \
		[C_DIM, C_GOOD if morale >= 75 else (C_WARN if morale >= 55 else C_BAD), morale]

	if f.get("played", false):
		var us := int(f["score_home"] if we_home else f["score_away"])
		var them := int(f["score_away"] if we_home else f["score_home"])
		bb += I18n.t("\n[color=#%s]The match has since been played — we %s %d-%d. The talking is over.[/color]\n") % \
			[C_GOOD if us > them else C_BAD, I18n.t("won") if us > them else I18n.t("lost"), us, them]
	elif msg.get("replied", "") == "":
		bb += I18n.t("\n[color=#%s][b]The press pack wants your response before kick-off. How you answer will reach the dressing room.[/b][/color]\n") % C_WARN
	bb += _reply_block(msg)

	var actions: Array = mind_replies(msg)
	actions.append({"label": I18n.t("Go to Fixture"), "screen": "competition"})
	actions.append({"label": I18n.t("Tactics"), "screen": "tactics"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


func _form_bb(form: Array) -> String:
	if form.is_empty():
		return I18n.t("[color=#%s]no matches yet[/color]") % C_DIM
	var out := ""
	for r in form:
		out += "[color=#%s][b] %s [/b][/color]" % [C_GOOD if str(r) == "W" else C_BAD, I18n.t(str(r))]
	return out


func _avg_squad_morale(pc: Dictionary) -> int:
	var total := 0
	var n := 0
	for inst in pc["squad"]:
		total += int(inst.get("morale", 70))
		n += 1
	return int(round(float(total) / maxi(n, 1)))


# ------------------------------------------------------------- press pieces

func _render_press(msg: Dictionary) -> Dictionary:
	var f := _fixture(str(msg.get("fid", "")))
	if f.is_empty():
		return {"bbcode": "[color=#%s]%s[/color]" % [C_WHITE, str(msg.get("body", ""))], "actions": [], "banner": {}}
	var pc: Dictionary = GameState.player_club()
	var we_home: bool = GameState.is_player_club(f["home"])
	var home: Dictionary = GameState.club(str(f["home"]))
	var away: Dictionary = GameState.club(str(f["away"]))
	var opp: Dictionary = away if we_home else home
	var us := int(f["score_home"] if we_home else f["score_away"])
	var them := int(f["score_away"] if we_home else f["score_home"])
	var won := us > them
	var comp_line: String = ("%s · %s" % [I18n.t(GameState.world["meta"]["league_name"]), I18n.t("Matchday %d") % int(f["round"])]) \
		if str(f["comp"]) == "league" else ("%s · %s" % [I18n.t("Indigo Cup"), I18n.cup_round(int(f["round"]))])

	var bb := I18n.t("[color=#%s][i]An opinion piece in %s.[/i][/color]\n\n") % [C_DIM, PAPER]
	var prose := str(msg.get("prose", ""))
	if prose == "":
		prose = _legacy_press_prose(msg, f, pc, opp, us, them)
	bb += "[color=#%s]%s[/color]\n\n" % [C_WHITE, prose]

	# the real star of the tie, from the deterministic replay
	var star := _fixture_star(f, 0 if we_home else 1)
	if not star.is_empty():
		bb += I18n.t("[color=#%s][b]%s OF THE MATCH[/b][/color]\n") % [C_DIM, I18n.t("STAR") if won else I18n.t("ONE BRIGHT SPOT")]
		bb += I18n.t("[color=#%s][b]%s[/b][/color] [color=#%s](%s) — %d KO%s, %d damage across %d battle%s. Match rating [/color][color=#%s][b]%s[/b][/color]\n\n") % \
			[C_ACC, star["name"], C_DIM, star["species"], star["kos"], "" if int(star["kos"]) == 1 else "s",
			star["dmg"], star["battles"], "" if int(star["battles"]) == 1 else "s",
			C_GOOD if float(star["rating"]) >= 7.5 else C_WHITE, I18n.decimal(float(star["rating"]), 1)]

	# table position at publication time (snapshotted; legacy falls back live)
	var pos := int(msg.get("pos_at_pub", -1))
	if pos < 0:
		pos = GameState.player_table_position()
	if pos > 0 and str(f["comp"]) == "league":
		bb += I18n.t("[color=#%s]%s sat [b]%s[/b] in the %s as this went to print.[/color]\n") % \
			[C_DIM, pc["short"], _ordinal(pos), I18n.t(GameState.world["meta"]["league_name"])]
	bb += "\n[color=#%s]— %s[/color]" % [C_DIM, str(msg.get("sender", PAPER))]

	return {"bbcode": bb,
		"actions": [{"label": I18n.t("Go to Fixture"), "screen": "competition"},
			{"label": I18n.t("View Squad"), "screen": "squad"}],
		"banner": {"home": home["name"], "away": away["name"],
			"sh": int(f["score_home"]), "sa": int(f["score_away"]),
			"comp": comp_line + " · " + I18n.pretty_date(str(f["date"])), "won": won}}


## Pre-variant saves stored no prose — reproduce the original single templates.
func _legacy_press_prose(msg: Dictionary, f: Dictionary, pc: Dictionary, opp: Dictionary,
		us: int, them: int) -> String:
	match str(msg.get("press_kind", "")):
		"champions":
			return I18n.t("They will sing about this one for years. [b]%s[/b] beat %s %d-%d in the Indigo Cup Final and the trophy is theirs. Whatever happens in the league now, this season is already immortal.") % \
				[pc["name"], opp["name"], us, them]
		"upset":
			return I18n.t("Nobody outside the %s dressing room saw this coming. A club with a reputation of %d/20 dismantling [b]%s[/b] (%d/20) by %d-%d is the kind of result that changes how a league talks about you. %s's side played without fear — and the giants blinked first.") % \
				[pc["short"], int(pc["reputation"]), opp["name"], int(opp["reputation"]), us, them, pc["manager"]]
		"cupwin":
			return I18n.t("The cup run is alive. [b]%s[/b] saw off %s %d-%d in the %s, and the draw for the %s suddenly matters a great deal in this corner of the league.") % \
				[pc["name"], opp["name"], us, them, I18n.cup_round_prose(int(f["round"])),
				I18n.cup_round_prose(int(f["round"]) + 1)]
		"streak":
			return I18n.t("[b]%d wins in a row.[/b] Streaks like this are not luck — they are structure, squad depth and a dugout that trusts itself. %s made it %d straight by beating %s %d-%d, and the chasing pack has noticed.") % \
				[int(msg.get("streak", 3)), pc["name"], int(msg.get("streak", 3)), opp["name"], us, them]
		_:
			return I18n.t("There is no dressing this up. [b]%s[/b] (reputation %d/20) were beaten %d-%d by %s (%d/20) — a side they were built, budgeted and expected to beat. Questions travel fast in this league, and today they are all pointed at %s's office.") % \
				[pc["name"], int(pc["reputation"]), them, us, opp["name"], int(opp["reputation"]), pc["manager"]]


## Best-rated battler in a fixture replay; side -1 = either side.
func _fixture_star(f: Dictionary, side: int) -> Dictionary:
	var d: Dictionary = Season.fixture_detail(f)
	if d.is_empty():
		return {}
	var best := {}
	var best_r := 0.0
	var players: Dictionary = d["players"]
	for puid in players:
		var p: Dictionary = players[puid]
		if side >= 0 and int(p["side"]) != side:
			continue
		var r: float = float(p["rating_sum"]) / maxi(int(p["battles"]), 1)
		if r > best_r:
			best_r = r
			best = {"name": str(p["name"]), "species": str(p["species"]), "kos": int(p["kos"]),
				"dmg": int(p["dmg"]), "battles": int(p["battles"]), "rating": snappedf(r, 0.01)}
	return best


# ------------------------------------------------------------- coach notes

func _render_unhappy(msg: Dictionary) -> Dictionary:
	var inst := GameState.squad_member(str(msg.get("mon_uid", "")))
	if inst.is_empty():
		return {"bbcode": I18n.t("[color=#%s]That battler has since left the club — the matter is closed.[/color]") % C_DIM,
			"actions": [{"label": I18n.t("View Squad"), "screen": "squad"}], "banner": {}}
	var apps := int(msg.get("apps", 0))
	var cm := int(msg.get("club_matches", 0))
	var morale := int(inst.get("morale", 70))
	var prose := str(msg.get("prose", ""))
	if prose == "":   # legacy message
		prose = I18n.t("Boss — a quiet word before this becomes a loud one. [b]%s[/b] (%s, Lv %d) has featured in [b]%d of our %d[/b] matches this season. The mood around the training pens is turning: less appetite in drills, snapping at the younger battlers. In my experience this only goes one way if it's left alone.") % \
			[news.display_name(inst), inst["species"], int(inst["level"]), apps, cm]
	var bb := "[color=#%s]%s[/color]\n\n" % [C_WHITE, prose]
	bb += I18n.t("[color=#%s][b]CURRENT MORALE[/b][/color]  [color=#%s][b]%d/100[/b][/color]     [color=#%s][b]CONDITION[/b][/color]  [color=#%s]%d[/color]     [color=#%s][b]WAGES[/b][/color]  [color=#%s]%s / mo[/color]\n\n") % \
		[C_DIM, C_BAD if morale < 60 else C_WARN, morale,
		C_DIM, C_WHITE, int(inst.get("condition", 100)),
		C_DIM, C_WHITE, news.money(int(inst["contract"]["salary"]))]
	bb += _pledge_status_block(msg, inst)
	if msg.get("replied", "") == "":
		if bool(msg.get("urgent", false)):
			bb += I18n.t("[color=#%s][b]They are waiting on a message from you. What do I tell them?[/b][/color]\n") % C_WARN
		else:
			bb += I18n.t("[color=#%s]You let it slide — the mood in the gym cooled on its own, but the coach noted your silence.[/color]\n") % C_DIM
	bb += _reply_block(msg)

	var actions: Array = []
	if msg.get("replied", "") == "" and bool(msg.get("urgent", false)):
		actions = [
			{"kind": "reply", "reply": "promise", "style": "good", "label": I18n.t("Promise More Battles (+morale, tracked)")},
			{"kind": "reply", "reply": "patient", "style": "bad", "label": I18n.t("Tell Them to Earn It (-morale)")},
		]
	actions.append({"label": I18n.t("View Squad"), "screen": "squad"})
	actions.append({"label": I18n.t("Training"), "screen": "training"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


## Live status of a promised-battles pledge on its originating message.
func _pledge_status_block(msg: Dictionary, inst: Dictionary) -> String:
	var pl_v: Variant = msg.get("pledge", {})
	if not (pl_v is Dictionary) or (pl_v as Dictionary).is_empty():
		return ""
	var pl: Dictionary = pl_v
	var target := int(pl.get("target", PLEDGE_TARGET))
	match str(pl.get("status", "")):
		"open":
			var pc: Dictionary = GameState.player_club()
			var upto := str(pl["deadline"]) if str(pl["deadline"]) < GameState.current_date else GameState.current_date
			var so_far := _appearance_dates(str(pc["id"]), str(pl["mon_uid"]), str(pl["made_on"]), upto).size()
			return I18n.t("[color=#%s][b]PLEDGE OPEN[/b][/color]  [color=#%s]You promised [b]%d battles by %s[/b]. Progress: [b]%d of %d[/b]. Break it and the whole squad will know.[/color]\n\n") % \
				[C_WARN, C_WHITE, target, I18n.pretty_date(str(pl["deadline"])), so_far, target]
		"kept":
			return I18n.t("[color=#%s][b]PLEDGE KEPT[/b][/color]  [color=#%s]%s got the promised battles (%d of %d) by %s.[/color]\n\n") % \
				[C_GOOD, C_WHITE, news.display_name(inst), int(pl.get("apps", target)), target,
				I18n.pretty_date(str(pl.get("resolved_on", pl["deadline"])))]
		"broken":
			return I18n.t("[color=#%s][b]PLEDGE BROKEN[/b][/color]  [color=#%s]Only %d of the %d promised battles arrived before %s. The squad remembers.[/color]\n\n") % \
				[C_BAD, C_WHITE, int(pl.get("apps", 0)), target, I18n.pretty_date(str(pl["deadline"]))]
		"void":
			return I18n.t("[color=#%s]The pledge dissolved when the battler left the club.[/color]\n\n") % C_DIM
	return ""


func _render_star(msg: Dictionary) -> Dictionary:
	var inst := GameState.squad_member(str(msg.get("mon_uid", "")))
	if inst.is_empty():
		return {"bbcode": I18n.t("[color=#%s]That battler has since left the club.[/color]") % C_DIM,
			"actions": [{"label": I18n.t("View Squad"), "screen": "squad"}], "banner": {}}
	var rating := float(msg.get("rating", 7.0))
	var prose := str(msg.get("prose", ""))
	if prose == "":   # legacy message
		prose = I18n.t("Boss — thought you'd want this one in writing. [b]%s[/b] (%s, Lv %d) has been outstanding. Across the last [b]%d[/b] matches: [b]%d KOs[/b] and an average match rating of [b]%s[/b]. Technique, timing, temperament — everything we drill is showing up on matchday.") % \
			[news.display_name(inst), inst["species"], int(inst["level"]),
			int(msg.get("recent_n", 3)), int(msg.get("recent_kos", 0)), I18n.decimal(rating, 2)]
	var bb := "[color=#%s]%s[/color]\n\n" % [C_WHITE, prose]
	bb += I18n.t("[color=#%s][b]CURRENT MORALE[/b][/color]  [color=#%s][b]%d/100[/b][/color]     [color=#%s][b]FITNESS[/b][/color]  [color=#%s]%d[/color]\n\n") % \
		[C_DIM, C_GOOD, int(inst.get("morale", 70)), C_DIM, C_WHITE, int(inst.get("fitness", 100))]
	if msg.get("replied", "") == "":
		bb += I18n.t("[color=#%s]Development like this deserves a word from the manager — your call how loud that word is.[/color]\n") % C_DIM
	bb += _reply_block(msg)

	var actions: Array = []
	if msg.get("replied", "") == "":
		actions = [
			{"kind": "reply", "reply": "praise", "style": "good", "label": I18n.t("Pass On Your Praise (+morale)")},
			{"kind": "reply", "reply": "grounded", "style": "warn", "label": I18n.t("Keep Them Grounded")},
		]
	actions.append({"label": I18n.t("View Squad"), "screen": "squad"})
	return {"bbcode": bb, "actions": actions, "banner": {}}


# ------------------------------------------------------------- pledge follow-ups

func _render_pledge(msg: Dictionary) -> Dictionary:
	var kept := bool(msg.get("pledge_kept", false))
	var bb := "[color=#%s]%s[/color]\n\n" % [C_WHITE, str(msg.get("prose", msg.get("body", "")))]
	bb += I18n.t("[color=#%s][b]THE PLEDGE[/b][/color]  [color=#%s]%d battles promised on %s, deadline %s — [b]%d delivered[/b].[/color]\n") % \
		[C_DIM, C_WHITE, int(msg.get("target", PLEDGE_TARGET)),
		I18n.pretty_date(str(msg.get("made_on", ""))),
		I18n.pretty_date(str(msg.get("deadline", ""))), int(msg.get("apps", 0))]
	bb += I18n.t("[color=#%s][b]MORALE[/b][/color]  [color=#%s][b]%d » %d[/b][/color]") % \
		[C_DIM, C_GOOD if kept else C_BAD, int(msg.get("morale_before", 70)), int(msg.get("morale_after", 70))]
	if not kept:
		bb += I18n.t("  [color=#%s](and a knock across the rest of the squad — word travels)[/color]") % C_DIM
	bb += "\n"
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("View Squad"), "screen": "squad"},
			{"label": I18n.t("Training"), "screen": "training"}], "banner": {}}


# ------------------------------------------------------------- monthly column

func _render_roundup(msg: Dictionary) -> Dictionary:
	var mname := _month_name(str(msg.get("month", "")))
	var bb := I18n.t("[color=#%s][i]%s's monthly league column.[/i][/color]\n\n") % [C_DIM, PAPER]
	bb += I18n.t("[color=#%s]The books are closed on [b]%s[/b] — %d league matchdays of it. Here is how the month will be remembered.[/color]\n\n") % \
		[C_WHITE, mname, int(msg.get("league_n", 0))]

	# --- Pokémon of the Month podium (real replay ratings)
	var podium: Array = msg.get("podium", [])
	if not podium.is_empty():
		bb += I18n.t("[color=#%s][b]POKÉMON OF THE MONTH[/b][/color]\n") % C_WARN
		var medals := [I18n.t("1st"), I18n.t("2nd"), I18n.t("3rd")]
		for i in podium.size():
			var p: Dictionary = podium[i]
			var name_col := C_ACC if bool(p.get("mine", false)) else C_WHITE
			bb += I18n.t("[color=#%s]%s[/color]  [color=#%s][b]%s[/b][/color] [color=#%s](%s, %s) — %d battles, %d KOs, %d dmg · avg rating [/color][color=#%s][b]%s[/b][/color]%s\n") % \
				[C_DIM, medals[i], name_col, str(p["name"]), C_DIM, str(p["species"]), str(p["club"]),
				int(p["battles"]), int(p["kos"]), int(p["dmg"]),
				C_GOOD if float(p["rating"]) >= 7.0 else C_WHITE, I18n.decimal(float(p["rating"]), 2),
				I18n.t("  [color=#%s][b]« OURS[/b][/color]") % C_GOOD if bool(p.get("mine", false)) else ""]
		var w: Dictionary = podium[0]
		var pom_quote := str(msg.get("pom_quote", ""))
		if pom_quote == "":   # legacy message
			pom_quote = I18n.t("%s was simply a level above everything else on the circuit this month.") % str(w["name"])
		bb += "[color=#%s]\"%s\"[/color]\n\n" % [C_DIM, pom_quote]

	# --- Team of the Month
	var totm: Dictionary = msg.get("totm", {})
	if not totm.is_empty():
		var mine: bool = GameState.is_player_club(str(totm.get("club_id", "")))
		bb += I18n.t("[color=#%s][b]TEAM OF THE MONTH[/b][/color]  [color=#%s][b]%s[/b][/color] [color=#%s](%d-%d in the league)%s[/color]\n") % \
			[C_WARN, C_ACC if mine else C_WHITE, str(totm["club"]), C_DIM,
			int(totm["won"]), int(totm["lost"]), I18n.t(" — yes, YOUR team") if mine else ""]

	# --- upset of the month
	var upset: Dictionary = msg.get("upset", {})
	if not upset.is_empty():
		bb += I18n.t("[color=#%s][b]SHOCK OF THE MONTH[/b][/color]  [color=#%s]%s toppling %s (%s, %s) — a %d-point reputation gap bridged in an afternoon.[/color]\n") % \
			[C_WARN, C_WHITE, str(upset["winner"]), str(upset["loser"]), str(upset["score"]),
			I18n.pretty_date(str(upset["date"])), int(upset["gap"])]

	# --- the state of the race + our month
	bb += I18n.t("\n[color=#%s][b]THE TABLE[/b][/color]  [color=#%s][b]%s[/b] led the league as the month closed") % \
		[C_DIM, C_WHITE, str(msg.get("leader", "?"))]
	var our_pos := int(msg.get("our_pos", 0))
	if our_pos > 0:
		bb += I18n.t("; %s sat [b]%s[/b]") % [GameState.player_club()["short"], _ordinal(our_pos)]
	bb += ".[/color]\n"
	var ow := int(msg.get("our_won", 0))
	var ol := int(msg.get("our_lost", 0))
	var our_col := C_GOOD if ow > ol else (C_WARN if ow == ol else C_BAD)
	bb += I18n.t("[color=#%s][b]OUR MONTH[/b][/color]  [color=#%s][b]%d won, %d lost[/b] in the league — %s.[/color]\n") % \
		[C_DIM, our_col, ow, ol,
		I18n.t("a month to build on") if ow > ol else (I18n.t("honours even") if ow == ol else I18n.t("a month to forget"))]
	bb += "\n[color=#%s]— %s[/color]" % [C_DIM, str(msg.get("sender", PAPER))]
	return {"bbcode": bb,
		"actions": [{"label": I18n.t("League Table"), "screen": "competition"},
			{"label": I18n.t("View Squad"), "screen": "squad"}], "banner": {}}


# ==================================================================== helpers

func _fixture(fid: String) -> Dictionary:
	if fid == "":
		return {}
	for f in GameState.fixtures:
		if str(f["id"]) == fid:
			return f
	return {}


func _pos_text(club_id: String) -> String:
	var t: Array = GameState.league_table()
	for i in t.size():
		if str(t[i]["club_id"]) == club_id:
			if int(t[i]["played"]) == 0:
				return I18n.t("yet to play in the league")
			return I18n.t("%s in the league") % _ordinal(i + 1)
	return I18n.t("unranked")


func _ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	return I18n.ordinal(n)
