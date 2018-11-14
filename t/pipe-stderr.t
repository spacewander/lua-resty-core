# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;
use Cwd qw(abs_path realpath cwd);
use File::Basename;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 4);

my $pwd = cwd();

add_block_preprocessor(sub {
    my $block = shift;

    my $http_config = $block->http_config || '';
    my $init_by_lua_block = $block->init_by_lua_block || 'require "resty.core"';

    $http_config .= <<_EOC_;

    lua_package_path "$pwd/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";
    init_by_lua_block {
        $init_by_lua_block
    }
_EOC_

    $block->set_value("http_config", $http_config);

    if (!defined $block->error_log) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

$ENV{TEST_NGINX_CERT_DIR} ||= dirname(realpath(abs_path(__FILE__)));
my $port = server_port;
if ($port < 65535) {
    $port++;
} else {
    $port--;
}
$ENV{TEST_NGINX_SERVER_SSL_PORT} = $port;

env_to_nginx("PATH");
no_long_string();
run_tests();

__DATA__

=== TEST 1: read stderr, pattern is read line
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello world"})

            local data, err = proc:stderr_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
hello world



=== TEST 2: read stderr, pattern is read bytes
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello world"})

            local data, err = proc:stderr_read_bytes(5)
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end

            data, err = proc:stderr_read_bytes(6)
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
hello
 world



=== TEST 3: read stderr, bytes length is zero
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello world"})

            local data, err = proc:stderr_read_bytes(0)
            if not data then
                ngx.say(err)
            else
                ngx.say("data:", data)
            end
        }
    }
--- response_body
data:



=== TEST 4: read stderr, bytes length is less than zero
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello world"})

            local ok, err = pcall(proc.stderr_read_bytes, proc, -1)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- response_body
bad len argument



=== TEST 5: read stderr, bytes length is more than data
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello world"})

            local data, err = proc:stderr_read_bytes(20)
            if not data then
                ngx.say(err)
            else
                ngx.say("data:", data)
            end
        }
    }
--- response_body
closed



=== TEST 6: read stderr, pattern is read all
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo -n hello && sleep 0.05 && >&2 echo -n world"})

            local data, err = proc:stderr_read_all()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
helloworld



=== TEST 7: read stderr, pattern is read any
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo -n hello && sleep 0.05 && >&2 echo -n world"})

            local data, err = proc:stderr_read_any(1024)
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end

            data, err = proc:stderr_read_any(1024)
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
hello
world



=== TEST 8: read stderr, pattern is read any, with limited, max <= 0
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo -n hello && sleep 0.05 && >&2 echo -n world"})

            local ok, err = pcall(proc.stderr_read_any, proc, 0)
            if not ok then
                ngx.say(err)
            end
        }
    }
--- response_body
bad max argument



=== TEST 9: read stderr, without yield
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello world"})

            ngx.sleep(0.05)
            local data, err = proc:stderr_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
hello world



=== TEST 10: read stderr, without yield, pattern is read bytes
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello world"})

            ngx.sleep(0.05)
            local data, err = proc:stderr_read_bytes(7)
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
hello w



=== TEST 11: read stderr, without yield, pattern is read all
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello && >&2 echo world"})

            ngx.sleep(0.05)
            local data, err = proc:stderr_read_all()
            if not data then
                ngx.say(err)
            else
                ngx.print(data)
            end
        }
    }
--- response_body
hello
world



=== TEST 12: read stderr, without yield, pattern is read any
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo -n hello && sleep 0.01 && >&2 echo -n world"})

            ngx.sleep(0.05)
            local data, err = proc:stderr_read_any(1024)
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
helloworld



=== TEST 13: read stderr, mix read pattern and stdout/stderr
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local script = [[
                echo -n hello
                >&2 echo world
                >&2 echo -n more
                sleep 0.1
                >&2 echo -n da
                sleep 0.1
                >&2 echo ta
                echo more
                >&2 echo -n data
            ]]
            local proc = ngx_pipe.spawn({"sh", "-c", script})

            local function check_call(proc, func, ...)
                local data, err = func(proc, ...)
                if not data then
                    ngx.say(err)
                    ngx.exit(ngx.OK)
                end
                ngx.say(data)
            end

            ngx.sleep(0.05)
            ngx.say("reading any")
            check_call(proc, proc.stderr_read_any, 1024)

            ngx.say("reading 3")
            check_call(proc, proc.stderr_read_bytes, 3)

            ngx.say("reading line")
            check_call(proc, proc.stderr_read_line)

            ngx.say("reading all")
            check_call(proc, proc.stderr_read_all)
        }
    }
