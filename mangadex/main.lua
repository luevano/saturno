---@diagnostic disable: duplicate-doc-alias
---@alias Metadata { english_title: string?, romaji_title: string?, native_title: string?, synonyms: string[]?, community_score: number?, summary: string?, cover_image: string?, banner_image: string?, tag_list: string[]?, genre_list: string[]?, character_list: string[]?, author_list: string[]?, artist_list: string[]?, translator_list: string[]?, letterer_list: string[]?, date_start: string?, date_end: string?, provider_publisher: string?, publication_status: string?, publication_format: string?, country_of_origin: string?, chapter_count: number?, extra_notes: string?, source_url: string?, provider_id: string?, provider_id_code: string? }
---@alias Manga { id: string, title: string, url: string?, cover: string?, banner: string?, metadata: Metadata?, [any]: any }
---@alias Volume { number: number, [any]: any }
---@alias Chapter { title: string, url: string?, number: number?, date: string?, scanlation_group: string?, unavailable: string?, [any]: any }
---@alias Page { url: string, headers: table<string, string>?, cookies: table<string, string>?, extension: string? }

local sdk = require("sdk")

local http = sdk.http
-- older luaprovider versions don't have the options
local options = sdk.options or { language = "en", avoid_duplicate_chapters = true }

local LANG = options.language ~= "" and options.language or "en"

local BASE_URL = "https://mangadex.org"
local BASE_API_URL = "https://api.mangadex.org"
-- mangadex blocks spoofed user agents (e.g. a browser one), so not the default one
local USER_AGENT = "saturno (+https://github.com/luevano/saturno)"

local STATUSES = {
  ongoing = "RELEASING",
  completed = "FINISHED",
  hiatus = "HIATUS",
  cancelled = "CANCELLED",
}

---@param url string
---@return table
local function get_json(url)
  local req = http.request(http.METHOD_GET, url)
  req:header("User-Agent", USER_AGENT)
  local res = req:send()

  if res:status() ~= http.STATUS_OK then
    error("GET " .. url .. ": " .. res:status())
  end

  return sdk.encoding.json.decode(res:body())
end

---@param params table
local function add_content_ratings(params)
  params:add("contentRating[]", "safe")
  params:add("contentRating[]", "suggestive")
  if options.nsfw then
    params:add("contentRating[]", "erotica")
    params:add("contentRating[]", "pornographic")
  end
end

---@param titles table<string, string>
---@return string?
local function any_title(titles)
  for _, title in pairs(titles) do
    return title
  end
  return nil
