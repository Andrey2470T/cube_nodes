-- Painting Machine

local pm_output_list_name = "pm_list"
local pm_node_list_name = "pm_node_list"
local pm_dye_list_name = "pm_dye_list"
local pm_font_dd = "pm_font_dd"

function cube_nodes.get_paint_machine_fs(pos, nodes_count)
	local list_w = math.ceil(nodes_count / 4)

	local steps_c

	if list_w <= 8 then
		steps_c = 6
	else
		steps_c = list_w
	end

	steps_c = (steps_c - 6) / 0.1
	local fs = table.concat({
		"formspec_version[4]size[11,13]",
		("scrollbaroptions[min=0;max=%d;smallstep=%d;largestep=%s]"):format(steps_c, steps_c/7, steps_c/7),
		"scrollbar[0.5,5.5;10,0.2;horizontal;pm_scrlbar;]",
		"scroll_container[0.5,0.5;10,5;pm_scrlbar;horizontal]",
		("list[nodemeta:%d,%d,%d;%s;0,0;%d,4;]"):format(pos.x, pos.y, pos.z, pm_output_list_name, list_w),
		"scroll_container_end[]",
		"list[current_player;main;0.5,7.5;8,4;]",
		("label[2,6;Node:]list[nodemeta:%d,%d,%d;%s;2,6.25;1,1;]"):format(pos.x, pos.y, pos.z, pm_node_list_name),
		("label[5,6;Dye:]list[nodemeta:%d,%d,%d;%s;5,6.25;1,1;]"):format(pos.x, pos.y, pos.z, pm_dye_list_name),
		"image[5,6.25;1,1;dye_icon.png]",
		("label[7,6;Font:]dropdown[7,6.25;1.5;%s;Normal,Italic;1;]"):format(pm_font_dd)
	})

	return fs
end

function cube_nodes.form_paint_machine_output_list(node_list_item, dye_list_item, font_type)
	local node_item_name = node_list_item:get_name()
	local dye_item_name = dye_list_item:get_name()

	local count = math.min(node_list_item:get_count(), dye_list_item:get_count())

	local list = {}

	if not node_item_name:match("node_empty") then
		return list
	end

	if not dye_item_name:match("dye:") then
		return list
	end

	local f_type = font_type == "normal" and "" or font_type .. "_"
	local color_s, color_e = dye_item_name:find("dye:")
	local color = dye_item_name:sub(color_e+1)

	if color == "darkgreen" then
		color = "dark_green"
	elseif color == "darkgrey" then
		color = "dark_grey"
	end

	for _, sym in ipairs(cube_nodes.symbols) do
		if not cube_nodes.skip_nodes[font_type] or (cube_nodes.skip_nodes[font_type] and not cube_nodes.skip_nodes[font_type][sym]) then
			local nodename = "cube_nodes:node_" .. f_type .. sym .. "_" .. color

			local stack = ItemStack(nodename)
			stack:set_count(count)

			table.insert(list, stack)
		end
	end

	return list
end

function cube_nodes.on_inv_action_in_paint_machine(pos, action, listname)
	if not pos then return end

	local dd_value = minetest.get_meta(pos):get_string("context_dd_value")

	local inv = minetest.get_inventory({type="node", pos=pos})

	if action == "take" and listname == pm_output_list_name then
		inv:set_stack(pm_node_list_name, 1, ItemStack(""))
		inv:set_stack(pm_dye_list_name, 1, ItemStack(""))
	end

	-- Waiting for when the given list gets updated and only after that get new itemstacks
	minetest.after(0.01, function()
		local node_stack = inv:get_stack(pm_node_list_name, 1)
		local dye_stack = inv:get_stack(pm_dye_list_name, 1)

		local list = cube_nodes.form_paint_machine_output_list(node_stack, dye_stack, dd_value)
		inv:set_list(pm_output_list_name, list)
	end)
end

minetest.register_node("cube_nodes:paint_machine", {
	description = "Painting Machine",
	visual_scale = 0.5,
	drawtype = "mesh",
	mesh = "painting_machine.b3d",
	tiles = {"painting_machine.png"},
	paramtype = "light",
	paramtype2 = "facedir",
	groups = {cracky=2.5},
	use_texture_alpha = "blend",
	collision_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}
	},
	selection_box = {
		type = "fixed",
		fixed = {-0.5, -0.5, -0.5, 0.5, 1.5, 0.5}
	},
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)

		meta:set_string("formspec", cube_nodes.get_paint_machine_fs(pos, cube_nodes.nodes_count))
		meta:set_string("context_dd_value", "normal")

		local inv = minetest.get_inventory({type="node", pos=pos})
		local w = math.ceil(cube_nodes.nodes_count/4)
		inv:set_size(pm_output_list_name, w*4)
		inv:set_width(pm_output_list_name, w)

		inv:set_size(pm_node_list_name, 1)
		inv:set_size(pm_dye_list_name, 1)
	end,
	allow_metadata_inventory_put = function(pos, listname, index, stack, player)
		local not_allow = listname == pm_output_list_name or
			(listname == pm_node_list_name and not stack:get_name():match("node_empty")) or
			(listname == pm_dye_list_name and not stack:get_name():match("dye:"))

		if not_allow then return 0 end

		return stack:get_count()
	end,
	on_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		cube_nodes.on_inv_action_in_paint_machine(pos, "move", to_list)
	end,
	on_metadata_inventory_put = function(pos, listname, index, stack, player)
		cube_nodes.on_inv_action_in_paint_machine(pos, "put", listname)
	end,
	on_metadata_inventory_take = function(pos, listname, index, stack, player)
		cube_nodes.on_inv_action_in_paint_machine(pos, "take", listname)
	end,
	on_receive_fields = function(pos, formname, fields, sender)
		if fields.pm_font_dd then
			local new_ftype = fields.pm_font_dd:lower()
			minetest.get_meta(pos):set_string("context_dd_value", new_ftype)

			local inv = minetest.get_inventory({type="node", pos=pos})
			local node_stack = inv:get_stack(pm_node_list_name, 1)
			local dye_stack = inv:get_stack(pm_dye_list_name, 1)

			local list = cube_nodes.form_paint_machine_output_list(node_stack, dye_stack, new_ftype)

			inv:set_list(pm_output_list_name, list)
		elseif fields.quit then
			minetest.get_meta(pos):set_string("context_dd_value", "normal")
		end
	end,
	can_dig = function(pos)
		local inv = minetest.get_inventory({type="node",pos=pos})
		local node_l_empty = inv:is_empty(pm_node_list_name)
		local dye_l_empty = inv:is_empty(pm_dye_list_name)

		return node_l_empty and dye_l_empty
	end
})

minetest.register_craft({
	output = "cube_nodes:paint_machine",
	recipe = {
		{"default:steelblock", "default:steelblock", "bucket:bucket_empty"},
		{"", "default:glass", ""},
		{"", "", ""}
	}
})
