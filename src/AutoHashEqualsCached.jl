# SPDX-License-Identifier: MIT

module AutoHashEqualsCached

using Pkg

export @auto_hash_equals_cached, @auto_hash_equals, @auto_hash_equals_const

pkgversion(m::Module) = VersionNumber(Pkg.TOML.parsefile(joinpath(dirname(string(first(methods(m.eval)).file)), "..", "Project.toml"))["version"])

function if_has_package(
    action::Function,
    name::String,
    uuid::Base.UUID,
    version::VersionNumber
)
    pkgid = Base.PkgId(uuid, name)
    if Base.root_module_exists(pkgid)
        pkg = Base.root_module(pkgid)
        if pkgversion(pkg) >= version
            return action(pkg)
        end
    end
end

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
        else
            error("$(__source__.file):$(__source__.line): Unexpected field declaration: $decl")
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

function check_valid_alt_hash_name(__source__, alt_hash_name)
    alt_hash_name === nothing || alt_hash_name isa Symbol || Base.is_expr(alt_hash_name, :.) ||
        error("$(__source__.file):$(__source__.line): invalid alternate hash function name: $alt_hash_name")
end

function auto_hash_equals_impl(__source__::LineNumberNode, alt_hash_name, typ::Expr)
    check_valid_alt_hash_name(__source__, alt_hash_name)
    struct_decl = get_struct_decl(__source__, typ)
    @assert struct_decl.head === :struct

    (type_name, _, _) = unpack_type_name(__source__, struct_decl.args[2])
    @assert type_name isa Symbol

    (member_names, _) = get_fields(__source__, struct_decl)

    equalty_impl = foldl(
        (r, f) -> :($r && $isequal($getfield(a, $(QuoteNode(f))), $getfield(b, $(QuoteNode(f))))),
        member_names;
        init = :true)
    if struct_decl.args[1]
        # mutable structs can efficiently be compared by reference
        equalty_impl = :(a === b || $equalty_impl)
    end

    result = Expr(:block, __source__, esc(:(Base.@__doc__ $typ)), __source__)

    # add function for hash(x, h)
    base_hash_name = :($Base.hash)
    defined_hash_name = alt_hash_name === nothing ? base_hash_name : alt_hash_name
    compute_hash = foldl(
        (r, a) -> :($defined_hash_name($getfield(x, $(QuoteNode(a))), $r)),
        member_names;
        init = :($defined_hash_name($(QuoteNode(type_name)), h)))
    push!(result.args, esc(:(function $defined_hash_name(x::$type_name, h::UInt)
        $compute_hash
        end)))
    if defined_hash_name != base_hash_name
        # add function for Base.hash(x, h)
        push!(result.args, esc(:(function $base_hash_name(x::$type_name, h::UInt)
            $defined_hash_name(x, h)
            end)))
    end

    # for compatibility with [AutoHashEquals.jl](https://github.com/andrewcooke/AutoHashEquals.jl)
    # we do not require that the types (specifically, the type arguments) are the same for two
    # objects to be considered `==`.
    push!(result.args, esc(:(function $Base.:(==)(a::$type_name, b::$type_name)
        $equalty_impl
        end)))

    # push!(result.args, esc(:()))
    return result
end

