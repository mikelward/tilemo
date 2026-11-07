-- The saved clipboard history's encryption, with its key in the keychain
-- (SPEC.md §9.1): the real scripts, run by the real sh and openssl, with a
-- stand-in for macOS's `security` that keeps its keychain in a file.

local t = require("t")
local clipcrypt = require("tide.clipcrypt")

local function sh(cmd)
    local f = assert(io.popen(cmd))
    local out = f:read("a")
    f:close()
    return out
end

local OPENSSL = sh("command -v openssl"):gsub("%s+$", "")
if OPENSSL == "" then
    print("clipcrypt: skipped, no openssl")
    return
end

-- A scratch folder with a stand-in `security`: find-generic-password -w
-- prints the kept secret, or exits 44 without one (or 51 when `locked`
-- exists); add-generic-password keeps -w's value. Every call is logged.
local function keychain()
    local dir = sh("mktemp -d"):gsub("%s+$", "")
    local security = dir .. "/security"
    local f = assert(io.open(security, "w"))
    f:write([[#!/bin/sh
dir=$(dirname "$0")
echo "$*" >>"$dir/log"
case $1 in
find-generic-password)
    test -e "$dir/locked" && exit 51
    test -e "$dir/secret" || exit 44
    cat "$dir/secret"
    ;;
add-generic-password)
    while test $# -gt 0; do
        if test "$1" = -w; then printf '%s\n' "$2" >"$dir/secret"; fi
        shift
    done
    ;;
esac
]])
    f:close()
    sh("chmod +x '" .. security .. "'")
    local k = { dir = dir }
    k.crypt = clipcrypt.new(io.popen, { security = security, openssl = OPENSSL, sh = "/bin/sh" })
    function k.read(name)
        local g = io.open(dir .. "/" .. name, "rb")
        if not g then
            return nil
        end
        local s = g:read("a")
        g:close()
        return s
    end
    function k.done()
        sh("rm -rf '" .. dir .. "'")
    end
    return k
end

local function seal(k, text, path)
    local ok, err
    k.crypt.seal(text, path, function(o, e)
        ok, err = o, e
    end)
    return ok, err
end

local function open(k, path)
    local text, err
    k.crypt.open(path, function(o, e)
        text, err = o, e
    end)
    return text, err
end

t.test("what's sealed opens again, and isn't plain text on disk", function()
    local k = keychain()
    local path = k.dir .. "/history"
    local text = '[{"text":"my address, 1 Main St","at":1}]'
    t.eq({ seal(k, text, path) }, { true })
    t.eq(k.read("history"):find("Main St", 1, true), nil)
    t.eq({ open(k, path) }, { text })
    k.done()
end)

t.test("the first seal makes a key and keeps it; later ones use it", function()
    local k = keychain()
    seal(k, "one", k.dir .. "/a")
    local secret = k.read("secret")
    t.eq(secret:match("^%x+\n$") ~= nil and #secret == 65, true, "a random 256-bit secret")
    seal(k, "two", k.dir .. "/b")
    t.eq(k.read("secret"), secret)
    local adds = select(2, k.read("log"):gsub("add%-generic%-password", ""))
    t.eq(adds, 1)
    k.done()
end)

t.test("the secret goes to openssl in its environment, never its arguments", function()
    local k = keychain()
    seal(k, "x", k.dir .. "/a")
    local secret = k.read("secret"):gsub("%s+$", "")
    -- What `security` was asked, besides the one add, never holds it.
    for line in k.read("log"):gmatch("[^\n]+") do
        if not line:find("^add%-generic%-password") then
            t.eq(line:find(secret, 1, true), nil)
        end
    end
    k.done()
end)

t.test("the file is yours alone", function()
    local k = keychain()
    seal(k, "x", k.dir .. "/a")
    local mode = sh("stat -c %a '" .. k.dir .. "/a' 2>/dev/null || stat -f %Lp '" .. k.dir .. "/a'"):gsub("%s+$", "")
    t.eq(mode, "600")
    k.done()
end)

t.test("a large history goes through whole", function()
    local k = keychain()
    local big = string.rep("0123456789abcdef", 200000)
    seal(k, big, k.dir .. "/a")
    t.eq(open(k, k.dir .. "/a") == big, true)
    k.done()
end)

t.test("a locked keychain says so, and makes no new key", function()
    local k = keychain()
    sh("touch '" .. k.dir .. "/locked'")
    t.eq({ seal(k, "x", k.dir .. "/a") }, { nil, "the keychain wouldn't give its key; it may be locked" })
    t.eq(k.read("secret"), nil)
    k.done()
end)

t.test("opening never makes a key", function()
    local k = keychain()
    seal(k, "x", k.dir .. "/a")
    sh("rm '" .. k.dir .. "/secret'")
    t.eq({ open(k, k.dir .. "/a") }, { nil, "there's no key for it in the keychain" })
    t.eq(k.read("secret"), nil)
    k.done()
end)

t.test("a file under another key won't open, and says why", function()
    local k = keychain()
    seal(k, "x", k.dir .. "/a")
    local f = io.open(k.dir .. "/secret", "w")
    f:write(string.rep("ab", 32) .. "\n")
    f:close()
    local text, err = open(k, k.dir .. "/a")
    t.eq(text, nil)
    t.eq(err:find("^openssl failed") ~= nil, true)
    k.done()
end)

t.done("clipcrypt")
