function initialize!(integrator, ::Tsit5ConstantCache_for_relaxation)
    integrator.kshortsize = 7
    integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
    integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
    integrator.stats.nf += 1

    # Avoid undefined entries if k is an array of arrays
    integrator.fsallast = zero(integrator.fsalfirst)
    integrator.k[1] = integrator.fsalfirst
    @inbounds for i in 2:(integrator.kshortsize - 1)
        integrator.k[i] = zero(integrator.fsalfirst)
    end
    integrator.k[integrator.kshortsize] = integrator.fsallast
end


function perform_step!(integrator, cache::Tsit5ConstantCache_for_relaxation, repeat_step = false)

    # Variable to know if dt has changed during perform_step
    integrator.dt_has_changed = false

    # computations! will only contain the mathematical scheme
    # i.e the computations of the u(t+dt)
    # the result is store not in integrator.u but integrator.u_propose
    computations!(integrator, cache, repeat_step)

    # modif_step! enables to modify the step like when we want to perform a relaxation
    # for this we give a new struture that can be defined either by us for already known
    # modification we want to do or by a user (see below)
    modif_step!(integrator)

    # finalize_step! will do staff related to the solver like integrator.stats, register integrator.fsal
    # and register integrator.u
    finalize_step!(integrator, cache)
end


@muladd function computations!(integrator, ::Tsit5ConstantCache_for_relaxation, repeat_step = false)
    @unpack t, dt, uprev, u, f, p = integrator
    T = constvalue(recursive_unitless_bottom_eltype(u))
    T2 = constvalue(typeof(one(t)))
    @OnDemandTableauExtract Tsit5ConstantCacheActual T T2
    k1 = integrator.fsalfirst
    a = dt * a21
    k2 = f(uprev + a * k1, p, t + c1 * dt)
    k3 = f(uprev + dt * (a31 * k1 + a32 * k2), p, t + c2 * dt)
    k4 = f(uprev + dt * (a41 * k1 + a42 * k2 + a43 * k3), p, t + c3 * dt)
    k5 = f(uprev + dt * (a51 * k1 + a52 * k2 + a53 * k3 + a54 * k4), p, t + c4 * dt)
    g6 = uprev + dt * (a61 * k1 + a62 * k2 + a63 * k3 + a64 * k4 + a65 * k5)
    k6 = f(g6, p, t + dt)
    u = uprev + dt * (a71 * k1 + a72 * k2 + a73 * k3 + a74 * k4 + a75 * k5 + a76 * k6)
    k7 = f(u, p, t + dt)
    integrator.k[1] = k1
    integrator.k[2] = k2
    integrator.k[3] = k3
    integrator.k[4] = k4
    integrator.k[5] = k5
    integrator.k[6] = k6
    integrator.k[7] = k7
    integrator.u_propose = u

    if integrator.opts.adaptive
        utilde = dt *
                 (btilde1 * integrator.k[1] + btilde2 * integrator.k[2] + btilde3 * integrator.k[3] + btilde4 * integrator.k[4] + btilde5 * integrator.k[5] +
                  btilde6 * integrator.k[6] + btilde7 * integrator.k[7])
        atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol,
            integrator.opts.reltol, integrator.opts.internalnorm, t)
        integrator.EEst = integrator.opts.internalnorm(atmp, t)
    end
end


function modif_step!(integrator)
    
    # Perform the modifications
    if !(integrator.opts.modif isa Nothing)
        integrator.opts.modif(integrator)

        # Here we check the validity of chaging dt if it has changed
        # if it is valid integrator.changed_valid will be true, if not it will be false
        changed_valid = true
        if integrator.dt_has_changed
            # check dt in [dtmin, dtmax]
            # things related to tstops
            # surely other things
            if changed_valid
                integrator.u_propose = integrator.u_changed
                integrator.dt = integrator.dt_changed
            else
                # print error or warning
            end
        end
    end
end


function finalize_step!(integrator, cache::Tsit5ConstantCache_for_relaxation)
    @unpack t, dt, uprev, u_propose, f, p = integrator
    integrator.u = u_propose
    integrator.fsallast = f(u_propose, p, t + dt)

    integrator.stats.nf += 7
end


