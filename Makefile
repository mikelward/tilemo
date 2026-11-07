# tidemo
#
#   make test     run the tests (plain Lua 5.4, no Mac needed)
#   make lint     check every Lua file parses
#   make install  copy the Hammerspoon modules to ~/.hammerspoon/tide
#   make check-tide   compare the copies of tide for Linux's geometry, direction,
#                 clocks, startup, clipboard, steps, layouts, input, fuzzy,
#                 workspaces and bar settings modules and character list with
#                 a tide checkout (TIDE=../tide by default)
#   make check-tideco   compare the dashboard's copies of tide for Chrome's clock
#                 modules and launcher page with a tideco checkout
#                 (TIDECO=../tideco by default)
#   make icons    render tide's logo to hammerspoon/tide/icons/*.png (needs
#                 Node and Playwright's Chromium; skips with a note without them)
#   make mocks    render the bar in fixed states to mocks/*.png (needs Node
#                 and Playwright's Chromium; skips with a note without them)

LUA ?= $(shell command -v lua5.4 || command -v lua)
LUAC ?= $(shell command -v luac5.4 || command -v luac)
HAMMERSPOON_DIR ?= $(HOME)/.hammerspoon
TIDE ?= ../tide
TIDECO ?= ../tideco
# The dashboard files that are tide for Chrome's, copied unchanged.
TIDECO_FILES := clocks.js calendar.js clockview.js launcher.css \
	launcherview.js launcher.js extras.js keepawake.js platform.js apps.js workspaces.js unread.js watchers.js
export LUA_PATH := hammerspoon/?.lua;hammerspoon/?/init.lua;tests/?.lua;;

