// Karabiner-Elements' rules, turned on and off by tide (SPEC.md §15): the
// rule files in Karabiner's assets folder, which conf links there, and
// karabiner.json, where Karabiner keeps the rules it runs. Pure functions,
// run in JavaScriptCore (karabiner.lua), since only JSON.parse and
// JSON.stringify keep every other part of karabiner.json as it was. Turning a
// rule on copies it from its file into the selected profile, as Karabiner's
// own Enable button does; Karabiner reloads the file when it changes.

// `order` is conf's rules, top first, as each description starts
// (karabiner.lua's ORDER): Karabiner uses the first rule that matches a
// key, so some must sit above others. A rule not in it goes at the top, as
// Karabiner puts each rule it enables.

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

function rank(order, description) {
  return (Array.isArray(order) ? order : []).findIndex((prefix) => String(description).startsWith(prefix));
}

// A rule's name as the section shows it: its description up to the note in
// brackets, if any.
export function label(description) {
  const cut = description.indexOf(" (");
  return cut > 0 ? description.slice(0, cut) : description;
}

// The rules in `files`, a list of { name, text }: each { file, title,
// description, label, rule }, and what's wrong with any file, by name.
export function assetRules(files) {
  const rules = [];
  const errors = [];
  for (const f of Array.isArray(files) ? files : []) {
    let parsed;
    try {
      parsed = JSON.parse(f.text);
    } catch (e) {
      errors.push(`${f.name} isn't JSON: ${e.message}`);
      continue;
    }
    if (!isObject(parsed) || !Array.isArray(parsed.rules)) {
      errors.push(`${f.name} has no list of rules`);
      continue;
    }
    for (const rule of parsed.rules) {
      if (!isObject(rule) || typeof rule.description !== "string" || rule.description === "") {
        errors.push(`${f.name} has a rule with no description`);
        continue;
      }
      // Two files with one rule's name would be one switch for two rules.
      if (rules.some((r) => r.description === rule.description)) {
        errors.push(`${f.name} repeats the rule "${label(rule.description)}"`);
        continue;
      }
      rules.push({ file: f.name, title: typeof parsed.title === "string" ? parsed.title : "", description: rule.description, label: label(rule.description), rule });
    }
  }
  return { rules, errors };
}

// The selected profile's rules list in parsed karabiner.json `config`, made
// if it's missing, or an { error }.
function profileRules(config) {
  if (!isObject(config) || !Array.isArray(config.profiles) || config.profiles.length === 0) {
    return { error: "karabiner.json has no profiles" };
  }
  const profile = config.profiles.find((p) => isObject(p) && p.selected === true) ?? config.profiles[0];
  if (!isObject(profile)) {
    return { error: "karabiner.json's profile isn't an object" };
  }
  if (profile.complex_modifications === undefined) {
    profile.complex_modifications = {};
  }
  const cm = profile.complex_modifications;
  if (!isObject(cm)) {
    return { error: "karabiner.json's complex_modifications isn't an object" };
  }
  if (cm.rules === undefined) {
    cm.rules = [];
  }
  if (!Array.isArray(cm.rules)) {
    return { error: "karabiner.json's complex_modifications.rules isn't a list" };
  }
  return { list: cm.rules };
}

function parse(configText) {
  try {
    return { config: JSON.parse(configText) };
  } catch (e) {
    return { error: `karabiner.json isn't JSON: ${e.message}` };
  }
}

// A copy of `rule` as Karabiner keeps it once enabled. Karabiner may add
// keys of its own, such as "enabled", and writes each object's keys sorted,
// so a copy is the same rule when its manipulators match, key order aside;
// a list's order counts.
const copyOf = (rule) => JSON.parse(JSON.stringify(rule));
function canonical(v) {
  if (Array.isArray(v)) return v.map(canonical);
  if (!isObject(v)) return v;
  const out = {};
  for (const k of Object.keys(v).sort()) out[k] = canonical(v[k]);
  return out;
}
const same = (a, b) => JSON.stringify(canonical(a.manipulators ?? [])) === JSON.stringify(canonical(b.manipulators ?? []));

// Where the rule named `description` goes in `list`: above the first rule
// ranked below it in `order`, else below the last ranked above it, else at
// the top.
function slot(list, order, description) {
  const r = rank(order, description);
  if (r < 0) return 0;
  const below = list.findIndex((x) => isObject(x) && rank(order, x.description) > r);
  if (below >= 0) return below;
  for (let i = list.length - 1; i >= 0; i--) {
    const k = isObject(list[i]) ? rank(order, list[i].description) : -1;
    if (k >= 0 && k < r) return i + 1;
  }
  return 0;
}

function text(config) {
  return JSON.stringify(config, null, 4) + "\n";
}

// Each rule's state in karabiner.json: { description, on, stale }, stale
// when its copy there differs from its file, or an { error }. A copy
// Karabiner's window turned off ("enabled": false) is off.
export function ruleStates(configText, rules) {
  const p = parse(configText);
  if (p.error) return p;
  const r = profileRules(p.config);
  if (r.error) return r;
  return {
    states: rules.map((rule) => {
      const copy = r.list.find((x) => isObject(x) && x.description === rule.description);
      return {
        description: rule.description,
        on: copy !== undefined && copy.enabled !== false,
        stale: copy !== undefined && !same(copy, rule.rule),
      };
    }),
  };
}

// karabiner.json's text with the rule named `description` on or off, or an
// { error }. On, it's copied from its file into its place; off, every copy
// of it goes. The rest of the file stays as it was.
export function withRule(configText, rules, description, on, order) {
  const rule = rules.find((x) => x.description === description);
  if (!rule) return { error: `no rule "${label(String(description))}" in Karabiner's rule files` };
  const p = parse(configText);
  if (p.error) return p;
  const r = profileRules(p.config);
  if (r.error) return r;
  const list = r.list;
  for (let i = list.length - 1; i >= 0; i--) {
    if (isObject(list[i]) && list[i].description === description) list.splice(i, 1);
  }
  if (on) list.splice(slot(list, order, description), 0, copyOf(rule.rule));
  return { text: text(p.config) };
}

// karabiner.json brought up to date with the rule files: every copy that
// differs from its file replaced in place, and every rule not in `seen`
// that's off turned on, once, so a new rule from conf starts on and one you
// turn off stays off. { text, updated, enabled }: text is null when nothing
// changed, and the others name what did. Or an { error }.
export function synced(configText, rules, seen, order) {
  const p = parse(configText);
  if (p.error) return p;
  const r = profileRules(p.config);
  if (r.error) return r;
  const list = r.list;
  const known = new Set(Array.isArray(seen) ? seen : []);
  const updated = [];
  const enabled = [];
  for (const rule of rules) {
    const i = list.findIndex((x) => isObject(x) && x.description === rule.description);
    if (i >= 0) {
      if (!same(list[i], rule.rule)) {
        list[i] = Object.assign({}, list[i], copyOf(rule.rule));
        updated.push(rule.description);
      }
    } else if (!known.has(rule.description)) {
      list.splice(slot(list, order, rule.description), 0, copyOf(rule.rule));
      enabled.push(rule.description);
    }
  }
  return { text: updated.length + enabled.length > 0 ? text(p.config) : null, updated, enabled };
}
