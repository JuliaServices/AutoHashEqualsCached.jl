# SPDX-License-Identifier: MIT

module AutoHashEqualsCached

export @auto_hash_equals

include("impl.jl")

"""
    @auto_hash_equals [options] struct Foo ... end

Generate `Base.hash` and `Base.==` methods for `Foo`.

Options:

* `cache=true|false` whether or not to generate an extra cache field to store the precomputed hash value. Default: `false`.
* `hashfn=myhash` the hash function to use. Default: `Base.hash`.
* `fields=a,b,c` the fields to use for hashing and equality. Default: all fields.
"""
macro auto_hash_equals(args...)
    kwargs = Dict{Symbol,Any}()
    length(args) > 0 || error_usage(__source__)
    for option in args[1:end-1]
        if !isexpr(option, :(=), 2) || !(option.args[1] isa Symbol)
            error("$(__source__.file):$(__source__.line): expected keyword argument of the form `key=value`, but saw `$option`")
        end
        name=option.args[1]
        value=option.args[2]
        if name == :fields
            # fields=a,b,c
            if value isa Symbol
                value = (value,)
            elseif isexpr(value, :tuple)
                value = Symbol[value.args...]
                value=(value...,)
            else
                error("$(__source__.file):$(__source__.line): expected tuple or symbol for `fields`, but got `$value`")
            end
        end
        kwargs[name] = value
    end
    typ = args[end]
    auto_hash_equals_impl(__source__, typ; kwargs...)
end

"""
    @auto_hash_equals_cached struct Foo ... end

Shorthand for @auto_hash_equals cache=true struct Foo ... end
"""
macro auto_hash_equals_cached(typ)
    esc(Expr(:macrocall, var"@auto_hash_equals", __source__, :(cache = true), typ))
end

end # module
