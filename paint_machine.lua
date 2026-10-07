-- Painting Machine: put in an empty cube and a dye, pick a font and take
-- the painted cubes you need from the output list.

----------------------------------------------------------------- constants --

-- Inventory list names
local OUTPUT_LIST = "pm_list"
local NODE_LIST = "pm_node_list"
local DYE_LIST = "pm_dye_list"

-- Formspec field names
local FONT_DROPDOWN = "pm_font_dd"
local SCROLLBAR = "pm_scrlbar"

-- Meta key the selected font is stored under.
-- Must not be renamed: machines placed by older mod versions use it.
local FONT_META = "context_dd_value"

-- Output list geometry
local OUTPUT_LIST_W = 8 -- slots per row

-- Formspec layout, in real-coordinate units. A slot is 1.0 units in size
-- plus 0.25 units of spacing between slots, so a slot takes 1.25 units.
local SLOT_STEP = 1.25
local VISIBLE_ROWS = 4
local SCROLL_FACTOR = 0.1
local WINDOW_X, WINDOW_Y = 0.5, 0.5
local SCROLLBAR_X = 10.4
local SCROLLBAR_W = 0.3

------------------------------------------------------------------- formspec --

local function fs_list(pos, listname, x, y, w, h)
	return ("list[nodemeta:%d,%d,%d;%s;%g,%g;%d,%d;]")
		:format(pos.x, pos.y, pos.z, listname, x, y, w, h)
end

local function round(value)
	return math.floor(value + 0.5)
end

