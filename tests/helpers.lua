local M = {}

function M.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return vim.uv.fs_realpath(dir)
end

function M.project(lines)
  local root = M.tmpdir()
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(root .. "/src", "p")
  local file = root .. "/src/main.lua"
  vim.fn.writefile(lines, file)
  return root, file
end

function M.lines(n, prefix)
  local out = {}
  for i = 1, n do
    out[i] = ("%s line number %d"):format(prefix or "code", i)
  end
  return out
end

function M.setup(opts)
  local dir = M.tmpdir()
  require("scholia").setup(
    vim.tbl_deep_extend("force", { dir = dir, confirm_delete = false, start_insert_on_new = false }, opts or {})
  )
  return dir
end

function M.reset()
  vim.cmd "silent! %bwipeout!"
  local state = require "scholia.state"
  state.buffers = {}
  state.pending = {}
  vim.go.statuscolumn = ""
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    vim.wo[win].statuscolumn = ""
  end
end

function M.write_note(text)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, text)
  vim.cmd "silent write"
end

return M
