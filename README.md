# scholia.nvim

Personal notes attached to lines and blocks of code that never end up in git.

A note is a plain Markdown file stored outside the project
(`stdpath("data")/scholia` by default). The plugin only knows where the file
lives and which lines it belongs to.

Notes open as plain text: markdown highlighting, but no LSP, completion,
diagnostics, breadcrumbs or line numbers. Opening and saving take a few
milliseconds: other plugins' autocommands do not run, and notes are written
without `fsync`. Set `plain = false` to get a regular `markdown` buffer with all
your integrations instead.

Requires Neovim >= 0.10 on Linux or macOS (Windows paths are not supported).
No dependencies. Full documentation: `:h scholia`.

## Install

```lua
{
  "kremeshnoi/scholia.nvim",
  opts = {},
}
```

## Usage

| Key                         | Mode | Action                                |
| --------------------------- | ---- | ------------------------------------- |
| `<leader>M`                 | n, x | open note in a popup                  |
| `<leader>mf`                | n, x | open note full screen                 |
| `<leader>ms`                | n, x | open note in a split                  |
| `<leader>md`                | n    | delete note                           |
| `<leader>ml`                | n    | all project notes in quickfix         |
| `dd`                        | n    | delete the note in that quickfix list |
| `<leader>mj` / `<leader>mk` | n    | next / previous note in the file      |

Opening always edits the note file. Save non-empty text to create or update the
note, save an empty file to delete it, close without saving to discard it.

In visual mode the selected lines become a block note. Selecting exactly the
range of an existing block opens that note.

The popup closes when you move to a regular window; pickers like Telescope
keep it open. A file opened from a popup or full screen note (picker, `:edit`,
`:bnext`) goes to the code window and the note closes.

`:Scholia [open|full|split|delete|list|orphans]` accepts a range, e.g.
`:'<,'>Scholia split`.

## Configuration

```lua
require("scholia").setup({
  dir = nil,
  icon = "",
  bar = "▎",
  bar_start = "▖",
  column = "auto",
  sign_priority = 5,
  highlight_active_range = false,
  preview = false,
  preview_max = 40,
  preview_position = "eol",
  float = { width = 70, max_height = 20, border = "rounded" },
  split = "vertical",
  split_size = nil,
  plain = true,
  filetype = "scholia",
  close_with_q = true,
  start_insert_on_new = true,
  confirm_delete = true,
  keymaps = {
    open = "<leader>M",
    full = "<leader>mf",
    split = "<leader>ms",
    delete = "<leader>md",
    list = "<leader>ml",
    list_delete = "dd",
    next = "<leader>mj",
    prev = "<leader>mk",
  },
})
```

Set any key to `false` to disable it.

`plain = true` loads notes without running other plugins' autocommands, as an
unlisted `acwrite` buffer with `filetype` (markdown highlighting), and disables
completion (`b:completion`), LSP and diagnostics in it. Full screen is a
floating window over the whole editor, so tabs, statusline and winbar are
hidden; popup and split windows get no numbers, signs or winbar.

`icon` (a Nerd Font glyph, `nf-fa-sticky_note_o`) marks the first line of each
note, `bar` the rest of a block. With `icon = false` the first line of a block
that directly follows another one gets `bar_start`, so adjacent blocks do not
merge into one line.

An open `:Scholia list` / `orphans` quickfix list is updated in place when
notes are created, changed, moved or deleted. A hidden list is refreshed when
it is shown again. `dd` in it deletes the note under the cursor (with
`confirm_delete`); in other quickfix lists `dd` works as usual.

### Sign column vs statuscolumn

Notes get a column of their own, so they never cover gitsigns or diagnostics.
With `column = "auto"` and an empty `statuscolumn`, scholia sets it to fold
column, sign column, notes and line numbers once a buffer with notes is shown.

If you already have a `statuscolumn`, it is kept. A buffer shown in a window
without the scholia component gets signs with a priority below gitsigns. Add
the component to your `statuscolumn` to get the separate column back:

```lua
vim.o.statuscolumn = "%s%{%v:lua.require'scholia'.statuscolumn()%}%l "
```

`column = "sign"` always uses signs, `signcolumn = "auto:2"` (or wider) shows
them next to gitsigns.

### Highlights

| Group                | Default          |
| -------------------- | ---------------- |
| `ScholiaIcon`        | `fg = #CE9178`   |
| `ScholiaBar`         | `ScholiaIcon`    |
| `ScholiaBarActive`   | `ScholiaIcon`    |
| `ScholiaRangeActive` | `CursorLine`     |
| `ScholiaPreview`     | `Comment`        |
| `ScholiaOrphan`      | `DiagnosticWarn` |

## Lua API

```lua
local scholia = require("scholia")
scholia.open({ mode = "float" | "full" | "split", range = { start, finish } })
scholia.delete({ row = n })
scholia.set_range(note_id, start, finish)
scholia.get(bufnr, row)
scholia.list({ project = path })
scholia.next()
scholia.prev()
scholia.statuscolumn()
```

Rows are 0-based. `get` returns `{ id, file, start, finish, orphan, created,
preview, path }`, `list` returns `{ id, file, filename, note, start, finish,
text, entry }` sorted by file and row; see `:h scholia-api`.

## Storage

```
~/.local/share/nvim/scholia/
└── %home%me%app/
    ├── index.json
    ├── files/
    │   └── src/components/LoanTable.vue/
    │       └── 01JAQ7Z8X3K9V2M4T6R8B0C1D2.md
    └── abs/
        └── etc/hosts/
            └── 01JAQ80F5W2N7H1Y9P3S5G6E4A.md
```

Notes of project files live under `files/`, notes of files outside the project
under `abs/`. Project roots that contain `%` are percent-encoded and prefixed
with `~`.

`index.json` keeps only bindings: file, range, anchor lines, author, space,
timestamps. Each note id is a ULID. `project_id` is the normalized git remote
URL, or the project path when there is no remote.

When a file changes outside Neovim, notes are re-anchored by the content of
their first and last lines and the surrounding lines. Notes that cannot be
found keep their old position and are highlighted as orphans; they stay
orphans until `set_range()` moves them. `:Scholia orphans` lists them,
together with `.md` files that have no index entry.

A broken or unreadable `index.json` is never overwritten: it is reported once,
copied to `index.json.bak`, and notes cannot be changed until it is fixed.

Only anchor lines of source code are stored next to the notes.

## Health

`:checkhealth scholia` checks the Neovim version, setup, git, the storage
directory, the index of the current project, overridden mappings and whether
gitsigns shares the sign column.

## Development

```sh
make test
make test NVIM=/path/to/nvim-0.10/bin/nvim
make lint
make format
```

Tests use plenary.nvim (`PLENARY_DIR`, the lazy.nvim install, or a clone into
`.tests/`) and ignore the user config and `site` directory. Lint needs
[StyLua](https://github.com/JohnnyMorganz/StyLua) and
[selene](https://github.com/Kampfkarren/selene). CI runs both and the tests on
Neovim 0.10, stable and nightly.
