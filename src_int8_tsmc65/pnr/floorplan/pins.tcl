# Signal pins: spread over all four sides on two mid-stack routing layers.
set_block_pin_constraints -self -allowed_layers {M4 M5} -sides {1 2 3 4}
place_pins -self
