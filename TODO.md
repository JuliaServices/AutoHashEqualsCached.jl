TODO:

- Make Base.== sensitive to type arguments for all forms of these macros.
- Make the macro helpers able to take an optional hash name and an optional list of member names.
  - In either order
- Give an error if any of the named members are not the name of declared members.
- If the struct ends up mutable but a field isn't, do one of the following as apropos:
  - Give an error
  - Give a warning
  - Change its declaration so that it is const
- Add tests for each of these features.

arguments:
    __source__
    __module__
    args...

where args is
    optional: alt_hash_name `foo` or `Package.foo`
    optional: member list (:a, :b, :c)
    required: struct declaration

helper function to unpack args, returns
    (1) alt_hash_name (or nothing)
    (2) member list (or nothing)
    (3) struct declaration (or throws an error)

helper function to unpack and check names to process
takes:
    struct declaration
    member list (or nothing)
    flags
        should make mutable
        should add const
        should check const
returns
    member list for hashing and equality
        (either the input or computed)

helper function to enumerate the member declarations
    takes a lambda that receives and returns the member decl

Also go through the documentation point by point and make sure
each point is implemented and tested:
- @auto_hash_equals_cached:
  - If the struct declaration includes the keyword `mutable` in source, a error is produced (warning if version < 1.8) if any of the (named) fields do not have the `const` modifier.
  - alt_hash_name respected
  - field names respected
  - type arguments significant
- @auto_hash_equals_const
  - adds mutable
  - adds const to fields if possible (Julia version >= 1.8)
  - If the struct declaration includes the keyword `mutable` in source, then rather than adding `const` to every field, a warning is produced if any of the (named) fields do not have the `const` modifier.
  - alt_hash_name respected
  - field names respected
  - type arguments significant
- @auto_hash_equals
  - alt_hash_name respected
  - field names respected
  - type arguments not significant
