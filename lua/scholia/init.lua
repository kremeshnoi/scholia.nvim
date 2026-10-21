local actions = require "scholia.actions"
local config = require "scholia.config"
local render = require "scholia.render"
local state = require "scholia.state"
local store = require "scholia.store"
local util = require "scholia.util"

local M = {}

local modes = { open = "float", full = "full", split = "split" }
local subcommands = { "open", "full", "split", "delete", "list", "orphans" }

local function selection()
  local a, b = vim.fn.line "v", vim.fn.line "."
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  return { math.min(a, b) - 1, math.max(a, b) - 1 }
end

local function is_note(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and store.is_note(util.normalize(name))
end

local function attach(buf)
  if state.eligible(buf) then
    state.attach(buf)
    render.refresh(buf)
  end
end

local function autocmds()
  local group = vim.api.nvim_create_augroup("scholia", { clear = true })
  local function au(events, callback)
    vim.api.nvim_create_autocmd(events, { group = group, callback = callback })
  end
  au({ "BufReadPost", "BufNewFile", "BufFilePost" }, function(a)
    attach(a.buf)
  end)
  au("BufWritePre", function(a)
    if is_note(a.buf) then
      actions.prepare(a.buf)
    end
  end)
  au("BufWritePost", function(a)
    if is_note(a.buf) then
      actions.written(a.buf)
    elseif state.buffers[a.buf] then
      state.sync(a.buf)
      actions.changed()
    end
  end)
  au("BufHidden", function(a)
    if is_note(a.buf) then
      actions.abandoned(a.buf, false)
    end
  end)
  au("BufWinEnter", function(a)
    if vim.bo[a.buf].buftype == "quickfix" then
      vim.schedule(actions.shown)
    end
  end)
  au("BufUnload", function(a)
    if state.buffers[a.buf] then
      state.unload(a.buf)
      render.views[a.buf] = nil
    end
  end)
  au("BufWipeout", function(a)
    if is_note(a.buf) then
      actions.abandoned(a.buf, true)
    end
    state.detach(a.buf)
    render.views[a.buf] = nil
  end)
  au(
    { "TextChanged", "TextChangedI", "CursorMoved", "CursorMovedI", "BufEnter", "BufWinEnter", "WinEnter", "WinLeave" },
    function(a)
      if state.buffers[a.buf] then
        render.schedule(a.buf)
      end
    end
  )
  au("ColorScheme", render.highlights)
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "statuscolumn",
    callback = function()
      vim.schedule(render.refresh_all)
    end,
  })
  au("LspAttach", function(a)
    if config.options.plain and is_note(a.buf) then
      vim.schedule(function()
        pcall(vim.lsp.buf_detach_client, a.buf, a.data.client_id)
      end)
    end
  end)
  local ft = config.options.filetype
  if ft and ft ~= "markdown" then
    pcall(vim.treesitter.language.register, "markdown", ft)
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = ft,
      callback = function(a)
        if not pcall(vim.treesitter.start, a.buf, "markdown") then
          vim.bo[a.buf].syntax = "markdown"
        end
      end,
    })
  end
end

local function command()
  vim.api.nvim_create_user_command("Scholia", function(c)
    local sub = c.fargs[1] or "open"
    local range = c.range > 0 and { c.line1 - 1, c.line2 - 1 } or nil
    if modes[sub] then
      actions.open { mode = modes[sub], range = range }
    elseif sub == "delete" then
      actions.delete { row = range and range[1] }
    elseif sub == "list" or sub == "orphans" then
      actions.quickfix(sub)
    else
      util.notify("unknown subcommand " .. sub, vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    range = true,
    desc = "Scholia notes",
    complete = function(lead)
      return vim.tbl_filter(function(s)
        return s:sub(1, #lead) == lead
      end, subcommands)
    end,
  })
end

local function keymaps()
  local keys = config.options.keymaps or {}
  local function map(mode, lhs, fn, desc)
    if lhs then
      vim.keymap.set(mode, lhs, fn, { desc = "Scholia: " .. desc })
    end
  end
  for name, mode in pairs(modes) do
    map("n", keys[name], function()
      actions.open { mode = mode }
    end, "open note (" .. mode .. ")")
    map("x", keys[name], function()
      actions.open { mode = mode, range = selection() }
    end, "open block note (" .. mode .. ")")
  end
  map("n", keys.delete, function()
    actions.delete()
  end, "delete note")
  map("n", keys.list, function()
    actions.quickfix "list"
  end, "list project notes")
  map("n", keys.next, actions.next, "next note")
  map("n", keys.prev, actions.prev, "previous note")
end

function M.setup(opts)
  config.setup(opts)
  render.highlights()
  render.provider()
  autocmds()
  command()
  keymaps()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      attach(buf)
    end
  end
end

function M.open(opts)
  opts = opts or {}
  local range = opts.range and { opts.range[1], opts.range[2] or opts.range[1] } or nil
  return actions.open { mode = opts.mode, range = range, buf = opts.buf }
end

function M.delete(opts)
  return actions.delete(opts)
end

function M.set_range(id, s, e)
  return actions.set_range(id, s, e)
end

function M.get(bufnr, row)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not state.ensure(bufnr) then
    return nil
  end
  row = row or util.cursor(bufnr)
  local n = row and state.at(bufnr, row)
  if n then
    local st = state.buffers[bufnr]
    n.path = store.note_path(st.root, st.file, n.id)
  end
  return n
end

function M.list(opts)
  opts = opts or {}
  local root = opts.project and util.normalize(opts.project) or actions.current_root()
  return actions.collect(root)
end

M.next = actions.next
M.prev = actions.prev
M.statuscolumn = render.statuscolumn

return M
