-- LÖVE2D Mobile Terminal Registration Simulation
-- https://love2d.org/wiki/Main_Page

love.window.setMode(600, 1200, {resizable=true})

local NUM_TERMINALS = 1000
local OPERATOR_THRESHOLDS = {0.5, 0.3, 0.2} -- 50%, 30%, 20%
local OPERATOR_COLORS = {
    {0.2, 0.8, 0.2}, -- green
    {0.2, 0.2, 0.8}, -- blue
    {0.8, 0.8, 0.2}, -- yellow
}
local BAR_WIDTH = 120
local BAR_GAP = 60
local BAR_HEIGHT = 400
local REREGISTER_PERIOD = 10 -- seconds
local REGISTRATION_ATTEMPTS = 3
local TERMINAL_START_INTERVAL = 1 -- seconds
local gap_up = 0.05 -- 5% for closing
local gap_down = 0    -- 0% for opening

local operators = {}
local terminals = {}
local time_since_last_terminal = 0
local next_terminal_index = 1
local simulation_time = 0

-- Add a table to track recent reregistration events for visualization
local rereg_flash = {0, 0, 0} -- one per operator
local FLASH_DURATION = 0.3 -- seconds

-- Metrics for failed registration attempts
local min_failed_attempts = math.huge
local max_failed_attempts = 0
local total_failed_attempts = 0
local total_registrations = 0

-- Per-operator metrics
local op_failed_min = {math.huge, math.huge, math.huge}
local op_failed_max = {0, 0, 0}
local op_failed_total = {0, 0, 0}
local op_registrations = {0, 0, 0}

-- Histogram of failed attempts (successful registrations)
local failed_histogram = {}

local simulation_paused = true

local operator_open = {true, true, true} -- one per operator

local step_requested = false
local step_result_message = nil

local function update_operator_hysteresis()
    local total_registered = 0
    for i = 1, #operators do
        total_registered = total_registered + operators[i].registered
    end
    for i = 1, #operators do
        local current_percent = 0
        if total_registered > 0 then
            current_percent = (operators[i].registered / total_registered)
        end
        if operator_open[i] then
            -- Close if at or above threshold + gap_up
            if current_percent >= (OPERATOR_THRESHOLDS[i] + gap_up) then
                operator_open[i] = false
            end
        else
            -- Open if below threshold - gap_down
            if current_percent < (OPERATOR_THRESHOLDS[i] - gap_down) then
                operator_open[i] = true
            end
        end
    end
end

function love.load()
    for i = 1, 3 do
        operators[i] = {
            registered = 0,
            threshold = math.floor(OPERATOR_THRESHOLDS[i] * NUM_TERMINALS),
        }
    end
end

local function operator_register(terminal, op_index)
    local op = operators[op_index]
    if op.registered < op.threshold then
        if terminal.registered_operator then
            operators[terminal.registered_operator].registered = operators[terminal.registered_operator].registered - 1
        end
        op.registered = op.registered + 1
        terminal.registered_operator = op_index
        terminal.last_reregister = simulation_time
        return true
    end
    return false
end

local function can_register_in_operator(op_index)
    update_operator_hysteresis()
    return operator_open[op_index]
end

