.PHONY: test lint format

NVIM ?= nvim

test:
	$(NVIM) --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec { minimal_init = 'tests/minimal_init.lua', sequential = true }"

format:
	stylua lua tests

lint:
	stylua --check lua tests
	selene lua tests
