needsPackage "NumericalSchubertCalculus"
setRandomSeed 2

--Problem WW2^3W11W21 in G(3,7)
 --a problem with 12 solutions

print("Solving problem WW2^3W11W21 in G(3,7)");

SchPblm = randomSchubertProblemInstance(
  {{2, 1},{1, 1},{2},{2},{2},{1}},3,7);
time S = solveSchubertProblem(SchPblm, 3,7);
assert all(S,s->checkIncidenceSolution(s, SchPblm))

 end
 ------

restart
 load"NumericalSchubertCalculus/EXA/ProblemsG37/WW2^3W11W21-G37.m2"

