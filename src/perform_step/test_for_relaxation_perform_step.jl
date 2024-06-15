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

function perform_step!(integrator, cache::Union{Tsit5Cache_for_relaxation,Tsit5ConstantCache_for_relaxation}, repeat_step = false)

    # Caculate uₙ₊₁
    calculate_nextstep!(integrator, cache, repeat_step)

    # Perform customize modification right after the step, i.e modify uₙ₊₁
    if has_poststep_callback(integrator)
        apply_poststep_callback!(integrator)
    end

    # Calculate f(uₙ₊₁) if the aglortihm has the FSAL property
    if isfsal(integrator.alg)
        calculate_fsal!(integrator, cache)
    end

    # Perform customize modification right after fsal, i.e modify f(uₙ₊₁)
    if has_postfsal_callback(integrator)
        apply_postfsal_callback!(integrator)
    end

    # Calculate the error estimate needed for PID controller
    if integrator.opts.adaptive
        calculate_EEst!(integrator, cache)
    end

    #Perform customized modification right after error estimate
    if has_postEEst_callback(integrator)
        apply_postEEst_callback!(integrator)
    end

    # finalize_step (useless for the moment)
    finalize_step!(integrator, cache)
end

function apply_poststep_callback!(integrator)

    # Variable to know if dt has changed during perform_step
    integrator.dt_has_changed = false

    integrator.opts.performstepcallback.poststep_cb(integrator)

    handle_dt_bound_and_tstop!(integrator)
end

function apply_postfsal_callback!(integrator)

    # Variable to know if dt has changed during perform_step
    integrator.dt_has_changed = false

    integrator.opts.performstepcallback.postfsal_cb(integrator)

    handle_dt_bound_and_tstop!(integrator)
end

function apply_postEEst_callback!(integrator)

    # Variable to know if dt has changed during perform_step
    integrator.dt_has_changed = false

    integrator.opts.performstepcallback.postEEst_cb(integrator)

    handle_dt_bound_and_tstop!(integrator)
end

function handle_dt_bound_and_tstop!(integrator)
    
    # Here we carry of the dt modified by the user in this step, if it has been changed.

    if integrator.dt_has_changed

        # Match dt in [dtmin, dtmax]
        if integrator.tdir > 0
            integrator.dt_changed = min(integrator.opts.dtmax, integrator.dt_changed)
        else
            integrator.dt_changed = max(integrator.opts.dtmax, integrator.dt_changed)
        end
        dtmin = timedepentdtmin(integrator)
        if integrator.tdir > 0
            integrator.dt_changed = max(integrator.dt_changed, dtmin)
        else
            integrator.dt_changed = min(integrator.dt_changed, dtmin)
        end
        # Match dt with tstops
        if has_tstop(integrator)
            tdir_t = integrator.tdir * integrator.t
            tdir_tstop = first_tstop(integrator)
            integrator.dt_changed = integrator.tdir * min(abs(integrator.dt_changed), abs(tdir_tstop - tdir_t)) 
        end
    
        integrator.dt = integrator.dt_changed
        integrator.dt_has_changed = false
    end
end

@muladd function calculate_nextstep!(integrator, ::Tsit5ConstantCache_for_relaxation, repeat_step = false)
    
    @unpack t, dt, uprev, u, f, p = integrator
    T = constvalue(recursive_unitless_bottom_eltype(u))
    T2 = constvalue(typeof(one(t)))
    @OnDemandTableauExtract Tsit5ConstantCacheActual T T2

    k1 = integrator.fsalfirst
    k2 = f(uprev + dt * a21 * k1, p, t + c1 * dt)
    k3 = f(uprev + dt * (a31 * k1 + a32 * k2), p, t + c2 * dt)
    k4 = f(uprev + dt * (a41 * k1 + a42 * k2 + a43 * k3), p, t + c3 * dt)
    k5 = f(uprev + dt * (a51 * k1 + a52 * k2 + a53 * k3 + a54 * k4), p, t + c4 * dt)
    k6 = f(uprev + dt * (a61 * k1 + a62 * k2 + a63 * k3 + a64 * k4 + a65 * k5), p, t + dt)
    u = uprev + dt * (a71 * k1 + a72 * k2 + a73 * k3 + a74 * k4 + a75 * k5 + a76 * k6)
    
    integrator.k[1] = k1
    integrator.k[2] = k2
    integrator.k[3] = k3
    integrator.k[4] = k4
    integrator.k[5] = k5
    integrator.k[6] = k6
    integrator.u = u

    integrator.stats.nf += 5
end

@muladd function calculate_fsal!(integrator, ::Tsit5ConstantCache_for_relaxation)
    @unpack t, dt, u, f, p = integrator
    k7 = f(u, p, t + dt)
    integrator.k[7] = k7
    integrator.fsallast = k7
    integrator.stats.nf += 1
end

