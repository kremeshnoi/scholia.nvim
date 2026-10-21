local anchor = require "scholia.anchor"
local config = require "scholia.config"
local store = require "scholia.store"
local util = require "scholia.util"

local M = {}

M.ns = vim.api.nvim_create_namespace "scholia"
M.buffers = {}
M.pending = {}

function M.eligible(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return false
  end
  return not store.is_note(util.normalize(name))
end

function M.place(buf, s, e, id)
  return vim.api.nvim_buf_set_extmark(buf, M.ns, s, 0, {
    id = id,
    end_row = e + 1,
    end_col = 0,
    strict = false,
    right_gravity = true,
    end_right_gravity = false,
  })
end

function M.range(buf, mark)
  if not mark or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local ok, m = pcall(vim.api.nvim_buf_get_extmark_by_id, buf, M.ns, mark, { details = true })
  if not ok or not m[1] then
    return nil
  end
  local last = math.max(vim.api.nvim_buf_line_count(buf) - 1, 0)
  local d = m[3] or {}
  local s = math.min(m[1], last)
  local e = s
  if d.end_row then
    e = (d.end_col or 0) > 0 and d.end_row or d.end_row - 1
  end
  e = math.max(math.min(e, last), s)
  return s, e
end

function M.preview(root, file, id)
  if not config.options.preview then
    return nil
  end
  local text = util.first_line(util.readlines(store.note_path(root, file, id), 50))
  return text and util.truncate(text, config.options.preview_max) or nil
end

function M.attach(buf)
  if not M.eligible(buf) then
    return nil
  end
  local path = util.normalize(vim.api.nvim_buf_get_name(buf))
  local root = util.root(path)
  local st = { root = root, file = util.relpath(root, path), path = path, notes = {} }
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  M.buffers[buf] = st
  local data = store.load(root, true)
  local ctx
  for id, entry in pairs(data.notes) do
    if type(entry) == "table" and entry.file == st.file and util.exists(store.note_path(root, entry.file, id)) then
      ctx = ctx or anchor.context(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      local s, e, orphan = anchor.resolve(ctx, entry)
      st.notes[id] = {
        mark = M.place(buf, s, e),
        orphan = orphan,
        created = entry.created or 0,
        preview = M.preview(root, entry.file, id),
      }
    end
  end
  for _, p in pairs(M.pending) do
    if p.buf == buf then
      local last = math.max(vim.api.nvim_buf_line_count(buf) - 1, 0)
      p.mark = M.place(buf, math.min(p.start, last), math.min(p.finish, last))
    end
  end
  return st
end

function M.ensure(buf)
  return M.buffers[buf] or M.attach(buf)
end

function M.remember(buf)
  for _, p in pairs(M.pending) do
    if p.buf == buf then
      local s, e = M.range(buf, p.mark)
      if s then
        p.start, p.finish = s, e
      end
    end
  end
end

function M.unload(buf)
  M.remember(buf)
  M.buffers[buf] = nil
  for _, p in pairs(M.pending) do
    if p.buf == buf then
      p.mark = nil
    end
  end
end

function M.detach(buf)
  M.remember(buf)
  M.buffers[buf] = nil
  for _, p in pairs(M.pending) do
    if p.buf == buf then
      p.buf, p.mark = nil, nil
    end
  end
end

function M.find(root, file)
  for buf, st in pairs(M.buffers) do
    if st.root == root and st.file == file and vim.api.nvim_buf_is_loaded(buf) then
      return buf, st
    end
  end
end

function M.list(buf)
  local st = M.buffers[buf]
  local out = {}
  if not st then
    return out
  end
  for id, n in pairs(st.notes) do
    local s, e = M.range(buf, n.mark)
    if s then
      out[#out + 1] = {
        id = id,
        file = st.file,
        start = s,
        finish = e,
        orphan = n.orphan,
        created = n.created,
        preview = n.preview,
      }
    end
  end
  table.sort(out, function(a, b)
    local la, lb = a.finish - a.start, b.finish - b.start
    if la ~= lb then
      return la < lb
    end
    if a.created ~= b.created then
      return a.created < b.created
    end
    return a.id < b.id
  end)
  return out
end

function M.at(buf, row)
  for _, n in ipairs(M.list(buf)) do
    if n.start <= row and row <= n.finish then
      return n
    end
  end
end

function M.forget(id)
  local p = M.pending[id]
  if p and p.buf and p.mark then
    pcall(vim.api.nvim_buf_del_extmark, p.buf, M.ns, p.mark)
  end
  M.pending[id] = nil
end

function M.drop(id)
  M.forget(id)
  for buf, st in pairs(M.buffers) do
    local n = st.notes[id]
    if n then
      pcall(vim.api.nvim_buf_del_extmark, buf, M.ns, n.mark)
      st.notes[id] = nil
    end
  end
end

function M.sync(buf)
  local st = M.buffers[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  M.remember(buf)
  local data = store.load(st.root, true)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = false
  for id, n in pairs(st.notes) do
    local entry = data.notes[id]
    if not entry then
      pcall(vim.api.nvim_buf_del_extmark, buf, M.ns, n.mark)
      st.notes[id] = nil
    else
      local s, e = M.range(buf, n.mark)
      if s then
        local a = n.orphan and entry.anchor or anchor.build(lines, s, e)
        if entry.start ~= s or entry["end"] ~= e or not vim.deep_equal(entry.anchor, a) then
          entry.start, entry["end"], entry.anchor = s, e, a
          changed = true
        end
      end
    end
  end
  if changed then
    store.save(st.root, data)
  end
end

return M
