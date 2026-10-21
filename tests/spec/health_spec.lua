local assert = require "luassert"
local h = require "tests.helpers"

describe("health", function()
  local calls, original

  before_each(function()
    h.reset()
    h.setup()
    calls = {}
    original = vim.health
    vim.health = setmetatable({}, {
      __index = function(_, level)
        return function(msg)
          calls[#calls + 1] = { level = level, msg = msg }
        end
      end,
    })
  end)

  after_each(function()
    vim.health = original
  end)

  local function check()
    package.loaded["scholia.health"] = nil
    require("scholia.health").check()
    return vim.tbl_filter(function(c)
      return c.level == "warn" or c.level == "error"
    end, calls)
  end

  it("reports no problems after setup", function()
    assert.are.same({}, check())
  end)

  it("warns about an overridden keymap", function()
    vim.keymap.set("n", "<leader>mj", "<Nop>")
    local problems = check()
    assert.are.equal(1, #problems)
    assert.is_truthy(problems[1].msg:find("<leader>mj", 1, true))
  end)
end)
