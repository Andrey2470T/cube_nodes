-- Painting Machine: put in an empty cube and a dye, pick a font, click the
-- button of the symbol you need — this spends the inputs right away — and
-- take the painted cube from the output slot.

-- constants

-- Inventory list names
local OUTPUT_SLOT = "pm_output"
local NODE_LIST = "pm_node_list"
local DYE_LIST = "pm_dye_list"

-- Output list of mod versions before the symbol buttons; old machines may
-- still hold painted cubes in it, they are handed back to the player on use
local LEGACY_LIST = "pm_list"

-- Formspec field names
local FONT_DROPDOWN = "pm_font_dd"
local SCROLLBAR = "pm_scrlbar"
local BUTTON_PREFIX = "pm_btn_"

-- Meta key the selected font is stored under.
-- Must not be renamed: machines placed by older mod versions use it.
local FONT_META = "context_dd_value"

-- Meta key the state of the stored formspec is cached under, so that the
-- formspec is rebuilt and re-sent only when its contents really changed
local FS_STATE_META = "pm_fs_state"

-- Button grid geometry, in real-coordinate units. A button is 1.0 units in
-- size plus 0.25 units of spacing between buttons, so it takes 1.25 units.
local BUTTON_COLS = 8 -- buttons per row
local SLOT_STEP = 1.25
local VISIBLE_ROWS = 4
local SCROLL_FACTOR = 0.1
local WINDOW_X, WINDOW_Y = 0.5, 0.5
local SCROLLBAR_X = 10.4
local SCROLLBAR_W = 0.3

-- formspec

local function fs_list(pos, listname, x, y, w, h)
	return ("list[nodemeta:%d,%d,%d;%s;%g,%g;%d,%d;]")
		:format(pos.x, pos.y, pos.z, listname, x, y, w, h)
end

-- Dropdown choices are generated from the font list so that the two
-- cannot get out of sync; font_index doubles as a font name validator
local FONT_CHOICES = {}
local font_index = {}
for i, font in ipairs(cube_nodes.fonts) do
	FONT_CHOICES[i] = font:sub(1, 1):upper() .. font:sub(2)
	font_index[font] = i
end
FONT_CHOICES = table.concat(FONT_CHOICES, ",")

local function get_font(meta)
	local font = meta:get_string(FONT_META)
	return font_index[font] and font or "normal"
end

