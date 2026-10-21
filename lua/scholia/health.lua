local config = require "scholia.config"
local render = require "scholia.render"
local store = require "scholia.store"
local util = require "scholia.util"

local M = {}

local health = vim.health

local function version()
  if vim.fn.has "nvim-0.10" == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim >= 0.10 is required", { "Update Neovim" })
  end
end

local function setup()
  if vim.fn.exists ":Scholia" == 2 then
    health.ok "setup() has been called"
  else
    health.error("setup() has not been called", { 'Add require("scholia").setup() to your config' })
  end
end

local function storage()
  local dir = config.options.dir
  if not dir then
    return
  end
  if vim.fn.isdirectory(dir) == 0 then
    health.info(("storage %s does not exist yet, it is created with the first note"):format(dir))
    return
  end
  if vim.fn.filewritable(dir) == 2 then
    health.ok("storage " .. dir)
  else
    health.error(("storage %s is not writable"):format(dir))
  end
end

local function index()
  if not config.options.dir then
    return
  end
  local root = util.root(vim.fn.getcwd())
  local path = store.index_path(root)
  if not util.exists(path) then
    health.info("no notes for " .. root)
    return
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if ok and type(data) == "table" and type(data.notes) == "table" then
    health.ok(("%d notes for %s"):format(vim.tbl_count(data.notes), root))
  else
    health.error("broken index " .. path, { "Fix or remove the file, a copy is kept in index.json.bak" })
  end
  local stray = #store.unindexed(root)
  if stray > 0 then
    health.warn(("%d .md files without index entries"):format(stray), { ":Scholia orphans" })
  end
end

local function git()
  if vim.fn.executable "git" == 1 then
    health.ok "git found"
  else
    health.warn("git not found", { "project_id falls back to the project path, author to $USER" })
  end
end

local function keymaps()
  for name, lhs in pairs(config.options.keymaps or {}) do
    if lhs and name ~= "list_delete" then
      for _, mode in ipairs { "n" } do
        local map = vim.fn.maparg(lhs, mode, false, true)
        if vim.tbl_isempty(map) then
          health.warn(("%s (%s) is not mapped"):format(lhs, name))
        elseif not (map.desc or ""):find "^Scholia" then
          health.warn(("%s (%s) is overridden by another mapping"):format(lhs, name), { "Change keymaps." .. name })
        end
      end
    end
  end
end

local function column()
  local mode = config.options.column
  if mode == "statuscolumn" or (mode == "auto" and render.has_component(0)) then
    health.ok "bar is drawn in statuscolumn"
    return
  end
  health.ok "bar is drawn in the sign column"
  local width = vim.o.signcolumn:match "%d+$"
  if package.loaded.gitsigns and (not width or tonumber(width) < 2) then
    health.warn("gitsigns takes the same sign column", {
      'Set signcolumn = "auto:2" or use require("scholia").statuscolumn()',
    })
  end
end

function M.check()
  health.start "scholia"
  version()
  setup()
  git()
  storage()
  index()
  keymaps()
  column()
end

return M