--- response_body
reading any
world
more
reading 3
dat
reading line
a
reading all
data



=== TEST 14: read stderr, timeout
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sleep", "10s"})
            proc:set_timeouts(nil, 4000, 100)

            local ok, err = proc:stderr_read_line()
            if not ok then
                ngx.say(err)
            else
                ngx.say("ok")
            end
        }
    }
--- response_body
timeout
--- no_error_log
[error]
--- error_log
lua pipe add timer for reading: 100(ms)



=== TEST 15: read stderr, aborted by uthread kill
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", "sleep 0.1 && >&2 echo hello"})

            local function read()
                proc:stderr_read_line()
                ngx.log(ngx.ERR, "can't reach here")
            end

            local th = ngx.thread.spawn(read)
            ngx.thread.kill(th)

            local data, err = proc:stderr_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
hello
--- no_error_log
[error]
--- error_log
lua pipe read process:
lua pipe proc read stderr cleanup



=== TEST 16: more than one coroutines read stderr of a process
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local proc = ngx_pipe.spawn({"sh", "-c", "sleep 0.1 && >&2 echo hello && >&2 echo world"})

            local function read()
                local data, err = proc:stderr_read_line()
                if not data then
                    ngx.say(err)
                else
                    ngx.say(data)
                end
            end

            local th1 = ngx.thread.spawn(read)
            local th2 = ngx.thread.spawn(read)
            ngx.thread.wait(th1)
            ngx.thread.wait(th2)
            ngx.thread.spawn(read)
        }
    }
--- response_body
pipe busy reading
hello
world



=== TEST 17: read stderr while read stdout in other request
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            package.loaded.proc = ngx_pipe.spawn({"sh", "-c", [[
                echo hello
                >&2 echo world
                sleep 0.1
                >&2 echo more
                echo -n da
                sleep 0.1
                echo ta
                echo -n more
                >&2 echo -n data
            ]]})
            local res1, res2 = ngx.location.capture_multi{{"/req1"}, {"/req2"}}
            ngx.say("stderr:")
            ngx.print(res1.body)
            ngx.say("stdout:")
            ngx.print(res2.body)
        }
    }

    location = /req1 {
        content_by_lua_block {
            while true do
                local data, err = package.loaded.proc:stderr_read_any(1024)
                if data then
                    ngx.print(data)
                else
                    if err ~= 'closed' then
                        ngx.say(err)
                    end
                    break
                end
            end
            ngx.say('')
        }
    }

    location = /req2 {
        content_by_lua_block {
            while true do
                local data, err = package.loaded.proc:stdout_read_any(1024)
                if data then
                    ngx.print(data)
                else
                    if err ~= 'closed' then
                        ngx.say(err)
                    end
                    break
                end
            end
            ngx.say('')
        }
    }
--- response_body
stderr:
world
more
data
stdout:
hello
data
more



