-- The Mac's light or dark, from tide's Appearance settings (SPEC.md §10;
-- tide SPEC.md §15): tide's own module works out which, and until when,
-- run in JavaScriptCore, so the Mac changes when tide does. With no mode in
-- tide's files, macOS's own appearance stays, Auto and all. Pure Lua:
-- running the script, and setting macOS's appearance, are the caller's.

local names = require("tide.names")

local M = {}

-- tide's modules, in the order bundled: its appearance module imports its
-- clocks, steps and palette modules.
M.MODULES = { "tide-clocks.js", "tide-steps.js", "tide-palette.js", "tide-appearance.js" }

-- Seconds at most between checks, so a clock that jumps, or a timer a
-- sleep held up, is caught within the hour as well as on a wake.
M.RECHECK = 3600

local function literal(v, encode)
    if v == nil then
        return "null"
    elseif type(v) == "string" then
        return names.js_string(v)
    end
    return encode(v)
end

-- JavaScript giving what tide's module says at `now` (ms) as JSON, after
-- `bundle` (dashboard.bundle of M.MODULES): the two files' texts (nil for
-- one that isn't there), and the switch by hand still holding, if any
-- (tide's flip: { dark, until, settings }). `encode` is hs.json.encode.
-- `last` is the last good answer's `good` ({ settings, chosen }): with a
-- file that's wrong, it stands, as tide keeps its last good settings, and
-- with none yet, macOS's own stays.
function M.script(bundle, shared, own, now, override, encode, last)
    return bundle .. "\n(function(){"
        .. 'const A=modules["./tide-appearance.js"];'
        .. "const shared=" .. literal(shared, encode) .. ",own=" .. literal(own, encode)
        .. ",now=" .. string.format("%d", now) .. ",override=" .. literal(override, encode) .. ";"
        -- Lua's nil `until` is tide's null: held until the settings change.
        .. "if(override&&override.until===undefined)override.until=null;"
        .. "const last=" .. literal(last, encode) .. ";"
        .. "const r=A.loadAppearance(shared,own,last?last.settings:undefined);const s=r.settings;"
        -- A mode set in either file, which tide follows; with none it
        -- leaves macOS's own. With a file that's wrong, the last good one's.
        .. "const chosen=r.errors.length>0?(last?last.chosen===true:false):[shared,own].some(t=>{if(t===null)return false;"
        .. "try{const v=JSON.parse(t);return v!==null&&typeof v==='object'&&'mode' in v;}catch(e){return false;}});"
        .. "const shown=A.themeAt(s,now,override);const plan=A.scheduled(s,now);"
        .. "return JSON.stringify({chosen,dark:shown.dark,next:shown.next,held:shown.override!==null,"
        .. "planned:plan.dark,plannedNext:plan.next,key:A.settingsKey(s),errors:r.errors,"
        .. "good:r.errors.length>0?last:{settings:s,chosen}});})()"
end

-- The script's answer, `run_js`'s (ok, result), as { chosen, dark, next,
-- held, planned, planned_next, key, errors }, or nil and why. `next` and
-- `planned_next` are ms, or nil for a mode that doesn't change.
function M.read(ok, result, decode)
    if not ok or type(result) ~= "string" then
        return nil, "couldn't work out light or dark: " .. tostring(result)
    end
    local good, r = pcall(decode, result)
    if not good or type(r) ~= "table" or type(r.dark) ~= "boolean" then
        return nil, "couldn't work out light or dark: " .. tostring(result)
    end
    return {
        chosen = r.chosen == true,
        dark = r.dark,
        next = type(r.next) == "number" and r.next or nil,
        held = r.held == true,
        planned = r.planned == true,
        planned_next = type(r.plannedNext) == "number" and r.plannedNext or nil,
        key = r.key,
        errors = type(r.errors) == "table" and r.errors or {},
        -- What to pass as `last` next time.
        good = type(r.good) == "table" and r.good or nil,
    }
end

-- The switch by hand to `dark` that holds against `plan` (M.read's) until
-- its next change, as tide's flip; nil when it's what the plan says, which
-- needs none.
function M.hold(plan, dark)
    if dark == plan.planned then
        return nil
    end
    return { dark = dark, ["until"] = plan.planned_next, settings = plan.key }
end

-- Seconds until `plan` next needs a look, from `now` (ms): its next change,
-- or M.RECHECK, whichever's sooner; never less than one.
function M.wait(plan, now)
    -- With no mode chosen there's nothing to follow, so tide's default
    -- schedule's next change isn't one to wake for.
    if not plan or not plan.chosen or not plan.next then
        return M.RECHECK
    end
    return math.max(1, math.min(M.RECHECK, math.ceil((plan.next - now) / 1000)))
end

-- The AppleScript that sets macOS's appearance, through System Events.
function M.applescript(dark)
    return 'tell application "System Events" to tell appearance preferences to set dark mode to '
        .. (dark and "true" or "false")
end

return M
