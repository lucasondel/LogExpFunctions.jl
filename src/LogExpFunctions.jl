module LogExpFunctions

export xlogx, xlogy, logistic, logit, log1psq, log1pexp, log1mexp, log2mexp, logexpm1,
    log1pmx, logmxp1, logaddexp, logsumexp, softmax!, softmax

using DocStringExtensions: SIGNATURES

using Base: Math.@horner, @irrational

####
#### constants
####

@irrational loghalf -0.6931471805599453094 log(big(0.5))
@irrational logtwo 0.6931471805599453094 log(big(2.))
@irrational logπ   1.1447298858494001741 log(big(π))
@irrational log2π  1.8378770664093454836 log(big(2.)*π)
@irrational log4π  2.5310242469692907930 log(big(4.)*π)

####
#### functions
####

"""
$(SIGNATURES)

Return `x * log(x)` for `x ≥ 0`, handling ``x = 0`` by taking the downward limit.

```jldoctest
julia> xlogx(0)
0.0
```
"""
xlogx(x::Real) = x > zero(x) ? x * log(x) : zero(log(x))

"""
$(SIGNATURES)

Return `x * log(y)` for `y > 0` with correct limit at ``x = 0``.
"""
xlogy(x::T, y::T) where {T<:Real} = x > zero(T) ? x * log(y) : zero(log(x))
xlogy(x::Real, y::Real) = xlogy(promote(x, y)...)

"""
$(SIGNATURES)

The [logistic](https://en.wikipedia.org/wiki/Logistic_function) sigmoid function mapping a
real number to a value in the interval ``[0,1]``,

```math
\\sigma(x) = \\frac{1}{e^{-x} + 1} = \\frac{e^x}{1+e^x}.
```

Its inverse is the [`logit`](@ref) function.
"""
logistic(x::Real) = inv(exp(-x) + one(x))

"""
$(SIGNATURES)

The [logit](https://en.wikipedia.org/wiki/Logit) or log-odds transformation,

```math
\\log\\left(\\frac{x}{1-x}\\right), \\text{where} 0 < x < 1
```

Its inverse is the [`logistic`](@ref) function.
"""
logit(x::Real) = log(x / (one(x) - x))

"""
$(SIGNATURES)

Return `log(1+x^2)` evaluated carefully for `abs(x)` very small or very large.
"""
log1psq(x::Real) = log1p(abs2(x))
function log1psq(x::Union{Float32,Float64})
    ax = abs(x)
    ax < maxintfloat(x) ? log1p(abs2(ax)) : 2 * log(ax)
end

"""
$(SIGNATURES)

Return `log(1+exp(x))` evaluated carefully for largish `x`.

This is also called the ["softplus"](https://en.wikipedia.org/wiki/Rectifier_(neural_networks))
transformation, being a smooth approximation to `max(0,x)`. Its inverse is [`logexpm1`](@ref).
"""
log1pexp(x::Real) = x < 18.0 ? log1p(exp(x)) : x < 33.3 ? x + exp(-x) : oftype(exp(-x), x)
log1pexp(x::Float32) = x < 9.0f0 ? log1p(exp(x)) : x < 16.0f0 ? x + exp(-x) : oftype(exp(-x), x)

"""
$(SIGNATURES)

Return `log(1 - exp(x))`

See:
 * Martin Maechler (2012) [“Accurately Computing log(1 − exp(− |a|))”](http://cran.r-project.org/web/packages/Rmpfr/vignettes/log1mexp-note.pdf)

Note: different than Maechler (2012), no negation inside parentheses
"""
log1mexp(x::Real) = x < loghalf ? log1p(-exp(x)) : log(-expm1(x))

"""
$(SIGNATURES)

Return `log(2 - exp(x))` evaluated as `log1p(-expm1(x))`
"""
log2mexp(x::Real) = log1p(-expm1(x))

"""
$(SIGNATURES)

Return `log(exp(x) - 1)` or the “invsoftplus” function.  It is the inverse of
[`log1pexp`](@ref) (aka “softplus”).
"""
logexpm1(x::Real) = x <= 18.0 ? log(expm1(x)) : x <= 33.3 ? x - exp(-x) : oftype(exp(-x), x)

logexpm1(x::Float32) = x <= 9f0 ? log(expm1(x)) : x <= 16f0 ? x - exp(-x) : oftype(exp(-x), x)

const softplus = log1pexp
const invsoftplus = logexpm1