=== TEST 18: read stderr while read stdout in other request, individual error
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            package.loaded.proc = ngx_pipe.spawn({"sleep", 0.5})
            package.loaded.proc:set_timeouts(nil, 100)
            local res1, res2 = ngx.location.capture_multi{{"/req1"}, {"/req2"}}
            ngx.say("stderr:")
            ngx.print(res1.body)
            ngx.say("stdout:")
            ngx.print(res2.body)
        }
    }

    location = /req1 {
        content_by_lua_block {
            local data, err = package.loaded.proc:stderr_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }

    location = /req2 {
        content_by_lua_block {
            local data, err = package.loaded.proc:stdout_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
stderr:
closed
stdout:
timeout



=== TEST 19: read stderr while read stdout in other request, individual result
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            package.loaded.proc = ngx_pipe.spawn({"sh", "-c", ">&2 echo hello"})
            local res1, res2 = ngx.location.capture_multi{{"/req1"}, {"/req2"}}
            ngx.say("stderr:")
            ngx.print(res1.body)
            ngx.say("stdout:")
            ngx.print(res2.body)
        }
    }

    location = /req1 {
        content_by_lua_block {
            local data, err = package.loaded.proc:stderr_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }

    location = /req2 {
        content_by_lua_block {
            local data, err = package.loaded.proc:stdout_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
stderr:
hello
stdout:
closed



=== TEST 20: read stderr, mix read pattern and stdout/stderr, merge_stderr is true
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local script = [[
                echo hello
                sleep 0.1
                >&2 echo world
                >&2 echo more
                sleep 0.1
                >&2 echo -n da
                sleep 0.1
                >&2 echo ta
                echo more
                >&2 echo -n data
            ]]

            local proc, err = ngx_pipe.spawn({"sh", "-c", script}, {merge_stderr = true})
            if not proc then
                ngx.say(err)
                return
            end

            ngx.say("reading stderr all")
            local data, err = proc:stderr_read_all()
            if not data then
                ngx.say(err)
                ngx.exit(ngx.OK)
            end
            ngx.say(data)

            proc = ngx_pipe.spawn({"sh", "-c", script}, {merge_stderr = true})
            ngx.say("reading stdout all")
            local data, err = proc:stdout_read_all()
            if not data then
                ngx.say(err)
                ngx.exit(ngx.OK)
            end
            ngx.say(data)

            proc = ngx_pipe.spawn({"sh", "-c", script}, {merge_stderr = true})
            ngx.say("reading any")
            i = 1
            while true do
                local data, err
                if i % 1 == 0 then
                    data, err = proc:stdout_read_any(1024)
                else
                    data, err = proc:stderr_read_any(1024)
                end

                i = i + 1
                if data then
                    ngx.print(data)
                else
                    if err ~= 'closed' then
                        ngx.say(err)
                    end
                    break
                end
            end
            ngx.say('')

        }
    }
--- error_log eval
qr/lua pipe spawn process:[0-9A-F]+ pid:\d+ merge_stderr:1 buffer_size:4096/
--- no_error_log
[error]
--- response_body
reading stderr all
hello
world
more
data
more
data
reading stdout all
hello
world
more
data
more
data
reading any
hello
world
more
data
more
data



=== TEST 21: more than one coroutines read with merge_stderr is true
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local script = "sleep 0.1 && echo this is && echo hello && >&2 echo world"
            local proc = ngx_pipe.spawn({"sh", "-c", script}, {merge_stderr = true})

            local function read(stderr)
                local data, err
                if stderr then
                    data, err = proc:stderr_read_line()
                else
                    data, err = proc:stdout_read_line()
                end

                if not data then
                    ngx.say(err)
                else
                    ngx.say(data)
                end
            end

            local th1 = ngx.thread.spawn(read, false)
            local th2 = ngx.thread.spawn(read, true)
            local th3 = ngx.thread.spawn(read, false)
            ngx.thread.wait(th1)
            ngx.thread.wait(th2)
            ngx.thread.wait(th3)
            th1 = ngx.thread.spawn(read, true)
            ngx.thread.wait(th1)
            ngx.thread.spawn(read, false)
        }
    }
--- response_body
pipe busy reading
pipe busy reading
this is
hello
world



=== TEST 22: read stderr, aborted by uthread kill, merge_stderr is true
--- config
    location = /t {
        content_by_lua_block {
            local ngx_pipe = require "ngx.pipe"
            local args = {"sh", "-c", "sleep 0.1 && >&2 echo hello && echo world"}
            local proc = ngx_pipe.spawn(args, {merge_stderr = true})

            local function read()
                proc:stderr_read_line()
                ngx.log(ngx.ERR, "can't reach here")
            end

            local th = ngx.thread.spawn(read)
            ngx.thread.kill(th)

            local data, err = proc:stdout_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end

            local data, err = proc:stderr_read_line()
            if not data then
                ngx.say(err)
            else
                ngx.say(data)
            end
        }
    }
--- response_body
hello
world
