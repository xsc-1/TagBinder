--!stric
local AUTO_START = false

local function assertObject(obj)
    assert(obj and obj:IsA("Instance"), "object must be valid instance")
end
local function assertString(str, name:string)
    assert(typeof(str)=="string" and str~="", name.." must be a valid string")
end

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

export type AnyFunction = (...any)->(...any)
export type AnyClass = {
    [string]:any,
    new : (object:Instance, attributes:{[string]:any}) -> (any),
    Destroy:(self:any)->(),
    Start:((self:any)->())?,
    init:((self:any)->())?,
    Update:((self:any, deltaTime:number)->())?
}

export type FunctionTable = {
    setup:(object:any, attributes:{[string]:any})->(),
    destroy:(object:any, attributes:{[string]:any})->()?,
    update:(object:any, deltaTime:number)->()?,
}

local TagBinder = {}

TagBinder._running = false

TagBinder.BindedClasses = {} :: {[string]:AnyClass}
TagBinder.BindedFunctions = {} :: {[string]:FunctionTable}

TagBinder.ClassObjects = {} :: {[string]:{[any]:AnyClass}}

TagBinder.UpdatingFunctionTags = {} :: {[string]:boolean}
TagBinder.UpdatingClassTags = {} :: {[string]:boolean}

TagBinder.TaggedInstances = {} :: {[string]:{Instance}}
TagBinder.TaggedInstanceIndices = {} :: {[string]:{[Instance]:number}}

TagBinder.Connections = {} :: {[string]:{RBXScriptConnection}}
--[=[
    binds an OOP class to a tag
    whenever an instance gets created
    of the given tag,
    an OOP object gets created too
]=]
function TagBinder:BindClass(tagName:string, classTable:AnyClass)
    assert(typeof(classTable) == "table", "class must be a valid class")
    assert(classTable.new, "class table must contain a method named (new)")
    assert(classTable.Destroy, "class table must contain a method named (Destroy)")
    assertString(tagName, "tagName")

    if self.BindedClasses[tagName] ~= nil or self.BindedFunctions[tagName] ~= nil then
        warn(tagName.." tag is already bound")
        return
    end

    self.BindedClasses[tagName] = classTable
    self.ClassObjects[tagName] = {}

    if typeof(classTable.Update) == "function" then
        self.UpdatingClassTags[tagName] = true
    end


    self.TaggedInstances[tagName] = {}
    self.TaggedInstanceIndices[tagName] = {}

    self.Connections[tagName] = {}

    if self._running then
        self:_StartTag(self._setupClass, self._destroyClass, tagName, classTable)
    end
end

--[=[
    unbinds a tag,
    stops creating new
    oop objects
]=]
function TagBinder:UnbindClass(tagName:string)
    assertString(tagName, "tagName")

    self.BindedClasses[tagName] = nil
    if self.ClassObjects[tagName] then
        table.clear(self.ClassObjects[tagName])
        self.ClassObjects[tagName] = nil
    end
    self.UpdatingClassTags[tagName] = nil

    for _,c in self.Connections[tagName] do
        c:Disconnect() 
    end
    self.Connections[tagName] = nil

    self.TaggedInstances[tagName] = nil
    self.TaggedInstanceIndices[tagName] = nil
end

--[=[
    returns the OOP
    object by Instance and tagName
]=]
function TagBinder:GetClassObject<A>(obj:A, tagName:string)
    assertString(tagName, "tagName")

    if self.ClassObjects[tagName] then
        return self.ClassObjects[tagName][obj]
    else
        return nil
    end
end

--[=[
    returns a table
    containing all OOP
    objects of a tag
]=]
function TagBinder:GetAllClassObjects(tagName:string) : {[Instance]:any}
    assertString(tagName, "tagName")
    return self.ClassObjects[tagName] or {}
end

