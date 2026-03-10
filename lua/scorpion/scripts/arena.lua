local M = {}

-- Optional hook called whenever a player is eliminated in arena combat.
-- Signature: on_arena_eliminate(api, ctx)
--  - api.temporarily_disguise_as_npc(session, { npc_id?, seconds?, ... })
--  - api.temporarily_override_appearance(session, { seconds?, hair_style?, ... })
--  - api.random_npc_id([list])
--  - api.log(level, message, fields)
--  - api.config()
--  - api.clear_disguise(session)
--
-- Note: character packets only support player appearance fields.
-- The runner maps npc_id -> safe player hair/skin/sex values.
--
-- ctx fields:
--  - victim (session table)
--  - killer (session table or nil)
--  - victim_id, killer_id, direction
--  - arena_players (session array of current round participants)
--  - victim_origin { map_id, x, y, direction }
function M.on_arena_eliminate(api, ctx)
  local victim = ctx and ctx.victim
  if not victim then
    return
  end

  local cfg = api.config() or {}

  if cfg.mass_bald_enabled == true then
    local seconds = math.max(1, math.floor(tonumber(cfg.mass_bald_seconds) or 20))
    local players = (ctx and ctx.arena_players) or {}
    local affected = 0

    for _, session in ipairs(players) do
      if session and session.connected then
        api.temporarily_override_appearance(session, {
          seconds = seconds,
          hair_style = 0,
        })
        affected = affected + 1
      end
    end

    if affected == 0 then
      api.temporarily_override_appearance(victim, {
        seconds = seconds,
        hair_style = 0,
      })
      affected = 1
    end

    api.log("info", "arena mass bald applied", {
      affected = affected,
      killer_id = ctx and ctx.killer_id or 0,
      seconds = seconds,
      victim_id = victim.id or 0,
    })
    return
  end

  local npc_id = api.random_npc_id(cfg.loser_npc_ids)
  local disguise = api.temporarily_disguise_as_npc(victim, {
    npc_id = npc_id,
    seconds = cfg.loser_duration_seconds or 3,
    -- These optional fields can be customized for style:
    -- hair_style = 0,
    -- hair_color = 0,
    -- sex = 0,
    -- name = "loser npc",
  })

  api.log("info", "arena loser disguise applied", {
    victim_id = victim.id or 0,
    killer_id = ctx and ctx.killer_id or 0,
    npc_id = disguise and disguise.npc_id or 0,
    seconds = cfg.loser_duration_seconds or 3,
  })
end

return M
