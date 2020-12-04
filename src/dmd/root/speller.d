/**
 * Try to detect typos in identifiers.
 *
 * Copyright: Copyright (C) 1999-2020 by The D Language Foundation, All Rights Reserved
 * Authors:   Walter Bright, http://www.digitalmars.com
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:    $(LINK2 https://github.com/dlang/dmd/blob/master/src/dmd/root/speller.d, root/_speller.d)
 * Documentation:  https://dlang.org/phobos/dmd_root_speller.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/src/dmd/root/speller.d
 */

module dmd.root.speller;

import core.stdc.stdlib;
import core.stdc.string;

/* Characters used to substitute ones in the string we're checking
 * the spelling on.
 */
private immutable string idchars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";

/**************************************************
 * Combine a new result from the spell checker to
 * find the one with the closest symbol with
 * respect to the cost defined by the search function
 * Params:
 *      p = best found spelling so far, T.init if none found yet.
 *          If np is better, p is replaced with np
 *      cost = cost of p (int.max if none found yet).
 *          If np is better, cost is replaced with ncost
 *      np = current spelling to check against p, T.init if none
 *      ncost = cost of np if np is not T.init
 * Returns:
 *      true    if the cost is less or equal 0, meaning we can stop looking
 *      false   otherwise
 */
private bool combineSpellerResult(T)(ref T p, ref int cost, T np, int ncost)
{
    if (np && ncost < cost) // if np is better
    {
        p = np;             // np is new best match
        cost = ncost;
        if (cost <= 0)
            return true;    // meaning we can stop looking
    }
    return false;
}

/**********************************************
 * Do second level of spell matching.
 * Params:
 *      dg = delegate that looks up string in dictionary AA and returns value found
 *      seed = starting string
 *      index = index into seed[] that is where we will mutate it
 *      cost = current best match, will update it
 * Returns:
 *      whatever dg returns, null if no match
 */
private auto spellerY(alias dg)(const(char)[] seed, size_t index, ref int cost)
{
    if (!seed.length)
        return null;

    /* Allocate a buf to store the new string to play with, needs
     * space for an extra char for insertions
     */
    char[30] tmp = void;        // stack allocations are fastest
    char[] buf;
    if (seed.length <= tmp.sizeof - 1)
        buf = tmp;
    else
    {
        buf = (cast(char*)alloca(seed.length + 1))[0 .. seed.length + 1]; // leave space for extra char
        if (!buf.ptr)
            return null; // no matches
    }
    buf[0 .. index] = seed[0 .. index];

    cost = int.max;             // start with worst possible match
    searchFunctionType!dg p = null;
    int ncost;

    /* Delete character at seed[index] */
    if (index < seed.length)
    {
        buf[index .. seed.length - 1] = seed[index + 1 .. $]; // seed[] with deleted character
        auto np = dg(buf[0 .. seed.length - 1], ncost); // look it up
        if (combineSpellerResult(p, cost, np, ncost))   // compare with prev match
            return p;                                   // cannot get any better
    }

    /* Substitute character at seed[index] */
    if (index < seed.length)
    {
        buf[0 .. seed.length] = seed;
        foreach (s; idchars)
        {
            buf[index] = s;     // seed[] with substituted character
            //printf("sub buf = '%s'\n", buf);
            auto np = dg(buf[0 .. seed.length], ncost);
            if (combineSpellerResult(p, cost, np, ncost))
                return p;
        }
    }

    /* Insert character at seed[index] */
    buf[index + 1 .. seed.length + 1] = seed[index .. $];
    foreach (s; idchars)
    {
        buf[index] = s;
        //printf("ins buf = '%s'\n", buf);
        auto np = dg(buf[0 .. seed.length + 1], ncost);
        if (combineSpellerResult(p, cost, np, ncost))
            return p;
    }
    return p; // return "best" result
}

/*************************************
 * Spell check level 1.
 * Params:
 *      dg = delegate that looks up string in dictionary AA and returns value found
 *      seed = starting string
 *      flag = if true, do 2 level lookup
 * Returns:
 *      whatever dg returns, null if no match
 */
