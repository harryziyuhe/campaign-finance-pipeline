# Empirical Design Architecture for the Corporate PAC–Scandal Project

This memo lays out a sequence of empirical designs for studying how corporate PACs respond to congressional scandals. The premise is that no single design can fully separate targeted withdrawal, firm-wide chilling, access-value loss, candidate exit, and spillover effects. The designs are therefore organized cumulatively. The first design estimates the baseline relationship-level response to scandal revelation. Subsequent designs address specific identification and interpretation problems raised by the earlier designs.

Throughout, the primary scandal event is the first public break date, denoted $t_0$. This is the date on which the scandal first becomes publicly observable to firms, donors, journalists, voters, and other stakeholders. Later events, such as investigations, retirement announcements, resignations, indictments, sanctions, or electoral decline, should generally be treated as downstream consequences, secondary shocks, or mechanisms rather than as the primary treatment.

## Notation Used in Regression Equations

Let $i$ index firms or firm PACs, $j$ index candidates or members of Congress, $t$ index time periods, $g$ index scandal-control matched sets, and $r$ index recipient categories. Let $Y_{ijt}$ denote a contribution outcome from firm $i$ to candidate $j$ in period $t$, such as any contribution, total amount, log amount, share of remaining contribution capacity used, or time-to-next-contribution in hazard specifications. Let $Y_{it}$ denote firm-level political activity in period $t$. Let $Post_{jt}$ indicate periods after candidate $j$'s scandal break date $t_0$. Let $Scandal_j$ indicate that candidate $j$ is scandal-tainted. Let $Treated_{ij}$ indicate a preexisting firm-candidate relationship exposed to scandal. Let $\alpha$, $\delta$, $\gamma$, and $\lambda$ denote fixed effects.

The equations below are templates. The appropriate outcome model may be linear probability, OLS for transformed amounts, Poisson or negative binomial for counts, Tobit or fractional models for contribution shares, or Cox/discrete-time hazard models for time-to-next-contribution. The identifying structure is more important than the specific functional form at this stage.

# Design 1: Relationship-Level Response

## Objective

The objective of this design is to estimate whether firms with preexisting political relationships reduce support for a scandal-tainted politician after the scandal becomes public. The design fits several empirical models to estimate the scandal effect. This should likely be the main design of the paper because it is closest to the central theoretical claim: political scandals increase the reputational cost of visible association, and firms may respond by withdrawing support from the tainted politician.

## Question Answered

Among firms with prior contribution relationships to a politician, does the public revelation of a scandal reduce subsequent giving to that politician?

## Unit of Analysis

The unit of analysis is the firm PAC–candidate–period. The period can be defined at the month, quarter, reporting-period, or election-cycle level. A quarter-level or FEC-reporting-period level panel may be preferable because PAC contributions are lumpy and do not arrive on a regular monthly schedule.

## Sample

The preferred sample includes firm PAC–candidate pairs where the firm contributed to the candidate before $t_0$, the candidate is an incumbent member of Congress, the firm has remaining legal capacity to contribute after $t_0$, and the candidate remains legally and practically able to receive contributions during the post-treatment window. This creates a risk set of firms that had an existing relationship and a meaningful opportunity to continue or withdraw support.

Broader robustness samples could include prior-cycle contributors, firms that contributed to similar candidates, or all politically active corporate PACs. However, the narrow prior-contributor sample has the cleanest interpretation because it focuses on firms that had an observable relationship to maintain or abandon.

## Treatment Group

The treatment group consists of preexisting firm PAC–candidate relationships in which the candidate experiences a scandal at $t_0$. Treatment begins when the scandal first becomes public. A firm-candidate pair enters the treated group only if the firm had given to the candidate before $t_0$, using only pre-treatment information.

## Control Group

There are two complementary control-group strategies.

The first strategy uses matched non-scandal politicians. The control group consists of preexisting firm PAC–candidate relationships involving comparable politicians who did not experience scandal at the same point in the electoral cycle. Control candidates should be similar to treated candidates on party, chamber, incumbency, electoral competitiveness, district partisanship, committee assignment, leadership status, ideology, prior fundraising, and prior corporate PAC support.

