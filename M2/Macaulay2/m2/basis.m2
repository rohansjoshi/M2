-- Copyright 1995-2002 by Daniel R. Grayson and Michael Stillman
-- Updated 2021 by Mahrud Sayrafi
-* TODO:
 0. hookify, cache
 1. what are (basis, ZZ, List, *) methods for? why only Ring and Ideal?
 2. why isn't (basis, Matrix) implemented?
*-

needs "gb.m2"
needs "max.m2" -- for InfiniteNumber
needs "modules2.m2"
needs "ringmap.m2"

-----------------------------------------------------------------------------
-- Local variables
-----------------------------------------------------------------------------

algorithms := new MutableHashTable from {}

-----------------------------------------------------------------------------
-- Local utilities
-----------------------------------------------------------------------------

inf := t -> if t === infinity then -1 else t

-----------------------------------------------------------------------------
-- helpers for basis
-----------------------------------------------------------------------------

-- the output of this is used in BasisContext
getVarlist = (R, varlist) -> toList(
    numvars := R.numallvars ?? numgens R;
    if varlist === null then toList(0 .. numvars - 1)
    else if instance(varlist, VisibleList) then apply(varlist, v ->
        -- TODO: what if R = ZZ?
        if instance(v, R)  then index v else
        if instance(v, ZZ) then v
        else error "expected list of ring variables or variable indices")
    else error "expected list of ring variables or variable indices")

findHeftandVars := (R, varlist, ndegs) -> (
    -- returns (posvars, heftvec)
    -- such that posvars is a subset of varlist
    -- consisting of those vars whose degree is not 0 on the first ndegs slots
    -- and heftvec is an integer vector of length ndegs s.t. heftvec.deg(x) > 0 for each variable x in posvars
    r := degreeLength R;
    varlist = getVarlist(R, varlist);
    if ndegs == 0 or #varlist == 0 then return (varlist, toList(ndegs : 1));
    if ndegs == r and #varlist == numgens R then (
        heftvec := heft R;
        if heftvec =!= null then return (varlist, heftvec));
    --
    zerodeg := toList(ndegs:0);
    posvars := select(varlist, x -> R_x != 0 and take(degree R_x, ndegs) != zerodeg);
    nonvars := select(varlist, x -> R_x == 0 or  take(degree R_x, ndegs) == zerodeg);
    -- given a partial multidegree, or when the subring generated by variables
    -- that do not contribute to the given multidegree is positive dimensional,
    -- use only the variables with non-zero degree in the appropriate entries.
    if ndegs < r or 0 < codim ideal apply(nonvars, i -> R_i) then varlist = posvars;
    -- compute heft vector for posvars
    degs := apply(posvars, x -> take(degree R_x, ndegs));
    heftvec = findHeft(degs, DegreeRank => ndegs);
    if heftvec =!= null then (varlist, heftvec)
    else error("heft vector required that is positive on the degrees of the variables " | toString posvars))

-- TODO: can this be done via a tensor or push forward?
-- c.f. https://github.com/Macaulay2/M2/issues/1522
liftBasis = (M, phi, B, offset) -> (
    -- lifts a basis B of M via a ring map phi
    (R, S) := (phi.target, phi.source);
    (n, m) := degreeLength \ (R, S);
    offset  = if offset =!= null then splice offset else toList( n:0 );
    -- TODO: audit this line. Why doesn't map(M, , B, Degree => offset) work?
    if R === S then return map(M, , B, Degree => offset);
    r := if n === 0 then rank source B else (
        lifter := phi.cache.DegreeLift;
        if not instance(lifter, Function)
        then rank source B else (
            zeroDegree := toList(m:0);
            apply(pack(n, degrees source B),
                deg -> try - lifter(deg - offset) else zeroDegree)));
    map(M, S ^ r, phi, B, Degree => offset))

-- TODO: is there already code to do this? if not then
-- implement related functions and move to modules.m2?
-- Non-torsion components of a ZZ-module
freeComponents = N -> select(numgens N, i -> QQ ** N_{i} != 0)
-- Torsion components of a ZZ-module
torsionComponents = N -> select(numgens N, i -> QQ ** N_{i} == 0)
-- Map to a ring where degree components are permuted so that
-- the free components come before the torsion components.
permuteDegreeGroup = R -> (
    G := degreeGroup R;
    F := freeComponents G;
    P := F | torsionComponents G;
    H := subquotient(
	if G.?generators then G.generators^P,
	if G.?relations  then G.relations^P);
    f := deg -> if deg =!= null then deg_F;
    p := deg -> if deg =!= null then deg_P;
    S := newRing(R,
	Heft        => p heft R,
	Degrees     => p \ degrees R,
	DegreeGroup => H);
    -- FIXME: why is inverse phi not automatically homogeneous?
    phi := map(S, R, generators S, DegreeMap => p);
    -- TODO: this shouldn't be necessary, see https://github.com/Macaulay2/M2/issues/2580
    psi := map(R, S, generators R, DegreeMap => deg -> deg_(inversePermutation P)); -- TODO: F^-1 for inversePermutation F?
    (S, phi, psi, p, f))

