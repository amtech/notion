--
-- ion/mod_panews/mod_panews.lua
-- 
-- Copyright (c) Tuomo Valkonen 2004.
-- 
-- Ion is free software; you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation; either version 2.1 of the License, or
-- (at your option) any later version.
--


-- This is a slight abuse of the _LOADED variable perhaps, but library-like 
-- packages should handle checking if they're loaded instead of confusing 
-- the user with require/include differences.
if _LOADED["templates"] then return end

if not ioncore.load_module("mod_panews") then
    return
end

assert(not _G["mod_panews"]);
local mod_panews={}
_G["mod_panews"]=mod_panews

local private={}
local settings={}

-- Settings {{{

-- Classes:
--  (T)erminal
--  (V)iewer
--  (M)isc
settings.valid_classifications={["V"]=true, ["T"]=true, ["M"]=true,}

-- Xterm, rxvt, aterm, etc. all have "XTerm" as class part of WM_CLASS
settings.terminal_emulators={["XTerm"]=true,} 

-- Pixel scale factor from 1280x1024/75dpi
settings.scalef=1.0

--settings.b_ratio=(1+math.sqrt(5))/2
--settings.s_ratio=1
settings.b_ratio=3
settings.s_ratio=2

settings.b_ratio2=7
settings.s_ratio2=1

settings.templates={}

settings.templates["default"]={
    type="WSplitFloat",
    dir="horizontal",
    tls=settings.b_ratio,
    brs=settings.s_ratio,
    tl={
        type="WSplitPane",
        contents={
            type="WSplitFloat",
            dir="vertical",
            tls=settings.b_ratio2,
            brs=settings.s_ratio2,
            tl={
                type="WSplitPane",
                marker="V:single",
            },
            br={
                type="WSplitPane",
                marker="M:right",
            },
        },
    },
    br={
        type="WSplitPane",
        marker="T:up",
    },
}


settings.templates["alternative1"]={
    type="WSplitFloat",
    dir="horizontal",
    tls=settings.s_ratio2,
    brs=settings.b_ratio2,
    tl={
        type="WSplitPane",
        marker="M:down",
    },
    br={
        type="WSplitFloat",
        dir="vertical",
        tls=settings.b_ratio,
        brs=settings.s_ratio,
        tl={
            type="WSplitPane",
            marker="V:single",
        },
        br={
            type="WSplitPane",
            marker="T:right",
        },
    },
}


settings.templates["alternative2"]={
    type="WSplitFloat",
    dir="vertical",
    tls=settings.b_ratio,
    brs=settings.s_ratio,
    tl={
        type="WSplitFloat",
        dir="horizontal",
        tls=settings.s_ratio2,
        brs=settings.b_ratio2,
        tl={
            type="WSplitPane",
            marker="M:down",
        },
        br={
            type="WSplitPane",
            marker="V:single",
        },
    },
    br={
        type="WSplitPane",
        marker="T:right",
    },
}


settings.template=settings.templates["default"]

settings.shrink_minimum=32

--DOC
-- Set some module parameters. Currently \var{s} may contain the following
-- fields:
-- \begin{tabularx}{\linewidth}{lX}
--  \hline
--  Field & Description \\
--  \hline
--  \var{template} & layout template for newly created \type{WPaneWS} 
--                   workspaces. This can be either a table or one of the 
--                   predefined layouts 'default', 'alternative1', and
--                   'alternative2'. \\
--  \var{scalef}   & Scale factor for classification heuristics to work 
--                   with different screen resolutions. The default is 1.0 
--                   and is designed for 1280x1024 at 75dpi. \\
--  \var{valid_classifications} & A table with valid window classifications
--                                as valid keys. \\
-- \end{tabularx}
function mod_panews.set(s)
    if s.template then
        local ok=false
        if type(s.template)=="string" then
            if settings.templates[s.template] then
                settings.template=settings.templates[s.template]
                ok=true
            end
        elseif type(s.template)=="table" then
            settings.template=s.template
        end
        if not ok then
            warn("Invalid template.")
        end
    end
    if s.scalef then
        if type(s.scalef)~="number" or s.scalef<=0 then
            warn('Invalid scale factor')
        else
            settings.scalef=s.scalef
        end
    end
    
    if type(s.valid_classifications)=="table" then
        settings.valid_classifications=s.valid_classifications
    end
end


--DOC
-- Get some module settings. See \fnref{mod_panews.set} for documentation
-- on the contents of the returned table.
function mod_panews.get()
    return table.copy(settings, true)
end

                        
-- }}}