local function pick_random_operator(exclude)
    local choices = {}
    for i = 1, #operators do
        if not exclude or not exclude[i] then
            table.insert(choices, i)
        end
    end
    if #choices == 0 then return nil end
    return choices[love.math.random(1, #choices)]
end

function love.keypressed(key)
    if key == "space" then
        simulation_paused = not simulation_paused
    end
end

function love.update(dt)
    if simulation_paused and not step_requested then
        return
    end
    step_requested = false
    simulation_time = simulation_time + dt
    -- If step requested and paused, force next terminal registration and process one registration update
    if simulation_paused and next_terminal_index <= NUM_TERMINALS then
        local terminal = {
            id = next_terminal_index,
            registered_operator = nil,
            last_reregister = simulation_time,
            state = "unregistered",
            next_event_time = simulation_time + love.math.random(1, 10),
            current_operator = nil,
            current_attempts = 0,
            tried_operators = {},
            failed_attempts = 0,
        }
        terminals[next_terminal_index] = terminal
        next_terminal_index = next_terminal_index + 1
        -- Process registration for this terminal immediately
        local attempts = 0
        local op = nil
        while terminal.state == "unregistered" do
            if not terminal.current_operator then
                terminal.current_operator = pick_random_operator()
                terminal.current_attempts = 0
                terminal.tried_operators = {}
                terminal.tried_operators[terminal.current_operator] = true
            end
            terminal.current_attempts = terminal.current_attempts + 1
            attempts = attempts + 1
            if can_register_in_operator(terminal.current_operator) then
                if operator_register(terminal, terminal.current_operator) then
                    terminal.state = "registered"
                    op = terminal.current_operator
                    break
                else
                    terminal.failed_attempts = terminal.failed_attempts + 1
                    if terminal.current_attempts < REGISTRATION_ATTEMPTS then
                        -- Try again with the same operator
                    else
                        local new_op = pick_random_operator(terminal.tried_operators)
                        if new_op then
                            terminal.current_operator = new_op
                            terminal.current_attempts = 0
                            terminal.tried_operators[new_op] = true
                        else
                            terminal.current_operator = nil
                            terminal.current_attempts = 0
                            terminal.tried_operators = {}
                        end
                    end
                end
            else
                terminal.failed_attempts = terminal.failed_attempts + 1
                local new_op = pick_random_operator(terminal.tried_operators)
                if new_op then
                    terminal.current_operator = new_op
                    terminal.current_attempts = 0
                    terminal.tried_operators[new_op] = true
                else
                    terminal.current_operator = nil
                    terminal.current_attempts = 0
                    terminal.tried_operators = {}
                end
            end
        end
        -- Show result message (persist until next step or unpause)
        step_result_message = string.format("Terminal %d registered to Op%d after %d attempts", terminal.id, op or 0, attempts)
        -- Metrics (on every successful registration)
        min_failed_attempts = math.min(min_failed_attempts, terminal.failed_attempts)
        max_failed_attempts = math.max(max_failed_attempts, terminal.failed_attempts)
        total_failed_attempts = total_failed_attempts + terminal.failed_attempts
        total_registrations = total_registrations + 1
        local opidx = op or 1
        op_failed_min[opidx] = math.min(op_failed_min[opidx], terminal.failed_attempts)
        op_failed_max[opidx] = math.max(op_failed_max[opidx], terminal.failed_attempts)
        op_failed_total[opidx] = op_failed_total[opidx] + terminal.failed_attempts
        op_registrations[opidx] = op_registrations[opidx] + 1
        failed_histogram[terminal.failed_attempts] = (failed_histogram[terminal.failed_attempts] or 0) + 1
        terminal.current_operator = nil
        terminal.current_attempts = 0
        terminal.tried_operators = {}
        terminal.failed_attempts = 0
    elseif not simulation_paused and next_terminal_index <= NUM_TERMINALS then
        time_since_last_terminal = time_since_last_terminal + dt
        if time_since_last_terminal >= TERMINAL_START_INTERVAL then
            local terminal = {
                id = next_terminal_index,
                registered_operator = nil,
                last_reregister = simulation_time,
                state = "unregistered",
                next_event_time = simulation_time + love.math.random(1, 10),
                current_operator = nil,
                current_attempts = 0,
                tried_operators = {},
                failed_attempts = 0,
            }
            terminals[next_terminal_index] = terminal
            next_terminal_index = next_terminal_index + 1
            time_since_last_terminal = time_since_last_terminal - TERMINAL_START_INTERVAL
        end
    end
    -- Handle terminal state transitions
    for _, terminal in ipairs(terminals) do
        if simulation_time >= (terminal.next_event_time or 0) then
            if terminal.state == "unregistered" then
                if not terminal.current_operator then
                    terminal.current_operator = pick_random_operator()
                    terminal.current_attempts = 0
                    terminal.tried_operators = {}
                    terminal.tried_operators[terminal.current_operator] = true
                end
                terminal.current_attempts = terminal.current_attempts + 1
                if can_register_in_operator(terminal.current_operator) then
                    if operator_register(terminal, terminal.current_operator) then
                        -- Registration succeeded
                        terminal.state = "registered"
                        terminal.next_event_time = simulation_time + love.math.random(1, 10)
                        -- Metrics (on every successful registration)
                        min_failed_attempts = math.min(min_failed_attempts, terminal.failed_attempts)
                        max_failed_attempts = math.max(max_failed_attempts, terminal.failed_attempts)
                        total_failed_attempts = total_failed_attempts + terminal.failed_attempts
                        total_registrations = total_registrations + 1
                        -- Per-operator metrics
                        local op = terminal.current_operator
                        op_failed_min[op] = math.min(op_failed_min[op], terminal.failed_attempts)
                        op_failed_max[op] = math.max(op_failed_max[op], terminal.failed_attempts)
                        op_failed_total[op] = op_failed_total[op] + terminal.failed_attempts
                        op_registrations[op] = op_registrations[op] + 1
                        -- Histogram
                        failed_histogram[terminal.failed_attempts] = (failed_histogram[terminal.failed_attempts] or 0) + 1
                        -- Reset for next cycle
                        terminal.current_operator = nil
                        terminal.current_attempts = 0
                        terminal.tried_operators = {}
                        terminal.failed_attempts = 0
                    else
                        -- Registration failed due to quota
                        terminal.failed_attempts = terminal.failed_attempts + 1
                        if terminal.current_attempts < REGISTRATION_ATTEMPTS then
                            -- Try again with the same operator after interval
                            terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                        else
                            -- Pick a new operator not tried yet
                            local new_op = pick_random_operator(terminal.tried_operators)
                            if new_op then
                                terminal.current_operator = new_op
                                terminal.current_attempts = 0
                                terminal.tried_operators[new_op] = true
                                terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                            else
                                -- All operators tried, reset and try again
                                terminal.current_operator = nil
                                terminal.current_attempts = 0
                                terminal.tried_operators = {}
                                terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                            end
                        end
                    end
                else
                    -- Registration failed due to threshold
                    terminal.failed_attempts = terminal.failed_attempts + 1
                    -- Operator is at/over threshold, pick a new one
                    local new_op = pick_random_operator(terminal.tried_operators)
                    if new_op then
                        terminal.current_operator = new_op
                        terminal.current_attempts = 0
                        terminal.tried_operators[new_op] = true
                        terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                    else
                        -- All operators tried, reset and try again
                        terminal.current_operator = nil
                        terminal.current_attempts = 0
                        terminal.tried_operators = {}
                        terminal.next_event_time = simulation_time + TERMINAL_START_INTERVAL
                    end
                end
            elseif terminal.state == "registered" then
                -- Unregister
                if terminal.registered_operator then
                    operators[terminal.registered_operator].registered = operators[terminal.registered_operator].registered - 1
                    terminal.registered_operator = nil
                end
                terminal.state = "unregistered"
                terminal.next_event_time = simulation_time + love.math.random(1, 10)
            end
        end
    end
    -- Update operator hysteresis
    update_operator_hysteresis()
end

function love.mousepressed(x, y, button)
    if button == 1 then
        local win_w = love.graphics.getWidth()
        local win_h = love.graphics.getHeight()
        local total_bar_width = (#operators) * BAR_WIDTH + (#operators-1) * BAR_GAP
        local START_X = math.floor((win_w - total_bar_width) / 2)
        local START_Y = math.floor(win_h * 0.7)
        local hist_y = START_Y + 60
        local hist_bar_h = 80
        local bar_bottom = hist_y + hist_bar_h + 60
        local btn_y = bar_bottom + 40
        local btn_w = 80
        local btn_h = 40
        local center_x = START_X + total_bar_width/2
        -- Pause/Resume button
        if x >= center_x - btn_w/2 and x <= center_x + btn_w/2 and y >= btn_y and y <= btn_y + btn_h then
            simulation_paused = not simulation_paused
        end
        -- Step button (right of pause)
        if simulation_paused and x >= center_x + btn_w/2 + 20 and x <= center_x + btn_w/2 + 20 + btn_w and y >= btn_y and y <= btn_y + btn_h then
            step_requested = true
        end
        -- Slower button (left)
        if x >= center_x - 120 - btn_w/2 and x <= center_x - 120 + btn_w/2 and y >= btn_y and y <= btn_y + btn_h then
            TERMINAL_START_INTERVAL = TERMINAL_START_INTERVAL * 2
        end
        -- Faster button (further right)
        if x >= center_x + 240 - btn_w/2 and x <= center_x + 240 + btn_w/2 and y >= btn_y and y <= btn_y + btn_h then
            TERMINAL_START_INTERVAL = math.max(0.01, TERMINAL_START_INTERVAL / 2)
        end
    end
end

function love.draw()
    local win_w = love.graphics.getWidth()
    local win_h = love.graphics.getHeight()
    -- Dynamically center operator bars
    local total_bar_width = (#operators) * BAR_WIDTH + (#operators-1) * BAR_GAP
    local START_X = math.floor((win_w - total_bar_width) / 2)
    local START_Y = math.floor(win_h * 0.7)
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Mobile Terminal Registration Simulation", START_X, 30)
    love.graphics.print(string.format("Time: %.1fs", simulation_time), START_X, 60)
    love.graphics.print(string.format("Terminals started: %d / %d", next_terminal_index-1, NUM_TERMINALS), START_X, 90)
    love.graphics.print(string.format("Current registration interval: %.2fs", TERMINAL_START_INTERVAL), START_X, 110)
    -- Show registration metrics
    local avg_failed = total_registrations > 0 and (total_failed_attempts / total_registrations) or 0
    love.graphics.print(string.format("Failed registration attempts: min=%d, max=%d, avg=%.2f", min_failed_attempts < math.huge and min_failed_attempts or 0, max_failed_attempts, avg_failed), START_X, 130)
    -- 1. Ongoing failed attempts (only those actively trying to register)
    local ongoing_failed = 0
    local ongoing_unregistered = 0
    for _, t in ipairs(terminals) do
        if t.state == "unregistered" and (t.current_operator ~= nil) then
            ongoing_failed = ongoing_failed + t.failed_attempts
            ongoing_unregistered = ongoing_unregistered + 1
        end
    end
    love.graphics.print(string.format("Ongoing failed attempts (actively trying): %d", ongoing_failed), START_X, 150)
    love.graphics.print(string.format("Unregistered terminals (actively trying): %d", ongoing_unregistered), START_X, 170)
    -- 2. Per-operator metrics
    local y = 190
    for i = 1, #operators do
        local op_avg = op_registrations[i] > 0 and (op_failed_total[i] / op_registrations[i]) or 0
        love.graphics.print(string.format("Op%d: min=%d, max=%d, avg=%.2f, regs=%d", i, op_failed_min[i] < math.huge and op_failed_min[i] or 0, op_failed_max[i], op_avg, op_registrations[i]), START_X, y)
        y = y + 20
    end
    -- 3. Draw operator bars as before
    for i, op in ipairs(operators) do
        local x = START_X + (i-1)*(BAR_WIDTH+BAR_GAP)
        local ybar = START_Y
        local h = BAR_HEIGHT -- all bars same height
        local total_registered = 0
        for j = 1, #operators do
            total_registered = total_registered + operators[j].registered
        end
        local current_percent = 0
        if total_registered > 0 then
            current_percent = (op.registered / total_registered)
        end
        -- Fill bar up to current distribution percent
        local fill_h = h * current_percent
        if operator_open[i] then
            love.graphics.setColor(0.2, 0.8, 0.2) -- green for open
        else
            love.graphics.setColor(0.9, 0.2, 0.2) -- red for closed
        end
        love.graphics.rectangle("fill", x, ybar-h+ (h-fill_h), BAR_WIDTH, fill_h)
        -- Draw bar border
        love.graphics.setColor(OPERATOR_COLORS[i])
        love.graphics.rectangle("line", x, ybar-h, BAR_WIDTH, h)
        -- Draw threshold line
        local threshold_y = ybar - h + h * (1 - OPERATOR_THRESHOLDS[i])
        love.graphics.setColor(1, 1, 0)
        love.graphics.line(x, threshold_y, x+BAR_WIDTH, threshold_y)
        -- Draw hysteresis band line depending on open/closed state
        if operator_open[i] then
            -- Draw line at threshold+gap_up
            local y_gap = ybar - h + h * (1 - (OPERATOR_THRESHOLDS[i] + gap_up))
            love.graphics.setColor(0, 1, 1)
            love.graphics.line(x, y_gap, x+BAR_WIDTH, y_gap)
        else
            -- Draw line at threshold-gap_down
            local y_gap = ybar - h + h * (1 - (OPERATOR_THRESHOLDS[i] - gap_down))
            love.graphics.setColor(1, 0, 1)
            love.graphics.line(x, y_gap, x+BAR_WIDTH, y_gap)
        end
        -- Draw text in white
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Op%d", i), x+BAR_WIDTH/2-18, ybar+10)
        love.graphics.print(string.format("%d/%d", op.registered, op.threshold), x+BAR_WIDTH/2-30, ybar-h-30)
        love.graphics.print(
            string.format("%d (%.1f%%)", op.registered, current_percent*100),
            x + BAR_WIDTH/2 - 35, ybar - h - 50
        )
    end
    -- 4. Histogram of failed attempts (draw as bars under operator bars)
    local hist_x = START_X
    local hist_y = START_Y + 60
    local hist_bar_w = 20
    local hist_bar_h = 80
    local max_hist = 0
    for k, v in pairs(failed_histogram) do if v > max_hist then max_hist = v end end
    if max_hist > 0 then
        love.graphics.setColor(0.7, 0.7, 1)
        for i = 0, 20 do
            local count = failed_histogram[i] or 0
            local bar_height = (count / max_hist) * hist_bar_h
            love.graphics.rectangle("fill", hist_x + i * (hist_bar_w + 2), hist_y + hist_bar_h - bar_height, hist_bar_w, bar_height)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(tostring(i), hist_x + i * (hist_bar_w + 2), hist_y + hist_bar_h + 2)
            love.graphics.setColor(0.7, 0.7, 1)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Histogram: failed attempts (bar height = count)", hist_x, hist_y - 18)
    end
    -- 5. Button controls below bars
    local bar_bottom = hist_y + hist_bar_h + 60
    local btn_y = bar_bottom + 40
    local btn_w = 80
    local btn_h = 40
    local center_x = START_X + total_bar_width/2
    -- Pause/Resume button
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("fill", center_x - btn_w/2, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", center_x - btn_w/2, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.printf(simulation_paused and "Start" or "Pause", center_x - btn_w/2, btn_y + 10, btn_w, "center")
    -- Step button (right of pause)
    if simulation_paused then
        love.graphics.setColor(0.3, 0.3, 0.3)
    else
        love.graphics.setColor(0.15, 0.15, 0.15)
    end
    love.graphics.rectangle("fill", center_x + btn_w/2 + 20, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", center_x + btn_w/2 + 20, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.printf("Step", center_x + btn_w/2 + 20, btn_y + 10, btn_w, "center")
    -- Slower button (left)
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("fill", center_x - 120 - btn_w/2, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", center_x - 120 - btn_w/2, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.printf("Slower", center_x - 120 - btn_w/2, btn_y + 10, btn_w, "center")
    -- Faster button (further right)
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("fill", center_x + 240 - btn_w/2, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", center_x + 240 - btn_w/2, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.printf("Faster", center_x + 240 - btn_w/2, btn_y + 10, btn_w, "center")
    -- Show step result message under histogram if present
    if step_result_message then
        local msg_y = hist_y + hist_bar_h + 20
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", hist_x, msg_y, 500, 30)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(step_result_message, hist_x + 10, msg_y + 7)
    end
end 