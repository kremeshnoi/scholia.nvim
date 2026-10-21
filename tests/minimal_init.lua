local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local plenary = os.getenv "PLENARY_DIR" or (vim.fn.stdpath "data" .. "/lazy/plenary.nvim")

if not vim.uv.fs_stat(plenary) then
  plenary = root .. "/.tests/plenary.nvim"
  if not vim.uv.fs_stat(plenary) then
    vim.fn.system { "git", "clone", "--depth=1", "https://github.com/nvim-lua/plenary.nvim", plenary }
  end
end

vim.o.packpath = ""
vim.opt.rtp = vim.tbl_filter(function(dir)
  return not vim.startswith(dir, vim.fn.stdpath "data") and not vim.startswith(dir, vim.fn.stdpath "config")
end, vim.opt.rtp:get())
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(plenary)
vim.o.swapfile = false
vim.o.hidden = true
vim.cmd "runtime plugin/plenary.vim"
