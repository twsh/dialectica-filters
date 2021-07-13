--[[-- # Labelled-lists - custom labelled lists
 in Pandoc's markdown.

@author Julien Dutant <julien.dutant@kcl.ac.uk>
@copyright 2021 Julien Dutant
@license MIT - see LICENSE file for details.
@release 0.1
]]

-- # Internal settings

-- target_formats  filter is triggered when those format are targeted
local target_formats = {
  "html.*",
  "latex",
  "jats",
}

-- table of indentified labels
local labels_by_id = {}

-- html classes
local html_classes = {
    item = 'labelled-lists-item',
    label = 'labelled-lists-label',
    list = 'labelled-lists-list',
}

-- # Helper functions

--- format_matches: Test whether the target format is in a given list.
-- @param formats list of formats to be matched
-- @return true if match, false otherwise
function format_matches(formats)
  for _,format in pairs(formats) do
    if FORMAT:match(format) then
      return true
    end
  end
  return false
end

--- message: send message to std_error
-- @param type string INFO, WARNING, ERROR
-- @param text string text of the message
function message(type, text)
    local level = {INFO = 0, WARNING = 1, ERROR = 2}
    if level[type] == nil then type = 'ERROR' end
    if level[PANDOC_STATE.verbosity] <= level[type] then
        io.stderr:write('[' .. type .. '] Labelled-lists lua filter: ' 
            .. text .. '\n')
    end
end

-- # Filter functions

-- style_label: style the label
-- returns a styled label. Default: round brackets
-- @param label Inlines an item's label as list of inlines
function style_label(label)
    label:insert(1, pandoc.Str('('))
    label:insert(#label+1, pandoc.Str(')'))
    return label
end

--- build_list: processes a custom label list
-- returns a list of blocks containing Raw output format code
-- @param element BulletList the original Bullet List element
function build_list(element)

    -- build a list of blocks
    local list = pandoc.List:new()

    -- start

    if FORMAT:match('latex') then
        list:insert(pandoc.RawBlock('latex',
            '\\begin{itemize}\n\\tightlist'
            ))
    elseif FORMAT:match('html') then
        list:insert(pandoc.RawBlock('html',
            '<div class="' .. html_classes['list'] .. '">'
            ))
    end


    -- process each item

    for _,blocks in ipairs(element.c) do

        -- get the span, remove it from the tree, store its content
        local span = blocks[1].c[1]
        blocks[1].c:remove(1)
        local label = pandoc.List(span.content)
        local id = ''

        -- get identifier if not duplicate, store a copy in global table
        if not (span.identifier == '') then
            if labels_by_id[span.identifier] then
                message('WARNING', 'duplicate item identifier ' 
                    .. span.identifier .. '. The second is ignored.')
            else
                labels_by_id[span.identifier] = label:clone()
                id = span.identifier
            end
        end

        if FORMAT:match('latex') then

            local inlines = pandoc.List:new()
            inlines:insert(pandoc.RawInline('latex','\\item['))
            inlines:extend(style_label(label))
            inlines:insert(pandoc.RawInline('latex',']'))

            -- if the first block is Plain or Para, we insert
            -- the label code at the beginning
            -- otherwise we add a Plain block for the label
            if blocks[1].t == 'Plain' or blocks[1].t == 'Para' then
                inlines:extend(blocks[1].c)
                blocks[1].c = inlines
                list:extend(blocks)
            else
                list:insert(pandoc.Plain(inlines))
                list:extend(blocks)
            end

        elseif FORMAT:match('html') then

            local label_span = pandoc.Span(style_label(label))
            label_span.classes = { html_classes['label'] }
            if id then label_span.identifier = id end

            -- if there is only one block and it's Plain or Para,
            -- we create the item as <p>, otherwise as <div>
            if #blocks == 1 and 
                (blocks[1].t == 'Plain' or blocks[1].t == 'Para') then
                    local inlines = pandoc.List:new()
                    inlines:insert(1, pandoc.RawInline('html', 
                        '<p class="' .. html_classes['item'] .. '">'))
                    inlines:insert(label_span)
                    inlines:extend(blocks[1].c)
                    inlines:insert(pandoc.RawInline('html', '</p>'))
                    list:insert(pandoc.Plain(inlines))
            else
                -- if the first block is Plain or Para we insert the
                -- label in it, otherwise the label is its own paragraph
                if (blocks[1].t == 'Plain' or blocks[1].t == 'Para') then
                    local inlines = pandoc.List:new()
                    inlines:insert(label_span)
                    inlines:extend(blocks[1].c)
                    blocks[1].c = inlines
                else
                    blocks:insert(1, pandoc.Para(label_span))
                end

                list:insert(pandoc.Div(blocks,  
                    { class = html_classes['item'] } ))        

            end
 
        end

    end

    if FORMAT:match('latex') then
        list:insert(pandoc.RawBlock('latex',
            '\\end{itemize}\n'
            ))
    elseif FORMAT:match('html') then
        list:insert(pandoc.RawBlock('html','</div>'))        
    end

    return list
end

--- is_custom_labelled_list: Look for custom labels markup
-- Custom label markup requires each item starting with a span
-- containing the label
-- @param element pandoc BulletList element
function is_custom_labelled_list (element)

    local is_cl_list = true

    -- the content of BulletList is a List of List of Blocks
    for _,blocks in ipairs(element.c) do

        -- check that the first element of the first block is Span
        -- and not empty
        if not( blocks[1].c[1].t == 'Span' ) or 
            pandoc.utils.stringify(blocks[1].c[1].content) == '' then
            is_cl_list = false
            break 
        end
    end

    return is_cl_list
end

--- filter_list: Process custom labelled lists
-- If a list has the custom label markup, process labels
-- @param element pandoc BulletList element
function filter_list (element)
    
    if is_custom_labelled_list(element) then
        return build_list(element)
    end

end

--- filter_links: process internal links to labelled lists
-- Empty links to a custom label are filled with the custom
-- label text. 
-- @param element pandoc AST link
function filter_links (link)
    if pandoc.utils.stringify(link.content) == '' 
        and link.target:sub(1,1) == '#' 
        and labels_by_id[link.target:sub(2,-1)] then
            link.content = labels_by_id[link.target:sub(2,-1)]
        return link
    end
end


--- Main code
-- return the filter on BulletList elements
if format_matches(target_formats) then
    return {
      {
        BulletList = filter_list
      },
      {
        Link = filter_links
      }
    }
end