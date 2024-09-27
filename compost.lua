local compost = {}

--- Each namespace holds the definitions of components belonging to it.
--- You shouldn't edit this table directly, instead use `compost.defineNamespace`.
---@type table<string, table[]>
compost.namespaces = {
    global = {},
}

------------------------------------------------------------

--- An object holding instanced components  
--- Fields may be injected into this definition to annotate components based on their names
---@class Compost.Bin
---@field [string] table A component

--- If you're using annotations, your component definitions should inherit from this class
---@class Compost.Component
---@field Bin Compost.Bin The bin this component belongs to
---@field EventManager Compost.ComponentEventManager The event manager for this component

---@class Compost.ComponentEventManager
---@field events table<string, [string, string]> The event names mapped to the listening component, and a method name within it

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
    compost.namespaces[namespace][componentName] = componentDefinition
end

return compost