--[=[
    yields until requested
    OOP object gets created
]=]
function TagBinder:WaitForClassObject<A>(obj:A, tagName:string, timeout:number?) : any
    assertString(tagName, "tagName")
    assert(typeof(timeout)=="number", "timeout must be a valid number")

    timeout = timeout or 5
    local elapsedTime = 0

    if self.ClassObjects[tagName] and self.ClassObjects[tagName][obj] then
        return self.ClassObjects[tagName][obj]
    end

    while elapsedTime < timeout::number do
        if self.ClassObjects[tagName] and self.ClassObjects[tagName][obj] then
            return self.ClassObjects[tagName][obj]
        end
        task.wait(0.2)
        elapsedTime += 0.2
    end
    return nil
end

--[=[
    binds a table of functions
    to a tag to be called on
    certain actions
]=]
function TagBinder:BindFunction(tagName:string, fnTable:FunctionTable)
    assert(typeof(fnTable.setup) == "function", "setup function must be a function")
    assert(typeof(fnTable.destroy) == "function" or typeof(fnTable.destroy) == "nil", "destroy function must be a function or nil")
    assert(typeof(fnTable.update) == "function" or typeof(fnTable.update) == "nil", "update function must be a function or nil")
    assertString(tagName, "tagName")

    if self.BindedFunctions[tagName] ~= nil or self.BindedClasses[tagName] ~= nil then
        warn(tagName.." tag is already bound")
        return
    end

    self.BindedFunctions[tagName] = {}
    self.BindedFunctions[tagName].setup = fnTable.setup
    self.BindedFunctions[tagName].destroy = fnTable.destroy
    self.BindedFunctions[tagName].update = fnTable.update

    if fnTable.update then
        self.UpdatingFunctionTags[tagName] = true
    end

    self.TaggedInstances[tagName] = {}
    self.TaggedInstanceIndices[tagName] = {}
    
    self.Connections[tagName] = {}

    if self._running then
        self:_StartTag(self._setupFunction, self._destroyFunction, tagName, fnTable)
    end
end

--[=[
    stop calling functions for
    a tag and clean ups
]=]
function TagBinder:UnbindFunction(tagName:string)
    assertString(tagName, "tagName")
    self.BindedFunctions[tagName] = nil
    self.UpdatingFunctionTags[tagName] = nil
    for _,c in self.Connections[tagName] do
        c:Disconnect()
    end
    self.Connections[tagName] = nil

    self.TaggedInstances[tagName] = nil
    self.TaggedInstanceIndices[tagName] = nil
end

--[=[
    returns true if the instance has
    all of the given tags
]=]
function TagBinder:HasAllTags(obj:Instance, tags:{string})
    assertObject(obj)
    for _,tagName in tags do
        if not self.TaggedInstanceIndices[tagName][obj] then
            return false
        end
    end
    return true
end

--[=[
    returns true if the instance has
    any one of the given tags
]=]
function TagBinder:HasAnyTag(obj:Instance, tags:{string})
    assertObject(obj)
    for _,tagName in tags do
        if self.TaggedInstanceIndices[tagName] and self.TaggedInstanceIndices[tagName][obj] then
            return true
        end
    end
    return false
end

--[=[
    returns true if the instance
    has the given tag
]=]
function TagBinder:HasTag(obj:Instance, tagName:string)
    assertString(tagName, "tagName")
    assertObject(obj)
    local indices = self.TaggedInstanceIndices[tagName]
    return indices and indices[obj] ~= nil
end

