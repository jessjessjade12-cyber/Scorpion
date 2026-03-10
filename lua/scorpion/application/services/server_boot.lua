local RequiredPubKeys = { "ecf", "eif", "enf", "esf" }

local M = {}

local function missing_required_pub(world)
  local client = ((world.pub or {}).client or {})
  for _, key in ipairs(RequiredPubKeys) do
    if not client[key] then
      return true
    end
  end
  return false
end

function M.validate(settings, world)
  local spawn = ((settings.new_character or {}).spawn_map) or 5
  local arena = settings.arena or {}

  if arena.only then
    if not world:has_map(spawn) then
      return nil, ("arena map %d missing"):format(spawn)
    end

    if arena.enforce_pub and missing_required_pub(world) then
      return nil, "required pub files missing (ECF/EIF/ENF/ESF)"
    end
  end

  return true
end

return M
