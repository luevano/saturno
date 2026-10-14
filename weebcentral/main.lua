---@diagnostic disable: duplicate-doc-alias
---@alias Metadata { english_title: string?, romaji_title: string?, native_title: string?, synonyms: string[]?, community_score: number?, summary: string?, cover_image: string?, banner_image: string?, tag_list: string[]?, genre_list: string[]?, character_list: string[]?, author_list: string[]?, artist_list: string[]?, translator_list: string[]?, letterer_list: string[]?, date_start: string?, date_end: string?, provider_publisher: string?, publication_status: string?, publication_format: string?, country_of_origin: string?, chapter_count: number?, extra_notes: string?, source_url: string?, provider_id: string?, provider_id_code: string? }
---@alias Manga { id: string, title: string, url: string?, cover: string?, banner: string?, metadata: Metadata?, [any]: any }
---@alias Volume { number: number, [any]: any }
---@alias Chapter { title: string, url: string?, number: number?, date: string?, scanlation_group: string?, unavailable: string?, [any]: any }
---@alias Page { url: string, headers: table<string, string>?, cookies: table<string, string>?, extension: string? }

-- MangaSee shut down and moved to Weeb Central, its old id is in the history (mangal.toml).

local sdk = require("sdk")

local http = sdk.http

local BASE_URL = "https://weebcentral.com"

-- 1 request every 2 seconds to the site (not the image hosts), like keiyoushi's
-- src/en/weebcentral/WeebCentral.kt; older luaprovider versions can't limit
if http.rate_limit then
  http.rate_limit(1, 2, "weebcentral.com")
end

-- luaprovider sends its user agent by default
---@param url string
---@return table
local function get_html(url)
  -- check raises an error mangal can tell apart (not found, rate limited)
  local res = http.request(http.METHOD_GET, url):send():check()

  return sdk.html.parse(res:body())
end

---@param href string
---@return string
local function absolute(href)
  if sdk.strings.has_prefix(href, "/") then
    return BASE_URL .. href
  end
  return href
end

-- the path segment after the given one, e.g. the id after "series"; nil if there's none
---@param url string
---@param segment string
---@return string?
local function path_after(url, segment)
  local parts = sdk.strings.split(url, "/")
  for i, part in ipairs(parts) do
    if part == segment and parts[i + 1] ~= "" then
      return parts[i + 1]
    end
  end
  return nil
end

---@param query string
---@return Manga[]
function SearchMangas(query)
  local params = sdk.urls.values()
  params:set("text", sdk.strings.trim_space(query))
  params:set("sort", "Best Match")
  params:set("order", "Descending")
  params:set("official", "Any")
  params:set("anime", "Any")
  params:set("adult", "Any")
  params:set("display_mode", "Full Display")

  local html = get_html(BASE_URL .. "/search/data?" .. params:string())

  local mangas = {}
  html:find("article.bg-base-300"):each(function(selection)
    local link = selection:find('section:nth-child(2) a[href*="/series/"]'):first()
    local url = absolute(link:attr_or("href", ""))
    local id = path_after(url, "series")

    -- one odd result shouldn't fail the search
    if id ~= nil then
      table.insert(mangas, {
        title = sdk.strings.trim_space(link:text()),
        url = url,
        cover = selection:find("picture img"):first():attr_or("src", ""),
        id = id,
      })
    end
  end)

  return mangas
end

---@param id string
---@return Manga?
function MangaByID(id)
  local url = BASE_URL .. "/series/" .. sdk.urls.path_escape(id)
  -- a missing series is a 404, which luaprovider takes as no manga
  local main = get_html(url):find("main"):first()
  local title = sdk.strings.trim_space(main:find("h1"):first():text())
  if title == "" then
    return nil
  end

  return {
    title = title,
    url = url,
    cover = main:find("picture img"):first():attr_or("src", ""),
    id = id,
  }
end

---@param manga Manga
---@return Volume[]
function MangaVolumes(manga)
  -- weeb central does not provide volumes
  return {
    {
      number = 1,
    },
  }
end

-- prologues go before chapter 1, e.g. "Prologue 3" is 0.03; without a number luaprovider puts the
-- chapter right after the previous one
---@param title string
---@return number?
local function chapter_number(title)
  local words = sdk.strings.split(title, " ")
  local number = tonumber(words[#words])
  if number ~= nil and words[1] == "Prologue" then
    return number / 100
  end
  return number
end

---@param volume Volume
---@return Chapter[]
function VolumeChapters(volume)
  -- the series page only shows the latest chapters
  local html = get_html(BASE_URL .. "/series/" .. volume.manga.id .. "/full-chapter-list")

  local chapters = {}
  html:find('a[href*="/chapters/"]'):each(function(selection)
    local title = sdk.strings.trim_space(selection:find("span.grow > span"):first():text())
    local url = absolute(selection:attr_or("href", ""))
    local datetime = selection:find("time"):attr_or("datetime", "")
    local id = path_after(url, "chapters")

    if id ~= nil then
      table.insert(chapters, {
        id = id,
        title = title,
        url = url,
        number = chapter_number(title),
        date = sdk.strings.split(datetime, "T")[1],
        scanlation_group = "Weeb Central",
      })
    end
  end)

  -- the list is newest first
  return sdk.util.reverse(chapters)
end

---@param chapter Chapter
---@return Page[]
function ChapterPages(chapter)
  -- the chapter page loads its images from here
  local url = BASE_URL .. "/chapters/" .. chapter.id .. "/images?is_prev=False&current_page=1&reading_style=long_strip"
  local html = get_html(url)

  local pages = {}
  html:find('img[alt^="Page"]'):each(function(selection)
    local src = selection:attr_or("src", "")
    table.insert(pages, {
      url = src,
      extension = src:match("%.%w+$"),
    })
  end)

  return pages
end
