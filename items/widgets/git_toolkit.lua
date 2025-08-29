-- Git Streak Toolkit - Fixed (anchor to real bracket name + small cleanups)
local colors = require("colors")
local settings = require("settings")

local TOOL_PREFIX = "widgets.git"
local SCAN_SCRIPT = os.getenv("HOME") .. "/.config/sketchybar/helpers/git_toolkit/git_scan.sh"
local MAX_GRAPH = tonumber(os.getenv("GIT_WIDGET_GRAPH_LINES") or "12")

-- CHIP
local chip = sbar.add("item", TOOL_PREFIX .. ".chip", {
	position = "right",
	icon = { string = "󰊤 ", font = { size = 14 } },
	label = { string = "Git", font = { style = settings.font.style_map["Bold"], size = 12 } },
	padding_left = 8,
	padding_right = 8,
	update_freq = 180,
	background = { color = colors.bg1, border_width = 1, border_color = colors.black, height = 26 },
})

-- BRACKET (keep handle!)
local br = sbar.add("bracket", TOOL_PREFIX .. ".br", { chip.name }, {
	background = { color = colors.transparent, height = 28, border_width = 2, border_color = colors.bg2 },
	popup = { align = "center" },
})

-- STATE
local state = {
	rows = {}, -- created item names to clean up
	rows_index = {}, -- set of created names
	repo_items = {}, -- key -> { row = item }
	scan_in_flight = false,
	popup_open = false,
}