The second strategy uses within-firm recipient comparisons. Here, the control recipients are other politicians to whom the same firm contributed before $t_0$. This comparison asks whether the firm reallocates support away from the scandal-tainted politician relative to its own giving elsewhere. In stricter versions, likely spillover or substitute recipients, such as same-state copartisans, same-committee members, successors, or replacement candidates, should be excluded from the control group and analyzed separately.

## Causal Inference Tools

The main tools are difference-in-differences and event-study specifications. The preferred specification should include firm-candidate fixed effects to compare within the same donor-politician relationship before and after scandal revelation. Calendar-period fixed effects should absorb common time shocks. Depending on the design, one may also include party-by-period, chamber-by-period, state-by-period, or election-cycle-by-period fixed effects.

Matching or weighting can be used to construct a more credible control group of non-scandal politicians. Candidate-level matching should use only pre-$t_0$ characteristics. Possible methods include exact matching on party, chamber, incumbency, and election cycle, followed by propensity-score matching, coarsened exact matching, entropy balancing, or nearest-neighbor matching on fundraising, ideology, committee assignment, electoral safety, and prior PAC support.


## Regression Equation

A baseline relationship-level DiD can be written as:

$Y_{ijt} = \beta (Scandal_j \times Post_{jt}) + \alpha_{ij} + \delta_t + X_{jt}'\theta + R_{it}'\rho + \epsilon_{ijt}.$

Here, $\alpha_{ij}$ are firm-candidate fixed effects, so identification comes from within-relationship changes in giving before and after scandal revelation. $\delta_t$ are calendar-period fixed effects. $X_{jt}$ includes candidate-level time-varying controls, preferably measured pre-treatment or predetermined relative to $t_0$, and $R_{it}$ includes relationship-level covariates.
A matched-set version can be written as:

$Y_{ijgt} = \beta(Scandal_j \times Post_{jt}) + \alpha_{ij} + \lambda_{gt} + \epsilon_{ijgt},$

where $g$ indexes matched scandal-control sets and $\lambda_{gt}$ are matched-set-by-period fixed effects.

The within-firm substitution version can be written as:

$Y_{ijt} = \beta(TaintedRecipient_j \times Post_{jt}) + \alpha_{ij} + \gamma_{it} + \epsilon_{ijt}.$

Here, $\gamma_{it}$ are firm-by-period fixed effects. This specification asks whether the scandal-tainted politician receives less from the same firm relative to the firm's other recipients after $t_0$.

A stricter version can include recipient-class-by-period fixed effects:

$Y_{ijkt} = \beta(TaintedRecipient_j \times Post_{jt}) + \alpha_{ij} + \gamma_{it} + \lambda_{kt} + \epsilon_{ijkt},$

where $k$ denotes recipient class, such as party, chamber, state, or committee group.

## Potential Control Variables

Potential controls include pre-scandal electoral margin, district partisanship, incumbency status, party, chamber, committee assignments, leadership position, ideology, pre-scandal fundraising, cash on hand, challenger quality, race competitiveness, firm size, industry, firm PAC giving history, prior amount given to the candidate, remaining contribution capacity, and time to Election Day.

Post-treatment variables such as post-scandal race ratings, retirement announcements, resignation, committee loss, or fundraising decline should not be included as ordinary controls in the baseline specification because they may be consequences of the scandal.

## Reasons for Caution

This design may confound reputational withdrawal with changes in candidate viability or access value. If a scandal causes a candidate to retire, resign, lose committee influence, or become electorally nonviable, firms may stop giving because the politician is no longer useful rather than because association with the politician is reputationally costly.

The matched-candidate version can also be threatened by spillovers. If comparable politicians are in the same party, state delegation, committee, or ideological faction, they may themselves be affected by the scandal through reputational contamination or substitution.

The within-firm version addresses firm-wide changes in political activity, but it does not fully solve candidate comparability. The firm's other recipients may differ from the scandal-tainted politician in committee value, electoral context, or relationship strength.

