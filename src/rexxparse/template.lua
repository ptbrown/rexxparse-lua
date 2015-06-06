local coroutine,yield = coroutine,coroutine.yield
local sub,gsub,find = string.sub,string.gsub,string.find
local tonumber = tonumber

local function parse_template(template)
    local position, reset
    local matches, matchstart, matchend

    local function collectmatches(mstart, mend, ...)
        if not mstart then
            return nil
        end
        if not (...) then
            return mstart, mend, {sub(template, mstart, mend)}
        end
        return mstart, mend, {...}
    end
    local function match(pattern)
        matchstart, matchend, matches = collectmatches(find(template, pattern, position))
        if matchstart then
            position = matchend + 1
            return true
        end
        return false
    end
    local function check(pattern)
        return nil ~= find(template, pattern, position)
    end
    local function error(errorposition, message)
        yield("ERROR", errorposition, message)
        position = #template + 1
        yield() -- send nil to abort iteration
    end
    local function send(match, parameter, variables)
        reset = yield(match, parameter, variables)
        if reset then
            position = 1
        end
        return reset
    end

    -- Dummy yield to collect the arguments
    yield()
    while true do
        position = 1
        reset = true
        -- Return matches in sequence
        while position <= #template do
            if reset then
                -- Blank lines are ignored
                -- but only at the start of a template
                match "^[ \t\n]+"
            else
                match "^[ \t]+"
            end
            reset = false
            -- Names of variables
            local variables = {}
            repeat
                local token
                -- Symbol name
                if match "^[%a_][%w_]*" then
                    variables[#variables+1] = matches[1]
                -- or Placeholder dot
                elseif match "^%." then
                    variables[#variables+1] = "."
                else
                    break
                end
                if position <= #template and
                not (match "^[ \t]+" or check "^[,\n]") then
                    error(position, "variable name or pattern expected")
                    break
                end
            until not matches
            -- End of pattern
            if position > #template then
                send("VARS", nil, variables)
                break
            elseif match "^[,\n]" then
                reset = send("VARS", nil, variables)
                     or send("EOT")
                     or true
            -- Positional patterns
            elseif match "^([=+-]?)(%d+)" then
                local token, number
                number = tonumber(matches[2])
                if matches[1] == "=" then
                    token = "POS"
                else
                    token = "POS" .. matches[1]
                end
                send(token, number, variables)
            -- Variable reference, position or string
            elseif match "^([=+-]?)%(([%a_][%w_]*)%)" then
                local token
                if matches[1] == "" then
                    token = "VREF"
                elseif matches[1] == "=" then
                    token = "POS"
                else
                    token = "POS" .. matches[1]
                end
                send(token, matches[2], variables)
            -- or String patterns
            elseif match "^[\"']" then
                local quote = matches[1]
                local strstart = position
                local escapepattern = "[\\"..quote.."]"
                repeat
                    if not match(escapepattern) then
                        error(strstart-1, "unterminated quoted string")
                        break
                    end
                    if matches[1] == "\\" then
                        local escaped = sub(template, position, position)
                        if escaped == quote or escaped == "\\" then
                            -- move past character, will substitute later
                            position = position + 1
                        end
                    end
                until matches[1] == quote
                local quotedstring = gsub(sub(template, strstart, matchend - 1),
                                        "\\("..escapepattern..")", "%1")
                send("MATCH", quotedstring, variables)
            -- or Parse error
            else
                error(position, "pattern expected")
            end
            -- End of pattern (check again after pattern)
            if not reset then
                if position > #template then
                    break
                elseif match "^[ \t]*[,\n]" then
                    send("EOT")
                    reset = true
                elseif not match "^[ \t]+" then
                    error(position, "variable name or pattern expected.")
                    break
                end
            end
        end
        yield("EOT", true)
    end
end

return function(template)
    local parser_thread = coroutine.wrap(parse_template)
    parser_thread(template)
    return parser_thread
end