-- Dropdown choices are generated from the font list so that the two
-- cannot get out of sync
local FONT_CHOICES = {}
for _, font in ipairs(cube_nodes.fonts) do
	FONT_CHOICES[#FONT_CHOICES + 1] = font:sub(1, 1):upper() .. font:sub(2)
end
FONT_CHOICES = table.concat(FONT_CHOICES, ",")

local function get_paint_machine_fs(pos, nodes_count)
	local list_h = math.ceil(nodes_count / OUTPUT_LIST_W)

	-- Size of the scrolling window and of the full list inside it
	local window_w = SLOT_STEP * OUTPUT_LIST_W - 0.25
	local window_h = SLOT_STEP * VISIBLE_ROWS - 0.25
	local content_h = SLOT_STEP * list_h - 0.25

	-- The scrollbar scrolls only the hidden part of the content; its thumb
	-- covers the same fraction of the bar as the window covers of the content
	local scroll_max = round(math.max(content_h - window_h, 0) / SCROLL_FACTOR)
	local thumb_size = math.max(1, round(scroll_max * window_h / content_h))

	local fs = {
		"formspec_version[4]size[11,13]",

		-- smallstep/largestep = one slot row / one visible page
		("scrollbaroptions[min=0;max=%d;thumbsize=%d;smallstep=%d;"
			.. "largestep=%d;arrows=hide]"):format(
			scroll_max, thumb_size,
			round(SLOT_STEP / SCROLL_FACTOR),
			round(window_h / SCROLL_FACTOR)),

		-- The scrollbar must not overlap the scroll_container, otherwise
		-- the container intercepts mouse clicks aimed at the scrollbar
		("scrollbar[%g,%g;%g,%g;vertical;%s;]"):format(
			SCROLLBAR_X, WINDOW_Y, SCROLLBAR_W, window_h, SCROLLBAR),

		("scroll_container[%g,%g;%g,%g;%s;vertical;%g]"):format(
			WINDOW_X, WINDOW_Y, window_w, window_h, SCROLLBAR, SCROLL_FACTOR),
			-- the full list is drawn here, the container clips it
			fs_list(pos, OUTPUT_LIST, 0, 0, OUTPUT_LIST_W, list_h),
		"scroll_container_end[]",

		"list[current_player;main;0.5,7.5;8,4;]",

		"label[2,6;Node:]" .. fs_list(pos, NODE_LIST, 2, 6.25, 1, 1),
		"label[5,6;Dye:]" .. fs_list(pos, DYE_LIST, 5, 6.25, 1, 1)
			.. "image[5,6.25;1,1;dye_icon.png]",
		("label[7,6;Font:]dropdown[7,6.25;1.5;%s;%s;1;]")
			:format(FONT_DROPDOWN, FONT_CHOICES),
	}

	return table.concat(fs)
end

---------------------------------------------------------------- output list --

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

local function build_output_list(node_stack, dye_stack, font)
	if not node_stack:get_name():match("node_empty")
		or not dye_stack:get_name():match("dye:") then
		return {}
	end

	local color = dye_color(dye_stack)
	-- there are no white nodes
	if color == "white" then
		return {}
	end

	local prefix = cube_nodes.font_prefix(font)
	local count = math.min(node_stack:get_count(), dye_stack:get_count())
	local list = {}

	for _, symbol in ipairs(cube_nodes.symbols) do
		if not cube_nodes.is_skipped(font, symbol) then
			local stack = ItemStack(
				"cube_nodes:node_" .. prefix .. symbol .. "_" .. color)
			stack:set_count(count)
			list[#list + 1] = stack
		end
	end

	return list
end

-------------------------------------------------------- inventory handling --

local function take_from_inputs(inv, count)
	for _, listname in ipairs({NODE_LIST, DYE_LIST}) do
		local stack = inv:get_stack(listname, 1)
		stack:take_item(count)
		inv:set_stack(listname, 1, stack)
	end
end

local function update_output(pos)
	local inv = core.get_inventory({type = "node", pos = pos})
	local font = core.get_meta(pos):get_string(FONT_META)

	local node_stack = inv:get_stack(NODE_LIST, 1)
	local dye_stack = inv:get_stack(DYE_LIST, 1)

	inv:set_list(OUTPUT_LIST, build_output_list(node_stack, dye_stack, font))
end

local function on_inventory_change(pos, action, listname, taken_count)
	if action == "take" and listname == OUTPUT_LIST then
		-- every output cube taken costs one input cube and one dye
		local inv = core.get_inventory({type = "node", pos = pos})
		take_from_inputs(inv, taken_count)
	end

	-- Wait until the engine has applied the change, then rebuild the output
	core.after(0.01, function()
		update_output(pos)
	end)
end

------------------------------------------------------------- node & craft --

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
	mesh = "painting_machine.b3d",
	tiles = {"painting_machine.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	use_texture_alpha = "blend",
	groups = {cracky = 2.5},
	collision_box = MACHINE_BOX,
	selection_box = MACHINE_BOX,

	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string("formspec",
			get_paint_machine_fs(pos, cube_nodes.nodes_count))
		meta:set_string(FONT_META, "normal")

		local inv = core.get_inventory({type = "node", pos = pos})
		local rows = math.ceil(cube_nodes.nodes_count / OUTPUT_LIST_W)
		inv:set_size(OUTPUT_LIST, OUTPUT_LIST_W * rows)
		inv:set_width(OUTPUT_LIST, OUTPUT_LIST_W)
		inv:set_size(NODE_LIST, 1)
		inv:set_size(DYE_LIST, 1)
	end,

	on_rightclick = function(pos)
		-- Refresh the stored formspec so machines placed by an older mod
		-- version get the current layout too
		core.get_meta(pos):set_string("formspec",
			get_paint_machine_fs(pos, cube_nodes.nodes_count))
	end,

	allow_metadata_inventory_put = function(_, listname, _, stack)
		local pattern = ALLOWED_INPUTS[listname]

		if not pattern or not stack:get_name():match(pattern) then
			return 0
		end

		return stack:get_count()
	end,

	on_metadata_inventory_put = function(pos, listname)
		on_inventory_change(pos, "put", listname)
	end,

	on_metadata_inventory_move = function(pos, _, _, to_list)
		on_inventory_change(pos, "move", to_list)
	end,

	on_metadata_inventory_take = function(pos, listname, _, stack)
		on_inventory_change(pos, "take", listname, stack:get_count())
	end,

	on_receive_fields = function(pos, _, fields)
		if fields[FONT_DROPDOWN] then
			local font = fields[FONT_DROPDOWN]:lower()
			core.get_meta(pos):set_string(FONT_META, font)
			update_output(pos)
		elseif fields.quit then
			core.get_meta(pos):set_string(FONT_META, "normal")
		end
	end,

	can_dig = function(pos)
		local inv = core.get_inventory({type = "node", pos = pos})
		return inv:is_empty(NODE_LIST) and inv:is_empty(DYE_LIST)
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
