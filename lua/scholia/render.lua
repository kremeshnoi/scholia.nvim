local config = require "scholia.config"
local state = require "scholia.state"

local M = {}

M.ns = vim.api.nvim_create_namespace "scholia.signs"
M.deco = vim.api.nvim_create_namespace "scholia.deco"
M.views = {}
M.expr = "%!v:lua.require'scholia.render'.column()"

local scheduled = {}

function M.highlights()
  local links = {
    ScholiaBar = "ScholiaIcon",
    ScholiaBarActive = "ScholiaIcon",
    ScholiaRangeActive = "CursorLine",
    ScholiaPreview = "Comment",
    ScholiaOrphan = "DiagnosticWarn",
    ScholiaPickerSelection = "Visual",
    ScholiaPickerCaret = "ScholiaIcon",
    ScholiaPickerMatch = "Special",
    ScholiaPickerPath = "Comment",
    ScholiaPickerCount = "Comment",
  }
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  vim.api.nvim_set_hl(0, "ScholiaIcon", { fg = "#CE9178", default = true })
end

function M.has_component(win)
  return vim.wo[win].statuscolumn:find("scholia", 1, true) ~= nil
end

local function install()
  if config.options.column ~= "auto" or vim.go.statuscolumn ~= "" then
    return
  end
  vim.go.statuscolumn = M.expr
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.wo[win].statuscolumn == "" then
      vim.wo[win].statuscolumn = M.expr
    end
  end
end

local function columns(buf, has_notes)
  local column = config.options.column
  if has_notes then
    install()
  end
  local wins = vim.fn.win_findbuf(buf)
  local with, without = false, false
  for _, win in ipairs(wins) do
    if M.has_component(win) then
      with = true
    else
      without = true
    end
  end
  if column == "sign" then
    return true, with
  end
  if column == "statuscolumn" then
    return false, true
  end
  if #wins == 0 then
    local view = M.views[buf]
    return view == nil or view.signs, false
  end
  return without, with
end

local function active_hl()
  local active = vim.api.nvim_get_hl(0, { name = "ScholiaBarActive", link = false })
  local bar = vim.api.nvim_get_hl(0, { name = "ScholiaBar", link = false })
  return not vim.deep_equal(active, bar) and "ScholiaBarActive" or nil
end

local function same(a, b)
  if not a or not b then
    return false
  end
  for r, c in pairs(a) do
    local d = b[r]
    if not d or d.text ~= c.text or d.hl ~= c.hl then
      return false
    end
  end
  for r in pairs(b) do
    if not a[r] then
      return false
    end
  end
  return true
end

local function cursor_row(buf)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return nil
  end
  return vim.api.nvim_win_get_cursor(win)[1] - 1
end

local function place_signs(buf, cells)
  local rows = vim.tbl_keys(cells)
  table.sort(rows)
  local i = 1
  while i <= #rows do
    local first = rows[i]
    local cell = cells[first]
    local j = i
    while j < #rows do
      local next_row, next_cell = rows[j + 1], cells[rows[j + 1]]
      if
        next_row ~= rows[j] + 1
        or next_cell.id ~= cell.id
        or next_cell.text ~= cell.text
        or next_cell.hl ~= cell.hl
      then
        break
      end
      j = j + 1
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, first, 0, {
      end_row = rows[j],
      end_col = 0,
      strict = false,
      sign_text = cell.text,
      sign_hl_group = cell.hl,
      priority = config.options.sign_priority,
    })
    i = j + 1
  end
end

