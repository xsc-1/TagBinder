# TagBinder
TagBinder is a simple singleton utility module that hides collection service boilerplates while making Roblox games

## Simple Usage

### Class
you can use the module with classes that has a constructor with a part as the first argument,
the class also has to contain a "Destroy" method and it may contain an "Update" method that will be called on heartbeat

```luau
--getting the module
local TagBinder = require(path.to.TagBinder)


--Creating our class
local ColorPart = {}
ColorPart.__index = ColorPart

function ColorPart.new(part:Part, attributes)--constructor method should have the part as the first argument
    local self = setmetatable({}, ColorPart)
    self.Part = part
    self.Part.Color = attributes.Color or Color3.new()--attributes which the part has

    return self
end

function ColorPart:Update(dt:number)
    self.Part.Position += Vector3.new(0, 0.1, 0)
end

function ColorPart:Destroy()
    print("part destroyed")
    table.clear(self)
    setmetatable(self, nil)
end


--Binding "ColorPart" tag to our class
TagBinder:BindClass("ColorPart", ColorPart)
TagBinder:Start() -- Auto-start is off by default

--ColorPart tagged parts will change color by their Color attributes and will go up every frame
```

### Function
if you want to use struct of arrays instead of arrays of struct you can use :BindFunction to create common functions with less overhead compared to oop

```luau
--getting the module
local TagBinder = require(path.to.TagBinder)

--binding funtions to different actions
TagBinder:BindFunction("ColorPart", {
    setup = function(part:Instance, attributes)
        part.Color = attributes.Color or Color3.new()
    end,
    update = function(part:Instance, dt:number)
        part.Position += Vector3.new(0, 0.1, 0)
    end,
    destroy = function(part:Instance)
        print("part destroyed")
    end
})
TagBinder:Start()

--ColorPart tagged parts will change color by their Color attributes and will go up every frame
```

## Behaviours

### 1. constructor/setup
.new for classes and setup function for funtion tables, called for every tagged instance once

### 2. init and Start (optional)(for Classes only)
if you add an :init or :Start method to your class, it will be called after .new

### 3. Update (optional)
if you add an :Update method to your class or funtion table, it will be called every heartbeat with deltaTime

### 4. Destroy
called when tagged instance gets destroyed



## API
```luau
local TagBinder = require(path.to.TagBinder)


--stop listening a tag
TagBinder:UnbindClass("Tag")
TagBinder:UnbindFunction("Tag")

--get a specific instance's class' object
TagBinder:GetClassObject(part, "Tag")

--get all class objects for a tag
TagBinder:GetAllClassObjects("Tag")

--yield the thread until a class object gets created for an instance and return the class object
TagBinder:WaitForClassObject(part, "Tag", 10) --10 seconds timeout


```