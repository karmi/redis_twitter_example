#!/bin/bash

## Redis Twitter Example
#
### An Executable Tutorial

# This file contains a tutorial explaining core concepts of the [_Redis_](http://redis.io/)
# database, dressed as a fully working bash script. All the words in UPPERCASE are _Redis_
# built-in commands. All the words in lowercase are parameters for those commands. The
# `redis-cli` binary is aliased as `%` throughout the script.

# The tutorial implements a much simplified _Twitter_ “clone”, loosely based on the
# now classic [_TwitterAlikeExample_](http://redis.io/topics/twitter-clone)
# by [`@antirez`](http://twitter.com/antirez).

# You may copy and paste snippets from this file, or run it directly:
#
#     $ bash redis_twitter_example.sh
#

# <img src="http://github.com/favicon.ico" style="position:relative; top:2px">
# The full source code for this tutorial is available at
# <http://github.com/karmi/redis_twitter_example>.

# ---------------------------------------------------------------------------------------

# First, let's create some aliases for better code readability:
#
shopt    -s expand_aliases

# to get current time,
#
alias    t="date +%H:%M"

# to define the _Redis_ database used,
#
export   db="13"

# to simplify using the `redis-cli` command,
#
alias    %="redis-cli -n $db"

# and to simplify displaying notices in the terminal.
#
function  + () { echo; echo -e "# \033[1m$@\033[0m"; for i in {1..60}; do echo -n '‾'; done; echo; }

# Second, let's wipe the selected _Redis_ database clean.
#
% FLUSHDB

# OK. We're ready to add some users to our “twitter”. We will use a _set_ for storing users.
#
+ "Let's add some users, A and B"
% SADD users A
% SADD users B

# Let's make user A follow user B. We will use a _set_ for storing the relationship,
# again. Notice it's the first place where we denormalize the data, storing both
# sides of the relationship in separate sets.
#
+ "User A follows user B"
% SADD users:A:following B
% SADD users:B:followers A

# We will add another user, C.
#
+ "Let's add another user, C"
% SADD users C

# B is quite popular, so C will follow him as well.
#
+ "User C follows user B"
% SADD users:C:following B
% SADD users:B:followers C

# A follows nearly everybody, so let him follow C.
#
+ "User A follows user C"
% SADD users:A:following C
% SADD users:C:followers A

# Now, let's have a look at the relationships we have here.
# We can see A is really not being followed by anyone.
#
+ "Display A's followers"
% SMEMBERS users:A:followers

# B, as said, is quite popular, and is being followed by both A and C.
#
+ "Display B's followers"
% SMEMBERS users:B:followers

# And C is being followwed by A.
#
+ "Display C's followers"
% SMEMBERS users:C:followers

# It's quite easy to display statistics such as “which users follow A and C”
# in common:
#
+ "Who is followed by both A and C?"
% SINTER users:A:following users:C:following

# or display those of C's followers who are not being followed back:
#
+ "Who is not followed back by C?"
% SDIFF users:C:followers users:C:following

# OK, it's time for B to tweet something. We'll be storing the message in
# a corresponding variable.
#
# We will store the published time and message body directly in the message
# itself. (In real world, we would most probably use JSON and not some crazy
# custom serialization format, obviously.)
#
message="$(t);Message from B"
+ "B publishes message '$message'"

# We will see how “query-needs” based schema, often called “denormalization”
# in the RDBMS world, really plays here.
#
# We're optimizing for the maximum **read performance**.

# First, we have to push the message to the global timeline, possibly
# displayed on the “twitter” homepage. We will use a Redis _list_
# for storing the tweets: that will allow us to efficiently get
# parts of the list, trim its size when needed, and the messages
# will be automatically ordered by the time of publication.
#
% LPUSH global:timeline "$message"

# Second, we will push the message to the B's own timeline.
#
% LPUSH users:B:timeline "$message"

# And, most importantly, third, we have to push the message into
# the timleine, or “inbox” of every user following B, which is A and C in our case.
# This will be a bit more tricky.

