module runtests

using AutoHashEqualsCached: @auto_hash_equals, @auto_hash_equals_cached
using Markdown: plain
using Serialization: serialize, deserialize, IOBuffer, seekstart
using Test: @testset, @test

function serialize_and_deserialize(x)
    buf = IOBuffer()
    serialize(buf, x)
    seekstart(buf)
    deserialize(buf)
end

macro noop(x)
    esc(quote
       Base.@__doc__$(x)
    end)
end

@testset "AutoHashEqualsCached.jl" begin

    @testset "tests for @auto_hash_equals_cached" begin

        @testset "macro preserves comments 1" begin
            """a comment"""
            @auto_hash_equals_cached struct T23
                x
            end
            @test plain(@doc T23) == "a comment\n"
        end

        @testset "macro preserves comments 2" begin
            """a comment"""
            @auto_hash_equals_cached @noop struct T26
                x
            end
            @test plain(@doc T26) == "a comment\n"
        end

        @testset "macro preserves comments 3" begin
            """a comment"""
            @noop @auto_hash_equals_cached struct T30
                @noop x
            end
            @test plain(@doc T30) == "a comment\n"
        end

        @testset "empty struct" begin
            @auto_hash_equals_cached struct T35 end
            @test T35() isa T35
            @test hash(T35()) == hash(:T35)
            @test hash(T35(), UInt(0)) == hash(hash(:T35), UInt(0))
            @test hash(T35(), UInt(1)) == hash(hash(:T35), UInt(1))
            @test T35() == T35()
            @test T35() == serialize_and_deserialize(T35())
            @test hash(T35()) == hash(serialize_and_deserialize(T35()))
            @test "$(T35())" == "$(T35)()"
        end

        @testset "struct with members" begin
            @auto_hash_equals_cached struct T48
                x; y
            end
            @test T48(1, :x) isa T48
            @test hash(T48(1, :x)) == hash(:x,hash(1,hash(:T48)))
            @test T48(1, :x) == T48(1, :x)
            @test T48(1, :x) != T48(2, :x)
            @test hash(T48(1, :x)) != hash(T48(2, :x))
            @test T48(1, :x) != T48(1, :y)
            @test hash(T48(1, :x)) != hash(T48(1, :y))
            @test T48(1, :x) == serialize_and_deserialize(T48(1, :x))
            @test hash(T48(1, :x)) == hash(serialize_and_deserialize(T48(1, :x)))
            @test "$(T48(1, :x))" == "$(T48)(1, :x)"
        end

        @testset "generic struct with members" begin
            @auto_hash_equals_cached struct T63{G}
                x
                y::G
            end
            @test T63{Symbol}(1, :x) isa T63
            @test hash(T63{Symbol}(1, :x)) == hash(:x,hash(1,hash(:T63)))
            @test hash(T63{Symbol}(1, :x)) == hash(T63{Any}(1, :x))
            @test T63{Symbol}(1, :x) != T63{Any}(1, :x) # note: type args are significant
            @test T63{Symbol}(1, :x) == T63{Symbol}(1, :x)
            @test T63{Symbol}(1, :x) != T63{Symbol}(2, :x)
            @test hash(T63{Symbol}(1, :x)) != hash(T63{Symbol}(2, :x))
            @test T63{Symbol}(1, :x) != T63{Symbol}(1, :y)
            @test hash(T63{Symbol}(1, :x)) != hash(T63{Symbol}(1, :y))
            @test T63{Symbol}(1, :x) == serialize_and_deserialize(T63{Symbol}(1, :x))
            @test hash(T63{Symbol}(1, :x)) == hash(serialize_and_deserialize(T63{Symbol}(1, :x)))
        end

        @testset "inheritance from an abstract base" begin
            abstract type Base81 end
            @auto_hash_equals_cached struct T81a<:Base81 x end
            @auto_hash_equals_cached struct T81b<:Base81 x end
            @test T81a(1) isa T81a
            @test T81a(1) isa Base81
            @test T81b(1) isa T81b
            @test T81b(1) isa Base81
            @test T81a(1) != T81b(1)
            @test T81a(1) == T81a(1)
            @test serialize_and_deserialize(T81a(1)) isa T81a
            @test T81a(1) == serialize_and_deserialize(T81a(1))
            @test hash(T81a(1)) == hash(serialize_and_deserialize(T81a(1)))
        end

        @testset "generic bounds" begin
            abstract type Base107{T<:Union{String, Int}} end
            @auto_hash_equals_cached struct T107a{T}<:Base107{T} x::T end
            @auto_hash_equals_cached struct T107b{T}<:Base107{T} x::T end
            @test T107a(1) isa T107a
            @test T107a(1) == T107a(1)
            @test T107a(1) == serialize_and_deserialize(T107a(1))
            @test T107a(1) != T107a(2)
            @test hash(T107a(1)) == hash(1, hash(:T107a))
            @test hash(T107a("x")) == hash("x", hash(:T107a))
            @test hash(T107a(1)) != hash(T107b(1))
            @test hash(T107a(1)) != hash(T107a(2))
        end

        @testset "macro applied to type before @auto_hash_equals_cached" begin
            @noop @auto_hash_equals_cached struct T116
                x::Int
                y
            end
            @test T116(1, :x) isa T116
            @test hash(T116(1, :x)) == hash(:x,hash(1,hash(:T116)))
            @test T116(1, :x) == T116(1, :x)
            @test T116(1, :x) != T116(2, :x)
            @test hash(T116(1, :x)) != hash(T116(2, :x))
            @test T116(1, :x) != T116(1, :y)
            @test hash(T116(1, :x)) != hash(T116(1, :y))
            @test T116(1, :x) == serialize_and_deserialize(T116(1, :x))
            @test hash(T116(1, :x)) == hash(serialize_and_deserialize(T116(1, :x)))
        end

        @testset "macro applied to type after @auto_hash_equals_cached" begin
            @auto_hash_equals_cached @noop struct T132
                x::Int
                y
            end
            @test T132(1, :x) isa T132
            @test hash(T132(1, :x)) == hash(:x,hash(1,hash(:T132)))
            @test T132(1, :x) == T132(1, :x)
            @test T132(1, :x) != T132(2, :x)
            @test hash(T132(1, :x)) != hash(T132(2, :x))
            @test T132(1, :x) != T132(1, :y)
            @test hash(T132(1, :x)) != hash(T132(1, :y))
            @test T132(1, :x) == serialize_and_deserialize(T132(1, :x))
            @test hash(T132(1, :x)) == hash(serialize_and_deserialize(T132(1, :x)))
        end

        @testset "macro applied to members" begin
            @auto_hash_equals_cached @noop struct T148
                @noop x::Int
                @noop y
            end
            @test T148(1, :x) isa T148
            @test hash(T148(1, :x)) == hash(:x,hash(1,hash(:T148)))
            @test T148(1, :x) == T148(1, :x)
            @test T148(1, :x) != T148(2, :x)
            @test hash(T148(1, :x)) != hash(T148(2, :x))
            @test T148(1, :x) != T148(1, :y)
            @test hash(T148(1, :x)) != hash(T148(1, :y))
            @test T148(1, :x) == serialize_and_deserialize(T148(1, :x))
            @test hash(T148(1, :x)) == hash(serialize_and_deserialize(T148(1, :x)))
        end

        @testset "contained NaN values compare equal" begin
            @auto_hash_equals_cached struct T155
                x
            end
            nan = 0.0 / 0.0
            @test nan != nan
            @test T155(nan) == T155(nan)
        end

        @testset "ensure circular data structures, produced by hook or by crook, do not blow the stack" begin
            @auto_hash_equals_cached struct T157
                a::Array{Any,1}
            end
            t::T157 = T157(Any[1])
            t.a[1] = t
            @test hash(t) != 0
            @test t == t
            @test "$t" == "$(T157)(Any[$(T157)(#= circular reference @-2 =#)])"
        end

    end

    @testset "tests for @auto_hash_equals" begin

        @testset "macro preserves comments 1" begin
            """a comment"""
            @auto_hash_equals struct T160
                x
            end
            @test plain(@doc T160) == "a comment\n"
        end

        @testset "macro preserves comments 2" begin
            """a comment"""
            @auto_hash_equals @noop struct T165
                x
            end
            @test plain(@doc T165) == "a comment\n"
        end

        @testset "macro preserves comments 3" begin
            """a comment"""
            @noop @auto_hash_equals struct T170
                @noop x
            end
            @test plain(@doc T170) == "a comment\n"
        end

        @testset "empty struct" begin
            @auto_hash_equals struct T176 end
            @test T176() isa T176
            @test hash(T176()) == hash(:T176, UInt(0))
            @test hash(T176(), UInt(1)) == hash(:T176, UInt(1))
            @test hash(T176(), UInt(1)) != hash(:T176, UInt(0))
            @test T176() == T176()
            @test T176() == serialize_and_deserialize(T176())
            @test hash(T176()) == hash(serialize_and_deserialize(T176()))
        end

        @testset "struct with members" begin
            @auto_hash_equals struct T186
                x; y
            end
            @test T186(1, :x) isa T186
            @test hash(T186(1, :x)) == hash(:x,hash(1,hash(:T186, UInt(0))))
            @test T186(1, :x) == T186(1, :x)
            @test T186(1, :x) != T186(2, :x)
            @test hash(T186(1, :x)) != hash(T186(2, :x))
            @test T186(1, :x) != T186(1, :y)
            @test hash(T186(1, :x)) != hash(T186(1, :y))
            @test T186(1, :x) == serialize_and_deserialize(T186(1, :x))
            @test hash(T186(1, :x)) == hash(serialize_and_deserialize(T186(1, :x)))
        end

        @testset "generic struct with members" begin
            @auto_hash_equals struct T201{G}
                x
                y::G
            end
            @test T201{Symbol}(1, :x) isa T201
            @test hash(T201{Symbol}(1, :x)) == hash(:x,hash(1,hash(:T201, UInt(0))))
            @test hash(T201{Symbol}(1, :x)) == hash(T201{Any}(1, :x))
            @test T201{Symbol}(1, :x) == T201{Any}(1, :x) # note: type args are not significant
            @test T201{Symbol}(1, :x) == T201{Symbol}(1, :x)
            @test T201{Symbol}(1, :x) != T201{Symbol}(2, :x)
            @test hash(T201{Symbol}(1, :x)) != hash(T201{Symbol}(2, :x))
            @test T201{Symbol}(1, :x) != T201{Symbol}(1, :y)
            @test hash(T201{Symbol}(1, :x)) != hash(T201{Symbol}(1, :y))
            @test T201{Symbol}(1, :x) == serialize_and_deserialize(T201{Symbol}(1, :x))
            @test hash(T201{Symbol}(1, :x)) == hash(serialize_and_deserialize(T201{Symbol}(1, :x)))
        end

        @testset "inheritance from an abstract base" begin
            abstract type Base219 end
            @auto_hash_equals struct T219a<:Base219 x end
            @auto_hash_equals struct T219b<:Base219 x end
            @test T219a(1) isa T219a
            @test T219a(1) isa Base219
            @test T219b(1) isa T219b
            @test T219b(1) isa Base219
            @test T219a(1) != T219b(1)
            @test T219a(1) == T219a(1)
            @test serialize_and_deserialize(T219a(1)) isa T219a
            @test T219a(1) == serialize_and_deserialize(T219a(1))
            @test hash(T219a(1)) == hash(serialize_and_deserialize(T219a(1)))
            @test hash(T219a(1)) == hash(1, hash(:T219a, UInt(0)))
        end

        @testset "generic bounds" begin
            abstract type Base225{T<:Union{String, Int}} end
            @auto_hash_equals struct T225a{T}<:Base225{T} x::T end
            @auto_hash_equals struct T225b{T}<:Base225{T} x::T end
            @test T225a(1) == T225a(1)
            @test T225a(1) == serialize_and_deserialize(T225a(1))
            @test T225a(1) != T225a(2)
            @test hash(T225a(1)) == hash(1, hash(:T225a, UInt(0)))
            @test hash(T225a("x")) == hash("x", hash(:T225a, UInt(0)))
            @test hash(T225a(1)) != hash(T225b(1))
            @test hash(T225a(1)) != hash(T225a(2))
        end

        @testset "macro applied to type before @auto_hash_equals" begin
            @noop @auto_hash_equals struct T238
                x::Int
                y
            end
            @test T238(1, :x) isa T238
            @test hash(T238(1, :x)) == hash(:x,hash(1,hash(:T238, UInt(0))))
            @test T238(1, :x) == T238(1, :x)
            @test T238(1, :x) != T238(2, :x)
            @test hash(T238(1, :x)) != hash(T238(2, :x))
            @test T238(1, :x) != T238(1, :y)
            @test hash(T238(1, :x)) != hash(T238(1, :y))
            @test T238(1, :x) == serialize_and_deserialize(T238(1, :x))
            @test hash(T238(1, :x)) == hash(serialize_and_deserialize(T238(1, :x)))
        end

        @testset "macro applied to type after @auto_hash_equals" begin
            @auto_hash_equals @noop struct T254
                x::Int
                y
            end
            @test T254(1, :x) isa T254
            @test hash(T254(1, :x)) == hash(:x,hash(1,hash(:T254, UInt(0))))
            @test T254(1, :x) == T254(1, :x)
            @test T254(1, :x) != T254(2, :x)
            @test hash(T254(1, :x)) != hash(T254(2, :x))
            @test T254(1, :x) != T254(1, :y)
            @test hash(T254(1, :x)) != hash(T254(1, :y))
            @test T254(1, :x) == serialize_and_deserialize(T254(1, :x))
            @test hash(T254(1, :x)) == hash(serialize_and_deserialize(T254(1, :x)))
        end

        @testset "macro applied to members" begin
            @auto_hash_equals @noop struct T313
                @noop x::Int
                @noop y
            end
            @test T313(1, :x) isa T313
            @test hash(T313(1, :x)) == hash(:x,hash(1,hash(:T313, UInt(0))))
            @test T313(1, :x) == T313(1, :x)
            @test T313(1, :x) != T313(2, :x)
            @test hash(T313(1, :x)) != hash(T313(2, :x))
            @test T313(1, :x) != T313(1, :y)
            @test hash(T313(1, :x)) != hash(T313(1, :y))
            @test T313(1, :x) == serialize_and_deserialize(T313(1, :x))
            @test hash(T313(1, :x)) == hash(serialize_and_deserialize(T313(1, :x)))
        end

        @testset "contained NaN values compare equal" begin
            @auto_hash_equals struct T330
                x
            end
            nan = 0.0 / 0.0
            @test nan != nan
            @test T330(nan) == T330(nan)
        end

    end

end

end # module