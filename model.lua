local M = {}
local Terminal = require "terminal"

-- Simulation state
M.NUM_TERMINALS = 100
M.OPERATOR_THRESHOLDS = {0.5, 0.3, 0.2}
M.gap_up = 0.02
M.gap_down = 0.00
M.REGISTRATION_ATTEMPTS = 4

M.operators = {}
-- M.terminals is a list of Terminal objects (see terminal.lua)
M.terminals = {}
M.next_terminal_index = 1
M.simulation_time = 0
M.operator_open = {true, true, true}
M.failed_histogram = {}
M.min_failed_attempts = math.huge
M.max_failed_attempts = 0
M.total_failed_attempts = 0
M.total_registrations = 0
M.op_failed_min = {math.huge, math.huge, math.huge}
M.op_failed_max = {0, 0, 0}
M.op_failed_total = {0, 0, 0}
M.op_registrations = {0, 0, 0}
M.simulation_paused = true
M.TERMINAL_START_INTERVAL = 1
M.step_result_message = nil

function M.init()
    for i = 1, 3 do
        M.operators[i] = {
            registered = 0,
            threshold = math.floor(M.OPERATOR_THRESHOLDS[i] * M.NUM_TERMINALS),
        }
    end
    M.terminals = {}
    M.next_terminal_index = 1
    M.simulation_time = 0
    M.operator_open = {true, true, true}
    M.failed_histogram = {}
    M.min_failed_attempts = math.huge
    M.max_failed_attempts = 0
    M.total_failed_attempts = 0
    M.total_registrations = 0
    M.op_failed_min = {math.huge, math.huge, math.huge}
    M.op_failed_max = {0, 0, 0}
    M.op_failed_total = {0, 0, 0}
    M.op_registrations = {0, 0, 0}
    M.simulation_paused = true
    M.TERMINAL_START_INTERVAL = 1
    M.step_result_message = nil
end

function M.update_operator_hysteresis()
    local total_registered = 0
    for i = 1, #M.operators do
        total_registered = total_registered + M.operators[i].registered
    end
    for i = 1, #M.operators do
        local current_percent = 0
        if total_registered > 0 then
            current_percent = (M.operators[i].registered / total_registered)
        end
        if M.operator_open[i] then
            if current_percent > (M.OPERATOR_THRESHOLDS[i] + M.gap_up) then
                M.operator_open[i] = false
            end
        else
            if current_percent < (M.OPERATOR_THRESHOLDS[i] - M.gap_down) then
                M.operator_open[i] = true
            end
        end
    end
end

function M.can_register_in_operator(op_index)
    M.update_operator_hysteresis()
    -- If any operator is open, use normal logic
    local any_open = false
    for i = 1, #M.operators do
        if M.operator_open[i] then
            any_open = true
            break
        end
    end
    if any_open then
        return M.operator_open[op_index]
    else
        -- All closed: allow registration if below threshold + gap_up
        local total_registered = 0
        for i = 1, #M.operators do
            total_registered = total_registered + M.operators[i].registered
        end
        local current_percent = 0
        if total_registered > 0 then
            current_percent = (M.operators[op_index].registered / total_registered)
        end
        return current_percent < (M.OPERATOR_THRESHOLDS[op_index] + M.gap_up)
    end
end

function M.pick_random_operator(exclude)
    local choices = {}
    for i = 1, #M.operators do
        if not exclude or not exclude[i] then
            table.insert(choices, i)
        end
    end
    if #choices == 0 then return nil end
    return choices[love.math.random(1, #choices)]
end

function M.operator_register(terminal, op_index)
    local op = M.operators[op_index]
    if op.registered < op.threshold then
        if terminal.registered_operator then
            M.operators[terminal.registered_operator].registered = M.operators[terminal.registered_operator].registered - 1
        end
        op.registered = op.registered + 1
        terminal.registered_operator = op_index
        terminal.last_reregister = M.simulation_time
        return true
    end
    return false
end

return M 