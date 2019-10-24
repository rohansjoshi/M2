
gaussCC = () -> (
    (u1,u2):=(random RR,random RR);
    sqrt(-2*log(u1))*cos(2*pi*u2)+ii*sqrt(-2*log(u1))*sin(2*pi*u2)
    )

rNorm = (mu,var) -> mu+var*(realPart gaussCC())_CC

-- n = dim(sphere)+1, r = radius
sphere = (n,r) -> (
    l:=apply(n,i->rNorm(0,1));
    r/(sum apply(l,i->i^2))*l
    )

cauchy = () -> rNorm(0,1)/rNorm(0,1)

logCauchy = () -> exp cauchy()

m=n-1
R=CC[toList(a_1..a_m)|flatten for i from 0 to m list for j from i to m list B_({i,j})][s_1..s_m,c_1..c_m]
nParams=numgens coefficientRing R;
nVars=numgens R
topEqs=apply(toList(1..m),i->a_i-sum apply(toList(1..m),j->B_(sort{i,j})*(s_i*c_j-s_j-c_i*s_j)))
bottomEqs=apply(toList(1..m),i->c_i^2+s_i^2-1)
PS=polySystem(topEqs|bottomEqs)

end

uninstallPackage "MonodromySolver"
restart

installPackage("MonodromySolver",FileName=>"../MonodromySolver.m2",RerunExamples=>true)
needsPackage "MonodromySolver"

n=6
setRandomSeed 0
load "kuramoto.m2"


k=3
(tot,npav,fav,tav)=(0,0,0,0_RR)
iters=100
elapsedTime for i from 1 to iters do (
    zs=apply(m,i->random CC);
    rs=apply(zs,z->(realPart z)_CC);
    is=apply(zs,z->(imaginaryPart z)_CC);
    seedSC=rs|is;
    (p0,v0)=createSeedPair(PS,seedSC);
    t = first(timing (V,npaths)=monodromySolve(PS,p0,{v0},
    "new tracking routine"=>false,tMin=>(1e-1)^k,TargetSolutionCount=>252,
    SelectEdgeAndDirection => selectBestEdgeAndDirection, Potential => potentialE));
    f = V.Graph.Failures;
    suc = (#points V.PartialSols == 252) and all(points V.PartialSols,p->norm evaluate(polySystem V.SpecializedSystem, p) < 1e-5);
    if suc then tot = tot +1;
    if instance(npaths,ZZ) then npav = npav + npaths;
    fav = fav + f;
    tav = tav + t;
    print ("success is " | toString suc);
    print ("failure rate is " | toString f);
    print ("time is " | toString t);
    print ("npaths is " | toString npaths);
    )
sub(tot/iters,RR)

peek V.Graph
# points V.PartialSols