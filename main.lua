-- LÖVE2D Mobile Terminal Registration Simulation
-- https://love2d.org/wiki/Main_Page

local model = require "model"
local view = require "view"
local controller = require "controller"

love.window.setMode(600, 1200, {resizable=true})

function love.load()
    model.init()
end

function love.update(dt)
    if controller.update then
        controller.update(dt, model, view)
    end
end

function love.draw()
    view.draw(model, controller)
end

function love.mousepressed(x, y, button)
    controller.mousepressed(x, y, button, model, view)
end

function love.keypressed(key)
    controller.keypressed(key, model, view)
end 