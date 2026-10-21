local M = {}

local uv = vim.uv
local alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local remotes = {}
local author

function M.notify(msg, level)
  vim.notify("scholia: " .. msg, level or vim.log.levels.INFO)
end

function M.ulid()
  local sec, usec = uv.gettimeofday()
  local ms = sec * 1000 + math.floor(usec / 1000)
  local out = {}
  for i = 10, 1, -1 do
    local d = ms % 32
    out[i] = alphabet:sub(d + 1, d + 1)
    ms = math.floor(ms / 32)
  end
  local bytes = uv.random(16)
  for i = 1, 16 do
    local d = bytes:byte(i) % 32
    out[10 + i] = alphabet:sub(d + 1, d + 1)
  end
  return table.concat(out)
end

function M.now()
  return os.time()
end

function M.normalize(path)
  if not path or path == "" then
    return nil
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  local real = uv.fs_realpath(path)
  if real then
    return real
  end
  local parent = vim.fs.dirname(path)
  if parent == path then
    return path
  end
  local base = M.normalize(parent)
  return (base == "/" and "" or base) .. "/" .. vim.fs.basename(path)
end

function M.cursor(buf)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    win = vim.fn.bufwinid(buf)
    if win == -1 then
      return nil
    end
  end
  return vim.api.nvim_win_get_cursor(win)[1] - 1
end

function M.exists(path)
  return path ~= nil and uv.fs_stat(path) ~= nil
end

function M.root(path)
  local root = vim.fs.root(path, ".git")
  return M.normalize(root or vim.fn.getcwd())
end

function M.relpath(root, path)
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  return path
end

function M.abspath(root, file)
  if file:sub(1, 1) == "/" then
    return file
  end
  return root .. "/" .. file
end

function M.encode(path)
  if path:find("%", 1, true) then
    return "~" .. path:gsub("[%%/]", function(c)
      return ("%%%02X"):format(c:byte())
    end)
  end
  return (path:gsub("/", "%%"))
end

function M.decode(name)
  if name:sub(1, 1) == "~" then
    return (name:sub(2):gsub("%%(%x%x)", function(hex)
      return string.char(tonumber(hex, 16))
    end))
  end
  return (name:gsub("%%", "/"))
end

function M.normalize_remote(url)
  url = vim.trim(url)
  url = url:gsub("^%a[%w+.-]*://", "")
  url = url:gsub("^[^@/]+@", "")
  url = url:gsub("^([^/:]+):%d+/", "%1/")
  url = url:gsub("^([^/:]+):", "%1/")
  url = url:gsub("/+$", "")
  url = url:gsub("%.git$", "")
  return url
end

local function git(cwd, args)
  local ok, res = pcall(function()
    return vim.system(vim.list_extend({ "git", "-C", cwd }, args), { text = true }):wait(2000)
  end)
  if not ok or not res or res.code ~= 0 then
    return nil
  end
  local out = vim.trim(res.stdout or "")
  return out ~= "" and out or nil
end

function M.project_id(root)
  if remotes[root] == nil then
    local url = git(root, { "remote", "get-url", "origin" })
    if not url then
      local names = git(root, { "remote" })
      local first = names and vim.split(names, "\n")[1]
      url = first and git(root, { "remote", "get-url", first })
    end
    remotes[root] = url and M.normalize_remote(url) or false
  end
  return remotes[root] or root
end

function M.author()
  if author == nil then
    author = git(vim.fn.getcwd(), { "config", "user.name" }) or os.getenv "USER" or "unknown"
  end
  return author
end

function M.readlines(path, max)
  if not M.exists(path) then
    return nil
  end
  local ok, lines
  if max then
    ok, lines = pcall(vim.fn.readfile, path, "", max)
  else
    ok, lines = pcall(vim.fn.readfile, path)
  end
  return ok and lines or nil
end

function M.first_line(lines)
  for _, line in ipairs(lines or {}) do
    local text = vim.trim(line)
    if text ~= "" then
      return text
    end
  end
end

function M.blank(lines)
  return M.first_line(lines) == nil
end

function M.truncate(text, max)
  if vim.fn.strchars(text) <= max then
    return text
  end
  return vim.fn.strcharpart(text, 0, math.max(max - 1, 0)) .. "…"
end

return M
