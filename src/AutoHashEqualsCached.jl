# SPDX-License-Identifier: MIT

module AutoHashEqualsCached

using Rematch

export @auto_hash_equals_cached, @auto_hash_equals

# `_show_default_auto_hash_equals_cached` is just like `Base._show_default(io, x)`,
# except it ignores fields named `_cached_hash`.  This function is called in the
# implementation of `T._show_default` for each type `T` annotated with
# `@auto_hash_equals_cached`.  This is ultimately used in the implementation of
# `Base.show`.  This specialization ensures that showing circular data structures does not
# result in infinite recursion.
function _show_default_auto_hash_equals_cached(io::IO, @nospecialize(x))
    t = typeof(x)
    show(io, Base.inferencebarrier(t)::DataType)
    print(io, '(')
    recur_io = IOContext(io, Pair{Symbol,Any}(:SHOWN_SET, x),
                         Pair{Symbol,Any}(:typeinfo, Any))
    if !Base.show_circular(io, x)
        for i in 1:nfields(x)
            f = fieldname(t, i)
            if (f === :_cached_hash)
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

# Find the first struct declaration buried in the Expr.
get_struct_decl(__source__, typ) = nothing
function get_struct_decl(__source__, typ::Expr)
    if typ.head === :struct
        return typ
    elseif typ.head === :macrocall
        return get_struct_decl(__source__, typ.args[3])
    elseif typ.head === :block
        # get the first struct decl in the block
        for x in typ.args
            if x isa LineNumberNode
                __source__ = x
            elseif x isa Expr && (x.head === :macrocall || x.head === :struct || x.head === :block)
                result = get_struct_decl(__source__, x)
                if !isnothing(result)
                    return result
                end
            end
        end
    end

    error("$(__source__.file):$(__source__.line): macro @auto_hash_equals_cached should only be applied to a struct")
end

unpack_name(node) = node
function unpack_name(node::Expr)
    if node.head === :macrocall
        return unpack_name(node.args[3])
    elseif node.head in (:(<:), :(::))
        return unpack_name(node.args[1])
    else
        return node
    end
end

unpack_type_name(__source__, n::Symbol) = (n, n, nothing)
function unpack_type_name(__source__, n::Expr)
    if n.head === :curly
        type_name = n.args[1]
        type_name isa Symbol ||
            error("$(__source__.file):$(__source__.line): macro @auto_hash_equals_cached applied to type with invalid signature: $type_name")
        where_list = n.args[2:length(n.args)]
        type_params = map(unpack_name, where_list)
        full_type_name = Expr(:curly, type_name, type_params...)
        return (type_name, full_type_name, where_list)
    elseif n.head === :(<:)
        return unpack_type_name(__source__, n.args[1])
    else
        error("$(__source__.file):$(__source__.line): macro @auto_hash_equals_cached applied to type with unexpected signature: $n")
    end
end

function get_fields(__source__, struct_decl::Expr; prevent_inner_constructors=false)
    member_names = Vector{Symbol}()
    member_decls = Vector()

    add_field(__source__, b) = nothing
    function add_field(__source__, b::Symbol)
        push!(member_names, b)
        push!(member_decls, b)
    end
    function add_field(__source__, b::Expr)
        if b.head === :block
            add_fields(field)
        elseif b.head === :const
            add_field(__source__, b.args[1])
        elseif b.head === :(::) && b.args[1] isa Symbol
            push!(member_names, b.args[1])
            push!(member_decls, b)
        elseif b.head === :macrocall
            add_field(__source__, b.args[3])
        elseif b.head === :function || b.head === :(=) && (b.args[1] isa Expr && b.args[1].head in (:call, :where))
            # :function, :equals:call, :equals:where are defining functions - inner constructors
            # we don't want to permit that if it would interfere with us producing them.
            prevent_inner_constructors &&
                error("$(__source__.file):$(__source__.line): macro @auto_hash_equals_cached should not be used on a struct that declares an inner constructor")
        end
    end
    function add_fields(__source__, b::Expr)
        @assert b.head === :block
        for field in b.args
            if field isa LineNumberNode
                __source__ = field
            else
                add_field(__source__, field)
            end
        end
    end

    @assert (struct_decl.args[3].head === :block)
    add_fields(__source__, struct_decl.args[3])
    return (member_names, member_decls)
end

