local M = {}

M.window = 2000

local Context = {}
Context.__index = Context

function M.context(lines)
  return setmetatable({ lines = lines, trimmed = {}, rows = nil }, Context)
end

function Context:at(row)
  local value = self.trimmed[row]
  if value == nil then
    local line = self.lines[row + 1]
    value = line and vim.trim(line) or false
    self.trimmed[row] = value
  end
  return value or nil
end

function Context:find(text)
  if not self.rows then
    self.rows = {}
    for i = 0, #self.lines - 1 do
      local key = self:at(i)
      local list = self.rows[key]
      if not list then
        list = {}
        self.rows[key] = list
      end
      list[#list + 1] = i
    end
  end
  return self.rows[text] or {}
end

local function trim(text)
  return type(text) == "string" and vim.trim(text) or nil
end

local function usable(text)
  return text ~= nil and vim.fn.strchars(text) > 2
end

function M.build(lines, s, e)
  return {
    first = lines[s + 1] or "",
    last = lines[e + 1] or "",
    before = lines[s] or "",
    after = lines[e + 2] or "",
  }
end

function M.resolve(ctx, entry)
  local last = math.max(#ctx.lines - 1, 0)
  local s = math.max(entry.start or 0, 0)
  local len = math.max((entry["end"] or s) - s, 0)
  local a = entry.anchor or {}
  local first, final = trim(a.first), trim(a.last)
  local before, after = trim(a.before), trim(a.after)

  local function block(r)
    return r >= 0 and r + len <= last and ctx:at(r) == first and ctx:at(r + len) == final
  end

  local function score(r)
    local n = 0
    if usable(before) and ctx:at(r - 1) == before then
      n = n + 1
    end
    if usable(after) and ctx:at(r + len + 1) == after then
      n = n + 1
    end
    return n
  end

  local function context(r)
    return block(r) and score(r) > 0
  end

  local function better(r, best)
    if not best then
      return true
    end
    local dr, db = math.abs(r - s), math.abs(best - s)
    local wr, wb = dr <= M.window, db <= M.window
    if wr ~= wb then
      return wr
    end
    local sr, sb = score(r), score(best)
    if sr ~= sb then
      return sr > sb
    end
    return dr < db
  end

  local function pick(candidates, accept)
    local best
    for _, r in ipairs(candidates) do
      if accept(r) and better(r, best) then
        best = r
      end
    end
    return best
  end

  if first == nil then
    return math.min(s, last), math.min(s + len, last), false
  end

  if block(s) then
    return s, s + len, false
  end

  if usable(first) then
    local candidates = ctx:find(first)
    local r = pick(candidates, block)
    if r then
      return r, r + len, false
    end
    r = pick(candidates, function()
      return true
    end)
    if r then
      return r, math.min(r + len, last), false
    end
  elseif usable(before) or usable(after) then
    local candidates = {}
    if usable(before) then
      for _, row in ipairs(ctx:find(before)) do
        candidates[#candidates + 1] = row + 1
      end
    end
    if usable(after) then
      for _, row in ipairs(ctx:find(after)) do
        candidates[#candidates + 1] = row - len - 1
      end
    end
    local r = pick(candidates, context)
    if r then
      return r, r + len, false
    end
  end

  return math.min(s, last), math.min(s + len, last), true
end

return M
