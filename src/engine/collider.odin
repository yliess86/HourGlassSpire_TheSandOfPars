package engine

import physics "../physics"

// Type aliases — all existing code using engine.Collider_* continues to work.
Collider_Rect :: physics.Rect
Collider_Slope_Kind :: physics.Slope_Kind
Collider_Slope :: physics.Slope
Collider_Raycast_Hit :: physics.Raycast_Hit

// Proc aliases
collider_check_rect_vs_rect :: physics.rect_overlap
collider_resolve_dynamic_rect :: physics.rect_resolve
collider_slope_surface_y :: physics.slope_surface_y
collider_slope_surface_x :: physics.slope_surface_x
collider_slope_is_floor :: physics.slope_is_floor
collider_raycast_rect :: physics.raycast_rect
collider_raycast_slope :: physics.raycast_slope