end

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
  add_content_ratings(params)

  local json = get_json(BASE_API_URL .. "/manga?" .. params:string())

  local mangas = {}
  for _, m in ipairs(json.data) do
    local coverURL = nil
    for _, r in ipairs(m.relationships) do
      if r.type == "cover_art" and r.attributes ~= nil then
        coverURL = BASE_URL .. "/covers/" .. m.id .. "/" .. r.attributes.fileName
      end
    end

    -- the main title isn't always in the same language
    local titles = m.attributes.title
    local romaji = titles["ja-ro"]
    local native = titles.ja
    for _, alt in ipairs(m.attributes.altTitles) do
      romaji = romaji or alt["ja-ro"]
      native = native or alt.ja
    end
    local mangaTitle = titles.en or romaji or native or any_title(titles)

    local tags, genres = {}, {}
    for _, tag in ipairs(m.attributes.tags) do
      local name = tag.attributes.name.en
      if name ~= nil then
        if tag.attributes.group == "genre" then
          table.insert(genres, name)
        else
          table.insert(tags, name)
        end
      end
    end

    local manga = {
      title = mangaTitle,
      url = BASE_URL .. "/title/" .. m.id,
      cover = coverURL,
      id = m.id,
      metadata = {
        english_title = titles.en,
        romaji_title = romaji,
        native_title = native,
        summary = m.attributes.description.en,
        publication_status = STATUSES[m.attributes.status],
        genre_list = genres,
        tag_list = tags,
      },
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

  local json = get_json(BASE_API_URL .. "/manga/" .. manga.id .. "/aggregate?" .. params:string())

  local noneVolume = nil
  local volumes = {}
  for _, v in pairs(json.volumes) do
    if v.volume ~= "none" then
      table.insert(volumes, { number = tonumber(v.volume) })
    else
      -- anything else can be passed down and will only be seen by this script
      noneVolume = { number = 0, none = true }
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

-- keeps one chapter per number: a downloadable one, from the group with the most uploads in the volume
---@param chapters Chapter[]
---@return Chapter[]
local function unique_chapters(chapters)
  local uploads = {}
  for _, c in ipairs(chapters) do
    uploads[c.scanlation_group] = (uploads[c.scanlation_group] or 0) + 1
  end

  local better = function(a, b)
    if (a.unavailable == nil) ~= (b.unavailable == nil) then
      return a.unavailable == nil
    end
    return uploads[a.scanlation_group] > uploads[b.scanlation_group]
  end

  local unique = {}
  local byNumber = {}
  for _, c in ipairs(chapters) do
    -- chapters without a number (e.g. oneshots) are all kept
    local key = c.number
    if key == nil then
      table.insert(unique, c)
    elseif byNumber[key] == nil then
      byNumber[key] = #unique + 1
      table.insert(unique, c)
    elseif better(c, unique[byNumber[key]]) then
      unique[byNumber[key]] = c
    end
  end
  return unique
end

---@param volume Volume
---@return Chapter[]
function VolumeChapters(volume)
  local volumeNumber = "none"
  if not volume.none then
    volumeNumber = volume.number
  end
  local params = sdk.urls.values()
  params:set("manga", volume.manga.id)
  params:set("volume[]", volumeNumber)
  params:set("limit", 100)
  params:set("translatedLanguage[]", LANG)
  params:set("order[chapter]", "asc")
  add_content_ratings(params)
  params:add("includes[]", "scanlation_group")
  params:add("includes[]", "user")
  if not options.show_unavailable_chapters then
    params:set("includeEmptyPages", 0)
  end

  local chapters = {}
  local offset = 0
  repeat
    params:set("offset", offset)
    local json = get_json(BASE_API_URL .. "/chapter?" .. params:string())

    for _, c in ipairs(json.data) do
      local chapterNumber = c.attributes.chapter
      -- sometimes there is no chapter title, related to the scanlation group
      local title = c.attributes.title
      if title == nil or title == "" then
        title = chapterNumber ~= nil and ("Chapter " .. chapterNumber) or "Oneshot"
      end
      local date = sdk.strings.split(c.attributes.publishAt, "T")[1]

      local scanlator = nil
      for _, r in ipairs(c.relationships) do
        if r.type == "scanlation_group" and r.attributes ~= nil then
          scanlator = r.attributes.name
          break
        end
      end
      if scanlator == nil then
        for _, r in ipairs(c.relationships) do
          if r.type == "user" and r.attributes ~= nil then
            scanlator = r.attributes.username
            break
          end
        end
      end

      -- luaprovider hides these unless the user wants to see them
      local unavailable = nil
      if c.attributes.externalUrl ~= nil then
        unavailable = "external"
      elseif c.attributes.pages == 0 then
        unavailable = "0 pages"
      end

      table.insert(chapters, {
        id = c.id,
        title = title,
        url = BASE_URL .. "/chapter/" .. c.id,
        -- without a number luaprovider puts it right after the previous chapter
        number = tonumber(chapterNumber),
        date = date,
        scanlation_group = scanlator or "Mangadex",
        unavailable = unavailable,
      })
    end

    offset = offset + json.limit
  until offset >= json.total

  if options.avoid_duplicate_chapters then
    return unique_chapters(chapters)
  end
  return chapters
end

---@param chapter Chapter
---@return Page[]
function ChapterPages(chapter)
  local json = get_json(BASE_API_URL .. "/at-home/server/" .. chapter.id)

  local pages = {}
  for _, filename in ipairs(json.chapter.data) do
    table.insert(pages, {
      url = json.baseUrl .. "/data/" .. json.chapter.hash .. "/" .. filename,
      extension = filename:match("%.%w+$"),
      headers = { ["User-Agent"] = USER_AGENT },
    })
  end

  return pages
end