Contribution caps and irregular contribution timing also complicate interpretation. A firm that does not give after $t_0$ may have already reached the legal contribution limit or may not have planned to give again during that window.

## Why Additional Designs Are Needed

This design can show whether firms reduce support for scandal-tainted politicians, either relative to matched non-scandal politicians or relative to the firm's own giving elsewhere. However, it cannot fully distinguish targeted withdrawal from firm-wide chilling, access-value loss, candidate exit, or spillover effects. Additional designs are therefore needed to decompose the mechanisms behind any observed decline.

# Design 2: Firm-Level Chilling Effect Design

## Objective

The objective of this design is to estimate whether firms exposed to scandal through a prior political connection reduce political activity more generally. This design treats scandal exposure as a shock to the firm's reputational environment rather than only to a specific firm-candidate relationship.

## Question Answered

After one of a firm’s political recipients becomes scandal-tainted, does the firm reduce its overall PAC activity, even toward politicians not directly involved in the scandal?

## Unit of Analysis

The unit of analysis is the firm PAC–period.

## Sample

The sample includes firms that were politically active before $t_0$. Treated firms are those that contributed before $t_0$ to a politician who later became scandal-tainted. Control firms are politically similar firms that contributed before a comparable date to similar politicians who did not experience scandal.

The outcome should generally exclude contributions to the scandal-tainted politician. Otherwise, the outcome mechanically combines targeted withdrawal with general chilling. Preferred outcomes include total contributions to all other candidates, number of contributions to all other candidates, number of unique recipients, giving to same-party candidates, giving to committee-relevant candidates, and giving to party committees or other observable channels.

## Treatment Group

The treatment group consists of firms exposed to a scandal through a preexisting contribution relationship. A firm becomes treated when a politician to whom it had previously contributed becomes publicly scandal-tainted at $t_0$.

## Control Group

The control group consists of firms with similar pre-treatment political behavior but without exposure to a scandal-tainted recipient. Ideally, control firms should be selected from firms that gave to matched non-scandal politicians at the same point in the electoral cycle. Controls should have comparable pre-treatment total giving, partisan giving profile, industry, firm size, number of recipients, and committee-relevant giving.

## Causal Inference Tools

The main tool is firm-level difference-in-differences. The model should include firm fixed effects and period fixed effects. Matching or weighting should be used to construct a control group with similar pre-treatment political activity.

Possible matching variables include total pre-treatment PAC giving, number of candidates supported, party balance of giving, industry, firm size, prior giving to incumbents, prior giving to committee-relevant members, prior giving to vulnerable candidates, and exposure to electorally competitive races.

## Regression Equation

The firm-level chilling design can be written as:

$Y_{it} = \beta (ExposedFirm_i \times Post_{it}) + \alpha_i + \delta_t + W_{it}'\theta + \epsilon_{it}.$

Here, $ExposedFirm_i$ indicates firms that had contributed to a politician before that politician became scandal-tainted, and $Post_{it}$ begins after the relevant scandal break date for the firm. $\alpha_i$ are firm fixed effects, and $\delta_t$ are period fixed effects. The outcome $Y_{it}$ should generally exclude giving to the scandal-tainted politician so that the estimate captures broader political chilling rather than targeted withdrawal.

A matched-set version can assign each exposed firm to a scandal-control set $g$, where control firms are firms that gave to similar non-scandal politicians:

$Y_{igt} = \beta (ExposedFirm_i \times Post_{gt}) + \alpha_i + \lambda_{gt} + W_{it}'\theta + \epsilon_{igt}.$

The matched-set-by-period fixed effect, $\lambda_{gt}$, compares exposed firms to similar control firms facing the same pseudo-event timing.

## Potential Control Variables

Potential controls include firm size, industry, revenue, market capitalization, public visibility, consumer-facing status, institutional ownership, government-contracting dependence, regulatory exposure, total pre-treatment PAC activity, number of recipients, partisan contribution profile, and election-cycle timing.

