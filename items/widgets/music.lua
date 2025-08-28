-- Apple Music widget with artwork + inline controls
-- ~/.config/sketchybar/items/widgets/music.lua
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

local COVER_SIZE = 26 -- px, matches your chip height
local COVER_SCALE = 0.04 -- tune: 0.15–0.25 looks good
local COVER_RADIUS = 5
local TEXT_W = 110 -- tune to fit your bar

-- put widget on the right (set false for left)
local SHOW_ON_RIGHT = true
local function side()
	return SHOW_ON_RIGHT and "right" or "left"
end

-- temp artwork file
local ART_PATH = "/tmp/sketchybar_music_art.jpg"

-- --- items ---------------------------------------------------------------
local btn_next = sbar.add("item", "widgets.music.next", {
	position = side(),
	icon = { string = icons.media.forward, font = { size = 12.0 } },
	label = { drawing = false },
	padding_left = 2,
	padding_right = 0,
})
local btn_pp = sbar.add("item", "widgets.music.pp", {
	position = side(),
	icon = { string = icons.media.play_pause, font = { size = 12.0 } },
	label = { drawing = false },
	padding_left = 2,
	padding_right = 2,
})

local btn_prev = sbar.add("item", "widgets.music.prev", {
	position = side(),
	icon = { string = icons.media.back, font = { size = 12.0 } },
	label = { drawing = false },
	padding_left = 4,
	padding_right = 2,
})
-- ARTIST (top line) — overlay item (doesn't push), but label reserves TEXT_W
local artist = sbar.add("item", "widgets.music.artist", {
	position = side(),
	width = 0, -- overlay
	padding_left = -5,
	padding_right = 0,
	y_offset = -6, -- top
	icon = { drawing = false },
	label = {
		width = TEXT_W, -- << fixed pixel width
		align = "left",
		font = { style = settings.font.style_map["Semibold"], size = 11 },
		color = colors.grey,
		max_chars = 999, -- keep if you like
	},
})

-- TITLE (bottom line) — real block that pushes controls
local title = sbar.add("item", "widgets.music.title", {
	position = side(),
	width = TEXT_W, -- << block width matches label width
	padding_left = -5,
	padding_right = 6,
	y_offset = 6, -- bottom
	icon = { drawing = false },
	label = {
		width = TEXT_W, -- << same pixel width
		align = "left",
		font = { style = settings.font.style_map["Bold"], size = 13 },
		color = colors.white,
		max_chars = 999,
	},
})
-- square cover
local cover = sbar.add("item", "widgets.music.cover", {
	position = side(),
	background = {
		image = { string = ART_PATH, scale = COVER_SCALE, corner_radius = COVER_RADIUS },
		color = colors.transparent,
		height = COVER_SIZE,
	},
	icon = { drawing = false },
	label = { drawing = false },
	padding_left = 0,
	padding_right = 6,
	updates = true,
})

-- inline controls

-- chip bracket background around (title, artist, controls)
sbar.add(
	"bracket",
	"widgets.music.bracket",
	{ btn_prev.name, btn_pp.name, btn_next.name, artist.name, title.name, cover.name },
	{
		background = {
			color = colors.bg1,
			border_color = colors.black,
			border_width = 1,
			height = 26,
		},
	}
)
sbar.add("item", "widgets.music.padding", {
	position = "right",
	width = settings.group_paddings,
})
-- --- actions -------------------------------------------------------------

btn_prev:subscribe("mouse.clicked", function()
	sbar.exec([[osascript -e 'tell application "Music" to previous track']])
end)
btn_pp:subscribe("mouse.clicked", function()
	sbar.exec([[osascript -e 'tell application "Music" to playpause']])
end)
btn_next:subscribe("mouse.clicked", function()
	sbar.exec([[osascript -e 'tell application "Music" to next track']])
end)

-- open Music on click of text/art
for _, it in ipairs({ cover, title, artist }) do
	it:subscribe("mouse.clicked", function()
		sbar.exec([[open -a "Music"]])
	end)
end

-- --- AppleScript helpers -------------------------------------------------

-- writes current artwork to ART_PATH (returns "ok" / "")
local APPLESCRIPT_ART = ([[
if application "Music" is running then
  tell application "Music"
    try
      if (player state as string) is "stopped" then return ""
      set artcount to count of artworks of current track
      if artcount is 0 then return ""
      set outFile to POSIX file "%s"
      set d to data of artwork 1 of current track
      try
        set fh to open for access outFile with write permission
        set eof of fh to 0
        write d to fh
        close access fh
      on error
        try
          close access outFile
        end try
        return ""
      end try
      return "ok"
    on error
      return ""
    end try
  end tell
end if
return ""
]]):format(ART_PATH)

-- returns 3 lines: title, artist, player_state  ("" if stopped/not running)
local APPLESCRIPT_INFO = [[
if application "Music" is running then
  tell application "Music"
    set ps to (player state as string)
    if ps is "stopped" then return ""
    try
      set t to name of current track
      set ar to artist of current track
      return t & linefeed & ar & linefeed & ps
    on error
      return ""
    end try
  end tell
end if
return ""
]]

-- --- refresh loop --------------------------------------------------------

local function show(on)
	local draw = on and "on" or "off"
	cover:set({ drawing = draw })
	title:set({ drawing = draw })
	artist:set({ drawing = draw })
	btn_prev:set({ drawing = draw })
	btn_pp:set({ drawing = draw })
	btn_next:set({ drawing = draw })
end

local function refresh()
	-- get title/artist/state
	sbar.exec("osascript -e '" .. APPLESCRIPT_INFO:gsub("'", [["]]) .. "'", function(meta)
		if not meta or meta == "" then
			show(false)
			return
		end

		local t, ar, st
		local i = 0
		for line in string.gmatch(meta, "[^\r\n]+") do
			i = i + 1
			if i == 1 then
				t = line
			elseif i == 2 then
				ar = line
			elseif i == 3 then
				st = line
			end
		end
		if not t or not ar or not st then
			show(false)
			return
		end

		-- update texts
		title:set({ label = { string = (t ~= "" and t or "—") } })
		artist:set({ label = { string = (ar ~= "" and ar or "—") } })

		-- update play/pause glyph (optional: pick your glyphs)
		-- if st == "playing" then btn_pp:set({ icon = { string = "􀊆" } }) else btn_pp:set({ icon = { string = "􀊄" } }) end

		-- fetch artwork
		sbar.exec("osascript -e '" .. APPLESCRIPT_ART:gsub("'", [["]]) .. "'", function(ok)
			if ok and ok:match("ok") then
				cover:set({
					background = {
						height = COVER_SIZE,
						image = { string = ART_PATH, scale = COVER_SCALE, corner_radius = COVER_RADIUS },
					},
				})
			else
				-- fallback: no art → just hide cover background
				cover:set({
					background = {
						height = COVER_SIZE,
						color = colors.transparent,
						image = { string = "", scale = COVER_SCALE, corner_radius = COVER_RADIUS },
					},
				})
			end
			show(true)
		end)
	end)
end

-- events + gentle polling
cover:subscribe("routine", refresh)
cover:subscribe("system_woke", refresh)
cover:subscribe("media_change", refresh)

local function loop()
	refresh()
	sbar.delay(2, loop) -- snappy but light
end
loop()

return { refresh = refresh }
