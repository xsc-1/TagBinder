--!strict
local AUTO_START = false

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

export type AnyFunction = (...any)->(...any)
export type AnyClass = {
    [string]:any,
    new : (object:Instance, attributes:{[string]:any}) -> (any),
    Destroy:(self:any)->(),
    Start:((self:any)->())?,
    init:((self:any)->())?,
}

export type FunctionTable = {
    setup:(object:any, attributes:{[string]:any})->(any),
    destroy:(object:any, attributes:{[string]:any})->(any)?,
    update:(object:any, deltaTime:number)->(any)?,
}

local TagBinder = {}

TagBinder._running = false

TagBinder.BindedClasses = {} :: {[string]:AnyClass}
TagBinder.ClassObjects = {} :: {[string]:{[any]:AnyClass}}
TagBinder.BindedFunctions = {} :: {[string]:{setup:AnyFunction, destroy:AnyFunction, update:AnyFunction}}
TagBinder.BindedFunctionInstances = {} :: {[string]:{[Instance]:boolean}}

TagBinder.UpdatingFunctionTags = {} :: {[string]:boolean}
TagBinder.UpdatingClassTags = {} :: {[string]:boolean}

function TagBinder:BindClass(tagName:string, classTable:AnyClass)
    assert(typeof(classTable) == "table", "class must be a valid class")
    assert(classTable.new, "class table must contain a method named (new)")
    assert(classTable.Destroy, "class table must contain a method named (Destroy)")
    assert(typeof(tagName) == "string" and tagName~="", "tagName must be a valid string")

    self.BindedClasses[tagName] = classTable
    self.ClassObjects[tagName] = {}

    if typeof(classTable.Update) == "function" then
        self.UpdatingClassTags[tagName] = true
    end
end

function TagBinder:UnbindClass(tagName:string)
    self.BindedClasses[tagName] = nil
    if self.ClassObjects[tagName] then
        table.clear(self.ClassObjects[tagName])
        self.ClassObjects[tagName] = nil
    end
    self.UpdatingClassTags[tagName] = nil
end

function TagBinder:GetClassObject<A>(obj:A, tagName:string) : any
    if self.ClassObjects[tagName] then
        return self.ClassObjects[tagName][obj]
    else
        return nil
    end
end

function TagBinder:GetAllClassObjects(tagName:string) : {[Instance]:any}
    return self.ClassObjects[tagName] or {}
end

function TagBinder:WaitForClassObject<A>(obj:A, tagName:string, timeout:number?) : any
    timeout = timeout or 5
    local elapsedTime = 0

    if self.ClassObjects[tagName] and self.ClassObjects[tagName][obj] then
        return self.ClassObjects[tagName][obj]
    end

    while elapsedTime < timeout do
        if self.ClassObjects[tagName] and self.ClassObjects[tagName][obj] then
            return self.ClassObjects[tagName][obj]
        end
        task.wait(0.2)
        elapsedTime += 0.2
    end
    return nil
end

function TagBinder:BindFunction(tagName:string, fnTable:FunctionTable)
    assert(typeof(fnTable.setup) == "function", "setup function must be a function")
    assert(typeof(fnTable.destroy) == "function" or typeof(fnTable.destroy) == "nil", "destroy function must be a function or nil")
    assert(typeof(fnTable.update) == "function" or typeof(fnTable.update) == "nil", "update function must be a function or nil")
    assert(typeof(tagName) == "string" and tagName ~="", "tagName must be a valid string")

    if self.BindedFunctions[tagName] ~= nil then
        warn(tagName.." tag is already binded")
    end

    self.BindedFunctions[tagName] = {}
    self.BindedFunctions[tagName].setup = fnTable.setup
    self.BindedFunctions[tagName].destroy = fnTable.destroy
    self.BindedFunctions[tagName].update = fnTable.update
    self.BindedFunctionInstances[tagName] = {}

    if fnTable.update then
        self.UpdatingFunctionTags[tagName] = true
    end
end

function TagBinder:UnbindFunction(tagName:string)
    self.BindedFunctions[tagName] = nil
    self.BindedFunctionInstances[tagName] = nil
    self.UpdatingFunctionTags[tagName] = nil
end


function TagBinder:Start()
    if self._running then return end
    self._running = true

    local function setupClass(class:AnyClass, obj:Instance, tagName:string)
        local newClassObj = class.new(obj, obj:GetAttributes())
        if newClassObj ~= nil then
            self.ClassObjects[tagName][obj] = newClassObj
            if typeof(newClassObj.Start) == "function" then
                task.spawn(newClassObj.Start, newClassObj)
            end
            if typeof(newClassObj.init) == "function" then
                task.spawn(newClassObj.init, newClassObj)
            end
        end
    end

    for tagName, class in self.BindedClasses do
        local initial = CollectionService:GetTagged(tagName)
        for _,obj in initial do
           setupClass(class, obj, tagName)
        end

        CollectionService:GetInstanceAddedSignal(tagName):Connect(function(obj)
            setupClass(class, obj, tagName)
        end)
        CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(obj)
            self.ClassObjects[tagName][obj]:Destroy()
            self.ClassObjects[tagName][obj] = nil
        end)
    end

    for tagName, fnTable in self.BindedFunctions do
        local initial = CollectionService:GetTagged(tagName)
        for _,obj:Instance in initial do
            fnTable.setup(obj, obj:GetAttributes())
            self.BindedFunctionInstances[tagName][obj] = true
        end

        CollectionService:GetInstanceAddedSignal(tagName):Connect(function(obj:Instance)
            fnTable.setup(obj, obj:GetAttributes())
            self.BindedFunctionInstances[tagName][obj] = true
        end)
        CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(obj)
            if fnTable.destroy then
                fnTable.destroy(obj)
            end
            self.BindedFunctionInstances[tagName][obj] = nil
        end)
    end

    RunService.Heartbeat:Connect(function(deltaTime)
        for tagName, _ in self.UpdatingFunctionTags do
            for obj, _ in self.BindedFunctionInstances[tagName] do
                self.BindedFunctions[tagName].update(obj, deltaTime)
            end
        end

        for tagName, _ in self.UpdatingClassTags do
            for obj, classObj in self.ClassObjects[tagName] do
                classObj:Update(deltaTime)
            end
        end
    end)
end

if AUTO_START then
    TagBinder:Start()
end

return TagBinder