---
date: "2016-01-16T18:44:51+01:00"
title: "Fusing it together"
tags:   [ "Development", "Go", "brig"]
topics: [ "Development", "Go" ]
---

Another productive day, another update late in the night.

A basic FUSE layer is integrated and is already able to display
the contents of a ``util.trie.Trie`` as files and directories.
Reading and writing is not yet implemented, since that's the
part where fuse and brig actually need to... fuse.

Here's a small session inside the fuse layer:

{{< highlight bash>}}
λ ~ → brig mount /tmp/mount && cd /tmp/mount
λ /tmp/mount → touch hello  # Creating file work. 
λ /tmp/mount → cat hello    # Although they contain weird stuff.
NaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNa
NaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNa
NaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNa
NaNaNaNaNaNaNaNaNaNaNaNaNa%
λ /tmp/mount → stat hello   # Every file is 200 bytes in size currently.
File: „hello“
(...) Size: 200  (...)
λ /tmp/mount → ls           # Also enumerating the directory.
hello  test
λ /tmp/mount → mkdir new    # Adding directories even somehow works.
hello  new  test
$ brig mount -u /tmp/mount
{{< /highlight >}}

It already feels like a pretty normal directory. Most of it's code is inspired
from bolt-mount, which is described in this
[video](http://eagain.net/talks/bolt-mount/).
As you may have noticed ``mount`` and ``mount -u`` are daemon commands already.
The only thing left to do now, is to read the actual stream and display
``store.Trie``.

There was another small change which might have larger impact. Instead of generating
the AES-key from the hash of the first 8KB of a file, the key is randomly generated now
and stored in the index. This is probably saner/faster/more secure. But the actual
reason for this is: When modifying the file, the key might need to change, which 
required re-encrypting the file, which in turn is very expensive. 
For the prototype we probably need to re-add every file to ``ipfs`` anyways, but now
we have more space for optimisations later on.

Another nicety is that ``brig add`` now works on directories. It simply adds all
files in it and ``brig mkdir`` all directories. Also missing ``/`` are prefixed
automatically and the repo path can be guessed from the source path.

As usual, a list of targets for the next entry follows (this evolves into my TODO-list...):

- Add ``brig rm`` which does obvious things.
- Make sure trie modifications in the index are locked.
- Read relevant metadata from the source file (size, mtime, etc.)
- Fix my sleep schedule.
