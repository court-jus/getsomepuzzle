-- pandoc_links.lua
-- Rewrite cross-doc links for the dev-docs PDF build.
--
-- 1. Each input file's first H1 becomes the anchor for that file: its
--    identifier is forced to the basename (without `.md`).
-- 2. Every Markdown link whose target ends in `.md` is rewritten to
--    `#<basename>` so it lands on the matching section in the PDF.
--
-- Used by bin/build_dev_docs_pdf.sh.

local filenames = {}
for _, path in ipairs(PANDOC_STATE.input_files) do
  table.insert(filenames, path:match("([^/]+)%.md$"))
end

local h1_index = 0
function Header(el)
  if el.level == 1 then
    h1_index = h1_index + 1
    local fname = filenames[h1_index]
    if fname then el.identifier = fname end
  end
  return el
end

function Link(el)
  local base = el.target:match("^(.+)%.md$")
  if base then el.target = "#" .. base end
  return el
end