private auto spellerX(alias dg)(const(char)[] seed, bool flag)
{
    if (!seed.length)
        return null;

    /* Need buffer to store trial strings in
     */
    char[30] tmp = void;
    char[] buf;
    if (seed.length <= tmp.sizeof - 1)
        buf = tmp;
    else
    {
        buf = (cast(char*)alloca(seed.length + 1))[0 .. seed.length + 1]; // leave space for extra char
    }

    int cost = int.max;
    int ncost;
    searchFunctionType!dg p = null, np;

    /* Deletions */
    buf[0 .. seed.length - 1] = seed[1 .. $];
    for (size_t i = 0; i < seed.length; i++)
    {
        //printf("del buf = '%s'\n", buf);
        if (flag)
            np = spellerY!dg(buf[0 .. seed.length - 1], i, ncost);
        else
            np = dg(buf[0 .. seed.length - 1], ncost);
        if (combineSpellerResult(p, cost, np, ncost))
            return p;
        buf[i] = seed[i];
    }

    /* Transpositions */
    if (!flag)
    {
        buf[0 .. seed.length] = seed;
        for (size_t i = 0; i + 1 < seed.length; i++)
        {
            // swap [i] and [i + 1]
            buf[i] = seed[i + 1];
            buf[i + 1] = seed[i];
            //printf("tra buf = '%s'\n", buf);
            if (combineSpellerResult(p, cost, dg(buf[0 .. seed.length], ncost), ncost))
                return p;
            buf[i] = seed[i];
        }
    }

    /* Substitutions */
    buf[0 .. seed.length] = seed;
    for (size_t i = 0; i < seed.length; i++)
    {
        foreach (s; idchars)
        {
            buf[i] = s;
            //printf("sub buf = '%s'\n", buf);
            if (flag)
                np = spellerY!dg(buf[0 .. seed.length], i + 1, ncost);
            else
                np = dg(buf[0 .. seed.length], ncost);
            if (combineSpellerResult(p, cost, np, ncost))
                return p;
        }
        buf[i] = seed[i];
    }

    /* Insertions */
    buf[1 .. seed.length + 1] = seed;
    for (size_t i = 0; i <= seed.length; i++) // yes, do seed.length+1 iterations
    {
        foreach (s; idchars)
        {
            buf[i] = s;
            //printf("ins buf = '%s'\n", buf);
            if (flag)
                np = spellerY!dg(buf[0 .. seed.length + 1], i + 1, ncost);
            else
                np = dg(buf[0 .. seed.length + 1], ncost);
            if (combineSpellerResult(p, cost, np, ncost))
                return p;
        }
        if (i < seed.length)
            buf[i] = seed[i];
    }

    return p; // return "best" result
}

/**************************************************
 * Looks for correct spelling.
 * Looks a distance of up to two.
 * This does an exhaustive search, so can potentially be very slow.
 * Params:
 *      seed = wrongly spelled word
 *      dg = search delegate of the form `T delegate(const(char)[] p, ref int cost)`
 * Returns:
 *      T.init = no correct spellings found,
 *      otherwise the value returned by dg() for first possible correct spelling
 */
auto speller(alias dg)(const(char)[] seed)
if (isSearchFunction!dg)
{
    size_t maxdist = seed.length < 4 ? seed.length / 2 : 2;
    for (int distance = 0; distance < maxdist; distance++)
    {
        auto p = spellerX!dg(seed, distance > 0);
        if (p)
            return p;
        //      if (seedlen > 10)
        //          break;
    }
    return null; // didn't find it
}

enum isSearchFunction(alias fun) = is(searchFunctionType!fun);
alias searchFunctionType(alias fun) = typeof(() {int x; return fun("", x);}());

unittest
{
    static immutable string[][] cases =
    [
        ["hello", "hell", "y"],
        ["hello", "hel", "y"],
        ["hello", "ello", "y"],
        ["hello", "llo", "y"],
        ["hello", "hellox", "y"],
        ["hello", "helloxy", "y"],
        ["hello", "xhello", "y"],
        ["hello", "xyhello", "y"],
        ["hello", "ehllo", "y"],
        ["hello", "helol", "y"],
        ["hello", "abcd", "n"],
        ["hello", "helxxlo", "y"],
        ["hello", "ehlxxlo", "n"],
        ["hello", "heaao", "y"],
        ["_123456789_123456789_123456789_123456789", "_123456789_123456789_123456789_12345678", "y"],
    ];
    //printf("unittest_speller()\n");

    string dgarg;

    string speller_test(const(char)[] s, ref int cost)
    {
        assert(s[$-1] != '\0');
        //printf("speller_test(%s, %s)\n", dgarg, s);
        cost = 0;
        if (dgarg == s)
            return dgarg;
        return null;
    }

    dgarg = "hell";
    auto p = speller!speller_test("hello");
    assert(p !is null);
    foreach (testCase; cases)
    {
        //printf("case [%d]\n", i);
        dgarg = testCase[1];
        auto p2 = speller!speller_test(testCase[0]);
        if (p2)
            assert(testCase[2][0] == 'y');
        else
            assert(testCase[2][0] == 'n');
    }
    //printf("unittest_speller() success\n");
}
