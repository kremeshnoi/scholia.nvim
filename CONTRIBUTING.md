# Contributing

Thanks for helping with scholia.nvim. Bug reports, ideas and pull requests are
welcome. For larger changes, especially anything around spaces
([ROADMAP.md](ROADMAP.md)), open an issue first so we can agree on the design.

## Setup

You need Neovim 0.10 or newer, git, [StyLua](https://github.com/JohnnyMorganz/StyLua)
and [selene](https://github.com/Kampfkarren/selene).

```sh
git clone https://github.com/kremeshnoi/scholia.nvim
cd scholia.nvim
make test
make lint
make format
```

Tests run with [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). It is
taken from `PLENARY_DIR`, from a lazy.nvim install, or cloned into `.tests/`.
The tests ignore your own config. To check the oldest supported version:

```sh
make test NVIM=/path/to/nvim-0.10/bin/nvim
```

To try your checkout in your own config with lazy.nvim:

```lua
{
  dir = "~/dev/scholia.nvim",
  name = "scholia.nvim",
  opts = {},
}
```

## Code

- No comments in code. That is the point of the plugin: if something needs
  explaining, make the code clearer, and keep personal remarks in a note.
- Match the surrounding code: naming, module layout, small local functions.
- No dependencies beyond Neovim itself.
- Keep opening and saving notes fast. Avoid work on every keystroke and
  project-wide work when a single file is opened.
- Never overwrite user data you could not read: a broken `index.json` stays
  untouched.

## Tests

- Every bug fix comes with a test that fails without the fix.
- New behavior comes with tests in `tests/spec/`. `flow_spec.lua` covers user
  flows end to end, the other specs cover single modules.
- Restore anything a test stubs (`vim.notify`, `io.open`, API functions) even
  when the test fails: wrap the body in `pcall` and restore after it.

## Documentation

User-facing changes update both `README.md` and `doc/scholia.txt`. In the help
file, tags are right-aligned to column 78 and `:helptags doc` must run without
errors.

## Commits

One commit per module or concern, ordered from shared code to entry points:
tooling, `util`, modules without dependencies, dependent modules, `init`,
tests, docs. Messages look like this:

```
fix(modules): store
- keep the old index when writing the new one fails;
```

Types: `feat`, `fix`, `refactor`, `chore`, `docs`. The scope is the layer
(`config`, `utils`, `modules`, `entry`, `tests`, `docs`), the subject is the
module or concern.

## Pull requests

- `make test` and `make lint` pass; CI runs them on Neovim 0.10, stable and
  nightly.
- Describe what changed and why, and how you checked it by hand.
