---@diagnostic disable: duplicate-doc-alias
---@alias Manga { id: string, title: string, url: string?, cover: string?, banner: string?, anilist_search: string?, [any]: any }
---@alias Volume { number: number, [any]: any }
---@alias Chapter { title: string, url: string?, number: number?, date: string?, scanlation_group: string?, [any]: any }
---@alias Page { url: string, headers: table<string, string>?, cookies: table<string, string>?, extension: string?}

local sdk = require("sdk")

local http = sdk.http

local BASE_URL = "https://mangapill.com"
local USER_AGENT = "libmangal"

---@param query string
---@return string
local function query_to_search_url(query)
  query = query:lower()
  query = sdk.strings.trim_space(query)

  local params = sdk.urls.values()
  params:set("q", query)
  params:set("type", "")
  params:set("status", "")

  return BASE_URL .. "/search?" .. params:string()
end

---@param query string
---@return Manga[]
function SearchMangas(query)
  local url = query_to_search_url(query)

  local req = http.request(http.METHOD_GET, url)
  req:header("User-Agent", USER_AGENT)
  local res = req:send()

  if res:status() ~= http.STATUS_OK then
    error(res:status())
  end

  local html = sdk.html.parse(res:body())

  local mangas = {}

  local selector =
    "body > div.container.py-3 > div.my-3.grid.justify-end.gap-3.grid-cols-2.md\\:grid-cols-3.lg\\:grid-cols-5 > div"

  html:find(selector):each(function(selection)
    local title = selection:find("div a div.leading-tight"):text()
    local href = selection:find("div a:first-child"):attr_or("href", "")
    local cover = selection:find("img"):attr_or("data-src", "")
    local id = sdk.strings.split(href, "/")[3]

    local manga = {
      title = title,
      anilist_search = title,
      url = BASE_URL .. href,
      cover = cover,
      id = id,
    }

    table.insert(mangas, manga)
  end)

  return mangas
end

---@param manga Manga
---@return Volume[]
function MangaVolumes(manga)
  -- mangapill does not provide volumes
  return {
    {
      number = 1,
      manga_url = manga.url,
    },
  }
end

---@param volume Volume
---@return Chapter[]
function VolumeChapters(volume)
  local req = http.request(http.METHOD_GET, volume.manga_url)
  req:header("User-Agent", USER_AGENT)
  local res = req:send()

  if res:status() ~= http.STATUS_OK then
    error(res:status())
  end

  local html = sdk.html.parse(res:body())

  local chapters = {}

  local selector = "div[data-filter-list] a"
  html:find(selector):each(function(selection)
    local title = sdk.strings.trim_space(selection:text())
    local href = selection:attr_or("href", "")
    local number = sdk.strings.split(title, " ")[2]

    local chapter = {
      title = title,
      url = BASE_URL .. href,
      number = number,
      -- mangapill doesn't provide dates let luaprovider generate today's date
      date = "",
      scanlation_group = "Mangapill",
    }

    table.insert(chapters, chapter)
  end)

  return sdk.util.reverse(chapters)
end

---@param chapter Chapter
---@return Page[]
function ChapterPages(chapter)
  local req = http.request(http.METHOD_GET, chapter.url)
  req:header("User-Agent", USER_AGENT)
  local res = req:send()

  if res:status() ~= http.STATUS_OK then
    error(res:status())
  end

  local html = sdk.html.parse(res:body())

  local pages = {}
  local selector = "picture img"
  html:find(selector):each(function(selection)
    local url = selection:attr_or("data-src", "")

    local page = {
      url = url,
    }

    table.insert(pages, page)
  end)

  return pages
end
