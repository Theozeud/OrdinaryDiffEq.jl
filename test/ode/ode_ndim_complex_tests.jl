using OrdinaryDiffEq, DiffEqBase

## Start on Number
f = (u,p,t) -> (2u)
(p::typeof(f))(::Type{Val{:analytic}},u0,p,t) = u0*exp(t)
prob = ODEProblem(f,1/2+(1/4)im,(0.0,1.0))

sol = solve(prob,Tsit5(),dt=1/2^4)

u0 = rand(Complex64,5,5,5)
f = (du,u,p,t) -> (du.=2u)
(p::typeof(f))(::Type{Val{:analytic}},u0,p,t) = u0*exp(t)
prob = ODEProblem(f,u0,(0.0,1.0))

sol = solve(prob,Tsit5(),dt=1/2^4)

@test typeof(sol[1]) == Array{Complex64,3}
