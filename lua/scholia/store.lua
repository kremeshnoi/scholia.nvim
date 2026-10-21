local config = require "scholia.config"
local util = require "scholia.util"

local M = {}

local uv = vim.uv
local cache = {}
local broken = {}

M.backend = "local"

function M.project_dir(root)
  return config.options.dir .. "/" .. util.encode(root)
end

function M.index_path(root)
  return M.project_dir(root) .. "/index.json"
end

function M.note_dir(root, file)
  if file:sub(1, 1) == "/" then
    return M.project_dir(root) .. "/abs" .. file
  end
  return M.project_dir(root) .. "/files/" .. file
end

function M.note_path(root, file, id)
  return M.note_dir(root, file) .. "/" .. id .. ".md"
end

function M.is_note(path)
  local prefix = config.options.dir .. "/"
  return path ~= nil and path:sub(1, #prefix) == prefix and path:sub(-3) == ".md"
end

function M.parse(path)
  if not M.is_note(path) then
    return nil
  end
  local encoded = path:sub(#config.options.dir + 2):match "^([^/]+)/"
  if not encoded then
    return nil
  end
  return { root = util.decode(encoded), id = vim.fs.basename(path):sub(1, -4) }
end

local function empty(root)
  return { version = 1, project = root, notes = {} }
end

local function encode(data)
  local ok, out = pcall(vim.json.encode, data, { indent = "  ", sort_keys = true })
  if ok then
    return out
  end
  return vim.json.encode(data)
end

local function stamp(path)
  local st = uv.fs_stat(path)
  return st and ("%d.%d.%d"):format(st.mtime.sec, st.mtime.nsec, st.size) or nil
end

local function has_files(dir, pred)
  for name, kind in vim.fs.dir(dir, { depth = math.huge }) do
    if kind == "file" and pred(name) then
      return true
    end
  end
  return false
end

function M.cleanup(root)
  local dir = M.project_dir(root)
  if not util.exists(dir) then
    return
  end
  cache[root] = nil
  os.remove(M.index_path(root))
  local keep = has_files(dir, function(name)
    return name:sub(-3) == ".md" or name:sub(-4) == ".bak"
  end)
  if not keep then
    vim.fn.delete(dir, "rf")
  end
end

function M.save(root, data)
  if data.broken then
    util.notify(("index %s is unreadable, notes are not changed"):format(M.index_path(root)), vim.log.levels.ERROR)
    return false
  end
  if next(data.notes) == nil then
    M.cleanup(root)
    return true
  end
  data.project_id = data.project_id or util.project_id(root)
  vim.fn.mkdir(M.project_dir(root), "p")
  local path = M.index_path(root)
  local tmp = ("%s.tmp.%d"):format(path, uv.os_getpid())
  local fd, err = io.open(tmp, "w")
  if not fd then
    util.notify("cannot write index: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  local written, werr = fd:write(encode(data))
  local closed, cerr = fd:close()
  if not written or not closed then
    os.remove(tmp)
    util.notify("cannot write index: " .. tostring(werr or cerr), vim.log.levels.ERROR)
    return false
  end
  local ok, rerr = uv.fs_rename(tmp, path)
  if not ok then
    os.remove(tmp)
    util.notify("cannot write index: " .. tostring(rerr), vim.log.levels.ERROR)
    return false
  end
  cache[root] = { stamp = stamp(path), data = vim.deepcopy(data) }
  return true
end

local function read(root)
  local path = M.index_path(root)
  local current = stamp(path)
  local hit = cache[root]
  if current and hit and hit.stamp == current then
    return vim.deepcopy(hit.data)
  end
  cache[root] = nil
  if not current then
    broken[root] = nil
    return empty(root)
  end
  local data = empty(root)
  data.broken = true
  if broken[root] == current then
    return data
  end
  local fd, err = io.open(path, "r")
  if not fd then
    util.notify(("cannot read index %s: %s"):format(path, tostring(err)), vim.log.levels.ERROR)
    return data
  end
  local content = fd:read "*a"
  fd:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" or type(decoded.notes) ~= "table" then
    broken[root] = current
    uv.fs_copyfile(path, path .. ".bak")
    util.notify(("broken index %s, copy saved to index.json.bak"):format(path), vim.log.levels.ERROR)
    return data
  end
  broken[root] = nil
  data = decoded
  cache[root] = { stamp = current, data = vim.deepcopy(data) }
  return data
end

function M.load(root, fast)
  local data = read(root)
  if fast then
    return data
  end
  local dropped = false
  for id, entry in pairs(data.notes) do
    if type(entry) ~= "table" or type(entry.file) ~= "string" or not util.exists(M.note_path(root, entry.file, id)) then
      data.notes[id] = nil
      dropped = true
    end
  end
  data.version = data.version or 1
  data.project = root
  if dropped then
    M.save(root, data)
  end
  return data
end

function M.get(root, id)
  return M.load(root, true).notes[id]
end

function M.put(root, id, entry)
  local data = M.load(root, true)
  data.notes[id] = entry
  return M.save(root, data)
end

local function prune(dir, stop)
  while #dir > #stop and dir:sub(1, #stop) == stop and uv.fs_rmdir(dir) do
    dir = vim.fs.dirname(dir)
  end
end

function M.remove(root, id, file)
  local data = M.load(root, true)
  local entry = data.notes[id]
  file = file or (entry and entry.file)
  if file then
    local path = M.note_path(root, file, id)
    os.remove(path)
    prune(vim.fs.dirname(path), M.project_dir(root))
  end
  data.notes[id] = nil
  return M.save(root, data)
end

function M.unindexed(root)
  local dir = M.project_dir(root)
  local out = {}
  if not util.exists(dir) then
    return out
  end
  local data = M.load(root)
  for name, kind in vim.fs.dir(dir, { depth = math.huge }) do
    if kind == "file" and name:sub(-3) == ".md" and not data.notes[vim.fs.basename(name):sub(1, -4)] then
      out[#out + 1] = dir .. "/" .. name
    end
  end
  table.sort(out)
  return out
end

return M
