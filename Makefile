# tilemo
#
#   make test     run the tests (plain Lua 5.4, no Mac needed)
#   make lint     check every Lua file parses
#   make install  copy the Hammerspoon modules to ~/.hammerspoon/tilemo
#   make check-tide   compare tilemo's copies of tide's geometry, clocks
#                 and startup modules and character list with a tide checkout (TIDE=../tide
#                 by default)
#   make check-tileco   compare the dashboard's copies of tileco's clock
#                 modules with a tileco checkout (TILECO=../tileco by default)
#   make mocks    render the bar in fixed states to mocks/*.png (needs Node
#                 and Playwright's Chromium; skips with a note without them)

LUA ?= $(shell command -v lua5.4 || command -v lua)
LUAC ?= $(shell command -v luac5.4 || command -v luac)
HAMMERSPOON_DIR ?= $(HOME)/.hammerspoon
TIDE ?= ../tide
TILECO ?= ../tileco
# The dashboard files that are tileco's, copied unchanged.
TILECO_FILES := clocks.js calendar.js clockview.js launcher.css
export LUA_PATH := hammerspoon/?.lua;hammerspoon/?/init.lua;tests/?.lua;;

LUA_FILES := $(wildcard hammerspoon/tilemo/*.lua hammerspoon/timo/*.lua tests/*.lua ci/*.lua)
TESTS := $(wildcard tests/*_test.lua)

.PHONY: test lint install check-tide check-geometry check-tileco mocks

test:
	@status=0; for t in $(TESTS); do $(LUA) $$t || status=1; done; exit $$status

lint:
	@for f in $(LUA_FILES); do $(LUAC) -p $$f || exit 1; done

# An init.lua from before the rename says require("timo"): the shim takes
# the place of timo's own init.lua and loads tilemo.
install:
	mkdir -p $(HAMMERSPOON_DIR)/tilemo
	cp hammerspoon/tilemo/*.lua $(HAMMERSPOON_DIR)/tilemo/
	cp hammerspoon/tilemo/chars.tsv hammerspoon/tilemo/LICENSE-UNICODE $(HAMMERSPOON_DIR)/tilemo/
	mkdir -p $(HAMMERSPOON_DIR)/tilemo/dashboard
	cp hammerspoon/tilemo/dashboard/* $(HAMMERSPOON_DIR)/tilemo/dashboard/
	mkdir -p $(HAMMERSPOON_DIR)/timo
	cp hammerspoon/timo/init.lua $(HAMMERSPOON_DIR)/timo/
	@echo "Add to $(HAMMERSPOON_DIR)/init.lua:"
	@echo '  tilemo = require("tilemo")'
	@echo '  tilemo.start({})'

# geometry.lua is tide's, copied unchanged, so a workspace looks the same on
# both desktops; so is its clocks module, so tilemo reads and writes tide's
# clocks files as tide does, and its startup module, for startup.json; so is the picker's character list.
check-tide:
	cmp $(TIDE)/hypr/tide/geometry.lua hammerspoon/tilemo/geometry.lua
	cmp $(TIDE)/shell/lib/clocks.mjs hammerspoon/tilemo/dashboard/tide-clocks.js
	cmp $(TIDE)/shell/lib/startup.mjs hammerspoon/tilemo/dashboard/tide-startup.js
	cmp $(TIDE)/shell/chars/chars.tsv hammerspoon/tilemo/chars.tsv

check-geometry: check-tide

# The dashboard's clocks, calendar and styles are tileco's, so the two
# dashboards agree.
check-tileco:
	@for f in $(TILECO_FILES); do cmp $(TILECO)/src/$$f hammerspoon/tilemo/dashboard/$$f || exit 1; done

# The bar's page as tilemo builds it, rendered in fixed states. The page is
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