Candidate-level characteristics of the scandal-linked politician may also be included as moderators: scandal type, scandal salience, committee position, leadership status, party, electoral safety, and eventual retirement or resignation.

## Reasons for Caution

The main challenge is that firms connected to scandal-tainted politicians may differ systematically from firms not connected to such politicians. They may be more politically active, more access-oriented, more partisan, more involved in controversial sectors, or more willing to support risky politicians. Matching on pre-treatment giving behavior is therefore essential.

Another challenge is that the timing of scandal exposure may coincide with broader campaign-cycle dynamics. Firm PACs may change total giving over the course of an election cycle for reasons unrelated to scandal. Period fixed effects, election-cycle timing controls, and matched pseudo-event dates for control firms are therefore important.

## Why Additional Designs Are Needed

This design estimates firm-wide chilling, but it does not reveal whether firms specifically abandon the scandal-tainted politician. A firm may reduce overall giving while maintaining support for the tainted politician, or it may withdraw from the tainted politician while maintaining overall activity. Therefore, this design complements rather than replaces the relationship-level and same-firm substitution designs.

# Design 3: Scandal Retirement Versus Ordinary Retirement

### Objective

The objective of this design is to distinguish the reputational effect of scandal-driven retirement from the ordinary lame-duck effect of retirement. A retiring member may still hold office, retain committee access, and receive contributions, but the value of giving may decline because the member will not seek reelection. Comparing scandal-driven retirements to non-scandal retirements helps identify whether scandal adds an additional stigma beyond ordinary retirement.

### Question Answered

Do firms respond more negatively to scandal-driven retirement announcements than to otherwise comparable non-scandal retirement announcements?

### Unit of Analysis

The preferred unit of analysis is the firm PAC–candidate–cycle or firm PAC–candidate–period. The firm-candidate-cycle level is especially useful because firms can and may still contribute to members who have announced retirement, but the relevant behavior may be better observed across the remainder of the cycle than in a short monthly window.

### Sample

The sample includes firm-candidate relationships involving members who announce retirement. Treated cases are scandal-connected retirements. Control cases are ordinary retirements not connected to scandal. The preferred sample includes firms that contributed to the retiring member before the retirement announcement and had remaining legal capacity to contribute afterward.

### Treatment Group

The treatment group consists of firm-candidate relationships involving members whose retirement announcements are connected to scandal. The event date is the retirement announcement date, denoted $t_R$. In some cases, $t_R$ occurs after $t_0$, so the design should distinguish the initial scandal break from the later retirement announcement.

### Control Group

The control group consists of firm-candidate relationships involving members who retire for non-scandal reasons. These members should be matched to scandal-retirement members on party, chamber, incumbency, committee assignment, leadership status, seniority, electoral safety, prior fundraising, prior corporate PAC support, and time within the election cycle.

### Causal Inference Tools

The main tools are DiD and event-study models around the retirement announcement date. Matching is especially important because retirement is not random. One can match scandal retirements to ordinary retirements using only pre-announcement characteristics.

This design can also be combined with spillover analysis by examining whether firms redirect contributions from the retiring scandal-tainted member to successors, same-party candidates, same-state delegation members, committee substitutes, party committees, or leadership PACs.

### Regression Equation

A candidate-period retirement model can be written as:

$Y_{ijt} = \beta(ScandalRetire_j \times PostRetire_{jt}) + \alpha_{ij} + \delta_t + X_{jt}'\theta + \epsilon_{ijt}.$

Here, $ScandalRetire_j$ equals one for scandal-connected retirements, and $PostRetire_{jt}$ begins after the retirement announcement.

A matched-set version can be written as

$Y_{ijgt} = \beta(ScandalRetire_j \times PostRetire_{jt}) + \alpha_{ij} + \lambda_{gt} + \epsilon_{ijgt}.$

where $g$ indexes matched sets of scandal exits and ordinary exits. This specification compares the contribution response to scandal-driven exits against the response to ordinary lame-duck or exit events.

### Potential Control Variables

