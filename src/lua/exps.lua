local function asr_name (e, cnds, err_msg)
    ASR(e.dcl.tag~='Val', e, err_msg..' : expected name expression')
    --assert(e.dcl.tag ~= 'Val')
    local ok do
        for _, tag in ipairs(cnds) do
            if tag == e.dcl.tag then
                ok = true
                break
            end
        end
    end
    ASR(ok, e, err_msg..' : '..
                'unexpected context for '..AST.tag2id[e.dcl.tag]
                                         ..' "'..e.dcl.id..'"')
end

local function asr_if_name (e, cnds, err_msg)
    if e.dcl.tag == 'Val' then
        return
    else
        return asr_name(e, cnds, err_msg)
    end
end

EXPS = {
    asr_name    = asr_name,
    asr_if_name = asr_if_name,
}

INFO = {}

local function info_copy (dcl, tag, Type)
    local new = AST.copy(dcl)
    if tag then
        new.tag = tag
    end
    if Type then
        new[1] = AST.copy(Type)
    end
    new[2] = false  -- no '&'
    return new
end

function INFO.new (me, id, ...)
    local tp
    if AST.is_node(id) and (id.tag=='Type' or id.tag=='Typelist') then
        assert(not ...)
        tp = id
    else
        assert(type(id) == 'string')
        local ID = (string.sub(id,1,1)==string.sub(string.upper(id),1,1) and
                    'ID_abs' or 'ID_prim')
        tp = AST.node('Type', me.ln,
                AST.node(ID, me.ln,
                    id),
                ...)
    end
    local ret = AST.node('Val', me.ln, tp)
    ret.id = 'unknown'
    return ret
end

-------------------------------------------------------------------------------
-- NAMES
-------------------------------------------------------------------------------

F = {
-- IDs

--[[
    ID_prim = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, true, 'primitive identifier')
    end,

    ID_nat = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, true, 'native identifier')
    end,

    ID_ext = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, true, 'external identifier')
    end,

    ID_abs = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, true, 'abstraction')
    end,

    ID_int = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, false, 'internal identifier')
    end,
]]

-- TYPECAST: as

    Exp_as = function (me)
        local op,e,Type = unpack(me)
        if not e.dcl then return end

        -- ctx
        asr_if_name(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(not TYPES.check(e.dcl[1],'?'), me,
            'invalid operand to `'..op..'´ : unexpected option type')

        -- dcl
        me.dcl = info_copy(e.dcl)
        if AST.is_node(Type) then
            me.dcl[1] = AST.copy(Type)
        else
            -- annotation (/plain, etc)
DBG'TODO: type annotation'
        end
    end,

-- OPTION: !

    ['Exp_!'] = function (me)
        local op,e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.check(e.dcl[1],'?'), me,
            'invalid operand to `'..op..'´ : expected option type')

        -- dcl
        me.dcl = info_copy(e.dcl, nil, TYPES.pop(e.dcl[1]))
    end,

-- INDEX

    ['Exp_idx'] = function (me)
        local _,vec,idx = unpack(me)

        -- ctx, tp

        local tp = AST.copy(vec.dcl[1])
        tp[2] = nil
        if (vec.dcl.tag=='Var' or vec.dcl.tag=='Nat') and TYPES.is_nat(tp) then
            -- _V[0][0]
            -- var _char&&&& argv; argv[1][0]
            -- v[1]._plain[0]
            asr_name(vec, {'Nat','Var'}, 'invalid vector')
        else
            asr_name(vec, {'Vec'}, 'invalid vector')
        end

        -- dcl
        me.dcl = info_copy(vec.dcl, 'Var',
                    TYPES.check(vec.dcl[1],'&&') and TYPES.pop(vec.dcl[1]))
    end,

-- PTR: *

    ['Exp_1*'] = function (me)
        local op,e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')
DBG('TODO: remove pool')

        -- tp
        local _,mod = unpack(e.dcl[1])
        local is_ptr = TYPES.check(e.dcl[1],'&&')
        local is_nat_ptr = TYPES.is_nat_ptr(e.dcl[1])
        ASR(is_ptr or is_nat_ptr, me,
            'invalid operand to `'..op..'´ : expected pointer type')

        -- dcl
        me.dcl = info_copy(e.dcl, nil, is_ptr and TYPES.pop(e.dcl[1]))
    end,

