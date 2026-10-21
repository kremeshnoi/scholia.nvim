local assert = require "luassert"
local anchor = require "scholia.anchor"

local function lines(n)
  local out = {}
  for i = 1, n do
    out[i] = "statement number " .. i
  end
  return out
end

local function entry(src, s, e)
  return { start = s, ["end"] = e, anchor = anchor.build(src, s, e) }
end

local function resolve(src, e)
  return anchor.resolve(anchor.context(src), e)
end

describe("anchor", function()
  it("keeps the position when lines match", function()
    local src = lines(20)
    local s, e, orphan = resolve(src, entry(src, 4, 6))
    assert.are.same({ 4, 6, false }, { s, e, orphan })
  end)

  it("compares trimmed lines", function()
    local src = lines(10)
    local n = entry(src, 3, 3)
    src[4] = "    " .. src[4] .. "   "
    local s, e, orphan = resolve(src, n)
    assert.are.same({ 3, 3, false }, { s, e, orphan })
  end)

  it("follows a block shifted by external edits", function()
    local src = lines(20)
    local n = entry(src, 10, 12)
    table.insert(src, 1, "new a")
    table.insert(src, 1, "new b")
    table.insert(src, 1, "new c")
    local s, e, orphan = resolve(src, n)
    assert.are.same({ 13, 15, false }, { s, e, orphan })
  end)

  it("keeps the block length when only the first line is found", function()
    local src = lines(20)
    local n = entry(src, 5, 8)
    src[9] = "changed last line"
    table.insert(src, 1, "inserted")
    local s, e, orphan = resolve(src, n)
    assert.are.same({ 6, 9, false }, { s, e, orphan })
  end)

  it("marks a deleted block as orphan and clamps it", function()
    local src = lines(20)
    local n = entry(src, 15, 17)
    for _ = 1, 10 do
      table.remove(src, 10)
    end
    local s, e, orphan = resolve(src, n)
    assert.are.same({ 9, 9, true }, { s, e, orphan })
  end)

  it("prefers the candidate with matching context", function()
    local src = { "alpha", "duplicate line", "omega", "x1", "x2", "x3", "beta", "duplicate line", "gamma" }
    local n = entry(src, 7, 7)
    table.remove(src, 4)
    table.remove(src, 4)
    table.remove(src, 4)
    local s, _, orphan = resolve(src, n)
    assert.are.equal(4, s)
    assert.is_false(orphan)
  end)

  it("falls back to context for short anchor lines", function()
    local src = { "function a()", "  body a", "end", "function b()", "  body b", "}", "trailer" }
    local n = entry(src, 5, 5)
    table.insert(src, 1, "header")
    table.insert(src, 1, "}")
    local s, e, orphan = resolve(src, n)
    assert.are.same({ 7, 7, false }, { s, e, orphan })
  end)

  it("uses the line below a short anchor when the line above changed", function()
    local src = { "function a()", "  body a", "}", "function b()", "  body b", "}", "trailer line" }
    local n = entry(src, 5, 5)
    src[5] = "  body b changed"
    table.insert(src, 1, "header")
    table.insert(src, 1, "}")
    local s, e, orphan = resolve(src, n)
    assert.are.same({ 7, 7, false }, { s, e, orphan })
  end)

  it("searches beyond the window when nothing is nearby", function()
    local src = lines(6000)
    local n = entry(src, 10, 10)
    local moved = {}
    for i = 1, 5000 do
      moved[i] = "padding " .. i
    end
    vim.list_extend(moved, src)
    local s, _, orphan = resolve(moved, n)
    assert.are.equal(5010, s)
    assert.is_false(orphan)
  end)

  it("resolves 100 notes quickly", function()
    local src = lines(5000)
    local notes = {}
    for i = 1, 100 do
      notes[i] = entry(src, i * 40, i * 40 + 2)
    end
    table.insert(src, 1, "shift")
    local t = vim.uv.hrtime()
    local ctx = anchor.context(src)
    for _, n in ipairs(notes) do
      anchor.resolve(ctx, n)
    end
    local ms = (vim.uv.hrtime() - t) / 1e6
    assert.is_true(ms < 50, "took " .. ms .. "ms")
  end)
end)
