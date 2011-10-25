#!/bin/bash

## Redis Twitter Example
#
### An Executable Tutorial

# This file contains a tutorial explaining core concepts of the [_Redis_](http://redis.io/)
# database, dressed as a fully working bash script. All the words in UPPERCASE are _Redis_
# built-in commands. All the words in lowercase are parameters for those commands.

# The tutorial implements a simplified _Twitter_ clone, loosely based on the now classic
# [_TwitterAlikeExample_](http://redis.io/topics/twitter-clone)
# by [`@antirez`](http://twitter.com/antirez).

# You may copy and paste snippets from this file, or run it directly:
#
#     $ bash redis_twitter_example.sh
#

# <img src="http://github.com/favicon.ico" style="position:relative; top:2px">
# The full source for this tutorial is available at <http://github.com/karmi/redis_twitter_example>.

# ---------------------------------------------------------------------------------------

# First, let's create some aliases for better code readability.
#
shopt    -s expand_aliases
alias    t="date +%H:%M"
export   db="13"
alias    %="redis-cli -n $db"
function  + () { echo; echo -e "# \033[1m$@\033[0m"; for i in {1..60}; do echo -n '‾'; done; echo; }

# Second, let's wipe the selected _Redis_ database clean.
#
% FLUSHDB

# OK. We're ready to add some users to our “twitter”. We will use a _set_ for storing users.
#
+ "Let's add some users, A and B"
% SADD users A
% SADD users B

# Let's make user A follow user B. We will use a _set_ for this, again.
# Notice the first place where we denormalize the data, storing both
# sides of the relationship in discrete sets.
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

# OK, it's time for B to tweet something.
#
# We will store the published time and message body directly in the message
# itself. In real world, we would just use JSON.
#
export message="$(t);Message from B"
+ "B publishes message '$message'"


# We will see how “query-needs” based schema, often called “denormalization”
# in the RDBMS world really play here. We're optimizing for the maximum **read
# performance**.

# First, we have to push the message to the global timeline, possibly
# displayed on the “twitter” homepage. We will use a Redis _list_
# for storing the tweets.
#
% LPUSH global:timeline "$message"

# Second, we will push the message to the B's own messages list.
#
% LPUSH users:B:timeline "$message"

# And, most importantly, third, we have to push the message into
# the “inbox” of every user following B, which is A and C in our case.
# This will be a bit more tricky.

# First, we have to get a list of all followers of B.
#
% SMEMBERS users:B:followers | \