-- MEMBER: .

    ['Exp_.'] = function (me)
        local _, e, member = unpack(me)
        if not e.dcl then return end

        ASR(TYPES.ID_plain(e.dcl[1]), me,
            'invalid operand to `.´ : expected plain type : got "'..
            TYPES.tostring(e.dcl[1])..'"')

        local ID_abs = AST.get(e.dcl,'', 1,'Type', 1,'ID_abs')
        if ID_abs and ID_abs.dcl.tag == 'Data' then
            -- data.member
            local blk = AST.asr(ID_abs.dcl,'Data', 2,'Block')
            me.dcl = info_copy(DCLS.asr(me,blk,member,false,e.dcl.id))
            me.dcl.blk = e.dcl.blk
        else
            me.dcl = info_copy(e.dcl)
        end
    end,

-- VECTOR LENGTH: $

    ['Exp_$'] = function (me)
        local op,vec = unpack(me)

        -- ctx
        asr_name(vec, {'Vec'}, 'invalid operand to `'..op..'´')

        -- tp
        -- any

        -- dcl
        me.dcl = INFO.new(me, 'usize')
        me.dcl.tag = 'Var'
    end,
}

AST.visit(F)

-------------------------------------------------------------------------------
-- EXPS
-------------------------------------------------------------------------------

G = {
    Exp_Name = function (me)
        local e = unpack(me)
        me.dcl = e.dcl
    end,

-- PRIMITIVES

    NULL = function (me)
        me.dcl = INFO.new(me, 'null', '&&')
    end,

    NUMBER = function (me)
        local v = unpack(me)
        if math.floor(v) == tonumber(v) then
            me.dcl = INFO.new(me, 'int')
        else
            me.dcl = INFO.new(me, 'float')
        end
    end,

    BOOL = function (me)
        me.dcl = INFO.new(me, 'bool')
    end,

    STRING = function (me)
        me.dcl = INFO.new(me, '_char', '&&')
    end,

-- SIZEOF

    SIZEOF = function (me)
        local e = unpack(me)

        -- ctx
        if e.tag ~= 'Type' then
            asr_if_name(e, {'Nat','Var'}, 'invalid operand to `sizeof´')
        end

        -- tp
        -- any

        -- dcl
        me.dcl = INFO.new(me, 'usize')
    end,

-- CALL

    Exp_Call = function (me)
        local _, e = unpack(me)

        -- ctx
        asr_name(e, {'Nat'}, 'invalid call')

        -- tp

        -- dcl
        me.dcl = e.dcl
    end,

    Abs_Call = function (me)
        local ID_abs = AST.asr(me,'', 2,'Abs_Cons', 1,'ID_abs')

        -- ctx
        asr_name(ID_abs, {'Code'}, 'invalid call')

        -- tp
        local id = unpack(ID_abs)
        ASR(ID_abs.dcl.tag=='Code', me,
            'invalid call : "'..id..'" is not a `code´ abstraction')

        -- dcl
        local _,_,_,_,out = unpack(ID_abs.dcl)
        me.dcl = INFO.new(me, AST.copy(out))
    end,

-- BIND

    ['Exp_1&'] = function (me)
        local op, e = unpack(me)

        -- ctx
        local par = me.__par
        ASR(par.tag=='Set_Alias' or par.tag=='Explist' or par.tag=='Abslist', me,
            'invalid expression : unexpected context for operation `&´')

        -- tp
        -- any

        -- dcl
        me.dcl = info_copy(e.dcl, 'Val')
        me.dcl[2] = '&'
    end,

-- INDEX ("idx" is Exp, not Exp_Name)

    ['Exp_idx'] = function (me)
        local _,_,idx = unpack(me)

        -- ctx
        asr_if_name(idx, {'Nat','Var'}, 'invalid index')

        -- tp
        ASR(TYPES.is_int(idx.dcl[1]), me,
            'invalid index : expected integer type')
    end,

-- POINTERS

    ['Exp_&&'] = function (me)
        local op, e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(not TYPES.check(e.dcl[1],'?'), me,
            'invalid operand to `'..op..'´ : unexpected option type')

        -- dcl
        me.dcl = info_copy(e.dcl, 'Val', TYPES.push(e.dcl[1],'&&'))
    end,

-- OPTION: ?

    ['Exp_?'] = function (me)
        local op,e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.check(e.dcl[1],'?'), me,
            'invalid operand to `'..op..'´ : expected option type')

        -- dcl
        me.dcl = INFO.new(me, 'bool')
    end,

-- VECTOR LENGTH: $$

    ['Exp_$$'] = F['Exp_$'],

-- NOT

    ['Exp_not'] = function (me)
        local op, e = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.check(e.dcl[1],'bool'), me,
            'invalid operand to `'..op..'´ : expected boolean type')

        -- dcl
        me.dcl = INFO.new(me, 'bool')
    end,