--[=[
    private,
    adds an instance to a table
    and saves its index to
    access later
]=]
function TagBinder:_RegisterTaggedInstance(tagName:string, obj:Instance)
    local indices = self.TaggedInstanceIndices[tagName]
    if not indices then return end
    self.TaggedInstances[tagName][#self.TaggedInstances[tagName]+1] = obj
    self.TaggedInstanceIndices[tagName][obj] = #self.TaggedInstances[tagName]
end

--[=[
    private,
    removes an instance from a
    table without shifting elements
]=]
function TagBinder:_RemoveTaggedInstance(tagName:string, obj:Instance)
    local index = self.TaggedInstanceIndices[tagName][obj]
    if not index then
        return
    end

    local last = #self.TaggedInstances[tagName]
    local popped = self.TaggedInstances[tagName][last]

    if last ~= index then
        self.TaggedInstances[tagName][index] = popped
        self.TaggedInstanceIndices[tagName][popped] = index
    end
    self.TaggedInstances[tagName][last] = nil
    self.TaggedInstanceIndices[tagName][obj] = nil
end

--[=[
    private,
    creates OOP object and
    calls lifecycle methods if exist
    for a tagged instance
]=]
function TagBinder:_setupClass(class:AnyClass, obj:Instance, tagName:string)
    local newClassObj = class.new(obj, obj:GetAttributes())
    if newClassObj ~= nil then
        self.ClassObjects[tagName][obj] = newClassObj
        if typeof(newClassObj.Start) == "function" then
            newClassObj:init()
        end
        if typeof(newClassObj.init) == "function" then
            task.spawn(newClassObj.Start, newClassObj)
        end

        self:_RegisterTaggedInstance(tagName, obj)
    end
end

--[=[
    private,
    destroy OOP object
    and cleans up for a removed
    tagged instance
]=]
function TagBinder:_destroyClass(class:AnyClass, obj:Instance, tagName:string)
    local classObject = self.ClassObjects[tagName][obj]
    if classObject and typeof(classObject.Destroy) == "function" then
        classObject:Destroy()
        self.ClassObjects[tagName][obj] = nil
        self:_RemoveTaggedInstance(tagName, obj)
    end
end

--[=[
    private,
    calls setup function
    for a tagged instance
]=]
function TagBinder:_setupFunction(fnTable:FunctionTable, obj:Instance, tagName:string)
    fnTable.setup(obj, obj:GetAttributes())
    self:_RegisterTaggedInstance(tagName, obj)
end

--[=[
    private,
    calls destroy method 
    for a removed tagged instance
]=]
function TagBinder:_destroyFunction(fnTable:FunctionTable, obj:Instance, tagName:string)
    if fnTable.destroy then
        fnTable.destroy(obj, obj:GetAttributes())
    end
    self:_RemoveTaggedInstance(tagName, obj)
end

--[=[
    private,
    connects setup and destroy
    methods to CollectionService
    events
]=]
function TagBinder:_StartTag(setupCb:AnyFunction, destroyCb:AnyFunction, tagName:string, sourceTable:AnyClass|FunctionTable)
    local initial = CollectionService:GetTagged(tagName)
    for _,obj in initial do
        setupCb(self, sourceTable, obj, tagName)
    end
    table.insert(self.Connections[tagName],CollectionService:GetInstanceAddedSignal(tagName):Connect(function(obj)
        setupCb(self, sourceTable, obj, tagName)
    end))
    table.insert(self.Connections[tagName],CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(obj)
        destroyCb(self, sourceTable, obj, tagName)
    end))
end


--[=[
    starts the module,
    can be called once
]=]
function TagBinder:Start()
    if self._running then return end
    self._running = true

    for tagName, class in self.BindedClasses do
        self:_StartTag(self._setupClass, self._destroyClass, tagName, class)
    end

    for tagName, fnTable in self.BindedFunctions do
        self:_StartTag(self._setupFunction, self._destroyFunction, tagName, fnTable)
    end

    RunService.Heartbeat:Connect(function(deltaTime)
        for tagName, _ in self.UpdatingFunctionTags do
            for _,obj in self.TaggedInstances[tagName] do
                self.BindedFunctions[tagName].update(obj, deltaTime)
            end
        end

        for tagName, _ in self.UpdatingClassTags do
            for _,obj in self.TaggedInstances[tagName] do
                self.ClassObjects[tagName][obj]:Update(deltaTime)
            end
        end
    end)
end

if AUTO_START then
    (TagBinder::any):Start()
end

return TagBinder