Potential controls include seniority, committee assignment, leadership status, party, chamber, ideology, pre-announcement fundraising, cash on hand, district partisanship, electoral competitiveness, time to Election Day, prior corporate PAC support, firm industry, firm size, prior firm-candidate giving, and remaining contribution capacity.

### Reasons for Caution

Even ordinary retirement is not random. Members who retire may differ from those who run again, and scandal-driven retirements may differ from ordinary retirements in visibility, severity, media attention, and political context. This design should therefore be framed as comparing types of retirement rather than fully randomizing scandal status.

Retirement is also a downstream response to scandal. If the purpose is to estimate the total effect of scandal revelation, retirement should not be controlled away. But if the purpose is to distinguish scandal stigma from lame-duck effects, comparing scandal retirements to ordinary retirements is useful.

### Why Additional Designs Are Needed

This design helps separate scandal stigma from the ordinary decline in access value caused by retirement. However, it does not cover resignation, where the candidate often exits office and contribution opportunities disappear. Resignation therefore requires a different design, likely at the firm-cycle level.

# Design 4: Scandal-Driven Resignation Versus Ordinary Resignation

## Objective

The objective of this design is to study whether firms connected to a resigning scandal-tainted politician reduce political activity more generally or redirect political money after the politician exits office. Unlike retirement, resignation sharply reduces or eliminates the possibility of continued contributions to the member. Therefore, resignation is less useful for studying firm-candidate continuation and more useful for studying firm-level chilling, substitution, and spillover.

## Question Answered

When a politician connected to a firm resigns under scandal, does the firm reduce political activity in the remainder of the cycle, or does it redirect contributions to replacement candidates, copartisans, committee substitutes, or party organizations? Is this response different from the response to non-scandal resignations?

## Unit of Analysis

The preferred unit of analysis is the firm PAC–cycle or firm PAC–recipient-category–cycle. A firm-candidate-period design is less useful because contributions to the resigning politician may no longer be possible or meaningful after resignation.

## Sample

The sample includes firms that contributed before resignation to members who later resign. Treated cases are firms connected to scandal-driven resignations. Control cases are firms connected to ordinary or non-scandal resignations. The analysis can focus on the remainder of the election cycle after resignation.

## Treatment Group

The treatment group consists of firms that had contributed to a politician who resigned in connection with scandal. The event date is the resignation announcement or effective resignation date, denoted $t_S$. In some cases, the announcement and effective date may differ; the announcement date is more relevant for donor information, while the effective date is more relevant for loss of office.

## Control Group

The control group consists of firms that had contributed to politicians who resigned for non-scandal reasons. Control resignation cases should be matched on party, chamber, committee position, seniority, leadership status, district or state context, prior corporate PAC support, and time within the election cycle.

## Causal Inference Tools

The main tools are firm-level DiD, matched comparisons, and recipient-category allocation models. Matching is needed because resignations are rare and highly selected. The design should compare firms connected to scandal resignations against firms connected to non-scandal resignations and examine post-resignation changes in total giving, same-party giving, committee-relevant giving, and giving to replacement candidates.

This design is especially useful for spillover analysis. Because the original recipient exits, firms must either stop giving, redirect money, or shift to alternative political channels. The allocation of post-resignation contributions can reveal whether the effect is generalized chilling or substitution to safer access points.

## Regression Equation

A firm-cycle chilling model for resignation can be written as:
$Y_{ic}^{-j} = \beta(ScandalResign_i \times PostResignCycle_{ic}) + \alpha_i + \delta_c + W_{ic}'\theta + \epsilon_{ic}.$

Here, $Y_{ic}^{-j}$ denotes firm $i$'s political activity in cycle $c$, excluding contributions to the resigning politician. $ScandalResign_i$ indicates that firm $i$ was connected to a scandal-driven resignation, and $PostResignCycle_{ic}$ identifies the remainder of the cycle after resignation.

A matched-set version can be written as:
$Y_{igc}^{-j} = \beta(ScandalResign_i \times PostResignCycle_{gc}) + \alpha_i + \lambda_{gc} + W_{ic}'\theta + \epsilon_{igc}.$

