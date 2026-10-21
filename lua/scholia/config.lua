local M = {}

M.defaults = {
  dir = nil,
  icon = "",
  bar = "▎",
  bar_start = "▖",
  column = "auto",
  sign_priority = 5,
  highlight_active_range = false,
  preview = false,
  preview_max = 40,
  preview_position = "eol",
  float = { width = 70, max_height = 20, border = "rounded" },
  split = "vertical",
  split_size = nil,
  plain = true,
  filetype = "scholia",
  close_with_q = true,
  start_insert_on_new = true,
  confirm_delete = true,
  keymaps = {
    open = "<leader>M",
    full = "<leader>mf",
    split = "<leader>ms",
    delete = "<leader>md",
    list = "<leader>ml",
    list_delete = "dd",
    next = "<leader>mj",
    prev = "<leader>mk",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  M.options.dir = require("scholia.util").normalize(M.options.dir or (vim.fn.stdpath "data" .. "/scholia"))
  return M.options
end

return M
