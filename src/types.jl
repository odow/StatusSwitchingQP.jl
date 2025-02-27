


"""

        @enum Status

Status: assets go IN/OUT(DN or UP), or inequalities go binded (EO, as equality) or not (OE, original ineq), with fields:

            IN  #within the lower and upper bound
            DN  #down, lower bound
            UP  #upper bound
            OE  #original <= not active
            EO  #edge, <= as =

"""
@enum Status begin
    IN
    DN  #down, lower bound
    UP  #upper bound
    OE  #original <=, not active
    EO  #edge, <= as =, active
end



"""

        struct Event{T<:AbstractFloat}

Events that assets go IN/OUT(DN or UP), or inequalities go binded (EO, as equality) or not (OE, original ineq), with fields:

            From::Status
            To::Status
            id::Int     #asset ID
            L::T        #L

"""
struct Event{T<:AbstractFloat}
    From::Status
    To::Status
    id::Int
    L::T
end



"""
        LP(c::Vector{T}, A::Matrix{T}, b::Vector{T}) where {T}
        LP(c::Vector{T}, A::Matrix{T}, b::Vector{T}; G, g, d, u) where {T}

The LP takes the following form

```math
min   f=c′x
s.t.  Ax=b  ∈R^{M}
      Gx≤g  ∈R^{J}
      d≤x≤u ∈R^{N}
```

for free variables, d=-Inf, u=Inf.  The default LP takes the following form (G = [], g = [], d = 0, u = +∞)

```math
min   f=c′x
s.t.  Ax=b  ∈R^{M}
      x≥0   ∈R^{N}
```

See also [`QP`](@ref), [`Settings`](@ref), [`SimplexLP`](@ref), [`solveLP`](@ref)
"""
struct LP{T<:AbstractFloat}    #standard LP, or structure of LP
    c::Vector{T}
    A::Matrix{T}
    b::Vector{T}
    G::Matrix{T}
    g::Vector{T}
    d::Vector{T}
    u::Vector{T}
    N::Int
    M::Int
    J::Int
end


function LP(c::Vector{T}, A::Matrix{T}, b::Vector{T}; N=length(c),
    u=fill(Inf, N),
    d=zeros(N),
    G=ones(0, N),
    g=ones(0)) where {T}

    M = length(b)
    J = length(g)

    (M, N) == size(A) || throw(DimensionMismatch("incompatible dimension: A"))
    (J, N) == size(G) || throw(DimensionMismatch("incompatible dimension: G"))
    N == size(d, 1) || throw(DimensionMismatch("incompatible dimension: d"))
    N == size(u, 1) || throw(DimensionMismatch("incompatible dimension: u"))

    #check feasibility and redundancy of Ax=b
    rb = rank([A vec(b)])
    @assert rb == rank(A) "infeasible: Ax=b"
    #@assert M == length(getRows(A, tolN)) "redundant rows in Ax=b"   #full row rank
    @assert M == rb "redundant rows in Ax=b"       #full row rank

    @assert !any(d .== u) "downside bound == upper bound detected"
    @assert J > 0 || any(isfinite.(d)) || any(isfinite.(u)) "no inequalities and bounds"

    iu = u .< d
    if sum(iu) > 0
        @warn "swap the elements where u < d, to make sure u > d"
        t = u[iu]
        u[iu] .= d[iu]
        d[iu] .= t
    end

    LP{T}(c, A, b, G, g, d, u, N, M, J)
end


"""

        QP(V::Matrix{T}; q, u, d, G, g, A, b) where T
        QP(P::QP{T}, q::Vector{T}, L::T=0.0) where T
        QP(P::QP{T}, mu::T, q::Vector{T}) where T

Setup a quadratic programming model:

```math
    min   (1/2)z′Vz+q′z
    s.t.   Az=b ∈ R^{M}
           Gz≤g ∈ R^{J}
           d≤z≤u ∈ R^{N}
```

variable z[i] may be free, say d[i]= -Inf and u[i]=+Inf . No equalities if M=0.
Default values: q = 0, u = +∞, d = 0, G = [], g = [], A = ones(1,N), b = [1], such that
```math
    min   (1/2)z′Vz
    s.t.   1'z=1  ∈ R^{M}
           z≥0    ∈ R^{N}
```

`QP(P::QP, q, L)`  :  replace the q'z term in the objective function by `-L * q`
`QP(P::QP, mu, q)` :  add q'z=mu to the last row of Az=b, and remove q'z in the objective function

See also [`LP`](@ref), [`Settings`](@ref), [`solveQP`](@ref)

"""
struct QP{T<:AbstractFloat}    #standard QP, or structure of QP
    V::Matrix{T}
    A::Matrix{T}
    G::Matrix{T}
    q::Vector{T}
    b::Vector{T}
    g::Vector{T}
    d::Vector{T}
    u::Vector{T}
    N::Int
    M::Int
    J::Int
end

