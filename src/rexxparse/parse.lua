local sub,gsub,find = string.sub,string.gsub,string.find
local type,select = type,select
local tonumber,tostring = tonumber,tostring

local parse_template = require "rexxparse.template"

local function fillvars(variables, env, source, matchstart, matchend)
    if #variables == 0 then
        return
    end
    local match
    for n = 1,#variables-1 do
        if matchstart < matchend then
            local mstart,mend = find(source, [[^[ \t]*[^ \t]*[ \t]*]], matchstart)
            if mstart then
                if mend >= matchend then
                    mend = matchend - 1
                end
                match = sub(source, mstart, mend)
                matchstart = mend + 1
            else
                match = ""
            end
        else
            match = ""
        end
        if variables[n] ~= '.' then
            env[variables[n]] = gsub(match, "[ \t]$", "")
        end
    end
    if variables[#variables] ~= '.' then
        match = sub(source, matchstart, matchend-1)
        env[variables[#variables]] = match
    end
end

local function positional_parameter(parameter, env)
    if type(parameter) == 'number' then
        return parameter
    end
    local position = env[parameter]
    return position and tonumber(position)
end

local function parse_source(parser_thread, source, env, firsttime)
    local position = 1
    local endoftemplate = false
    local matchstart, matchend
    local match, parameter, variables = parser_thread(firsttime)
    while match do
        if match == "ERROR" then
            local message = "parse error at position " .. parameter
            if variables then
                message = message .. " (" .. variables .. ")"
            end
            return nil, message
        end
        if match == "VARS" then
            matchstart = #source + 1
            matchend = matchstart
        elseif match == "POS" then
            local pos_param = positional_parameter(parameter, env)
            if not pos_param then
                return nil, "bad parameter '" .. tostring(parameter) .. "'"
            end
            matchstart = pos_param
            matchend = matchstart
        elseif match == "POS+" then
            local pos_param = positional_parameter(parameter, env)
            if not pos_param then
                return nil, "bad parameter '" .. tostring(parameter) .. "'"
            end
            matchstart = position + pos_param
            matchend = matchstart
        elseif match == "POS-" then
            local pos_param = positional_parameter(parameter, env)
            if not pos_param then
                return nil, "bad parameter '" .. tostring(parameter) .. "'"
            end
            matchstart = position - pos_param
            matchend = matchstart
        elseif match == "VREF" then
            local match_param = env[parameter]
            if not match_param then
                return nil, "bad parameter '" .. tostring(parameter) .. "'"
            end
            matchstart, matchend = find(source, match_param, position, true)
            if matchend then
                matchend = matchend + 1
            else
                matchstart = #source + 1
                matchend = matchstart
            end
        elseif match == "MATCH" then
            matchstart, matchend = find(source, parameter, position, true)
            if matchend then
                matchend = matchend + 1
            else
                matchstart = #source + 1
                matchend = matchstart
            end
        elseif match == "EOT" then
            endoftemplate = parameter
            break
        end
        if matchstart <= position then
            matchstart = #source + 1
        end
        fillvars(variables, env, source, position, matchstart)
        position = matchend
        if position < 1 then
            position = 1
        elseif position > #source then
            position = #source + 1
        end
        match, parameter, variables = parser_thread()
    end
    return env, endoftemplate
end

local function parser(template)
    local parser_thread = parse_template(template)
    local function parser_fn(env, ...)
        if not env then
            return parser_fn({}, ...)
        elseif type(env) ~= 'table' then
            return parser_fn({}, env, ...)
        end
        -- Did a previous call fail?
        if not parser_thread then
            return nil, "cannot continue"
        end
        local source = ...
        if source then
            local result, errstatus = parse_source(parser_thread, source, env, true)
            if not result then
                parser_thread = nil
                return nil, errstatus
            end
            arg = 2
            while not errstatus do
                source = select(arg, ...) or ""
                arg = arg + 1
                result,errstatus = parse_source(parser_thread, source, env)
                if not result then
                    return nil, errstatus
                end
            end
        end
        return env
    end
    return parser_fn
end

local function parse(source, template, env)
    if not template then
        return parser(source) -- actually template
    end
    local parser_thread = parse_template(template)
    env = env or {}
    local result,errstatus = parse_source(parser_thread, source, env, true)
    if not result then
        return nil, errstatus
    end
    while not errstatus do -- there are more variables in the template
        result,errstatus = parse_source(parser_thread, "", env)
        if not result then
            return nil, errstatus
        end
    end
    return env
end

return {
    version = "rexxparse scm";
    parse = parse;
}
