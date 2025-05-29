local C = {}
local Terminal = require "terminal"

local function handlePause(x, y, btn_y, btn_w, btn_h, center_x, model)
    if x >= center_x - btn_w/2 and x <= center_x + btn_w/2 and y >= btn_y and y <= btn_y + btn_h then
        model.simulation_paused = not model.simulation_paused
        if not model.simulation_paused then
            model.step_result_message = nil
        end
        return true
    end
    return false
end

local function handleStep(x, y, btn_y, btn_w, btn_h, center_x, model)
    if model.simulation_paused and x >= center_x + btn_w/2 + 20 and x <= center_x + btn_w/2 + 20 + btn_w and y >= btn_y and y <= btn_y + btn_h then
        model._step_requested = true
        return true
    end
    return false
end

local function handleSpeed(x, y, btn_y, btn_w, btn_h, center_x, model)
    -- Slower button (left)
    if x >= center_x - 120 - btn_w/2 and x <= center_x - 120 + btn_w/2 and y >= btn_y and y <= btn_y + btn_h then
        model.TERMINAL_START_INTERVAL = model.TERMINAL_START_INTERVAL * 2
        return true
    end
    -- Faster button (further right)
    if x >= center_x + 240 - btn_w/2 and x <= center_x + 240 + btn_w/2 and y >= btn_y and y <= btn_y + btn_h then
        model.TERMINAL_START_INTERVAL = math.max(0.01, model.TERMINAL_START_INTERVAL / 2)
        return true
    end
    return false
end

local function get_button_positions()
    local btn_w = 80
    local btn_h = 40
    local spacing = 20
    local num_buttons = 4
    local win_w = love.graphics.getWidth()
    local win_h = love.graphics.getHeight()
    local BAR_WIDTH = 120
    local BAR_GAP = 60
    local BAR_HEIGHT = 400
    local total_bar_width = 3 * BAR_WIDTH + 2 * BAR_GAP
    local START_X = math.floor((win_w - total_bar_width) / 2)
    local START_Y = math.floor(win_h * 0.7)
    local hist_y = START_Y + 60
    local hist_bar_h = 80
    local bar_bottom = hist_y + hist_bar_h + 60
    local btn_y = bar_bottom + 40
    local total_width = num_buttons * btn_w + (num_buttons - 1) * spacing
    local start_x = (win_w - total_width) / 2
    return {
        slower = {x = start_x + 0 * (btn_w + spacing), y = btn_y, w = btn_w, h = btn_h},
        pause  = {x = start_x + 1 * (btn_w + spacing), y = btn_y, w = btn_w, h = btn_h},
        step   = {x = start_x + 2 * (btn_w + spacing), y = btn_y, w = btn_w, h = btn_h},
        faster = {x = start_x + 3 * (btn_w + spacing), y = btn_y, w = btn_w, h = btn_h},
    }
end

function C.mousepressed(x, y, button, model, view)
    if button == 1 then
        local btns = get_button_positions()
        -- Slower
        if x >= btns.slower.x and x <= btns.slower.x + btns.slower.w and y >= btns.slower.y and y <= btns.slower.y + btns.slower.h then
            model.TERMINAL_START_INTERVAL = model.TERMINAL_START_INTERVAL * 2
            return
        end
        -- Pause/Start
        if x >= btns.pause.x and x <= btns.pause.x + btns.pause.w and y >= btns.pause.y and y <= btns.pause.y + btns.pause.h then
            model.simulation_paused = not model.simulation_paused
            if not model.simulation_paused then
                model.step_result_message = nil
            end
            return
        end
        -- Step
        if model.simulation_paused and x >= btns.step.x and x <= btns.step.x + btns.step.w and y >= btns.step.y and y <= btns.step.y + btns.step.h then
            model._step_requested = true
            return
        end
        -- Faster
        if x >= btns.faster.x and x <= btns.faster.x + btns.faster.w and y >= btns.faster.y and y <= btns.faster.y + btns.faster.h then
            model.TERMINAL_START_INTERVAL = math.max(0.01, model.TERMINAL_START_INTERVAL / 2)
            return
        end
    end
end

function C.keypressed(key, model, view)
    if key == "space" then
        model.simulation_paused = not model.simulation_paused
        if not model.simulation_paused then
            model.step_result_message = nil
        end
    end
end

local function handleTerminalRegistration(model)
    local terminal = Terminal.new(model.next_terminal_index, model.simulation_time)
    model.terminals[model.next_terminal_index] = terminal
    model.next_terminal_index = model.next_terminal_index + 1
    -- Process registration for this terminal immediately
    local attempts = 0
    local op = nil
    while terminal.state == "unregistered" do
        if not terminal.current_operator then
            terminal:pick_operator(model)
        end
        terminal.current_attempts = terminal.current_attempts + 1
        attempts = attempts + 1
        if model.can_register_in_operator(terminal.current_operator) then
            if model.operator_register(terminal, terminal.current_operator) then
                terminal:register_success(model)
                op = terminal.current_operator
                break
            else
                terminal:register_failure(model)
            end
        else
            terminal:threshold_failure(model)
        end
    end
    -- Show result message (persist until next step or unpause)
    model.step_result_message = string.format("Terminal %d registered to Op%d after %d attempts", terminal.id, op or 0, attempts)
end

local function handleTerminalStateTransitions(model, dt)
    for _, terminal in ipairs(model.terminals) do
        if model.simulation_time >= (terminal.next_event_time or 0) then
            if terminal.state == "unregistered" then
                if not terminal.current_operator then
                    terminal:pick_operator(model)
                end
                terminal.current_attempts = terminal.current_attempts + 1
                if model.can_register_in_operator(terminal.current_operator) then
                    if model.operator_register(terminal, terminal.current_operator) then
                        terminal:register_success(model)
                    else
                        terminal:register_failure(model)
                    end
                else
                    terminal:threshold_failure(model)
                end
            elseif terminal.state == "registered" then
                terminal:unregister(model)
            end
        end
    end
end

function C.update(dt, model, view)
    if model.simulation_paused and not model._step_requested then
        return
    end
    model._step_requested = false
    model.simulation_time = model.simulation_time + dt
    if model.simulation_paused and model.next_terminal_index <= model.NUM_TERMINALS then
        handleTerminalRegistration(model)
    elseif not model.simulation_paused and model.next_terminal_index <= model.NUM_TERMINALS then
        model._time_since_last_terminal = model._time_since_last_terminal or 0
        model._time_since_last_terminal = model._time_since_last_terminal + dt
        if model._time_since_last_terminal >= model.TERMINAL_START_INTERVAL then
            handleTerminalRegistration(model)
            model._time_since_last_terminal = model._time_since_last_terminal - model.TERMINAL_START_INTERVAL
        end
    end
    handleTerminalStateTransitions(model, dt)
    model.update_operator_hysteresis()
end

return C 