-----------------------------------------------------------------------------
-- basis
-----------------------------------------------------------------------------

basis = method(TypicalValue => Matrix,
    Options => {
        Strategy   => null,
        SourceRing => null,     -- defaults to ring of the module, but accepts the coefficient ring
        Variables  => null,     -- defaults to the generators of the ring
        Degree     => null,     -- offset the degree of the resulting matrix
        Limit      => infinity, -- upper bound on the number of basis elements to collect
        Truncate   => false     -- TODO: what does this do?
        }
    )

-----------------------------------------------------------------------------

basis Module := opts -> M -> basis(-infinity, infinity, M, opts)
basis Ideal  := opts -> I -> basis(module I, opts)
basis Ring   := opts -> R -> basis(module R, opts)
basis Matrix := opts -> m -> basis(-infinity, infinity, m, opts)

-----------------------------------------------------------------------------

basis(List,                           Module) := opts -> (deg,    M) -> basisHelper(opts,  deg,   deg,  M)
basis(ZZ,                             Module) := opts -> (deg,    M) -> basisHelper(opts, {deg}, {deg}, M)
basis(InfiniteNumber, InfiniteNumber, Module) :=
basis(InfiniteNumber, List,           Module) := opts -> (lo, hi, M) -> basisHelper(opts,  lo,    hi,   M)
basis(InfiniteNumber, ZZ,             Module) :=
basis(List,           ZZ,             Module) := opts -> (lo, hi, M) -> basisHelper(opts,  lo,   {hi},  M)
basis(List,           List,           Module) :=
basis(List,           InfiniteNumber, Module) := opts -> (lo, hi, M) -> basisHelper(opts,  lo,    hi,   M)
basis(ZZ,             InfiniteNumber, Module) :=
basis(ZZ,             List,           Module) := opts -> (lo, hi, M) -> basisHelper(opts, {lo},   hi,   M)
basis(ZZ,             ZZ,             Module) := opts -> (lo, hi, M) -> basisHelper(opts, {lo},  {hi},  M)

-----------------------------------------------------------------------------

basis(List,                           Ideal) :=
basis(ZZ,                             Ideal) := opts -> (deg,    I) -> basis(deg, deg, module I, opts)
basis(InfiniteNumber, InfiniteNumber, Ideal) :=
basis(InfiniteNumber, List,           Ideal) :=
basis(InfiniteNumber, ZZ,             Ideal) :=
basis(List,           InfiniteNumber, Ideal) :=
basis(List,           List,           Ideal) :=
basis(List,           ZZ,             Ideal) :=
basis(ZZ,             InfiniteNumber, Ideal) :=
basis(ZZ,             List,           Ideal) :=
basis(ZZ,             ZZ,             Ideal) := opts -> (lo, hi, I) -> basis(lo,  hi,  module I, opts)

-----------------------------------------------------------------------------

basis(List,                           Ring) :=
basis(ZZ,                             Ring) := opts -> (deg,    R) -> basis(deg, deg, module R, opts)
basis(InfiniteNumber, InfiniteNumber, Ring) :=
basis(InfiniteNumber, List,           Ring) :=
basis(InfiniteNumber, ZZ,             Ring) :=
basis(List,           InfiniteNumber, Ring) :=
basis(List,           List,           Ring) :=
basis(List,           ZZ,             Ring) :=
basis(ZZ,             InfiniteNumber, Ring) :=
basis(ZZ,             List,           Ring) :=
basis(ZZ,             ZZ,             Ring) := opts -> (lo, hi, R) -> basis(lo,  hi,  module R, opts)

-----------------------------------------------------------------------------

