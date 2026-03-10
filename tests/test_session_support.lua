local T = require("tests.lib.test_helper")
local SessionSupport = require("scorpion.application.handlers.support.session_support")

T.test("cache_character_profile stores a minimal profile", function()
  local session = { character_id = 42 }
  local character = {
    id = 42,
    name = "alpha",
    level = 10,
    sex = 1,
    hair_style = 3,
    hair_color = 4,
    race = 2,
    admin = 0,
    map_id = 99, -- should not be copied into profile
  }

  local profile = SessionSupport.cache_character_profile(session, character)
  T.assert_not_nil(profile)
  T.assert_eq(profile.id, 42)
  T.assert_eq(profile.name, "alpha")
  T.assert_eq(profile.level, 10)
  T.assert_eq(profile.map_id, nil)
end)

T.test("cached_character_profile requires matching session.character_id", function()
  local session = { character_id = 10 }
  SessionSupport.cache_character_profile(session, {
    id = 11,
    name = "mismatch",
  })

  local profile = SessionSupport.cached_character_profile(session)
  T.assert_eq(profile, nil)
end)

T.test("clear_character_profile removes cached profile", function()
  local session = { character_id = 7 }
  SessionSupport.cache_character_profile(session, {
    id = 7,
    name = "cached",
  })

  T.assert_not_nil(SessionSupport.cached_character_profile(session))
  SessionSupport.clear_character_profile(session)
  T.assert_eq(SessionSupport.cached_character_profile(session), nil)
end)

T.test("find_session_by_character_name uses resolver callback", function()
  local s1 = { id = 1, connected = true, character_id = 11, account = "a" }
  local s2 = { id = 2, connected = true, character_id = 22, account = "b" }
  local world = {
    sessions = {
      [1] = s1,
      [2] = s2,
    },
  }

  local calls = 0
  local found_session, found_character = SessionSupport.find_session_by_character_name(
    world,
    nil,
    "beta",
    function(session)
      calls = calls + 1
      if session.id == 1 then
        return { id = 11, name = "alpha" }
      end
      return { id = 22, name = "beta" }
    end
  )

  T.assert_eq(calls, 2)
  T.assert_eq(found_session, s2)
  T.assert_eq(found_character.name, "beta")
end)
