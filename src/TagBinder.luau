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
    Update:((self:any, deltaTime:number)->())?
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

TagBinder.TaggedInstances = {} :: {[string]:{Instance}}
TagBinder.TaggedInstanceIndices = {} :: {[string]:{[Instance]:number}}

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

    self.TaggedInstances[tagName] = {}
    self.TaggedInstanceIndices[tagName] = {}

    if self._running then
        self:_StartTag(self._setupClass, self._destroyClass, tagName, classTable)
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

    while elapsedTime < timeout::number do
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

    self.TaggedInstances[tagName] = {}
    self.TaggedInstanceIndices[tagName] = {}

    if self._running then
        self:_StartTag(self._setupFunction, self._destroyFunction, tagName, fnTable)
    end
end

function TagBinder:UnbindFunction(tagName:string)
    self.BindedFunctions[tagName] = nil
    self.BindedFunctionInstances[tagName] = nil
    self.UpdatingFunctionTags[tagName] = nil
end

function TagBinder:HasAllTags(obj:Instance, tags:{string})
    for _,tagName in tags do
        if not self.TaggedInstanceIndices[tagName][obj] then
            return false
        end
    end
    return true
end

function TagBinder:HasAnyTag(obj:Instance, tags:{string})
    for _,tagName in tags do
        if self.TaggedInstanceIndices[tagName][obj] then
            return true
        end
    end
    return false
end

function TagBinder:HasTag(obj:Instance, tagName:string)
    return self.TaggedInstanceIndices[tagName][obj] ~= nil
end

function TagBinder:_RegisterTaggedInstance(tagName:string, obj:Instance)
    self.TaggedInstances[tagName][#self.TaggedInstances[tagName]+1] = obj
    self.TaggedInstanceIndices[tagName][obj] = #self.TaggedInstances[tagName]
end

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

function TagBinder:_setupClass(class:AnyClass, obj:Instance, tagName:string)
    local newClassObj = class.new(obj, obj:GetAttributes())
    if newClassObj ~= nil then
        self.ClassObjects[tagName][obj] = newClassObj
        if typeof(newClassObj.Start) == "function" then
            task.spawn(newClassObj.Start, newClassObj)
        end
        if typeof(newClassObj.init) == "function" then
            task.spawn(newClassObj.init, newClassObj)
        end

        self:_RegisterTaggedInstance(tagName, obj)
    end
end

function TagBinder:_destroyClass(class:AnyClass, obj:Instance, tagName:string)
    local classObject = self.ClassObjects[tagName][obj]
    if classObject and typeof(classObject.Destroy) == "function" then
        classObject:Destroy()
        self.ClassObjects[tagName][obj] = nil
        self:_RemoveTaggedInstance(tagName, obj)
    end
end

function TagBinder:_setupFunction(fnTable:FunctionTable, obj:Instance, tagName:string)
    fnTable.setup(obj, obj:GetAttributes())
    self.BindedFunctionInstances[tagName][obj] = true
    self:_RegisterTaggedInstance(tagName, obj)
end

function TagBinder:_destroyFunction(fnTable:FunctionTable, obj:Instance, tagName:string)
    if fnTable.destroy then
        fnTable.destroy(obj, obj:GetAttributes())
    end
    self.BindedFunctionInstances[tagName][obj] = nil
    self:_RemoveTaggedInstance(tagName, obj)
end

function TagBinder:_StartTag(setupCb:AnyFunction, destroyCb:AnyFunction, tagName:string, sourceTable:AnyClass|FunctionTable)
    local initial = CollectionService:GetTagged(tagName)
    for _,obj in initial do
        setupCb(self, sourceTable, obj, tagName)
    end
    CollectionService:GetInstanceAddedSignal(tagName):Connect(function(obj)
        setupCb(self, sourceTable, obj, tagName)
    end)
    CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(obj)
        destroyCb(self, sourceTable, obj, tagName)
    end)
end

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