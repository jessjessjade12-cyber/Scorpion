local M = {
  cases = {},
}

local function format_value(value)
  if type(value) == "string" then
    return ("%q"):format(value)
  end
  return tostring(value)
end

function M.test(name, fn)
  M.cases[#M.cases + 1] = {
    name = name,
    fn = fn,
  }
end

function M.assert_true(value, message)
  if not value then
    error(message or "expected value to be true")
  end
end

function M.assert_false(value, message)
  if value then
    error(message or "expected value to be false")
  end
end

function M.assert_eq(actual, expected, message)
  if actual ~= expected then
    local detail = ("expected %s, got %s"):format(
      format_value(expected),
      format_value(actual)
    )
    if message then
      detail = message .. " (" .. detail .. ")"
    end
    error(detail)
  end
end

function M.assert_not_nil(value, message)
  if value == nil then
    error(message or "expected value to be non-nil")
  end
end

function M.run()
  local failed = 0

  for _, case in ipairs(M.cases) do
    local ok, err = pcall(case.fn)
    if ok then
      io.write(("[PASS] %s\n"):format(case.name))
    else
      failed = failed + 1
      io.write(("[FAIL] %s\n  %s\n"):format(case.name, tostring(err)))
    end
  end

  io.write(("\nTotal: %d  Failed: %d\n"):format(#M.cases, failed))
  return failed
end

return M
