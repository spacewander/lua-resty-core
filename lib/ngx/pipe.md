Name
====

`ngx.pipe` - spawn and communicate with OS processes via stdin/stdout/stderr nonblockingly in OpenResty.

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Synopsis](#synopsis)
* [Description](#description)
* [Methods](#methods)
    * [spawn](#spawn)
    * [set_timeouts](#set_timeouts)
    * [wait](#wait)
    * [pid](#pid)
    * [kill](#kill)
    * [shutdown](#shutdown)
    * [write](#write)
    * [stderr_read_all](#stderr_read_all)
    * [stdout_read_all](#stdout_read_all)
    * [stderr_read_line](#stderr_read_line)
    * [stdout_read_line](#stdout_read_line)
    * [stderr_read_bytes](#stderr_read_bytes)
    * [stdout_read_bytes](#stdout_read_bytes)
    * [stderr_read_any](#stderr_read_any)
    * [stdout_read_any](#stdout_read_any)
* [Community](#community)
    * [English Mailing List](#english-mailing-list)
    * [Chinese Mailing List](#chinese-mailing-list)
* [Bugs and Patches](#bugs-and-patches)
* [Copyright and License](#copyright-and-license)
* [See Also](#see-also)

Status
======

This Lua module is currently considered experimental.

Synopsis
========

```nginx
location = /t {
    content_by_lua_block {
        local ngx_pipe = require "ngx.pipe"
        local select = select

        local function count_char(...)
            local proc = ngx_pipe.spawn({'wc', '-c'})
            local n = select('#', ...)
            for i = 1, n do
                local arg = select(i, ...)
                local bytes, err = proc:write(arg)
                if not bytes then
                    ngx.say(err)
                    return
                end
            end

            local ok, err = proc:shutdown('stdin')
            if not ok then
                ngx.say(err)
                return
            end

            local data, err = proc:stdout_read_line()
            if not data then
                ngx.say(err)
                return
            end

            ngx.say(data)
        end

        count_char(("1234"):rep(2048))
    }
}
```

This example counts characters (bytes) directly fed by OpenResty via the UNIX
command `wc`.

You could not do this with either `io.popen` or `os.execute` because `wc` will
not output the result until its stdin is closed.

[Back to TOC](#table-of-contents)

Description
===========

This module does not support non-POSIX operating systems like Windows yet.

And if you are not using the Nginx core shipped with OpenResty, then you need
to apply the `socket_cloexec` patch to the standard Nginx core.

The technical details behind this module are not complex.
We just `fork` and `execvp` with the specified command, and communicate with
spawned processes with POSIX's `pipe` API, which contributes to the name of this module.

A signal handler for `SIGCHLD` is registered so that we can get notification once the spawned processes exited.

We combine all these with Nginx's event mechanism and OpenResty's Lua coroutine scheduler, to make the communication APIs nonblockingly.

The communication APIs do not work in phases which do not support yielding, like `init_worker_by_lua*` and
`log_by_lua*`. Because there is no way to yield the current light thread to avoid
blocking the OS thread when communicating with processes in those phases.

[Back to TOC](#table-of-contents)

Methods
=======

spawn
-----
**syntax:** *proc, err = pipe_module.spawn(args, opts?)*

**context:** *any phase except init_by_lua&#42;*

Creates and returns a new sub-process instance with that we can communicate later.

For example,

```lua
local ngx_pipe = require "ngx.pipe"
local proc, err = ngx_pipe.spawn({"sh", "-c", "sleep 0.1 && exit 2"})
if not proc then
    ngx.say(err)
    return
end
```

The sub-process will be killed by `SIGKILL` if it is still alive when
the instance is collected by garbage collector.

Note that the `args` should be a single level array-like Lua table with string
pieces or just a single string.

Some more examples are as follows:

```lua
local proc, err = ngx_pipe.spawn{ "ls", "-l" }

local proc, err = ngx_pipe.spawn{ "perl", "-e", "print 'hello, wolrd'" }
```

If a string is specified as `args`, it will be executed by the operating system shell,
just like `os.execute`.

The example above could be rewritten as,

```lua
local ngx_pipe = require "ngx.pipe"
local proc, err = ngx_pipe.spawn("sleep 0.1 && exit 2")
if not proc then
    ngx.say(err)
    return
end
```

In the shell mode, you should be very careful about shell injection
attacks when you interpolate variable values into the shell command
string, especially those from untrusted sources.
Please make sure you escape those variable values while assembling the shell
command string. For this reason, it is highly recommended to use the multi-argument
table form to specify each command-line argument explicitly instead of using
a single shell command string.

Since Nginx does not pass along the `PATH` system environment by default,
if you want the outside `PATH` environment setting to take effect in the
searching of the sub-processes, you need to configure the `env PATH` directive
in your `nginx.conf`, as in

```nginx
env PATH;
...
content_by_lua_block {
    local ngx_pipe = require "ngx.pipe"

    local proc = ngx_pipe.spawn({'ls'})
}
```

The optional table argument `opts` can be used to control the behavior of
spawned processes. For instance,

```lua
local opts = {merge_stderr = true, buffer_size = 256}
local proc, err = ngx_pipe.spawn({"sh", "-c", ">&2 echo data"}, opts)
if not proc then
    ngx.say(err)
    return
end
```

The following options are supported:

* `merge_stderr`: when set to `true`, the output to stderr will be redirected to
stdout in the spawned process. It works like shell's `>&1`.
* `buffer_size`: specifies the buffer size used by reading operations, in bytes.
The default buffer size is `4096`.

[Back to TOC](#table-of-contents)

set_timeouts
------------
**syntax:** *proc:set_timeouts(write_timeout?, stdout_read_timeout?, stderr_read_timeout?, wait_timeout?)*

Sets the write timeout threshold, stdout read timeout threshold, stderr read timeout threshold, and wait timeout threshold respectively,
in milliseconds, for corresponding operations.

If the the specified timeout argument is `nil`, the timeout of corresponding operation won't be touched. For example:

```lua
local proc, err = ngx_pipe.spawn({"sleep", "10s"})
-- only change the wait_timeout to 0.1 second.
proc:set_timeouts(nil, nil, nil, 100)
-- only change the send_timeout to 0.1 second.
proc:set_timeouts(100)
```

[Back to TOC](#table-of-contents)

wait
----
**syntax:** *ok, reason, status = proc:wait()*

**context:** *phases that support yielding*

Waits until the current sub-process exits.

You could control how long to wait with [set_timeouts](#set_timeouts).
The default timeout is 10 seconds.

If process exited with zero, the `ok` will be `true`.

If process exited abnormally, the `ok` will be `false`.

The `reason` will be:

* `exit`: process exited by calling `exit(3)` or `_exit(2)`, or by returning from `main()`.
In this case, `status` will be the exit code.
* `signal`: process terminated by signal. In this case, `status` will be the signal number.

Note that only one light thread could wait on a process. If another light thread tries
to wait on a process, the return value will be `nil` plus `pipe busy waiting`.

If a thread try to wait an exited process, it will get `nil` and the error
string `"exited"`.

[Back to TOC](#table-of-contents)

pid
---
**syntax:** *pid = proc:pid()*

Returns the pid number of the current sub-process.

[Back to TOC](#table-of-contents)

kill
----
**syntax:** *ok, err = proc:kill(signum)*

Sends signal to current sub-process.

Note that the `signum` should be the number of signal. If the specified `signum`
is not a number, you will get a `bad signal value: ...` error.

You should use [lua-resty-signal's signum function](https://github.com/orinc/lua-resty-signal#signum)
to convert signal names to signal numbers for the sake of portable.

In case of success, it returns `true`. Otherwise it returns `nil` and a string
describing the error.

Killing an exited sub-process will return `nil` and the error string `"exited"`.

Sending an invalid signal to the process will return `nil` and the error string
`"invalid signal"`.

[Back to TOC](#table-of-contents)

shutdown
--------
**syntax:** *ok, err = proc:shutdown(direction)*

Closes the specified direction of the current sub-process.

The `direction` should be one of these three values: `stdin`, `stdout` and `stderr`.

In case of success, it returns `true`. Otherwise it returns `nil` and a string
describing the error.

Shutting down a direction when there is a light thread waiting on it (like
reading or writing) will yield the `nil` return value and the error string
`"pipe busy writing"` (for stdin) or `"pipe busy reading"` (for the others).

Shutting down directions of an exited process will return `nil` and the error
string `"closed"`.

It is fine to shut down the same direction of the same stream for multiple times
without side effects.

[Back to TOC](#table-of-contents)

write
-----
**syntax:** *nbytes, err = proc:write(data)*

**context:** *phases that support yielding*

Writes data to the current sub-process's stdin stream.

The `data` could be a string or a single level array-like Lua table with strings.

This method is a synchronous and nonblocking operation that will not return
until *all* the data has been flushed into the sub-process's stdin buffer or
an error occurs.

In case of success, it returns the total number of bytes that have been sent.
Otherwise, it returns `nil` and a string describing the error.

The timeout threshold of this `write` operation can be controlled by the
[set_timeouts](#set_timeouts) method. The default timeout threshold is 10 seconds.

When the timeout occurs, the data may be partially written into the sub-process's
stdin buffer and read by the sub-process.

Only one light thread is allowed to write to the sub-process at a time. If another
light thread tries to write to it, it will immediately return `nil` and the
error string `"pipe busy writing"`.

Writing to an exited sub-process will return `nil` and the error string
`"closed"`.

[Back to TOC](#table-of-contents)

stderr_read_all
---------------
**syntax:** *data, err, partial = proc:stderr_read_all()*

**context:** *phases that support yielding*

Reads all data from the current sub-process's stderr stream until the stderr is
closed.

When `merge_stderr` is specified in [spawn](#spawn), `stderr_read_all` is identical
to [stdout_read_all](#stdout_read_all).

This method is a synchronous and nonblocking operation just like the [write](#write) method.

The timeout threshold of this reading operation can be controlled by
[set_timeouts](#set_timeouts). The default timeout is 10 seconds.

In case of success, it returns the data received; otherwise it returns three values: `nil`,
a string describing the error, and the partial data received so far.

Only one light thread is allowed to read from a process's stderr or stdout stream at a time.
If another thread tries to read from the same stream, it will return `nil` and the error string
`"pipe busy reading"`.

Each stream for stdout and stderr are separate, so you can have at most two
light threads reading from a sub-process, one from the stdout stream and the other
from stderr.

Please note that when the `merge_stderr` option is specified in the
[spawn](#spawn) method call,
only one light thread can read from the sub-process, as stderr is now identical to stdout
in this case.

You can read from a data stream of the sub-process in a light thread when there is
another light thread is pending writing to the same stream of the same
sub-process. One light thread can, however, read from a stream while
another light thread is *writing* to the same stream since every stream supports
full-duplexing.

Reading from an exited process's streams will return `nil` plus `closed`.

[Back to TOC](#table-of-contents)

stdout_read_all
---------------
**syntax:** *data, err, partial = proc:stdout_read_all()*

**context:** *phases that support yielding*

Similar to the [stderr_read_all](#stderr_read_all) method but reading from
the stdout stream of the sub-process.

[Back to TOC](#table-of-contents)

stderr_read_line
----------------
**syntax:** *data, err, partial = proc:stderr_read_line()*

**context:** *phases that support yielding*

Reads data like [stderr_read_all](#stderr_read_all) but only reads a single line of data.

When the data stream is truncated without a new-line character, it returns 3 values:
`nil`, the error string `"closed"`, and the partial data received so far.

The line should be terminated by a `Line Feed` (LF) character (ASCII 10),
optionally preceded by a `Carriage Return` (CR) character (ASCII 13).
The CR and LF characters are not included in the returned line data.

[Back to TOC](#table-of-contents)

stdout_read_line
----------------
**syntax:** *data, err, partial = proc:stdout_read_line()*

**context:** *phases that support yielding*

Similar to [stderr_read_line](#stderr_read_line) but working on the sub-process's
stdout stream.

[Back to TOC](#table-of-contents)

stderr_read_bytes
-----------------
**syntax:** *data, err, partial = proc:stderr_read_bytes(len)*

**context:** *phases that support yielding*

Reads data from stderr like [stderr_read_all](#stderr_read_all) but only reads the
specified number of bytes of data.

If the data stream is truncated with less bytes of data available, it returns
3 values: `nil`, the error string `"closed"`, and the partial data string received so far.

[Back to TOC](#table-of-contents)

stdout_read_bytes
-----------------

**syntax:** *data, err, partial = proc:stdout_read_bytes(len)*

**context:** *phases that support yielding*

Similar to [stderr_read_bytes](#stderr_read_bytes) but working on the sub-process's
stdout stream.

[Back to TOC](#table-of-contents)

stderr_read_any
---------------

**syntax:** *data, err = proc:stderr_read_any(max)*

**context:** *phases that support yielding*

Reads data like [stderr_read_all](#stderr_read_all) but returns immediately
when any amount of data is received, at most `max` bytes.

If the received data is more than `max` bytes, this method will return with
exactly the `max` size of data. The remaining data in the underlying receive buffer
can be fetched in the next reading operation.

[Back to TOC](#table-of-contents)

stdout_read_any
---------------

**syntax:** *data, err = proc:stdout_read_any(max)*

**context:** *phases that support yielding*

Similar to [stderr_read_any](#stderr_read_any) but working on the sub-process's
stdout stream.

[Back to TOC](#table-of-contents)

Community
=========

[Back to TOC](#table-of-contents)

English Mailing List
--------------------

The [openresty-en](https://groups.google.com/group/openresty-en) mailing list
is for English speakers.

[Back to TOC](#table-of-contents)

Chinese Mailing List
--------------------

The [openresty](https://groups.google.com/group/openresty) mailing list is for
Chinese speakers.

[Back to TOC](#table-of-contents)

Bugs and Patches
================

Please report bugs or submit patches by

1. creating a ticket on the [GitHub Issue Tracker](https://github.com/openresty/lua-resty-core/issues),
1. or posting to the [OpenResty community](#community).

[Back to TOC](#table-of-contents)

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2018, by OpenResty Inc.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

See Also
========
* library [lua-resty-core](https://github.com/openresty/lua-resty-core)
* the ngx_lua module: https://github.com/openresty/lua-nginx-module
* OpenResty: http://openresty.org

[Back to TOC](#table-of-contents)
