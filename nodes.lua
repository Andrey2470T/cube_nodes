-- Symbol cube nodes: "cube_nodes:node_<font>_<symbol>_<color>"

----------------------------------------------------------------------- data --

cube_nodes.symbols = {
	-- digits
	"1", "2", "3", "4", "5",
	"6", "7", "8", "9", "0",
	-- letters
	"A", "B", "C", "D", "E", "F", "G",
	"H", "I", "J", "K", "L", "M", "N",
	"O", "P", "Q", "R", "S", "T", "U",
	"W", "X", "Y", "Z",
	-- symbols
	"ampersand", "asterisk", "bracket_left",
	"bracket_right", "comma", "corner_bracket_left",
	"corner_bracket_right", "dash", "division_mark",
	"dollar", "dot", "email", "empty",
	"equality_mark", "evil", "exclamation_mark",
	"figure_bracket_left", "figure_bracket_right",
	"grid", "minus", "multiplication_mark",
	"normal", "plus", "procent", "question_mark",
	"round_bracket_left", "round_bracket_right",
	"sad", "slash_left", "slash_right",
	"smile", "tilde",
}

cube_nodes.fonts = {
	"normal",
	"italic",
	"bold",
}

cube_nodes.colors = {
	"black", "blue", "brown", "cyan", "darkgreen",
	"darkgrey", "green", "grey", "magenta",
	"orange", "pink", "red", "violet", "yellow",
}

-- Symbols that have no italic/bold texture
local skipped_symbols = {
	"asterisk", "corner_bracket_left",
	"corner_bracket_right", "dash", "empty",
	"equality_mark", "evil", "minus",
	"normal", "plus", "procent", "sad",
	"slash_left", "slash_right", "smile", "tilde",
}

local skip_set = {}
for _, symbol in ipairs(skipped_symbols) do
	skip_set[symbol] = true
end

cube_nodes.skip_nodes = {
	italic = skip_set,
	bold = skip_set,
}

cube_nodes.nodes_count = #cube_nodes.symbols

-------------------------------------------------------------------- helpers --

-- The "normal" font has no font part in node and item names
function cube_nodes.font_prefix(font)
	if font == "normal" then
		return ""
	end
	return font .. "_"
end

function cube_nodes.is_skipped(font, symbol)
	local skipped = cube_nodes.skip_nodes[font]
	return skipped ~= nil and skipped[symbol] == true
end

-- "node_italic_smile" -> "Node Italic Smile"
function cube_nodes.name_to_desc(name)
	local words = {}
	for _, word in ipairs(name:split("_")) do
		words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
	end
	return table.concat(words, " ")
end

---------------------------------------------------------- node registration --

local function register_cube_node(font, symbol, color)
	local name = "node_" .. cube_nodes.font_prefix(font) .. symbol

	core.register_node("cube_nodes:" .. name .. "_" .. color, {
		description = cube_nodes.name_to_desc(name),
		tiles = {
			("blank.png^(%s.png^[colorize:%s:255)"):format(name, color),
		},
		paramtype = "light",
		sunlight_propagates = true,
		use_texture_alpha = "blend",
		light_source = 10,
		groups = {
			cracky = 1,
			oddly_breakable_by_hand = 1,
			-- only the black "empty" cube shows up as the craft result
			not_in_creative_inventory =
				(symbol == "empty" and color == "black") and 0 or 1,
		},
		sounds = default.node_sound_wood_defaults(),
	})
end

for _, font in ipairs(cube_nodes.fonts) do
	for _, symbol in ipairs(cube_nodes.symbols) do
		if not cube_nodes.is_skipped(font, symbol) then
			for _, color in ipairs(cube_nodes.colors) do
				register_cube_node(font, symbol, color)
			end
		end
	end
end

----------------------------------------------------------------------- craft --

core.register_craft({
	type = "shapeless",
	output = "cube_nodes:node_empty_black",
	recipe = {"default:steelblock", "dye:black"},
})
