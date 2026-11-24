-- Conservative lexical hints, never execution or proof of runtime behavior.
local Analysis = {}
local SERVICES = {ReplicatedStorage=true, ReplicatedFirst=true, StarterPlayer=true,
    StarterGui=true, PlayerGui=true, PlayerScripts=true, Workspace=true,
    SoundService=true, Lighting=true, Teams=true, StarterPack=true, Players=true}
local REMOTE_MEMBERS = {FireServer=true, InvokeServer=true, OnClientEvent=true,
    OnClientInvoke=true, Fire=true, Invoke=true, Event=true, OnInvoke=true}

local function lexer(source, budget)
    local position, line, processed = 1, 1, 0
    local function tick()
        if budget and budget:checkpoint("source_analysis") == false then error("analysis cancelled") end
    end
    local function move(to)
        while position < to do
            local ending = math.min(to - 1, position + 4095)
            local _, count = source:sub(position, ending):gsub("\n", "")
            line = line + count; position = ending + 1
            if position < to then tick() end
        end
    end
    local function findPlain(needle, start)
        local cursor = start
        while cursor <= #source do
            local chunk = source:sub(cursor, cursor + 4095 + #needle - 1)
            local found = chunk:find(needle, 1, true)
            if found then
                local first = cursor + found - 1
                return first, first + #needle - 1
            end
            cursor = cursor + 4096
            tick()
        end
    end
    local function findNonspace(start)
        if start <= #source and not source:find("^%s", start) then return start end
        local cursor = start
        while cursor <= #source do
            local chunk = source:sub(cursor, cursor + 4095)
            local found = chunk:find("%S")
            if found then return cursor + found - 1 end
            cursor = cursor + #chunk
            tick()
        end
    end
    local function quoted(quote)
        local parts, known = {}, true
        position = position + 1
        while position <= #source do
            local chunk = source:sub(position, position + 4095)
            local index = chunk:find(quote == '"' and '[\\"\n]' or "[\\'\n]")
            if not index then
                parts[#parts + 1] = chunk; position = position + #chunk; tick()
            else
                parts[#parts + 1] = chunk:sub(1, index - 1)
                position = position + index - 1
                local char = source:sub(position, position)
                if char == quote then position = position + 1; return table.concat(parts), known end
                if char == "\n" then line = line + 1; known = false; position = position + 1
                else
                    local nextChar = source:sub(position + 1, position + 1)
                    local simple = {n="\n", r="\r", t="\t", ["\\"]="\\", ['"']='"', ["'"]="'"}
                    if simple[nextChar] then
                        parts[#parts + 1] = simple[nextChar]; position = position + 2
                    elseif nextChar == "x" and source:sub(position + 2, position + 3):match("^%x%x$") then
                        parts[#parts + 1] = string.char(tonumber(source:sub(position + 2, position + 3), 16))
                        position = position + 4
                    elseif nextChar:match("%d") then
                        local digits = source:sub(position + 1, position + 3):match("^%d%d?%d?")
                        local n = tonumber(digits)
                        if n <= 255 then parts[#parts + 1] = string.char(n) else known = false end
                        position = position + 1 + #digits
                    else
                        known = false
                        position = position + 2
                    end
                end
            end
        end
        return table.concat(parts), false
    end
    local skipBacktick
    skipBacktick = function()
        position = position + 1
        local depth = 0
        while position <= #source do
            local chunk = source:sub(position, position + 4095)
            local index = chunk:find("[\\`{}\n\"'%-%[]")
            if not index then position = position + #chunk; tick()
            else
                position = position + index - 1
                local char = source:sub(position, position)
                if char == "\\" then position = position + 2
                elseif char == "`" then
                    if depth == 0 then position = position + 1; return end
                    skipBacktick()
                elseif depth > 0 and (char == '"' or char == "'") then quoted(char)
                elseif depth > 0 and source:sub(position, position + 1) == "--" then
                    local a, b, equals = source:find("^%-%-%[(=*)%[", position)
                    if a then
                        local _, ending = findPlain("]" .. equals .. "]", b + 1)
                        move(ending and ending + 1 or #source + 1)
                    else move((findPlain("\n", position) or #source) + 1) end
                elseif depth > 0 and char == "[" then
                    local a, b, equals = source:find("^%[(=*)%[", position)
                    if a then
                        local _, ending = findPlain("]" .. equals .. "]", b + 1)
                        move(ending and ending + 1 or #source + 1)
                    else position = position + 1 end
                elseif char == "{" then depth = depth + 1; position = position + 1
                elseif char == "}" and depth > 0 then depth = depth - 1; position = position + 1
                elseif char == "\n" then line = line + 1; position = position + 1
                else position = position + 1 end
            end
        end
    end
    return function()
        while position <= #source do
            processed = processed + 1
            if processed % 128 == 0 then tick() end
            local nonspace = findNonspace(position)
            if not nonspace then return nil end
            move(nonspace)
            local start, atLine = position, line
            local a, b, equal = source:find("^%-%-%[(=*)%[", position)
            if a == position then
                local _, ending = findPlain("]" .. equal .. "]", b + 1)
                move(ending and ending + 1 or #source + 1)
            elseif source:sub(position, position + 1) == "--" then
                move((findPlain("\n", position) or #source) + 1)
            else
                local char = source:sub(position, position)
                if char == '"' or char == "'" then
                    local value, known = quoted(char)
                    return {kind="string", value=value, known=known, line=atLine, offset=start, ending=position-1}
                end
                if char == "`" then skipBacktick(); continue end
                a, b, equal = source:find("^%[(=*)%[", position)
                if a == position then
                    local ending, closing = findPlain("]" .. equal .. "]", b + 1)
                    local value = source:sub(b + 1, (ending or (#source + 1)) - 1)
                    move(closing and closing + 1 or #source + 1)
                    local known = closing ~= nil and not value:find("\r", 1, true)
                        and value:sub(1, 1) ~= "\n"
                    return {kind="string", value=value, known=known, line=atLine, offset=start, ending=position-1}
                end
                a, b = source:find("^[%a_][%w_]*", position)
                if a == position then
                    position = b + 1
                    return {kind="identifier",value=source:sub(a,b),line=atLine,offset=start,ending=b}
                end
                a, b = source:find("^%d+", position)
                if a == position then
                    position = b + 1
                    return {kind="number",value=source:sub(a,b),line=atLine,offset=start,ending=b}
                end
                position = position + 1
                return {kind="symbol",value=char,line=atLine,offset=start,ending=start}
            end
        end
    end
end

function Analysis.analyze(source, entry, budget)
    local result = {version=1, evidence="static_text", confidence="candidate",
        scope="conservative lexical references; aliases and scope are not runtime-proven",
        imports={}, remoteReferences={}, guiReferences={}, services={}, tokenCount=0}
    local nextToken = lexer(source, budget)
    local buffer, head, tail, aliases, seen = {}, 1, 0, {}, {}
    local function peek(offset)
        local index = head + (offset or 0)
        while tail < index do
            local token = nextToken()
            if not token then return nil end
            tail = tail + 1; buffer[tail] = token
        end
        return buffer[index]
    end
    local function value(offset) local t=peek(offset); return t and t.value end
    local function advance()
        buffer[head]=nil; head=head+1
        if head>256 then
            local compact={}
            for i=head,tail do compact[#compact+1]=buffer[i] end
            buffer=compact;tail=#compact;head=1
        end
    end
    local function pathAt(offset)
        local token = peek(offset)
        if not token or token.kind~="identifier" then return nil,offset end
        local name=token.value
        local path=name=="game" and "@game" or (name=="script" and entry.robloxPath or aliases[name])
        if name=="workspace" then path="Workspace" end
        if not path then return nil,offset end
        local cursor=offset+1
        for _=1,128 do
            local separator=value(cursor)
            local member=peek(cursor+1)
            if separator=="." and member and member.kind=="identifier" then
                if REMOTE_MEMBERS[member.value] then return path,cursor+1,member.value end
                if member.value=="Parent" then path=path:match("^(.*)/[^/]+$")
                elseif path=="@game" then path=SERVICES[member.value] and member.value or nil
                else path=path.."/"..member.value end
                cursor=cursor+2
            elseif separator=="[" and member and member.kind=="string" and member.known and value(cursor+2)=="]" then
                if path=="@game" then path=SERVICES[member.value] and member.value or nil
                else path=path.."/"..member.value end
                cursor=cursor+3
            elseif separator==":" and member and value(cursor+2)=="(" then
                local argument=peek(cursor+3)
                if REMOTE_MEMBERS[member.value] then return path,cursor+1,member.value end
                if member.value=="GetService" and path=="@game" and argument and argument.kind=="string" and argument.known
                    and SERVICES[argument.value] and value(cursor+4)==")" then
                    path=argument.value;result.services[path]=true;cursor=cursor+5
                elseif (member.value=="WaitForChild" or member.value=="FindFirstChild")
                    and argument and argument.kind=="string" and argument.known and value(cursor+4)==")" then
                    path=path.."/"..argument.value;cursor=cursor+5
                elseif member.value=="Clone" and value(cursor+3)==")" then cursor=cursor+4
                else return nil,cursor end
            elseif separator=="[" or separator==":" then
                return nil,cursor
            else return path,cursor end
            if not path then return nil,cursor end
        end
        result.pathDepthLimitEncountered=true
        return nil,cursor
    end
    local function hint(target,kind,token,path,ending)
        local key=kind..":"..token.offset
        if seen[key] then return end
        seen[key]=true
        local expression=source:sub(token.offset,ending or token.ending)
        target[#target+1]={kind=kind,line=token.line,byteOffset=token.offset,
            expression=expression:sub(1,240),previewTruncated=#expression>240,
            pathCandidate=path~="@game" and path or nil,evidence="static_text",confidence="candidate"}
    end
    local previous
    while peek() do
        local token=peek();result.tokenCount=result.tokenCount+1
        if token.kind=="identifier" then
            if token.value=="require" and value(1)=="(" then
                local path, afterPath=pathAt(2)
                if value(afterPath)~=")" then path=nil end
                local arg=peek(2)
                local depth, ending = 0, token.ending
                for offset=1,2048 do
                    local part=peek(offset)
                    if not part then break end
                    ending=part.ending
                    if part.kind=="symbol" and part.value=="(" then depth=depth+1
                    elseif part.kind=="symbol" and part.value==")" then
                        depth=depth-1
                        if depth==0 then break end
                    end
                end
                hint(result.imports,"require",token,path,ending)
                local row=result.imports[#result.imports]
                if arg and arg.kind=="number" then row.assetIdCandidate=arg.value end
            end
            if value(1)=="=" and previous~="." and previous~=":" then
                aliases[token.value]=pathAt(2)
            end
            if previous~="." and previous~=":" then
                local path, ending, member=pathAt(0)
                local last=peek(ending)
                if path and member then hint(result.remoteReferences,member,token,path,last and last.ending) end
                if path and (path:find("PlayerGui",1,true) or path:find("StarterGui",1,true)) then
                    hint(result.guiReferences,"gui_path",token,path,last and last.ending)
                end
            end
        end
        previous=token.value;advance()
    end
    result.counts={imports=#result.imports,remoteReferences=#result.remoteReferences,guiReferences=#result.guiReferences}
    return result
end

return Analysis
