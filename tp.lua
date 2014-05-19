_TP = {
    types = {}
}

local __empty = {}
function _TP.get (id)
    return _TP.types[id] or __empty
end

function _TP.new (me)
    if me.tag == 'Type' then
        local id, ptr, arr, ref = unpack(me)

        me.id  = id
        me.ptr = ptr
        me.arr = arr
        me.ref = ref
        me.ext = (string.sub(id,1,1) == '_') or (id=='@')
        me.hold = true      -- holds by default

        -- var _tp[] v (pointer to _tp holding its own memory)
        -- (for pools `[]´ has another meaning)
        if (not (_AST and _AST.par(me,'Dcl_pool'))) and me.arr==true then
            me.arr = false
            me.mem = true
            ASR(me.ptr==0, me, 'invalid type')
            me.ptr = 1
        end

        -- set from outside (see "types" above and Dcl_nat in env.lua)
        me.prim  = false     -- if primitive
        me.num   = false     -- if numeric
        me.len   = nil       -- sizeof type
        me.plain = false     -- if plain type (no pointers inside it)

-- TODO: remove?
        if _ENV and me.ext and (not _ENV.c[me.id]) then
            _ENV.c[me.id] = { tag='type', id=me.id, len=nil, mod=nil }
        end

    else
        assert(me.tag == 'TupleType')
        me.id  = nil
        me.ptr = (#me==1 and 0) or 1
        me.arr = false
        me.ref = false
        me.ext = false

        me.tup = {}
        for i, t in ipairs(me) do
            local hold, tp, _ = unpack(t)
            tp.hold = hold

            if tp.id=='void' and tp.ptr==0 then
                ASR(#me==1, me, 'invalid type')
                me[1] = nil     -- empty tuple
                break
            end

            me.tup[#me.tup+1] = tp
        end

        if not _AST.par(me,'Dcl_fun') then
            _TP.types[_TP.toc(me)] = me     -- dump typedefs
        end
    end
    return me
end

-- primitive / numeric / len
local types = {
    void  = { true, false, 0 },
    char  = { true, true, 1 },
    byte  = { true, true, 1 },
    bool  = { true, true, 1 },
    word  = { true, true, _OPTS.tp_word },
    uint  = { true, true, _OPTS.tp_word },
    int   = { true, true, _OPTS.tp_word },
    u64   = { true, true, 8 },
    s64   = { true, true, 8 },
    u32   = { true, true, 4 },
    s32   = { true, true, 4 },
    u16   = { true, true, 2 },
    s16   = { true, true, 2 },
    u8    = { true, true, 1 },
    s8    = { true, true, 1 },
    float = { true, true, _OPTS.tp_word },
    f32   = { true, true, 4 },
    f64   = { true, true, 8 },

    pointer   = { false, false, _OPTS.tp_word },
    tceu_ncls = { false, false, true }, -- len set in "env.lua"
    tceu_nlbl = { false, false, true }, -- len set in "labels.lua"
}
for id, t in pairs(types) do
    _TP.types[id] = _TP.new{ tag='Type', id, false, false, false }
    _TP.types[id].prim = t[1]
    _TP.types[id].num  = t[2]
    _TP.types[id].len  = t[3]
end

function _TP.n2bytes (n)
    if n < 2^8 then
        return 1
    elseif n < 2^16 then
        return 2
    elseif n < 2^32 then
        return 4
    end
    error'out of bounds'
end

function _TP.copy (t)
    local ret = {}
    for k,v in pairs(t) do
        ret[k] = v
    end
    return ret
end

function _TP.fromstr (str)
    local id, ptr = string.match(str, '^(.-)(%**)$')
    assert(id and ptr)
    ptr = (id=='@' and 1) or string.len(ptr);
    return _TP.new{ tag='Type', id, ptr, false, false }
end

function _TP.toc (tp)
    if tp.tup then
        local t = { 'tceu' }
        for _, v in ipairs(tp.tup) do
            t[#t+1] = _TP.toc(v)
            if v.hold then
                t[#t] = t[#t] .. 'h'
            end
        end
        return string.gsub(table.concat(t,'__'),'%*','_')
    end

    local ret = tp.id

    if _TOPS[tp.id] then
        ret = 'CEU_'..ret
    end

    ret = ret .. string.rep('*',tp.ptr)

    if tp.arr then
        --error'not implemented'
        ret = ret .. '*'
    end

    if tp.ref then
        ret = ret .. '*'
    end

    return (string.gsub(ret,'^_', ''))
end

function _TP.tostr (tp)
    if tp.tup then
        local ret = {}
        for _, t in ipairs(tp.tup) do
            ret[#ret+1] = _TP.tostr(t)
        end
        return '('..table.concat(ret,',')..')'
    end

    local ret = tp.id
    ret = ret .. string.rep('*',tp.ptr)
    if tp.arr then
        ret = ret .. '[]'
    end
    if tp.ref then
        ret = ret .. '&'
    end
    return ret
end

function _TP.isNumeric (tp)
    return _TP.get(tp.id).num and tp.ptr==0 and (not tp.arr)
            or (tp.ext and tp.ptr==0)
            or tp.id=='@'
end

function _TP.contains (tp1, tp2)
    -- same type
    if tp1.id==tp2.id and tp1.ptr==tp2.ptr and tp1.arr==tp2.arr then
                                              -- i.e. false
        return true
    end

    -- tp[] vs tp*
    if tp1.id==tp2.id and ((tp1.ptr==1 and tp2.arr) or (tp2.ptr==1 and tp1.arr)) then
        return true
    end

    -- any type (calls, Lua scripts)
    if tp1.id=='@' or tp2.id=='@' then
        return true
    end

    if (tp1.ext and tp1.ptr==0) or (tp2.ext and tp2.ptr==0) then
        return true     -- let external types be handled by gcc
    end

    -- both are numeric
    if _TP.isNumeric(tp1) and _TP.isNumeric(tp2) then
        return true
    end

    -- compatible classes (same classes is handled above)
    local cls1 = _ENV.clss[tp1.id]
    local cls2 = _ENV.clss[tp2.id]
    if cls1 and cls2 then
        if tp1.ref or tp2.ref or (tp1.ptr>0 and tp2.ptr>0) then
            if tp1.ptr == tp2.ptr then
                return cls1.is_ifc and _ENV.ifc_vs_cls(cls1,cls2)
            end
        end
        return false
    end

    -- both are pointers
    if tp1.ptr>0 and tp2.ptr>0 then
        if tp1.id=='char' and tp1.ptr==1
        or tp1.id=='void' and tp1.ptr==1 then
            return true     -- any pointer can be cast to char*/void*
            -- TODO: void* too???
        end
        if tp2.id == 'null' then
            return true     -- any pointer can be assigned "null"
        end
        return false
    end

    -- c=accept ext // and at least one is ext
    if c and (_TP.ext(tp1) or _TP.ext(tp2)) then
        return true
    end

    -- tuples vs (tuples or single types)
    if tp1.tup or tp2.tup then
        tup1 = tp1.tup or { tp1 }
        tup2 = tp2.tup or { tp2 }
        if #tup1 == #tup2 then
            for i=1, #tup1 do
                local t1 = tup1[i]
                local t2 = tup2[i]
                if not _TP.contains(t1,t2) then
                    return false
                end
            end
        end
        return true
    end

    return false
end

function _TP.max (tp1, tp2)
    if _TP.contains(tp1, tp2) then
        return tp1
    elseif _TP.contains(tp2, tp1) then
        return tp2
    else
        return nil
    end
end
