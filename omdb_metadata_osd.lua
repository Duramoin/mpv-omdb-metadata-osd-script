-- omdb_metadata_osd.lua
-- mpv script to fetch and display movie/tv series metadata from the omdb api
-- with a custom font size for the metadata display using ass markup.

local mp = require 'mp'
local utils = require 'mp.utils'

-- replace with your valid omdb key. one thousand api requests per month (get one at http://www.omdbapi.com/)

local omdb_api_key = "api_key_here"

local display_duration = 10

local display_font_size = 10

local api_url_base = "http://www.omdbapi.com/"

local function url_encode(str)
    if str then
        str = str:gsub("\n", "\r\n")
        str = str:gsub("([^%w _%%%-%.~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = str:gsub(" ", "+")
    end
    return str
end

local function is_series(filename)    
    return string.find(filename, "[Ss]%d+[Ee]%d+") ~= nil
end

local function get_media_title_and_year(filename)   
    local name = filename:match("([^/\\]+)$")    
    name = name:gsub("%.%w+$", "")
    if is_series(name) then
        local title, year = name:match("^(.-)[%.%s]+[Ss]%d+[Ee]%d+[%.%s]+(%d%d%d%d)")
        if title then
            title = title:gsub("[_%.]", " "):match("^%s*(.-)%s*$")
            return title, year
        else          
            local title_only = name:match("^(.-)[%.%s]+[Ss]%d+[Ee]%d+")
            if title_only then
                title_only = title_only:gsub("[_%.]", " "):match("^%s*(.-)%s*$")
                return title_only, nil
            else
                return name:gsub("[_%.]", " "), nil
            end
        end
    else       
        local title, year = name:match("^(.-)%s*%((%d%d%d%d)%)")
        if not title then           
            title, year = name:match("^(.-)[%.%s]+(%d%d%d%d)")
        end

        if title then
            title = title:gsub("[_%.]", " "):match("^%s*(.-)%s*$")
            return title, year
        else
            return name:gsub("[_%.]", " "), nil
        end
    end
end

local function fetch_metadata(title, year, media_type)
    local encoded_title = url_encode(title)
    local url = api_url_base .. "?apikey=" .. omdb_api_key .. "&t=" .. encoded_title
    if year then
        url = url .. "&y=" .. year
    end
    if media_type then
        url = url .. "&type=" .. media_type
    end

    local args = { "curl", "-s", url }
    local res = utils.subprocess({ args = args, cancellable = false })

    if res.status ~= 0 then
        return nil, "failed to fetch metadata (curl returned status " .. tostring(res.status) .. ")"
    end
    if res.stdout == "" then
        return nil, "empty response from omdb api"
    end

    local data = utils.parse_json(res.stdout)
    if not data or data.Response == "False" then
        return nil, data and data.Error or "unknown error from omdb api"
    end

    return data, nil
end

local function format_metadata(data)
    local metadata = ""
    metadata = metadata .. string.format("Title: %s\n", data.Title or "N/A")
    metadata = metadata .. string.format("Year: %s\n", data.Year or "N/A")
    metadata = metadata .. string.format("Rated: %s\n", data.Rated or "N/A")
    metadata = metadata .. string.format("Released: %s\n", data.Released or "N/A")
    metadata = metadata .. string.format("Runtime: %s\n", data.Runtime or "N/A")
    metadata = metadata .. string.format("Genre: %s\n", data.Genre or "N/A")
    metadata = metadata .. string.format("Director: %s\n", data.Director or "N/A")
    metadata = metadata .. string.format("Actors: %s\n", data.Actors or "N/A")
    metadata = metadata .. string.format("Plot: %s", data.Plot or "N/A")
    return metadata
end

local function display_metadata()
    local path = mp.get_property("path")
    if not path then
        mp.msg.error("no file path found")
        return
    end

    local title, year = get_media_title_and_year(path)
    local media_type = is_series(path) and "series" or "movie"

    mp.msg.info("extracted title: " .. title .. (year and (" (" .. year .. ")") or ""))
    mp.msg.info("media type: " .. media_type)

    local data, err = fetch_metadata(title, year, media_type)
    if err then
        local ass_err = string.format("{\\fs%d}error: %s", display_font_size, err)
        mp.set_osd_ass(0, 0, ass_err)
        mp.msg.error("metadata fetch error: " .. err)
        mp.add_timeout(display_duration, function() mp.set_osd_ass(0, 0, "") end)
        return
    end

    local text = format_metadata(data)
    local ass_text = string.format("{\\fs%d}%s", display_font_size, text)
    ass_text = ass_text:gsub("\n", "\n{\\fs" .. display_font_size .. "}")
    mp.set_osd_ass(0, 0, ass_text)
    mp.add_timeout(display_duration, function() mp.set_osd_ass(0, 0, "") end)
end

-- remove the comment "--" if you want to fetch metadata automatically

--mp.register_event("file-loaded", function()
--    if omdb_api_key == "api_key_here" then
--        mp.msg.error("omdb api key not set in omdb_metadata_osd.lua. please edit the script and insert your key.")
--        return
--    end
--    display_metadata()
--end)

mp.add_key_binding("f2", "refresh-metadata", function()
    display_metadata()
end)