## Potential Control Variables

Potential controls include firm size, industry, pre-resignation PAC activity, partisan giving profile, number of pre-resignation recipients, prior relationship strength with the resigning member, member seniority, committee assignment, leadership status, party, chamber, time to Election Day, and whether a special election or replacement process occurs.

## Reasons for Caution

Resignation is highly endogenous to scandal severity. Scandal-driven resignations are likely to be more severe and salient than non-resignation scandals. Non-scandal resignations may also be unusual and difficult to compare. The design should therefore be framed as comparing donor responses to different kinds of exit rather than estimating the initial causal effect of scandal revelation.

Because resignation often eliminates the direct contribution opportunity, non-giving to the resigned member should not be interpreted as donor withdrawal. The meaningful outcomes are firm-wide political activity and redistribution across other recipients.

## Why Additional Designs Are Needed

This design is valuable for studying chilling and substitution after the loss of an access point, but it cannot answer whether firms would have continued supporting the scandal-tainted politician had the politician remained in office. That question belongs to Design 1 and the retirement design.

# Design 5: Spillover and Substitution Design

## Objective

The objective of this design is to examine whether scandal effects extend beyond the scandal-tainted politician and whether firms redirect political money toward alternative recipients. This design turns the spillover concern into a substantive empirical question rather than treating it only as a threat to identification.

## Question Answered

Do firms reduce giving only to the scandal-tainted politician, or do they also change giving to politically adjacent candidates, successors, substitutes, or opponents?

## Unit of Analysis

The unit of analysis can be firm PAC–candidate–period, firm PAC–recipient-category–period, firm PAC–candidate–cycle, or firm PAC–recipient-category–cycle. For retirement cases, firm-candidate-cycle designs may capture whether firms continue giving to the retiring member and whether they redirect money in the same cycle. For resignation cases, firm-recipient-category-cycle designs may be more appropriate because the original candidate often exits the contribution market.

## Sample

The sample includes firms with preexisting ties to scandal-tainted politicians and their broader contribution portfolios. It should also include politically adjacent candidates who may be affected by spillovers or substitution.

For retirement and resignation cases, the sample should include possible successors, same-party candidates, same-state delegation members, same-committee members, opponents, and other institutionally relevant substitutes.

## Treatment Group

The direct treatment recipient is the scandal-tainted politician. Potential spillover recipients include copartisans in the same state delegation, members of the same committee, ideological allies, replacement candidates, successors, and opponents.

For retirement and resignation designs, treatment can also be defined by connection to a scandal-driven exit. The relevant question becomes whether firms connected to scandal exits reallocate differently than firms connected to ordinary exits.

### Control Group

The control group should consist of candidates or recipient categories unlikely to be affected by the scandal, matched on party, chamber, committee relevance, electoral context, and prior firm support. Likely spillover or substitute recipients should not be used as controls in the main relationship-level design. They should instead be treated as separate outcome categories.

For exit-related spillovers, the control group can be firms connected to non-scandal retirements or non-scandal resignations. This allows the analysis to compare ordinary replacement or access-substitution behavior to scandal-related replacement or avoidance behavior.

### Causal Inference Tools

The design can use event-study models, DiD models, recipient-category allocation models, and network-based definitions of political proximity. Political adjacency can be defined through shared party, shared state delegation, shared committee, ideological proximity, leadership ties, successor status, opponent status, or prior co-receipt of contributions from the same firms.

Network-based measures may also be useful. Political adjacency can be defined through shared party, shared state delegation, shared committee, ideological proximity, leadership ties, or prior co-receipt of contributions from the same firms.

### Regression Equation

A recipient-category allocation model can be written as:

$Y_{irt} = \sum_{r \in R}\beta_r(Post_{it} \times RecipientCategory_{ir}) + \alpha_i + \delta_t + \mu_r + \epsilon_{irt}.$

Here, $r$ indexes recipient categories, such as the scandal-tainted politician, same-party same-state politicians, same-committee politicians, ideological allies, replacement candidates, opponents, party committees, and leadership PACs.

