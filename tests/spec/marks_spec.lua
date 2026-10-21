local assert = require "luassert"
local h = require "tests.helpers"
local state = require "scholia.state"

local function range(buf, mark)
  return { state.range(buf, mark) }
end

describe("extmark ranges", function()
  local buf, mark

  before_each(function()
    h.reset()
    h.setup()
    local _, file = h.project(h.lines(20))
    vim.cmd.edit(file)
    buf = vim.api.nvim_get_current_buf()
    mark = state.place(buf, 5, 8)
  end)

  it("shifts when lines are inserted above", function()
    vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "a", "b" })
    assert.are.same({ 7, 10 }, range(buf, mark))
  end)

  it("grows when lines are inserted inside", function()
    vim.api.nvim_buf_set_lines(buf, 7, 7, false, { "a", "b" })
    assert.are.same({ 5, 10 }, range(buf, mark))
  end)

  it("grows when a line is opened above the last line", function()
    vim.api.nvim_win_set_cursor(0, { 9, 0 })
    vim.cmd "normal! Onew"
    assert.are.same({ 5, 9 }, range(buf, mark))
  end)

  it("does not grow when lines are inserted below", function()
    vim.api.nvim_buf_set_lines(buf, 9, 9, false, { "a", "b" })
    assert.are.same({ 5, 8 }, range(buf, mark))
  end)

  it("does not grow when a line is opened above the first line", function()
    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    vim.cmd "normal! Onew"
    assert.are.same({ 6, 9 }, range(buf, mark))
  end)

  it("shrinks when lines inside are deleted", function()
    vim.api.nvim_buf_set_lines(buf, 6, 8, false, {})
    assert.are.same({ 5, 6 }, range(buf, mark))
  end)

  it("shrinks when the last line is deleted", function()
    vim.api.nvim_win_set_cursor(0, { 9, 0 })
    vim.cmd "normal! dd"
    assert.are.same({ 5, 7 }, range(buf, mark))
  end)

  it("collapses to one line when the whole range is deleted", function()
    vim.api.nvim_buf_set_lines(buf, 5, 9, false, {})
    assert.are.same({ 5, 5 }, range(buf, mark))
  end)

  it("stays inside the buffer when the range at the end is deleted", function()
    local last = state.place(buf, 17, 19)
    vim.api.nvim_buf_set_lines(buf, 17, 20, false, {})
    assert.are.same({ 16, 16 }, range(buf, last))
  end)
end)
