local M = {}

function M.append(packet, characters)
  packet:add_int1(#characters)
  packet:add_byte(1)
  packet:add_byte(255)
  for _, character in ipairs(characters) do
    packet:add_break_string(character.name)
    packet:add_int4(character.id)
    packet:add_int1(character.level or 0)
    packet:add_int1(character.sex or 0)
    packet:add_int1(character.hair_style or 1)
    packet:add_int1(character.hair_color or 0)
    packet:add_int1(character.race or 0)
    packet:add_int1(character.admin or 0)
    packet:add_int2(0)
    packet:add_int2(0)
    packet:add_int2(0)
    packet:add_int2(0)
    packet:add_int2(0)
    packet:add_byte(255)
  end
end

return M
