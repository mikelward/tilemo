-- Encrypting the saved clipboard history (SPEC.md §9.1) with a key kept in
-- the login keychain, through macOS's own `security` and `openssl`:
-- AES-256-CBC, its key derived with PBKDF2 from a random 256-bit secret.
-- The keychain unlocks at login, so nothing asks; any program running as
-- you can read the secret through `security` too, so this keeps the history
-- from backups, copies and other accounts, not from those.
--
-- Each run is one short shell script, run with io.popen, so tide waits
-- for it (a few tens of milliseconds) and writes or reads it in one piece:
-- the script fetches the secret itself and hands it to openssl in its
-- environment, so the secret never passes through Hammerspoon or a command's
-- arguments, save `security add-generic-password`'s, the once it's made.
-- openssl writes and reads the encrypted file; only the plain text crosses
-- a pipe, into openssl or out of it.
--
-- Pure Lua: `popen` is io.popen's shape; `tools` names the commands, which
-- the tests point at stand-ins.

local M = {}

M.TOOLS = { security = "/usr/bin/security", openssl = "/usr/bin/openssl", sh = "/bin/sh" }
-- The keychain item: Keychain Access shows it under this name, tide's
-- as everything shown is.
M.SERVICE = "tide clipboard history"
M.ACCOUNT = "tide"
M.ENV = "TIDE_CLIPBOARD_KEY"

-- The scripts' exit statuses, besides openssl's own.
local NO_KEY, KEYCHAIN, MAKE_KEY = 90, 91, 92
local WHY = {
    [NO_KEY] = "there's no key for it in the keychain",
    [KEYCHAIN] = "the keychain wouldn't give its key; it may be locked",
    [MAKE_KEY] = "couldn't keep a new key in the keychain",
}

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function M.new(popen, tools)
    tools = tools or M.TOOLS
    local self = {}
    local sec, ssl = q(tools.security), q(tools.openssl)
    local item = "-s " .. q(M.SERVICE) .. " -a " .. q(M.ACCOUNT)
    local cipher = "enc -aes-256-cbc -pbkdf2 -md sha256 -salt -a -pass env:" .. M.ENV

    -- The secret into $k: made and kept the first time if `make`, as
    -- `security find-generic-password` says 44 for an item that isn't
    -- there; then exported for openssl alone.
    local function fetch(make)
        local missing = make
                and ("k=$(" .. ssl .. " rand -hex 32) && " .. sec .. " add-generic-password " .. item
                    .. " -w \"$k\" || exit " .. MAKE_KEY)
            or ("exit " .. NO_KEY)
        return "k=$(" .. sec .. " find-generic-password " .. item .. " -w 2>/dev/null); s=$?; "
            .. "if test $s -eq 44; then " .. missing .. "; elif test $s -ne 0; then exit " .. KEYCHAIN .. "; fi; "
            .. "export " .. M.ENV .. "=\"$k\"; "
    end

    local function run(script, mode, text)
        local f, err = popen(q(tools.sh) .. " -c " .. q(script) .. " 2>/dev/null", mode)
        if not f then
            return nil, "couldn't run the clipboard history's encryption: " .. tostring(err)
        end
        local out
        if mode == "w" then
            f:write(text)
        else
            out = f:read("a")
        end
        local ok, _, code = f:close()
        if ok then
            return out or true
        end
        return nil, WHY[code] or ("openssl failed (" .. tostring(code) .. ")")
    end

    -- Encrypts `text` into the file at `path`, made readable by you alone:
    -- `done(true)` or `done(nil, why)`.
    function self.seal(text, path, done)
        done(run("umask 077; " .. fetch(true) .. "exec " .. ssl .. " " .. cipher .. " -out " .. q(path), "w", text))
    end

    -- The file at `path` decrypted: `done(text)` or `done(nil, why)`.
    function self.open(path, done)
        done(run(fetch(false) .. "exec " .. ssl .. " " .. cipher .. " -d -in " .. q(path), "r"))
    end

    return self
end

return M
