local colors = require("colors")
local settings = require("settings")

-- Create the weather item
local weather = sbar.add("item", "widgets.weather", {
	position = "right",
	icon = {
		string = "􀇃", -- SF Symbol cloud.sun.fill (replace with NerdFont if you prefer)
		font = { size = 16.0 },
		color = colors.blue,
		padding_left = 6,
		padding_right = 3,
	},
	label = {
		string = "??°C",
		font = { family = settings.font.numbers, size = 12.0 },
		color = colors.white,
		padding_left = 2,
		padding_right = 8,
	},
	update_freq = 900, -- 15 min
	popup = {
		align = "center",
		background = { border_width = 2, corner_radius = 6, color = colors.bg1 },
	},
})
sbar.add("bracket", "widgets.weather.bracket", { weather.name }, {
	background = {
		color = colors.bg1,
		border_color = colors.black,
		height = 26,
	},
})

-- Add spacing to the right
sbar.add("item", "widgets.weather.padding", {
	position = "right",
	width = settings.group_paddings,
})

-- Helper to update weather
local function update_weather()
	sbar.exec("curl -s 'wttr.in/Maastricht?format=%t+%C' | tr -d '\n'", function(out)
		if out and out ~= "" then
			-- Example: "+20°C Sunny"
			local temp, cond = out:match("([%+%-]?%d+°C)%s+(.+)")
			if temp and cond then
				local icon = "􀇃" -- default sun/cloud
				cond = cond:lower()

				if cond:find("rain") then
					icon = "􀇈" -- cloud.rain
				elseif cond:find("snow") then
					icon = "􀇇" -- cloud.snow
				elseif cond:find("clear") or cond:find("sun") then
					icon = "􀆮" -- sun.max
				elseif cond:find("cloud") then
					icon = "􀇂" -- cloud
				elseif cond:find("storm") then
					icon = "􀇏" -- cloud.bolt.rain
				end

				weather:set({
					icon = { string = icon },
					label = { string = temp },
					popup = { drawing = false },
				})
			end
		end
	end)
end

-- Subscribe updates
weather:subscribe("routine", update_weather)
weather:subscribe("system_woke", update_weather)

-- First run
update_weather()
