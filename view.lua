local V = {}

local function draw_title_and_time(model, START_X)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Mobile Terminal Registration Simulation", START_X, 30)
    love.graphics.print(string.format("Time: %.1fs", model.simulation_time), START_X, 60)
    love.graphics.print(string.format("Terminals started: %d / %d", model.next_terminal_index-1, model.NUM_TERMINALS), START_X, 90)
    love.graphics.print(string.format("Current registration interval: %.2fs", model.TERMINAL_START_INTERVAL or 1), START_X, 110)
end

local function draw_failed_stats(model, START_X)
    local avg_failed = model.total_registrations > 0 and (model.total_failed_attempts / model.total_registrations) or 0
    love.graphics.print(string.format("Failed registration attempts: min=%d, max=%d, avg=%.2f", model.min_failed_attempts < math.huge and model.min_failed_attempts or 0, model.max_failed_attempts, avg_failed), START_X, 130)
    local ongoing_failed = 0
    local ongoing_unregistered = 0
    for _, t in ipairs(model.terminals) do
        if t.state == "unregistered" and (t.current_operator ~= nil) then
            ongoing_failed = ongoing_failed + t.failed_attempts
            ongoing_unregistered = ongoing_unregistered + 1
        end
    end
    love.graphics.print(string.format("Ongoing failed attempts (actively trying): %d", ongoing_failed), START_X, 150)
    love.graphics.print(string.format("Unregistered terminals (actively trying): %d", ongoing_unregistered), START_X, 170)
end

local function draw_operator_stats(model, START_X)
    local y = 190
    for i = 1, #model.operators do
        local op_avg = model.op_registrations[i] > 0 and (model.op_failed_total[i] / model.op_registrations[i]) or 0
        love.graphics.print(string.format("Op%d: min=%d, max=%d, avg=%.2f, regs=%d", i, model.op_failed_min[i] < math.huge and model.op_failed_min[i] or 0, model.op_failed_max[i], op_avg, model.op_registrations[i]), START_X, y)
        y = y + 20
    end
end

local function draw_operator_bars(model, START_X, START_Y, BAR_WIDTH, BAR_GAP, BAR_HEIGHT, OPERATOR_COLORS)
    for i, op in ipairs(model.operators) do
        local x = START_X + (i-1)*(BAR_WIDTH+BAR_GAP)
        local ybar = START_Y
        local h = BAR_HEIGHT
        local total_registered = 0
        for j = 1, #model.operators do
            total_registered = total_registered + model.operators[j].registered
        end
        local current_percent = 0
        if total_registered > 0 then
            current_percent = (op.registered / total_registered)
        end
        local fill_h = h * current_percent
        if model.operator_open[i] then
            love.graphics.setColor(0.2, 0.8, 0.2)
        else
            love.graphics.setColor(0.9, 0.2, 0.2)
        end
        love.graphics.rectangle("fill", x, ybar-h+ (h-fill_h), BAR_WIDTH, fill_h)
        love.graphics.setColor(OPERATOR_COLORS[i])
        love.graphics.rectangle("line", x, ybar-h, BAR_WIDTH, h)
        local threshold_y = ybar - h + h * (1 - model.OPERATOR_THRESHOLDS[i])
        love.graphics.setColor(1, 1, 0)
        love.graphics.line(x, threshold_y, x+BAR_WIDTH, threshold_y)
        if model.operator_open[i] then
            local y_gap = ybar - h + h * (1 - (model.OPERATOR_THRESHOLDS[i] + model.gap_up))
            love.graphics.setColor(0, 1, 1)
            love.graphics.line(x, y_gap, x+BAR_WIDTH, y_gap)
        else
            local y_gap = ybar - h + h * (1 - (model.OPERATOR_THRESHOLDS[i] - model.gap_down))
            love.graphics.setColor(1, 0, 1)
            love.graphics.line(x, y_gap, x+BAR_WIDTH, y_gap)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(string.format("Op%d", i), x+BAR_WIDTH/2-18, ybar+10)
        love.graphics.print(string.format("%d/%d", op.registered, op.threshold), x+BAR_WIDTH/2-30, ybar-h-30)
        love.graphics.print(
            string.format("%d (%.1f%%)", op.registered, current_percent*100),
            x + BAR_WIDTH/2 - 35, ybar - h - 50
        )
    end
end