-- Helper code {{{

local function sfind(s, p)
    local function drop2(a, b, ...)
        return unpack(arg)
    end
    return drop2(string.find(s, p))
end


function private.div_length(w, r1, r2)
    local a=math.ceil(w*r1/(r1+r2))
    return a, w-a
end

function private.split3(d, ls, cs, rs, lo, co, ro)
    return {
        tls = ls+cs,
        brs = rs,
        dir = d,
        tl = {
            tls = ls,
            brs = cs,
            dir = d,
            tl = (lo or {}),
            br = (co or {}),
        },
        br = (ro or {}),
    }
end

function private.center3(d, ts, cs, lo, co, ro)
    local sc=math.min(ts, cs)
    local sl=math.floor((ts-sc)/2)
    local sr=ts-sc-sl
    local r=private.split3(d, sl, sc, sr, lo, co, ro)
    return r
end

function private.split2(d, ts, ls, rs, lo, ro)
    if ls and rs then
        assert(ls+rs==ts)
    elseif not ls then
        ls=ts-rs
    else
        rs=ts-ls
    end
    assert(rs>=0 and ls>=0)
    return {
        type="WSplitSplit",
        dir=d,
        tls=math.floor(ls),
        brs=math.ceil(rs),
        tl=lo,
        br=ro,
    }
end

-- }}}


-- Classification {{{

function private.classify(ws, reg)
    if obj_is(reg, "WClientWin") then
        -- Check if there's a winprop override
        local wp=ioncore.getwinprop(reg)
        if wp and wp.panews_classification then
            if settings.valid_classifications[wp.panews_classification] then
                return wp.panews_classification
            end
        end
        
        -- Handle known terminal emulators.
        local id=reg:get_ident()
        if settings.terminal_emulators[id.class] then
            return "T"
        end
    end
    
    -- Try size heuristics.
    local cg=reg:geom()

    if cg.w<3/8*(1280*settings.scalef) then
        return "M"
    end
    
    if cg.h>4/8*(960*settings.scalef) then
        return "V"
    else
        return "T"
    end
end

-- }}}