# First, we have to get a list of all followers of B.
#
% SMEMBERS users:B:followers | \

# Then, we have to iterate over this list, and push B's message
# into the timeline of each relevant user.
#
while read u; do
  % LPUSH users:$u:timeline "$message"
done

# Now, let C tweet something, as well.
#
message="$(t);Message from C"
+ "C publishes message '$message'"

# We have to run through the loop once again:

# 1) push the message to the global timeline,
#
% LPUSH global:timeline "$message"

# 2) push the message to C's own timeline,
#
% LPUSH users:C:timeline "$message"

# 3) and push the message to C's followers timelines
#
% SMEMBERS users:C:followers | \
while read u; do
  % LPUSH users:$u:timeline "$message"
done

# Finally, let A tweet something as well. We know the drill, by now.
#
message="$(t);Message from A"
+ "A publishes message '$message'"

# We have to push the message to:

# 1) the global timeline,
#
% LPUSH global:timeline "$message"

# 2) A's own timeline,
#
% LPUSH users:A:timeline "$message"

# 3) all A's followers timeline (empty in this case).
#
% SMEMBERS users:A:followers | \
while read u; do
  % LPUSH users:$u:timeline "$message"
done

# Now would be a good time to display some tweets.

# Let's display A's timeline, trimming it to 10 messages.
# We can see it contains three tweets: from A himself, C, and B,
# in the reversed order they were published, effectively
# making it a [LIFO queue](http://en.wikipedia.org/wiki/LIFO).
#
+ "A's timeline:"
% LRANGE users:A:timeline 0 9

# How does B's timeline look like? It contains just his own tweet.
#
+ "B's timeline:"
% LRANGE users:B:timeline 0 9

# And C's timeline? It contains his own tweet, first, and an earlier
# tweet from B, second.
#
+ "C's timeline:"
% LRANGE users:C:timeline 0 9

# We can just as easily display the global timeline, trimming it to
# just the single last tweet from A.
#
+ "Global timeline (last message):"
% LRANGE global:timeline 0 0

# Of course, we are esentially duplicating the same message in all the user
# timelines. This way, we would eat out RAM very quickly. How much memory
# does our “twitter” use now?
#
+ "Memory usage:"
% info | 'grep' "used_memory_human"

# We can de-duplicate the messages by storing them by ID, and storing
# only those IDs in user timelines, instead of full messages.
# Let's have a shot at that.

# ---------------------------------------------------------------------------------------

# OK, let's clear everything first.
#
% FLUSHDB

# Now, let's add some users, again, this time in batch.
#
+ "Adding users A, B and C"
% SADD users A B C

# Let's add the relationships:
#
# * A follows B and C
# * C follows B
# * B does not follow anybody
#
+ "User A follows user B and C"
% SADD users:A:following B C
% SADD users:B:followers A
% SADD users:C:followers A
+ "User C follows user B"
% SADD users:C:following B
% SADD users:B:followers C

# Let B tweet something, again.
#
message="$(t);Message from B"

# We will store every tweet under a separate key, with a unique ID.

# We'll get a unique, “auto-incrementing” ID from _Redis_,
# saving it in a `$id` variable.
#
id="$( % INCR tweets:next_id )"
+ "B publishes message '$message' with ID '$id'"

# Let's store the message content under a separate key, using the ID.
#
% SET tweets:$id "$message"

# Can we get it back? Sure thing.
#
% GET tweets:1

# Now, we have to push the ID to all the timelines, as in the previous implementation:

# the global timeline,
#
% LPUSH global:timeline $id

# B's own timeline,
#
% LPUSH users:B:timeline $id

# all the B's followers timelines.
#
% SMEMBERS users:B:followers | \
while read u; do
  % LPUSH users:$u:timeline "$id"
done

# We should now have the tweet ID stored in all relevant timelines.

# Let's have a look at the global one:
#
+ "Global timeline (IDs):"
% LRANGE global:timeline 0 -1