"""
$(SIGNATURES)

Return `log(1 + x) - x`.

Use naive calculation or range reduction outside kernel range.  Accurate ~2ulps for all `x`.
"""
function log1pmx(x::Float64)
    if !(-0.7 < x < 0.9)
        return log1p(x) - x
    elseif x > 0.315
        u = (x-0.5)/1.5
        return _log1pmx_ker(u) - 9.45348918918356180e-2 - 0.5*u
    elseif x > -0.227
        return _log1pmx_ker(x)
    elseif x > -0.4
        u = (x+0.25)/0.75
        return _log1pmx_ker(u) - 3.76820724517809274e-2 + 0.25*u
    elseif x > -0.6
        u = (x+0.5)*2.0
        return _log1pmx_ker(u) - 1.93147180559945309e-1 + 0.5*u
    else
        u = (x+0.625)/0.375
        return _log1pmx_ker(u) - 3.55829253011726237e-1 + 0.625*u
    end
end

"""
$(SIGNATURES)

Return `log(x) - x + 1` carefully evaluated.
"""
function logmxp1(x::Float64)
    if x <= 0.3
        return (log(x) + 1.0) - x
    elseif x <= 0.4
        u = (x-0.375)/0.375
        return _log1pmx_ker(u) - 3.55829253011726237e-1 + 0.625*u
    elseif x <= 0.6
        u = 2.0*(x-0.5)
        return _log1pmx_ker(u) - 1.93147180559945309e-1 + 0.5*u
    else
        return log1pmx(x - 1.0)
    end
end

# The kernel of log1pmx
# Accuracy within ~2ulps for -0.227 < x < 0.315
function _log1pmx_ker(x::Float64)
    r = x/(x+2.0)
    t = r*r
    w = @horner(t,
                6.66666666666666667e-1, # 2/3
                4.00000000000000000e-1, # 2/5
                2.85714285714285714e-1, # 2/7
                2.22222222222222222e-1, # 2/9
                1.81818181818181818e-1, # 2/11
                1.53846153846153846e-1, # 2/13
                1.33333333333333333e-1, # 2/15
                1.17647058823529412e-1) # 2/17
    hxsq = 0.5*x*x
    r*(hxsq+w*t)-hxsq
end


"""
$(SIGNATURES)

Return `log(exp(x) + exp(y))`, avoiding intermediate overflow/undeflow, and handling
non-finite values.
"""
function logaddexp(x::T, y::T) where T<:Real
    # x or y is  NaN  =>  NaN
    # x or y is +Inf  => +Inf
    # x or y is -Inf  => other value
    isfinite(x) && isfinite(y) || return max(x,y)
    x > y ? x + log1p(exp(y - x)) : y + log1p(exp(x - y))
end

logaddexp(x::Real, y::Real) = logaddexp(promote(x, y)...)

Base.@deprecate logsumexp(x::Real, y::Real) logaddexp(x,y)

"""
$(SIGNATURES)

Compute `log(sum(exp, X))`, evaluated avoiding intermediate overflow/undeflow.

`X` should be an iterator of real numbers.
"""
function logsumexp(X)
    isempty(X) && return log(sum(X))
    reduce(logaddexp, X)
end

function logsumexp(X::AbstractArray{T}) where {T<:Real}
    isempty(X) && return log(zero(T))
    u = maximum(X)
    isfinite(u) || return float(u)
    let u=u # avoid https://github.com/JuliaLang/julia/issues/15276
        u + log(sum(x -> exp(x-u), X))
    end
end

"""
$(SIGNATURES)

Overwrite `r` with the `softmax` (or _normalized exponential_) transformation of `x`

That is, `r` is overwritten with `exp.(x)`, normalized to sum to 1.

See the [Wikipedia entry](https://en.wikipedia.org/wiki/Softmax_function)
"""
function softmax!(r::AbstractArray{R}, x::AbstractArray{T}) where {R<:AbstractFloat,T<:Real}
    n = length(x)
    length(r) == n || throw(DimensionMismatch("Inconsistent array lengths."))
    u = maximum(x)
    s = 0.
    @inbounds for i = 1:n
        s += (r[i] = exp(x[i] - u))
    end
    invs = convert(R, inv(s))
    @inbounds for i = 1:n
        r[i] *= invs
    end
    r
end

"""
$(SIGNATURES)

Return the [`softmax transformation`](https://en.wikipedia.org/wiki/Softmax_function)
applied to `x` *in place*.
"""
softmax!(x::AbstractArray{<:AbstractFloat}) = softmax!(x, x)

"""
$(SIGNATURES)

Return the [`softmax transformation`](https://en.wikipedia.org/wiki/Softmax_function)
applied to `x`.
"""
softmax(x::AbstractArray{<:Real}) = softmax!(similar(x, Float64), x)

end # module
