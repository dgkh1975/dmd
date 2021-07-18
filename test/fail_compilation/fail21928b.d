/*
TEST_OUTPUT:
---
fail_compilation/fail21928b.d(18): Error: array literal in `@nogc` function `D main` may cause a GC allocation
---
*/

@nogc:


struct Shape
{
    immutable size_t[] dims = [];
}

void main()
{
    auto s = Shape(Shape.init.dims ~ 2);
}
