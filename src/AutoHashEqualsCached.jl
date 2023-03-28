module AutoHashEqualsCached

export @auto_hash_equals_cached, @auto_hash_equals

"""
  `_show_default_auto_hash_equals_cached` is just like `Base._show_default(io, x)`,
  except it ignores fields named `_cached_hash`.  This function is called in the
  implementation of `T._show_default` for types `T` annotated with
  `@auto_hash_equals_cached`.  This is ultimately used in the implementation of
  `Base.show`.  This specialization ensures that showing circular data structures does not
  result in infinite recursion.
"""
function _show_default_auto_hash_equals_cached(io::IO, @nospecialize(x))
    t = typeof(x)
    show(io, Base.inferencebarrier(t)::DataType)
    print(io, '(')
    recur_io = IOContext(io, Pair{Symbol,Any}(:SHOWN_SET, x),
                         Pair{Symbol,Any}(:typeinfo, Any))
    if !Base.show_circular(io, x)
        for i in 1:nfields(x)
            f = fieldname(t, i)
            if (f == :_cached_hash)
                continue
            elseif i > 1
                print(io, ", ")
            end
            if !isdefined(x, f)
                print(io, Base.undef_ref_str)
            else
                show(recur_io, getfield(x, i))
            end
        end
    end
    print(io,')')
end

"""
An exception used for reporting errors.
"""
struct AutoHashEqualsException <: Exception
    msg::String
end
error(msg::String) = throw(AutoHashEqualsException(msg))

"""
Find the first struct declaration buried in the Expr.
"""
get_struct_decl(typ) = nothing
function get_struct_decl(typ::Expr)
    if typ.head == :struct
        return typ
    elseif typ.head == :macrocall
        return get_struct_decl(typ.args[3])
    elseif typ.head == :block
        # get the first struct decl in the block
        for x in typ.args
            if x.head == :macrocall || x.head == :struct || x.head == :block
                result = get_struct_decl(x)
                if (result !== nothing)
                    return result
                end
            end
        end
    end

    error("macro @auto_hash_equals_cached should only be applied to a struct")
end

unpack_name(node) = node
function unpack_name(node::Expr)
    if node.head == :macrocall
        unpack_name(node.args[3])
    elseif node.head in (:(<:), :(::))
        unpack_name(node.args[1])
    else
        node
    end
end

unpack_type_name(n::Symbol) = (n, n, nothing)
function unpack_type_name(n::Expr)
    if n.head == :curly
        type_name = n.args[1]
        type_name isa Symbol ||
            error("macro @auto_hash_equals_cached applied to type with invalid signature")
        where_list = n.args[2:length(n.args)]
        type_params = map(unpack_name, where_list)
        full_type_name = Expr(:curly, type_name, type_params...)
        (type_name, full_type_name, where_list)
    elseif n.head == :(<:)
        unpack_type_name(n.args[1])
    else
        error("macro @auto_hash_equals_cached applied to type with unexpected signature")
    end
end

function get_fields(struct_decl::Expr)
    member_names = Vector{Symbol}()
    member_decls = Vector()

    add_field(b) = nothing
    function add_field(b::Symbol)
        push!(member_names, b)
        push!(member_decls, b)
    end
    function add_field(b::Expr)
        if b.head == :block
            add_fields(field)
        elseif b.head == :const
            add_field(b.args[1])
        elseif b.head == :(::) && b.args[1] isa Symbol
            push!(member_names, b.args[1])
            push!(member_decls, b)
        elseif b.head == :macrocall
            add_field(b.args[3])
        end
    end
    function add_fields(b::Expr)
        @assert b.head == :block
        for field in b.args
            add_field(field)
        end
    end

    @assert (struct_decl.args[3].head == :block)
    add_fields(struct_decl.args[3])
    (member_names, member_decls)
end

macro auto_hash_equals_cached(typ::Expr)
    struct_decl = get_struct_decl(typ)
    @assert struct_decl.head == :struct
    type_body = struct_decl.args[3].args

    !struct_decl.args[1] ||
        error("macro @auto_hash_equals_cached should only be applied to a non-mutable struct")

    (type_name, full_type_name, where_list) = unpack_type_name(struct_decl.args[2])
    @assert type_name isa Symbol

    (member_names, member_decls) = get_fields(struct_decl)

    # Add the cache field to the body of the struct
    push!(type_body, :(_cached_hash::UInt))

    # Add the internal constructor
    if where_list isa Nothing
        push!(type_body, :(function $(full_type_name)($(member_decls...))
            new($(member_names...), $(foldl((r, a) -> :(hash($a, $r)), member_names; init = :(hash($(QuoteNode(type_name)))))))
        end))
    else
        push!(type_body, :(function $(full_type_name)($(member_decls...)) where {$(where_list...)}
            new($(member_names...), $(foldl((r, a) -> :(hash($a, $r)), member_names; init = :(hash($(QuoteNode(type_name)))))))
        end))
    end

    # add functions for hash(x), hash(x, h), and Base._show_default
    result = quote
        Base.@__doc__$(esc(typ))
        $(esc(quote
            function Base.hash(x::$(type_name))
                x._cached_hash
            end
            function Base.hash(x::$(type_name), h::UInt)
                hash(x._cached_hash, h)
            end
        end))
        function Base._show_default(io::IO, x::$(esc(:($(type_name)))))
            # note `_show_default_auto_hash_equals_cached` is not escaped.
            # it should be bound to the one defined in *this* module.
            _show_default_auto_hash_equals_cached(io, x)
        end
    end

    if where_list isa Nothing
        # add == for non-generic types
        push!(result.args, esc(quote
            function Base.:(==)(a::$(type_name), b::$(type_name))
                $(foldl((r, f) -> :($r && isequal(a.$f, b.$f)), member_names; init = :(a._cached_hash == b._cached_hash)))
            end
        end))
    else
        # We require the type be the same (including type arguments) for two instances to be equal
        push!(result.args, esc(quote
            function Base.:(==)(a::$(full_type_name), b::$(full_type_name)) where {$(where_list...)}
                $(foldl((r, f) -> :($r && isequal(a.$f, b.$f)), member_names; init = :(a._cached_hash == b._cached_hash)))
            end
        end))
        # for generic types, we add an external constructor to perform ctor type inference:
        push!(result.args, esc(quote
            $(type_name)($(member_decls...)) where {$(where_list...)} = $(full_type_name)($(member_names...))
        end))
    end

    result
end

macro auto_hash_equals(typ::Expr)
    struct_decl = get_struct_decl(typ)
    @assert struct_decl.head == :struct

    (type_name, _, _) = unpack_type_name(struct_decl.args[2])
    @assert type_name isa Symbol

    (member_names, _) = get_fields(struct_decl)

    esc(quote
        Base.@__doc__$typ
        function Base.hash(x::$(type_name), h::UInt)
            $(foldl((r, a) -> :(hash(x.$a, $r)), member_names; init = :(hash($(QuoteNode(type_name)), h))))
        end
        function Base.:(==)(a::$(type_name), b::$(type_name))
            # for compatibility with [AutoHashEquals.jl](https://github.com/andrewcooke/AutoHashEquals.jl)
            # we do not require that the types (specifically, the type arguments) are the same.
            $(foldl((r, f) -> :($r && isequal(a.$f, b.$f)), member_names; init = :true))
        end
    end)
end

end