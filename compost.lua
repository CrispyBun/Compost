local compost = {}

--- Each namespace holds the metatables of components belonging to it.
--- You shouldn't edit this table directly, instead use `compost.defineNamespace`.
---@type table<string, table<string, table>>
compost.namespaces = {
    global = {},
}

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
---@field init? fun(...) Called when the component is added to a bin
---@field destruct? fun() Called when the component is removed from a bin

------------------------------------------------------------

--- ### compost.newNamespace(name, parentNamespace)
--- Defines a new namespace with the given name.  
--- A parent namespace may be provided to extend it. If not provided, the global namespace is used for the parent.
---@param name string The name of the namespace
---@param parentNamespace? string The name of the parent namespace (Optional)
function compost.defineNamespace(name, parentNamespace)
    parentNamespace = parentNamespace or "global"

    local namespace = {}
    setmetatable(namespace, {__index = compost.namespaces[parentNamespace]})

    if compost.namespaces[name] then error("Namespace '" .. tostring(name) .. "' already exists", 2) end
    compost.namespaces[name] = namespace
end

--- ### compost.defineComponent(componentName, componentDefinition, namespace)
--- Defines a new component.  
--- You can specify which namespace the component belongs to, or by default, it will be put in the "global" namespace.  
--- A component may be defined multiple times for different namespaces.
---@param componentName string
---@param componentDefinition table
---@param namespace string?
function compost.defineComponent(componentName, componentDefinition, namespace)
    namespace = namespace or "global"

    if not compost.namespaces[namespace] then error("Namespace '" .. tostring(namespace) .. "' doesn't exist", 2) end
    compost.namespaces[namespace][componentName] = {__index = componentDefinition}
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

--- ### Bin:addComponent(component, namespace)
--- Adds a component to the bin, optionally providing the namespace to look for it in (defaults to "global").
---@param component string The component to instance
---@param namespace? string The namespace to look for the component in (Default is "global")
---@param ... unknown Arguments to the component's `init` method
---@return table component
function Bin:addComponent(component, namespace, ...)
    namespace = namespace or "global"
    if not compost.namespaces[namespace] then error("Namespace '" .. tostring(namespace) .. "' doesn't exist", 2) end
    local mt = compost.namespaces[namespace][component]
    if not mt then error("Component '" .. tostring(component) .. "' not found in namespace '" .. tostring(namespace) .. "'", 2) end

    ---@type Compost.Component
    local instance = {
        Bin = self,
    }

    self[component] = setmetatable(instance, mt)

    if instance.init then
        instance:init(...)
    end

    return instance
end

--- ### Bin:removeComponent(component)
--- Removes a component from the bin.
---@param component string
function Bin:removeComponent(component)

    local instance = self[component]
    if instance and instance.destruct then
        instance:destruct()
    end

    local events = self[eventsKey]
    for event, listeners in pairs(events) do
        for listenerIndex = 1, #listeners do
            local listener = listeners[listenerIndex]
            if listener[1] == component then
                table.remove(listeners, listenerIndex)
            end
        end
    end

    self[component] = nil
end

--- ### Bin:getComponent(component)
--- Returns the component, or `nil` if it's not present in the bin.
---@param component string
---@return table?
function Bin:getComponent(component)
    return self[component]
end

--- ### Bin:forceComponent(component, namespace, ...)
--- Gets and returns the component if it's present, or if not, creates and adds it first.
---@param component string
---@param namespace? string
---@param ... unknown
---@return table component
function Bin:forceComponent(component, namespace, ...)
    if self[component] then return self[component] end
    return self:addComponent(component, namespace, ...)
end

--- ### Bin:expectComponent(component)
--- Returns the component if it's present, or throws an error if it's not.
---@param component string
---@return table
function Bin:expectComponent(component)
    local instance = self[component]
    if not instance then error("Expected component '" .. tostring(component) .. "' but was not found in bin", 2) end
    return instance
end

--- ### Bin:addListener(event, component, method)
--- Adds a listener to an event. The listener is a component in the same bin and a method within it.
--- 
--- Example usage:
--- ```
--- bin:addListener("health:damage", "sound", "playDamaged")
--- ```
---@param event string
---@param component string
---@param method string
function Bin:addListener(event, component, method)
    local events = self[eventsKey]
    if not events[event] then events[event] = {} end

    local listeners = events[event]
    listeners[#listeners+1] = {component, method}
end

--- ### Bin:removeListener(event, component, method)
--- Removes a listener from an event.
---@param event string
---@param component string
---@param method string
function Bin:removeListener(event, component, method)
    local events = self[eventsKey]
    if not events[event] then return end

    local listeners = events[event]
    for listenerIndex = 1, #listeners do
        local listener = listeners[listenerIndex]

        if listener[1] == component and listener[2] == method then
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