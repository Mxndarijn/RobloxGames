local serde = require("@lune/serde")

local Config = require("../../src/shared/Config")
local out = {}
for key, def in Config.EXCLUSIVE_SHOP.products do
	table.insert(out, { key = key, robux = def.robux, grant = def.grant })
end
print(serde.encode("json", { products = out, seats = Config.PET_SEATS, skins = Config.PLOT_SKINS, bases = Config.PLOT_BASES, shop = { trails = Config.EXCLUSIVE_SHOP.trails, batSkins = Config.EXCLUSIVE_SHOP.batSkins, fanfares = Config.EXCLUSIVE_SHOP.fanfares, lockStyles = Config.EXCLUSIVE_SHOP.lockStyles, hats = Config.EXCLUSIVE_SHOP.hats } }))
