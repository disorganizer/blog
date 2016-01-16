---
date: "2016-01-16T18:44:51+01:00"
title: "Making it persistent"
tags:   [ "Development", "Go", "brig"]
topics: [ "Development", "Go" ]
---

A bit more than one day after the last post. Not too bad.
Basically, three smaller things happened since the last time.

First, we now store files serialized as protobufs in the index persistently.
The index is just a BoltDB database file (which I can recommend, it's nice).

Secondly, the AES-key for each file is generated from the ``sha512`` hash of the
first 8KB of a file. We don't hash the full file for performance reasons, but
there is nothing stopping us from hashing the whole file, so we fully apply to
[Wikipedia's definiton of convergent
encryption](https://en.wikipedia.org/wiki/Convergent_encryption). The hash is
then processed by ``scrypt`` with the filesize as salt. Currently, the key is
also stored in the index.

Finally, the commandline interface was cleared up a bit.
We now use the ``withXY`` pattern which are usually popular in tests.
Since we use ``climax`` as commandline library, we need to pass a callback
handle for each subcommand we have (``add``, ``cat``, etc.).
Almost all of them have in common that they need to talk to the daemon 
and need a certain number of arguments to work. 

It would be nice to write something like this:

```go
	Handle: withArgCheck(needAtLeast(2), withDaemon(handleAdd)),
```

... which is nicely possible by writing a function that returns a closure:

```go
type CheckFunc func(ctx climax.Context) int

func withArgCheck(checker CheckFunc, handler climax.CmdHandler) climax.CmdHandler {
	return func(ctx climax.Context) int {
		if checker(ctx) != Success {
			return BadArgs
		}

		return handler(ctx)
	}
}

func needAtLeast(min int) CheckFunc {
	return func(ctx climax.Context) int {
		if len(ctx.Args) < min {
			log.Warningf("Need at least %d arguments.", min)
			return BadArgs
		}

		return Success
	}
}
```

Oh, as an extra: We're on GitHub now: 

* https://github.com/disorganizer (source)
* https://disorganizer.github.io/blog/index.html (blog)

That's it for now. The next days should bring some of the following:

- Make the index remember directories.
- Recursively add directories.
- A humble start on the FUSE layer.
