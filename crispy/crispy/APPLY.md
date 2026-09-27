# CRISpy v20

All twenty two production queries, the pin layer, and A&E's eighteen validation
cases canned.

## Apply

Unzip over the project root, then:

    docker compose up -d --build

Nothing in the database changed. The SQL files are the v20 notebooks byte for
byte, so a query rendered here is the query that was reviewed.

## What is new

### The queries

Six became twenty two. Section 1 was already here; Section 2 and Section 3 are
new, and the Section 1 files were refreshed from v20 so nothing is a version
behind.

`app/sql/` now holds q11 through q15, q21 through q213, and q31 through q34.
`specs.py` carries a spec for each: what it answers, how the router recognises
it, which parameters it exposes, which of them a question cannot proceed
without, and what everything else falls back to.

### The pin layer, `app/pins.py`

This is the part worth reading, because it is the thing that was not there
before and it is where a correct-looking answer used to go wrong.

Most parameters get a value one of two ways: the question supplies it, or it
falls to a documented default and the query resolves it. There is a third way,
and it is the one that is easy to lose. Some parameters have to be set
**explicitly**, to a value that is **not** the query's default, because that is
what reproduces A&E's own method. Nobody writes them in the question. A&E do not
write them on their sheets either. They were derived by reconstructing published
figures, and every one of them is anchored to a number that matched.

Ask 2.2 about any premiere, on any network, and the norm has to run from the
start of the fiscal year to the day before that premiere, clipped to prime 8p to
11p, with Curse of Oak Island left in and specials left in. The question never
says any of that. Left to the defaults the query still runs, still returns rows,
and returns the wrong norm: 209 where A&E publish 250.

There are two kinds.

**Method pins** are unconditional. 2.2 gets six, 2.1 gets two, 2.7 gets one, 3.1
gets one, 3.3 gets two. Each carries the reason it exists and the figure it was
derived from.

**Conditional pins** depend on what the question turns out to be about rather
than on what it says. A movie question moves three parameters at once, and a
person will not think to mention any of them: movies are excluded by default
because that is right for a series, Lifetime's movies are flagged as specials so
leaving specials out deletes the slate, and the film's title is the EPISODE
because the PROGRAM is the bucket it was bought under. All three have to move
before the answer can name the film.

Why a module and not prompt text. A model asked to remember eleven method rules
will remember most of them most of the time, and the failures are silent. A pin
applied in code is applied every time, and it appears in the parameter table
with its reason attached, so the person reading the answer can see what was set
on their behalf and why.

Two guards on the pin layer itself:

A pin whose value depends on a date it does not have is **not** applied. It
leaves a note saying the norm could not follow A&E's method without one, rather
than silently falling back to a trailing window.

A pin that never reaches a SET line is dropped from the list and turned into a
note. A pin that reports itself as applied when it was not is worse than no pin
at all, because it says the method was followed when it was not.

### The extraction flags

`Params` gained `is_movie_question`, `names_fiscal_year`, `has_published_cutoff`
and `premiere_date`. These are what the pins key off, and they are now the most
consequential things the extraction step produces. The prompt says so, and also
says which parameters are **not** the model's to set: the norm window, the prime
clip, the Curse rule, the slot threshold. Those are pinned afterwards and would
overwrite anything it put there. Its job is the question, not the method.

### The coverage guards

C3 and C7 carry no quarter-hour rows and no half-hour rows. The quarter-hour
guard was already here; the half-hour one is new, and it is the bigger hole,
because every dayparted answer is built on half hours.

This is A&E's R_2, the one case in their whole workbook that cannot be answered.
It is now said before the query runs rather than discovered as an empty table
afterwards, which matters: an empty ranker reads exactly like a quiet period.

### `app/validation.py`

A&E's eighteen cases, canned. Every one has been run in Snowflake and matched a
published figure, so the parameters recorded against each are known to be the
parameters that reproduce it.

This is the fixed point. The SQL is settled and the figures are settled, so a
wrong answer from here is a routing or a parameter mistake, and this file is how
you tell which.

Two things when reading `params`:

Fields the question supplies are written as a person would say them. Fields
CRISpy pins on its own are deliberately **absent**, because they are not
something the extraction step should produce. `p_norm_from` on 2.2 is not a
parameter anybody asks for. Checking for it would mark a correct extraction as
wrong.

`expects` is what the run should return, which is a different test from what the
extraction should produce. A case can extract perfectly and still return a
different number if a table is stale, and separating the two is the point of
writing both down.

## What has not changed

No SQL was edited. The renderer still rewrites the SET lines at the top and
touches nothing below them.

The resolver is untouched, and still runs real SQL against the two CSVs in
SQLite so that whoever ports it to CRIS is moving tested SQL rather than
inventing it.

## Worth knowing before the next session

**R_2 is not fixable here.** C3 has no half hours. A&E's own footer says their
C3 dayparts are programme based and commercial duration weighted, which would
make it answerable from the total-programme table, but that is a question for
them rather than a patch.

**R_1 has one open item and it is not a parameter.** Three 90 Day companion
strands appear as their own rows in our ranker and are consolidated into the
parent series on A&E's sheet. The figures reconstruct exactly: their 21 telecasts
and 2,544 minutes for Before the 90 Days are our 19 plus the Tell All's 2, and
2,302 minutes plus 242, which weight to their 603. What cannot be derived is the
link, because the programme codes are unrelated. It needs a rollup mapping from
A&E.

**LFT is still an assumption.** It is in the catalogue as an alias for LIF and it
works, and A&E use it in their own questions, but nobody has confirmed it. Same
class as VICE's default demo.

**Nielsen truncates PROGRAM_NAME at 25 characters.** The resolver exists because
of it. `%SKINWALKER%` matches both SECRET SKINWALKER RANCH and BEYOND SKINWALKER
RANCH, so a question about one comes back as two series averaged together.
EPISODE_NAME is truncated too, and not at the same width.
