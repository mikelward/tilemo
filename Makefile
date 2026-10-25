# timo
#
#   make test     run the tests (plain Lua 5.4, no Mac needed)
#   make lint     check every Lua file parses
#   make install  copy the Hammerspoon modules to ~/.hammerspoon/timo
#   make check-geometry   compare timo's copy of tide's geometry with a
#                 tide checkout (TIDE=../tide by default)
#   make check-tico   compare the dashboard's copies of tico's clock modules
#                 with a tico checkout (TICO=../tico by default)

LUA ?= $(shell command -v lua5.4 || command -v lua)
LUAC ?= $(shell command -v luac5.4 || command -v luac)
HAMMERSPOON_DIR ?= $(HOME)/.hammerspoon
TIDE ?= ../tide
TICO ?= ../tico
# The dashboard files that are tico's, copied unchanged.
TICO_FILES := clocks.js calendar.js clockview.js launcher.css
export LUA_PATH := hammerspoon/?.lua;hammerspoon/?/init.lua;tests/?.lua;;

LUA_FILES := $(wildcard hammerspoon/timo/*.lua tests/*.lua)
TESTS := $(wildcard tests/*_test.lua)

.PHONY: test lint install check-geometry check-tico

test:
	@status=0; for t in $(TESTS); do $(LUA) $$t || status=1; done; exit $$status

lint:
	@for f in $(LUA_FILES); do $(LUAC) -p $$f || exit 1; done

install:
	mkdir -p $(HAMMERSPOON_DIR)/timo
	cp hammerspoon/timo/*.lua $(HAMMERSPOON_DIR)/timo/
	mkdir -p $(HAMMERSPOON_DIR)/timo/dashboard
	cp hammerspoon/timo/dashboard/* $(HAMMERSPOON_DIR)/timo/dashboard/
	@echo "Add to $(HAMMERSPOON_DIR)/init.lua:"
	@echo '  timo = require("timo")'
	@echo '  timo.start({})'

# geometry.lua is tide's, copied unchanged, so a workspace looks the same on
# both desktops.
check-geometry:
	cmp $(TIDE)/hypr/tide/geometry.lua hammerspoon/timo/geometry.lua

# The dashboard's clocks, calendar and styles are tico's, so the two
# dashboards agree.
check-tico:
	@for f in $(TICO_FILES); do cmp $(TICO)/src/$$f hammerspoon/timo/dashboard/$$f || exit 1; done