At the firm-candidate level, a direct-and-spillover model can be written as:

$Y_{ijt} = \beta_1(DirectlyTainted_j \times Post_{jt})$
+ $\beta_2(SpilloverCandidate_j \times Post_{jt})$
+ $\alpha_{ij} + \gamma_{it} + \delta_t + \epsilon_{ijt}.$

The coefficient $\beta_1$ captures direct withdrawal from the scandal-tainted politician, while $\beta_2$ captures spillover to politically adjacent candidates. With firm-period fixed effects, $\gamma_{it}$, the model asks whether the firm reallocates its giving away from or toward particular recipient categories, conditional on total giving in that period.

A substitution-focused version can use the firm’s total giving share to each category:

$Share_{irt} = \sum_{r \in R} \beta_r (Post_{it} \times RecipientCategory_{ir}) + \alpha_i + \delta_t + \mu_r + \epsilon_{irt}.$

This version is useful for testing whether money withdrawn from the scandal-tainted politician is redirected to successors, committee substitutes, copartisans, opponents, or party committees.

For exit-related spillovers, the design can compare scandal exits to ordinary exits:
$Y_{irc} = \sum_{r \in R}\beta_r(ScandalExit_i \times PostExitCycle_{ic} \times RecipientCategory_{ir}) + \alpha_i + \delta_c + \mu_r + \epsilon_{irc}.$

This specification is especially useful for retirement and resignation cases. It asks whether firms connected to scandal-driven exits reallocate contributions differently from firms connected to ordinary exits.

### Potential Control Variables

Potential controls include candidate party, chamber, committee assignment, leadership status, ideology, district partisanship, electoral competitiveness, prior fundraising, prior firm support, successor status, opponent status, firm industry, firm size, firm partisan profile, and election-cycle timing.

### Reasons for Caution

Spillover analysis is theory-dependent. Same-party candidates may be substitutes, contaminated controls, or unaffected controls depending on the scandal type. Committee colleagues may receive redirected access-seeking money, but they may also be avoided if the scandal implicates a policy network or institutional environment. For this reason, the spillover design should be framed as a mechanism and allocation analysis rather than the main identification strategy.

# Recommended Paper Structure

The empirical section can be organized as a cumulative sequence of designs.

First, present descriptive timelines and raw contribution patterns around $t_0$. This establishes the empirical setting and shows how contribution behavior evolves around scandal revelation, investigation, retirement, resignation, and other downstream events.

Second, present the combined relationship-level design. This estimates whether prior connected firms reduce giving to scandal-tainted politicians after the scandal becomes public, using both matched non-scandal politicians and within-firm recipient comparisons.

Third, present the firm-level chilling design. This asks whether firms exposed to scandal through a prior political tie reduce political activity more generally.

Fourth, present the scandal-retirement design. This compares scandal-driven retirement to ordinary retirement, separating reputational stigma from the normal lame-duck effect.

Fifth, present the scandal-resignation design. This treats resignation as a firm-cycle shock and studies firm-level chilling and redistribution after the loss of a political access point.

Sixth, present spillover and substitution analyses. These examine whether firms redirect money to successors, committee substitutes, copartisans, opponents, party committees, or leadership PACs.

# Summary of Identification Logic

The designs should be understood as complementary rather than competing. The combined relationship-level design estimates whether firms reduce support for scandal-tainted politicians. The firm-level chilling design estimates whether scandal exposure reduces political activity more broadly. The retirement design separates scandal stigma from ordinary lame-duck effects while retaining the possibility of continued contributions to the retiring member. The resignation design shifts the analysis to the firm-cycle level because direct contributions to the resigned politician are no longer meaningful. The spillover design examines whether scandals contaminate adjacent political networks or induce substitution toward safer access points.

Together, these designs allow the paper to move beyond the simple question of whether scandal-tainted politicians receive less money. The broader contribution is to show how firms reallocate political engagement under reputational threat, and whether their responses are best understood as targeted avoidance, firm-wide chilling, access-value loss, candidate replacement, or political spillover.
