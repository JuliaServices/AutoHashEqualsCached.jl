# This package has been archived.  Please use https://github.com/JuliaServices/AutoHashEquals.jl instead!


[![Build Status](https://github.com/JuliaServices/AutoHashEqualsCached.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaServices/AutoHashEqualsCached.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaServices/AutoHashEqualsCached.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaServices/AutoHashEqualsCached.jl)

# AutoHashEqualsCached

A pair of macros to add `==` and `hash()` to struct types: `@auto_hash_equals` and `@auto_hash_equals_cached`.

# `@auto_hash_equals`

The macro `@auto_hash_equals` produces an implementation of `Base.hash(x)` that computes the hash code when invoked.  It is offered for compatibility with the package [AutoHashEquals](https://github.com/andrewcooke/AutoHashEquals.jl).

You use it like so:

```julia
@auto_hash_equals struct Box
    x
end
```

which is translated to

```julia
struct Box
    x
end
Base.hash(x::Type, h::UInt) = hash(x.x, hash(:Foo, h))
Base.(:(==))(a::Box, b::Box) = isequal(a.x, b.x)
```

However, there are a few enhancements beyond what is provided by [AutoHashEquals](https://github.com/andrewcooke/AutoHashEquals.jl):

- It handles empty structs without error
- You can use it either before or after another macro.
- You can specify the hash function to be implemented, by naming it before the struct definition:

```julia
@auto_hash_equals SomePackage.myhash struct Foo
    x
    y
end
```

In this case the macro implements both `SomePackage.myhash` and `Base.hash` for `Foo`.`

For compatibility with [AutoHashEquals](https://github.com/andrewcooke/AutoHashEquals.jl), we do not take the type arguments of a generic type into account in `==`.  So a `Box{Int}(1)` will test equal to a `Box{Any}(1)`.

# `@auto_hash_equals_cached`

The macro `@auto_hash_equals_cached` is useful for non-mutable struct types that define recursive or deep data structures (and therefore are likely to be stored on the heap).  It computes the hash code during construction and caches it in a field of the struct.  If you are working with data structures of any significant depth, computing the hash once can speed things up at the expense of one additional field per struct.

You use it like so:

```julia
@auto_hash_equals_cached struct Point{T<:Any, U<:Any}
  x::T
  y::U
end
```

which is translated to

```julia
struct Point{T<:Any, U<:Any}
    x::T
    y::U
    _cached_hash::UInt
    Point{T,U}(x::T, y::U) where {T<:Any, U<:Any} = new{T,U}(x,y,hash(y, hash(x, hash(Point{T,U}))))
end
Base.hash(x::Point) = x._cached_hash
Base.hash(x::Point, h::UInt) = hash(x._cached_hash, h)
function Base.:(==)(a::Point{T,U}, b::Point{T,U}) where {T<:Any, U<:Any}
    a._cached_hash == b._cached_hash && isequal(a.x, b.x) && isequal(a.y, b.y)
end
Base._show_default(io::IO, x::Point) = AutoHashEqualsCached._show_default_auto_hash_equals_cached(io, x)
Point(x::T, y::U) where {T<:Any, U<:Any} = Point{T, U}(x, y)
```

We use `isequal` so that a floating-point `NaN` compares equal to itself.  The generated code checks the exact types of the two compared objects, so `Box{Int}(1)` will compare unequal to `Box{Any}(1)`.

The definition of `_show_default(io,x)` prevents display of the `_cached_hash` field while preserving the behavior of `Base.show(...)` that handles self-recursive data structures without a stack overflow.

We provide an external constructor for generic types so that you get the same type inference behavior you would get in the absence of this macro.  Specifically, you can write `Point(1, 2)` to get an object of type `Point{Int, Int}`.

As with @auto_hash_equals, you can specify the hash function to be implemented:

```julia
@auto_hash_equals_cached SomePackage.myhash struct Foo
    x
    y
end
```

In this case the macro implements both `SomePackage.myhash` and `Base.hash` for `Foo`.`