# We get back only the IDs. When we want to retrieve the messages itself, we have
# to fetch them from the relevant keys:
#
+ "Global timeline (messages):"
#
# We will simply replace every numeric ID with the corresponding key in the form `tweets:<ID>`...
#
tweet_ids=$( % LRANGE global:timeline 0 9 | sed 's/^/tweets:/' )
#
# ... and feed it to the [`MGET`](http://redis.io/commands/mget) command.
#
% MGET $tweet_ids

# Now, let C tweet something, again.

# We need to get some ID.
#
id="$( % INCR tweets:next_id )"

# We'll store the message content under a separate key, again.
#
message="$(t);Message from C"
+ "C publishes message '$message' with ID '$id'"
% SET tweets:$id "$message"

# Now, we have to push the ID to all the relevant timelines, again:

# the global timeline,
% LPUSH global:timeline $id

# C's own timeline,
#
% LPUSH users:C:timeline $id

# and all the C's followers timelines.
#
% SMEMBERS users:C:followers | \
while read u; do
  % LPUSH users:$u:timeline "$id"
done

# And finally, let's repeat everything for A as well:
#
# 1. Getting the unique ID
# 2. Storing the message
# 3. Pushing it to the global timeline
# 4. Pushing it to the author's timeline
# 5. Pushing it to the author followers' timelines
#
id="$( % INCR tweets:next_id )"
message="$(t);Message from A"
+ "A publishes message '$message' with ID '$id'"

% SET tweets:$id "$message"

% LPUSH global:timeline $id

% LPUSH users:A:timeline $id

% SMEMBERS users:A:followers | \
while read u;do
  % LPUSH users:$u:timeline "$id"
done

# Now would be a good time to display the timelines, again.

# Note, that we cannot simply pull messages from the timelines,
# since we are storing only IDs. We have to feed the fetched
# IDs to the `MGET` command, as we'va seen a while ago.

# A's timeline.
#
+ "A's timeline:"
% MGET $( % LRANGE users:A:timeline 0 9 | sed 's/^/tweets:/' )

# B's timeline.
#
+ "B's timeline:"
% MGET $( % LRANGE users:B:timeline 0 9 | sed 's/^/tweets:/' )

# C's timeline.
#
+ "C's timeline:"
% MGET $( % LRANGE users:C:timeline 0 9 | sed 's/^/tweets:/' )

# The global timeline.
#
+ "Global timeline:"
% MGET $( % LRANGE global:timeline 0 9 | sed 's/^/tweets:/' ) 

# How does our RAM usage look now? You can see it's actually _larger_ then
# in the previous case, most probably because we're using a slightly
# larger pool of keys now. There's no free lunch in computer science.
#
+ "Memory usage:"
% info | 'grep' "used_memory_human"

# ---------------------------------------------------------------------------------------

# You may wonder, now, how we display the count of tweets authored by a specific user,
# for instance. Actually, there's no way to do that.
#
# One solution would be to continue with the simple “query-based” schema, and
# just keep track of counts manually, in a counter such as `users:A:tweets:count`.
#
# Another solution would be to use a [_sorted set_](http://redis.io/commands#sorted_set)
# for user's own tweets, one set per user, using timestamp as the score.
#
# Naturally, we would want to keep the “query-based” perspective when modelling the
# data, so we would store the messages (or their IDS) in additional user “inboxes” anyway.
# If we'd use sorted sets instead of lists, it would allow us interesting operations,
# such as intersections of their timelines, eg. “display timelines of all your followers”.
#
# The thing to keep in mind at all times is that we don't have any efficient technique
# to query data based on _value_. There's no `SELECT ... WHERE column = 'something'`.
#
# As you may know, a “traditional database” uses and _index_ on this column to be able
# to efficiently perform such a query, without doing a full table scan.
#
# In fact, those “de-normalized” data are just _indices_ in the traditional database
# sense. We're managing these _indices_ manually, and deciding upon their design and
# implementation ourselves. While absolutely transparent to us, it obviously involves
# a lot of “manual” labor. It depends on your point of view, your values and tastes,
# your education and experience, and your application domain, if you scream with
# joy or sorrow upon hearing that.
