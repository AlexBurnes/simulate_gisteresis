local Terminal = {}
Terminal.__index = Terminal

function Terminal.new(id, simulation_time)
    local self = setmetatable({}, Terminal)
    self.id = id
    self.registered_operator = nil
    self.last_reregister = simulation_time
    self.state = "unregistered"
    self.next_event_time = simulation_time + love.math.random(1, 10)
    self.current_operator = nil
    self.current_attempts = 0
    self.tried_operators = {}
    self.failed_attempts = 0
    return self
end

function Terminal:reset_attempts()
    self.current_operator = nil
    self.current_attempts = 0
    self.tried_operators = {}
    self.failed_attempts = 0
end

function Terminal:pick_operator(model)
    self.current_operator = model.pick_random_operator(self.tried_operators)
    self.current_attempts = 0
    self.tried_operators = self.tried_operators or {}
    if self.current_operator then
        self.tried_operators[self.current_operator] = true
    end
end

function Terminal:register_success(model)
    self.state = "registered"
    self.next_event_time = model.simulation_time + love.math.random(1, 10)
    -- Metrics (on every successful registration)
    model.min_failed_attempts = math.min(model.min_failed_attempts, self.failed_attempts)
    model.max_failed_attempts = math.max(model.max_failed_attempts, self.failed_attempts)
    model.total_failed_attempts = model.total_failed_attempts + self.failed_attempts
    model.total_registrations = model.total_registrations + 1
    local op = self.current_operator
    model.op_failed_min[op] = math.min(model.op_failed_min[op], self.failed_attempts)
    model.op_failed_max[op] = math.max(model.op_failed_max[op], self.failed_attempts)
    model.op_failed_total[op] = model.op_failed_total[op] + self.failed_attempts
    model.op_registrations[op] = model.op_registrations[op] + 1
    model.failed_histogram[self.failed_attempts] = (model.failed_histogram[self.failed_attempts] or 0) + 1
    self:reset_attempts()
end

function Terminal:register_failure(model)
    self.failed_attempts = self.failed_attempts + 1
    if self.current_attempts < model.REGISTRATION_ATTEMPTS then
        self.next_event_time = model.simulation_time + model.TERMINAL_START_INTERVAL
    else
        local new_op = model.pick_random_operator(self.tried_operators)
        if new_op then
            self.current_operator = new_op
            self.current_attempts = 0
            self.tried_operators[new_op] = true
            self.next_event_time = model.simulation_time + model.TERMINAL_START_INTERVAL
        else
            self:reset_attempts()
            self.next_event_time = model.simulation_time + model.TERMINAL_START_INTERVAL
        end
    end
end

function Terminal:threshold_failure(model)
    self.failed_attempts = self.failed_attempts + 1
    local new_op = model.pick_random_operator(self.tried_operators)
    if new_op then
        self.current_operator = new_op
        self.current_attempts = 0
        self.tried_operators[new_op] = true
        self.next_event_time = model.simulation_time + model.TERMINAL_START_INTERVAL
    else
        self:reset_attempts()
        self.next_event_time = model.simulation_time + model.TERMINAL_START_INTERVAL
    end
end

function Terminal:unregister(model)
    if self.registered_operator then
        model.operators[self.registered_operator].registered = model.operators[self.registered_operator].registered - 1
        self.registered_operator = nil
    end
    self.state = "unregistered"
    self.next_event_time = model.simulation_time + love.math.random(1, 10)
end

return Terminal 