local function draw_histogram(model, hist_x, hist_y, hist_bar_w, hist_bar_h)
    local max_hist = 0
    for k, v in pairs(model.failed_histogram) do if v > max_hist then max_hist = v end end
    if max_hist > 0 then
        love.graphics.setColor(0.7, 0.7, 1)
        for i = 0, 20 do
            local count = model.failed_histogram[i] or 0
            local bar_height = (count / max_hist) * hist_bar_h
            love.graphics.rectangle("fill", hist_x + i * (hist_bar_w + 2), hist_y + hist_bar_h - bar_height, hist_bar_w, bar_height)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(tostring(i), hist_x + i * (hist_bar_w + 2), hist_y + hist_bar_h + 2)
            love.graphics.setColor(0.7, 0.7, 1)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Histogram: failed attempts (bar height = count)", hist_x, hist_y - 18)
    end
end

local function draw_step_result_message(model, hist_x, hist_y, hist_bar_h)
    if model.step_result_message then
        local msg_y = hist_y + hist_bar_h + 20
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", hist_x, msg_y, 500, 30)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(model.step_result_message, hist_x + 10, msg_y + 7)
    end
end

local function draw_pause_button(model, center_x, btn_y, btn_w, btn_h)
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("fill", center_x, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", center_x, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.printf(model.simulation_paused and "Start" or "Pause", center_x, btn_y + 10, btn_w, "center")
end

local function draw_step_button(model, center_x, btn_y, btn_w, btn_h)
    if model.simulation_paused then
        love.graphics.setColor(0.3, 0.3, 0.3)
    else
        love.graphics.setColor(0.15, 0.15, 0.15)
    end
    love.graphics.rectangle("fill", center_x, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", center_x, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.printf("Step", center_x, btn_y + 10, btn_w, "center")
end

local function draw_slower_button(center_x, btn_y, btn_w, btn_h)
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("fill", center_x, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", center_x, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.printf("Slower", center_x, btn_y + 10, btn_w, "center")
end

local function draw_faster_button(center_x, btn_y, btn_w, btn_h)
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("fill", center_x, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", center_x, btn_y, btn_w, btn_h, 8, 8)
    love.graphics.printf("Faster", center_x, btn_y + 10, btn_w, "center")
end

local function draw_buttons(model, START_X, total_bar_width, hist_y, hist_bar_h)
    local bar_bottom = hist_y + hist_bar_h + 60
    local btn_y = bar_bottom + 40
    local btn_w = 80
    local btn_h = 40
    local win_w = love.graphics.getWidth()
    -- Arrange all buttons to the left of center, horizontally, with equal spacing
    local num_buttons = 4
    local spacing = 20
    local total_width = num_buttons * btn_w + (num_buttons - 1) * spacing
    local start_x = (win_w - total_width) / 2
    -- Draw buttons in order: Pause, Step, Slower, Faster
    draw_pause_button(model, start_x + 1 * (btn_w + spacing), btn_y, btn_w, btn_h)
    draw_step_button(model, start_x + 2 * (btn_w + spacing), btn_y, btn_w, btn_h)
    draw_slower_button(start_x + 0 * (btn_w + spacing), btn_y, btn_w, btn_h)
    draw_faster_button(start_x + 3 * (btn_w + spacing), btn_y, btn_w, btn_h)
end

function V.draw(model, controller)
    local BAR_WIDTH = 120
    local BAR_GAP = 60
    local BAR_HEIGHT = 400
    local OPERATOR_COLORS = {
        {0.2, 0.8, 0.2},
        {0.2, 0.2, 0.8},
        {0.8, 0.8, 0.2},
    }
    local win_w = love.graphics.getWidth()
    local win_h = love.graphics.getHeight()
    local total_bar_width = (#model.operators) * BAR_WIDTH + (#model.operators-1) * BAR_GAP
    local START_X = math.floor((win_w - total_bar_width) / 2)
    local START_Y = math.floor(win_h * 0.7)
    love.graphics.setBackgroundColor(0.1, 0.1, 0.1)
    draw_title_and_time(model, START_X)
    draw_failed_stats(model, START_X)
    draw_operator_stats(model, START_X)
    draw_operator_bars(model, START_X, START_Y, BAR_WIDTH, BAR_GAP, BAR_HEIGHT, OPERATOR_COLORS)
    local hist_x = START_X
    local hist_y = START_Y + 60
    local hist_bar_w = 20
    local hist_bar_h = 80
    draw_histogram(model, hist_x, hist_y, hist_bar_w, hist_bar_h)
    draw_step_result_message(model, hist_x, hist_y, hist_bar_h)
    draw_buttons(model, START_X, total_bar_width, hist_y, hist_bar_h)
end

return V 