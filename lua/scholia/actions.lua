local anchor = require "scholia.anchor"
local config = require "scholia.config"
local render = require "scholia.render"
local state = require "scholia.state"
local store = require "scholia.store"
local util = require "scholia.util"
local window = require "scholia.window"

local M = {}

local function title(file, s, e)
  local name = vim.fs.basename(file)
  if s == e then
    return ("%s:%d"):format(name, s + 1)
  end
  return ("%s:%d–%d"):format(name, s + 1, e + 1)
end

local function buffer_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and util.normalize(name) or nil
end

local function find_buffer(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and buffer_path(buf) == path then
      return buf
    end
  end
end

local function source(buf)
  if not buf or buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if store.is_note(buffer_path(buf)) then
    util.notify "you are already in a note"
    return nil
  end
  local st = state.ensure(buf)
  if not st then
    util.notify("notes are not available in this buffer", vim.log.levels.WARN)
    return nil
  end
  return st, buf
end

local function sorted(range)
  return math.min(range[1], range[2]), math.max(range[1], range[2])
end

local function find_exact(buf, s, e)
  for _, n in ipairs(state.list(buf)) do
    if n.start == s and n.finish == e then
      return n
    end
  end
end

local function find_pending(buf, s, e)
  for id, p in pairs(state.pending) do
    if p.buf == buf then
      local ps, pe = state.range(buf, p.mark)
      if ps == s and pe == e then
        return id
      end
    end
  end
end

local function source_lines(root, file)
  local buf = state.find(root, file)
  if buf then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  return util.readlines(util.abspath(root, file)) or {}
end

function M.open(opts)
  opts = opts or {}
  local st, buf = source(opts.buf)
  if not st then
    return nil
  end
  local id, s, e
  if opts.range then
    s, e = sorted(opts.range)
    local n = find_exact(buf, s, e)
    id = n and n.id
  else
    local row = util.cursor(buf)
    if not row then
      util.notify("the buffer is not shown in a window, pass a range", vim.log.levels.WARN)
      return nil
    end
    local n = state.at(buf, row)
    if n then
      id, s, e = n.id, n.start, n.finish
    else
      s, e = row, row
    end
  end
  if not id then
    id = find_pending(buf, s, e)
    if not id then
      id = util.ulid()
      state.pending[id] = { buf = buf, mark = state.place(buf, s, e), start = s, finish = e }
    end
  end
  local path = store.note_path(st.root, st.file, id)
  local fresh = not util.exists(path)
  local nbuf = window.open(path, opts.mode or "float", title(st.file, s, e))
  vim.b[nbuf].scholia = { project = st.root, file = st.file, start = s, ["end"] = e, id = id, source = buf }
  if vim.bo[nbuf].buftype == "acwrite" then
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      group = vim.api.nvim_create_augroup("scholia.write." .. nbuf, { clear = true }),
      buffer = nbuf,
      callback = function(a)
        M.save(nbuf, a.match)
      end,
    })
  end
  if config.options.close_with_q then
    vim.keymap.set("n", "q", function()
      window.close()
    end, { buffer = nbuf, nowait = true, desc = "Scholia: close" })
  end
  if fresh and config.options.start_insert_on_new and util.blank(vim.api.nvim_buf_get_lines(nbuf, 0, -1, false)) then
    vim.cmd.startinsert()
  end
  return id
end

function M.prepare(nbuf)
  local path = buffer_path(nbuf)
  if path then
    vim.fn.mkdir(vim.fs.dirname(path), "p")
  end
end

function M.save(nbuf, target)
  local path = buffer_path(nbuf)
  target = util.normalize(target) or path
  vim.fn.mkdir(vim.fs.dirname(target), "p")
  local ok, res = pcall(vim.fn.writefile, vim.api.nvim_buf_get_lines(nbuf, 0, -1, false), target, "S")
  if not ok or res ~= 0 then
    util.notify("cannot write " .. target .. (ok and "" or ": " .. tostring(res)), vim.log.levels.ERROR)
    return false
  end
  if target ~= path then
    return true
  end
  vim.bo[nbuf].modified = false
  M.written(nbuf)
  return true
end

