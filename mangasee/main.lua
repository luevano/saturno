---@alias Manga { id: string, title: string, url: string?, cover: string?, banner: string?, anilist_search: string?, [any]: any }
---@alias Volume { number: number, [any]: any }
---@alias Chapter { title: string, url: string?, number: number?, [any]: any }
---@alias Page { url: string, headers: table<string, string>?, cookies: table<string, string>?, extension: string?}

local sdk = require("sdk")
local browser = sdk.headless.browser()

local BASE_URL = "https://mangasee123.com"

---@param query string
---@return string
local function query_to_search_url(query)
  query = query:lower()
  query = sdk.strings.trim_space(query)

  local params = sdk.urls.values()
  params:set("sort", "s")
  params:set("desc", "false")
  params:set("name", query)

  return BASE_URL .. "/search/?" .. params:string()
end

---@param query string
---@return Manga[]
function SearchMangas(query)
  local url = query_to_search_url(query)

  local page = browser:page(url)
  local html = sdk.html.parse(page:html())

  local mangas = {}

  local selector =
    "div.row > div.col-md-8.order-md-1.order-12 > div.ng-scope > div.top-15.ng-scope > div.row"

  html:find(selector):each(function(selection)
    -- the href could be taken from either the title div or the href div
    local title = selection:find("div.col-md-10.col-8 > a.SeriesName.ng-binding"):text()
    local href = selection:find("div.col-md-2.col-4 > a.SeriesName"):attr_or("href", "")
    local cover = selection:find("div.col-md-2.col-4 > a.SeriesName > img"):attr_or("src", "")
    -- there is really no id
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
  -- mangasee does not provide volumes
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
  local page = browser:page(volume.manga_url)

  -- TODO: need to test with a manga that doesn't need to click this button (has few chapters)
  local showAllElem = page:element(".ShowAllChapters")
  if showAllElem ~= nil then
    showAllElem:click()
  end
  local html = sdk.html.parse(page:html())

  local chapters = {}

  html:find(".ChapterLink"):each(function(selection)
    -- the title is really nasty
    local title = selection:find('span'):first():text()
    title = sdk.strings.replace_all(title, "\t", "")
    title = sdk.strings.replace_all(title, "\n", " ")
    title = sdk.strings.trim_space(title)
    local href = selection:attr_or("href", "")
    local number = sdk.strings.split(title, " ")[2]

    local chapter = {
      title = title,
      url = BASE_URL .. href,
      number = number,
    }

    table.insert(chapters, chapter)
  end)

  return sdk.util.reverse(chapters)
end

---@param chapter Chapter
---@return Page[]
function ChapterPages(chapter)
  local page = browser:page(chapter.url)

  -- display all images in "long strip"
  page:element(".DesktopNav > div.row > div:nth-child(4) > button"):click()
  local html = sdk.html.parse(page:html())

  local pages = {}
  html:find(".ImageGallery > div.ng-scope > div.ng-scope > img.img-fluid.HasGap"):each(function(selection)
    local url = selection:attr_or("src", "")
    local p = {
      url = url,
    }
    table.insert(pages, p)
  end)

  return pages
end