#
# Modify the struct declaration to make it mutable, making the individual fields
# const in the process.  If the struct is already mutable, merely warn about
# any fields that are not declared const, since we will be cacheing a precomputed
# hash value.
#
function make_mutable(
    __source__::LineNumberNode,
    __module__::Module,
    struct_decl::Expr)

    # If the struct is already mutable, then we only need to warn on any fields that are
    # not declared const.
    warn_rather_than_force = struct_decl.args[1] # the mutable flag
    struct_decl.args[1] = true

    function ensure_const(decl)
        if VERSION < v"1.8"
            # Before Julia 1.8, we can't use `const` on a field declaration
            return decl
        elseif warn_rather_than_force
            println("producing warning for $decl")
            @warn("$(__source__.file):$(__source__.line): Field declaration `$decl` should be declared const, so that the cached hash value will not be invalidated by any mutations.")
            return decl
        else
            return Expr(:const, decl)
        end
    end
    add_const_if_needed(decl::LineNumberNode) = decl
    function add_const_if_needed(decl::Symbol)
        return ensure_const(decl)
    end
    function handle_decls end
    function add_const_if_needed(decl::Expr)
        if decl.head === :(::) && decl.args[1] isa Symbol
            decl = ensure_const(decl)
        elseif decl.head === :macrocall
            decl = add_const_if_needed(macroexpand(__module__, decl))
        elseif decl.head === :block
            handle_decls(decl.args)
        elseif decl.head === :const
            # already const
        elseif decl.head === :function || decl.head === :(=) && (decl.args[1] isa Expr && decl.args[1].head in (:call, :where))
            # ignore inner ctor
        else
            error("$(__source__.file):$(__source__.line): Unexpected field declaration: $decl")
        end
        return decl
    end
    function handle_decls(decls::Vector{Any})
        for i in 1:length(decls)
            decl = decls[i]
            if decl isa LineNumberNode
                __source__ = decl
            else
                decls[i] = add_const_if_needed(decl)
            end
        end
    end

    @assert struct_decl.args[3].head === :block
    handle_decls(struct_decl.args[3].args)
    nothing # we modified the struct decl in place
end

