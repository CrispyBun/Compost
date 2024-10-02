local compost = {}

--- Each namespace holds the metatables of components belonging to it.
--- You shouldn't edit this table directly, instead use `compost.defineNamespace`.
---@type table<string, table<string, table>>
compost.namespaces = {
    global = {},
}

------------------------------------------------------------

--- An object holding instanced components  
--- Fields may be injected into this definition to annotate components based on their names
---@class Compost.Bin
---@field [string] table
---@field EventManager Compost.ComponentEventManager The event manager for this bin
local Bin = {}
local BinMT = {__index = Bin}

--- If you're using annotations, your component definitions should inherit from this class
---@class Compost.Component
---@field Bin Compost.Bin The bin this component belongs to

---@class Compost.ComponentEventManager
---@field events table<string, [string, string]> The event names mapped to the listening component, and a method name within it
local EventManager = {}
local EventManagerMT = {__index = EventManager}

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
    if compost.namespaces[namespace][componentName] then error("Component name '" .. tostring(componentName) .. "' already defined in namespace", 2) end
    compost.namespaces[namespace][componentName] = {__index = componentDefinition}
end

---@return Compost.ComponentEventManager
local function newEventManager()
    ---@type Compost.ComponentEventManager
    local eventManager = {
        events = {},
    }
    return setmetatable(eventManager, EventManagerMT)
end

--- ### compost.newBin()
--- Creates a new empty Bin with no components.
---@return Compost.Bin
function compost.newBin()
    ---@type Compost.Bin
    local bin = {
        EventManager = newEventManager(),
    }
    return setmetatable(bin, BinMT)
end

------------------------------------------------------------

--- ### Bin:addComponent(component, namespace)
--- Adds a component to the bin, optionally providing the namespace to look for it in (defaults to "global").
---@param component string
---@param namespace? string
function Bin:addComponent(component, namespace)
    namespace = namespace or "global"
    local mt = compost.namespaces[namespace][component]
    if not mt then error("Component '" .. tostring(component) .. "' not found", 2) end

    ---@type Compost.Component
    local instance = {
        Bin = self,
    }

    self[component] = setmetatable(instance, mt)
end

return compost