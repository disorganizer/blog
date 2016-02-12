---
date:   "2016-02-11T19:26:59+01:00"
title: "Source Layout"
tags:   [ "Development", "Go", "brig"]
topics: [ "Development", "Go" ]
---

Hi there. Today's blog post is a unsorted notepad of how ``brig``'s source is
currently layout and what the big picture behind is supposed to look like.

Now that ``brig`` is already a mid-sized codebase (when did we get to 7k lines
of code?), it might be worthwhile to show what packages we have and how they
interact. Here's the ``tree(1)`` output of the git repository at the time of
writing. I allowed myself to reduce it to the most relevant files, also skipping
tests and rather unimportant subdirectories:

{{< highlight bash>}}
$ tree | grep -v 'unimportant' .
├── doc.go            # Top-level documentation.
├── Makefile          # Makefile with often used tools.
├── brig              # Source of the `brig` binary...
│   └── brig.go       # ...which just calls into cmdline.*
├── cmdline           # Actual implementation of the cli.
│   ├── handlers.go   # Handler function for each subcommand.
│   └── parser.go     # Subcommand definitions are in here.
├── daemon            # Implement the daemon/client process and io.
│   ├── client.go     # client side daemon io.
│   ├── server.go     # Server side daemon io.
│   ├── handlers.go   # Server handler for each daemon command.
│   └── operations.go # Client handler for each daemon command.
├── fuse              # Implementation of `brigfs`
│   ├── directory.go  # Logic for directory nodes.
│   ├── entry.go      # Logic for regular files.
│   ├── handle.go     # Logic for open()'d nodes.
│   ├── fs.go         # Filesystem entry; defines the root node.
│   └── mount.go      # Mount utility.
├── im                # XMPP communication layer.
│   ├── client.go     # A generic otr-enabled xmpp client.
│   ├── finger.go     # Fingerprint and key storage of each user.
├── repo              # Code for filesystem repository handling.
│   ├── config/       # Config value retrieval and default config.
│   ├── global/       # Global config handling (~/.brig/)
│   ├── id.go         # File locking (TODO: move to open.go?)
│   ├── init.go       # Code to initialize a new empty repo.
│   ├── locate.go     # Tool to find the repo root path.
│   ├── open.go       # Code to lock/unlock a repository.
│   ├── pwd.go        # Password handling.
│   └── repo.go       # The repository structure itself.
├── store             # The actual core: file structs and ipfs handling.
│   ├── compress/     # Seekable compression IO Layer using snappy.
│   ├── encrypt/      # Seekable encryption IO Layer.
│   ├── format-util/  # Compress&Encryption util for brigs file format.
│   ├── commit.go     # Versioning handling.
│   ├── file.go       # Implement the file struct and the implicit trie.
│   ├── hash.go       # wrapper around jbenet/multihash's implementation.
│   ├── index.go      # Implementation of add/rm/cat/checkout...
│   ├── overlay.go    # A write overlay of a immutable io.Reader for fuse.
│   ├── stream.go     # Stack encryption and compression.
├── util              # General utilities.
│   ├── colors/       # ASCII-terminal color code colorizing.
│   ├── filelock/     # Filelocking (used for the global repo)
│   ├── ipfsutil/     # Utils around the ipfs libraries.
│   ├── log/          # A colorful log-formatter for `logrus`
│   ├── security/     # security related utilites (scrypt simplified)
│   ├── testutil/     # Utils used in various tests.
│   ├── trie/         # A re-usable radix-trie for absolute file paths.
│   ├── tunnel/       # An io.ReadWriter that pipes through ECDH and AES.
│   └── std.go        # Standard utils that should be in the standard lib.
└── version.go        # Semantic versioning of the brig util/library.
{{< /highlight >}}

You might already have an idea how ``brig`` is working by now. There's a
command-line utility that speaks to a daemon that was somehow started, which
uses a store to ``add`` and ``cat`` files. The daemon is also capable of mounting 
a fuse filesystem, but before that it needs a repository to run in.
That's the very rough picture, but to recap this we have this diagram to show 
how the most important packages play together:

<img src="/img/package_map.svg" alt="Package map" width="800px"/>

From a slightly wider view, the communication between two repositories
is supposed too look like this:

<img src="/img/brig_arch.svg" alt="Security architecture" width="800px"/>

I don't have any details to show here, simply because there is nothing to show
yet: The inter-repository communication simply does not exist yet. 😉

What's working now is mostly the fuse part (well, mostly, it already works like
a buggy and slow ``encfs``) and the versioning. Naturally the next goal is
to exchange some information between two ``brig`` nodes.
The cool thing about the current architecture is naturally that we don't need to
do any file exchange or storage ourselves, since ``ipfs`` handles that for us.
As long as we manage to get the hashes and keys across XMPP, we successfully 
share files - ``ipfs`` will make sure to load it from the swarm.

It's late here, so that's it for today.
