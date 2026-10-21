local config = require "scholia.config"
local util = require "scholia.util"

local M = {}

M.ns = vim.api.nvim_create_namespace "scholia.picker"
M.caret = vim.api.nvim_create_namespace "scholia.picker.caret"

local titles = { list = "Scholia notes", orphans = "Scholia orphans" }
local active

local function location(item)
  if item.unindexed then
    return vim.fs.basename(item.filename)
  end
  if item.finish > item.start then
    return ("%s:%d–%d"):format(item.file, item.start + 1, item.finish + 1)
  end
  return ("%s:%d"):format(item.file, item.start + 1)
end

local function icon()
  local i = config.options.icon
  return i and i ~= "" and i .. " " or ""
end

local function build(raw)
  local prefix = "  " .. icon()
  local out = {}
  for i, item in ipairs(raw) do
    local body = util.readlines(item.note) or {}
    local loc = location(item)
    local line = prefix .. loc .. "  " .. item.text
    item.line = line
    item.body = body
    item.loc = { #prefix, #prefix + #loc }
    item.search = line .. " " .. table.concat(body, " ")
    item.index = i
    out[i] = item
  end
  return out
end

local function layout()
  local o = config.options.picker
  local cols, lines = vim.o.columns, math.max(vim.o.lines - vim.o.cmdheight, 1)
  local width = math.max(math.min(math.floor(cols * o.width), cols - 2), 20)
  local height = math.max(math.min(math.floor(lines * o.height), lines - 2), 8)
  local row = math.floor((lines - height) / 2)
  local col = math.floor((cols - width) / 2)
  local pw = width >= 80 and math.floor(width * o.preview_width) or 0
  local lw = width - pw
  return {
    prompt = { row = row, col = col, width = lw - 2, height = 1 },
    results = { row = row + 3, col = col, width = lw - 2, height = height - 5 },
    preview = {
      row = row,
      col = col + lw,
      width = math.max(pw - 2, 1),
      height = height - 2,
      hide = pw < 3,
    },
  }
end

local function scratch()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  return buf
end

local function float(buf, geometry, extra)
  local opts = vim.tbl_extend("force", {
    relative = "editor",
    style = "minimal",
    border = config.options.picker.border,
    zindex = 60,
    noautocmd = true,
  }, geometry, extra or {})
  return vim.api.nvim_open_win(buf, false, opts)
end

local function query(p)
  local line = vim.api.nvim_buf_get_lines(p.prompt.buf, 0, 1, false)[1] or ""
  return line:sub(#p.prefix + 1)
end

local function selected(p)
  return p.shown[p.selection]
end

local function draw_preview(p)
  local item = selected(p)
  local buf, win = p.preview.buf, p.preview.win
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, item and item.body or {})
  vim.bo[buf].modifiable = false
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  local cfg = vim.api.nvim_win_get_config(win)
  if not cfg.hide then
    pcall(vim.api.nvim_win_set_config, win, {
      title = item and " " .. location(item) .. " " or "",
      title_pos = "center",
    })
  end
end

local function draw_selection(p)
  local buf, win = p.results.buf, p.results.win
  vim.api.nvim_buf_clear_namespace(buf, M.caret, 0, -1)
  if not p.shown[1] then
    return
  end
  vim.api.nvim_win_set_cursor(win, { p.selection, 0 })
  vim.api.nvim_buf_set_extmark(buf, M.caret, p.selection - 1, 0, {
    virt_text = { { "❯", "ScholiaPickerCaret" } },
    virt_text_pos = "overlay",
  })
  draw_preview(p)
end

local function highlight(buf, row, item, positions)
  local function hl(s, e, group)
    vim.api.nvim_buf_set_extmark(buf, M.ns, row, s, { end_col = e, hl_group = group })
  end
  local ic = icon()
  if ic ~= "" then
    hl(2, 2 + #ic, "ScholiaIcon")
  end
  hl(item.loc[1], item.loc[2], "ScholiaPickerPath")
  local chars = vim.fn.strchars(item.line)
  for _, pos in ipairs(positions or {}) do
    if pos < chars then
      local s = vim.fn.byteidx(item.line, pos)
      local e = vim.fn.byteidx(item.line, pos + 1)
      vim.api.nvim_buf_set_extmark(buf, M.ns, row, s, { end_col = e, hl_group = "ScholiaPickerMatch", priority = 200 })
    end
  end
end

local function filter(p)
  local q = vim.trim(query(p))
  local shown, positions = {}, {}
  if q == "" then
    shown = vim.list_slice(p.items)
  else
    local keys = vim.tbl_map(function(item)
      return { search = item.search, index = item.index }
    end, p.items)
    local res = vim.fn.matchfuzzypos(keys, q, { key = "search" })
    for i, key in ipairs(res[1]) do
      shown[i] = p.items[key.index]
      positions[i] = res[2][i]
    end
  end
  p.shown = shown
  p.selection = math.max(math.min(p.selection, #shown), 1)
  local buf = p.results.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    vim.tbl_map(function(item)
      return item.line
    end, shown)
  )
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for i, item in ipairs(shown) do
    highlight(buf, i - 1, item, positions[i])
  end
  vim.api.nvim_buf_clear_namespace(p.prompt.buf, M.ns, 0, -1)
  vim.api.nvim_buf_set_extmark(p.prompt.buf, M.ns, 0, 0, {
    virt_text = { { ("%d / %d"):format(#shown, #p.items), "ScholiaPickerCount" } },
    virt_text_pos = "right_align",
  })
  draw_selection(p)
end

function M.close()
  local p = active
  if not p then
    return
  end
  active = nil
  pcall(vim.api.nvim_del_augroup_by_id, p.group)
  local inside = vim.api.nvim_get_current_win() == p.prompt.win
  for _, part in ipairs { p.prompt, p.results, p.preview } do
    if vim.api.nvim_win_is_valid(part.win) then
      pcall(vim.api.nvim_win_close, part.win, true)
    end
    if vim.api.nvim_buf_is_valid(part.buf) then
      pcall(vim.api.nvim_buf_delete, part.buf, { force = true })
    end
  end
  if not inside then
    return
  end
  if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
    vim.cmd.stopinsert()
  end
  if vim.api.nvim_win_is_valid(p.origin) then
    vim.api.nvim_set_current_win(p.origin)
  end
end

function M.move(delta)
  local p = active
  if not p or not p.shown[1] then
    return
  end
  p.selection = (p.selection - 1 + delta) % #p.shown + 1
  draw_selection(p)
end

function M.select(cmd)
  local p = active
  local item = p and selected(p)
  if not item then
    return
  end
  M.close()
  if cmd then
    vim.cmd(cmd)
  end
  vim.cmd.edit(vim.fn.fnameescape(item.filename))
  if not item.unindexed then
    pcall(vim.api.nvim_win_set_cursor, 0, { item.start + 1, 0 })
    vim.cmd "normal! zz^"
  end
end

function M.delete()
  local p = active
  local item = p and selected(p)
  if not item or not p.delete(item) then
    return
  end
  p.items = build(p.collect())
  filter(p)
end

function M.quickfix()
  local p = active
  if not p then
    return
  end
  M.close()
  p.quickfix()
end

function M.scroll(key)
  local p = active
  if not p or not vim.api.nvim_win_is_valid(p.preview.win) then
    return
  end
  vim.api.nvim_win_call(p.preview.win, function()
    vim.cmd("normal! " .. vim.keycode(key))
  end)
end

local function keymaps(p)
  local buf = p.prompt.buf
  local function map(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true })
  end
  local function move(delta)
    return function()
      M.move(delta)
    end
  end
  local function select(cmd)
    return function()
      M.select(cmd)
    end
  end
  local function scroll(key)
    return function()
      M.scroll(key)
    end
  end
  map({ "i", "n" }, "<CR>", select())
  map({ "i", "n" }, "<C-x>", select "split")
  map({ "i", "n" }, "<C-v>", select "vsplit")
  map({ "i", "n" }, "<C-t>", select "tab split")
  map({ "i", "n" }, "<C-n>", move(1))
  map({ "i", "n" }, "<C-p>", move(-1))
  map({ "i", "n" }, "<C-j>", move(1))
  map({ "i", "n" }, "<C-k>", move(-1))
  map({ "i", "n" }, "<Down>", move(1))
  map({ "i", "n" }, "<Up>", move(-1))
  map({ "i", "n" }, "<C-d>", scroll "<C-d>")
  map({ "i", "n" }, "<C-u>", scroll "<C-u>")
  map({ "i", "n" }, "<C-q>", M.quickfix)
  map({ "i", "n" }, "<M-d>", M.delete)
  map({ "i", "n" }, "<C-c>", M.close)
  map("n", "j", move(1))
  map("n", "k", move(-1))
  map("n", "<Esc>", M.close)
  map("n", "q", M.close)
  local lhs = (config.options.keymaps or {}).list_delete
  if lhs then
    map("n", lhs, M.delete)
  end
end

local function resize(p)
  local l = layout()
  for _, name in ipairs { "prompt", "results", "preview" } do
    local part = p[name]
    if vim.api.nvim_win_is_valid(part.win) then
      vim.api.nvim_win_set_config(part.win, vim.tbl_extend("force", { relative = "editor" }, l[name]))
    end
  end
  draw_selection(p)
end

function M.open(opts)
  M.close()
  local items = build(opts.collect())
  local l = layout()
  local p = {
    kind = opts.kind,
    items = items,
    shown = {},
    selection = 1,
    prefix = "> ",
    origin = vim.api.nvim_get_current_win(),
    collect = opts.collect,
    delete = opts.delete,
    quickfix = opts.quickfix,
  }
  p.preview = { buf = scratch() }
  p.preview.win = float(p.preview.buf, l.preview, { focusable = false })
  if not pcall(vim.treesitter.start, p.preview.buf, "markdown") then
    vim.bo[p.preview.buf].syntax = "markdown"
  end
  vim.wo[p.preview.win].wrap = true
  vim.wo[p.preview.win].linebreak = true
  p.results = { buf = scratch() }
  p.results.win = float(p.results.buf, l.results, { focusable = false })
  vim.wo[p.results.win].cursorline = true
  vim.wo[p.results.win].winhighlight = "CursorLine:ScholiaPickerSelection"
  vim.wo[p.results.win].wrap = false
  p.prompt = { buf = scratch() }
  vim.bo[p.prompt.buf].buftype = "prompt"
  vim.b[p.prompt.buf].completion = false
  vim.fn.prompt_setprompt(p.prompt.buf, p.prefix)
  p.prompt.win = float(p.prompt.buf, l.prompt, { title = " " .. titles[opts.kind] .. " ", title_pos = "center" })
  vim.api.nvim_set_current_win(p.prompt.win)
  active = p
  p.group = vim.api.nvim_create_augroup("scholia.picker", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = p.group,
    buffer = p.prompt.buf,
    callback = function()
      if active == p then
        p.selection = 1
        filter(p)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = p.group,
    buffer = p.prompt.buf,
    callback = function()
      vim.schedule(function()
        if active == p then
          M.close()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = p.group,
    callback = function()
      resize(p)
    end,
  })
  keymaps(p)
  filter(p)
  vim.cmd "startinsert!"
  return p
end

function M.state()
  return active
end

return M
