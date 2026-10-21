local assert = require "luassert"
local h = require "tests.helpers"
local scholia = require "scholia"
local render = require "scholia.render"
local state = require "scholia.state"
local store = require "scholia.store"
local util = require "scholia.util"

local function notes(root)
  return store.load(root).notes
end

local function count(t)
  return vim.tbl_count(t)
end

describe("note flow", function()
  local root, file, src

  before_each(function()
    h.reset()
    h.setup()
    root, file = h.project(h.lines(30))
    vim.cmd.edit(file)
    src = vim.api.nvim_get_current_buf()
  end)

  local function open_at(row, mode, range)
    vim.api.nvim_set_current_buf(src)
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    return scholia.open { mode = mode or "split", range = range }
  end

  it("stores notes in a symlinked folder that does not exist yet", function()
    local base = h.tmpdir()
    vim.fn.mkdir(base .. "/real", "p")
    vim.uv.fs_symlink(base .. "/real", base .. "/link")
    h.setup { dir = base .. "/link/store" }
    local id = open_at(3)
    h.write_note { "text" }
    assert.is_not_nil(notes(root)[id])
    assert.is_true(util.exists(base .. "/real/store"))
  end)

  it("creates a single line note on save", function()
    local id = open_at(10)
    assert.are.same({}, notes(root))
    h.write_note { "remember this" }
    local entry = notes(root)[id]
    assert.are.equal("src/main.lua", entry.file)
    assert.are.same({ 10, 10 }, { entry.start, entry["end"] })
    assert.are.equal("code line number 11", entry.anchor.first)
    assert.are.equal("personal", entry.space)
    assert.is_true(util.exists(store.note_path(root, "src/main.lua", id)))
    assert.are.equal(id, scholia.get(src, 10).id)
    assert.is_nil(scholia.get(src, 11))
  end)

  it("creates a block note from a range", function()
    local id = open_at(0, "split", { 4, 7 })
    h.write_note { "block" }
    local entry = notes(root)[id]
    assert.are.same({ 4, 7 }, { entry.start, entry["end"] })
    assert.are.equal(id, scholia.get(src, 6).id)
  end)

  it("reopens the existing note for the same range", function()
    local id = open_at(0, "split", { 4, 7 })
    h.write_note { "block" }
    vim.cmd "close"
    assert.are.equal(id, open_at(0, "split", { 4, 7 }))
    vim.cmd "close"
    assert.are.equal(id, open_at(5))
  end)

  it("opens the shortest note for nested ranges", function()
    local outer = open_at(0, "split", { 2, 12 })
    h.write_note { "outer" }
    vim.cmd "close"
    local inner = open_at(0, "split", { 5, 6 })
    h.write_note { "inner" }
    vim.cmd "close"
    assert.are_not.equal(outer, inner)
    assert.are.equal(inner, open_at(5))
    vim.cmd "close"
    assert.are.equal(outer, open_at(3))
  end)

  it("deletes the note when saved empty", function()
    local id = open_at(3)
    h.write_note { "text" }
    h.write_note { "   ", "" }
    assert.is_nil(notes(root)[id])
    assert.is_false(util.exists(store.note_path(root, "src/main.lua", id)))
    assert.is_false(util.exists(store.project_dir(root)))
    assert.is_nil(scholia.get(src, 3))
  end)

  it("creates nothing when closed without saving and autosave is off", function()
    require("scholia.config").options.autosave = false
    open_at(3)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })
    vim.cmd "close!"
    assert.are.same({}, notes(root))
    assert.is_false(util.exists(store.project_dir(root)))
    assert.is_nil(scholia.get(src, 3))
  end)

  it("saves the note automatically when its window closes", function()
    local id = open_at(3, "float")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })
    vim.cmd "close"
    assert.is_not_nil(notes(root)[id])
    assert.are.same({ "draft" }, util.readlines(store.note_path(root, "src/main.lua", id)))
    assert.are.equal(id, scholia.get(src, 3).id)
  end)

  it("saves the note automatically when leaving insert mode", function()
    local id = open_at(3)
    local nbuf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(nbuf, 0, -1, false, { "typed" })
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = nbuf })
    assert.is_not_nil(notes(root)[id])
    assert.is_false(vim.bo[nbuf].modified)
  end)

  it("saves modified notes before quitting", function()
    local id = open_at(3)
    local nbuf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(nbuf, 0, -1, false, { "before quit" })
    vim.api.nvim_exec_autocmds("ExitPre", {})
    assert.is_not_nil(notes(root)[id])
    assert.is_false(vim.bo[nbuf].modified)
  end)

  it("does not create an empty note and deletes a cleared one on close", function()
    local id = open_at(3)
    local nbuf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(nbuf, 0, -1, false, { "  " })
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = nbuf })
    vim.cmd "close"
    assert.are.same({}, notes(root))
    vim.wait(50)
    assert.is_nil(state.pending[id])
    id = open_at(5)
    h.write_note { "keep" }
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    assert.is_not_nil(notes(root)[id])
    vim.cmd "close"
    assert.is_nil(notes(root)[id])
    assert.is_nil(scholia.get(src, 5))
  end)

  it("forgets an untouched new note when its window closes", function()
    local id = open_at(3)
    vim.cmd "close"
    vim.wait(50)
    assert.is_nil(state.pending[id])
  end)

  it("follows code edits made while the note is being written", function()
    local id = open_at(10)
    vim.api.nvim_buf_set_lines(src, 0, 0, false, { "x", "y" })
    h.write_note { "moved" }
    assert.are.same({ 12, 12 }, { notes(root)[id].start, notes(root)[id]["end"] })
  end)

  it("creates the note from b:scholia when the source buffer is gone", function()
    local id = open_at(7)
    local nbuf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_delete(src, { force = true })
    vim.api.nvim_set_current_buf(nbuf)
    h.write_note { "orphaned source" }
    assert.are.same({ 7, 7 }, { notes(root)[id].start, notes(root)[id]["end"] })
  end)

  it("deletes the note under the cursor", function()
    local id = open_at(9)
    h.write_note { "bye" }
    vim.cmd "close"
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    assert.is_true(scholia.delete())
    assert.is_nil(notes(root)[id])
    assert.is_false(util.exists(store.note_path(root, "src/main.lua", id)))
    assert.is_false(scholia.delete())
  end)

  it("changes the range of a note", function()
    local id = open_at(9)
    h.write_note { "grow" }
    vim.cmd "close"
    assert.is_true(scholia.set_range(id, 9, 14))
    local entry = notes(root)[id]
    assert.are.same({ 9, 14 }, { entry.start, entry["end"] })
    assert.are.equal("code line number 15", entry.anchor.last)
  end)

  it("syncs positions to the index on source save", function()
    local id = open_at(10)
    h.write_note { "sync" }
    vim.cmd "close"
    vim.api.nvim_buf_set_lines(src, 0, 0, false, { "a", "b", "c" })
    vim.cmd "silent write"
    assert.are.equal(13, notes(root)[id].start)
  end)

  it("re-anchors after the file changes outside neovim", function()
    local id = open_at(10)
    h.write_note { "external" }
    vim.cmd "close"
    vim.cmd "silent write"
    local lines = h.lines(30)
    table.insert(lines, 1, "external 1")
    table.insert(lines, 1, "external 2")
    vim.fn.writefile(lines, file)
    vim.cmd "silent edit!"
    local n = scholia.get(src, 12)
    assert.are.equal(id, n.id)
    assert.is_false(n.orphan)
  end)

  it("marks notes whose code disappeared as orphans", function()
    local id = open_at(10)
    h.write_note { "lost" }
    vim.cmd "close"
    vim.cmd "silent write"
    vim.fn.writefile(h.lines(30, "other"), file)
    vim.cmd "silent edit!"
    local n = scholia.get(src, 10)
    assert.are.equal(id, n.id)
    assert.is_true(n.orphan)
  end)

  it("jumps between notes", function()
    open_at(4)
    h.write_note { "a" }
    vim.cmd "close"
    open_at(20)
    h.write_note { "b" }
    vim.cmd "close"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    scholia.next()
    assert.are.equal(5, vim.api.nvim_win_get_cursor(0)[1])
    scholia.next()
    assert.are.equal(21, vim.api.nvim_win_get_cursor(0)[1])
    scholia.next()
    assert.are.equal(5, vim.api.nvim_win_get_cursor(0)[1])
    scholia.prev()
    assert.are.equal(21, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("lists project notes", function()
    open_at(4)
    h.write_note { "first" }
    vim.cmd "close"
    open_at(0, "split", { 10, 12 })
    h.write_note { "", "second" }
    vim.cmd "close"
    local list = scholia.list()
    assert.are.equal(2, #list)
    assert.are.equal("first", list[1].text)
    assert.are.equal("second", list[2].text)
    vim.cmd "Scholia quickfix"
    local qf = vim.fn.getqflist()
    assert.are.equal(2, #qf)
    assert.are.equal("[11–13] second", qf[2].text)
    vim.cmd "cclose"
  end)

  it("draws the icon on the first line and the bar below", function()
    require("scholia.config").options.column = "sign"
    open_at(0, "split", { 3, 5 })
    h.write_note { "bar" }
    vim.cmd "close"
    render.refresh(src)
    local marks = vim.api.nvim_buf_get_extmarks(src, render.ns, 0, -1, { details = true })
    assert.are.equal(2, count(marks))
    assert.are.equal(3, marks[1][2])
    assert.are.equal(vim.trim(require("scholia.config").options.icon), vim.trim(marks[1][4].sign_text))
    assert.are.equal("ScholiaIcon", marks[1][4].sign_hl_group)
    assert.are.same({ 4, 5 }, { marks[2][2], marks[2][4].end_row })
    assert.are.equal("▎", vim.trim(marks[2][4].sign_text))
    assert.are.equal("ScholiaBar", marks[2][4].sign_hl_group)
  end)

  it("draws only the bar when the icon is disabled", function()
    require("scholia.config").options.column = "sign"
    require("scholia.config").options.icon = false
    open_at(0, "split", { 3, 5 })
    h.write_note { "bar" }
    vim.cmd "close"
    render.refresh(src)
    local marks = vim.api.nvim_buf_get_extmarks(src, render.ns, 0, -1, { details = true })
    assert.are.equal(1, count(marks))
    assert.are.same({ 3, 5 }, { marks[1][2], marks[1][4].end_row })
  end)

  it("draws notes in a column of their own next to other signs", function()
    vim.wo.number = false
    vim.wo.relativenumber = false
    local ns = vim.api.nvim_create_namespace "scholia.test.git"
    for row = 2, 6 do
      vim.api.nvim_buf_set_extmark(src, ns, row, 0, { sign_text = "┃", priority = 100 })
    end
    open_at(0, "split", { 3, 5 })
    h.write_note { "bar" }
    vim.cmd "close"
    render.refresh(src)
    assert.are.equal(render.expr, vim.go.statuscolumn)
    assert.are.equal(render.expr, vim.wo.statuscolumn)
    assert.are.equal(0, count(vim.api.nvim_buf_get_extmarks(src, render.ns, 0, -1, {})))
    local function column(lnum)
      return vim.api.nvim_eval_statusline(render.expr, { winid = 0, use_statuscol_lnum = lnum }).str
    end
    local icon = require("scholia.config").options.icon
    assert.are.equal("┃ " .. icon .. " ", column(4):match "^%S+ %S+ ")
    assert.are.equal("┃ ▎ ", column(5):match "^%S+ %S+ ")
    assert.are.equal("┃   ", column(3))
  end)

  it("keeps a statuscolumn set by the user and falls back to signs", function()
    vim.go.statuscolumn = "%s%l "
    open_at(0, "split", { 3, 5 })
    h.write_note { "bar" }
    vim.cmd "close"
    render.refresh(src)
    assert.are.equal("%s%l ", vim.go.statuscolumn)
    assert.are.equal(2, count(vim.api.nvim_buf_get_extmarks(src, render.ns, 0, -1, {})))
  end)

  it("keeps the open quickfix list up to date", function()
    open_at(4)
    h.write_note { "first" }
    vim.cmd "close"
    open_at(10)
    h.write_note { "second" }
    vim.cmd "close"
    vim.cmd "Scholia quickfix"
    assert.are.equal(2, #vim.fn.getqflist())
    vim.cmd "wincmd p"
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    scholia.delete()
    vim.wait(100, function()
      return #vim.fn.getqflist() == 1
    end)
    assert.are.equal(1, #vim.fn.getqflist())
    open_at(20)
    h.write_note { "third" }
    vim.cmd "close"
    vim.wait(100, function()
      return #vim.fn.getqflist() == 2
    end)
    local qf = vim.fn.getqflist()
    assert.are.same({ "second", "third" }, { qf[1].text, qf[2].text })
    vim.cmd "cclose"
  end)

  it("opens files without git calls or work for notes of other files", function()
    open_at(4)
    h.write_note { "first" }
    vim.cmd "close"
    local fresh = h.project(h.lines(5))
    local project_id, exists, get_lines = util.project_id, util.exists, vim.api.nvim_buf_get_lines
    local git, stats, reads = 0, 0, 0
    util.project_id = function(...)
      git = git + 1
      return project_id(...)
    end
    util.exists = function(...)
      stats = stats + 1
      return exists(...)
    end
    vim.api.nvim_buf_get_lines = function(...)
      reads = reads + 1
      return get_lines(...)
    end
    local other = root .. "/src/other.lua"
    vim.fn.writefile(h.lines(5), other)
    local ok, err = pcall(function()
      vim.cmd.edit(fresh .. "/src/main.lua")
      vim.cmd.edit(other)
    end)
    util.project_id, util.exists, vim.api.nvim_buf_get_lines = project_id, exists, get_lines
    assert.is_true(ok, err)
    assert.are.same({ 0, 0, 0 }, { git, stats, reads })
  end)

  it("refreshes a hidden list only when it is shown again", function()
    open_at(4)
    h.write_note { "first" }
    vim.cmd "close"
    vim.cmd "Scholia quickfix"
    vim.cmd "cclose"
    local collect = require("scholia.actions").collect
    local calls = 0
    require("scholia.actions").collect = function(...)
      calls = calls + 1
      return collect(...)
    end
    local ok, err = pcall(function()
      open_at(10)
      h.write_note { "second" }
      vim.cmd "close"
      vim.cmd "silent write"
      vim.wait(50)
      assert.are.equal(0, calls)
      assert.are.equal(1, #vim.fn.getqflist())
      vim.cmd "copen"
      vim.wait(100, function()
        return #vim.fn.getqflist() == 2
      end)
      assert.are.equal(2, #vim.fn.getqflist())
    end)
    require("scholia.actions").collect = collect
    assert.is_true(ok, err)
    vim.cmd "cclose"
  end)

  it("lists live positions without writing unsaved ones to the index", function()
    local id = open_at(4)
    h.write_note { "first" }
    vim.cmd "close"
    vim.api.nvim_buf_set_lines(src, 0, 0, false, { "a", "b" })
    vim.cmd "Scholia quickfix"
    assert.are.equal(7, vim.fn.getqflist()[1].lnum)
    assert.are.equal(4, notes(root)[id].start)
    vim.cmd "cclose"
  end)

  it("keeps the anchor when the source buffer was deleted before saving", function()
    local id = open_at(5)
    h.write_note { "first" }
    vim.cmd("bdelete " .. src)
    h.write_note { "second" }
    local entry = notes(root)[id]
    assert.are.same({ 5, 5 }, { entry.start, entry["end"] })
    assert.are.equal("code line number 6", entry.anchor.first)
    local fresh = open_at(9)
    vim.cmd("bdelete " .. src)
    h.write_note { "new" }
    assert.are.equal("code line number 10", notes(root)[fresh].anchor.first)
    assert.is_false(scholia.set_range(id, 2, 3))
  end)

  it("does not rebind a note saved while its file changed outside neovim", function()
    local id = open_at(5)
    h.write_note { "first" }
    local note = vim.api.nvim_get_current_buf()
    vim.cmd("bwipeout! " .. src)
    vim.fn.writefile(vim.list_extend({ "x", "y", "z" }, h.lines(30)), file)
    vim.api.nvim_set_current_buf(note)
    h.write_note { "second" }
    local entry = notes(root)[id]
    assert.are.equal(5, entry.start)
    assert.are.equal("code line number 6", entry.anchor.first)
    vim.cmd.edit(file)
    local n = state.list(vim.api.nvim_get_current_buf())[1]
    assert.are.same({ 8, false }, { n.start, n.orphan })
  end)

  it("keeps a new note in place when the source is reloaded", function()
    local id = open_at(10)
    local note = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(src, 0, 0, false, { "a", "b" })
    vim.api.nvim_buf_call(src, function()
      vim.cmd "silent write"
      vim.cmd "edit"
    end)
    vim.api.nvim_set_current_win(note)
    h.write_note { "text" }
    local entry = notes(root)[id]
    assert.are.equal(12, entry.start)
    assert.are.equal("code line number 11", entry.anchor.first)
  end)

  it("deletes the note under the cursor in the quickfix list", function()
    local first = open_at(4)
    h.write_note { "first" }
    vim.cmd "close"
    local second = open_at(10)
    h.write_note { "second" }
    vim.cmd "close"
    local third = open_at(20)
    h.write_note { "third" }
    vim.cmd "close"
    vim.cmd "Scholia quickfix"
    assert.are.equal("qf", vim.bo.filetype)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd "normal dd"
    local qf = vim.fn.getqflist()
    assert.are.same({ "first", "third" }, { qf[1].text, qf[2].text })
    assert.is_nil(notes(root)[second])
    assert.are.equal(2, vim.api.nvim_win_get_cursor(0)[1])
    local ids = vim.tbl_map(function(n)
      return n.id
    end, state.list(src))
    assert.are.same({ first, third }, ids)
    vim.cmd "cclose"
  end)

  it("keeps the popup open under other floats and opens files in the code window", function()
    local origin = vim.api.nvim_get_current_win()
    open_at(4, "float")
    local note = vim.api.nvim_get_current_win()
    local picker = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 3,
    })
    vim.wait(20)
    assert.is_true(vim.api.nvim_win_is_valid(note))
    vim.api.nvim_win_close(picker, true)
    vim.api.nvim_set_current_win(note)
    local other = root .. "/src/other.lua"
    vim.fn.writefile(h.lines(5, "other"), other)
    vim.cmd.edit(other)
    vim.wait(100, function()
      return not vim.api.nvim_win_is_valid(note)
    end)
    assert.is_false(vim.api.nvim_win_is_valid(note))
    assert.are.equal(origin, vim.api.nvim_get_current_win())
    assert.are.equal(other, util.normalize(vim.api.nvim_buf_get_name(0)))
  end)

  it("opens notes as plain buffers without integrations", function()
    local events = {}
    local group = vim.api.nvim_create_augroup("test.events", { clear = true })
    vim.api.nvim_create_autocmd({ "BufReadPre", "BufReadPost", "BufEnter" }, {
      group = group,
      callback = function(a)
        events[#events + 1] = a.event
      end,
    })
    for _, mode in ipairs { "float", "split", "full" } do
      events = {}
      open_at(3, mode)
      local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
      assert.are.equal("scholia", vim.bo[buf].filetype)
      assert.are.equal("acwrite", vim.bo[buf].buftype)
      assert.is_false(vim.bo[buf].buflisted)
      assert.is_false(vim.b[buf].completion)
      assert.is_false(vim.diagnostic.is_enabled { bufnr = buf })
      assert.are.equal("", vim.wo[win].winbar)
      assert.is_false(vim.wo[win].number)
      assert.are.equal("no", vim.wo[win].signcolumn)
      assert.are.same({}, events)
      vim.cmd "close!"
    end
    vim.api.nvim_del_augroup_by_id(group)
  end)

  it("covers the whole editor in full mode", function()
    open_at(3, "full")
    local cfg = vim.api.nvim_win_get_config(0)
    assert.are.equal("editor", cfg.relative)
    assert.are.same({ vim.o.columns, vim.o.lines - vim.o.cmdheight }, { cfg.width, cfg.height })
    h.write_note { "full" }
    assert.are.equal(1, count(notes(root)))
    assert.is_false(vim.bo.modified)
  end)

  it("writes notes without fsync", function()
    local seen
    local writefile = vim.fn.writefile
    vim.fn.writefile = function(lines, path, flags)
      seen = flags
      return writefile(lines, path, flags)
    end
    local ok, err = pcall(function()
      open_at(3)
      h.write_note { "fast" }
    end)
    vim.fn.writefile = writefile
    assert.is_true(ok, err)
    assert.are.equal("S", seen)
  end)

  it("uses the cursor of the window that shows the given buffer", function()
    local id = open_at(5)
    h.write_note { "text" }
    vim.cmd "close"
    local other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(other, 0, -1, false, h.lines(30))
    vim.cmd "vsplit"
    vim.api.nvim_win_set_buf(0, other)
    vim.api.nvim_win_set_cursor(0, { 20, 0 })
    assert.are.equal(id, scholia.get(src).id)
    vim.cmd "close"
    local hidden = h.project(h.lines(5))
    local buf = vim.fn.bufadd(hidden .. "/src/main.lua")
    vim.fn.bufload(buf)
    local notify = vim.notify
    vim.notify = function() end
    local opened = scholia.open { buf = buf }
    vim.notify = notify
    assert.is_nil(opened)
    assert.is_nil(scholia.get(buf))
  end)

  it("feeds special keys of list_delete in other quickfix lists", function()
    require("scholia.config").options.keymaps.list_delete = "<C-x>"
    open_at(4)
    h.write_note { "first" }
    vim.cmd "close"
    vim.cmd "Scholia quickfix"
    local fed
    local feedkeys = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function(keys)
      fed = keys
    end
    vim.fn.setqflist({}, " ", { title = "other", items = { { filename = file, lnum = 1, text = "x" } } })
    local ok, err = pcall(require("scholia.actions").quickfix_delete)
    vim.api.nvim_feedkeys = feedkeys
    assert.is_true(ok, err)
    assert.are.equal("1" .. vim.api.nvim_replace_termcodes("<C-x>", true, false, true), fed)
    vim.cmd "cclose"
  end)

  it("draws the column only on the first screen row of a line", function()
    open_at(0, "split", { 3, 5 })
    h.write_note { "bar" }
    vim.cmd "close"
    render.refresh(src)
    vim.api.nvim_buf_set_text(src, 3, 0, 3, 0, { string.rep("long ", 100) })
    vim.wo.wrap = true
    render.refresh(src)
    vim.fn.winrestview { topline = 1 }
    vim.cmd "redraw!"
    local row = vim.fn.win_screenpos(0)[1] + 3
    assert.are.equal(require("scholia.config").options.icon, vim.fn.screenstring(row, 1))
    assert.are.equal(" ", vim.fn.screenstring(row + 1, 1))
    assert.are.equal("▎", vim.fn.screenstring(vim.fn.screenpos(0, 5, 1).row, 1))
  end)

  it("does not redraw or replace signs when nothing visible changed", function()
    open_at(0, "split", { 3, 5 })
    h.write_note { "bar" }
    vim.cmd "close"
    render.refresh(src)
    local redraw, set_extmark = vim.api.nvim__redraw, vim.api.nvim_buf_set_extmark
    local redraws, signs = 0, 0
    vim.api.nvim__redraw = function(opts)
      if opts.statuscolumn then
        redraws = redraws + 1
      end
      return redraw(opts)
    end
    vim.api.nvim_buf_set_extmark = function(buf, ns, ...)
      if ns == render.ns then
        signs = signs + 1
      end
      return set_extmark(buf, ns, ...)
    end
    local ok, err = pcall(function()
      vim.api.nvim_buf_set_text(src, 4, 0, 4, 0, { "typed " })
      render.refresh(src)
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      render.refresh(src)
      assert.are.equal(0, redraws)
      require("scholia.config").options.column = "sign"
      render.refresh(src)
      local placed = signs
      vim.api.nvim_buf_set_text(src, 4, 0, 4, 0, { "more " })
      render.refresh(src)
      assert.are.equal(placed, signs)
    end)
    vim.api.nvim__redraw, vim.api.nvim_buf_set_extmark = redraw, set_extmark
    assert.is_true(ok, err)
    assert.are.equal("ScholiaBar", render.views[src].cells[4].hl)
    vim.api.nvim_set_hl(0, "ScholiaBarActive", { fg = "#00ff00" })
    render.refresh(src)
    vim.api.nvim_set_hl(0, "ScholiaBarActive", { link = "ScholiaIcon" })
    assert.are.equal("ScholiaBarActive", render.views[src].cells[4].hl)
  end)

  it("decides between signs and the column by the windows of the buffer", function()
    vim.cmd.edit(root .. "/src/empty.lua")
    render.refresh(vim.api.nvim_get_current_buf())
    assert.are.equal("", vim.go.statuscolumn)
    vim.api.nvim_set_current_buf(src)
    open_at(0, "split", { 3, 5 })
    h.write_note { "bar" }
    vim.cmd "close"
    render.refresh(src)
    assert.are.equal(render.expr, vim.go.statuscolumn)
    assert.are.equal(0, count(vim.api.nvim_buf_get_extmarks(src, render.ns, 0, -1, {})))
    vim.cmd "vsplit"
    vim.wo.statuscolumn = "%s%l "
    render.refresh(src)
    assert.is_true(count(vim.api.nvim_buf_get_extmarks(src, render.ns, 0, -1, {})) > 0)
    vim.wo.statuscolumn = render.expr
    render.refresh(src)
    assert.are.equal(0, count(vim.api.nvim_buf_get_extmarks(src, render.ns, 0, -1, {})))
    vim.cmd "close"
  end)

  local function picker_with_notes()
    open_at(4)
    h.write_note { "first", "body of the first" }
    vim.cmd "close"
    open_at(0, "split", { 10, 12 })
    h.write_note { "second", "searchable detail" }
    vim.cmd "close"
    vim.cmd "Scholia list"
    return require "scholia.picker"
  end

  local function results(p)
    return vim.api.nvim_buf_get_lines(p.results.buf, 0, -1, false)
  end

  local function type_query(p, text)
    vim.api.nvim_buf_set_lines(p.prompt.buf, 0, -1, false, { p.prefix .. text })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = p.prompt.buf })
  end

  it("lists project notes in a picker with a preview", function()
    local picker = picker_with_notes()
    local p = picker.state()
    assert.are.equal(p.prompt.win, vim.api.nvim_get_current_win())
    assert.are.equal("prompt", vim.bo[p.prompt.buf].buftype)
    local lines = results(p)
    assert.are.equal(2, #lines)
    assert.is_truthy(lines[1]:find("src/main.lua:5  first", 1, true))
    assert.is_truthy(lines[2]:find("src/main.lua:11–13  second", 1, true))
    assert.are.same({ "first", "body of the first" }, vim.api.nvim_buf_get_lines(p.preview.buf, 0, -1, false))
    picker.move(1)
    assert.are.same({ "second", "searchable detail" }, vim.api.nvim_buf_get_lines(p.preview.buf, 0, -1, false))
    picker.close()
    assert.is_nil(picker.state())
    assert.is_false(vim.api.nvim_win_is_valid(p.prompt.win))
    assert.is_false(vim.api.nvim_win_is_valid(p.preview.win))
  end)

  it("filters the picker by note text and body", function()
    local picker = picker_with_notes()
    local p = picker.state()
    type_query(p, "detail")
    assert.are.equal(1, #results(p))
    assert.is_truthy(results(p)[1]:find("second", 1, true))
    type_query(p, "")
    assert.are.equal(2, #results(p))
    picker.close()
  end)

  it("jumps to the code of the selected note", function()
    local origin = vim.api.nvim_get_current_win()
    local picker = picker_with_notes()
    picker.move(1)
    picker.select()
    assert.is_nil(picker.state())
    assert.are.equal(origin, vim.api.nvim_get_current_win())
    assert.are.equal(src, vim.api.nvim_get_current_buf())
    assert.are.equal(11, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("deletes the selected note from the picker without asking", function()
    local picker = picker_with_notes()
    local p = picker.state()
    local id = p.shown[1].id
    picker.delete()
    assert.is_nil(notes(root)[id])
    assert.are.equal(1, #results(p))
    assert.is_truthy(results(p)[1]:find("second", 1, true))
    picker.close()
  end)

  it("sends the picker list to quickfix", function()
    local picker = picker_with_notes()
    picker.quickfix()
    assert.is_nil(picker.state())
    assert.are.equal(2, #vim.fn.getqflist())
    vim.cmd "cclose"
  end)

  it("closes the picker when focus leaves it", function()
    local origin = vim.api.nvim_get_current_win()
    local picker = picker_with_notes()
    vim.api.nvim_set_current_win(origin)
    vim.wait(100, function()
      return picker.state() == nil
    end)
    assert.is_nil(picker.state())
    assert.are.equal(origin, vim.api.nvim_get_current_win())
  end)

  it("refuses to work inside a note", function()
    open_at(3)
    assert.is_nil(scholia.open())
  end)
end)
