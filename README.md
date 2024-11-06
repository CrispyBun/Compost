# Compost
Compost is a Lua library for component-based development (CBD).
It is designed to be conceptually easy to grasp for people familiar with OOP, while replacing inheritance with composition.

Compost puts importance on the [single-responsibility principle](https://en.m.wikipedia.org/wiki/Single-responsibility_principle) and [polymorphism](https://en.m.wikipedia.org/wiki/Polymorphism_(computer_science)), providing features to easily achieve both.

A basic overview of compost's features lays below, after which a more detailed documentation and proper usage guide can be found.

## Components
Components are packages of data and methods. They inherit from the `Compost.Component` class, whose fields are injected into components upon creation.

```lua
-- components/Health.lua
local compost = require 'compost'

---@class Health : Compost.Component
---@field health number
local Health = {}

-- Constructor
function Health:init(health)
    -- If you're using constructor arguments, they should always have a default value, for easier use of components in Templates.
    self.health = health or 100
end

function Health:damage(amount)
    self.health = self.health - amount
end

return compost.component(Health)
```

## The Bin
When instanced, components are always part of a *bin*, an object that holds components which define its behavior. A component cannot exist without a bin.

```lua
-- main.lua
local compost = require 'compost'
local Health = require 'components.Health'

local bin = compost.newBin()
bin:addComponent(Health, 20)

print(bin[Health].health) --> 20
```

## The Template
Adding components to a bin manually makes it hard to consistently instance bins for specific jobs.
Templates exist to define the way a specific bin should look like, including the data that goes in its components.

```lua
-- templates/GameObject.lua
local compost = require 'compost'
local Position = require 'components.Position'
local Sprite = require 'components.Sprite'
local Hitbox = require 'components.Hitbox'

-- Immediately add components when creating template
local template = compost.newTemplate(Sprite, Position)

-- Or add components to it alongside data that will be deep copied into the component after instancing
template:addComponent(Hitbox, {width = 0, height = 0})

-- The template's constructor can also be used to fill in data
template:setInit(function(bin)
    bin[Position]:setPosition(0, 0)
end)

return template
```

## The Event
Eventually, you're going to want to tie the behavior of one component to the behavior of another, which is what Events are for.

You can think of Events as a sort of Interface a component leaves for other components to implement. Events even allow for return values, which will be covered in the documentation.

```lua
-- components/Health.lua

-- ...

Health.Events = {
    Death = compost.newEvent()
}

function Health:damage(amount)
    self.health = self.health - amount

    if self.health <= 0 then
        -- All components have a `Bin` field
        self.Bin:announce(self.Events.Death)
    end
end
```
```lua
-- components/Sound.lua
local compost = require 'compost'
local Health = require 'components.Health'

local Sound = {}

function Sound:init()
    -- Attach the listener on init
    self:addBinListener(Health.Events.Death)
end

function Sound:playDeath()
    -- play death sound
end
Sound[Health.Events.Death] = Sound.playDeath -- Specify the implementation for the event
```
# Documentation
tba lol
