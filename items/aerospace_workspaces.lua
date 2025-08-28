-- ~/.config/sketchybar/items/aerospace_workspaces.lua
local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

-- Event emitted by AeroSpace (see TOML below)
sbar.add("event", "aerospace_workspace_change")

-- ==== Order you want on the bar (pre-create in this order) ====
local ORDER = {
	-- Monitor 1
	{ "1", "2", "3", "4", "5", "6", "7", "8", "9" },
	-- Monitor 2
	{ "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
	-- Monitor 3
	{ "A", "S", "D", "F", "G", "Z", "X", "C", "V", "B" },
}

-- Visual style
local CHIP_BG = colors.bg1
local CHIP_BORDER = colors.black
local CHIP_HEIGHT = 26
local BRACKET_BORDER = colors.bg2
local ACTIVE_ICON_HL = colors.red
local ACTIVE_LBL_HL = colors.white

-- Storage
local items = {} -- ws -> { item, bracket }
local separators = {} -- index -> separator item
local current_focused = ""

-- Helpers
local function ensure_item(ws)
	if items[ws] then
		return items[ws]
	end

	local item = sbar.add("item", "aws." .. ws, {
		position = "left",
		icon = {
			font = { family = settings.font.numbers },
			string = ws,
			padding_left = 15,
			padding_right = 8,
			color = colors.white,
			highlight_color = ACTIVE_ICON_HL,
		},
		label = {
			padding_right = 20,
			color = colors.grey,
			highlight_color = ACTIVE_LBL_HL,
			font = "sketchybar-app-font:Regular:16.0",
			y_offset = -1,
		},
		padding_right = 1,
		padding_left = 1,
		background = {
			color = CHIP_BG,
			border_width = 1,
			height = CHIP_HEIGHT,
			border_color = CHIP_BORDER,
		},
		click_script = "aerospace workspace " .. ws, -- left click focuses
		drawing = "off", -- start hidden
	})

	-- Double-border bracket
	local bracket = sbar.add("bracket", { item.name }, {
		background = {
			color = colors.transparent,
			border_color = BRACKET_BORDER,
			height = CHIP_HEIGHT + 2,
			border_width = 2,
		},
		drawing = "off",
	})

	-- Right click: send focused window to this workspace
	item:subscribe("mouse.clicked", function(env)
		if env.BUTTON == "right" then
			sbar.exec("aerospace move-node-to-workspace " .. ws)
		end
	end)

	items[ws] = { item = item, bracket = bracket }
	return items[ws]
end

-- Create separators between monitor groups
local function create_separators()
	separators[1] = sbar.add("item", "aws.sep.1", {
		position = "left",
		width = settings.group_paddings * 2,
		drawing = "off",
	})
	separators[2] = sbar.add("item", "aws.sep.2", {
		position = "left",
		width = settings.group_paddings * 2,
		drawing = "off",
	})
end

-- Pre-create all items and per-workspace paddings (keeps order stable)
local function create_all_items()
	for _, monitor_workspaces in ipairs(ORDER) do
		for _, ws in ipairs(monitor_workspaces) do
			ensure_item(ws)
			sbar.add("item", "aws.pad." .. ws, {
				position = "left",
				width = settings.group_paddings,
				drawing = "off",
			})
		end
	end
	create_separators()
end

local function set_item_visible(ws, visible)
	local rec = items[ws]
	if not rec then
		return
	end
	rec.item:set({ drawing = visible and "on" or "off" })
	rec.bracket:set({ drawing = visible and "on" or "off" })
	sbar.set("aws.pad." .. ws, { drawing = visible and "on" or "off" })
end

local function set_separator_visible(sep_idx, visible)
	if separators[sep_idx] then
		separators[sep_idx]:set({ drawing = visible and "on" or "off" })
	end
end

local function update_workspace_display(ws, focused)
	local rec = items[ws]
	if not rec then
		return
	end
	local is_focused = (ws == focused)

	sbar.exec(string.format('aerospace list-windows --workspace %s --format "%%{app-name}"', ws), function(out)
		local seen = {}
		local icon_line = ""
		local has_apps = false

		if out and out ~= "" then
			for app in string.gmatch(out, "[^\r\n]+") do
				app = app:gsub("^%s+", ""):gsub("%s+$", "")
				if app ~= "" and not seen[app] then
					seen[app] = true
					has_apps = true
					local icon = app_icons[app] or app_icons["Default"] or "?"
					icon_line = icon_line .. icon
				end
			end
		end

		if not has_apps then
			icon_line = " —"
		end

		rec.item:set({
			icon = { highlight = is_focused },
			label = { string = icon_line, highlight = is_focused },
			background = { border_color = is_focused and CHIP_BORDER or BRACKET_BORDER },
		})

		rec.bracket:set({
			background = { border_color = is_focused and colors.grey or BRACKET_BORDER },
		})
	end)
end

-- Main update
-- Build a quick lookup for ORDER so we ignore unknown ids
local ORDER_FLAT, ORDER_SET = {}, {}
for _, group in ipairs(ORDER) do
	for _, ws in ipairs(group) do
		table.insert(ORDER_FLAT, ws)
		ORDER_SET[ws] = true
	end
end

local function update_all()
	-- 1) Get focused workspace
	sbar.exec("aerospace list-workspaces --focused", function(focused_out)
		local focused = (focused_out or ""):gsub("%s+", "")
		current_focused = focused

		-- 2) Get ALL workspaces, then filter to non-empty via list-windows
		sbar.exec("aerospace list-workspaces --all", function(all_out)
			local all_list = {}
			for ws in string.gmatch(all_out or "", "[^\r\n%s]+") do
				if ws ~= "" and ORDER_SET[ws] then
					table.insert(all_list, ws)
				end
			end

			-- If nothing came back (edge case), just use ORDER
			if #all_list == 0 then
				for _, ws in ipairs(ORDER_FLAT) do
					table.insert(all_list, ws)
				end
			end

			local used = {} -- ws -> true (has windows or is focused)
			local pending = #all_list -- async counter

			local function finish()
				-- Track visibility per “monitor group” for separators
				local monitor_has_visible = {}

				for gi, group in ipairs(ORDER) do
					local group_visible = false
					for _, ws in ipairs(group) do
						local show = used[ws] or (ws == focused)
						set_item_visible(ws, show)
						if show then
							group_visible = true
							update_workspace_display(ws, focused)
						end
					end
					monitor_has_visible[gi] = group_visible
				end

				-- Separators between groups (1|2 and 2|3)
				set_separator_visible(1, monitor_has_visible[1] and monitor_has_visible[2])
				set_separator_visible(2, monitor_has_visible[2] and monitor_has_visible[3])
			end

			if pending == 0 then
				-- No workspaces? Still render focused, if any.
				used[focused] = (focused ~= "")
				finish()
				return
			end

			for _, ws in ipairs(all_list) do
				sbar.exec("aerospace list-windows --workspace " .. ws, function(win_out)
					if (win_out and win_out:match("%S")) or (ws == focused and focused ~= "") then
						used[ws] = true
					end
					pending = pending - 1
					if pending == 0 then
						finish()
					end
				end)
			end
		end)
	end)
end

-- Init
create_all_items()

-- Observer: react to AeroSpace trigger
local observer = sbar.add("item", "aws.observer", { drawing = "off", updates = true })
observer:subscribe("aerospace_workspace_change", function(env)
	if env.FOCUSED_WORKSPACE then
		current_focused = env.FOCUSED_WORKSPACE
	end
	update_all()
end)

-- Periodic refresh to catch window changes (no yabai events needed)
local function delayed_update()
	update_all()
	sbar.delay(5, delayed_update) -- refresh every 5s (adjust if you like)
end

-- First paint
update_all()
delayed_update()