function QP(V::Matrix{T}; N=size(V, 1), #N=convert(Int32, size(V, 1)),
    q=zeros(N),
    u=fill(Inf, N),
    d=zeros(N),
    G=ones(0, N),
    g=ones(0),
    A=ones(1, N),
    b=ones(1)) where {T}

    M = length(b)
    J = length(g)

    (N, N) == size(V) || throw(DimensionMismatch("incompatible dimension: V"))
    V = convert(Matrix{T}, (V + V') / 2)   #make sure symmetric
    #@assert det(V) >= 0 "variance matrix has negative determinant"
    @assert eigmin(V) > -sqrt(eps(T)) "variance matrix is not positive-semidefinite"
    (M, N) == size(A) || throw(DimensionMismatch("incompatible dimension: A"))
    (J, N) == size(G) || throw(DimensionMismatch("incompatible dimension: G"))
    N == size(q, 1) || throw(DimensionMismatch("incompatible dimension: q"))
    N == size(d, 1) || throw(DimensionMismatch("incompatible dimension: d"))
    N == size(u, 1) || throw(DimensionMismatch("incompatible dimension: u"))

    #check feasibility and redundancy of Ax=b
    rb = rank([A vec(b)])
    @assert rb == rank(A) "infeasible: Ax=b"
    @assert M == rb "redundant rows in Ax=b"       #full row rank

    @assert !any(d .== u) "downside bound == upper bound detected"
    #J+ (num of finite d u) > 0  , when LP is introduce
    @assert J > 0 || any(isfinite.(d)) || any(isfinite.(u)) "no any inequalities or bounds"

    iu = u .< d
    if sum(iu) > 0
        @warn "swap the elements where u < d, to make sure u > d"
        t = u[iu]
        u[iu] .= d[iu]
        d[iu] .= t
    end

    QP{T}(V, convert(Matrix{T}, copy(A)),
        convert(Matrix{T}, copy(G)),
        convert(Vector{T}, copy(q)),
        convert(Vector{T}, copy(vec(b))),
        convert(Vector{T}, copy(vec(g))),
        convert(Vector{T}, copy(d)),
        convert(Vector{T}, copy(u)), N, M, J)
end

function QP(P::QP{T}, q, L::T=0.0) where {T}
    #(; V, A, G, q, b, g, d, u, N, M, J) = P
    (; V, A, G, b, g, d, u, N, M, J) = P
    #q = -L * q
    #return QP(V, A, G, q, b, g, d, u, N, M, J)
    return QP(V, A, G, -L * q, b, g, d, u, N, M, J)
end

function QP(P::QP{T}, mu::T, q::Vector{T}) where {T}
    #(; V, A, G, q, b, g, d, u, N, M, J) = P
    (; V, A, G, b, g, d, u, N, M, J) = P
    #q = zeros(T, N)
    M += 1
    Am = [A; q']
    bm = [b; mu]
    return QP(V, Am, G, zeros(T, N), bm, g, d, u, N, M, J)
end

function QP(P::LP{T}) where {T}

    (; c, A, b, G, g, d, u, N, M, J) = P
    v = abs.(c) .+ 0.5
    return QP(diagm(v), A, G, zeros(T, length(c)), b, g, d, u, N, M, J)
end

"""

        Settings(; kwargs...)       The default Settings is set by Float64 type
        Settings{T<:AbstractFloat}(; kwargs...)

kwargs are from the fields of Settings{T<:AbstractFloat} for Float64 and BigFloat

            maxIter::Int    #7777
            tol::T          #2^-26 ≈ 1.5e-8  general scalar
            tolG::T         #2^-27 for Greeks (beta and gamma)
            pivot::Symbol   #pivot for purging redundant rows (Gauss-Jordan elimination) {:column, :row}
            rule::Symbol    #rule for Simplex {:Dantzig, :maxImprovement}

"""
struct Settings{T<:AbstractFloat}
    maxIter::Int    #7777
    tol::T          #2^-26
    #tolN::T         #2^-26
    tolG::T         #2^-27 for Greeks (beta and gamma)
    pivot::Symbol    #pivoting for purging redundant rows {:column, :row}
    rule::Symbol    #rule for Simplex {:Dantzig, :maxImprovement}
end

Settings(; kwargs...) = Settings{Float64}(; kwargs...)

function Settings{Float64}(; maxIter=7777,
    tol=2^-26,
    #tolN=2^-26,
    tolG=2^-33,
    pivot=:column, rule=:Dantzig)
    #Settings{Float64}(maxIter, tol, tolN, tolG, pivot, rule)
    Settings{Float64}(maxIter, tol, tolG, pivot, rule)
end

function Settings{BigFloat}(; maxIter=7777,
    tol=BigFloat(2)^-76,
    #tolN=BigFloat(2)^-76,
    tolG=BigFloat(2)^-87,
    pivot=:column, rule=:Dantzig)
    #Settings{BigFloat}(maxIter, tol, tolN, tolG, pivot, rule)
    Settings{BigFloat}(maxIter, tol, tolG, pivot, rule)
end

