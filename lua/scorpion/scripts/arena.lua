local M = {}

-- Arena script hooks. Implement any or all of the following:

-- Note: players cannot be turned into true NPC entities at the protocol type level.
-- Current workaround for loser disguise is:
--   1) hide the player entity
--   2) spawn/move a runtime NPC proxy on top of that player
-- Hair/non-hair avatar packet rules still apply for non-proxy appearance overrides.

function M.on_arena_eliminate(api, ctx)
  local victim = ctx and ctx.victim
  if not victim then
    return
  end

  local cfg = api.config() or {}

  -- Mass bald intentionally disabled for now.
  -- Arena elimination always applies loser disguise.
  local npc_id = api.random_npc_id(cfg.loser_npc_ids)
  local disguise = api.temporarily_disguise_as_npc(victim, {
    npc_id = npc_id,
    seconds = cfg.loser_duration_seconds or 60,
  })

  api.log("info", "arena loser disguise applied", {
    victim_id = victim.id or 0,
    killer_id = ctx and ctx.killer_id or 0,
    npc_id = disguise and disguise.npc_id or 0,
    seconds = cfg.loser_duration_seconds or 60,
  })
end

function M.on_arena_end(api, ctx)
  local cfg = api.config() or {}
  local winner_reward = math.floor(tonumber(cfg.winner_gold_reward) or 500)
  local loser_penalty = math.floor(tonumber(cfg.loser_gold_penalty) or 100)

  local winner = ctx and ctx.winner
  local loser = ctx and ctx.last_victim

  local winner_after = nil
  local winner_delta = 0
  if winner and winner_reward ~= 0 then
    winner_after, winner_delta = api.add_gold(winner, winner_reward)
  end

  local loser_after = nil
  local loser_delta = 0
  if loser and loser_penalty ~= 0 then
    loser_after, loser_delta = api.add_gold(loser, -loser_penalty)
  end

  api.log("info", "arena round payout applied", {
    winner_id = winner and winner.id or 0,
    winner_gold_after = winner_after or 0,
    winner_gold_delta = winner_delta,
    loser_id = loser and loser.id or 0,
    loser_gold_after = loser_after or 0,
    loser_gold_delta = loser_delta,
    winner_reward = winner_reward,
    loser_penalty = loser_penalty,
  })
end

return M
