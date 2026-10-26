-- timo is now tilemo. This keeps an ~/.hammerspoon/init.lua that still says
-- require("timo") working; change it to require("tilemo") to drop the note.
print('tilemo: require("timo") is deprecated; use require("tilemo")')
return require("tilemo")
