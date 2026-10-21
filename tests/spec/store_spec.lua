local assert = require "luassert"
local h = require "tests.helpers"
local store = require "scholia.store"
local util = require "scholia.util"

local function note(root, file, id, text)
  local path = store.note_path(root, file, id)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(text or { "text" }, path)
  return path
end

local function entry(file)
  return { file = file, start = 0, ["end"] = 0, anchor = { first = "", last = "", before = "", after = "" } }
end

describe("store", function()
  local dir, root

  before_each(function()
    dir = h.setup()
    root = h.tmpdir()
  end)

  it("mirrors the project structure", function()
    local path = store.note_path(root, "src/a.vue", "ID")
    assert.are.equal(dir .. "/" .. root:gsub("/", "%%") .. "/files/src/a.vue/ID.md", path)
    assert.are.same({ root = root, id = "ID" }, store.parse(path))
  end)

  it("keeps notes of files outside the project under abs", function()
    local path = store.note_path(root, "/etc/hosts", "ID")
    assert.are.equal(store.project_dir(root) .. "/abs/etc/hosts/ID.md", path)
  end)

  it("does not mix notes with the index for a root index.json", function()
    note(root, "index.json", "N1")
    assert.is_true(store.put(root, "N1", entry "index.json"))
    assert.is_not_nil(store.load(root).notes.N1)
    assert.are_not.equal(store.index_path(root), store.note_dir(root, "index.json"))
  end)

  it("encodes roots with percent signs without collisions", function()
    local a, b = util.encode "/a%b", util.encode "/a/b"
    assert.are_not.equal(a, b)
    assert.are.equal("/a%b", util.decode(a))
    assert.are.equal("/a/b", util.decode(b))
    assert.are.equal("/x/%2F/y", util.decode(util.encode "/x/%2F/y"))
  end)

  it("rereads the index after an external change", function()
    note(root, "a.lua", "N1")
    store.put(root, "N1", entry "a.lua")
    local raw = vim.json.decode(table.concat(vim.fn.readfile(store.index_path(root)), "\n"))
    raw.notes.N1.start = 7
    raw.notes.N1.extra = string.rep("x", 10)
    vim.fn.writefile({ vim.json.encode(raw) }, store.index_path(root))
    assert.are.equal(7, store.get(root, "N1").start)
  end)

  it("returns copies of cached data", function()
    note(root, "a.lua", "N1")
    store.put(root, "N1", entry "a.lua")
    store.load(root).notes.N1.start = 99
    assert.are.equal(0, store.get(root, "N1").start)
  end)

  it("writes and reads index entries", function()
    note(root, "a.lua", "N1")
    store.put(root, "N1", entry "a.lua")
    local data = store.load(root)
    assert.are.equal("a.lua", data.notes.N1.file)
    assert.are.equal(1, data.version)
    assert.are.equal(root, data.project_id)
  end)

  it("leaves no temp files after atomic write", function()
    note(root, "a.lua", "N1")
    store.put(root, "N1", entry "a.lua")
    local names = {}
    for name in vim.fs.dir(store.project_dir(root)) do
      names[#names + 1] = name
    end
    table.sort(names)
    assert.are.same({ "files", "index.json" }, names)
  end)

  it("drops index entries whose file was deleted", function()
    local path = note(root, "a.lua", "N1")
    note(root, "a.lua", "N2")
    store.put(root, "N1", entry "a.lua")
    store.put(root, "N2", entry "a.lua")
    os.remove(path)
    local data = store.load(root)
    assert.is_nil(data.notes.N1)
    assert.is_not_nil(data.notes.N2)
    local raw = vim.json.decode(table.concat(vim.fn.readfile(store.index_path(root)), "\n"))
    assert.is_nil(raw.notes.N1)
  end)

  it("lists md files without index entries and keeps them", function()
    note(root, "a.lua", "N1")
    store.put(root, "N1", entry "a.lua")
    local stray = note(root, "b.lua", "STRAY")
    assert.are.same({ stray }, store.unindexed(root))
    store.remove(root, "N1")
    assert.is_true(util.exists(stray))
  end)

  it("removes the project folder when no notes remain", function()
    note(root, "src/a.lua", "N1")
    store.put(root, "N1", entry "src/a.lua")
    store.remove(root, "N1")
    assert.is_false(util.exists(store.project_dir(root)))
  end)

  it("backs up a broken index and does not overwrite it on load", function()
    vim.fn.mkdir(store.project_dir(root), "p")
    vim.fn.writefile({ "{ broken" }, store.index_path(root))
    local notify = vim.notify
    local messages = {}
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    local data = store.load(root)
    vim.notify = notify
    assert.are.same({}, data.notes)
    assert.are.same({ "{ broken" }, vim.fn.readfile(store.index_path(root)))
    assert.are.same({ "{ broken" }, vim.fn.readfile(store.index_path(root) .. ".bak"))
    assert.are.equal(1, #messages)
  end)

  it("reports a broken index once and refuses to overwrite it", function()
    vim.fn.mkdir(store.project_dir(root), "p")
    vim.fn.writefile({ "{ broken" }, store.index_path(root))
    note(root, "src/a.lua", "N1")
    local notify = vim.notify
    local messages = {}
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    local ok, err = pcall(function()
      store.load(root)
      store.load(root, true)
      store.get(root, "N1")
      return store.put(root, "N1", entry "src/a.lua")
    end)
    vim.notify = notify
    assert.is_true(ok, err)
    assert.is_false(err)
    assert.are.same({ "{ broken" }, vim.fn.readfile(store.index_path(root)))
    assert.are.equal(2, #messages)
    assert.truthy(messages[1]:find "broken index")
    assert.truthy(messages[2]:find "unreadable")
  end)

  it("keeps the old index when writing the new one fails", function()
    note(root, "src/a.lua", "N1")
    assert.is_true(store.put(root, "N1", entry "src/a.lua"))
    local before = vim.fn.readfile(store.index_path(root))
    local open, notify = io.open, vim.notify
    io.open = function(path, mode)
      if path:find(".tmp.", 1, true) then
        local fd = open(path, mode)
        return {
          write = function()
            return nil, "No space left on device"
          end,
          close = function()
            return fd:close()
          end,
        }
      end
      return open(path, mode)
    end
    vim.notify = function() end
    local ok, res = pcall(store.put, root, "N2", entry "src/a.lua")
    io.open, vim.notify = open, notify
    assert.is_true(ok, res)
    assert.is_false(res)
    assert.are.same(before, vim.fn.readfile(store.index_path(root)))
    assert.are.same(
      { "index.json" },
      vim.tbl_filter(function(name)
        return name:find "^index"
      end, vim.fn.readdir(store.project_dir(root)))
    )
  end)

  it("resolves symlinks in paths that do not exist yet", function()
    local base = h.tmpdir()
    vim.fn.mkdir(base .. "/real", "p")
    vim.uv.fs_symlink(base .. "/real", base .. "/link")
    assert.are.equal(base .. "/real/a/b.md", util.normalize(base .. "/link/a/b.md"))
  end)

  it("normalizes git remotes", function()
    assert.are.equal("github.com/sunfinance/app", util.normalize_remote "git@github.com:sunfinance/app.git")
    assert.are.equal("github.com/sunfinance/app", util.normalize_remote "https://github.com/sunfinance/app.git")
    assert.are.equal("github.com/sunfinance/app", util.normalize_remote "ssh://git@github.com:22/sunfinance/app")
  end)

  it("generates sortable ulids", function()
    local a = util.ulid()
    assert.are.equal(26, #a)
    assert.is_truthy(a:match "^[0-9A-HJKMNP-TV-Z]+$")
    assert.are_not.equal(a, util.ulid())
  end)
end)