function M.written(nbuf)
  local path = buffer_path(nbuf)
  local parsed = store.parse(path)
  if not parsed then
    return
  end
  local root, id = parsed.root, parsed.id
  local meta = vim.b[nbuf].scholia
  local existing = store.get(root, id)
  local file = (existing and existing.file) or (meta and meta.file)
  if not file then
    return
  end
  if util.blank(util.readlines(path)) then
    store.remove(root, id, file)
    state.drop(id)
    vim.bo[nbuf].modified = false
    render.refresh_all()
    M.changed()
    util.notify "note deleted"
    return
  end
  local sbuf, st = state.find(root, file)
  local p = state.pending[id]
  local mark
  if st and st.notes[id] then
    mark = st.notes[id].mark
  elseif p and p.buf and p.buf == sbuf then
    mark = p.mark
  end
  local s, e
  if sbuf and mark then
    s, e = state.range(sbuf, mark)
  end
  local detached = not s and existing and existing.anchor
  if not s then
    if existing then
      s, e = existing.start, existing["end"]
    elseif p then
      s, e = p.start, p.finish
    else
      s, e = meta.start, meta["end"]
    end
  end
  local now = util.now()
  local orphan = st and st.notes[id] and st.notes[id].orphan
  local entry = existing or { created = now }
  entry.file = file
  entry.space = entry.space or "personal"
  entry.author = entry.author or util.author()
  entry.start, entry["end"] = s, e
  if not detached and (not orphan or not entry.anchor) then
    entry.anchor = anchor.build(source_lines(root, file), s, e)
  end
  entry.updated = now
  if not store.put(root, id, entry) then
    vim.bo[nbuf].modified = true
    return
  end
  state.pending[id] = nil
  if sbuf then
    if not st.notes[id] then
      st.notes[id] = { mark = mark or state.place(sbuf, s, e), orphan = false, created = entry.created }
    end
    st.notes[id].preview = state.preview(root, file, id)
    render.refresh(sbuf)
  end
  vim.b[nbuf].scholia = { project = root, file = file, start = s, ["end"] = e, id = id, source = sbuf }
  M.changed()
end

function M.abandoned(nbuf, wiped)
  local meta = vim.b[nbuf].scholia
  if not meta or not state.pending[meta.id] then
    return
  end
  local path = buffer_path(nbuf)
  if util.exists(path) or (not wiped and vim.bo[nbuf].modified) then
    return
  end
  state.forget(meta.id)
  if not wiped then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(nbuf) and not vim.bo[nbuf].modified and vim.fn.bufwinid(nbuf) == -1 then
        pcall(vim.api.nvim_buf_delete, nbuf, { force = true })
      end
    end)
  end
end

local function confirm(prompt, path)
  if not config.options.confirm_delete then
    return true
  end
  local first = util.first_line(util.readlines(path, 50)) or ""
  return vim.fn.confirm(("%s\n%s"):format(prompt, first), "&Yes\n&No", 2) == 1
end

local function remove(path, root, id, file)
  local nbuf = find_buffer(path)
  if id then
    store.remove(root, id, file)
    state.drop(id)
  else
    os.remove(path)
  end
  if nbuf then
    pcall(vim.api.nvim_buf_delete, nbuf, { force = true })
  end
end

function M.delete(opts)
  opts = opts or {}
  local st, buf = source(opts.buf)
  if not st then
    return false
  end
  local row = opts.row or util.cursor(buf)
  local n = row and state.at(buf, row)
  if not n then
    util.notify "no note here"
    return false
  end
  local path = store.note_path(st.root, st.file, n.id)
  if not confirm(("Delete note %s?"):format(title(st.file, n.start, n.finish)), path) then
    return false
  end
  remove(path, st.root, n.id, st.file)
  render.refresh(buf)
  M.changed()
  return true
end

function M.set_range(id, s, e)
  s, e = sorted { s, e }
  for buf, st in pairs(state.buffers) do
    local n = st.notes[id]
    if n then
      local last = math.max(vim.api.nvim_buf_line_count(buf) - 1, 0)
      s, e = math.min(s, last), math.min(e, last)
      state.place(buf, s, e, n.mark)
      n.orphan = false
      local entry = store.get(st.root, id)
      if entry then
        entry.start, entry["end"] = s, e
        entry.anchor = anchor.build(vim.api.nvim_buf_get_lines(buf, 0, -1, false), s, e)
        entry.updated = util.now()
        store.put(st.root, id, entry)
      end
      render.refresh(buf)
      M.changed()
      return true
    end
  end
  util.notify("note is not attached to an open buffer", vim.log.levels.WARN)
  return false
end

