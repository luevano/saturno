---@diagnostic disable: duplicate-doc-alias
---@alias Metadata { english_title: string?, romaji_title: string?, native_title: string?, synonyms: string[]?, community_score: number?, summary: string?, cover_image: string?, banner_image: string?, tag_list: string[]?, genre_list: string[]?, character_list: string[]?, author_list: string[]?, artist_list: string[]?, translator_list: string[]?, letterer_list: string[]?, date_start: string?, date_end: string?, provider_publisher: string?, publication_status: string?, publication_format: string?, country_of_origin: string?, chapter_count: number?, extra_notes: string?, source_url: string?, provider_id: string?, provider_id_code: string? }
---@alias Manga { id: string, title: string, url: string?, cover: string?, banner: string?, metadata: Metadata?, [any]: any }
---@alias Volume { number: number, [any]: any }
---@alias Chapter { title: string, url: string?, number: number?, date: string?, scanlation_group: string?, unavailable: string?, [any]: any }
---@alias Page { url: string, headers: table<string, string>?, cookies: table<string, string>?, extension: string? }

local sdk = require("sdk")

local http = sdk.http

local BASE_URL = "https://mangapill.com"

-- luaprovider sends its user agent by default
---@param url string
---@return table
local function get_html(url)
  -- check raises an error mangal can tell apart (not found, rate limited)
  local res = http.request(http.METHOD_GET, url):send():check()

  return sdk.html.parse(res:body())
end

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

  local html = get_html(url)

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
  local html = get_html(volume.manga_url)

  local chapters = {}

  local selector = "div[data-filter-list] a"
  html:find(selector):each(function(selection)
    local title = sdk.strings.trim_space(selection:text())
    local href = selection:attr_or("href", "")
    local number = tonumber(sdk.strings.split(title, " ")[2])

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
  local html = get_html(chapter.url)

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
