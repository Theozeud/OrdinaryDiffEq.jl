using Roots
using LinearAlgebra
using UnPack

struct Relaxation{OPT, INV}
    opt::OPT
    invariant::INV
end

function (r::Relaxation)(integrator)

    @unpack t, dt, uprev, u_propose = integrator

    # We fix here the bounds of interval where we are going to look for the relaxation
    #(gamma_min, gamma_max) = apriori_bounds_dt(integrator) ./ dt
    
    S_u = u_propose - uprev

    # Find relaxation paramter gamma
    gamma_min = 0.5
    gamma_max = 1.5

    if (r.invariant(gamma_min*S_u .+ uprev) .- r.invariant(uprev)) * (r.invariant(gamma_max*S_u .+ uprev) .- r.invariant(uprev)) ≤ 0
        gamma = find_zero(gamma -> r.invariant(gamma*S_u .+ uprev) .- r.invariant(uprev),
                            (gamma_min, gamma_max),
                            r.opt())

        change_dt!(integrator, gamma*dt)
        change_u!(integrator, uprev + gamma*S_u)

        integrator.fsallast = integrator.fsalfirst + gamma*(integrator.fsallast - integrator.fsalfirst)
    end

    # println("######################  Print of dt time")
    # @show integrator.dt
    # @show integrator.dt_changed
    # @show integrator.opts.dtmin
    # @show integrator.opts.dtmax
    # if has_tstop(integrator)
    #     @show first_tstop(integrator) - integrator.t
    # end

end