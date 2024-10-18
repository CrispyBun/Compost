local compost = {}

local EVENTS_KEY = {}
local META_KEY = {}

compost.EVENTS_KEY = EVENTS_KEY -- Used to get the list of events from a Bin
compost.META_KEY = META_KEY -- Used to get the metatable of a component used for its instances

------------------------------------------------------------

--- An object holding instanced components  
---@class Compost.Bin
---@field [table] table
local Bin = {}
local BinMT = {__index = Bin}

--- If you're using annotations, your component definitions should inherit from this class
---@class Compost.Component
---@field Bin Compost.Bin The bin this component belongs to
---@field init? fun(...) Called when the component is added to a bin. While it receives constructor arguments, it's recommended to make those optional to allow for easy creation of Bins using templates.
---@field destruct? fun() Called when the component is removed from a bin.
local ComponentBuiltinMethods = {}

------------------------------------------------------------

--- ### Component:addBinListener(event, methodName)
--- A shortcut for:
--- ```
--- self.Bin.addListener(event, ComponentDefinition, methodName)
--- ```
---@param event string
---@param methodName string?
function ComponentBuiltinMethods:addBinListener(event, methodName)
    self.Bin:addListener(event, self[META_KEY].__index, methodName)
end

------------------------------------------------------------

--- ### compost.createComponent(component)  
--- ### compost.component(component)  
--- Turns the table into a compost component and returns it. 
---  
--- Example usage:  
--- #### Position.lua
--- ```
--- local compost = require 'compost'
---
--- local Position = {}
--- Position.x = 0
--- Position.y = 0
---
--- return moss.create(Position)
--- ```
--- ---
--- #### main.lua
--- ```
--- local Position = require 'Position'
--- bin:addComponent(Position)
--- ```
---@generic T : Compost.Component
---@param component T
---@return T
function compost.createComponent(component)
    for key, value in pairs(ComponentBuiltinMethods) do
        component[key] = value
    end
    component[META_KEY] = {__index = component}
    return component
end
compost.component = compost.createComponent

--- ### compost.newBin()
--- Creates a new empty Bin with no components.
---@return Compost.Bin
function compost.newBin()
    local bin = {
        [EVENTS_KEY] = {},
    }
    return setmetatable(bin, BinMT)
end

------------------------------------------------------------

--- ### Bin:addComponent(component)
--- Adds a component to the bin.
---@generic T : Compost.Component
---@param component T
---@param ... unknown Arguments to the component's `init` method
---@return T component
function Bin:addComponent(component, ...)
    ---@type Compost.Component
    local instance = {
        Bin = self,
    }
    setmetatable(instance, component[META_KEY])

    self[component] = instance

    if instance.init then
        instance:init(...)
    end

    return instance
end

--- ### Bin:removeComponent(component)
--- Removes a component from the bin (also removing any of its listeners).
---@param component Compost.Component
function Bin:removeComponent(component)

    local instance = self[component]
    if not instance then return end

    if instance.destruct then
        instance:destruct()
    end

    local events = self[EVENTS_KEY]
    for event, listeners in pairs(events) do
        local listenerIndex = 1
        while listenerIndex <= #listeners do
            local listener = listeners[listenerIndex]
            if listener[1] == component then
                table.remove(listeners, listenerIndex)
            else
                listenerIndex = listenerIndex + 1
            end
        end
    end

    self[component] = nil
    component.Bin = nil
end

--- ### Bin:getComponent(component)
--- Returns the component, or `nil` if it's not present in the bin.
---@generic T : Compost.Component
---@param component T
---@return T? component
function Bin:getComponent(component)
    return self[component]
end

--- ### Bin:forceComponent(component)
--- Gets and returns the component if it's present, or if not, creates and adds it first.
---@generic T : Compost.Component
---@param component T
---@param ... unknown
---@return T component
function Bin:forceComponent(component, ...)
    if self[component] then return self[component] end
    return self:addComponent(component, ...)
end

--- ### Bin:expectComponent(component)
--- Returns the component if it's present, or throws an error if it's not.
---@generic T : Compost.Component
---@param component T
---@return T component
function Bin:expectComponent(component)
    local instance = self[component]
    if not instance then error("The expected component was not found in the bin", 2) end
    return instance
end