@muladd function calculate_EEst!(integrator, ::Tsit5ConstantCache_for_relaxation)
    T = constvalue(recursive_unitless_bottom_eltype(integrator.u))
    T2 = constvalue(typeof(one(integrator.t)))
    @OnDemandTableauExtract Tsit5ConstantCacheActual T T2
    utilde = integrator.dt * (btilde1 * integrator.k[1] + btilde2 * integrator.k[2] 
            + btilde3 * integrator.k[3] + btilde4 * integrator.k[4] 
            + btilde5 * integrator.k[5] + btilde6 * integrator.k[6] 
            + btilde7 * integrator.fsallast)
    atmp = calculate_residuals(utilde, integrator.uprev, integrator.u, integrator.opts.abstol,
    integrator.opts.reltol, integrator.opts.internalnorm, integrator.t)
    integrator.EEst = integrator.opts.internalnorm(atmp, integrator.t)
end

function finalize_step!(integrator, ::Tsit5ConstantCache_for_relaxation)

end


## Non Constant cache

@muladd function calculate_nextstep!(integrator, cache::Tsit5Cache_for_relaxation, repeat_step = false)
    
    @unpack t, dt, uprev, u, f, p = integrator
    T = constvalue(recursive_unitless_bottom_eltype(u))
    T2 = constvalue(typeof(one(t)))
    @OnDemandTableauExtract Tsit5ConstantCacheActual T T2
    @unpack k1, k2, k3, k4, k5, k6, k7, utilde, tmp, atmp, stage_limiter!, step_limiter!, thread = cache

    @.. broadcast=false thread=thread tmp = uprev + dt * a21 * k1
    stage_limiter!(tmp, f, p, t + c1 * dt)
    f(k2, tmp, p, t + c1 * dt)
    @.. broadcast=false thread=thread tmp = uprev + dt * (a31 * k1 + a32 * k2)
    stage_limiter!(tmp, f, p, t + c2 * dt)
    f(k3, tmp, p, t + c2 * dt)
    @.. broadcast=false thread=thread tmp = uprev + dt * (a41 * k1 + a42 * k2 + a43 * k3)
    stage_limiter!(tmp, f, p, t + c3 * dt)
    f(k4, tmp, p, t + c3 * dt)
    @.. broadcast=false thread=thread tmp = uprev +
                                          dt * (a51 * k1 + a52 * k2 + a53 * k3 + a54 * k4)
    stage_limiter!(tmp, f, p, t + c4 * dt)
    f(k5, tmp, p, t + c4 * dt)
    @.. broadcast=false thread=thread tmp = uprev +
                            dt * (a61 * k1 + a62 * k2 + a63 * k3 + a64 * k4 + a65 * k5)
    stage_limiter!(tmp, f, p, t + dt)
    f(k6, tmp, p, t + dt)
    @.. broadcast=false thread=thread u = uprev +
                    dt * (a71 * k1 + a72 * k2 + a73 * k3 + a74 * k4 + a75 * k5 + a76 * k6)
    stage_limiter!(u, integrator, p, t + dt)
    step_limiter!(u, integrator, p, t + dt)

    integrator.stats.nf += 5
    return nothing
end

@muladd function calculate_fsal!(integrator, cache::Tsit5Cache_for_relaxation)
    @unpack t, dt, u, f, p = integrator
    f(cache.k7, u, p, t + dt)
    integrator.stats.nf += 1
end

@muladd function calculate_EEst!(integrator, cache::Tsit5Cache_for_relaxation)
    T = constvalue(recursive_unitless_bottom_eltype(u))
    T2 = constvalue(typeof(one(t)))
    @OnDemandTableauExtract Tsit5ConstantCacheActual T T2
    @unpack k1, k2, k3, k4, k5, k6, k7, utilde, atmp, thread = cache
    @.. broadcast = false thread = threa utilde = integrator.dt * 
        (btilde1 * k1 + btilde2 * k2 + btilde3 * k3 + btilde4 * k4 +
         btilde5 * k5 + btilde6 * k6 + btilde7 * k7)
    calculate_residuals!(atmp, utilde, integrator.uprev, integrator.u,
                         integrator.opts.abstol, integrator.opts.reltol, 
                         integrator.opts.internalnorm, integrator.t, thread)
    integrator.EEst = integrator.opts.internalnorm(atmp, integrator.t)
end

function finalize_step!(integrator, cache::Tsit5Cache_for_relaxation)

end

# Is this useful ?
function apriori_bounds_dt(integrator)
    dt_sup = if has_tstop(integrator)
         integrator.tdir * min(abs(integrator.opts.dtmax) , abs(first_tstop(integrator) - integrator.t))
    else
        integrator.tdir * abs(integrator.opts.dtmax)
    end
    dt_inf = integrator.tdir * timedepentdtmin(integrator)
    (dt_inf,dt_sup)
end