local function get_paint_machine_fs(pos, outputs)
	local font = get_font(core.get_meta(pos))
	local rows = math.max(1, math.ceil(#outputs / BUTTON_COLS))

	-- Size of the scrolling window and of the full button grid inside it
	local window_w = SLOT_STEP * BUTTON_COLS - 0.25
	local window_h = SLOT_STEP * VISIBLE_ROWS - 0.25
	local content_h = SLOT_STEP * rows - 0.25

	-- The scrollbar scrolls only the hidden part of the content; its thumb
	-- covers the same fraction of the bar as the window covers of the content
	local scroll_max = math.round(math.max(content_h - window_h, 0) / SCROLL_FACTOR)
	local thumb_size = math.max(1, math.round(scroll_max * window_h / content_h))

	local fs = {
		"formspec_version[4]size[11,13]",

		-- smallstep/largestep = one button row / one visible page
		("scrollbaroptions[min=0;max=%d;thumbsize=%d;smallstep=%d;"
			.. "largestep=%d;arrows=hide]"):format(
			scroll_max, thumb_size,
			math.round(SLOT_STEP / SCROLL_FACTOR),
			math.round(window_h / SCROLL_FACTOR)),

		-- The scrollbar must not overlap the scroll_container, otherwise
		-- the container intercepts mouse clicks aimed at the scrollbar
		("scrollbar[%g,%g;%g,%g;vertical;%s;]"):format(
			SCROLLBAR_X, WINDOW_Y, SCROLLBAR_W, window_h, SCROLLBAR),

		("scroll_container[%g,%g;%g,%g;%s;vertical;%g]"):format(
			WINDOW_X, WINDOW_Y, window_w, window_h, SCROLLBAR, SCROLL_FACTOR),
	}

	-- One square button per paintable symbol, with the icon of the cube it
	-- paints. The buttons show up only when both input lists are filled and
	-- no chosen cube is waiting in the output slot.
	for i, entry in ipairs(outputs) do
		local index = i - 1
		fs[#fs + 1] = ("item_image_button[%g,%g;1,1;%s;%s%s;]"):format(
			(index % BUTTON_COLS) * SLOT_STEP,
			math.floor(index / BUTTON_COLS) * SLOT_STEP,
			entry.stack:get_name(),
			BUTTON_PREFIX, entry.symbol)
	end

	fs[#fs + 1] = "scroll_container_end[]"

	fs[#fs + 1] = "list[current_player;main;0.5,7.5;8,4;]"

	fs[#fs + 1] = "label[2,6;Node:]" .. fs_list(pos, NODE_LIST, 2, 6.25, 1, 1)
	fs[#fs + 1] = "label[5,6;Dye:]" .. fs_list(pos, DYE_LIST, 5, 6.25, 1, 1)
		.. "image[5,6.25;1,1;dye_icon.png]"
	fs[#fs + 1] = ("label[7,6;Font:]dropdown[7,6.25;1.5;%s;%s;%d;]")
		:format(FONT_DROPDOWN, FONT_CHOICES, font_index[font])
	fs[#fs + 1] = "label[8.75,6;Output:]"
		.. fs_list(pos, OUTPUT_SLOT, 8.75, 6.25, 1, 1)

	return table.concat(fs)
end

-- output

-- Dye colors that are named differently from the node colors
local DYE_COLOR_ALIASES = {
	dark_green = "darkgreen",
	dark_grey = "darkgrey",
}

local function dye_color(dye_stack)
	local name = dye_stack:get_name()
	local color = name:sub(name:find("dye:") + 4)

	return DYE_COLOR_ALIASES[color] or color
end

-- Color and count of the cubes paintable from the given input stacks,
-- or nil if painting is not possible at all
local function paint_params(node_stack, dye_stack)
	if not node_stack:get_name():match("node_empty")
		or not dye_stack:get_name():match("dye:") then
		return
	end

	local color = dye_color(dye_stack)
	-- there are no white nodes
	if color == "white" then
		return
	end

	return color, math.min(node_stack:get_count(), dye_stack:get_count())
end

-- All symbol cubes paintable from the given input stacks:
-- a list of {symbol, stack} entries
local function build_output_list(node_stack, dye_stack, font)
	local color, count = paint_params(node_stack, dye_stack)
	if not color then
		return {}
	end

	local list = {}

	for _, symbol in ipairs(cube_nodes.symbols) do
		if not cube_nodes.is_skipped(font, symbol) then
			local stack = ItemStack(cube_nodes.node_name(font, symbol, color))
			stack:set_count(count)
			list[#list + 1] = {symbol = symbol, stack = stack}
		end
	end

	return list
end

-- Known symbol names, to take apart item names correctly: the "normal"
-- font has no prefix, so a font prefix can otherwise end up in the symbol
local symbol_set = {}
for _, symbol in ipairs(cube_nodes.symbols) do
	symbol_set[symbol] = true
end

-- "cube_nodes:node_bold_A_black" -> {font = "bold", symbol = "A", color = "black"}
local function parse_node_item(itemname)
	local base = itemname:match("^cube_nodes:node_(.+)$")
	if not base then
		return
	end

	for _, font in ipairs(cube_nodes.fonts) do
		local prefix = cube_nodes.font_prefix(font)
		if base:sub(1, #prefix) == prefix then
			local rest = base:sub(#prefix + 1)
			for _, color in ipairs(cube_nodes.colors) do
				local suffix = "_" .. color
				if rest:sub(-#suffix) == suffix then
					local symbol = rest:sub(1, -#suffix - 1)
					if symbol_set[symbol] then
						return {
							font = font,
							symbol = symbol,
							color = color,
						}
					end
				end
			end
		end
	end
end

-- Mesh visuals entities handling (adds the paint fluid filling in the paint machine's transparent box for
-- the current put dye and cube node for the current put symbol)

-- The visuals live at fixed offsets from the machine node and are searched
-- for around it on every update, so they survive server restarts and cannot
-- get out of sync with the machine state
local VISUALS = {
	paint_fill = {
		entity = "cube_nodes:paint_fill",
		offset = vector.new(0, 1.25, 0),
		pack = function(data)
			return data.color
		end,
	},
	node_symbol = {
		entity = "cube_nodes:node_symbol",
		offset = vector.new(0, 0, 0), -- the node center
		pack = core.serialize,
	},
}

-- Updates or removes (data == nil) a machine visual entity
local function update_visual(pos, name, data)
	local spec = VISUALS[name]
	local anchor = vector.add(pos, spec.offset)

	local object
	for _, obj in ipairs(core.get_objects_inside_radius(anchor, 0.5)) do
		local luaentity = obj:get_luaentity()
		if luaentity and luaentity.name == spec.entity
			and vector.distance(obj:get_pos(), anchor) < 0.1 then
			object = obj
			break
		end
	end

	if not data then
		if object then
			object:remove()
		end
	elseif object then
		object:get_luaentity():update_visual(data)
	else
		core.add_entity(anchor, spec.entity, spec.pack(data))
	end
end

-- inventory handling

-- Spends the given number of input cubes and dyes
local function take_from_inputs(inv, count)
	for _, listname in ipairs({NODE_LIST, DYE_LIST}) do
		local stack = inv:get_stack(listname, 1)
		stack:take_item(count)
		inv:set_stack(listname, 1, stack)
	end
end

-- The machine formspec depends on the input stacks, but the engine does not
-- refresh node formspecs that are already open; they are re-sent by hand to
-- the players that currently have one open
local open_forms = {} -- player name -> machine position

core.register_on_leaveplayer(function(player)
	open_forms[player:get_player_name()] = nil
end)

local function rebuild_formspec(pos)
	local meta = core.get_meta(pos)
	local inv = core.get_inventory({type = "node", pos = pos})

	-- While a chosen cube is waiting in the output slot the buttons are
	-- not offered; they come back after the cube is taken
	local outputs = {}
	if inv:get_stack(OUTPUT_SLOT, 1):is_empty() then
		outputs = build_output_list(inv:get_stack(NODE_LIST, 1),
			inv:get_stack(DYE_LIST, 1), get_font(meta))
	end

	meta:set_string("formspec", get_paint_machine_fs(pos, outputs))
end

local function resend_formspec(pos)
	pos = vector.round(pos)
	local formspec = core.get_meta(pos):get_string("formspec")

	for name, machine_pos in pairs(open_forms) do
		if vector.equals(machine_pos, pos) then
			local player = core.get_player_by_name(name)
			if player then
				core.show_formspec(name,
					("nodemeta:%d,%d,%d"):format(pos.x, pos.y, pos.z),
					formspec)
			else
				open_forms[name] = nil
			end
		end
	end
end

-- Brings everything derived from the inventory up to date: the visual
-- entities and the open formspecs
local function refresh_paint_machine(pos)
	local meta = core.get_meta(pos)
	local inv = core.get_inventory({type = "node", pos = pos})

	local font = get_font(meta)
	local node_stack = inv:get_stack(NODE_LIST, 1)
	local dye_stack = inv:get_stack(DYE_LIST, 1)
	local color = paint_params(node_stack, dye_stack)

	-- The cubes in the output slot are paid for at the button click, so
	-- they are a finished product: no later input change invalidates them

	-- The paint fluid filling for the current dye
	if dye_stack:get_name():match("dye:") then
		update_visual(pos, "paint_fill", {color = dye_color(dye_stack)})
	else
		update_visual(pos, "paint_fill", nil)
	end

	-- The cube of the painted result while there is one, otherwise the cube
	-- put into the node input
	local output_stack = inv:get_stack(OUTPUT_SLOT, 1)
	local node_data
	if not output_stack:is_empty() then
		node_data = parse_node_item(output_stack:get_name())
	elseif not node_stack:is_empty() then
		node_data = parse_node_item(node_stack:get_name())
	end
	update_visual(pos, "node_symbol", node_data)

	-- The open formspecs need a rebuild when the button grid or the output
	-- slot changed: a symbol button click fills the output and hides the
	-- buttons, taking the cube empties the output and brings the buttons
	-- back, so the form must be re-sent in both cases
	local state = font .. "|" .. (color or "") .. "|"
		.. (output_stack:is_empty() and ""
			or output_stack:get_name() .. output_stack:get_count())
	if meta:get_string(FS_STATE_META) ~= state then
		meta:set_string(FS_STATE_META, state)
		rebuild_formspec(pos)
		resend_formspec(pos)
	end
end

-- Wait until the engine has applied an inventory change, then update the
-- machine
local function on_inventory_change(pos)
	core.after(0.01, function()
		refresh_paint_machine(pos)
	end)
end

-- Puts the stack of the chosen symbol cube into the output slot, spending
-- the input cubes and dyes it was painted from right away
local function on_symbol_button(pos, player, symbol)
	local meta = core.get_meta(pos)
	local font = get_font(meta)
	if cube_nodes.is_skipped(font, symbol) then
		return
	end

	local inv = core.get_inventory({type = "node", pos = pos})

	-- The output slot is normally empty here: the buttons are not offered
	-- while it is filled. A leftover stack can only be a lost race against
	-- another player's click; it was paid for already, so it is simply
	-- given back to the player
	local old_stack = inv:get_stack(OUTPUT_SLOT, 1)
	if not old_stack:is_empty() then
		local leftover = player:get_inventory():add_item("main", old_stack)
		if not leftover:is_empty() then
			core.item_drop(leftover, player, pos)
		end
	end

	local color, count = paint_params(
		inv:get_stack(NODE_LIST, 1), inv:get_stack(DYE_LIST, 1))

	local new_stack = ItemStack()
	if color and count > 0 then
		new_stack = ItemStack(cube_nodes.node_name(font, symbol, color))
		new_stack:set_count(count)

		-- every painted cube costs one input cube and one dye, paid at once
		take_from_inputs(inv, count)
	end
	inv:set_stack(OUTPUT_SLOT, 1, new_stack)

	if not new_stack:is_empty() then
		core.sound_play("painting_machine", {pos = pos}, true)
	end

	-- refreshes the input slots, the cube visual and the open formspecs
	refresh_paint_machine(pos)
end

-- node & craft

local MACHINE_BOX = {
	type = "fixed",
	fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5},
}

-- Which item names may be put into which input list
local ALLOWED_INPUTS = {
	[NODE_LIST] = "node_empty",
	[DYE_LIST] = "dye:",
}

core.register_node("cube_nodes:paint_machine", {
	description = "Painting Machine",
	drawtype = "mesh",
	visual_scale = 0.5,
	mesh = "painting_machine.obj",
	tiles = {"painting_machine.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	use_texture_alpha = "blend",
	groups = {cracky = 2.5},
	collision_box = MACHINE_BOX,
	selection_box = MACHINE_BOX,

	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string(FONT_META, "normal")

		local inv = core.get_inventory({type = "node", pos = pos})
		inv:set_size(NODE_LIST, 1)
		inv:set_size(DYE_LIST, 1)
		inv:set_size(OUTPUT_SLOT, 1)

		refresh_paint_machine(pos)
	end,

	after_destruct = function(pos)
		update_visual(pos, "paint_fill", nil)
		update_visual(pos, "node_symbol", nil)
	end,

	on_rightclick = function(pos, _, clicker)
		if clicker and clicker:is_player() then
			open_forms[clicker:get_player_name()] = vector.round(pos)

			-- Hand back what old mod versions kept in their output list,
			-- which the symbol buttons have replaced
			local inv = core.get_inventory({type = "node", pos = pos})
			local legacy = inv:get_list(LEGACY_LIST)
			if legacy then
				for _, stack in ipairs(legacy) do
					if not stack:is_empty() then
						local leftover = clicker:add_item("main", stack)
						if not leftover:is_empty() then
							core.item_drop(leftover, clicker, pos)
						end
					end
				end
				inv:set_size(LEGACY_LIST, 0)
			end
		end

		-- Refresh the stored formspec so machines placed by an older mod
		-- version get the current layout too
		rebuild_formspec(pos)
		refresh_paint_machine(pos)
	end,

	allow_metadata_inventory_put = function(_, listname, _, stack)
		local pattern = ALLOWED_INPUTS[listname]

		if not pattern or not stack:get_name():match(pattern) then
			return 0
		end

		return stack:get_count()
	end,

	-- The output slot is filled by the symbol buttons only: nothing can be
	-- moved into it or out of it inside the machine inventory by hand
	allow_metadata_inventory_move = function(pos, from_list, from_index,
		to_list, _, count)
		if from_list == OUTPUT_SLOT or to_list == OUTPUT_SLOT then
			return 0
		end

		local pattern = ALLOWED_INPUTS[to_list]
		if not pattern then
			return 0
		end

		local stack = core.get_inventory({type = "node", pos = pos})
			:get_stack(from_list, from_index)
		if not stack:get_name():match(pattern) then
			return 0
		end

		return count
	end,

	on_metadata_inventory_put = function(pos)
		on_inventory_change(pos)
	end,

	on_metadata_inventory_move = function(pos)
		on_inventory_change(pos)
	end,

	on_metadata_inventory_take = function(pos)
		on_inventory_change(pos)
	end,

	on_receive_fields = function(pos, _, fields, player)
		if fields.quit then
			if player then
				open_forms[player:get_player_name()] = nil
			end
			core.get_meta(pos):set_string(FONT_META, "normal")
			refresh_paint_machine(pos)
			return
		end

		-- The engine submits the current dropdown value together with every
		-- button click, so the font is applied first and the button is then
		-- handled below instead of the dropdown swallowing the click
		local font_changed = false
		if fields[FONT_DROPDOWN] then
			local font = fields[FONT_DROPDOWN]:lower()
			if font_index[font]
				and font ~= core.get_meta(pos):get_string(FONT_META) then
				core.get_meta(pos):set_string(FONT_META, font)
				font_changed = true
			end
		end

		-- a symbol button was pressed
		for field in pairs(fields) do
			local symbol = field:match("^" .. BUTTON_PREFIX .. "(.+)$")
			if symbol then
				-- refreshes the form and the machine on its own
				on_symbol_button(pos, player, symbol)
				return
			end
		end

		if font_changed then
			refresh_paint_machine(pos)
		end
	end,

	can_dig = function(pos)
		local inv = core.get_inventory({type = "node", pos = pos})
		return inv:is_empty(NODE_LIST) and inv:is_empty(DYE_LIST)
			and inv:is_empty(OUTPUT_SLOT)
	end,
})

core.register_craft({
	output = "cube_nodes:paint_machine",
	recipe = {
		{"default:steelblock", "default:steelblock", "bucket:bucket_empty"},
		{"", "default:glass", ""},
		{"", "", ""},
	},
})

core.register_entity("cube_nodes:paint_fill", {
	physical = false,
	pointable = false,
	visual = "cube",
	visual_size = {x=0.7, y=0.4, z=0.7},
	textures = {"blank.png"},
	use_texture_alpha = true,
	on_activate = function(self, staticdata)
		self:update_visual({color=staticdata})
		return true
	end,
	update_visual = function(self, new_data)
		self.color = new_data.color or ""
		self.object:set_properties({textures={"blank.png^[fill:32x32:0,0:" .. self.color}})
	end,
	get_staticdata = function(self)
		return self.color
	end
});

core.register_entity("cube_nodes:node_symbol", {
	physical = false,
	pointable = false,
	visual = "node",
	visual_size = {x=0.8, y=0.8, z=0.8},
	node = {name=cube_nodes.node_name("normal", "empty", "black")},
	use_texture_alpha = true,
	on_activate = function(self, staticdata)
		local data = {}
		if staticdata ~= "" then
			data = core.deserialize(staticdata) or {}
		end
		self:update_visual(data)

		return true
	end,
	update_visual = function(self, new_data)
		self.font = new_data.font or ""
		self.symbol = new_data.symbol or ""
		self.color = new_data.color or ""

		local name = cube_nodes.node_name(self.font, self.symbol, self.color)
		if core.registered_nodes[name] then
			self.object:set_properties({node={name=name}})
		end
	end,
	get_staticdata = function(self)
		return core.serialize({font=self.font, symbol=self.symbol, color=self.color})
	end
});
