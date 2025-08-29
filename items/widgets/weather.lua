-- ~/.config/sketchybar/items/widgets/weather.lua
local colors = require("colors")
local settings = require("settings")

-- === Compact chip (icon + temp) ===
local weather = sbar.add("item", "widgets.weather", {
	position = "right",
	icon = { string = "􀇃" }, -- default: cloud.sun
	label = {
		string = "…°",
		font = { style = settings.font.style_map["Bold"], size = 12 },
	},
	padding_left = 6,
	padding_right = 6,
	update_freq = 600, -- chip refresh cadence (10 min)
})

-- === Popup bracket container ===
local weather_bracket = sbar.add("bracket", "widgets.weather.bracket", { weather.name }, {
	background = { color = colors.bg1 },
	popup = { align = "center" },
})

-- Helper: add a popup row with fixed left/right columns
local function add_row(name, left, right, total_w, left_w, right_w)
	total_w = total_w or 260
	left_w = left_w or 120
	right_w = right_w or 140
	return sbar.add("item", name, {
		position = "popup." .. weather_bracket.name,
		icon = { string = left, align = "left", width = left_w },
		label = { string = right, align = "right", width = right_w },
		width = total_w,
	})
end

-- === Rows (with header sized to avoid overlap) ===
-- Header: left = city (wide), right = tempC (narrow), fixed widths so they never collide
local header = sbar.add("item", "widgets.weather.row.header", {
	position = "popup." .. weather_bracket.name,
	icon = { align = "left", width = 170, string = "—" }, -- city
	label = { align = "right", width = 80, string = "—", max_chars = 6 }, -- e.g., "23°C"
	width = 250,
})

-- Conditions: full-width single line (so we can scroll it smoothly)
local cond = sbar.add("item", "widgets.weather.row.cond", {
	position = "popup." .. weather_bracket.name,
	icon = { drawing = false },
	label = {
		string = "—",
		align = "left",
		width = 250, -- full width
		max_chars = 999, -- we’ll control visible window via marquee
	},
	width = 250,
})

local feels = add_row("widgets.weather.row.feels", "Feels like", "—")
local humidity = add_row("widgets.weather.row.hum", "Humidity", "—")
local wind = add_row("widgets.weather.row.wind", "Wind", "—")
local sep = sbar.add("item", "widgets.weather.row.sep", {
	position = "popup." .. weather_bracket.name,
	background = { height = 1, color = colors.bg2 },
	width = 250,
})
local h1 = add_row("widgets.weather.row.h1", "Next 1h", "—")
local h3 = add_row("widgets.weather.row.h3", "Next 3h", "—")
local h6 = add_row("widgets.weather.row.h6", "Next 6h", "—")

-- === CHIP REFRESH (icon + temp) — fast, simple endpoint ===
-- Change "Maastricht" to "" for auto-location, or to your preferred city.
local function refresh_chip()
	sbar.exec([[curl -s 'https://wttr.in/Maastricht?format=%t+%C' | tr -d '\n']], function(out)
		if not out or out == "" then
			return
		end
		local temp, condition = out:match("([%+%-]?%d+°C)%s+(.+)")
		if not temp or not condition then
			return
		end

		local c = condition:lower()
		local icon = "􀇃" -- cloud.sun default
		if c:find("storm") or c:find("thunder") then
			icon = "􀇏" -- cloud.bolt.rain
		elseif c:find("rain") or c:find("drizzle") then
			icon = "􀇈" -- cloud.rain
		elseif c:find("snow") or c:find("sleet") or c:find("hail") then
			icon = "􀇇" -- cloud.snow
		elseif c:find("clear") or c:find("sun") then
			icon = "􀆮" -- sun.max
		elseif c:find("cloud") or c:find("overcast") then
			icon = "􀇂" -- cloud
		end

		weather:set({
			icon = { string = icon },
			label = { string = temp },
		})
	end)
end

-- === POPUP REFRESH (details) — uses jq to parse JSON cleanly ===
local function refresh_popup()
	local url = "https://wttr.in/Maastricht?format=j1" -- set to "?format=j1" for auto-location
	local cmd = [[/bin/bash -lc '
    curl -fsSL "]] .. url .. [[" | jq -r "
      def h(i): .weather[0].hourly[i] | \"\\(.tempC)°C, \\(.weatherDesc[0].value)\";
      [
        .nearest_area[0].areaName[0].value,        # city only
        .current_condition[0].temp_C,
        .current_condition[0].weatherDesc[0].value,# condition (may be long)
        .current_condition[0].FeelsLikeC,
        .current_condition[0].humidity,
        (.current_condition[0].windspeedKmph|tostring + \" km/h\"),
        h(1), h(3), h(6)
      ] | .[]
    "
  ']]

	sbar.exec(cmd, function(out)
		if not out or out == "" then
			return
		end
		local lines = {}
		for line in string.gmatch(out, "[^\r\n]+") do
			table.insert(lines, line)
		end
		if #lines < 8 then
			return
		end

		local city, tempC, feelC, humP, windStr, n1, n3, n6 =
			lines[1], lines[2], lines[3], lines[4], lines[5], lines[6], lines[7], lines[8]

		header:set({
			icon = { string = city },
			label = { string = tostring(tempC) .. "°C" },
		})
		-- Start/stop marquee based on popup visibility
		feels:set({ label = { string = tostring(feelC) .. "°C" } })
		humidity:set({ label = { string = tostring(humP) .. "%" } })
		wind:set({ label = { string = windStr } })
		h1:set({ label = { string = n1 } })
		h3:set({ label = { string = n3 } })
		h6:set({ label = { string = n6 } })
	end)
end

-- === Click behavior ===
weather:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "right" then
		sbar.exec([[open -a "Weather"]]) -- right-click: open app
	else
		-- toggle popup and start/stop marquee accordingly
		sbar.set("widgets.weather.bracket", { popup = { drawing = "toggle" } })
		sbar.delay(0.05, function()
			local on = (sbar.query("widgets.weather.bracket").popup.drawing == "on")
			if on then
				refresh_popup() -- refresh and the marquee will start inside
			end
		end)
	end
end)

-- === Periodic updates ===
weather:subscribe({ "routine", "system_woke" }, function()
	refresh_chip()
	-- light periodic details refresh; marquee will kick in only when popup is open
	sbar.delay(300, refresh_popup) -- ~5 min
end)

-- Spacing after widget
sbar.add("item", { position = "right", width = settings.group_paddings })

-- Initial paint
refresh_chip()