function M.refresh(buf)
  scheduled[buf] = nil
  if not vim.api.nvim_buf_is_valid(buf) then
    M.views[buf] = nil
    return
  end
  if not state.buffers[buf] then
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    M.views[buf] = nil
    return
  end
  local o = config.options
  local list = state.list(buf)
  local map = {}
  for _, n in ipairs(list) do
    for row = n.start, n.finish do
      if not map[row] then
        map[row] = n
      end
    end
  end
  local row = cursor_row(buf)
  local active = row and map[row] or nil
  local active_group = active_hl()
  local cells = {}
  for r, n in pairs(map) do
    local prev = map[r - 1]
    local hl = "ScholiaBar"
    if n.orphan then
      hl = "ScholiaOrphan"
    elseif active_group and active and active.id == n.id then
      hl = active_group
    end
    local text = o.bar
    if r == n.start and o.icon then
      text = o.icon
      if not n.orphan then
        hl = "ScholiaIcon"
      end
    elseif r == n.start and prev and prev.id ~= n.id then
      text = o.bar_start
    end
    cells[r] = { id = n.id, text = text, hl = hl }
  end
  local previous = M.views[buf]
  local signs, component = columns(buf, #list > 0)
  local unchanged = previous and previous.signs == signs and same(previous.cells, cells)
  M.views[buf] = {
    list = list,
    map = map,
    cells = cells,
    active = active,
    signs = signs,
    tick = vim.api.nvim_buf_get_changedtick(buf),
  }
  if not unchanged then
    vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
    if signs then
      place_signs(buf, cells)
    end
  end
  local active_changed = (previous and previous.active and previous.active.id) ~= (active and active.id)
  if (component and not unchanged) or (o.highlight_active_range and active_changed) then
    pcall(vim.api.nvim__redraw, { buf = buf, valid = false, statuscolumn = component })
  end
end

function M.update(buf)
  local view = M.views[buf]
  if view and view.tick == vim.api.nvim_buf_get_changedtick(buf) then
    local row = cursor_row(buf)
    local active = row and view.map[row] or nil
    if (active and active.id) == (view.active and view.active.id) and columns(buf, false) == view.signs then
      return
    end
  end
  M.refresh(buf)
end

function M.schedule(buf)
  if scheduled[buf] then
    return
  end
  scheduled[buf] = true
  vim.schedule(function()
    if scheduled[buf] then
      scheduled[buf] = nil
      M.update(buf)
    end
  end)
end

function M.refresh_all()
  for buf in pairs(state.buffers) do
    M.refresh(buf)
  end
end

function M.statuscolumn()
  local o = config.options
  local blank = string.rep(" ", math.max(vim.api.nvim_strwidth(o.bar), o.icon and vim.api.nvim_strwidth(o.icon) or 0))
  local ok, buf = pcall(vim.api.nvim_win_get_buf, vim.g.statusline_winid)
  local view = ok and M.views[buf] or nil
  if view and view.signs and o.column == "auto" then
    M.schedule(buf)
  end
  local cell = view and vim.v.virtnum == 0 and view.cells[vim.v.lnum - 1]
  if not cell then
    return blank
  end
  return "%#" .. cell.hl .. "#" .. cell.text .. "%*"
end

function M.column()
  local ok, buf = pcall(vim.api.nvim_win_get_buf, vim.g.statusline_winid)
  local cell = ""
  if ok and M.views[buf] then
    cell = M.statuscolumn() .. " "
  end
  local wo = vim.wo[vim.g.statusline_winid]
  local number = (wo.number or wo.relativenumber) and "%l " or ""
  return "%C%s" .. cell .. number
end

function M.provider()
  vim.api.nvim_set_decoration_provider(M.deco, {
    on_win = function(_, win, buf, top, bot)
      local o = config.options
      local view = M.views[buf]
      if not view or (not o.preview and not o.highlight_active_range) then
        return false
      end
      if o.preview then
        for _, n in ipairs(view.list) do
          if n.preview and n.start >= top and n.start <= bot then
            pcall(vim.api.nvim_buf_set_extmark, buf, M.deco, n.start, 0, {
              ephemeral = true,
              virt_text = { { n.preview, "ScholiaPreview" } },
              virt_text_pos = o.preview_position,
              hl_mode = "combine",
            })
          end
        end
      end
      local active = view.active
      if o.highlight_active_range and active and win == vim.api.nvim_get_current_win() then
        for row = math.max(active.start, top), math.min(active.finish, bot) do
          pcall(vim.api.nvim_buf_set_extmark, buf, M.deco, row, 0, {
            ephemeral = true,
            line_hl_group = "ScholiaRangeActive",
          })
        end
      end
      return false
    end,
  })
end

return M
