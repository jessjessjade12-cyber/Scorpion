local T = require("tests.lib.test_helper")
local Nearby = require("scorpion.application.handlers.support.nearby")

local function make_world(candidates, in_range_fn)
  local world = {}
  function world:list_nearby_sessions(center, max_distance)
    return candidates
  end
  function world:in_client_range(center, other)
    return in_range_fn(center, other)
  end
  return world
end

T.test("get_nearby_sessions prefers resolver over accounts lookups", function()
  local center = {
    id = 1,
    connected = true,
    pending_warp = nil,
    character_id = 100,
    map_id = 46,
    invisible = true,
  }
  local visible_other = {
    id = 2,
    connected = true,
    pending_warp = nil,
    character_id = 200,
    map_id = 46,
    invisible = false,
  }
  local off_map = {
    id = 3,
    connected = true,
    pending_warp = nil,
    character_id = 300,
    map_id = 99,
    invisible = false,
  }

  local world = make_world({ center, visible_other, off_map }, function()
    return true
  end)

  local accounts = {
    get_character = function()
      error("accounts:get_character should not be used when resolver is provided")
    end,
  }

  local resolver_calls = 0
  local nearby = Nearby.get_nearby_sessions(world, accounts, center, function(session)
    resolver_calls = resolver_calls + 1
    return {
      id = session.character_id,
      name = "char" .. tostring(session.id),
      level = 1,
      sex = 0,
      hair_style = 1,
      hair_color = 1,
      race = 0,
      admin = 0,
    }
  end)

  T.assert_eq(#nearby, 2)
  T.assert_true(nearby[1].session.invisible == false, "self view should be visible locally")
  T.assert_eq(nearby[1].character.name, "char1")
  T.assert_eq(nearby[2].character.name, "char2")
  T.assert_eq(resolver_calls, 2)
end)

T.test("get_requested_nearby_sessions deduplicates IDs and filters invalid targets", function()
  local center = {
    id = 10,
    connected = true,
    pending_warp = nil,
    character_id = 10,
    map_id = 46,
    invisible = false,
  }
  local visible = {
    id = 11,
    connected = true,
    pending_warp = nil,
    character_id = 11,
    map_id = 46,
    invisible = false,
  }
  local hidden = {
    id = 12,
    connected = true,
    pending_warp = nil,
    character_id = 12,
    map_id = 46,
    invisible = true,
  }
  local world = {
    sessions = {
      [10] = center,
      [11] = visible,
      [12] = hidden,
    },
  }
  function world:in_client_range(observer, other)
    return other.id == 11
  end

  local requested = Nearby.get_requested_nearby_sessions(
    world,
    nil,
    center,
    { 11, 11, 12, 999 },
    function(session)
      return {
        id = session.character_id,
        name = "p" .. tostring(session.id),
      }
    end
  )

  T.assert_eq(#requested, 1)
  T.assert_eq(requested[1].session.id, 11)
  T.assert_eq(requested[1].character.name, "p11")
end)