-- Placement code {{{

function private.use_unused(p, n, d, forcefit)
    if d=="single" then
        p.res_node=n
        p.res_config={reg=p.frame}
        return true
    end

    -- TODO: Check fit
    local sg=n:geom()
    local fsh=p.frame:size_hints()
    local fg=p.frame:geom()
    
    if d=="up" or d=="down" then
        p.res_node=n
        if fsh.min_h>sg.h then
            return false
        end
        local fh=math.min(fg.h, sg.h)
        if d=="up" then
            p.res_config=private.split2("vertical", sg.h, nil, fh,
                                  {}, {reg=p.frame})
        else
            p.res_config=private.split2("vertical", sg.h, fh, nil,
                                  {reg=p.frame}, {})
        end
        return true
    elseif d=="left" or d=="right" then
        p.res_node=n
        if fsh.min_w>sg.w then
            return false
        end
        local fw=math.min(fg.w, sg.w)
        if d=="left" then
            p.res_config=private.split2("horizontal", sg.w, nil, fw,
                                  {}, {reg=p.frame})
        else
            p.res_config=private.split2("horizontal", sg.w, fw, nil,
                                  {reg=p.frame}, {})
        end
        return true
    end
end


function private.scan_pane(p, node, pdir)
    local function do_scan_active(n)
        local t=obj_typename(n)
        if t=="WSplitRegion" then
            p.res_node=n
            return true
        elseif t=="WSplitSplit" or t=="WSplitFloat" then
            local a, b=n:tl(), n:br()
            if b==n:current() then
                a, b=b, a
            end
            return (do_scan_active(a) or do_scan_active(b))
        end
    end

    local function do_scan_unused(n, d, forcefit)
        local t=obj_typename(n)
        if t=="WSplitSplit" or t=="WSplitFloat" then
            local sd=n:dir()
            if sd=="vertical" then
                if d=="up" then
                    return do_scan_unused(n:tl(), d, forcefit)
                elseif d=="down" then
                    return do_scan_unused(n:br(), d, forcefit)
                end
            elseif sd=="horizontal" then
                if d=="left" then
                    return do_scan_unused(n:tl(), d, forcefit)
                elseif d=="right" then
                    return do_scan_unused(n:br(), d, forcefit)
                end
            end
        elseif t=="WSplitUnused" then
            -- Found it
            return private.use_unused(p, n, d, forcefit)
        end
    end
    
    if do_scan_unused(node, pdir, false) then
        return true
    end
    
    if do_scan_active(node, pdir) then
        return true
    end

    return do_scan_unused(node, pdir, true)
end
    

function private.make_placement(p)
    if p.specifier then
        local n=p.specifier
        local pcls, pdir
        
        while n and not obj_is(n, "WSplitPane") do
            n=n:parent()
        end
        
        if n then
            pcls, pdir=sfind((n:marker() or ""), "(.*):(.*)")
        end
            
        return private.use_unused(p, p.specifier, (pdir or "single"), false)
    end
    
    local cls=private.classify(p.ws, p.reg)
    
    local function do_scan_cls(n)
        local t=obj_typename(n)
        if t=="WSplitPane" then
            local m=n:marker()
            if m then
                local pcls, pdir=sfind(m, "(.*):(.*)")
                if pcls and pcls==cls then
                    return private.scan_pane(p, n:contents(), pdir)
                end
            else
                return do_scan_cls(n:contents())
            end
        elseif t=="WSplitSplit" or t=="WSplitFloat" then
            return (do_scan_cls(n:tl()) or do_scan_cls(n:br()))
        end
    end
    
    local function do_scan_fallback(n)
        local t=obj_typename(n)
        if t=="WSplitUnused" then
            p.res_node=n
            p.res_config={reg=p.frame}
            return true
        elseif t=="WSplitRegion" then
            p.res_node=n
            return true
        elseif t=="WSplitPane" then
            return do_scan_fallback(n:contents())
        elseif t=="WSplitSplit" or t=="WSplitFloat" then
            return (do_scan_fallback(n:tl()) or do_scan_fallback(n:br()))
        end
    end
    
    local node=p.ws:split_tree()
    return (do_scan_cls(node) or do_scan_fallback(node))
end

-- }}}


-- Layout initialisation {{{


function private.calc_sizes(tmpl, sw, sh)
    tmpl._w, tmpl._h=sw, sh

    if tmpl.type=="WSplitSplit" or tmpl.type=="WSplitFloat" then
        local tmps, tlw, tlh, brw, brh
        -- Calculate pixel sizes of things
        if tmpl.dir=="vertical" then
            tmps=sh
        else
            tmps=sw
        end
        
        tmpl.tls, tmpl.brs=private.div_length(tmps, tmpl.tls, tmpl.brs)
    
        if tmpl.dir=="vertical" then
            tlw, brw=sw, sw
            tlh, brh=tmpl.tls, tmpl.brs
        else
            tlw, brw=tmpl.tls, tmpl.brs
            tlh, brh=sh, sh
        end
    
        private.calc_sizes(tmpl.tl, tlw, tlh)
        private.calc_sizes(tmpl.br, brw, brh)
    end
end


function private.init_layout(p)
    p.layout=table.copy(settings.template, true) -- deep copy template
    local wg=p.ws:geom()
    private.calc_sizes(p.layout, wg.w, wg.h)
    return true
end

-- }}}


-- Initialisation {{{

function private.setup_hooks()
    local function hookto(hkname, fn)
        local hk=ioncore.get_hook(hkname)
        if not hk then
            error("No hook "..hkname)
        end
        if not hk:add(fn) then
            error("Unable to hook to "..hkname)
        end
    end

    hookto("panews_init_layout_alt", private.init_layout)
    hookto("panews_make_placement_alt", private.make_placement)
end


private.setup_hooks()

-- }}}


-- Mark ourselves loaded.
_LOADED["templates"]=true


-- Load configuration file
dopath('cfg_panews', false)