function auto_hash_equals_cached_impl(
    __source__::LineNumberNode,
    __module__::Module,
    alt_hash_name,
    typ::Expr,
    should_make_mutable::Bool=false
)
    check_valid_alt_hash_name(__source__, alt_hash_name)
    struct_decl = get_struct_decl(__source__, typ)
    @assert struct_decl.head === :struct
    type_body = struct_decl.args[3].args
    was_mutable = struct_decl.args[1]

    if !should_make_mutable && was_mutable
        println("was mutable: $was_mutable")
        dump(struct_decl)
        error("$(__source__.file):$(__source__.line): macro @auto_hash_equals_cached should only be applied to a non-mutable struct.")
    end

    if should_make_mutable
        make_mutable(__source__, __module__, struct_decl)
    end

    (type_name, full_type_name, where_list) = unpack_type_name(__source__, struct_decl.args[2])
    @assert type_name isa Symbol

    (member_names, member_decls) = get_fields(__source__, struct_decl; prevent_inner_constructors=true)

    # Add the cache field to the body of the struct
    push!(type_body, :(_cached_hash::UInt))

    # Add the internal constructor
    base_hash_name = :($Base.hash)
    defined_hash_name = alt_hash_name === nothing ? base_hash_name : alt_hash_name
    compute_hash = foldl(
        (r, a) -> :($defined_hash_name($a, $r)),
        member_names;
        init = :($defined_hash_name($full_type_name)))
    ctor_body = :(new($(member_names...), $compute_hash))
    if isnothing(where_list)
        push!(type_body, :(function $full_type_name($(member_names...))
            $ctor_body
        end))
    else
        push!(type_body, :(function $full_type_name($(member_names...)) where {$(where_list...)}
            $ctor_body
        end))
    end

    result = Expr(:block, __source__, esc(:(Base.@__doc__ $typ)), __source__)

    # add function for hash(x, h). hash(x)
    push!(result.args, esc(:(function $defined_hash_name(x::$type_name, h::UInt)
        $defined_hash_name(x._cached_hash, h)
        end)))
    push!(result.args, esc(:(function $defined_hash_name(x::$type_name)
        x._cached_hash
        end)))
    if defined_hash_name != base_hash_name
        # add function for Base.hash(x, h), Base.hash(x)
        push!(result.args, esc(:(function $base_hash_name(x::$type_name, h::UInt)
            $defined_hash_name(x, h)
            end)))
        push!(result.args, esc(:(function $base_hash_name(x::$type_name)
            $defined_hash_name(x)
            end)))
    end

    # add function Base.show
    push!(result.args, esc(:(function $Base._show_default(io::IO, x::$type_name)
        $_show_default_auto_hash_equals_cached(io, x)
        end)))

    # Add functions to interoperate with Rematch and Rematch2 if they are loaded
    # at the time the macro is expanded.
    if_has_package("Rematch", Base.UUID("bfecab0d-fd4d-5014-a23f-56c5fae6447a"), v"0.3.3") do pkg
        push!(result.args, esc(:(function $pkg.evaluated_fieldcount(::Type{$type_name})
            $(length(member_names))
            end)))
    end
    if_has_package("Rematch2", Base.UUID("351a7294-9038-49b6-b9cf-e076b05af63f"), v"0.2.6") do pkg
        if :fieldnames in names(pkg; all=true)
            push!(result.args, esc(:(function $pkg.fieldnames(::Type{$type_name})
                $((member_names...,))
                end)))
        end
    end

    equalty_impl = foldl(
        (r, f) -> :($r && $isequal($getfield(a, $(QuoteNode(f))), $getfield(b, $(QuoteNode(f))))),
        member_names;
        init = :(a._cached_hash == b._cached_hash))

    # if the type is now mutable, we have an equality shortcut of compating references.
    if should_make_mutable
        equalty_impl = :(a === b || $equalty_impl)
    end

    if isnothing(where_list)
        # add == for non-generic types
        push!(result.args, esc(quote
            function $Base.:(==)(a::$type_name, b::$type_name)
                $equalty_impl
            end
        end))
    else
        # We require the type be the same (including type arguments) for two instances to be equal
        push!(result.args, esc(quote
            function $Base.:(==)(a::$full_type_name, b::$full_type_name) where {$(where_list...)}
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
    @auto_hash_equals_cached struct Foo ... end

Causes the struct to have an additional hidden field named `_cached_hash` that is
computed and stored at the time of construction.  Produces constructors and specializes
the behavior of `Base.show` to maintain the illusion that the field does not exist.
Two different instantiations of a generic type are considered not equal.

Also produces specializations of `Base.hash` and `Base.==`:

- `Base.==` is implemented as an elementwise test for `isequal`.
- `Base.hash` just returns the cached hash value.
"""
macro auto_hash_equals_cached(typ::Expr)
    auto_hash_equals_cached_impl(__source__, __module__, nothing, typ)
end
macro auto_hash_equals_cached(alt_hash_name, typ::Expr)
    auto_hash_equals_cached_impl(__source__, __module__, alt_hash_name, typ)
end

"""
    @auto_hash_equals_const struct Foo ... end

Causes the struct to have an additional hidden field named `_cached_hash` that is
computed and stored at the time of construction.  Produces constructors and specializes
the behavior of `Base.show` to maintain the illusion that the field does not exist.
Two different instantiations of a generic type are considered not equal.  This version
makes the type itself mutable, but makes every field `const`, so that the overall effect
is that the struct remains immutable.  However, the struct will be heap-allocated.  Using
this macro rather than @auto_hash_equals_cached can be useful when the use of the type
incurs a high cost for copying or boxing, or when comparing equality can benefit from
a reference equality shortcut.

Also produces specializations of `Base.hash` and `Base.==`:

- `Base.==` is implemented as an elementwise test for `isequal`.
- `Base.hash` just returns the cached hash value.
"""
macro auto_hash_equals_const(typ::Expr)
    auto_hash_equals_cached_impl(__source__, __module__,  nothing, typ, true)
end
macro auto_hash_equals_const(alt_hash_name, typ::Expr)
    auto_hash_equals_cached_impl(__source__, __module__, alt_hash_name, typ, true)
end

"""
    @auto_hash_equals struct Foo ... end

Produces specializations of `Base.hash` and `Base.==`:

- `Base.==` is implemented as an elementwise test for `isequal`.
- `Base.hash` combines the elementwise hash code of the fields with the hash code of the type's simple name.

The hash code and `==` implementations ignore type parameters, so that `Box{Int}(1)`
will be considered `isequal` to `Box{Any}(1)`.  This is for compatibility with the
package `AutoHashEquals.jl`.
"""
macro auto_hash_equals(typ::Expr)
    auto_hash_equals_impl(__source__, nothing, typ)
end
macro auto_hash_equals(alt_hash_name, typ::Expr)
    auto_hash_equals_impl(__source__, alt_hash_name, typ)
end

end