inducedBasisMap = (G, F, f) -> (
    -- Assumes G = image basis(deg, target f) and F = image basis(deg, source f)
    -- this helper routine is useful for computing basis of a pair of composable
    -- matrices or a chain complex, when target f is the source of a matrix which
    -- we previously computed basis for.
    psi := f * inducedMap(source f, , generators F);
    phi := last coefficients(ambient psi, Monomials => generators G);
    map(G, F, phi, Degree => degree f))
    -- TODO: benchmark against inducedTruncationMap in Truncations.m2
    -- f' := f * inducedMap(source f, F)       * inducedMap(F, source generators F, generators F);
    -- map(G, F, inducedMap(G, source f', f') // inducedMap(G, source generators G, generators G), Degree => degree f))

basis(List,                           Matrix) :=
basis(ZZ,                             Matrix) := opts -> (deg, M) -> basis(deg, deg, M, opts)
basis(InfiniteNumber, InfiniteNumber, Matrix) :=
basis(InfiniteNumber, List,           Matrix) :=
basis(InfiniteNumber, ZZ,             Matrix) :=
basis(List,           InfiniteNumber, Matrix) :=
basis(List,           List,           Matrix) :=
basis(List,           ZZ,             Matrix) :=
basis(ZZ,             InfiniteNumber, Matrix) :=
basis(ZZ,             List,           Matrix) :=
basis(ZZ,             ZZ,             Matrix) := opts -> (lo, hi, M) -> inducedBasisMap(
    image basis(lo, hi, target M, opts), image basis(lo, hi, source M, opts), M)

-----------------------------------------------------------------------------

-- Note: f needs to be homogeneous, otherwise returns nonsense
basis           RingMap  := Matrix => opts ->        f  -> basis(({},   {}),   f, opts)
basis(ZZ,       RingMap) :=
basis(List,     RingMap) := Matrix => opts -> (degs, f) -> basis((degs, degs), f, opts)
basis(Sequence, RingMap) := Matrix => opts -> (degs, f) -> (
    -- if not isHomogeneous f then error "expected a graded ring map (try providing a DegreeMap)";
    if #degs != 2          then error "expected a sequence (tardeg, srcdeg) of degrees for target and source rings";
    (T, S) := (target f, source f);
    (tardeg, srcdeg) := degs;
    if tardeg === null then tardeg = f.cache.DegreeMap  srcdeg;
    if srcdeg === null then srcdeg = f.cache.DegreeLift tardeg;
    targens := basis(tardeg, tardeg, T);
    srcgens := basis(srcdeg, srcdeg, S);
    -- TODO: should matrix RingMap return this map instead?
    -- mon := map(module T, image matrix(S, { S.FlatMonoid_* }), f, matrix f)
    mat := last coefficients(f cover srcgens, Monomials => targens);
    map(image targens, image srcgens, f, mat))

-----------------------------------------------------------------------------

basisHelper = (opts, lo, hi, M) -> (
    R := ring M;
    n := degreeLength R;
    strategy := opts.Strategy;

    -- TODO: check that S is compatible; i.e. there is a map R <- S
    -- perhaps the map should be given as the option instead?
    S := if opts.SourceRing =!= null then opts.SourceRing else R;
    phi := map(R, S);

    if lo === -infinity then lo = {} else
    if lo ===  infinity then error "incongruous lower degree bound: infinity";
    if hi ===  infinity then hi = {} else
    if hi === -infinity then error "incongruous upper degree bound: -infinity";

    -- implement generic degree check
    if #lo != 0  and #lo > n
    or #hi != 0  and #hi > n then error "expected length of degree bound not to exceed that of ring";
    if lo =!= hi and #lo > 1 then error "degree rank > 1 and degree bounds differ";
    if not all(lo, i -> instance(i, ZZ)) then error("expected a list of integers: ", toString lo);
    if not all(hi, i -> instance(i, ZZ)) then error("expected a list of integers: ", toString hi);

    -- e.g., basis(4, 2, QQ[x])
    if #hi == 1 and #lo == 1 and hi - lo < {0}
    then return if S === R then map(M, S^0, {}) else map(M, S^0, phi, {});

    opts = opts ++ {
        Limit      => if opts.Limit == -1 then infinity else opts.Limit
        };

    -- the actual computation of the basis occurs here
    B := runHooks((basis, List, List, Module), (opts, lo, hi, M), Strategy => strategy);

    if B =!= null then liftBasis(M, phi, B, opts.Degree) else if strategy === null
    then error("no applicable strategy for computing bases over ", toString R)
    -- used to be: error "'basis' can't handle this type of ring";
    else error("assumptions for basis strategy ", toString strategy, " are not met"))

-----------------------------------------------------------------------------
-- strategies for basis
-----------------------------------------------------------------------------

basisDefaultStrategy = (opts, lo, hi, M) -> (
    R := ring M;
    A := ultimate(ambient, R); -- is ambient better or coefficientRing?

    -- the assumptions for the default strategy:
    if not (ZZ === A
        or isAffineRing A
        or isPolynomialRing A and isAffineRing coefficientRing A and A.?SkewCommutative
        or isPolynomialRing A and ZZ === coefficientRing A )
    then return null;

    (varlist, heftvec) := findHeftandVars(R, opts.Variables, max(#hi, #lo));
    -- override if the user specifies the variables
    if opts.Variables =!= null then varlist = getVarlist(R, opts.Variables);

    m := generators gb presentation M;
    log := FunctionApplication { rawBasis, (
            raw m,
            lo, hi,
            heftvec,
            varlist,
            opts.Truncate,
            inf opts.Limit
            )};
    M.cache#"rawBasis log" = Bag {log};
    B := value log;
    B)

-- Note: for now, the strategies must return a RawMatrix
algorithms#(basis, List, List, Module) = new MutableHashTable from {
    Default => basisDefaultStrategy,
    -- For rings whose degree group has torsion
    -- TODO: should be handled in the engine
    Torsion => (opts, lo, hi, M) -> (
	G := degreeGroup(R := ring M);
	if G == 0 or isFreeModule G then return null;
	(S, phi, psi, p, f) := permuteDegreeGroup R;
	B := psi map_S basisDefaultStrategy(opts, f lo, f hi, phi M);
	L := positions(degrees source B, deg -> lo <= deg and deg <= hi);
	raw submatrix(B, , L)),
    -- TODO: add separate strategies for skew commutative rings, vector spaces, and ZZ-modules
    }

-- Installing hooks for resolution
scan({Default, Torsion}, strategy ->
    addHook(key := (basis, List, List, Module), algorithms#key#strategy, Strategy => strategy))