local function jump(dir)
  local st, buf = source()
  if not st then
    return
  end
  local seen, starts = {}, {}
  for _, n in ipairs(state.list(buf)) do
    if not seen[n.start] then
      seen[n.start] = true
      starts[#starts + 1] = n.start
    end
  end
  if #starts == 0 then
    util.notify "no notes in this buffer"
    return
  end
  table.sort(starts)
  local row = util.cursor(buf)
  local target
  if dir > 0 then
    for _, s in ipairs(starts) do
      if s > row then
        target = s
        break
      end
    end
    target = target or starts[1]
  else
    for i = #starts, 1, -1 do
      if starts[i] < row then
        target = starts[i]
        break
      end
    end
    target = target or starts[#starts]
  end
  vim.cmd "normal! m'"
  vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
  vim.cmd "normal! ^"
end

function M.next()
  jump(1)
end

function M.prev()
  jump(-1)
end

function M.current_root()
  local buf = vim.api.nvim_get_current_buf()
  local parsed = store.parse(buffer_path(buf))
  if parsed then
    return parsed.root
  end
  local st = state.buffers[buf]
  if st then
    return st.root
  end
  return util.root(vim.fn.getcwd())
end

function M.collect(root)
  local live = {}
  for buf, st in pairs(state.buffers) do
    if st.root == root and vim.api.nvim_buf_is_loaded(buf) then
      for id, n in pairs(st.notes) do
        local s, e = state.range(buf, n.mark)
        if s then
          live[id] = { s, e }
        end
      end
    end
  end
  local data = store.load(root)
  local out = {}
  for id, entry in pairs(data.notes) do
    local note = store.note_path(root, entry.file, id)
    local pos = live[id] or { entry.start or 0, entry["end"] or entry.start or 0 }
    out[#out + 1] = {
      id = id,
      file = entry.file,
      filename = util.abspath(root, entry.file),
      note = note,
      start = pos[1],
      finish = pos[2],
      text = util.first_line(util.readlines(note, 50)) or "",
      entry = entry,
    }
  end
  table.sort(out, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    if a.start ~= b.start then
      return a.start < b.start
    end
    return a.id < b.id
  end)
  return out
end

function M.is_orphan(root, n)
  local _, st = state.find(root, n.file)
  if st then
    return st.notes[n.id] ~= nil and st.notes[n.id].orphan
  end
  local lines = util.readlines(n.filename)
  if not lines then
    return true
  end
  local _, _, orphan = anchor.resolve(anchor.context(lines), n.entry)
  return orphan
end

local qf
local dirty = false

local function quickfix_items(kind, root)
  local items = {}
  for _, n in ipairs(M.collect(root)) do
    if kind ~= "orphans" or M.is_orphan(root, n) then
      local text = n.text
      if n.finish > n.start then
        text = ("[%d–%d] %s"):format(n.start + 1, n.finish + 1, text)
      end
      items[#items + 1] = { filename = n.filename, lnum = n.start + 1, col = 1, text = text, user_data = n.id }
    end
  end
  if kind == "orphans" then
    for _, path in ipairs(store.unindexed(root)) do
      local first = util.first_line(util.readlines(path, 50)) or ""
      items[#items + 1] = { filename = path, lnum = 1, col = 1, text = "unindexed: " .. first }
    end
  end
  return items
end

function M.quickfix(kind)
  kind = kind or "list"
  local root = M.current_root()
  local items = quickfix_items(kind, root)
  if #items == 0 then
    util.notify(kind == "orphans" and "no orphaned notes" or "no notes in this project")
    return
  end
  vim.fn.setqflist({}, " ", { title = "Scholia " .. kind, items = items })
  qf = { id = vim.fn.getqflist({ id = 0 }).id, kind = kind, root = root }
  vim.cmd.copen()
  local lhs = (config.options.keymaps or {}).list_delete
  if lhs then
    vim.keymap.set("n", lhs, M.quickfix_delete, { buffer = true, desc = "Scholia: delete note" })
  end
end

function M.refresh_quickfix()
  if not qf or vim.fn.getqflist({ id = qf.id }).id ~= qf.id then
    qf = nil
    return
  end
  dirty = false
  local items = quickfix_items(qf.kind, qf.root)
  local idx = vim.fn.getqflist({ id = qf.id, idx = 0 }).idx
  vim.fn.setqflist({}, "r", { id = qf.id, items = items, idx = math.max(math.min(idx, #items), 1) })
end

function M.quickfix_delete()
  local list = vim.fn.getqflist { id = 0, items = 0 }
  if not qf or list.id ~= qf.id then
    local keys = vim.api.nvim_replace_termcodes(config.options.keymaps.list_delete, true, false, true)
    vim.api.nvim_feedkeys(vim.v.count1 .. keys, "n", false)
    return false
  end
  local row = vim.fn.line "."
  local item = list.items[row]
  if not item then
    return false
  end
  local id = type(item.user_data) == "string" and item.user_data ~= "" and item.user_data or nil
  local entry = id and store.get(qf.root, id)
  local path
  if entry then
    path = store.note_path(qf.root, entry.file, id)
    local s = entry.start or 0
    if not confirm(("Delete note %s?"):format(title(entry.file, s, entry["end"] or s)), path) then
      return false
    end
  else
    path = util.normalize(vim.api.nvim_buf_get_name(item.bufnr))
    if not store.is_note(path) or not confirm(("Delete %s?"):format(vim.fs.basename(path)), path) then
      return false
    end
    id = nil
  end
  remove(path, qf.root, id, entry and entry.file)
  render.refresh_all()
  M.refresh_quickfix()
  local count = #vim.fn.getqflist({ id = qf.id, items = 0 }).items
  if count > 0 then
    pcall(vim.api.nvim_win_set_cursor, 0, { math.min(row, count), 0 })
  end
  return true
end

local refresh_pending = false

local function visible()
  return vim.fn.getqflist({ id = 0 }).id == qf.id and vim.fn.getqflist({ winid = 0 }).winid ~= 0
end

function M.shown()
  if qf and dirty and visible() then
    M.refresh_quickfix()
  end
end

function M.changed()
  if not qf or refresh_pending then
    return
  end
  if not visible() then
    dirty = true
    return
  end
  refresh_pending = true
  vim.schedule(function()
    refresh_pending = false
    M.refresh_quickfix()
  end)
end

return M
