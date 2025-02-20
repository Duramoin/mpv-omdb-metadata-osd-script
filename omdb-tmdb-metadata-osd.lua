-- omdb-tmdb-metadata-osd.lua
-- mpv script to fetch and display movie/tv series metadata from omdb(F2) or tmdb (F3)
-- displays the following fields:
-- title, director, actors, runtime, genre, country, year, released, ratings, votes, plot

local mp = require 'mp'
local utils = require 'mp.utils'

local omdb_api_key = "api_key_here"
local tmdb_api_key = "api_key_here"

local display_duration = 10
local display_font_size = 10

local omdb_api_url_base = "http://www.omdbapi.com/"
local tmdb_api_url_base = "https://api.themoviedb.org/3"

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

local function format_metadata_osd(text)
    local ass_text = string.format("{\\fs%d}%s", display_font_size, text)
    ass_text = ass_text:gsub("\n", "\n{\\fs" .. display_font_size .. "}")
    return ass_text
end

local function fetch_metadata_omdb(title, year, media_type)
    local encoded_title = url_encode(title)
    local url = omdb_api_url_base .. "?apikey=" .. omdb_api_key .. "&t=" .. encoded_title
    if year then url = url .. "&y=" .. year end
    if media_type then url = url .. "&type=" .. media_type end

    local args = { "curl", "-s", url }
    local res = utils.subprocess({ args = args, cancellable = false })
    if res.status ~= 0 then
        return nil, "failed to fetch metadata (curl status " .. tostring(res.status) .. ")"
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

local function format_metadata_omdb(data)
    local ratings = "N/A"
    if data.Ratings and #data.Ratings > 0 then
        local rating_list = {}
        for i, r in ipairs(data.Ratings) do
            table.insert(rating_list, r.Source .. ": " .. r.Value)
        end
        ratings = table.concat(rating_list, ", ")
    end

    local metadata = string.format(
        "Title: %s\nDirector: %s\nActors: %s\nRuntime: %s\nGenre: %s\nCountry: %s\nYear: %s\nReleased: %s\nRatings: %s\nVotes: %s\nPlot: %s\nSource: OMDB",
        data.Title or "N/A",
        data.Director or "N/A",
        data.Actors or "N/A",
        data.Runtime or "N/A",
        data.Genre or "N/A",
        data.Country or "N/A",
        data.Year or "N/A",
        data.Released or "N/A",
        ratings,
        data.imdbVotes or "N/A",
        data.Plot or "N/A"
    )
    return metadata
end

local function display_metadata_omdb()
    local path = mp.get_property("path")
    if not path then
        mp.msg.error("no file path found")
        return
    end

    local title, year = get_media_title_and_year(path)
    local media_type = is_series(path) and "series" or "movie"
    mp.msg.info("omdb - title: " .. title .. (year and (" (" .. year .. ")") or ""))
    mp.msg.info("media type: " .. media_type)

    local data, err = fetch_metadata_omdb(title, year, media_type)
    if err then
        local ass_err = format_metadata_osd("error: " .. err)
        mp.set_osd_ass(0, 0, ass_err)
        mp.msg.error("omdb fetch error: " .. err)
        mp.add_timeout(display_duration, function() mp.set_osd_ass(0, 0, "") end)
        return
    end

    local text = format_metadata_omdb(data)
    local ass_text = format_metadata_osd(text)
    mp.set_osd_ass(0, 0, ass_text)
    mp.add_timeout(display_duration, function() mp.set_osd_ass(0, 0, "") end)
end

local function fetch_metadata_tmdb(title, year, media_type)
    local endpoint = (media_type == "series") and "/search/tv" or "/search/movie"
    local encoded_title = url_encode(title)
    local url_search = tmdb_api_url_base .. endpoint .. "?api_key=" .. tmdb_api_key .. "&query=" .. encoded_title
    if year then
        if media_type == "series" then
            url_search = url_search .. "&first_air_date_year=" .. year
        else
            url_search = url_search .. "&year=" .. year
        end
    end

    local args = { "curl", "-s", url_search }
    local res = utils.subprocess({ args = args, cancellable = false })
    if res.status ~= 0 then
        return nil, "tmdb search failed (curl status " .. tostring(res.status) .. ")"
    end
    if res.stdout == "" then
        return nil, "empty response from tmdb search"
    end

    local search_data = utils.parse_json(res.stdout)
    if not search_data or not search_data.results or #search_data.results == 0 then
        return nil, "no tmdb results found"
    end
    local first = search_data.results[1]
    local details_endpoint = ""
    if media_type == "series" then
        details_endpoint = "/tv/" .. first.id
    else
        details_endpoint = "/movie/" .. first.id
    end
	
    details_endpoint = details_endpoint .. "?api_key=" .. tmdb_api_key .. "&append_to_response=credits"
    local args2 = { "curl", "-s", tmdb_api_url_base .. details_endpoint }
    local res2 = utils.subprocess({ args = args2, cancellable = false })
    if res2.status ~= 0 then
        return nil, "tmdb details fetch failed (curl status " .. tostring(res2.status) .. ")"
    end
    if res2.stdout == "" then
        return nil, "empty response from tmdb details"
    end

    local details_data = utils.parse_json(res2.stdout)
    return details_data, nil