## Non Constant cache
function initialize!(integrator, cache::Tsit5Cache_for_relaxation)
    integrator.kshortsize = 7
    integrator.fsalfirst = cache.k1
    integrator.fsallast = cache.k7 # setup pointers
    resize!(integrator.k, integrator.kshortsize)
    # Setup k pointers
    integrator.k[1] = cache.k1
    integrator.k[2] = cache.k2
    integrator.k[3] = cache.k3
    integrator.k[4] = cache.k4
    integrator.k[5] = cache.k5
    integrator.k[6] = cache.k6
    integrator.k[7] = cache.k7
    integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
    integrator.stats.nf += 1
    return nothing
end


function perform_step!(integrator, cache::Tsit5Cache_for_relaxation, repeat_step = false)

    # Variable to know if dt has changed during perform_step
    integrator.dt_has_changed = false

    # computations! will only contain the mathematical scheme
    # i.e the computations of the u(t+dt)
    # the result is store not in integrator.u but integrator.u_propose
    computations!(integrator, cache, repeat_step)

    # modif_step! enables to modify the step like when we want to perform a relaxation
    # for this we give a new struture that can be defined either by us for already known
    # modification we want to do or by a user (see below)
    modif_step!(integrator)

    # finalize_step! will do staff related to the solver like integrator.stats, register integrator.fsal
    # and register integrator.u
    finalize_step!(integrator, cache)
end

@muladd function computations!(integrator, cache::Tsit5Cache_for_relaxation, repeat_step = false)
    @unpack t, dt, uprev, u_propose, f, p = integrator
    T = constvalue(recursive_unitless_bottom_eltype(u_propose))
    T2 = constvalue(typeof(one(t)))
    @OnDemandTableauExtract Tsit5ConstantCacheActual T T2
    @unpack k1, k2, k3, k4, k5, k6, k7, utilde, tmp, atmp, stage_limiter!, step_limiter!, thread = cache
    a = dt * a21
    @.. broadcast=false thread=thread tmp=uprev + a * k1
    stage_limiter!(tmp, f, p, t + c1 * dt)
    f(k2, tmp, p, t + c1 * dt)
    @.. broadcast=false thread=thread tmp=uprev + dt * (a31 * k1 + a32 * k2)
    stage_limiter!(tmp, f, p, t + c2 * dt)
    f(k3, tmp, p, t + c2 * dt)
    @.. broadcast=false thread=thread tmp=uprev + dt * (a41 * k1 + a42 * k2 + a43 * k3)
    stage_limiter!(tmp, f, p, t + c3 * dt)
    f(k4, tmp, p, t + c3 * dt)
    @.. broadcast=false thread=thread tmp=uprev +
                                          dt * (a51 * k1 + a52 * k2 + a53 * k3 + a54 * k4)
    stage_limiter!(tmp, f, p, t + c4 * dt)
    f(k5, tmp, p, t + c4 * dt)
    @.. broadcast=false thread=thread tmp=uprev +
                                          dt * (a61 * k1 + a62 * k2 + a63 * k3 + a64 * k4 +
                                           a65 * k5)
    stage_limiter!(tmp, f, p, t + dt)
    f(k6, tmp, p, t + dt)
    @.. broadcast=false thread=thread u_propose = uprev +
                                        dt * (a71 * k1 + a72 * k2 + a73 * k3 + a74 * k4 +
                                         a75 * k5 + a76 * k6)
    stage_limiter!(u_propose, integrator, p, t + dt)
    step_limiter!(u_propose, integrator, p, t + dt)

    f(k7, u_propose, p, t + dt)

    if integrator.opts.adaptive
        @.. broadcast=false thread=thread utilde=dt * (btilde1 * k1 + btilde2 * k2 +
                                                  btilde3 * k3 + btilde4 * k4 +
                                                  btilde5 * k5 + btilde6 * k6 +
                                                  btilde7 * k7)
        calculate_residuals!(atmp, utilde, uprev, u_propose, integrator.opts.abstol,
            integrator.opts.reltol, integrator.opts.internalnorm, t,
            thread)
        integrator.EEst = integrator.opts.internalnorm(atmp, t)
    end
    return nothing
end

function finalize_step!(integrator, cache::Tsit5Cache_for_relaxation)
    @unpack t, dt, u_propose, u, f, p = integrator
    @unpack k7, stage_limiter!, step_limiter!, thread = cache
    @.. broadcast=false thread=thread u = u_propose 
    stage_limiter!(u, integrator, p, t + dt)
    step_limiter!(u, integrator, p, t + dt)
    f(k7, u_propose, p, t + dt)
    integrator.stats.nf += 7
end
