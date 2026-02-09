package engine

FSM_State_Handler :: struct($Ctx, $State: typeid) {
	enter:  proc(ctx: ^Ctx),
	update: proc(ctx: ^Ctx, dt: f32) -> Maybe(State),
	exit:   proc(ctx: ^Ctx),
}

FSM :: struct($Ctx, $State: typeid) {
	ctx:      ^Ctx,
	current:  State,
	previous: State,
	handlers: [State]FSM_State_Handler(Ctx, State),
}

fsm_init :: proc(sm: ^FSM($C, $S), ctx: ^C, initial: S) {
	sm.ctx = ctx
	sm.current = initial
	sm.previous = initial
	if handler := sm.handlers[initial].enter; handler != nil do handler(ctx)
}

fsm_update :: proc(sm: ^FSM($C, $S), dt: f32) {
	handler := sm.handlers[sm.current].update
	if handler == nil do return
	result := handler(sm.ctx, dt)
	if next, ok := result.?; ok do fsm_transition(sm, next)
}

fsm_transition :: proc(sm: ^FSM($C, $S), next: S) {
	if sm.current == next do return
	if handler := sm.handlers[sm.current].exit; handler != nil do handler(sm.ctx)
	sm.previous = sm.current
	sm.current = next
	if handler := sm.handlers[next].enter; handler != nil do handler(sm.ctx)
}
