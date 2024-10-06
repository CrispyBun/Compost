local compost = {}

--- The individual component IDs mapped to their definitions.  
--- You shouldn't edit this table directly, instead use `compost.defineComponent`.
---@type table<string, Compost.ComponentDefinition>
compost.components = {}

local eventsKey = {}
compost.eventsKey = eventsKey -- Used to get the list of events from a Bin

------------------------------------------------------------

--- An object holding instanced components  
--- Fields may be injected into this definition to annotate components based on their names
---@class Compost.Bin
---@field [string] table
local Bin = {}
local BinMT = {__index = Bin}

--- If you're using annotations, your component definitions should inherit from this class
---@class Compost.Component
---@field Bin Compost.Bin The bin this component belongs to
---@field init? fun(...) Called when the component is added to a bin. While it receives constructor arguments, it's recommended to make those optional to allow for easy creation of Bins using templates.
---@field destruct? fun() Called when the component is removed from a bin.

---@class Compost.ComponentDefinition
---@field metatable table The metatable for instances of this component
---@field values table Which table this component definition was made from (this is the table the metatable's `__index` points to)
---@field name any The name of the component within a bin

------------------------------------------------------------

--- ### compost.defineComponent(values, id, name)
--- Defines a new component.  
--- * `values` is the table of methods and fields for the component.
--- * `id` is the identifier of the component, which is used to create and add the component to bins. You can leave this as nil to use the actual `values` table as the ID, which will eliminate any possibility of a name clash in IDs.
--- * `name` is the key of the instanced component within a bin, which is used to refer to it in any way (getting, removing, attaching events, ...). If you want this to be the same as `id`, just leave it as nil.
--- ```
--- local Health = {}
--- Health.value = 100
--- 
--- -- More options depending on your naming scheme, e.g.:
--- 
--- compost.defineComponent(Health, "GameObject.Health", "health")
--- -- Then use `addComponent("GameObject.Health")` to add this component under the key "health"
--- 
--- compost.defineComponent(Health, "GameObject.Health")
--- -- Then use `addComponent("GameObject.Health")` to add this component under the key "GameObject.Health"
--- 
--- compost.defineComponent(Health)
--- -- Then use `addComponent(Health)` to add this component under the key [Health]
--- ```
---@param values table A table of the methods and all fields of the component
---@param id? any The ID of the component used to add it to bins (Defaults to the same as `values`)
---@param name? any The name of the component within a bin (Defaults to the same as `id`)
function compost.defineComponent(values, id, name)
    id = id ~= nil and id or values
    name = name ~= nil and name or id

    if compost.components[id] then error("Component with ID '" .. tostring(id) .. "' already defined", 2) end

    ---@type Compost.ComponentDefinition
    local definition = {
        metatable = {__index = values},
        values = values,
        name = name,
    }

    compost.components[id] = definition
end

--- ### compost.newBin()
--- Creates a new empty Bin with no components.
---@return Compost.Bin
function compost.newBin()
    local bin = {
        [eventsKey] = {},
    }
    return setmetatable(bin, BinMT)
end

------------------------------------------------------------

--- ### Bin:addComponent(componentId)
--- Adds a component to the bin based on its ID.
---@param componentId any The component to instance
---@param ... unknown Arguments to the component's `init` method
---@return table component
function Bin:addComponent(componentId, ...)
    local definition = compost.components[componentId]
    if not definition then error("Component with ID '" .. tostring(componentId) .. "' not found", 2) end

    if self[definition.name] then error("Component with name '" .. tostring(definition.name) .. "' already exists in bin", 2) end

    ---@type Compost.Component
    local instance = {
        Bin = self,
    }

    self[definition.name] = setmetatable(instance, definition.metatable)

    if instance.init then
        instance:init(...)
    end

    return instance
end

--- ### Bin:removeComponent(component)
--- Removes a component from the bin based on its *name*.
---@param componentName any
function Bin:removeComponent(componentName)

    local instance = self[componentName]
    if instance and instance.destruct then
        instance:destruct()
    end

    local events = self[eventsKey]
    for event, listeners in pairs(events) do
        for listenerIndex = 1, #listeners do
            local listener = listeners[listenerIndex]
            if listener[1] == componentName then
                table.remove(listeners, listenerIndex)
            end
        end
    end

    self[componentName] = nil
end

--- ### Bin:getComponent(componentName)
--- Returns the component (based on its name), or `nil` if it's not present in the bin.
---@param componentName any
---@return table?
function Bin:getComponent(componentName)
    return self[componentName]
end

--- ### Bin:forceComponent(componentName, componentId, ...)
--- Gets and returns the component if it's present, or if not, creates and adds it first.
---@param componentName any
---@param componentId any
---@param ... unknown
---@return table component
function Bin:forceComponent(componentName, componentId, ...)
    if self[componentName] then return self[componentName] end
    return self:addComponent(componentId, ...)
end

--- ### Bin:expectComponent(component)
--- Returns the component if it's present, or throws an error if it's not.
---@param componentName string
---@return table
function Bin:expectComponent(componentName)
    local instance = self[componentName]
    if not instance then error("Expected component '" .. tostring(componentName) .. "' but was not found in bin", 2) end
    return instance
end

--- ### Bin:addListener(event, componentName, methodName)
--- Adds a listener to an event. The listener is a component in the same bin and a method within it.
--- 
--- Example usage:
--- ```
--- bin:addListener("health:damage", "sound", "playDamaged")
--- ```
---@param event string
---@param componentName any
---@param methodName string
function Bin:addListener(event, componentName, methodName)
    local events = self[eventsKey]
    if not events[event] then events[event] = {} end

    local listeners = events[event]
    listeners[#listeners+1] = {componentName, methodName}
end

--- ### Bin:removeListener(event, componentName, methodName)
--- Removes a listener from an event.
---@param event string
---@param componentName any
---@param methodName string
function Bin:removeListener(event, componentName, methodName)
    local events = self[eventsKey]
    if not events[event] then return end

    local listeners = events[event]
    for listenerIndex = 1, #listeners do
        local listener = listeners[listenerIndex]

        if listener[1] == componentName and listener[2] == methodName then
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
---@param event string
---@param reducerFn fun(accumulator: any, value: unknown, index: integer, component: table): any
---@param ... unknown
---@return unknown
function Bin:announceAndCollect(event, reducerFn, ...)
    local events = self[eventsKey]
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

return compost