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
---@field Events? table<string, Compost.BinEvent> A table of events this component defines and announces. This is just a convention you can use, though, as BinEvents can be defined anywhere in your codebase, not just in components.
local ComponentSharedMethods = {}

---@class Compost.BinEvent
---@field name string The name of the event, mainly for debugging purposes
---@field reducer fun(accumulator: any, value: unknown, index: integer, component: table): any A reducer function, used for events for which listeners return values. You can use a function from `compost.reducers` or write your own. Default is `compost.reducers.none`.
local BinEvent = {}
local BinEventMT = {__index = BinEvent, __tostring = function(self) return self.name end}

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
--- return compost.component(Position)
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
    for key, value in pairs(ComponentSharedMethods) do
        component[key] = component[key] == nil and value or component[key]
    end
    component[META_KEY] = {__index = component}
    return component
end
compost.component = compost.createComponent

--- ### Component:addBinListener(event)
--- A shortcut for:
--- ```
--- self.Bin.addListener(event, Component)
--- ```
--- 
--- Example usage:
--- ```lua
--- function Sound:init()
---     self:addBinListener(DamageEvent)
--- end
--- 
--- Sound[DamageEvent] = function(self)
---    -- play hurt sound
--- end
--- 
--- -- or:
--- 
--- function Sound:playDamaged()
---   -- play hurt sound
--- end
--- Sound[DamageEvent] = Sound.playDamaged
--- ```
---@param event Compost.BinEvent
function ComponentSharedMethods:addBinListener(event)
    return self.Bin:addListener(event, self[META_KEY].__index --[[this is how you get the component definition table from an instance lol]])
end

------------------------------------------------------------

--- ### compost.newBin()
--- Creates a new empty Bin with no components.
---@return Compost.Bin
function compost.newBin()
    local bin = {
        [EVENTS_KEY] = {},
    }
    return setmetatable(bin, BinMT)
end

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
    for event in pairs(events) do
        self:removeListener(event, component)
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

--- ### Bin:addListener(event, component)
--- Attaches the component as a listener to an event (assuming the function for the listener is defined in the component).
--- 
--- Example usage:
--- ```
--- function SoundComponent:init()
---     -- Attach the listener each time the component is added to a bin
---     self.Bin:addListener(DamageEvent, SoundComponent)
--- end
--- 
--- SoundComponent[DamageEvent] = function(self) -- Define the listener
---     -- play hurt sound
--- end
--- 
--- -- or:
--- 
--- function SoundComponent:playDamaged()
---    -- play hurt sound
--- end
--- SoundComponent[DamageEvent] = SoundComponent.playDamaged -- Define the listener
--- ```
---@param event Compost.BinEvent
---@param component Compost.Component
function Bin:addListener(event, component)
    if event == nil then return error("bad argument #1 to 'Bin:addListener' (event is nil)") end

    local events = self[EVENTS_KEY]
    if not events[event] then events[event] = {} end

    local listeners = events[event]

    for listenerIndex = 1, #listeners do
        if listeners[listenerIndex] == component then return error("Component '" .. tostring(component) .. "' is already attached as a listener for event '" .. tostring(event) .. "'") end
    end

    listeners[#listeners+1] = component
end

--- ### Bin:removeListener(event, component)
--- Removes a listener from an event. Does nothing if the listener is not present or if the event doesn't exist.
---@param event Compost.BinEvent
---@param component Compost.Component
function Bin:removeListener(event, component)
    local events = self[EVENTS_KEY]
    if not events[event] then return end

    local listeners = events[event]
    for listenerIndex = 1, #listeners do
        local listener = listeners[listenerIndex]

        if listener == component then
            table.remove(listeners, listenerIndex)
            return
        end
    end
end

--- ### Bin:announce(event, ...)
--- Announces an event with the given arguments.  
--- If the event has a reducer function set, the reduced results from the listeners will be returned.
---@param event Compost.BinEvent
---@param ... unknown
function Bin:announce(event, ...)
    return event:announce(self, ...)
end

------------------------------------------------------------

--- ### compost.newEvent()
--- Creates a new bin event object.  
--- 
--- Example usage:
--- ```
--- HealthComponent.Events = {
---     GetHealth = compost.newBinEvent(),
---     Damage = compost.newBinEvent(),
---     Death = compost.newBinEvent(),
---     Heal = compost.newBinEvent(),
--- }
--- ```
---@param reducer? fun(accumulator: any, value: unknown, index: integer, component: table): any
---@return Compost.BinEvent
function compost.newEvent(reducer)
    ---@type Compost.BinEvent
    local event = {
        name = "Unnamed Event",
        reducer = reducer or compost.reducers.none,
    }
    return setmetatable(event, BinEventMT)
end
compost.newBinEvent = compost.newEvent

--- ### BinEvent:setName(name)
--- Sets the name of the event, mainly used for debugging purposes.
function BinEvent:setName(name)
    self.name = name
    return self
end

--- ### BinEvent:setReducer(reducerFn)
--- Sets the reducer function for the event to collect results from listeners.
--- 
--- The reducer function gets called for each listener, and gets passed:
--- * accumulator - The accumulator value (`nil` on the first call)
--- * value - The value returned by the listener
--- * index - The index of the listener in the list
--- * component - The component of the listener
--- 
--- The return value of the reducer will be the value of the accumulator for the next call. The final accumulator value is returned by this function.  
--- 
--- Useful reducer functions can be found in `compost.reducers`. If you write your own reducer, it should return the same value no matter which order the listeners are in.
---@param reducerFn fun(accumulator: any, value: unknown, index: integer, component: table): any
---@return Compost.BinEvent self
function BinEvent:setReducer(reducerFn)
    self.reducer = reducerFn
    return self
end

--- ### BinEvent:announce(bin, ...)
--- Announces the event to the listeners in the bin. This is called automatically by the bin.  
--- 
--- It is possible to override this function for an event to change its behavior, but that's mostly for advanced usage. Regular events should be fine for most cases.
---@param bin Compost.Bin
---@param ... unknown
---@return unknown
function BinEvent:announce(bin, ...)
    local events = bin[EVENTS_KEY]
    if not events[self] then return nil end

    local reducerFn = self.reducer
    local accumulator

    local listeners = events[self]
    for listenerIndex = 1, #listeners do
        local component = listeners[listenerIndex]

        if not bin[component] then error("[Error in listener] Couldn't announce event, component '" .. tostring(component) .. "' is set as a listener but isn't attached to the bin", 2) end
        if not bin[component][self] then error("[Error in listener] Couldn't announce event, listening component '" .. tostring(component) .. "' doesn't define a listener function for the event '" .. tostring(self) .. "'", 2) end

        local receivedValue = bin[component][self](bin[component], ...)
        accumulator = reducerFn(accumulator, receivedValue, listenerIndex, bin[component])
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