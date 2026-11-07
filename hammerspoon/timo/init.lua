-- timo is now tide. This keeps an ~/.hammerspoon/init.lua that still says
-- require("timo") working; change it to require("tide") to drop the note.
print('tide: require("timo") is deprecated; use require("tide")')
return require("tide")
