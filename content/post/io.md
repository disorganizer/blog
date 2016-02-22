---
date: "2016-02-22T18:44:51+01:00"
title: "The semantics of io"
tags:   [ "Development", "Go", "brig"]
topics: [ "Development", "Go" ]
---

# Introduction

When using Go, you can't get far without using one of ``io.Reader`` or
``io.Writer``. If you tinkered a bit more with the language it's also almost
certain that you wrote a ``io.{Reader,Writer}`` yourself. In fact, ``brig``
currently implements 9 ``io.Writer`` and 7 ``io.Reader``, 4 of them with
additional support for ``io.Seeker``. Some of them closable, some not. Some of
them wrapping other writers, some not. It's a great concept, since they're very
re-usable and allow a program to operate on arbitrary streams of data, without
being bound on where the data actually comes from. It might come from 
the network, a file or ``stdin``.

While writing those, I noticed that there are implied rules which might not be
obvious from reading the [io documentation](https://golang.org/pkg/io/) and some
other things that just make sense in the majority of implementations. Therefore
this article tries to collect some of those *best practices* (if there is such a
thing).

We assume you already have a bit of experience in using the ``io`` package and
it's interfaces, please refer to the documentation when unclear.
[Here's](http://nathanleclaire.com/blog/2014/07/19/demystifying-golangs-io-dot-reader-and-io-dot-writer-interfaces/)
also a nice and gentle introduction you might want to read first. I try to
show some code where I feel it's necessary, but the end of the article links
to a variety of ``io.Reader`` and ``io.Writer`` you might want look into 
if you're a *gimme the code!*-kind of person.

Just as a reminder, those are the [interface definitions from
io](https://golang.org/pkg/io/) we're talking of:

{{< highlight go>}}
type Reader interface {
    Read(p []byte) (int, error)
}

type Writer interface {
    Write(p []byte) (int, error)
}

type Seeker interface {
    Seek(off int64, whence int) (int64, error)
}

type Closer  interface {
    Close() error
}
{{< /highlight >}}

# Lessons learned

You might notice that there is a bit more to these interfaces, than
you might expect from a quick glance. 

## How much to read/write and return?

There is a bit of confusion on what byte count to return when ``Read/Write`` is
called. For ``Read()`` it's relatively straightforward: Just return the offset
where you stopped writing to the provided buffer ``p``.

Some people however get confused when implementing ``Write()``: It's not the
number of bytes you've actually written to some underlying layer. It's the
number of bytes you used from ``p`` to write to the underlying stream.  The term
"used" means  that you might have cached the input, wrote it directly or
else wise processed or ignored it. And that number should be the whole length of ``p``.
Actually I find myself to return this frequently:

{{< highlight go>}}
func (x *X) Write(p []byte) (int, error) {
    // Do something with p: ignore, cache, duplicate or whatever.
    return len(p), nil
}
{{< /highlight >}}

Why is returning the correct byte count important? For a lot of reasons.  One
reason being ``io.Copy()``. If you write less than expected (and ``Copy()``
expects the whole buffer ``p``) then [it will
bitch](https://golang.org/src/io/io.go?s=12235:12295#L391) at you with a
``ErrShortWrite``.

As a general rule of thumb you should always strive to read and write every byte
you get your hands on, i.e. always fill the buffer on ``Read`` as much as
possible and ``Write`` everything you get you get passed (or at least say so).
This makes the life of the caller easier: If he provides a buffer with 4096
byte, then he can rely on you that you fill with all the data you have, or will
return ``io.EOF`` and the number of leftover bytes.

Honestly enough, this might make some implementations a bit harder.  But when in
question, do the work once on your side, otherwise the caller might give you a
surprise visit at night to ``Read()`` your blood.

# Copying and chunking data

This should be obvious, but in one case I forgot to do that and spend a few
hours debugging: you have to copy the data when using ``io.Writer``. You cannot
rely on the data to be valid after the end of ``Write()``. You can especially
not just store ``p`` for processing it later.

Sometimes you're gonna implement a reader that has to chunk it's underlying
data. Example: Suppose you're building a reader/writer with compression support.
The underlying data stream is usually chunked into blocks that need to be read
and written as a whole. However the caller usually doesn't care and wants as
little as one byte, 2.37 of your chunks or any arbitrary number.
This in turn means that you need to read the whole chunk into an internal
buffer and only pass the requested portion to the outside, or in case of the
writer, buffer the input until it's big enough for one block.
Go comes with a data type that's useful for this: ``bytes.Buffer``:

{{< highlight go>}}
// Example chunking Read() with a internal buffer called `backlog`.
func (r *Reader) Read(dest []byte) (int, error) {
	readBytes := 0

	for readBytes < len(dest) {
		if r.backlog.Len() == 0 {
			if _, err := r.readBlock(); err != nil {
				return readBytes, err
			}
		}

		n, _ := r.backlog.Read(dest[readBytes:])
		readBytes += n
	}

	return readBytes, nil
}
{{< /highlight >}}

More performance might be doable by implementing a true, [fixed size ring
buffer](https://github.com/glycerine/rbuf).  And sometimes even more convenience
can be achieved by using [bufio](https://golang.org/pkg/bufio/#NewReaderSize).

That said, ,,zero-copying" is not directly supported by the concept of ``Write()
/ Read()``, but you can use the  ``io.WriteTo`` and ``io.ReadFrom`` interfaces
for this.  ``io.Copy()`` will automatically use them if present.

The advantage here is that you can write and read the data in sizes you can
dictate - therefore buffering and chunking might not be needed in this case.
General rule of thumb is: Implement ``io.WriteTo``/``io.ReadFrom`` if you wrap
another reader/writer and if you do (lots of) copying. 

## Stacking writers and readers

A popular use of ``io.Reader/Writer`` is stacking them up, making one
transformation per layer. Example: ``brig`` uses this extensively by providing a
``Overlay``-writer over a ``Compression``-writer over a ``Encryption``-writer
that in turns feeds it's data to a ``DAGWriter`` provided by ``ipfs``. Some
``bytes.Buffer`` and ``bufio.Writer`` are sandwiched in there too.
The read side does almost the same thing, but mirrored.

The semantics are relatively clear here for ``Read() / Write() / Seek()`` but
``Close()`` is the odd kid in the class. Is ``Close()`` on the top-layer supposed to
close only itself or also everything below? This might not what you might
expect though, although it would be somewhat convenient, since you might not
always have access to all layers.

My general advice is: *Close everything separately.* 

Some people won't listen to advice though and might try something like this in
their implementation:

{{< highlight go>}}
func (r *Reader) Close() error {
    // Try to close the underlying reader if supported:
    closer, ok := r.rawR.(io.Closer)
    if ok {
        return closer.Close()
    }

    return nil
}
{{< /highlight >}}

This has some drawbacks. The most obvious one is that all your readers need to
implement that pattern. Even those from some libraries you don't control.
Also, even if you have control over all of them, it's enough to insert
a normal ``io.Reader`` (one without being a ``io.Closer``) into the chain in
order to break the close-chain. *Please don't do this.*

A better approach might be implementing and maintaining a separate ``CloseStack``:

{{< highlight go>}}
type CloseStack struct {
	stack []io.Closer
}

func (s *CloseStack) Push(cls io.Closer) {
	s.stack = append(s.stack, cls)
}

func (s *CloseStack) Close() error {
    var err error
    for i := 0; i < len(s.stack); i++ {
        cl := s.stack[len(s.stack)-i-1]
        if clErr := cl.Close(); err == nil && clErr != nil {
            // Remember first error:
            err = clErr
        }
    }

    return err
}

type dummyCloser struct { id int }

func (d dummyCloser) Close() error {
	fmt.Printf("Closing %d\n", d.id)
	return nil
}

func main() {
    chain := &CloseStack{}

    for i := 0; i < 4; i++ {
	    chain.Push(dummyCloser{i + 1})
    }

    // Prints numbers from 4 till 1. 
    chain.Close()
}
{{< /highlight >}}

When stacking readers/writers with different abilities (e.g. one
``io.ReadCloser`` over a ``io.ReadSeeker``), it's useful to keep those abilities
on the top layer if possible. This can be stupidly done by implementing a dummy
method of e.g.  ``Seek()`` that just calls the underlying ``Seek()``. Besides a
little performance penalty, it introduces a tiny bit of boilerplate code.  Go's
[interface embedding](http://www.hydrogen18.com/blog/golang-embedding.html)
makes this slightly easier:

{{< highlight go>}}
type A struct {
	io.ReadSeeker
}

func (a *A) Read(buf []byte) (int, error) {
	return 0, nil
}

type B struct {
	io.ReadSeeker
	io.Closer
}

func main() {
    src := bytes.NewReader([]byte{})
	low := &A{src}
	top := &B{low, ioutil.NopCloser(low)}

	// Calls bytes.Reader's Seek()
	top.Seek(0, os.SEEK_CUR)

	// Calls A's Read()
	top.Read(nil)
}
{{< /highlight >}}

Beware a bit of this method though, since it tends to make code slightly
confusing. It was [inspired](https://golang.org/src/io/ioutil/ioutil.go#L114) by
the Go's builtin ``ioutil.NopCloser`` (why the heck does this only exist for
``io.Reader``, not ``io.Writer``, Rob?).

## ``Seek()`` is hard

``Seek()`` is a handy interface, but when using it, it always feels like a bit
the 1970s could ring you any moment. You probably already figured out yourself,
what Im gonna tell you in the next few lines though.

Chances are, when you think about implementing ``Seek()``, that you need
to map from an underlying stream to a virtual, somehow processed stream.
``Seek()``'s job is then to position your stream at a certain offset - and
this is offset is relative to the virtual stream which the user sees (popular
beginner mistake: mixing offset types). Example: A Reader that "skips" a header
in front of the actual data. In this case ``Seek()`` just needs to add the
length of the header to get the underlying offset from the virtual offset.
An exercise for the reader is imagining a ``Seek()`` that maps from a (virtual)
uncompressed stream to an (underlying) compressed data stream. You'll notice
that ``Seek()`` gets a little harder in that case.

Another source of confusion is what ``Seek()`` does for a ``io.ReadWriter``.
Answer: It depends on the implementation. In most cases it's probably moving
the read offset. In some both. In a few cases it might even make sense to only
moving the write pointer. Consult your manual or a doctor.

In some usecases you may not be able to provide the full spec of ``Seek()``.
Imagine a stream of data you consume bytewise. You can't go back, since caching
all previous input might be no option (How to handle ``SEEK_CUR`` with negative
offset?). Or you might process a video stream, where you don't know when it ends
(how to handle ``SEEK_END``?). Is it okay to return something like
``ErrNotImplemented`` in this case? Probably, but my advice would be either 
to document that clearly or use a different function name than ``Seek()`` which
makes clear it's not a full ``Seek()`` implementation.

[There is also](https://golang.org/pkg/io/#ReaderAt) ``ReaderAt`` which is a bit
like a combined seek & read. You might know this idea from ``preadv(3)`` on (some)
Unix-derivatives. An important difference is that it allows the caller to 
call ``ReadAt()`` in parallel.
Once you have ``Seek()`` you can easily implement ``ReadAt()``, although you
might need to introduce an additional locking mechanism for the parallel reads.

By the way, if you want to go back from the end, you have to use ``SEEK_END`` with
a negative offset. No, not a positive offset. Popular mistake.

## The perks of ``io.EOF``

The story of EOF is a story full of misunderstandings.
In C it was a the ``#define`` on the number ``-1`` and it was returned by
``read(3)``.  This led some people to the misunderstanding that ``EOF`` 
was actually a character that sits at the end of the file, waiting for you to
be consumed. Kind of weird thinking when you can only read the numbers [0-255]
from a byte. Go has you covered here: ``io.EOF`` is just an error return value,
that you should check on. 

Some users falsely expect that no data was read when ``io.EOF`` is returned.
This is usually not true, there might be any valid number of bytes read before
reaching the end of the file (that's why you always check for ``io.EOF`` separately).
Note that many current Readers behave slightly different: They return ``nil`` on
the last block of data, but will return a byte count of 0 and ``io.EOF`` on the
next ``Read()`` call.  That's slightly less convenient, but okay too.

It gets a bit confusing when seeking to or over the end of a file.
What will ``Seek()`` return? The offset of the stream end? ``io.EOF`` as error?
Is seeking back allowed after hitting EOF?
There is no answer, since this depends on the implementation.
Example: For some writers it might make sense to seek over the end of the file
and write something there --- an overlay writer (see below) is a good
example for this. Other usecases might have different needs.

*Conclusion:* You should always think about ``io.EOF`` and whether you need
to check for it separately. If you come from other languages: reading an empty
file in Go will return ``0 / io.EOF`` on the *first* read.

# Some ``io`` exhibits:

To round this writing up, here are some of the more interesting
``io.Reader/Writers`` in ``brig``. Some might be useful in other applications:

## [SizeAccumulator](https://godoc.org/github.com/disorganizer/brig/util#SizeAccumulator)

A small ``io.Writer`` that simply counts the number of bytes written to it.
This is very useful in conjunction with ``io.TeeReader`` to count how many 
bytes of data were written to the underlying stream of data (Remember: ``Write()`` will tell
you the number of bytes taken as input). Example without error handling:

{{< highlight go>}}
func hello() {
	s := &SizeAccumulator{}
	teeR := io.TeeReader(bytes.NewReader([]byte("Hello, ")), s)
	io.Copy(os.Stdout, teeR)
	fmt.Printf("wrote %d bytes to stdout\n", s.Size())
	// Output: Hello, wrote 7 bytes to stdout
}
{{< /highlight >}}

## [TimeoutWriter / TimeoutReader](https://godoc.org/github.com/disorganizer/brig/util#TimeoutWriter)

A ``io.Reader`` and a ``io.Writer`` that wraps another reader or writer.
If the respective operation is not done until a certain deadline, it will
return. Any results arriving later will be dismissed.

## [SeekBuffer](https://godoc.org/github.com/disorganizer/brig/util#SeekBuffer)

A ``bytes.Buffer`` that supports ``Seek()``. The ``Seek()`` call
will move both the read and write offset. Go's ``bytes.Buffer`` does not
support ``Seek()`` because it would be unclear what ``Seek()`` would do on it
and because ``bytes.Buffer`` is not required to hold all data that has been
read already. ``SeekBuffer`` is stupid and can do this therefore.
(Never underestimate the power of stupid things.)

## [SyncReadWriter](https://godoc.org/github.com/disorganizer/brig/util#SyncReadWriter)

Simply a ``io.ReadWriter`` that protects each call of ``Read()`` and ``Write()``
with a ``sync.Mutex``. Very useful for simulating a "network" where each party
might want to write or read to the network at any time.

## [Tunnel](https://godoc.org/github.com/disorganizer/brig/util/tunnel)

A ``io.ReadWriter`` that encrypts data written to it and decrypts it on
``Read()``. It uses elliptic curve diffie-hellman to estimate an AES-key between
both sides.  While it provides good encryption, it does not provide any
authentication, nor does it provide suitable protection against man-in-the-middle
attacks. It's the caller's responsibility to make sure he's actually speaking to
the right party.

## [Layer](https://godoc.org/github.com/disorganizer/brig/store#Layer)

A ``io.ReadWriter`` that *overlays* a ``io.Reader``. Every write is cached in
memory and merged together with the actual data on the next read.
``Seek()`` is supported and may be used to seek over the end of the original
data stream in order to extend the stream. Additionally the stream may be
truncated.

## [compress.ReadSeeker / compress.Writer](https://godoc.org/github.com/disorganizer/brig/store/compress)

Compressed and decompresses input using a variety of different compression
algorithms (``none`` is also supported). The greatest benefit compared to other
implementations is the support for ``Seek()`` in the reader part.

## [encrypt.ReadSeeker / encrypt.Writer](https://godoc.org/github.com/disorganizer/brig/store/encrypt)

Encrypts and decrypts input using AES-GCM or ChaCha20. The data is chunked into
blocks (consisting of a nonce, a MAC and the data) and a header which contains
the settings used for encryption. It supports ``Seek()`` in the reader part.

# Conclusion

Phew, that was a lot of text. I know some of you will just skip here for a
TL;DR. Those lazy bastards shall have this checklist:

- Make your ``io.Reader`` and ``io.Writer`` is (easily) stackable.
- Implement ``WriteTo/ReadFrom`` for (possibly) less copying.

As final tip: You might want to use these packages when testing your ``io.*``
stuff (or get inspiration from):

- https://golang.org/pkg/testing/iotest.
- https://golang.org/pkg/io/ioutil/ 
- https://godoc.org/github.com/disorganizer/brig/util/testutil

*Remember:* You don't need to write files on disk. Use in-memory buffers
(``&bytes.Buffer{}``!) in your tests for performance and reproducibility.
Also try to keep your testdata small and debuggable. Testing gigabytes instead of 
a few kilobytes just gives you more repetition, but no added safety.

<!--
TODO: Points to fix:

- Embedded interfaces (easier stacking)
- No Close() on Close()
- bufio?
- WriteTo/ReadFrom.
-->
