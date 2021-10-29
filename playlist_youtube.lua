--[[
 Youtube playlist importer for VLC media player 1.1 and 2.0
 Copyright 2012 Guillaume Le Maout

 Authors:  Guillaume Le Maout
 Contact: http://addons.entrylan.org/messages/?action=newmessage&username=exebetche

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
--]]

--[[
 MODified by Kai Gillmann, 19.01.2013, kaigillmann@googlemail.com:
 VLC HAS already a youtube importer, but not for playlists. IMO this mentioned one is
 better than this one, because it opens the entry in the best possible entry resolution.
 So i decided to remove all parts of the code which is not responsible for list handling.
 Now this lua script parses the list, as wanted, but for each entry opened, the vlc default
 Youtube script is used, so the entrys will be displayed properly.
--]]

--[[
 Patched by Aaron Hill (https://github.com/seraku24), 2018-05-16:
 The original script was failing in VLC 3.x due to an overzealous probe function.
 This patch makes the probe function more restrictive to avoid false positives.
--]]

--[[
 Patched by Nuv4 (https://github.com/nuv4), 2021-10-29:
 The original script was failing for new xml from youtube.
 This patch makes the.
--]]

-- Helper function to get a parameter's value in a URL
function get_url_param( url, name )
     local _, _, res = string.find( url, "[&?]"..name.."=([^&]*)" )
     return res
end

-- Probe function.
function probe()
     if vlc.access ~= "http" and vlc.access ~= "https" then
	     return false
     end

     return string.match(vlc.path:match("([^/]+)"),"%w+.youtube.com") and (
			 not string.match(vlc.path, "list_ajax") and string.match(vlc.path, "[?&]list="))
end

-- Parse function.
function parse()

     if string.match( vlc.path, "^consent%.youtube%.com/" ) then
        -- Cookie consent redirection
        -- Location: https://consent.youtube.com/m?continue=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DXXXXXXXXXXX&gl=FR&m=0&pc=yt&uxe=23983172&hl=fr&src=1
        -- Set-Cookie: CONSENT=PENDING+355; expires=Fri, 01-Jan-2038 00:00:00 GMT; path=/; domain=.youtube.com
        local url = get_url_param( vlc.path, "continue" )
		vlc.msg.err(url)
		

        if not url then
            vlc.msg.err( "Couldn't handle YouTube cookie consent redirection, please check for updates to this script or try disabling HTTP cookie forwarding" )
            return { }
			end
    return { { path = vlc.strings.decode_uri( url ), options = { ":no-http-forward-cookies" } } }
	    elseif not string.match( vlc.path, "^www%.youtube%.com/" ) then
        -- Skin subdomain
        return { { path = vlc.access.."://"..string.gsub( vlc.path, "^([^/]*)/", "www.youtube.com/" ) } }
	else if string.match( vlc.path, "list=" ) then
		local playlist_parsed, playlistData, line, s, item
		local p = {}
		local id_ref = {}
		local index = 0
		local playlistID = get_url_param( vlc.path, "list" )
		local entryID = get_url_param( vlc.path, "v" )
		local playlistURL = "https://www.youtube.com/feeds/videos.xml?playlist_id="..playlistID
		local prevLoaded = 0

		while true do
			playlistData = ""
			line = ""
			s = nil
			s = vlc.stream(playlistURL.."&index="..index)
			while line do
				playlistData = playlistData..line
				line = s:readline()
			end


			playlist_parsed = parse_xml(playlistData).feed.entry

			if playlist_parsed == nil then
				playlist_parsed = {}
			end

			for i, entry in ipairs(playlist_parsed) do
				if not id_ref[entry.id.CDATA] then

					vlc.msg.dbg(i.." "..entry.id.CDATA)
					id_ref[entry.id.CDATA] = true
					
					item = nil
					item = {}

					if entry["yt:videoId"]
					and entry["yt:videoId"]["CDATA"] then
					 	item.path = "http://www.youtube.com/watch?v="..entry["yt:videoId"]["CDATA"] 
					end

					if entry.title
					and entry.title.CDATA then
						item.title = entry.title.CDATA
					end

					if entry.author.name
					and entry.author.name.CDATA then
						item.artist = entry.author.name.CDATA
					end

					if entry.thumbnail
					and entry.thumbnail.CDATA then
						item.arturl = entry.thumbnail.CDATA
					end

					if entry.description
					and entry.description.CDATA then
						item.description = entry.description.CDATA
					end

					--~ item.rating = entry.rating
					table.insert (p, item)

				end
			end
			if #p > prevLoaded or index == 100 then
				vlc.msg.dbg("Playlist-Youtube: Loaded " ..#p.. " entrys...")
				index = index + 100
				prevLoaded = #p
			else
				vlc.msg.dbg("Playlist-Youtube: Finished loading " ..#p.. " entrys!")
				return p
			end
		end
	end
	end
end



function parse_xml(data)
	local tree = {}
	local stack = {}
	local tmp = {}
	local tmpTag = ""
	local level = 0

	table.insert(stack, tree)

	for op, tag, attr, empty, val in string.gmatch(
		data,
		"<(%p?)([^%s>/]+)([^>]-)(%/?)>[%s\r\n\t]*([^<]*)[%s\r\n\t]*") do
		if op=="?" then
			--~ DOCTYPE
		elseif op=="/" then
			if level>0 then
			level = level - 1
			table.remove(stack)
			end
		else
		level = level + 1

		if op=="!" then
			stack[level]['CDATA'] = vlc.strings.resolve_xml_special_chars(
			string.gsub(tag..attr, "%[CDATA%[(.+)%]%]", "%1"))
			attr = ""
			level = level - 1
		elseif type(stack[level][tag]) == "nil" then
			stack[level][tag] = {}
			table.insert(stack, stack[level][tag])
		else
			if type(stack[level][tag][1]) == "nil" then
			 tmp = nil
			 tmp = stack[level][tag]
			 stack[level][tag] = nil
			 stack[level][tag] = {}
			 table.insert(stack[level][tag], tmp)
			end
			tmp = nil
			tmp = {}
			table.insert(stack[level][tag], tmp)
			table.insert(stack, tmp)
			end

			if val~="" then
			stack[level][tag]['CDATA'] = {}
			stack[level][tag]['CDATA'] = vlc.strings.resolve_xml_special_chars(val)
			end

			if attr ~= "" then
			stack[level][tag]['ATTR'] = {}
				string.gsub(attr,
				"(%w+)=([\"'])(.-)%2",
				function (name, _, value)
				 stack[level][tag]['ATTR'][name] = value
				end)
			end

			if empty ~= "" then
				level = level - 1
				table.remove(stack)
			end
		end
	end
			
	return tree
end
