local WorldScheduler = {}
WorldScheduler.__index = WorldScheduler

function WorldScheduler.new(deps)
  return setmetatable({
    logger = deps.logger,
    next_arena_tick = 0,
    world = deps.world,
  }, WorldScheduler)
end

function WorldScheduler:log(level, message, fields)
  if not self.logger then
    return
  end

  if level == "error" then
    self.logger:error(message, fields)
  elseif level == "warn" then
    self.logger:warn(message, fields)
  else
    self.logger:info(message, fields)
  end
end

function WorldScheduler:tick(now)
  local world = self.world
  if not world then
    return
  end

  local tick_now = tonumber(now) or os.clock()
  if tick_now >= (self.next_arena_tick or 0) then
    self.next_arena_tick = tick_now + 1
    local winner = world:tick_arena()
    if winner then
      self:log("info", "arena round over", {
        winner = winner.account or "unknown",
        kills = winner.arena_kills or 0,
      })
    end

    local runner = world.arena_script_runner
    if runner and runner.tick then
      local ok_tick, tick_err = pcall(runner.tick, runner)
      if not ok_tick then
        self:log("warn", "arena script tick failed", { error = tostring(tick_err) })
      end
    end
  end

  local ok_npc, npc_err = pcall(world.tick_npcs, world, tick_now)
  if not ok_npc then
    self:log("warn", "npc movement tick failed", { error = tostring(npc_err) })
  end
end

return WorldScheduler
