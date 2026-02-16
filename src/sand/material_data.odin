package sand

// Movement archetype for cellular automaton dispatch
Behavior :: enum u8 {
	Static, // immovable (Solid, Platform, Empty)
	Powder, // granular: falls, piles with diagonal repose (Sand, Wet_Sand)
	Liquid, // fluid: falls, flows horizontally, pressure-driven rise (Water)
	Gas, // rises (future use)
}

// Data-driven material properties for simulation dispatch
Material_Props :: struct {
	behavior: Behavior,
	density:  u8, // higher density sinks below lower; 0 = displaceable by anything
	inert:    bool, // skip simulation dispatch entirely
}

// Single source of truth for material physics.
// Density ordering drives buoyancy: Wet_Sand(4) > Sand(3) > Water(1) > Empty(0).
MAT_PROPS := [Material]Material_Props {
	.Empty = {behavior = .Static, density = 0, inert = true},
	.Solid = {behavior = .Static, density = 255, inert = true},
	.Sand = {behavior = .Powder, density = 3, inert = false},
	.Water = {behavior = .Liquid, density = 1, inert = false},
	.Platform = {behavior = .Static, density = 255, inert = true},
	.Wet_Sand = {behavior = .Powder, density = 4, inert = false},
}