-- UNARY: +,-

    ['Exp_1+'] = 'Exp_num_num',
    ['Exp_1-'] = 'Exp_num_num',
    Exp_num_num = function (me)
        local op, e = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_num(e.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected numeric type')

        -- dcl
        me.dcl = info_copy(e.dcl, 'Val')
    end,

-- NUMERIC: +, -, %, *, /, ^

    ['Exp_+']  = 'Exp_num_num_num',
    ['Exp_-']  = 'Exp_num_num_num',
    ['Exp_%']  = 'Exp_num_num_num',
    ['Exp_*']  = 'Exp_num_num_num',
    ['Exp_/']  = 'Exp_num_num_num',
    ['Exp_^']  = 'Exp_num_num_num',
    Exp_num_num_num = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_num(e1.dcl[1]) and TYPES.is_num(e2.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected numeric type')

        -- dcl
        local max = TYPES.max(e1.dcl[1], e2.dcl[1])
        ASR(max, me, 'invalid operands to `'..op..'´ : '..
                        'incompatible numeric types : "'..
                        TYPES.tostring(e1.dcl[1])..'" vs "'..
                        TYPES.tostring(e2.dcl[1])..'"')
        me.dcl = INFO.new(me, AST.copy(max))
    end,

-- BITWISE

    ['Exp_|']  = 'Exp_int_int_int',
    ['Exp_&']  = 'Exp_int_int_int',
    ['Exp_<<'] = 'Exp_int_int_int',
    ['Exp_>>'] = 'Exp_int_int_int',
    Exp_int_int_int = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_int(e1.dcl[1]) and TYPES.is_int(e2.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected integer type')

        -- dcl
        local max = TYPES.max(e1.dcl[1], e2.dcl[1])
        ASR(max, me, 'invalid operands to `'..op..'´ : '..
                        'incompatible integer types : "'..
                        TYPES.tostring(e1.dcl[1])..'" vs "'..
                        TYPES.tostring(e2.dcl[1])..'"')
        me.dcl = INFO.new(me, AST.copy(max))
    end,

    ['Exp_~'] = function (me)
        local op, e = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_int(e.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected integer type')

        -- dcl
        me.dcl = info_copy(e.dcl, 'Val')
    end,

-- COMPARISON: >, >=, <, <=

    ['Exp_>='] = 'Exp_num_num_bool',
    ['Exp_<='] = 'Exp_num_num_bool',
    ['Exp_>']  = 'Exp_num_num_bool',
    ['Exp_<']  = 'Exp_num_num_bool',
    Exp_num_num_bool = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_num(e1.dcl[1]) and TYPES.is_num(e2.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected numeric type')

        -- dcl
        me.dcl = INFO.new(me, 'bool')
    end,

-- EQUALITY: ==, !=

    ['Exp_!='] = 'Exp_eq_bool',
    ['Exp_=='] = 'Exp_eq_bool',
    Exp_eq_bool = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp

        local ID1 = TYPES.ID_plain(e1.dcl[1])
        local ID2 = TYPES.ID_plain(e2.dcl[1])
        ASR( (not (ID1 and ID1.tag=='ID_abs')) and
             (not (ID2 and ID2.tag=='ID_abs')), me,
            'invalid operands to `'..op..'´ : unexpected `data´ value' )

        ASR(TYPES.contains(e1.dcl[1],e2.dcl[1]) or
            TYPES.contains(e2.dcl[1],e1.dcl[1]), me,
            'invalid operands to `'..op..'´ : '..
            'incompatible types : "'..
                TYPES.tostring(e1.dcl[1])..'" vs "'..
                TYPES.tostring(e2.dcl[1])..'"')

        -- dcl
        me.dcl = INFO.new(me, 'bool')
    end,

-- AND, OR

    ['Exp_or']  = 'Exp_bool_bool_bool',
    ['Exp_and'] = 'Exp_bool_bool_bool',
    Exp_bool_bool_bool = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.check(e1.dcl[1],'bool') and TYPES.check(e2.dcl[1],'bool'), me,
            'invalid operand to `'..op..'´ : expected boolean type')

        -- dcl
        me.dcl = INFO.new(me, 'bool')
    end,

-- IS, AS/CAST

    Exp_as = F.Exp_as,
    Exp_is = function (me)
        local op,e = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(not TYPES.check(e.dcl[1],'?'), me,
            'invalid operand to `'..op..'´ : unexpected option type')

        -- dcl
        me.dcl = INFO.new(me, 'bool')
    end,
}
AST.visit(G)