end

local function format_metadata_tmdb(data, media_type)
    local title = (media_type == "series") and (data.name or "N/A") or (data.title or "N/A")   
    local director = "N/A"
    local directors = {}
    if data.credits and data.credits.crew then
        for _, crew in ipairs(data.credits.crew) do
            if crew.job == "Director" then
                table.insert(directors, crew.name)
            end
        end
    end
    if #directors > 0 then
        director = table.concat(directors, ", ")
    end

    local actors = "N/A"
    local cast_names = {}
    if data.credits and data.credits.cast then
        for i, cast in ipairs(data.credits.cast) do
            table.insert(cast_names, cast.name)
            if i >= 5 then break end
        end
    end
    if #cast_names > 0 then
        actors = table.concat(cast_names, ", ")
    end

    local runtime = "N/A"
    if media_type == "series" then
        if data.episode_run_time and #data.episode_run_time > 0 then
            runtime = tostring(data.episode_run_time[1]) .. " min"
        end
    else
        if data.runtime then
            runtime = tostring(data.runtime) .. " min"
        end
    end

    local genres = "N/A"
    if data.genres then
        local genre_names = {}
        for _, genre in ipairs(data.genres) do
            table.insert(genre_names, genre.name)
        end
        if #genre_names > 0 then
            genres = table.concat(genre_names, ", ")
        end
    end

    local country = "N/A"
    if media_type == "series" then
        if data.origin_country and #data.origin_country > 0 then
            country = table.concat(data.origin_country, ", ")
        end
    else
        if data.production_countries and #data.production_countries > 0 then
            local countries = {}
            for _, c in ipairs(data.production_countries) do
                table.insert(countries, c.name)
            end
            if #countries > 0 then
                country = table.concat(countries, ", ")
            end
        end
    end

    local year_str = "N/A"
    local released = "N/A"
    if media_type == "series" then
        if data.first_air_date and #data.first_air_date >= 4 then
            year_str = data.first_air_date:sub(1,4)
            released = data.first_air_date
        end
    else
        if data.release_date and #data.release_date >= 4 then
            year_str = data.release_date:sub(1,4)
            released = data.release_date
        end
    end

    local ratings = (data.vote_average and tostring(data.vote_average)) or "N/A"
    local votes = (data.vote_count and tostring(data.vote_count)) or "N/A"
    local plot = data.overview or "N/A"
    local metadata = string.format(
        "Title: %s\nDirector: %s\nActors: %s\nRuntime: %s\nGenre: %s\nCountry: %s\nYear: %s\nReleased: %s\nRatings: %s\nVotes: %s\nPlot: %s\nSource: TMDB",
        title, director, actors, runtime, genres, country, year_str, released, ratings, votes, plot
    )
    return metadata
end

local function display_metadata_tmdb()
    local path = mp.get_property("path")
    if not path then
        mp.msg.error("no file path found")
        return
    end

    local title, year = get_media_title_and_year(path)
    local media_type = is_series(path) and "series" or "movie"
    mp.msg.info("tmdb - title: " .. title .. (year and (" (" .. year .. ")") or ""))
    mp.msg.info("media type: " .. media_type)
    local data, err = fetch_metadata_tmdb(title, year, media_type)
    if err then
        local ass_err = format_metadata_osd("error: " .. err)
        mp.set_osd_ass(0, 0, ass_err)
        mp.msg.error("tmdb fetch error: " .. err)
        mp.add_timeout(display_duration, function() mp.set_osd_ass(0, 0, "") end)
        return
    end

    local text = format_metadata_tmdb(data, media_type)
    local ass_text = format_metadata_osd(text)
    mp.set_osd_ass(0, 0, ass_text)
    mp.add_timeout(display_duration, function() mp.set_osd_ass(0, 0, "") end)
end

mp.add_key_binding("f2", "refresh-metadata-omdb", function() display_metadata_omdb() end)
mp.add_key_binding("f3", "refresh-metadata-tmdb", function() display_metadata_tmdb() end)