--- ### Bin:addListener(event, component, methodName)
--- Adds a listener to an event. The listener is a component in the same bin and a method within it.
--- If the method name isn't specified, it becomes the same as the event name.
--- 
--- Example usage:
--- ```
--- bin:addListener("Health.Damage", Sound, "playDamaged")
--- ```
---@param event string
---@param component Compost.Component
---@param methodName? string
function Bin:addListener(event, component, methodName)
    methodName = methodName or event

    local events = self[EVENTS_KEY]
    if not events[event] then events[event] = {} end

    local listeners = events[event]
    listeners[#listeners+1] = {component, methodName}
end

--- ### Bin:removeListener(event, component, methodName)
--- Removes a listener from an event.
---@param event string
---@param component Compost.Component
---@param methodName? string
function Bin:removeListener(event, component, methodName)
    methodName = methodName or event

    local events = self[EVENTS_KEY]
    if not events[event] then return end

    local listeners = events[event]
    for listenerIndex = 1, #listeners do
        local listener = listeners[listenerIndex]

        if listener[1] == component and listener[2] == methodName then
            table.remove(listeners, listenerIndex)
            return
        end
    end
end

--- ### Bin:announce(event, ...)
--- Announces an event with the given arguments.
---@param event string
---@param ... unknown
function Bin:announce(event, ...)
    return self:announceAndCollect(event, compost.reducers.none, ...)
end

--- ### Bin:announceAndCollect(event, reducerFn, ...)
--- Announces an event with the given arguments, and collects the results from the listeners using a reducer function.
--- 
--- The reducer function gets called for each listener, and gets passed:
--- * accumulator - The accumulator value (`nil` on the first call)
--- * value - The value returned by the listener
--- * index - The index of the listener in the list
--- * component - The component of the listener
--- 
--- The return value of the reducer will be the value of the accumulator for the next call. The final accumulator value is returned by this function.  
--- 
--- Useful reducer functions can be found in `compost.reducers`.
---@param event string
---@param reducerFn fun(accumulator: any, value: unknown, index: integer, component: table): any
---@param ... unknown
---@return unknown
function Bin:announceAndCollect(event, reducerFn, ...)
    local events = self[EVENTS_KEY]
    if not events[event] then return nil end

    local accumulator

    local listeners = events[event]
    for listenerIndex = 1, #listeners do
        local listener = listeners[listenerIndex]
        local component = listener[1]
        local method = listener[2]

        if not self[component] then error("Component '" .. tostring(component) .. "' is set as a listener but isn't attached to the bin", 2) end
        if not self[component][method] then error("Listening method '" .. tostring(method) .. "' doesn't exist in component '" .. tostring(component) .. "'", 2) end

        local out = self[component][method](self[component], ...)
        accumulator = reducerFn(accumulator, out, listenerIndex, self[component])
    end

    return accumulator
end

------------------------------------------------------------

--- Useful reducer functions for use with `Bin:announceAndCollect()`.
compost.reducers = {}

---@return nil
function compost.reducers.none()
    return nil
end

--- Returns all received values as a list (nils are skipped)
---@param accumulator any[]?
---@param value any
function compost.reducers.collectResults(accumulator, value)
    accumulator = accumulator or {}
    accumulator[#accumulator+1] = value
    return accumulator
end

local random = _G["love"] and _G["love"].math.random or math.random
--- Randomly picks a value from the received values to return
---@param accumulator any
---@param value any
---@param index integer
---@return any
function compost.reducers.random(accumulator, value, index)
    if index == 1 then return value end -- Kinda redundant, but adds clarity
    if random() < (1 / index) then return value end
    return accumulator
end

--- Only allows a single listener to be present and return a value. If there are more listeners present, it throws an error.
---@param accumulator any
---@param value any
---@param index integer
---@return any
function compost.reducers.singleListener(accumulator, value, index)
    if index == 1 then return value end
    error("Announcing an event that expects a single listener, but multiple listeners are present", 3)
end

--- Returns the minimum of numerical values
---@param accumulator number?
---@param value number
---@return number
function compost.reducers.min(accumulator, value)
    return math.min(accumulator or value, value)
end

--- Returns the maximum of numerical values
---@param accumulator number?
---@param value number
---@return number
function compost.reducers.max(accumulator, value)
    return math.max(accumulator or value, value)
end

--- Returns the average of numerical values
---@param accumulator number?
---@param value number
---@param index integer
---@return number
function compost.reducers.average(accumulator, value, index)
    accumulator = accumulator or 0
    return (accumulator * (index - 1) + value) / index
end

--- Returns the sum of numerical values
---@param accumulator number?
---@param value number
---@return number
function compost.reducers.sum(accumulator, value)
    return (accumulator or 0) + value
end

------------------------------------------------------------

compost.Bin = Bin -- Bin class exposed for the ability to potentially add more methods

return compost