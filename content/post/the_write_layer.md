---
date:        "2016-02-01T00:03:36+01:00"
title:       "The write layer"
tags:        [ "Development", "Go", "brig"]
topics:      [ "Development", "Go" ]
---

A bit more than a week since the last post, I'm getting worse again. Screw it.
Besides a lot of personal life stuff a major "problem" was solved: Writing to
files. Doesn't sound like an impressive problem, I know.

But how is ``brig`` able to modify existing files by writing somewhere in them,
extending them or truncating them to some size? With the cli interface it's not
much of a problem, a simple ``brig add`` updates the file:

{{< highlight bash>}}
$ echo -n 'What now?' > file.txt 
$ brig add file.txt && brig cat file.txt
What now?
$ echo ' PARTY!' >> file.txt
$ brig add file.txt && brig cat file.txt
What now? PARTY!
{{< /highlight >}}

The file is simply hashed and encrypted as a whole and is added to ``ipfs``. 
A new entry in the version history will be created and the next ``cat``
gives the newer version.  But what about editing large files in the fuse layer?
Do we need to add the whole file on every edit over and over again?
That would be hella inefficient.

The solution is kinda obvious, but the devil is in the details.
Every file handle that is opened from the outside via the fuse layer 
internally opens a seekable read-only stream to the actual data in ipfs.
The decryption and retrieving from ``ipfs`` is transparently managed, so
to the caller side it simply looks like a stream of the originally added file.
When a user writes data to the file, the data will be cached in memory a layer
over the original file. Once the file handle is closed, the written data will
be layered over the original read-only stream and added to ``ipfs``.
Since images are easier to grasp than text, here's an example overlay:

<img src="/img/write_overlay.svg" alt="Overlay" width="800px"/>

That's the current solution and it's already a lot better than just re-adding
the file over and over. However, on every close the whole file is added anyways,
which makes editing large files inefficient. This might be helped in the future
by rolling hashes and direct writing to the blocks in ``ipfs``.
Another drawback is that every write is cached in memory, which can obviously
suck up your RAM in minutes. A viable solution would be to implement a "scratchpad"
on disk where encrypted chunks of data will be stored until the handle closes.

As mentioned, the actual details are hairy. Implementing seekable decryption,
overlaying ``io.Writers`` and similar stuff is a really great source for one-off
errors and other exotic bugs that are hard to find. To be more exact: there are
known bugs: Truncating to zero and then appending to the end (like ``echo xyz >>
file.txt``) produces a file with content zeroed everything before the appended
data.

Speaking of bugs, there are plenty of todos until the next blog entry:

- **Make creating files in fuse possible:** This does not work currently for
  unknown reasons.
- **Actually add old files to commit history:** Old hashes are silently discarded
  and not unpinned. This will lead to lot of undeleteable garbage files.
- The encryption format needs a field to **remember compression and a MAC** to
  protect against forgery of the header data.
- **General code cleanup:** This involves running linters, removing debug messages
  and cleaning up old hacks.
- There are no **tests** for the fuse layer, but some bash scripts. These need
  to be converted to go.

**Long term goals:**

Before diving much deeper in the frontend part of ``brig`` (``fuse``, cli, etc.)
it's probably a good idea to get on the ``xmpp/bolt`` side and see if we can
persuade ``brig`` to sync files over the net. Steep goals, but you can already
get the raw from ``ipfs`` from another computer!

The next blog post will give therefore an overview of the current architecture
and how the source is layout. Writing about that always help figuring out what
parts I screwed up. 😃