# Then, we have to iterate over this list, and push B's message
# into the timeline of each user.
#
# We'll cheat here, and JUST USE RUBY, reading the list from standard input.
#
ruby -e "
  followers = STDIN.read.split(\"\n\")
  message   = ENV['message']

  followers.each do |f|
    system %Q|redis-cli -n #{ENV['db']} LPUSH users:#{f}:timeline '#{message}'|
  end
"

# Now, let C tweet something, as well.
#
export message="$(t);Message from C"
+ "C publishes message '$message'"

# We have to run through the loop once again.

# 1) push the message to the global timeline,
#
% LPUSH global:timeline "$message"

# 2) push the message to C's own timeline,
#
% LPUSH users:C:timeline "$message"

# 3) push the message to C's followers timelines
#
% SMEMBERS users:C:followers | \
ruby -e "
  followers = STDIN.read.split(\"\n\")
  message   = ENV['message']

  followers.each do |f|
    system %Q|redis-cli -n #{ENV['db']} LPUSH users:#{f}:timeline '#{message}'|
  end
"

# And finally, let A tweet something as well. We know the drill, now.
#
export message="$(t);Message from A"
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
ruby -e "
  followers = STDIN.read.split(\"\n\")
  message   = ENV['message']

  followers.each do |f|
    system %Q|redis-cli -n #{ENV['db']} LPUSH users:#{f}:timeline '#{message}'|
  end
"

# Now would be the good time to display some tweets.

# Let's display A's timeline, trimming it to 10 messages.
# We can see it contains two tweets, from C and B, in reversed
# order they were published: C's tweet comes first.
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

# We can just as easily display the global timeline.
#
+ "Global timeline:"
% LRANGE global:timeline 0 9

# Of course, we are esentially duplicating the same message in all the user
# timeline. This way, we would eat out RAM very quickly. How much memory
# does our “twitter” use now?
#
+ "Memory usage:"
% info | \grep "used_memory_human"

# We can de-duplicate the messages by storing them by ID, and storing
# only those IDs in user timelines, instead of full messages.
# Let's have a shot at that.

# OK, let's clear everything first.
#
% FLUSHDB

# Now, let's again add some users.
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

# Let B tweet something.
#
export message="$(t);Message from B"

# We will store every tweet in under a separate key, with unique ID.

# Let's get a unique, “auto-incrementing” ID, saving it in a `$id` variable.
#
export id="$( % INCR tweets:next_id | tr -d " " )"
+ "B publishes message '$message' with ID '$id'"

# Let's store the message content under a key.
#
% SET tweets:$id "$message"

# Can we get it back? We can.
#
% GET tweets:1

# Now, we have to push the ID to all the timelines, as in the previous implementation.

# The global timeline,
% LPUSH global:timeline $id

# B's own timeline,
#
% LPUSH users:B:timeline $id

# all B's followers timeline.
#
% SMEMBERS users:B:followers | \
ruby -e "
  followers = STDIN.read.split(\"\n\")
  id        = ENV['id']

  followers.each do |f|
    system %Q|redis-cli -n #{ENV['db']} LPUSH users:#{f}:timeline '#{id}'|
  end
"

# We should now have the tweet ID stored in relevant timelines.

# Let's have a look on the global one:
#
+ "Global timeline (IDs):"
% LRANGE global:timeline 0 -1

# We get back only the IDs. When we want to retrieve the messages itself, we have
# to fetch them from the relevant keys. It's kinda tricky with the command
# line client, but doable.
#
+ "Global timeline (messages):"
% LRANGE global:timeline 0 -1 | \
xargs echo | \
# We will simply replace every numeric ID with the corresponding key in the form `tweets:<ID>`...
sed 's/\([0-9]\)/tweets:&/g' | \
# ... and feed it to the `redis-cli`'s [`MGET`](http://redis.io/commands/mget) command.
xargs redis-cli -n $db MGET


# Now, let C tweet something, again.

# Let's get some ID, again
#
export id="$( % INCR tweets:next_id | tr -d " " )"

# Let's store the message content under a key, again.
#
export message="$(t);Message from C"
+ "C publishes message '$message' with ID '$id'"
% SET tweets:$id "$message"

# Now, we have to push the ID to all the timelines, again.

# The global timeline,
% LPUSH global:timeline $id

# C's own timeline,
#
% LPUSH users:C:timeline $id

# all C's followers timeline.
#
% SMEMBERS users:C:followers | \
ruby -e "
  followers = STDIN.read.split(\"\n\")
  id        = ENV['id']

  followers.each do |f|
    system %Q|redis-cli -n #{ENV['db']} LPUSH users:#{f}:timeline '#{id}'|
  end
"

# And finally, let's repeat everything for A as well.
#
export id="$( % INCR tweets:next_id | tr -d " " )"
export message="$(t);Message from A"
+ "A publishes message '$message' with ID '$id'"
% SET tweets:$id "$message"

% LPUSH global:timeline $id

% LPUSH users:A:timeline $id

% SMEMBERS users:A:followers | \
ruby -e "
  followers = STDIN.read.split(\"\n\")
  id        = ENV['id']

  followers.each do |f|
    system %Q|redis-cli -n #{ENV['db']} LPUSH users:#{f}:timeline '#{id}'|
  end
"

# Now would be the good time to display the timelines, again.

# Note, that we cannot simply pull messages from the timelines,
# since we are storing only IDs. We have to feed the fetched
# IDs to `MGET` again.

# A's timeline.
#
+ "A's timeline:"
% LRANGE users:A:timeline 0 9 | xargs echo | \
  sed 's/\([0-9]\)/tweets:&/g' | \
  xargs redis-cli -n $db MGET

# B's timeline.
#
+ "B's timeline:"
% LRANGE users:B:timeline 0 9 | xargs echo | \
  sed 's/\([0-9]\)/tweets:&/g' | \
  xargs redis-cli -n $db MGET

# C's timeline.
#
+ "C's timeline:"
% LRANGE users:C:timeline 0 9 | xargs echo | \
  sed 's/\([0-9]\)/tweets:&/g' | \
  xargs redis-cli -n $db MGET

# Global timeline.
+ "Global timeline:"
% LRANGE global:timeline 0 9 | xargs echo | \
  sed 's/\([0-9]\)/tweets:&/g' | \
  xargs redis-cli -n $db MGET

# How does our RAM usage look now? You can see it's actually _larger_ then
# in the previous case, most probably because we're using a larger pool
# of keys now. There's no free lunch in computer science.
#
+ "Memory usage:"
% info | \grep "used_memory_human"

# You may wonder, now, how we display the count of tweets for specific user,
# for instance. Actually, there's no way to do that.
#
# One solution would be to continue with the “query-based” schema, and
# just keep track of counts manually, in a counter such as `users:A:tweets:count`.
#
# Another solution would be to use [_sorted sets_](http://redis.io/commands#sorted_set)
# for tweets, with one set per user, using timestamp as the score.
#
# But that would shift the perspective to “data-based” schema, and we would have to walk
# through all the sets of all the followers when displaying user's timeline, using
# [`ZREVRANGEBYSCORE`](http://redis.io/commands/zrevrangebyscore) to get a limited set of IDs,
# and then perform a [`ZUNIONSTORE`](http://redis.io/commands/zunionstore)
# to store them in an easily accessible set, sorted by timestamp.
#
# And that would certainly be a _very_ expensive set of operations.
#