"""
    @auto_hash_equals_cached struct Foo ... end

Causes the struct to have an additional hidden field named `_cached_hash` that is computed and stored at the time of construction.
Produces constructors and specializes the behavior of `Base.show` to maintain the illusion that the field does not exist.
Two different instantiations of a generic type are considered not equal.

Also produces specializations of `Base.hash` and `Base.==`:

- `Base.==` is implemented as an elementwise test for `isequal`.
- `Base.hash` just returns the cached hash value.
"""
macro auto_hash_equals_cached(typ::Expr)
    struct_decl = get_struct_decl(__source__, typ)
    @assert struct_decl.head === :struct
    type_body = struct_decl.args[3].args

    !struct_decl.args[1] ||
        error("$(__source__.file):$(__source__.line): macro @auto_hash_equals_cached should only be applied to a non-mutable struct.")

    (type_name, full_type_name, where_list) = unpack_type_name(__source__, struct_decl.args[2])
    @assert type_name isa Symbol

    (member_names, member_decls) = get_fields(__source__, struct_decl; prevent_inner_constructors=true)

    # Add the cache field to the body of the struct
    push!(type_body, :(_cached_hash::UInt))

    # Add the internal constructor
    if isnothing(where_list)
        push!(type_body, :(function $full_type_name($(member_names...))
            new($(member_names...), $(foldl((r, a) -> :(hash($a, $r)), member_names; init = :(hash($full_type_name)))))
        end))
    else
        push!(type_body, :(function $full_type_name($(member_names...)) where {$(where_list...)}
            new($(member_names...), $(foldl((r, a) -> :(hash($a, $r)), member_names; init = :(hash($full_type_name)))))
        end))
    end

    # add functions for hash(x), hash(x, h), and Base._show_default
    result = quote
        Base.@__doc__ $(esc(typ))
        $(esc(quote
            function Base.hash(x::$type_name)
                x._cached_hash
            end
            function Base.hash(x::$type_name, h::UInt)
                hash(x._cached_hash, h)
            end
        end))
        function Base._show_default(io::IO, x::$(esc(:($type_name))))
            # note `_show_default_auto_hash_equals_cached` is not escaped.
            # it should be bound to the one defined in *this* module.
            _show_default_auto_hash_equals_cached(io, x)
        end
        # Make Rematch ignore the field that caches the hash code
        function Rematch.evaluated_fieldcount(::Type{$(esc(:($type_name)))})
            $(length(member_names))
        end
    end

    equalty_impl = foldl((r, f) -> :($r && isequal(a.$f, b.$f)), member_names; init = :(a._cached_hash == b._cached_hash))

    if isnothing(where_list)
        # add == for non-generic types
        push!(result.args, esc(quote
            function Base.:(==)(a::$type_name, b::$type_name)
                $equalty_impl
            end
        end))
    else
        # We require the type be the same (including type arguments) for two instances to be equal
        push!(result.args, esc(quote
            function Base.:(==)(a::$full_type_name, b::$full_type_name) where {$(where_list...)}
                $equalty_impl
            end
        end))
        # for generic types, we add an external constructor to perform ctor type inference:
        push!(result.args, esc(quote
            $type_name($(member_decls...)) where {$(where_list...)} = $full_type_name($(member_names...))
        end))
    end

    return result
end

"""
    @auto_hash_equals struct Foo ... end

Produces specializations of `Base.hash` and `Base.==`:

- `Base.==` is implemented as an elementwise test for `isequal`.
- `Base.hash` combines the elementwise hash code of the fields with the hash code of the type's simple name.

The hash code and `==` implementations ignore type parameters, so that `Box{Int}(1)` will be considered
`equals` to `Box{Any}(1)`.
This is for compatibility with the package `AutoHashEquals`.
"""
macro auto_hash_equals(typ::Expr)
    struct_decl = get_struct_decl(__source__, typ)
    @assert struct_decl.head === :struct

    (type_name, _, _) = unpack_type_name(__source__, struct_decl.args[2])
    @assert type_name isa Symbol

    (member_names, _) = get_fields(__source__, struct_decl)

    equalty_impl = foldl((r, f) -> :($r && isequal(a.$f, b.$f)), member_names; init = :true)
    if struct_decl.args[1]
        # mutable structs can efficiently be compared by reference
        equalty_impl = :(a === b || $equalty_impl)
    end

    # for compatibility with [AutoHashEquals.jl](https://github.com/andrewcooke/AutoHashEquals.jl)
    # we do not require that the types (specifically, the type arguments) are the same for two
    # objects to be considered `==`.
    return esc(quote
        Base.@__doc__ $typ
        function Base.hash(x::$type_name, h::UInt)
            $(foldl((r, a) -> :(hash(x.$a, $r)), member_names; init = :(hash($(QuoteNode(type_name)), h))))
        end
        function Base.:(==)(a::$type_name, b::$type_name)
            $equalty_impl
        end
    end)
end

end
