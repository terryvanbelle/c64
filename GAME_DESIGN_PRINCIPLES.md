# Game design principles

Research reviewed: **2026-10-14**. A working reference for designing, evaluating,
and improving computer games, with applications to this repository's stock C64
projects. Pair it with [TIPS_AND_TRICKS.md](TIPS_AND_TRICKS.md) for implementation
and hardware constraints.

A good design gives its intended players a worthwhile experience through actions
they can understand, consequences they can interpret, and situations worth
returning to. The intended experience can be tactical tension, discovery,
mastery, cooperation, expression, comedy, contemplation, or beauty. Choose the
experience before choosing which design advice to apply.

The sections below combine original designer writing, developer case studies,
academic models, and official accessibility guidance. A practitioner technique
is an option to investigate; a research association is evidence within its
studied setting; a platform guideline is a useful inclusion reference. None is a
formula guaranteeing enjoyment. The C64 applications, example experiments, and
working checklists are our synthesis. They should evolve with player feedback.

## Contents

1. [Practical defaults](#practical-defaults)
2. [Player experience and design pillars](#player-experience-and-design-pillars)
3. [Useful design models](#useful-design-models)
4. [Core loops and meaningful decisions](#core-loops-and-meaningful-decisions)
5. [Controls and game feel](#controls-and-game-feel)
6. [Information and readability](#information-and-readability)
7. [Learning and onboarding](#learning-and-onboarding)
8. [Difficulty failure and forgiveness](#difficulty-failure-and-forgiveness)
9. [Counterplay and balance](#counterplay-and-balance)
10. [Computer opponents](#computer-opponents)
11. [Randomness and procedural generation](#randomness-and-procedural-generation)
12. [Level and spatial design](#level-and-spatial-design)
13. [Pacing and match endings](#pacing-and-match-endings)
14. [Progression rewards and economies](#progression-rewards-and-economies)
15. [Art sound and narrative](#art-sound-and-narrative)
16. [Accessibility and player options](#accessibility-and-player-options)
17. [Prototyping and scope](#prototyping-and-scope)
18. [Playtesting and iteration](#playtesting-and-iteration)
19. [Measurement and evidence](#measurement-and-evidence)
20. [Respect for player time and trust](#respect-for-player-time-and-trust)
21. [Applying the principles to C64 games](#applying-the-principles-to-c64-games)
22. [Ironveil design review](#ironveil-design-review)
23. [Genre specific priorities](#genre-specific-priorities)
24. [Common symptoms and possible causes](#common-symptoms-and-possible-causes)
25. [Working templates and checklists](#working-templates-and-checklists)
26. [Glossary](#glossary)
27. [Sources and further reading](#sources-and-further-reading)

## Practical defaults

Use these defaults at the start of a small project, then adjust them to its genre
and audience:

1. **Name the experience.** Describe what the player should feel and do in one
   sentence. Select a few priorities that can resolve feature disagreements.
2. **Make a small complete loop playable early.** Include an action, a
   consequence, feedback, and a reason to make another decision.
3. **Make the repeated action understandable.** A player should be able to act
   intentionally before being asked to combine several difficult tasks.
4. **Put depth in the intended challenge.** A tactical game can have simple
   movement and difficult positioning. A driving simulation can make vehicle
   handling central. Decide which demands belong.
5. **Give the player useful information.** Communicate current state, relevant
   options, and consequential changes. Preserve uncertainty when it serves the
   game, with cues that explain the uncertainty.
6. **Make competing choices useful in different circumstances.** Investigate
   options that are always superior, never worth considering, or costly only
   because the interface is inconvenient.
7. **Let mistakes teach.** Make causes legible, allow another attempt at a
   sensible cost, and give the player a plausible improvement to try.
8. **Design the opponent's experience too.** Powerful actions need appropriate
   warnings, vulnerabilities, escape routes, or strategic answers.
9. **Give each system a purpose.** Added features create interactions, learning
   demands, art requirements, and failure cases as well as possibilities.
10. **Test with unfamiliar players.** Observe their actions before explaining
    the design. Compare their understanding and enjoyment with the brief.
11. **Separate correctness from quality of play.** Successful execution, valid
    maps, and reliable AI are necessary engineering evidence. Enjoyment,
    readability, trust, and willingness to replay need player evidence.
12. **Finish the surrounding experience.** Setup, pause, loss, retry, rematch,
    and exit affect how much worthwhile play a session actually contains.

When two defaults conflict, write the tradeoff and test alternatives. Examples
include clarity versus mystery, forgiveness versus exact execution, competitive
consistency versus dramatic surprises, and short retries versus a survival
experience in which loss carries weight.

## Player experience and design pillars

### Write a usable brief

An experience brief should identify the audience, the activity, the feeling,
and the constraints. It should guide a real choice during development.

Weak: a large tank game with procedural terrain, impressive effects, and good AI.

More useful: a local tank duel in which players use cover, sound, and positioning
to outwit an opponent; movement is deliberate, aiming is independent, and a
stock C64 presents the essential information clearly.

The second version helps decide whether to spend effort on another terrain type,
a hearing cue, a tutorial, or a spectacular explosion. It also gives playtests a
question: are players making and revising tactical plans?

### Use a few design pillars

Pillars are working priorities, such as:

- Deliberate decisions with readable consequences.
- Discovery through observation and experimentation.
- Expressive movement with a low initial control burden.
- Fair rivalry with useful counterplay.
- Quiet beauty and sustained atmosphere.

Explain what each pillar permits and what it costs. A stealth pillar might
permit imprecise enemy positions while requiring clear visibility rules. A
beauty pillar might favor graceful motion and sparse overlays. A competitive
pillar might require equivalent treatment of identical actions.

Avoid pillars that approve everything, such as high quality or lots of fun.
Useful pillars help defer a feature that would dilute the chosen experience.
They can change when the project changes direction; record why.

### Choose players by needs and context

Specify familiarity with the genre, input device, expected session length,
physical and sensory needs, and whether people play alone or together. A person
can be experienced at strategy while unfamiliar with tank steering. Another can
understand a rule and have difficulty holding several keys simultaneously.

Do not infer preferences from age, gender, or a broad label such as casual.
Recruit people with the relevant experience and access needs, and observe what
actually happens. The same person may seek intense competition one evening and
quiet exploration another.

### Keep the priorities coherent

Ask what each mechanic contributes to the brief. More terrain may support
flanking, but it also changes travel time, navigation, visual texture, and AI
coverage. Longer starting separation may create anticipation while delaying the
first encounter. A marker can reduce disorientation while weakening a hunt if
it reveals too much.

Specify the expected improvement and the possible cost before adding a feature.
This makes a later decision to simplify the feature easier and more reasoned.

## Useful design models

### Mechanics dynamics and aesthetics

Hunicke, LeBlanc, and Zubek's MDA framework distinguishes the implemented rules
and data, the behavior those rules produce during play, and the player's
emotional experience. A small rule change can alter the experience through
interactions with other rules. The authors encourage reasoning from the
experience toward the systems that might produce it, as well as inspecting
what implemented systems actually produce. Their aesthetic vocabulary covers
several kinds of enjoyment, beyond challenge alone. [MDA][mda]

For our own tank example:

| Layer | Example | Question to investigate |
|---|---|---|
| Mechanics | Vegetation limits sightings; driving makes sound; roads are fast | Are the rules reliable and understandable? |
| Dynamics | Players stop to listen, choose detours, or risk a fast crossing | Do people actually use these options? |
| Experience | Suspense, an earned ambush, satisfaction from prediction | Is this the experience players report? |

An accurate cover implementation establishes the first layer. It does not
establish that the other two occurred. A player who waits in confusion for
several minutes may be experiencing a very different result from the intended
suspense.

### Intention and understandable consequences

Doug Church's design vocabulary emphasizes a player's ability to form a plan
using their understanding of the world, then perceive what followed from the
action. An implemented consequence can feel arbitrary if the player cannot
connect it with a choice. Church also discusses the tradeoff between player
control and carefully authored story moments; the tools should suit the desired
experience. [Formal Abstract Design Tools][church]

Use a practical sequence when diagnosing a problem:

1. What did the player want to do?
2. What did they think would happen?
3. What input did they provide?
4. What rule actually ran?
5. What feedback could they perceive?
6. What did they conclude?

For example, an unsuccessful shot can come from wrong aim, a cooldown, a wall,
range limits, a missed input, or a hidden target. Distinguishing those causes is
more useful than immediately increasing damage or weakening the opponent.

### Learning and mastery

Koster's game grammar describes nested interactions from individual controls to
larger objectives, and learning loops through which players develop useful
models of a system. A solved or apparently solved challenge can lose its appeal
for a player seeking mastery. This is a designer's lens, rather than a complete
scientific account of every reason people play. [Game Grammar][koster-grammar]

His later interview distinguishes designing for the discovery of new strategies
from designing for comfort or meditative repetition. That distinction helps
explain why continuous novelty is a poor universal requirement.
[RePlay interview][koster-replay]

For a mastery game, seek new combinations, contexts, opponents, or constraints
that let an existing skill become more expressive. For a contemplative game,
repetition may be welcome when rhythm, variation, and presentation sustain the
chosen mood. Inspect whether an apparent lack of novelty is a problem for the
intended player before expanding the feature list.

### Autonomy competence and relatedness

Ryan, Rigby, and Przybylski's four-study paper reported associations between
perceived autonomy and competence and enjoyment; its multiplayer survey also
linked relatedness with enjoyment and intentions for future play. Intuitive
controls were related to these perceptions. These results support useful questions about
agency, capability, and social connection within the studied games; they do
not prove that adding a particular feature will make a new game enjoyable.
[The Motivational Pull of Video Games][sdt]

Our working questions are:

- **Autonomy:** Can players form a worthwhile plan, express a preference, and
  understand the options available to them?
- **Competence:** Can they recognize improvement, understand setbacks, and
  learn the skills the game expects?
- **Relatedness:** Does social play create opportunities to cooperate,
  acknowledge an opponent, contribute, or share an experience?

A menu with twenty similar choices may offer little practical agency. A system
with two consequential options can offer more. A progress bar can acknowledge
activity while giving weak evidence of improved ability. Evaluate the actual
experience each feature supports.

### GameFlow as a review lens

Sweetser and colleagues organize enjoyment criteria around concentration,
challenge, skills, control, clear goals, feedback, immersion, and social
interaction. Their 2012 RTS work explicitly seeks genre-specific detail because
general criteria can be difficult to implement across very different games.
The RTS heuristics were derived from professional game reviews; the paper
identifies further validation as future work.
The model is useful for finding neglected aspects of an experience, rather
than assigning every game the same ideal pattern. [GameFlow heuristics][gameflow]

A quiet exploration game may intentionally lower workload. A difficult puzzle
may preserve uncertainty about a solution. A local duel may prioritize social
interaction and clear competition. Choose the relevant questions and inspect
their answers together; maximizing each factor independently can create
conflicting demands.

## Core loops and meaningful decisions

### Define the repeated activity

Write the small sequence that generates most of the play. For a hunt, one
possible loop is observe, choose a route, move, update the enemy estimate,
engage or withdraw, and observe again. For a puzzle, it may be inspect, predict,
try, interpret, and revise.

At each step identify:

- The player's goal and available action.
- The information they use.
- The state the action can change.
- The feedback that exposes the change.
- The next choice the change makes possible.

Build that loop with a small amount of representative content. Watch whether
people find another worthwhile action after its first completion. If the loop
requires a reward screen to make every action tolerable, investigate the action
and its consequences before building a larger reward system.

### Support consequential choices

Sid Meier's 2012 session frames gameplay through interesting decisions and
explicitly connects decisions with pacing, information, and feedback. That is
a productive question for strategy design, rather than a definition that
excludes every other kind of play. [Interesting Decisions][meier]

The following decision audit is our working synthesis:

| Property | Useful question |
|---|---|
| Distinct consequences | Will choosing differently plausibly change the situation? |
| Comprehensible stakes | Can the player estimate what they might gain or lose? |
| Context sensitivity | Can different circumstances favor different options? |
| Commitment | Is there some relevant cost, exposure, time, or lost opportunity? |
| Feedback | Can the player connect the result with their decision? |
| Room to improve | Can experience lead to a better future judgment? |

A choice can be interesting with complete information. It can also be
interesting with uncertainty when the player understands the uncertainty and
has ways to investigate or manage it. A completely opaque choice often needs a
different purpose, such as surprise, expression, or narrative discovery.

### Investigate depth and complexity separately

Complexity includes rules, modes, vocabulary, state to remember, and physical
input demands. Depth concerns the useful plans and distinctions those systems
allow over repeated play. Treat both as things to examine, not quantities that
increase together automatically.

Try removing or combining a rule in a prototype. Check what decisions disappear,
what becomes easier to understand, and whether players still distinguish good
and poor plans. A small rule set can contain rich interactions; an extensive
rule set can collapse into a single routine.

Avoid reducing every difference to damage per second or movement speed. Position,
information, commitment, recovery time, resource use, and interaction with the
opponent can create different roles even when simple output values are similar.

### Give expressive choices a place

Some choices concern identity, aesthetic preference, curiosity, or a personal
challenge. They need not be strategic optimizations. A game about arranging a
space can value expression; a competitive game may value a chosen fighting
style; a narrative game may value interpretation.

Describe the function of the choice before evaluating it. A cosmetic choice
should not be presented as a major strategic decision. A story choice needs a
consequence consistent with the promise made to the player, even if that
consequence concerns meaning rather than mechanical advantage.

## Controls and game feel

### Match input to the intended activity

Swink explains that internally consistent input can feel unpredictable when
mappings conflict with expectations, state is unclear, or response is difficult
to perceive. Spatial mappings and prompt feedback can help people understand
what they are controlling. The proper feel depends on the intended experience;
a deliberate response can still be comprehensible. [Principles of Virtual
Sensation][swink-sensation]

For a tank tactics game, map-relative movement lets attention shift toward
positioning and enemy behavior. Hull-relative controls can suit a vehicle
simulation in which steering is itself a major skill. Test the mapping against
the brief and audience, rather than accepting whichever scheme is easiest to
implement.

A command should acknowledge intent promptly even when the object moves slowly.
A visible turn, selected destination, charging animation, or state indicator can
confirm the command. An unexplained delay gives the player little basis for
deciding whether to wait, retry, or change input.

### Tune the action in representative space

Swink's game-feel article considers input, response, context, polish, metaphor,
and rules together. The surrounding geometry helps give movement meaning, and
selected sounds and animation can communicate physical qualities. Polishing a
prototype needs the effects important to its intended feel, not a maximal
collection of effects. [Game Feel The Secret Ingredient][swink-feel]

Create a small action laboratory containing a wall, a narrow passage, open
space, a rough patch, and a fast surface. Tune:

- Start, stop, acceleration, and maximum speed.
- Turning, aiming, reversing, and simultaneous inputs.
- Contact with walls, corners, and another actor.
- Camera behavior near an edge and during direction changes.
- Action acknowledgement, cooldown, impact, and recovery cues.

Include the actual controller and display conditions early. A control tuned by
single-stepping coordinates can behave correctly and still feel unpleasant at
normal speed.

### Decide which manipulation difficulty belongs

Juul and Norton argue that interface and gameplay difficulty do not have a fixed
boundary. Difficult manipulation can be part of an intended game, while the
same game can contain unrelated interface problems. This cautions against a
universal demand for effortless controls. [Easy to Use and Incredibly
Difficult][juul-interface]

Use a demand inventory for the project:

| Demand | Example | Design question |
|---|---|---|
| Decision | Which crossing is worth the risk? | Is this central to the experience? |
| Execution | Can I aim during a turn? | Is the required precision appropriate? |
| Perception | Can I distinguish a shell from scenery? | Is the cue sufficiently legible? |
| Memory | Do I remember the current mode or terrain rule? | Can useful state be shown or revisited? |
| Physical input | Can I hold the required keys together? | Is an alternative available? |

A player struggling to navigate does not automatically need a weaker opponent.
They may need a better mapping, slower motion, clearer state, or practice.
Change the demand that is causing the problem.

### Define collision and movement promises

Thorson's Celeste and TowerFall physics account shows how explicit collider and
movement rules, fractional remainders, and separate carrying/pushing behavior
can support predictable action. It is a particular platformer implementation,
not a universal physics architecture. [Celeste and TowerFall Physics][thorson-physics]

For our projects, state the important promises: what blocks movement, which
part of a sprite represents its body, whether diagonal speed is normalized,
what happens when two actors collide, and whether a shell can pass through
vegetation. A decorative branch may differ from a solid rock, but the distinction
must be learnable. If a rule needs an invisible collider, expose its effect
consistently enough for the player to make sensible predictions.

## Information and readability

### Set an information contract

List the facts a player knows exactly, approximately, after a delay, and only
through inference. This is especially useful for stealth, exploration, deduction,
and competitive games.

| Information | Possible treatment | Important distinction |
|---|---|---|
| Own position and health | Exact, continuously available | Basic self-control state |
| A visible opponent | Exact within the visibility rules | Observation |
| A concealed opponent | Sector, old position, or rough bearing | Estimate |
| A moving engine | Presence and proximity band | Hearing |
| A chosen route | Known terrain plus unobserved risks | Planning uncertainty |

Communicate age and precision when they affect a decision. A delayed estimate
should not look identical to a current exact lock. Decide what happens when a
contact becomes unavailable. Apply the same contract to cameras, markers,
sound, status strips, AI observations, and result screens.

### Build a visual hierarchy

Competitive decisions need the relevant scene to remain readable. Separate
actors, hazards, interactive terrain, decorative terrain, and interface elements
through shape, motion, value contrast, placement, and timing. The most attractive
texture should not make the most important object disappear accidentally.

For each display element, ask what decision it supports and how quickly it must
be recognized. A health change during combat needs different presentation from
a settings explanation. Put long explanations where people can read them
without sacrificing active play space.

Microsoft's contrast guidance recommends sufficient contrast and ways to keep
important elements readable against changing backgrounds. Its modern-platform
ratios and size definitions do not guarantee legibility on a C64 television.
[Xbox contrast guidance][xag102]

For retro displays, inspect actual sprite size, blurred output, viewing distance,
and busy terrain. A numerically distinct palette index is weak evidence that a
player can distinguish two objects during motion.

### Make cues consistent and appropriately redundant

Microsoft recommends additional sensory channels for important visual or audio
information, and another signifier for information otherwise conveyed solely by
color. Multiple visual cues still do not establish accessibility without vision.
[Xbox additional cue guidance][xag103]

Use a small event vocabulary. A hit, blocked shot, selected menu item, detected
contact, and destroyed tank should have distinguishable responses. Combine
cues where useful, while keeping their information content consistent.

A visual alternative to an engine sound should reveal the same kind of rough
hearing information. It should not expose an exact enemy coordinate that the
sound does not communicate. Similarly, a terrain pattern can reinforce a color
without changing its gameplay meaning.

### Preserve useful ambiguity

Mystery can concern the enemy's plan or location while the player understands
what their own controls and sensors do. Decide what the player is meant to
infer. Avoid making every uncertainty an unexplained malfunction.

One practical test is to ask players what they believe is happening before
revealing the answer. If they form plausible competing explanations, the
uncertainty may be productive. If they believe the program is broken or cannot
name any action to investigate, inspect the cues and available experiments.

## Learning and onboarding

### Teach skills through action and consequence

Cook's skill-atom model links action, simulation, feedback, and the player's
updated mental model. Chains of prerequisite skills help identify where a
newcomer can become blocked, or where an experienced player is made to repeat
already mastered material. Treat this as a diagnostic model without adopting
the essay's broader biological claims as established neuroscience.
[The Chemistry of Game Design][cook]

Write a dependency chain for the game. For a tank duel it might be intentional
movement, separate aiming, firing, recognizing a hit, using cover, then planning
a flank. Introduce the next skill when the player has enough understanding to
use it.

A controls chart helps recall. It cannot demonstrate that the player can move,
aim, fire, or interpret an outcome. Provide a safe experiment, demonstration,
or practice encounter for essential relations.

### Sequence introduction and combination

A useful working pattern is introduce a relation in a low-pressure situation,
let the player try it, vary its context, combine it with something familiar,
then challenge its application. This pattern is a design proposal, not a
mandatory level structure.

Examples:

- Let a moving enemy reveal its engine before asking the player to locate an
  unseen one by hearing.
- Show the same tank on an exposed road and in vegetation before expecting
  knowledge of camouflage.
- Use one clear route choice before a battlefield with several ambiguous routes.
- Let players discover a projectile's travel time before requiring leading shots.

A tutorial should teach the final game's rules. If practice uses altered rules,
make that alteration apparent. A skill learned through misleading feedback can
be costly to unlearn.

### Offer guidance at a useful moment

Microsoft's objective-clarity guidance supports revisiting objectives and
progress, optional directional assistance, and interactive or demonstrated
learning that can be revisited. It distinguishes a static control chart from
a tutorial. [Xbox objective clarity guidance][xag109]

Keep essential goals available, but let optional help respect discovery. A
hint can move through levels of specificity: remind the goal, identify a relevant
rule, suggest an experiment, then offer an explicit action if requested. Repeating
the full solution immediately can remove the activity the game promised.

Let experienced players skip introductory practice, and let newcomers return
to it. Observe whether players can use what was taught in a slightly changed
situation; memorizing a tutorial sequence is weaker evidence of understanding.

## Difficulty failure and forgiveness

### Identify the source of difficulty

Difficulty can come from reaction speed, precision, information, planning depth,
resource pressure, opponent skill, memory, or physical demands. A single preset
can change several of these in ways a player does not expect.

Microsoft recommends descriptive difficulty options and considers independent
adjustments because different players encounter different barriers. Its guidance
also addresses changing difficulty without losing progress and access to pause.
[Xbox game difficulty guidance][xag108]

For our projects, explain what Easy, Medium, and Hard change. A stronger planner,
shorter reaction delay, more accurate aim, and extra health have different
meanings. A player who needs direct navigation may still want demanding tactics.
An assist should address the barrier identified in play, rather than assuming
that every request means the player wants to win more easily.

### Tune failure cost separately

Juul distinguishes failing from its punishment, including lost energy, lives,
progress, and opportunities to retry. His prototype study supports investigating
how players attribute failure. It does not establish a universally ideal success
rate: the overall rating-versus-performance comparison reported p = 0.06,
and its sample and single-player setting limit generalization.
[Fear of Failing][juul-failure]

Measure the time and effort between a mistake and the next meaningful attempt.
Consider loading, repeated menus, travel to the encounter, mandatory dialogue,
and lost progress as part of that cost. A demanding action can have a fast retry;
a survival game can deliberately make loss consequential. Choose the burden
that serves the experience and teach the stakes before imposing it.

After a loss, ask what the player believes could have worked differently. Useful
answers can involve decisions, execution, preparation, or new knowledge. A vague
belief that the game randomly refused an action calls for a different diagnosis.

### Use forgiveness deliberately

Thorson documents small timing and position allowances in Celeste, such as a
jump shortly after leaving a ledge, accepting an early input, and correcting
certain corner contacts. These techniques show how a demanding game can allow
small errors consistent with player intent. They are platformer techniques with
context-specific tradeoffs. [Celeste and Forgiveness][thorson-forgiveness]

For other genres, consider a short action buffer, a slightly generous interaction
zone, or a clearly communicated grace period. Define duration, cancellation,
and reset rules. An old fire request executing after death, pause, or a menu
can contradict the player's current intent. In competitive play, apply equivalent
and predictable rules to equivalent actions.

Keep assistance separate from a misleading description of the rules. If a hit
can be forgiven or corrected, decide whether the correction affects tactics
and whether the player or opponent needs to know about it.

## Counterplay and balance

### Separate viable options from fair opportunity

Sirlin distinguishes choices that are useful during play from fairness of starting
conditions. Many nominal options can create learning burden while contributing
little to competitive strategy. Differences between players' starting options
also need to be distinguished from a field's visual symmetry.
[Balancing Multiplayer Games Part 1][sirlin1]

Our review should ask separate questions:

- Can each player use several worthwhile plans?
- Can an opponent respond to a strong plan?
- Do starting conditions give comparable opportunities under the intended rules?
- Can both participants understand the advantages and disadvantages?

Equal statistics answer only part of these questions. A start near a protected
fast road may be much stronger than one separated from every crossing by rough
terrain. A mirrored map can still favor a control scheme, camera orientation,
or first action. An asymmetric field can be fair, but needs evidence about its
actual opportunities.

### Give powerful actions appropriate answers

Riot distinguishes tactical responses during an encounter from strategic
responses prepared before it. High-impact threats generally warrant meaningful
answers, but the developer warns that forcing a last-second response into every
ability can make action unreliable or cumbersome. Strategic weaknesses can
support counterplay without making a matchup hopeless.
[Riot on champion counterplay][riot-counterplay]

For each strong tactic, write a possible answer and a possible response to that
answer. In a tank game, concealment might be answered by listening and careful
search; the hiding player may stop to become quiet; the searching player may
change route or hold a crossing. The useful distinction is whether players can
understand and influence this exchange.

Check traps that combine high reward, low commitment, little exposure, and no
meaningful answer. Also check whether an apparent answer is available early
enough, visible enough, and affordable enough to use.

### Allow advantages to be earned

Sirlin's viable-options discussion separates overall fairness from the fairness
of an intermediate position. An earned decisive situation can legitimately
constrain the opponent. Prolonged cleanup after the outcome is effectively
settled is a different problem. [Balancing Multiplayer Games Part 2][sirlin2]

A player who makes a good flank should benefit. Universal last-second escape
can erase the value of planning. Conversely, a player who cannot reasonably
recover should not be forced through minutes of repetitive defeat before a
rematch.

Choose how much commitment a successful attack requires, how long its advantage
lasts, and what learning a loss offers. Inspect both the attacker's satisfaction
and the defender's understanding.

### Tune a comprehensible system

Sirlin describes balancing difficulties created by large option sets and the
value of safeguards that address classes of abusive interactions. Relative
strength can vary while options remain usable; exact numerical equality is not
the only objective. His arguments concern competitive projects and should not
become a prohibition on customization in every genre.
[Balancing Multiplayer Games Part 3][sirlin3]

Begin with a small set of interacting rules. Try broadly understandable limits,
such as finite ammunition, a recovery window, bounded simultaneous projectiles,
or spawn protection. Then investigate exploits introduced by those limits:
protection that enables a free attack, a cooldown that encourages perpetual
stalling, or an escape that invalidates every earned advantage.

Use actual skilled play as well as analysis. A strong tactic may be difficult to
execute, culturally unfamiliar, or poorly explained. Separate these causes
before changing its numbers.

## Computer opponents

### Design the opponent for the experience

A computer opponent has several possible jobs: teach a rule, pressure a decision,
express a character, provide a credible rival, create an encounter rhythm, or
help a newcomer practice. Select the job before choosing the algorithm.

For each difficulty, specify:

| Dimension | Examples of a deliberate policy |
|---|---|
| Observation | Same sensors as player, visible clues, disclosed special knowledge |
| Reaction | A perceivable delay, staged commitment, immediate expert response |
| Planning | Direct approach, alternative route, flank, prediction |
| Execution | Aim precision, timing consistency, use of resources |
| Statistics | Equal values or clearly described advantages |
| Recovery | Separation after overlap, replanning after a blocked route |
| Personality | Cautious search, aggression, bluffing, territorial behavior |

These are distinct tuning dimensions. Reducing accuracy alone can produce a
weak opponent that behaves incomprehensibly. An easier opponent can make simpler
plans and leave visible opportunities to learn the real game.

### Establish trust through a stated rule policy

Soren Johnson discusses how rules compliance and perceived AI fairness can
diverge. Opaque but legitimate calculations can look suspicious; understandable
and disclosed difficulty adjustments can be accepted. His examples include
player-favoring exceptions, so the article does not prescribe identical
statistics for every opponent. [Game AI and Our Cheatin Hearts][johnson-ai]

For Ironveil's fair-rivalry premise, our chosen policy is stricter: authorized
sensor observations, shared physical rules, and stronger decisions at higher
difficulty. If another game uses extra information or statistical bonuses,
explain the policy and inspect whether it serves the promised experience.

Investigate losses that feel like mind reading, instant retaliation, a changed
rule, or an invisible accuracy bonus. Sometimes the algorithm is wrong;
sometimes the cue is missing; sometimes the player has discovered a powerful
legitimate strategy. Each calls for a different response.

### Make plans legible through behavior

An AI need not explain its internal state in text. Committed movement, a cautious
pause, searching an old contact, turning before firing, or retreating after a
miss can make its behavior interpretable.

Avoid rapid reversals that have no visible reason, perfect pre-aiming at a
concealed player, and repeated action loops after a route fails. A simple
opponent following an intelligible plan can support better play than a stronger
opponent whose actions seem arbitrary.

Test edge cases as part of the opponent's design: corners, unreachable goals,
loss of contact, respawn, overlap, stale information, and limited computation.
Then watch people play. Thousands of completed scripted matches demonstrate
useful reliability, but do not establish that the opponent feels enjoyable or
fair to a person.

## Randomness and procedural generation

### Decide what uncertainty contributes

Randomness can create surprise, variation, adaptation, social drama, or an
unknown world to discover. Identify that purpose before adding random outcomes.

Soren Johnson describes randomness that creates situations players can adapt
to, along with failures that obscure rules or determine outcomes before a player
can respond. His examples deliberately control the distribution of crucial
resources while allowing less important variation. These are design preferences
and case studies, rather than a universal rejection of random outcomes.
[Playing the Odds][johnson-random]

A useful working distinction is:

- **Uncertainty presented before a decision:** a generated battlefield, a drawn
  hand, or an enemy formation the player can inspect and respond to.
- **Uncertainty resolving after commitment:** a hit roll, damage variation, or
  an event that changes the chosen action's result.

Both can work. Their effects on planning, blame, dramatic tension, and skill
expression differ. Players need an appropriate way to understand the possible
outcomes and the amount of control they have.

### Generate within a designed structure

Cogmind's developer describes planning coarse layout patterns, generating within
them, examining loops and openness, and rejecting layouts outside constraints
before adding population and detail. Judging the overview alone misses problems
seen through the player's limited view. [Procedural Layouts][cogmind-layouts]

For our own generator, distinguish:

1. Structural promises: legal starts, reachability, essential resources, usable
   clearances, and permitted encounter arrangements.
2. Tactical variety: route costs, cover, sightlines, alternatives, and exposure.
3. Presentation variety: texture, silhouettes, decorative detail, and atmosphere.

Validate the structural promises before relying on presentation variety. Use
bounded repair, rejection, or a fallback appropriate to the target machine.
Conflicting constraints can make repeated rejection expensive or impossible.

### Preserve seeds and inspect outliers

Keep the generator version and seed with observations. Repeat an unfavorable
case before changing a rule. Sample ordinary seeds, extremes, and deliberately
constructed stress cases.

Useful checks for a tactical map include routes for the actor's actual footprint,
travel cost using real terrain speeds, safe exits from both starts, firing lanes,
cover networks, and exposure at chokepoints. These are our design diagnostics;
a passing result does not make every map enjoyable.

Compare the map overview with each player's real camera. A route that looks
obvious from above may be impossible to understand from a small viewport. A
beautiful distribution of forests may produce repetitive slow corridors.

### Seek replay through changed decisions

A new arrangement is valuable when it changes what the player observes,
predicts, or chooses. If every generated field rewards the same route and tactic,
its visual variety may offer little tactical replay.

Reuse learned rules in new contexts. Preserve enough regularity for players to
transfer knowledge, and enough variation to make observation worthwhile. Do not
make every surface visually different if those differences convey no rule.

## Level and spatial design

### Give spaces a gameplay purpose

Describe the purpose of each region in terms of action: orientation, practice,
commitment, alternate routing, a contested crossing, a safe pause, or a dramatic
reveal. Geometry changes the value of controls, speed, range, and observation.

Taylor's level-design discussion connects navigation cues, understandable
objectives, teaching, and variation. He allows deliberate exploration and
confusion when they serve the desired experience. A clear objective can coexist
with several possible methods. [Ten Principles Part 1][taylor1]

Use recognizable landmarks and consistent route cues. If orientation is a
secondary task, give the player enough help to focus on the main activity.
If mapping an unknown place is central, preserve that work while keeping basic
movement and interaction understandable.

### Compare routes by their actual costs

Taylor discusses player-controlled risk, efficient reuse of space, and layouts
that exploit the game's mechanics and emotional direction. Reuse works when
the conditions or decisions change; repeated travel with no new purpose can
become padding. [Ten Principles Part 2][taylor2]

A route comparison for our tank game might include:

| Route | Gain | Cost | Question for playtests |
|---|---|---|---|
| Road crossing | Speed and clear navigation | Exposure and predictable destination | Does its speed reward justify the risk? |
| Forest detour | Concealment and approach options | Slow travel and uncertain enemy position | Can players use it deliberately? |
| Narrow ford | An alternate crossing | Limited room and slow movement | Is it a genuine alternative or a trap? |
| Open flank | Space to maneuver and fire | Visibility and travel distance | Does it answer a dominant defensive position? |

Inspect combinations. An alternate route can exist in the data while being
unusable because its approach is always watched, its clearance is too small,
or its cost exceeds the remaining match time.

### Use loops and sightlines intentionally

Loops can allow retreat, flanking, and rediscovery. Chokepoints can concentrate
conflict and make a small map legible. Open areas can expose movement and permit
several attack angles. Each needs a purpose and a response.

Check what the player can see before committing, where they can recover, and
whether a mistake has a plausible alternative on the next attempt. An ambush
can be satisfying when the attacker prepared it and the defender had ways to
infer danger. Repeated unavoidable hits at a compulsory spawn exit deserve
investigation.

### Make starts part of the level design

Starting separation affects anticipation, orientation, travel burden, and the
first encounter. Pixel distance alone is insufficient when terrain speeds and
route geometry differ.

Measure time to a useful plan, a credible contact, and the first firing
opportunity. Compare both sides and swap the players. Ask whether the opening
gives room to act or simply postpones every meaningful interaction.

## Pacing and match endings

### Observe the session rhythm

Booth's Left 4 Dead presentation describes a Director that combines structured
procedural population with changes in intensity, creating quieter periods and
combat peaks. He distinguishes modulation of pacing from changing difficulty.
It is a cooperative PvE case study; its timings and interventions do not define
the right rhythm for every game. [The AI Systems of Left 4 Dead][l4d]

Map the actual rhythm of our game: orientation, search, a clue, approach,
commitment, exchange, and recovery. A quiet interval can mean anticipation,
intentional concealment, confusion, or empty travel. Ask what the player is
thinking and trying during it.

Use natural system interactions before adding a pacing controller to a small
competitive game. Secret adjustments to force a desired winner or comeback
need a very different contract from fair local rivalry.

### Give a session a satisfying shape

Consider the opening, development, climax, and result. The shape can be a tense
short match, an exploratory journey, a puzzle solved in stages, or a sustained
contemplative experience. Continuous peak intensity can make distinctions harder
to perceive; continuous low activity can make the purpose disappear.

Vary meaningful conditions: enemy pressure, available routes, information,
resources, or the player's current goal. Adding more enemies is only one way to
change intensity and may worsen readability or performance.

### Specify endings and ties

Make the win condition understandable before it determines the result. Define
ties, simultaneous outcomes, sudden death, draw conditions, and surrender where
they matter. Explain these on a surface that remains accessible during play.

Test whether an ending rewards the activity the game intends. A timer that makes
hiding permanently optimal may conflict with an active duel. A shrinking arena
can encourage engagement while weakening a deliberate stealth premise. A draw
and fast rematch may be more appropriate than indefinite overtime, depending
on what players want.

When using a tie-breaking rule, examine incentives before the deadline as well
as after it. The rule can change the entire match strategy.

### Make recovery and rematch part of pacing

A result should acknowledge what happened, give the player time to understand
it, and make the next choice straightforward. Preserve convenient settings,
allow appropriate side swaps, and avoid requiring repeated configuration.

Differentiate a player voluntarily reflecting on a loss from a program forcing
idle time. Neither immediate restart nor a long victory animation is universally
right. Choose the time that serves the session, and give control where practical.

## Progression rewards and economies

### Recognize the resources already present

Schreiber treats economies as systems of creation, consumption, conversion,
exchange, and scarcity. Resources can influence caution, experimentation, session
length, and social behavior. He also stresses examining interacting feedback
processes and notes that balance alone is insufficient for enjoyment.
[Game Balance Concepts Level 10][schreiber]

Our tank game already has resources without currency: armor, shell availability,
cooldown time, position, remaining match time, and information. A shot spends
an opportunity and can reveal location. A fast route spends concealment. Waiting
can conserve exposure while spending time and initiative.

Before adding ammunition, fuel, money, or crafting, identify the decision it
would create and the extra interfaces and learning it would require.

### Examine feedback loops

A positive feedback loop amplifies an advantage: success provides resources that
make further success easier. A negative feedback loop counteracts a difference:
a leader takes on a burden or a trailing player receives a recovery opportunity.
Both can serve a purpose.

Inspect their interaction. A comeback mechanism can keep a match competitive
while making earned progress feel less valuable. Snowballing can reward strong
opening play while leaving the rest of the match predictable. A limit or reset
can contain an advantage without covertly manipulating the result.

State the intended effect and expose consequential rules. Avoid judging an
economy by resource totals alone; look at the choices those resources permit.

### Distinguish player learning from character growth

An unlock, larger number, new ability, and improved player understanding are
different kinds of progression. A larger number can help express advancement,
but it can also make the same actions compulsory against larger enemies.

Seek changes that alter goals, interactions, context, or expressive possibilities.
A new tool should have a learnable purpose. A skill tree whose useful branches
collapse into one required sequence offers limited agency.

For short replayable games, learning routes and reading opponents may provide
sufficient progression. Persistent unlocks can complicate fair local matches
if players arrive with different access. Decide whether progression is shared,
cosmetic, optional, reset for competition, or part of the intended asymmetry.

### Connect rewards with their purpose

Rewards can acknowledge skill, reveal new possibilities, complete a narrative
beat, support expression, or provide a pleasant sensory response. Ask what the
reward is encouraging and whether the encouraged behavior improves the game.

Check for rewards that encourage tedious repetition, risk-free waiting, farming
an ineffective opponent, or ignoring the game's interesting decisions. A
reward structure can make an undesirable routine efficient enough that people
feel compelled to follow it.

## Art sound and narrative

### Give presentation a functional hierarchy

Valve's art-direction presentation shows how silhouette, proportion, lighting,
color, and contrast support recognizing actors, weapons, threats, and navigable
space. Its TF2 and Left 4 Dead examples demonstrate different stylistic solutions
to gameplay needs. [How Valve Connects Art Direction to Gameplay][valve-art]

Riot similarly connects clarity with quick understanding and the ability to
respond, including consistent silhouettes, facing, projectile direction, and
hitbox presentation across backgrounds. [Clarity in League][riot-clarity]

For our projects, make essential distinctions legible first, then build a style
that strengthens the intended mood. A beautiful forest can remain rich while
reserving a reliable outline or motion cue for a visible tank. A dramatic effect
can emphasize impact without masking the next attack.

Use a small style guide: important silhouettes, terrain patterns, team cues,
state transitions, animation rhythm, and effect priority. Check the guide against
actual play scenes rather than isolated asset sheets.

### Make sound communicate state and mood

The Returnal sound team describes creating an audio identity with the game and
narrative directors, and prioritizing sounds according to combat context. Its
mix gives important threats precedence over less important competing sounds;
an initially weapon-centered mix did not supply the awareness players needed.
This is a production case study, with a useful priority principle despite its
very different hardware scale. [Returnal sound-team interview][returnal]

Write an event and priority table for our own audio:

| Event | Possible information | Priority question |
|---|---|---|
| Movement | Actor identity and rough proximity | Can a warning interrupt it? |
| Shot | Action confirmation and exposure | Is it distinct from a hit? |
| Impact | Contact, obstruction, or damage | Can the player interpret which occurred? |
| Destruction | A major state change | How long may it occupy attention? |
| Contact cue | New information or changed certainty | Does it preserve the visibility contract? |
| Ambience or music | Place, mood, rhythm | What yields when critical cues conflict? |

Silence can carry information in a stealth game. A repeating engine can disclose
movement; stopping can become a tactical action. Do not add continuous audio
merely because a voice is available.

Give the player an appropriate way to adjust or substitute important cues.
Test the combined mix at ordinary volume, with effects competing, and with
sound disabled. A collection of individually distinctive sounds can become
confusing when played together.

### Integrate story with the player's activity

The Portal postmortem describes adapting story and mechanics together through
playtests. Its boss iterations show how a more complex, intense ending could
conflict with the experience players enjoyed; the final approach combined
dramatic presentation with a simpler puzzle. This is a specific example of
coherence, rather than a prescription for every game's climax.
[Portal narrative and design postmortem][portal]

Let fiction explain useful relations: why a surface behaves differently, why an
opponent acts cautiously, what an object is for, or why a decision has stakes.
Do not let an extended explanation interrupt the repeated activity without
considering its cost.

A game can express a place or emotional arc with minimal text. A story-heavy
game can value language and authored pacing. Choose presentation that supports
the actual brief instead of adding exposition to make a game seem substantial.

### Let environments support interpretation

Smith and Worch describe players constructing meaning from environmental clues,
with room for interpretation in optional narrative and clearer signals where
play depends on understanding a threat or route. [Environmental Storytelling][environment-story]

For a small game, a recognizable landmark, changed surface, damaged object, or
persistent consequence can connect actions with the world. Give a detail a
legible purpose before spending scarce assets on it. A clue too small to be
recognized cannot carry the intended warning or story.

## Accessibility and player options

### Analyze the actual barrier

Game Accessibility Guidelines recommends practical measures such as simpler
controls, readable presentation, alternatives to color or sound alone, difficulty
choices, and menus using the gameplay input method. Its applicability depends
on the particular game and players. [Basic accessibility guidelines][gag]

Input accessibility includes speed, complexity, and duration of physical demands.
Microsoft's input guidance discusses remapping, digital alternatives, simpler
schemes, and alternatives to rapid repetition, prolonged holds, and simultaneous
actions. [Xbox input guidance][xag107]

For each required action, inspect what a player must perceive, remember, decide,
and physically perform. A layout change addresses a different barrier from
slower action or a hold-to-toggle option. Test useful alternatives with people
who face the relevant barrier where possible.

### Provide coherent choices

Keep an assist's meaning understandable. Aiming assistance, direct navigation,
extra time, stronger armor, and a less capable opponent affect different aspects
of play. Provide descriptions that help players choose without ridicule.

Keep menus and help reachable using the selected device when practical. Update
prompts after a control change. Avoid an accessible gameplay scheme paired with
a title screen that requires an unrelated keyboard command to begin.

For competitive play, make rule-changing options mutually understood. A shared
visual hearing cue can have different implications from an individual assist.
Preserve the stated information policy when offering an alternate sensory route.

### Address presentation and cognitive load

Use adequate text and symbol sizes for the intended display. Give important
information a stable place and vocabulary. Allow instructions and current
objectives to be revisited. Avoid requiring a player to remember a long list
while simultaneously navigating and aiming.

A color alternative can use shape, pattern, position, or text. An audio alternative
needs to carry the important information in another channel. A colorblind filter
or keyboard-only interface is useful evidence for a limited aspect of access;
it does not establish inclusion for every player.

Microsoft's motion guidance recommends control over distracting moving or
auto-updating interface content, and avoiding or allowing players to disable
secondary camera effects such as shake and bobbing. Apply this to effects,
scrolling help, and animated menus as well as the playing field. A reduced-motion
setting should preserve important information through a calmer cue. These
measures reduce particular barriers; they do not guarantee medical safety for
every player. [Xbox visual distractions and motion guidance][xag117]

Choose achievable features for the hardware and describe their limits. A small
set of well-designed control presets can be more useful than promising remapping
that the interface does not make practical.

Review flashing and high-contrast repetitive patterns alongside animation.
Basic Game Accessibility Guidelines recommends avoiding flickering images and
repetitive patterns. Avoid unnecessary rapid flashing and investigate calmer
alternatives to decorative effects. [Basic accessibility guidelines][gag]

## Prototyping and scope

### Prototype the strongest uncertainty

The Experimental Gameplay Project's authors describe short, tightly scoped
prototypes, early attention to the basic interaction, inexpensive experiments,
and cutting ideas that did not become compelling. They also discuss art and
music as part of communicating the desired experience. Their seven-day limit
was a project constraint, not a universal production schedule.
[How to Prototype a Game in Under 7 Days][prototype]

Name the largest unresolved question and build the cheapest representative
experiment that can answer it. Examples include whether a movement scheme feels
natural, hearing creates a useful choice, a map supports flanking, or a quiet
animation communicates the intended beauty.

A paper sketch can examine decisions. A rough input prototype can examine feel.
A small audio scene can examine cue conflict. Choose fidelity appropriate to the
question; visual roughness can distract from an art-direction question, while a
polished title can distract from a weak repeated action.

### Build a small complete version

Derek Yu emphasizes finishing as a skill: playable prototypes, a protected core,
ideas compatible with resources, feature cuts, and attention to transitions and
final polish. He warns against repeated rewrites and large late additions while
allowing exceptions for a project's actual needs. [Finishing a Game][yu]

For a small C64 game, a complete version includes loading, setup, starting,
learning, play, pause, result, rematch, and exit. Plan these explicitly. They
consume implementation, art, explanation, and testing effort.

A vertical slice is a small portion at representative final quality. It can
expose whether the intended presentation and rules fit the hardware and workload.
It should be chosen for what it teaches, rather than for how impressive its
screenshot looks.

### Account for the cost of each feature

Estimate the feature's interaction cost as well as its implementation cost:
controls, explanation, art, sound, AI behavior, maps, balance, exceptional states,
CPU time, memory, and loading. Reuse can be valuable, but new combinations
still need investigation.

Keep a stable version while trying a risky change. Cutting a weak experiment
should be inexpensive. Preserve the important learning in notes, so abandoning
an implementation does not erase why it was attempted.

A technical experiment can be a legitimate project goal. State that goal when
choosing it; a cycle-perfect effect and an enjoyable game answer different
questions and can both be worthwhile.

## Playtesting and iteration

### Turn an assumption into an observable question

Ambinder's Valve presentation treats design proposals as hypotheses and
playtests as a way to examine them. Observation reveals behavior; verbal reports
can expose intent while also introducing distraction or bias. Statistics help
comparisons but can omit context and hide extremes.
[Valve Approach to Playtesting][valve-test]

Write a prediction before the change:

- Direct movement will reduce wrong-direction corrections during the first minute.
- A coarse marker will help a newcomer choose a search route while preserving
  uncertainty about the concealed tank.
- An engine cue will produce deliberate stops and listening near a contact.
- Wider starts will create planning time without excessive unproductive travel.

Define the observation that would challenge the prediction. A player pressing
fewer buttons may be confused, successful, or disengaged. Record the situation
and interpretation as well as the count.

### Observe before coaching

Give an unfamiliar player the actual instructions and selected device. Let them
begin. Record hesitation, repeated ineffective actions, missed cues, unexpected
strategies, and recovery. If help is needed, record when and what was supplied.

Useful neutral follow-up questions include:

- What were you trying to do at that moment?
- What did you think that sound or marker meant?
- What do you think caused the hit or loss?
- Was there a point when you stopped knowing what to try?
- What would you change on another attempt?
- Which part would you most want to keep, change, or remove?

Avoid supplying the hoped-for answer in the question. Ask whether the player
wants another round separately from asking them to perform another test.
Polite cooperation is different evidence from a spontaneous request to replay.

### Use suitable participants and comparisons

Include newcomers to investigate first use, experienced players to investigate
mastery, and people with relevant access needs to investigate barriers. A trained
tester no longer represents a first-time player.

For a focused change, preserve a comparison build and similar circumstances.
For map fairness, pair matches on the same seed with sides swapped. Distinguish
practice effects from the effect of a new build. When several substantial
changes must be bundled, the result cannot identify which change caused an
improvement by itself.

Think-aloud play can reveal intentions but distort timing and concentration.
A quiet first attempt followed by a discussion of recorded moments may suit a
reflex or tense stealth game better. Recording requires the player's permission;
keep participation and identifying data minimal.

### Choose the next iteration from evidence

Valve's production presentation describes rough playable segments, external
feedback, and small work increments that test both the intended experience and
its appeal. Its particular schedules and content sizes belong to its production
context. [Sound Practices of Games Business and Design][valve-process]

Address a strong observed obstacle before polishing a feature that is merely
easy to add. Recheck the behavior that revealed the problem. Preserve raw examples
alongside summaries, and allow the brief to change when the intended experience
is not what the intended players want.

### Learn after release without losing scope

Keep a small, prioritized record of reports: build, context, observed behavior,
and expected behavior. Separate failures, recurring comprehension problems,
balance concerns, preferences, and feature requests. A request can identify a
need without identifying the best solution.

Look for recurring friction across sessions while preserving useful exceptions.
Reproduce a technical failure where possible; use player observation for an
experience question. Investigate a new rule's effects on experienced players
as well as first use.

Finish improvements in small, usable increments. Update help and distribution
artifacts when rules change. Keep additions within a sustainable scope and
revisit the brief before turning a focused game into several competing projects.

## Measurement and evidence

### Match the measure to the question

Use an observation plan rather than a single enjoyment score:

| Question | Possible observation | Interpretation to check |
|---|---|---|
| Can players act intentionally? | Wrong-direction corrections, unassisted goal completion | Confusion, execution trouble, or deliberate exploration |
| Can they understand feedback? | Cue explanations after an event | Accurate understanding or a plausible but wrong model |
| Are routes meaningful? | Route selection and changes after contact | Preference, habit, blocked alternatives, or incomplete knowledge |
| Is cover useful? | Stops, listening, ambush attempts, evasions | Deliberate stealth or inability to find a next action |
| Does failure teach? | A changed plan or execution on retry | Learning or merely a weaker encounter |
| Is the ending satisfying? | Explanation of result, optional replay | Understanding, frustration, courtesy, or enthusiasm |

Choose a small number of useful measures for a session. Time to first intentional
action, credible contact, or retry can help locate friction. Their ideal values
are project questions, rather than universal targets.

### Preserve context and uncertainty

Small qualitative sessions can reveal a serious problem without estimating how
common it is in a population. A small quantitative sample can produce an unstable
percentage. Report counts, participant context, build, settings, and seeds.

For a side-bias investigation, compare the same players and field with sides
swapped, then repeat across relevant skill levels and map types. A raw overall
win rate can conceal a favored side, a preferred controller, or mismatched skill.

Watch distributions and extreme cases, not only averages. A median easy start
can coexist with some players who cannot begin. A mean match length can conceal
both immediate defeats and prolonged stalemates. Those cases need different
explanations.

### Use automation for what it can establish

Automation is useful for invariants, reachability, input decoding, rule consistency,
performance budgets, deterministic replay, and AI stalls. It can expose a design
assumption that fails at a corner or under an unusual combination.

It cannot establish delight, legibility on a person's display, perceived fairness,
or willingness to return. Treat an automated opponent's completed matches as
behavioral reliability under the tested conditions. Add human observation for
the experience claims.

An interview study of 13 independent game professionals reports practical
challenges recruiting participants and handling playtest data. Its qualitative
findings support adapting research to a small creator's resources, with no claim to establish the
prevalence of every problem or a universal testing recipe.
[Indie games user research study][indie-research]

## Respect for player time and trust

### Make consequential commands honest

The FTC's 2022 dark-patterns report describes commercial interfaces that obscure
or impair informed choice, including misleading hierarchy, hidden terms,
unwanted charges, and obstructive cancellation. Its examples support concern
for clear consequential choices; it is not a general theory of enjoyment.
[Bringing Dark Patterns to Light][ftc]

For our small games, apply that concern to plain commands: begin, pause, reset,
new map, change rules, erase progress, and quit. Distinguish reversible choices
from destructive ones. Do not make the player guess whether a button starts a
new round or discards something they meant to keep.

A commercial version would additionally need honest prices, contents, purchase
consequences, and accessible ways to decline. This document is design guidance,
not a statement of current legal compliance.

### Invite return without engineering obligation

Hodent distinguishes entertainment and enjoyable persuasion from careless
friction or designs that exploit players for business benefit. Her analysis
emphasizes context and the player's interests; it does not make rewards or
randomness inherently unethical. [Ethics in the Videogame Industry][hodent]

Provide a satisfying conclusion and an optional reason to try again: a new map,
a strategy to test, a skill to improve, or a shared rematch. Treat the player's
decision to stop as a legitimate outcome.

Investigate mechanisms that make stopping costly for reasons unrelated to the
experience: lost streaks, artificial urgency, concealed exits, shame, or rewards
that demand unwanted repetition. Session length and repeated return can have
several causes; neither is a complete measure of value to the player.

For this repository, there is no need to import a persistent currency, daily
obligation, or purchase system merely because it appears in a popular game.
Choose the reward structure that supports the actual project.

## Applying the principles to C64 games

### Spend the hardware budget on the experience

The technical reference documents eight hardware sprites, the limit on sprites
sharing a scanline, three SID voices, keyboard matrix interactions, and different
PAL and NTSC frame budgets. Those constraints shape which experiences we can
present consistently. Consult [TIPS_AND_TRICKS.md](TIPS_AND_TRICKS.md) for the
hardware details and original references.

Translate a resource limit into a design choice:

| Constraint | Useful design response | Question for players |
|---|---|---|
| Limited moving objects | Give each actor, projectile, and effect a clear role | Can players identify the consequential objects? |
| Limited sound voices | Prioritize events and preserve silence where meaningful | Can players hear the warning during a busy exchange? |
| Small visible area | Choose camera, scale, landmarks, and offscreen cues together | Can players plan beyond the immediate view? |
| Limited text space | Put setup and help on suitable screens; keep essential live state available | Can players recover the rule they need? |
| Limited computation | Bound generation and AI work; preserve consistent input handling | Does complexity create stalls at consequential moments? |
| One-button joysticks | Design a small action vocabulary and make mode changes visible | Can players move, aim, and fire without accidental actions? |
| Shared keyboard | Choose both players' layouts and simultaneous actions together | Can both players perform the required combinations? |

A constraint can create a strong identity. Few visible actors can support tense
duels. A restricted palette can produce recognizable terrain. Deliberate movement
can allow a modest refresh rate to serve planning and anticipation. The constraint
still needs a coherent response; scarcity alone does not make a design elegant.

### Separate intended pace from implementation timing

Express important tuning in player terms: time to turn, time to cross a clearing,
warning duration, projectile travel, recovery after a hit, and time between shots.
Then implement the supported timing paths. A delay expressed only as a frame
count can change its duration between PAL and NTSC.

Design for the slowest supported demanding scene. If input becomes less responsive
precisely when two tanks meet, the performance failure changes the contest. Reduce
decorative work or spread background computation before accepting an unexplained
loss of control.

Evaluate the distribution build at the intended emulation speed and display
settings. Host keyboard behavior and modern displays can introduce differences.
Record an actual hardware run separately when one becomes available. An emulator
session provides useful evidence within its configuration.

### Include the whole physical session

Think through finding the program, loading it, choosing a controller, reading
the setup, beginning, pausing, retrying, and returning to a usable state. A short
game with a cumbersome restart can contain more waiting than play.

Prefer configuration that matches the scale of the game. Preserve common choices
across rematches. Make joystick ports and ownership visible. Plan readable help
for a typical living-room viewing distance, and account for color, contrast,
sound volume, and keyboard combinations on the target setup.

Our current projects have different purposes:

- **Nocturne:** animation and beauty. Composition, rhythm, motion, and sound are
  central review questions; competitive decisions are outside its brief.
- **Atlas:** procedural exploration. Geography, orientation, terrain meaning,
  travel cost, and the value of zoom levels deserve attention.
- **Bannerfall:** a local objective contest. Movement, pursuit, flag rules,
  recoverable mistakes, and understandable wins deserve attention.
- **Ironveil:** a duel using concealment and positioning. Information, navigation,
  sound, counterplay, contact frequency, and match endings deserve attention.

Use the project brief to select review criteria. These are priorities for our
work, rather than claims that any current build has satisfied them with every
player.

## Ironveil design review

### Preserve the intended promise

The working promise is a deliberate tank hunt: use cover and incomplete
information to approach, outflank, and defeat an opponent. The player should
understand navigation well enough to concentrate on that hunt.

The user's feedback already provides concrete evidence about this player's
preferences: keyboard movement felt twitchy; remembering hull-relative navigation
was inconvenient; extensive live text consumed too much map space; engine sound,
more forest, greater initial separation, and a rough contact cue were desirable.
This is valuable feedback from one person, with no claim to represent everyone.

Current rules and controls are documented in [IRONVEIL.md](docs/IRONVEIL.md).
The questions below are proposed design investigations, not conclusions from a
completed human playtest.

| Area | Intended benefit | Risk to investigate | Small useful experiment |
|---|---|---|---|
| Cardinal keyboard navigation | Spend attention on tactics | Hull turn delay may still make a direction seem ignored | Observe first encounters; ask players to explain a delayed move |
| Slow tank movement | Support planning and anticipation | Traversal or aiming could become tedious | Compare travel, contact, and combat portions of a session |
| More forest | Make concealment and ambush useful | Search can become aimless or favor indefinite waiting | Use matched seeds; observe whether players choose and revise search plans |
| Distant starts | Allow an opening maneuver | New players may wait too long for meaningful contact | Compare a few travel-cost bands while keeping routes useful |
| Fast visible roads | Offer a clear speed and exposure tradeoff | One road may dominate every opening | Swap sides and observe alternatives after opponents learn the route |
| Rough contact marker | Give search a direction | Players may mistake stale or coarse information for exact tracking | Ask what the marker means before explaining it |
| Movement sound | Reward listening and remaining still | Mix, room sound, or hearing differences may obscure the cue | Try quiet and busy exchanges, and investigate an equivalent visual cue |
| Independent hull and turret | Support armor orientation and flanking | Multiple controls may consume the tactical attention budget | Observe simultaneous navigation, aiming, and firing on each device |
| CPU difficulty | Offer a learnable range of opposition | Faster decisions or hidden knowledge may feel inexplicable | Compare what players infer with the stated CPU information and reaction policy |
| Deadline and sudden death | Limit regulation time and provide a tie-resolution phase | A leading player may hide; tied matches may stall | Record late-match plans, contact, and ending explanations |

### Treat the two views as shared information

Both people can see the entire television in local split-screen play. Each pane
can enforce its own visibility rules, but it cannot provide genuinely private
information. Looking at the other pane can reveal its camera location, landmarks,
and actions even if a tank is concealed in the observer's own pane.

Choose an explicit social and mechanical policy. The game can accept screen
watching as part of play, reduce incidental leakage where useful, or describe
the intended convention. A convention will not make information technically
private. In solo play, a coarse contact view can preserve the human's stated
information limits; it should remain consistent with markers, HUD, and sound.

### Review terrain as a set of choices

Give each terrain type a recognizable movement, visibility, firing, or route role.
If two types have identical practical effects, investigate whether their visual
variety is sufficient reason to keep both. If every type changes several hidden
numbers, the learning cost may exceed the choices created.

Compare routes by travel time, exposure, firing position, retreat options, and
what the opponent can infer. Equal geometric distances can have unequal tactical
cost. An asymmetric field needs useful opportunities for both starts without
requiring identical geography.

Define how a contact ages and disappears. Keep the marker, bearing, sound, and
visibility transitions consistent with that policy. An opponent should be able
to break visual contact or reduce contact precision through understandable
behavior, and a seeker should have a plausible way to improve it.

### Review the contest from both seats

Observe hunting, hiding, attacking, escaping, taking damage, respawning, and
winning. For each role, identify the available information and answers. A strong
ambush can be enjoyable for its planner while leaving its target unable to
understand any preventative action.

Try repeated encounters after players know the rules. Does a successful tactic
invite a response, or become a compulsory routine? Is stillness a tactical choice
with a cost, or the best answer throughout the match? Does a rear hit express
outflanking without making one unclear contact decide the whole contest?

The next useful outcome is a list of observed problems and small experiments.
The reference should guide those experiments while leaving room for player
preferences and unexpected successful tactics.

## Genre specific priorities

Different genres emphasize different demands. Hybrids need a deliberate priority
when their demands compete.

| Experience | Design priority | Common risk | Useful observation |
|---|---|---|---|
| Reflex action or platforming | Responsive input, readable hazards, recoverable execution | Failure caused by unclear contact or timing | Can a player describe and improve the failed action? |
| Puzzle solving | Understandable rules and a satisfying inference | Obscure wording or arbitrary exceptions | What model does the player form, and what changes at the insight? |
| Turn-based tactics | Useful alternatives, forecastable consequences, initiative | One efficient routine overwhelms context | Does the best plan change with position, resources, and opponent? |
| Real-time strategy | Attention management, feedback, meaningful expansion | Interface demands conceal the strategic choices | Can players explain priorities under pressure? |
| Stealth or hunting | An explicit information policy and recoverable contact | Invisible rule changes or prolonged empty searching | Can both hunter and target infer a next action? |
| Exploration | Orientation, curiosity, distinctive discoveries | Scale increases travel without discovery | What motivates a destination, and what makes it memorable? |
| Survival | Legible risk, resource pressure, meaningful preparation | Punishment overwhelms learning or forces routine | Can players connect preparation with outcomes? |
| Cooperative play | Complementary contributions and shared understanding | One player solves everything or controls the other | Does each person make worthwhile decisions? |
| Competitive play | Counterplay, fair opportunities, interpretable results | Degenerate strategy or unexplained advantage | Do informed opponents develop responses? |
| Narrative play | Consistent characterization, clear stakes, fitting agency | Choices promise consequences the game cannot deliver | What does the player believe their action changed? |
| Creative or expressive play | Useful tools, discoverable possibilities, ownership | Evaluation pressures replace experimentation | Do players produce and value their own variations? |
| Contemplative or aesthetic work | Coherent composition, rhythm, atmosphere, comfort | Arbitrary demands interrupt the intended mood | Does the experience sustain the desired attention and feeling? |

Difficulty, rewards, scores, permanent progression, tutorials, and fail states
are design choices within these experiences. Their presence or absence does not
by itself establish quality. Choose a coherent set and explain its consequences.

## Common symptoms and possible causes

A symptom rarely identifies one cause. Use these as investigation starting points.
Change a small number of variables, preserve useful comparison conditions, and
observe whether the predicted improvement occurs.

| Symptom | Possible causes | Next small investigation |
|---|---|---|
| Players move the wrong way repeatedly | Mapping, camera orientation, delayed turn, conflicting inputs | Observe a simple route with no opponent; inspect intended and received actions |
| Players describe controls as twitchy | Repeat rate, acceleration, sensitivity, excessive correction | Compare two movement timings on the same maneuver |
| Players say deaths are random | Missing cue, unclear hitbox, hidden rule, actual variance | Ask for a cause immediately after an event; inspect the same encounter |
| Players miss an important event | Cue hierarchy, overlap, low contrast, competing sound | Reduce one competing channel and observe recognition |
| Players cannot find an opponent | Sparse routes, stale cues, long traversal, unclear goal | Track search plans and time spent without an actionable clue |
| Players camp throughout a match | Low cost of waiting, favorable ending rule, weak search tools | Ask what would make moving worthwhile; compare the relevant incentive |
| Players always choose one route | Dominant travel cost, safer opening, unknown alternatives | Swap starts, teach an alternative, and observe informed choices |
| Players ignore a mechanic | No useful context, poor teaching, high execution cost | Create a representative situation in which its benefit should be apparent |
| Players enjoy a prototype but stop after several rounds | Repetition, exhausted learning, limited variation, tiring controls | Observe what changed between early and later rounds |
| Hard CPU feels dishonest | Privileged information, instant reaction, opaque stat changes | Expose the policy and compare it with a constrained opponent |
| Many matches end in a foregone conclusion | Snowballing, weak recovery, prolonged cleanup | Locate when useful decisions disappear and what extends the ending |
| A comeback feels unearned | Hidden adjustment, excessive catch-up, poorly explained rule | Ask both sides what caused it and inspect the actual rules |
| New players abandon the start screen | Dense help, unrelated input, unclear readiness, loading confusion | Observe an unassisted start using the advertised controller |
| Players cannot explain a win | Ambiguous objective, tie rule, feedback, simultaneous event | Review the final moments and result display together |
| People rarely retry after a loss | Excessive cost, no improvement idea, exhaustion, satisfied completion | Ask why they stopped; distinguish frustration from a complete experience |

## Working templates and checklists

### One page design brief

Keep the brief short enough to use during ordinary decisions:

- **Audience and context:** who, controller, session length, solo or social setting.
- **Experience sentence:** what players do and what makes it worthwhile.
- **Pillars:** two or three priorities that resolve actual tradeoffs.
- **Repeated loop:** perception, decision, action, consequence, feedback, next situation.
- **Main choices:** alternatives and the circumstances in which each is useful.
- **Intended demands:** learning, planning, reaction, precision, cooperation, expression.
- **Information policy:** what players know, infer, remember, and can conceal.
- **Outcome:** success, failure, tie, recovery, and replay.
- **Constraints:** hardware, production effort, access, distribution.
- **Largest uncertainty:** the question the next prototype must answer.
- **Evidence to seek:** an observable behavior and a relevant player explanation.

### Mechanic design card

For a proposed mechanic, write:

1. The player purpose and connection to a pillar.
2. The trigger, prerequisites, rule, cost, and consequence.
3. Its feedback and how it is first learned.
4. Useful alternatives and opponent responses where relevant.
5. Interactions with existing movement, resources, visibility, and outcomes.
6. The worst plausible exploit, confusion, or accessibility barrier.
7. Implementation and content costs, including additional states and help.
8. The smallest experiment that could justify keeping, changing, or removing it.

For a terrain mechanic, include collision, travel time, visibility, projectile
behavior, audio, map-generation role, and marker appearance. Unknown rules in
these relationships create misleading expectations.

### Information contract

For every important state or cue, record:

| Field | Question |
|---|---|
| Meaning | What does the cue represent? |
| Precision | Exact value, category, sector, bearing, or implication? |
| Availability | Who receives it, under what conditions? |
| Freshness | Live, periodically sampled, delayed, or last known? |
| Confidence | Guaranteed, fallible, or uncertain in a stated way? |
| Lifetime | When does it update, disappear, or become invalid? |
| Presentation | Which shape, text, motion, sound, or alternate cue carries it? |
| Consequence | What useful decision can a player make from it? |

Check all presentations of the same state against this contract. A coarse map
marker and an exact sound cue may accidentally reveal more than intended.

### Playtest observation record

Record the build, participant experience, controller, display/audio setup,
settings, seed, session goal, and any coaching. Keep observations separate from
interpretations:

- **Observation:** what the player did, said, or failed to perceive, with event context.
- **Player explanation:** their account of intention and outcome; mark direct quotes as such.
- **Possible explanation:** your hypothesis and plausible alternatives.
- **Impact:** blocker, repeated friction, occasional issue, preference, or successful behavior.
- **Next step:** a small design change, further observation, or no action yet.

Ask permission before recording people. Keep only the personal information
needed for the work. Summaries can usually refer to anonymous participant labels.

### Design experiment record

- **Question:** the uncertainty to resolve.
- **Prediction:** what should change if the explanation is correct.
- **Variant:** the specific rule, timing, cue, or content change.
- **Comparison:** what stays consistent and what may confound the result.
- **Participants and situations:** who and which representative cases.
- **Observations:** counts, sequences, explanations, and exceptions.
- **Result:** supported, contradicted, mixed, or still uncertain.
- **Confidence and limits:** what the session can reasonably establish.
- **Decision:** keep, revise, remove, or investigate further, with the reason.

Example: if the contact marker's meaning is unclear, change its presentation or
teaching while preserving its data. Predict more accurate explanations and more
intentional search. A higher win rate alone would not establish that improvement.

### Reviews at useful milestones

**Concept review**

- [ ] The audience, experience, and main activity are specific.
- [ ] The design pillars can resolve a real feature disagreement.
- [ ] The smallest complete version fits available resources.
- [ ] The largest uncertainty has a practical prototype plan.

**First playable review**

- [ ] An unfamiliar player can begin and take an intentional action.
- [ ] The repeated action and its consequences are understandable.
- [ ] The intended challenge is present and worth investigating further.
- [ ] Failure, recovery, and an ending are represented.
- [ ] Input and presentation remain consistent in representative demanding scenes.

**Systems and content review**

- [ ] Options have useful contexts; dominant routines have been investigated.
- [ ] Opponents have understandable responses to consequential actions.
- [ ] Random content respects required invariants and useful variation.
- [ ] Levels support orientation, deliberate routes, and appropriate pacing.
- [ ] Difficulty changes have a coherent, explainable purpose.
- [ ] Art and sound communicate the important states without overwhelming them.
- [ ] Relevant access barriers and alternative cues have been considered.

**Release review**

- [ ] The distribution loads and the supported controllers can complete the whole flow.
- [ ] Help, pause, loss, tie, restart, and rematch rules are understandable.
- [ ] Human observations have been recorded alongside technical validation.
- [ ] Remaining limitations and supported hardware paths are stated accurately.
- [ ] The final documentation matches the shipped controls and rules.

These reviews are prompts for evidence and judgment. A checked box is a record
of what was examined, rather than a certificate that every player will enjoy it.

## Glossary

| Term | Working meaning |
|---|---|
| Agency | The ability to form an intention and affect a result through meaningful action |
| Perceived affordance | An action the player believes an object permits, based on its presentation and behavior |
| Core loop | A repeated sequence of perception, decision, action, consequence, and feedback |
| Mechanic | A rule or operation supplied by the game |
| Dynamic | Behavior that emerges when rules interact during play |
| Game feel | The experienced relationship among input, motion, response, context, and presentation |
| Telegraph | A cue that makes an impending action or consequence interpretable before it happens |
| Counterplay | An opponent's tactical or strategic ways to respond to an action |
| Dominant strategy | A strategy that remains best regardless of the opponent's response; a common successful tactic need not be dominant |
| Feedback loop | A process in which an outcome changes conditions that influence future outcomes |
| Positive feedback | A process that amplifies an existing difference or tendency |
| Negative feedback | A process that counteracts a difference or tendency |
| Input buffer | A system that remembers a recent input so it can execute when an action becomes valid |
| Grace window | A limited interval allowing an action around an otherwise strict boundary |
| Input randomness | Uncertainty resolved before the player makes the decision under discussion |
| Output randomness | Uncertainty resolved after that decision, influencing its outcome |
| Progression | Change over time in player knowledge, abilities, available content, or game state |
| Procedural generation | Production of content through rules and data, often including randomness |
| Seed | A value used to initialize reproducible pseudo-random generation under the same implementation |
| Vertical slice | A small representative portion developed to the intended quality of the finished work |
| Playtest | Observation of people playing to investigate understanding, behavior, and experience |
| Quality assurance | Investigation of whether the software and content behave as specified |

Definitions here support the document's use. Some terms have narrower technical
meanings or different usage in other design traditions.

## Sources and further reading

The links below favor authors, original developer presentations, author-hosted
papers, and official guidance. Each citation in the body supports a nearby
attributed claim. Practical tables, templates, and applications to our repository
are synthesis, with no claim that the sources directly evaluated our games.

Read the original before adopting a technique whose context differs from ours.
Talk decks communicate less detail than a complete recorded presentation. The
Meier entry uses its session overview; the indie research entry uses the published
abstract. Those access limits constrain the claims made above.

### Foundations and motivation

1. Robin Hunicke, Marc LeBlanc, and Robert Zubek, [MDA A Formal Approach to Game
   Design and Game Research][mda] (2004). Design analysis framework.
2. Doug Church, [Formal Abstract Design Tools][church] (1999). Intention and
   perceivable consequence.
3. Raph Koster, [Game Grammar][koster-grammar]. Author's presentation notes on
   learning and game structures.
4. Raph Koster, [RePlay interview][koster-replay]. Learning, comfort, and the
   limits of a single explanation for play.
5. Richard M. Ryan, C. Scott Rigby, and Andrew Przybylski, [The Motivational Pull
   of Video Games A Self-Determination Theory Approach][sdt] (2006). Four studies;
   associations require their study context.
6. Penelope Sweetser, Daniel Johnson, Anne Ozdowska, and Peta Wyeth, [GameFlow
   heuristics for designing and evaluating real-time strategy games][gameflow]
   (2012). Author-uploaded full paper; genre-specific evaluation.
7. Sid Meier, [Interesting Decisions][meier] (GDC 2012). Session overview and
   further viewing.

### Controls learning and failure

8. Steve Swink, [Principles of Virtual Sensation][swink-sensation] (2006).
   Mapping, response, and feedback.
9. Steve Swink, [Game Feel The Secret Ingredient][swink-feel] (2007). Context
   and presentation in moment-to-moment interaction.
10. Daniel Cook, [The Chemistry of Game Design][cook] (2007). A practitioner
    model of learnable skills.
11. Jesper Juul and Marleigh Norton, [Easy to Use and Incredibly Difficult On the
    Mythical Border Between Interface and Gameplay][juul-interface] (2009).
    Interface and challenge.
12. Jesper Juul, [Fear of Failing The Many Meanings of Difficulty in Video
    Games][juul-failure] (2009). Failure costs and context-dependent player response.
13. Maddy Thorson, [Celeste and Forgiveness][thorson-forgiveness]. Concrete
    platforming allowances.
14. Maddy Thorson, [Celeste and TowerFall Physics][thorson-physics]. Collision,
    fractional movement, and moving solids.

### Competition systems AI and space

15. David Sirlin, [Balancing Multiplayer Games Part 1 Definitions][sirlin1]
    (2014). Competitive viability and starting conditions.
16. David Sirlin, [Balancing Multiplayer Games Part 2 Viable Options][sirlin2]
    (2014). Useful alternatives and how advantage develops.
17. David Sirlin, [Balancing Multiplayer Games Part 3 Fairness][sirlin3] (2014).
    Asymmetric competition and safeguards.
18. Riot Scruffy, [Quick Gameplay Thoughts on Champion Counterplay][riot-counterplay]
    (2021). Tactical and strategic responses in League of Legends.
19. Soren Johnson, [Playing the Odds][johnson-random] (original column 2009;
    author's republication 2010). Uncertainty and adaptation.
20. Soren Johnson, [Game AI and Our Cheatin Hearts][johnson-ai] (2009).
    Information privileges, trust, and difficulty.
21. Dan Taylor, [Ten Principles of Good Level Design Part 1][taylor1] (2013).
    Navigation, learning, and player direction.
22. Dan Taylor, [Ten Principles of Good Level Design Part 2][taylor2] (2013).
    Risk, space, reuse, and design opportunities.
23. Josh Ge, [Roguelike Level Design Addendum Procedural Layouts][cogmind-layouts]
    (2019). Cogmind generation case study.
24. Mike Booth, [The AI Systems of Left 4 Dead][l4d] (2009). Cooperative PvE
    population and dramatic pacing.
25. Ian Schreiber, [Game Balance Concepts Level 10 Final Boss][schreiber]
    (2010). Economic systems and interacting feedback processes.

### Presentation production and research

26. Moby Francke and Randy Lundeen, [How Valve Connects Art Direction to
    Gameplay][valve-art] (GameFest 2008). Visual recognition and world readability.
27. Riot bananaband1t, [Clarity in League][riot-clarity] (2021). Competitive
    visual hierarchy and consistency.
28. Jennifer Walden interviewing the Returnal audio team, [Returnal How its
    glorious, dark electronic sound was made][returnal] (2021). Audio identity
    and combat mix priorities.
29. Kim Swift and Erik Wolpaw, [Integrating Narrative and Design A Portal
    Post-Mortem][portal] (GDC 2008). Teaching, story, and puzzle production.
30. Harvey Smith and Matthias Worch, [What Happened Here Environmental
    Storytelling][environment-story] (GDC 2010). Player interpretation of spaces.
31. Kyle Gabler, Kyle Gray, Matt Kucic, and Shalin Shodhan, [How to Prototype a
    Game in Under 7 Days][prototype] (2005). Original article, academic mirror.
32. Derek Yu, [Finishing a Game][yu] (2010). Scope and completion practice.
33. Mike Ambinder, [Valve's Approach to Playtesting The Application of
    Empiricism][valve-test] (GDC 2009). Hypotheses and player observation.
34. Brian Jacobson, [Sound Practices of Games Business and Design][valve-process].
    Valve's iterative production example; archive path says 2005, slides carry
    a 2007 copyright.
35. Alena Denisova, Steve Bromley, Pejman Mirza-Babaei, and Elisa D. Mekler,
    [Towards Democratisation of Games User Research Exploring Playtesting
    Challenges of Indie Video Game Developers][indie-research] (2024). Abstract;
    qualitative interviews with 13 professionals.

### Accessibility and player trust

36. [Basic Game Accessibility Guidelines][gag]. Practical inclusion guidance.
37. Microsoft, [Xbox Accessibility Guideline 102 Contrast][xag102].
38. Microsoft, [Xbox Accessibility Guideline 103 Additional channels for visual
    and audio cues][xag103].
39. Microsoft, [Xbox Accessibility Guideline 107 Input][xag107].
40. Microsoft, [Xbox Accessibility Guideline 108 Game difficulty options][xag108].
41. Microsoft, [Xbox Accessibility Guideline 109 Objective clarity][xag109].
42. Microsoft, [Xbox Accessibility Guideline 117 Visual distractions and motion
    settings][xag117].
43. Federal Trade Commission, [Bringing Dark Patterns to Light][ftc] (2022).
    Commercial interface practices; design ethics context.
44. Celia Hodent, [Ethics in the Videogame Industry][hodent] (2019, updated
    2021). Context, player interests, and business responsibility.

[mda]: https://www.cs.northwestern.edu/~hunicke/MDA.pdf
[church]: https://www.gamedeveloper.com/design/formal-abstract-design-tools
[koster-grammar]: https://www.raphkoster.com/games/presentations/game-grammar/
[koster-replay]: https://www.raphkoster.com/replay-interview-the-puddle-the-splat-and-the-droplets/
[sdt]: https://selfdeterminationtheory.org/wp-content/uploads/2020/10/2006_RyanRigbyPrzybylski_MandE.pdf
[gameflow]: https://www.researchgate.net/publication/254462666_GameFlow_heuristics_for_designing_and_evaluating_real-time_strategy_games
[meier]: https://www.gdcvault.com/play/1015756/
[swink-sensation]: https://www.gamedeveloper.com/design/principles-of-virtual-sensation
[swink-feel]: https://www.gamedeveloper.com/design/game-feel-the-secret-ingredient
[cook]: https://www.gamedeveloper.com/design/the-chemistry-of-game-design
[juul-interface]: https://jesperjuul.net/text/easydifficult/
[juul-failure]: https://jesperjuul.net/text/fearoffailing/
[thorson-forgiveness]: https://www.maddymakesgames.com/articles/celeste_and_forgiveness/index.html
[thorson-physics]: https://www.maddymakesgames.com/articles/celeste_and_towerfall_physics/index.html
[sirlin1]: https://www.sirlin.net/articles/balancing-multiplayer-games-part-1-definitions
[sirlin2]: https://www.sirlin.net/articles/balancing-multiplayer-games-part-2-viable-options
[sirlin3]: https://www.sirlin.net/articles/balancing-multiplayer-games-part-3-fairness
[riot-counterplay]: https://www.leagueoflegends.com/en-us/news/dev/quick-gameplay-thoughts-may-14/
[johnson-random]: https://www.designer-notes.com/game-developer-column-9-playing-the-odds-3/
[johnson-ai]: https://www.gamedeveloper.com/game-platforms/analysis-game-ai-our-cheatin-hearts
[taylor1]: https://www.gamedeveloper.com/design/ten-principles-of-good-level-design-part-1-
[taylor2]: https://www.gamedeveloper.com/design/ten-principles-of-good-level-design-part-2-
[cogmind-layouts]: https://www.gridsagegames.com/blog/2019/03/roguelike-level-design-addendum-procedural-layouts/
[l4d]: https://cdn.cloudflare.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf
[schreiber]: https://gamebalanceconcepts.wordpress.com/2010/09/08/level-10-final-boss/
[valve-art]: https://cdn.fastly.steamstatic.com/apps/valve/2008/GameFest08_ArtInSource.pdf
[riot-clarity]: https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/
[returnal]: https://www.asoundeffect.com/returnal-game-audio/
[portal]: https://cdn.fastly.steamstatic.com/apps/valve/2008/GDC2008_PortalPostMortem.pdf
[environment-story]: https://media.gdcvault.com/gdc10/slides/Smith_Harvey_WhatHappenedHereWeb_Notes.pdf
[prototype]: https://www.cs.hmc.edu/~markk/SWE_copies/gabler_prototyping.html
[yu]: https://makegames.tumblr.com/post/1136623767/finishing-a-game
[valve-test]: https://cdn.fastly.steamstatic.com/apps/valve/2009/GDC2009_ValvesApproachToPlaytesting.pdf
[valve-process]: https://cdn.fastly.steamstatic.com/apps/valve/2005/AGDC2005_SoundPractices.pdf
[indie-research]: https://pure.york.ac.uk/portal/en/publications/towards-democratisation-of-games-user-research-exploring-playtest/
[gag]: https://gameaccessibilityguidelines.com/basic/
[xag102]: https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102
[xag103]: https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/103
[xag107]: https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107
[xag108]: https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/108
[xag109]: https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/109
[xag117]: https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/117
[ftc]: https://www.ftc.gov/system/files/ftc_gov/pdf/P214800%20Dark%20Patterns%20Report%209.14.2022%20-%20FINAL.pdf
[hodent]: https://celiahodent.com/ethics-in-the-videogame-industry/
