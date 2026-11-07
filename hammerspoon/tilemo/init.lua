-- tilemo is now tide. This keeps an ~/.hammerspoon/init.lua that still says
-- require("tilemo") working; change it to require("tide") to drop the note.
print('tide: require("tilemo") is deprecated; use require("tide")')
return require("tide")
