local config = require "scholia.config"
local util = require "scholia.util"

local M = {}

local function find(path)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if name ~= "" and util.normalize(name) == path then
      return win
    end
  end
end

function M.is_float(win)
  return vim.api.nvim_win_get_config(win or 0).relative ~= ""
end

function M.close(win)
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  require("scholia.actions").autosave(vim.api.nvim_win_get_buf(win), true)
  local ok, err = pcall(vim.api.nvim_win_close, win, false)
  if not ok then
    util.notify(tostring(err), vim.log.levels.WARN)
  end
end

local clean = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  statuscolumn = "",
  winbar = "",
  colorcolumn = "",
  cursorline = false,
  cursorcolumn = false,
  list = false,
  spell = false,
  wrap = true,
  linebreak = true,
}

local function plain(win)
  if not config.options.plain then
    return
  end
  for name, value in pairs(clean) do
    vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
  end
end

local function open_win(buf, opts)
  opts.noautocmd = config.options.plain or nil
  local win = vim.api.nvim_open_win(buf, true, opts)
  plain(win)
  return win
end

function M.buffer(path)
  local buf = vim.fn.bufadd(path)
  if vim.api.nvim_buf_is_loaded(buf) then
    return buf
  end
  if not config.options.plain then
    vim.bo[buf].buflisted = true
    vim.fn.bufload(buf)
    return buf
  end
  vim.bo[buf].buflisted = false
  vim.bo[buf].buftype = "acwrite"
  local ignore = vim.o.eventignore
  vim.o.eventignore = "all"
  local ok, err = pcall(vim.fn.bufload, buf)
  vim.o.eventignore = ignore
  if not ok then
    util.notify(tostring(err), vim.log.levels.ERROR)
  end
  vim.b[buf].completion = false
  vim.bo[buf].filetype = config.options.filetype
  vim.diagnostic.enable(false, { bufnr = buf })
  return buf
end

local function main_win(win)
  if win and vim.api.nvim_win_is_valid(win) and not M.is_float(win) then
    return win
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not M.is_float(w) then
      return w
    end
  end
end

local function redirect(win, buf, origin, group)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function()
      vim.schedule(function()
        if not vim.api.nvim_win_is_valid(win) then
          return
        end
        local other = vim.api.nvim_win_get_buf(win)
        if other == buf then
          return
        end
        local pos = vim.api.nvim_win_get_cursor(win)
        local target = main_win(origin)
        if not target then
          return
        end
        vim.api.nvim_win_set_buf(target, other)
        pcall(vim.api.nvim_win_set_cursor, target, pos)
        M.close(win)
        vim.api.nvim_set_current_win(target)
      end)
    end,
  })
end

local function float(path, title)
  local o = config.options.float
  local origin = vim.api.nvim_get_current_win()
  local buf = M.buffer(path)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local height = math.max(5, math.min(o.max_height, #lines))
  local width = math.max(math.min(o.width, vim.o.columns - 4), 10)
  local below = vim.api.nvim_win_get_height(0) - vim.fn.winline()
  local above = vim.fn.winline() - 1
  local up = below < height + 2 and above > below
  local win = open_win(buf, {
    relative = "cursor",
    anchor = up and "SW" or "NW",
    row = up and 0 or 1,
    col = 0,
    width = width,
    height = up and math.min(height, math.max(above - 2, 1)) or math.min(height, math.max(below - 2, 1)),
    style = "minimal",
    border = o.border,
    title = " " .. title .. " ",
    title_pos = "center",
  })
  vim.keymap.set("n", "<Esc>", function()
    M.close(win)
  end, { buffer = buf, nowait = true, desc = "Scholia: close" })
  local group = vim.api.nvim_create_augroup("scholia.float." .. win, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      local current = vim.api.nvim_get_current_win()
      if current ~= win and not M.is_float(current) then
        vim.schedule(function()
          M.close(win)
        end)
      end
    end,
  })
  redirect(win, buf, origin, group)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.keymap.del, "n", "<Esc>", { buffer = buf })
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  return buf
end

local function screen()
  return {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = math.max(vim.o.lines - vim.o.cmdheight, 1),
  }
end

local function full(path)
  local origin = vim.api.nvim_get_current_win()
  local buf = M.buffer(path)
  local win = open_win(buf, vim.tbl_extend("force", screen(), { style = "minimal", border = "none", zindex = 40 }))
  local group = vim.api.nvim_create_augroup("scholia.full." .. win, { clear = true })
  redirect(win, buf, origin, group)
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_config(win, screen())
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    callback = function()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
  return buf
end

local function split(path)
  local o = config.options
  local buf = M.buffer(path)
  local horizontal = o.split == "horizontal"
  local side
  if horizontal then
    side = vim.o.splitbelow and "below" or "above"
  else
    side = vim.o.splitright and "right" or "left"
  end
  open_win(buf, {
    split = side,
    win = 0,
    width = not horizontal and o.split_size or nil,
    height = horizontal and o.split_size or nil,
  })
  return buf
end

function M.open(path, mode, title)
  local win = find(path)
  if win then
    vim.api.nvim_set_current_win(win)
    return vim.api.nvim_win_get_buf(win), false
  end
  if mode == "full" then
    return full(path), true
  end
  if mode == "split" then
    return split(path), true
  end
  return float(path, title), true
end

return M