LUA_FILES := $(wildcard hammerspoon/tide/*.lua hammerspoon/tilemo/*.lua hammerspoon/timo/*.lua tests/*.lua ci/*.lua)
TESTS := $(wildcard tests/*_test.lua)

.PHONY: test lint install check-tide check-geometry check-tideco mocks icons

test:
	@status=0; for t in $(TESTS); do $(LUA) $$t || status=1; done; exit $$status

lint:
	@for f in $(LUA_FILES); do $(LUAC) -p $$f || exit 1; done

# An init.lua from before a rename says require("tilemo") or require("timo"):
# each shim takes the place of that name's own init.lua and loads tide. The
# rest of an old ~/.hammerspoon/tilemo stays, unused.
install:
	mkdir -p $(HAMMERSPOON_DIR)/tide
	cp hammerspoon/tide/*.lua $(HAMMERSPOON_DIR)/tide/
	cp hammerspoon/tide/chars.tsv hammerspoon/tide/LICENSE-UNICODE $(HAMMERSPOON_DIR)/tide/
	cp hammerspoon/tide/compose.tsv hammerspoon/tide/LICENSE-X11 $(HAMMERSPOON_DIR)/tide/
	mkdir -p $(HAMMERSPOON_DIR)/tide/icons
	cp hammerspoon/tide/icons/*.png $(HAMMERSPOON_DIR)/tide/icons/
	mkdir -p $(HAMMERSPOON_DIR)/tide/dashboard
	cp hammerspoon/tide/dashboard/* $(HAMMERSPOON_DIR)/tide/dashboard/
	mkdir -p $(HAMMERSPOON_DIR)/tilemo $(HAMMERSPOON_DIR)/timo
	cp hammerspoon/tilemo/init.lua $(HAMMERSPOON_DIR)/tilemo/
	cp hammerspoon/timo/init.lua $(HAMMERSPOON_DIR)/timo/
	@echo "Add to $(HAMMERSPOON_DIR)/init.lua:"
	@echo '  tide = require("tide")'
	@echo '  tide.start({})'

# geometry.lua is tide for Linux's, copied unchanged, so a workspace looks the
# same on both desktops; so is its clocks module, so this reads and writes tide
# for Linux's clocks files as it does, and its startup, clipboard and input modules, for startup.json, clipboard.json and input.json, and its Workspaces page's, for workspaces.json; so is the picker's character list, and
# the logo, which `make icons` renders. The bar's chips and the settings
# window take tide for Linux's palette's colors.
check-tide:
	cmp $(TIDE)/hypr/tide/geometry.lua hammerspoon/tide/geometry.lua
	cmp $(TIDE)/hypr/tide/direction.lua hammerspoon/tide/direction.lua
	cmp $(TIDE)/shell/lib/clocks.mjs hammerspoon/tide/dashboard/tide-clocks.js
	cmp $(TIDE)/shell/lib/startup.mjs hammerspoon/tide/dashboard/tide-startup.js
	cmp $(TIDE)/shell/lib/clipboard.mjs hammerspoon/tide/dashboard/tide-clipboard.js
	cmp $(TIDE)/shell/lib/steps.mjs hammerspoon/tide/dashboard/tide-steps.js
	cmp $(TIDE)/shell/lib/layouts.mjs hammerspoon/tide/dashboard/tide-layouts.js
	cmp $(TIDE)/shell/lib/input.mjs hammerspoon/tide/dashboard/tide-input.js
	cmp $(TIDE)/shell/lib/appearance.mjs hammerspoon/tide/dashboard/tide-appearance.js
	cmp $(TIDE)/shell/lib/idle.mjs hammerspoon/tide/dashboard/tide-idle.js
	cmp $(TIDE)/shell/lib/dnd.mjs hammerspoon/tide/dashboard/tide-dnd.js
	cmp $(TIDE)/shell/lib/palette.mjs hammerspoon/tide/dashboard/tide-palette.js
	cmp $(TIDE)/shell/lib/fuzzy.mjs hammerspoon/tide/dashboard/tide-fuzzy.js
	cmp $(TIDE)/shell/lib/span.mjs hammerspoon/tide/dashboard/tide-span.js
	cmp $(TIDE)/shell/lib/workspacenames.mjs hammerspoon/tide/dashboard/tide-workspacenames.js
	cmp $(TIDE)/shell/lib/workspacepage.mjs hammerspoon/tide/dashboard/tide-workspacepage.js
	cmp $(TIDE)/shell/lib/barsettings.mjs hammerspoon/tide/dashboard/tide-barsettings.js
	cmp $(TIDE)/shell/chars/chars.tsv hammerspoon/tide/chars.tsv
	cmp $(TIDE)/shell/icons/tide-symbolic.svg hammerspoon/tide/icons/tide-symbolic.svg
	$(LUA) ci/check_chip_colors.lua $(TIDE)/theme/palette.json hammerspoon/tide/dashboard/bar.html
	$(LUA) ci/check_settings_colors.lua $(TIDE)/theme/palette.json hammerspoon/tide/dashboard/settings.html

check-geometry: check-tide

# The dashboard's clocks, calendar and styles are tide for Chrome's, so the two
# dashboards agree; so is the dashboard launcher's page and what it imports.
check-tideco:
	@for f in $(TIDECO_FILES); do cmp $(TIDECO)/src/$$f hammerspoon/tide/dashboard/$$f || exit 1; done
	@# The launcher page's markup is launcher.html's body, around tide's script.
	@dir=$$(mktemp -d) || exit 1; \
	sed -n '/^<body>$$/,/^<\/body>$$/p' $(TIDECO)/src/launcher.html | sed '1d;$$d' > "$$dir/theirs"; \
	sed -n '/^<body>$$/,/^<script>$$/p' hammerspoon/tide/dashboard/launcherpage.html | sed '1d;$$d' > "$$dir/ours"; \
	if test -s "$$dir/theirs" && cmp "$$dir/theirs" "$$dir/ours"; then status=0; else \
		echo "dashboard/launcherpage.html: its body isn't tide for Chrome's launcher.html's"; status=1; fi; \
	rm -rf "$$dir"; exit $$status

# The bar's page as tide builds it, rendered in fixed states. The page is
# written to a temporary directory (as .html, so the browser reads it as a
# page), removed whether the render works or not.
mocks:
	@dir=$$(mktemp -d) || exit 1; \
	if $(LUA) mocks/page.lua > "$$dir/bar.html"; then \
		NODE_PATH="$$(npm root -g)" node mocks/render.cjs "$$dir/bar.html"; status=$$?; \
	else \
		status=1; \
	fi; \
	rm -rf "$$dir"; exit $$status

# tide's logo as tide shows it (brand.lua), from the copy of tide's SVG.
icons:
	NODE_PATH="$$(npm root -g)" node hammerspoon/tide/icons/render.cjs
