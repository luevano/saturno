---@diagnostic disable: duplicate-doc-alias
---@alias Manga { id: string, title: string, url: string?, cover: string?, banner: string?, anilist_search: string?, [any]: any }
---@alias Volume { number: number, [any]: any }
---@alias Chapter { title: string, url: string?, number: number?, date: string?, scanlation_group: string?, [any]: any }
---@alias Page { url: string, headers: table<string, string>?, cookies: table<string, string>?, extension: string?}

local sdk = require("sdk")

local http = sdk.http

local LANG = "en"

local BASE_URL = "https://mangadex.org"
local BASE_API_URL = "https://api.mangadex.org"
local USER_AGENT = "libmangal"

-- TODO: handle more than 100 responses, need to use the offset param
---@param query string
---@return Manga[]
function SearchMangas(query)
  local title = sdk.strings.trim_space(query:lower())
  local params = sdk.urls.values()
  params:set("limit", 100)
  params:set("title", title)
  params:set("order[followedCount]", "desc")
  params:set("includes[]", "cover_art")
  params:set("contentRating[]", "safe")
  params:add("contentRating[]", "suggestive")
  params:add("contentRating[]", "erotica")
  params:add("contentRating[]", "pornographic")
  local url = BASE_API_URL .. "/manga?" .. params:string()

  local req = http.request(http.METHOD_GET, url)
  req:header("User-Agent", USER_AGENT)
  local res = req:send()

  if res:status() ~= http.STATUS_OK then
    error(res:status())
  end

  local json = sdk.encoding.json.decode(res:body())

  local mangas = {}

  if json.total < 1 then
    return mangas
  end

  for _, m in ipairs(json.data) do
    local coverFilename = nil
    for _, r in ipairs(m.relationships) do
      if r.type == "cover_art" then
        coverFilename = r.attributes.fileName
      end
    end

    local coverURL = nil
    if coverFilename ~= nil then
      coverURL = BASE_URL .. "/covers/" .. m.id .. "/" .. coverFilename
    end

    -- TODO: better handle this
    -- the primary title isn't always the same key..
    local tempTitle = m.attributes.title.en
    if tempTitle == nil then
      tempTitle = m.attributes.title.ja
      if tempTitle == nil then
        tempTitle = m.attributes.title["ja-ro"]
      end
    end

    local manga = {
      title = tempTitle,
      anilist_search = m.attributes.title.en,
      url = BASE_URL .. "/title/" .. m.id,
      cover = coverURL,
      id = m.id,
    }
    table.insert(mangas, manga)
  end

  return mangas
end

---@param manga Manga
---@return Volume[]
function MangaVolumes(manga)
  local params = sdk.urls.values()
  params:set("translatedLanguage[]", LANG)
  local url = BASE_API_URL .. "/manga/" .. manga.id .. "/aggregate?" .. params:string()

  local req = http.request(http.METHOD_GET, url)
  req:header("User-Agent", USER_AGENT)
  local res = req:send()

  if res:status() ~= http.STATUS_OK then
    error(res:status())
  end

  local json = sdk.encoding.json.decode(res:body())

  local noneVolume = nil
  local volumes = {}
  for _, v in pairs(json.volumes) do
    if v.volume ~= "none" then
      local volume = {
        number = tonumber(v.volume),
        -- anything else can be passed down and will only be seen by this script
        -- manga_url = manga.url,
      }
      table.insert(volumes, volume)
    else
      noneVolume = { number = 0 }
    end
  end

  -- json.volumes is not a list, so it is ordered by its hash or whatever, need to sort
  table.sort(volumes, function(a, b)
    return a.number < b.number
  end)

  -- Add the "un-volumed" at the end
  if noneVolume ~= nil then
    table.insert(volumes, noneVolume)
  end

  return volumes
end

---@param volume Volume
---@return Chapter[]
function VolumeChapters(volume)
  local volumeNumber = "none"
  if volume.number ~= 0 then
    volumeNumber = volume.number
  end
  local params = sdk.urls.values()
  params:set("manga", volume.manga.id)
  params:set("volume[]", volumeNumber)
  params:set("limit", 100)
  params:set("translatedLanguage[]", LANG)
  params:set("order[chapter]", "desc")
  params:set("contentRating[]", "safe")
  params:add("contentRating[]", "suggestive")
  params:add("contentRating[]", "erotica")
  params:add("contentRating[]", "pornographic")
  params:add("includes[]", "scanlation_group")
  params:add("includes[]", "user")

  local url = BASE_API_URL .. "/chapter?" .. params:string()

  local req = http.request(http.METHOD_GET, url)
  req:header("User-Agent", USER_AGENT)
  local res = req:send()

  if res:status() ~= http.STATUS_OK then
    error(res:status())
  end

  local json = sdk.encoding.json.decode(res:body())

  local chapters = {}
  if json.total < 1 then
    return chapters
  end

  for _, c in ipairs(json.data) do
    -- ignore undownloadable chapters
    if c.attributes.externalUrl ~= nil then
      goto continue
    end

    local chapterNumber = c.attributes.chapter
    -- sometimes there is no chapter title, related to the scanlation group
    local title = c.attributes.title
    if title == "" then
      title = "Chapter " .. chapterNumber
    end
    local date = sdk.strings.split(c.attributes.publishAt, "T")[1]

    local scanlator = nil
    for _, r in pairs(c.relationships) do
      if r.type == "scanlation_group" then
        scanlator = r.attributes.name
        break
      end
    end

    if scanlator == nil then
      for _, r in pairs(c.relationships) do
        if r.type == "user" then
          scanlator = r.attributes.username
          break
        end
      end
    end

    if scanlator == nil then
      scanlator = "Mangadex"
    end

    local chapter = {
      title = title,
      url = BASE_URL .. "/chapter/" .. c.id,
      number = chapterNumber,
      date = date,
      scanlation_group = scanlator,
    }

    table.insert(chapters, chapter)
      ::continue::
  end

  return sdk.util.reverse(chapters)
end

---@param chapter Chapter
---@return Page[]
function ChapterPages(chapter)
  local chapterId = sdk.strings.split(chapter.url, "chapter/")[2]
  local url = BASE_API_URL .. "/at-home/server/" .. chapterId

  local req = http.request(http.METHOD_GET, url)
  req:header("User-Agent", USER_AGENT)
  local res = req:send()

  if res:status() ~= http.STATUS_OK then
    error(res:status())
  end

  local json = sdk.encoding.json.decode(res:body())
  local pages = {}

  for _, p in ipairs(json.chapter.data) do
    local page = {
      url = json.baseUrl .. "/data/" .. json.chapter.hash .. "/" .. p,
    }

    table.insert(pages, page)
  end

  return pages
end