-- UTILS
local function split_lines(s)
	local t = {}
	for line in string.gmatch(s or "", "[^\r\n]+") do
		t[#t + 1] = line
	end
	return t
end

local function escape_for_bash_double(s)
	return (s or ""):gsub('"', '\\"')
end

local function track(name)
	if not state.rows_index[name] then
		state.rows_index[name] = true
		table.insert(state.rows, name)
	end
end

local function clear_rows()
	for _, name in ipairs(state.rows) do
		sbar.remove(name)
	end
	state.rows, state.rows_index, state.repo_items = {}, {}, {}
end

-- Open in iTerm / iTerm2 (try both)
local function open_in_terminal(path)
	local osa = ([[if application "iTerm" is running or application "iTerm2" is running then
  try
    tell application "iTerm"
      activate
      if (count of windows) = 0 then create window with default profile
      tell current window
        create tab with default profile
        tell current session to write text "cd %s && clear"
      end tell
    end tell
  on error
    tell application "iTerm2"
      activate
      if (count of windows) = 0 then create window with default profile
      tell current window
        create tab with default profile
        tell current session to write text "cd %s && clear"
      end tell
    end tell
  end try
else
  tell application "iTerm"
    activate
    if (count of windows) = 0 then create window with default profile
    tell current window
      create tab with default profile
      tell current session to write text "cd %s && clear"
    end tell
  end tell
end if]]):format(path, path, path)
	sbar.exec('/usr/bin/osascript -e "' .. escape_for_bash_double(osa) .. '"')
end

-- DETAIL POPUP
local function build_detail_popup(key, rec)
	local detail_name = ("%s.detail.%s"):format(TOOL_PREFIX, key)
	sbar.remove(detail_name)

	local detail = sbar.add("item", detail_name, {
		position = "popup." .. state.repo_items[key].row.name,
		icon = { drawing = false },
		label = { string = "Loading…", align = "left", font = "SF Mono:Regular:11.0", max_chars = 999 },
		width = 500,
	})
	track(detail_name)

	local cmd = ([=[/bin/bash -lc '
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
cd "%s" 2>/dev/null || { echo "(cannot cd)"; exit 0; }
echo "%s  (%s)"
echo "last commit: %s    dirty: %s    ahead/behind: %s/%s"
echo "────────────────────────────────────────────────────────────"
git --no-pager log --graph --decorate --oneline -n %d 2>/dev/null || echo "(no commits)"
echo ""
if command -v gh >/dev/null 2>&1 && [ "%s" != "-" ]; then
  echo "PR status (%s):"
  gh pr status -R "%s" 2>/dev/null | sed -e "s/\x1b\[[0-9;]*m//g"
else
  echo "(gh not found or remote not github)"
fi
' ]=]):format(
		escape_for_bash_double(rec.path or ""),
		escape_for_bash_double(rec.name or ""),
		escape_for_bash_double(rec.branch or ""),
		escape_for_bash_double(rec.last or "-"),
		(rec.dirty == "1") and "yes" or "no",
		escape_for_bash_double(rec.ahead or "0"),
		escape_for_bash_double(rec.behind or "0"),
		tonumber(MAX_GRAPH) or 12,
		escape_for_bash_double(rec.slug or "-"),
		escape_for_bash_double(rec.slug or "-"),
		escape_for_bash_double(rec.slug or "-")
	)

	sbar.exec(cmd, function(out)
		detail:set({ label = { string = out or "(no details)" } })
	end)
end

-- ROWS
local function create_repo_row(rec)
	local key = rec.name
	local row_name = ("%s.row.%s"):format(TOOL_PREFIX, key)
	if state.rows_index[row_name] then
		return
	end

	local row = sbar.add("item", row_name, {
		position = "popup." .. br.name, -- <— use the REAL bracket name
		icon = { string = rec.branch, align = "left", width = 140, color = colors.white },
		label = { string = "—", align = "right", width = 340, font = { style = settings.font.style_map["Regular"] } },
		width = 480,
		padding_left = 6,
		padding_right = 6,
		background = { color = colors.bg1 },
	})
	track(row_name)

	row:subscribe("mouse.clicked", function(env)
		if env.BUTTON == "right" then
			local dn = row_name .. ".detail"
			local q = sbar.query(dn)
			if q and q.drawing == "on" then
				sbar.set(dn, { drawing = "off" })
			else
				sbar.remove(dn)
				build_detail_popup(key, rec)
			end
		else
			open_in_terminal(rec.path)
		end
	end)

	-- thin separator
	local sep_name = row_name .. ".sep"
	sbar.remove(sep_name)
	sbar.add("item", sep_name, {
		position = "popup." .. row.name,
		background = { height = 1, color = colors.bg2 },
		width = 480,
	})
	track(sep_name)

	state.repo_items[key] = { row = row }
end

local function update_repo_row(rec)
	local key = rec.name
	local row = state.repo_items[key] and state.repo_items[key].row
	if not row then
		return
	end

	local dirty = rec.dirty == "1"
	local ahead = tonumber(rec.ahead or "0") or 0
	local behind = tonumber(rec.behind or "0") or 0

	local bits = {}
	if dirty then
		table.insert(bits, "● dirty")
	end
	if ahead > 0 then
		table.insert(bits, "↑" .. ahead)
	end
	if behind > 0 then
		table.insert(bits, "↓" .. behind)
	end
	table.insert(bits, rec.last)
	local status = table.concat(bits, "  ·  ")

	row:set({
		icon = { string = rec.branch, color = dirty and colors.orange or colors.white },
		label = {
			string = rec.name .. "  —  " .. status,
			color = (ahead > 0 or behind > 0) and colors.yellow or (dirty and colors.orange or colors.grey),
		},
	})
end

local function ensure_repo_row(rec)
	create_repo_row(rec)
	update_repo_row(rec)
end

-- SCAN
local function parse(line)
	local n, p, b, d, a, be, la, sl = line:match("^(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)|(.-)$")
	if not n or n == "" then
		return nil
	end
	return { name = n, path = p, branch = b, dirty = d, ahead = a, behind = be, last = la, slug = sl }
end

local function count_dirty_or_diverged(tbl)
	local c = 0
	for _, r in ipairs(tbl) do
		if r.dirty == "1" or (tonumber(r.ahead or "0") or 0) > 0 or (tonumber(r.behind or "0") or 0) > 0 then
			c = c + 1
		end
	end
	return c
end

local function rescan()
	if state.scan_in_flight then
		return
	end
	state.scan_in_flight = true
	chip:set({ label = { string = "…" } })

	local cmd = "/bin/bash -lc 'export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin; \""
		.. escape_for_bash_double(SCAN_SCRIPT)
		.. "\"'"
	sbar.exec(cmd, function(out)
		state.scan_in_flight = false

		-- If popup closed: just update count
		if not state.popup_open then
			local cnt = 0
			for _ in string.gmatch(out or "", "[^\r\n]+") do
				cnt = cnt + 1
			end
			chip:set({ label = { string = (cnt > 0 and (cnt .. " repos") or "git") }, icon = { color = colors.white } })
			return
		end

		clear_rows()

		if not out or out == "" then
			local empty = TOOL_PREFIX .. ".row.empty"
			sbar.remove(empty)
			sbar.add("item", empty, {
				position = "popup." .. br.name,
				icon = { drawing = false },
				label = { string = "No repos found", align = "center" },
				width = 480,
			})
			track(empty)
			chip:set({ label = { string = "git" }, icon = { color = colors.white } })
			return
		end

		local records = {}
		for _, line in ipairs(split_lines(out)) do
			local r = parse(line)
			if r then
				table.insert(records, r)
			end
		end

		chip:set({
			label = { string = (#records > 0 and (#records .. " repos") or "git") },
			icon = { color = (count_dirty_or_diverged(records) > 0) and colors.yellow or colors.white },
		})

		for _, r in ipairs(records) do
			ensure_repo_row(r)
		end

		local pad = TOOL_PREFIX .. ".pad"
		sbar.remove(pad)
		sbar.add("item", pad, {
			position = "popup." .. br.name,
			width = 1,
			background = { color = colors.transparent, height = 6 },
		})
		track(pad)
	end)
end

-- TOGGLE POPUP
chip:subscribe("mouse.clicked", function()
	sbar.set(br.name, { popup = { drawing = "toggle" } })
	sbar.delay(0.05, function()
		local q = sbar.query(br.name)
		state.popup_open = (q and q.popup and q.popup.drawing == "on") or false
		if state.popup_open then
			-- fast feedback: show a small “Loading…” row immediately
			local loader = TOOL_PREFIX .. ".row.loading"
			sbar.remove(loader)
			sbar.add("item", loader, {
				position = "popup." .. br.name,
				icon = { drawing = false },
				label = { string = "Loading repositories…", align = "center" },
				width = 480,
			})
			track(loader)
			rescan()
		else
			clear_rows()
			chip:set({ label = { string = "Git" }, icon = { color = colors.white } })
		end
	end)
end)

-- PERIODIC (only count while closed)
chip:subscribe({ "routine", "system_woke" }, function()
	if state.popup_open then
		return
	end
	rescan()
end)

-- spacing after widget
sbar.add("item", { position = "right", width = settings.group_paddings })
