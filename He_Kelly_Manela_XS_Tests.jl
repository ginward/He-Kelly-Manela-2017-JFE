##############################################################################
# Replication code for He-Kelly-Manela (2017 JFE) main results.
#
# Replicates main cross-sectional tests at the quarterly and monthly levels,
# with both Fama-MacBeth standard errors as well as GMM ones used in the paper.
#
# Some of this code is adapted from John Cochrane's cs_gmm() matlab function,
# which implements the GMM-based corrections he suggests in his Asset Pricing
# book for the fact that β are estimated, without assuming iid errors.
#
# Author: Asaf Manela
# Date: Feb 2017
#
# Code is for Julia v1.0.5.
# update time: 20191206 by woclass
##############################################################################

# data directory
datadir = dirname(@__FILE__)

# data files
qfilename = joinpath(datadir,"He_Kelly_Manela_Factors_And_Test_Assets.csv")
mfilename = joinpath(datadir,"He_Kelly_Manela_Factors_And_Test_Assets_monthly.csv")

# results files
# qresfilename = joinpath(datadir,"He_Kelly_Manela_Factors_And_Test_Assets_XS_results.csv")
# mresfilename = joinpath(datadir,"He_Kelly_Manela_Factors_And_Test_Assets_XS_results_monthly.csv")
qresfilename = joinpath(datadir,"He_Kelly_Manela_Factors_And_Test_Assets_XS_results_1.0test.csv")
mresfilename = joinpath(datadir,"He_Kelly_Manela_Factors_And_Test_Assets_XS_results_monthly_1.0test.csv")

# asset classes
classnames = ["FF25", "US_bonds", "Sov_bonds", "Options", "CDS", "Commod", "FX", "All"]

# uncomment if missing any of the following
# Pkg.add("GLM")
# Pkg.add("DataFrames")
# Pkg.add("Gadfly")
# Pkg.add("Cairo")
# Pkg.update()
using CSV, LinearAlgebra, Statistics, Dates
using DataFrames, GLM, Gadfly

# https://github.com/JuliaStats/DataArrays.jl
DataArray = Array{Union{Any, Missing}}

##############################################################################
# Utilities
##############################################################################
dropna(v::AbstractVector)::Vector{Float64} = filter(!ismissing, v)
eye(n::Int) = Matrix{Float64}(I, n, n)

yyyyq2date(yyyyq::Int) = 
Dates.lastdayofquarter(Date(div(yyyyq,10),round(mod(yyyyq,10)*3),1))
yyyymm2date(yyyymm::Int) = Dates.lastdayofmonth(Date(div(yyyymm,100),mod(yyyymm,100),1))

"Means with NAs"
namean(v::AbstractVector) = mean(dropna(v))
namean(df::DataFrame) = [namean(v[2]) for v=eachcol(df)]
namean(m::AbstractMatrix) = [namean(m[:,j]) for j=1:size(m,2)]

"Calculate second moment matrices with NAs"
function naExx(x)
    xna = ismissing.(x)
    
    completerows = vec(all(~, xna, dims=2))
    completex = x[completerows,:]
    naT = size(completex,1)
    Exx = completex'*completex/naT
    Exx, naT
end
naExx(x::DataFrame) = naExx(convert(DataArray,x))

"Run linear regression with NAs"
function nalm(X,y)
    completerows = vec(all(~, ismissing.([X y]), dims=2))
    compX = convert(Array{Float64},  X[completerows,:])
    compy = convert(Vector{Float64}, y[completerows])
    GLM.lm(compX, compy)
end

function _completecases(classname::String,excessreturns::DataFrame,factors::DataFrame)
    if classname!="All" && classname!="All_Ptfs"
        nonmissing = completecases([excessreturns factors])
        factors = factors[nonmissing,:]
        excessreturns = excessreturns[nonmissing,:]
    end

    convert(Matrix{Union{Float64, Missing}},excessreturns), convert(Matrix{Union{Float64, Missing}},factors)
end

function organizedata(alldata)
    returnsstart = first(findall(names(alldata).==:rf))+1
    returns = alldata[:,returnsstart:end]

    rf = alldata[!, :rf]

    assetnames = map(x->string(x),names(returns))
    nassets = length(assetnames)

    nclasses = length(classnames)
    assetclasses = DataFrame(classnames=classnames)
    # assetclasses[:returns] = DataArray(nclasses)
    # assetclasses[:excessreturns] = DataArray(nclasses)
    # assetclasses[:n] = DataArray(nclasses)
    # assetclasses[:allassetsRange] = DataArray(nclasses)
    assetclasses[!, :returns] = DataArray(undef,nclasses)
    assetclasses[!, :excessreturns] = DataArray(undef,nclasses)
    assetclasses[!, :n] = DataArray(undef,nclasses)
    assetclasses[!, :allassetsRange] = DataArray(undef,nclasses)
    
    allassetsCounter = 1;
    for c=1:nclasses
        classname = classnames[c]
        classreturns = DataFrame()
        for a=1:nassets
            assetname = assetnames[a]
            if occursin(classname, assetname)
                classreturns[!, Symbol(assetname)] = returns[!, Symbol(assetname)]
            end
        end
        assetclasses[c,:returns]=classreturns
        excessreturns = classreturns
        T, n = size(excessreturns)
        for i=1:n
            excessreturns[!,i] = 100*(excessreturns[!,i] - rf)
        end
        assetclasses[c,:excessreturns]=excessreturns
        assetclasses[c,:n] = n
        assetclasses[c,:allassetsRange] = vcat(allassetsCounter:allassetsCounter+n-1)
        allassetsCounter = allassetsCounter + n
    end

    factors = alldata[!, [:intermediary_capital_risk_factor, :mkt_rf]]
    factors[!, :intermediary_capital_risk_factor]*=100
    factors[!, :mkt_rf]*=100

    assetclasses, factors
end

##############################################################################
# generic code for cross-sectional tests
##############################################################################
function xsaptest(excessreturns::AbstractMatrix, factors::AbstractMatrix)
    # get dimensions
    T, n = size(excessreturns)
    k = size(factors,2)

    # TS regression for betas
    # β = DataArray(Float64, n, 3)
    # ɛt = DataArray(Float64, T, n)
    # Xf = hcat(fill!(DataArray(Float64,T,1),1.0),factors)
    β  = Array{Union{Float64, Missing}}(undef, n, 3)
    ɛt = Array{Union{Float64, Missing}}(undef, T, n)
    Xf = hcat(ones(Union{Float64, Missing}, T, 1), factors)
    
    for i=1:n
        lmi = nalm(Xf, excessreturns[:,i])
        β[i,:] = coef(lmi)
        ɛt[:,i] = excessreturns[:,i] - Xf*β[i,:]
    end

    Σ, naT = naExx(ɛt)
    Σ = convert(Array,Σ)

    # FM regressions
    # X = hcat(fill!(DataArray(Float64,n,1),1.0),β[:,2:end])
    # λt = DataArray(Float64, T, k+1)
    X  = hcat(ones(Union{Float64, Missing} ,n,1), β[:,2:end])
    λt = Array{Union{Float64, Missing}}(undef, T, k+1)
    
    for t=1:T
        λt[t,:]=coef(nalm(X,excessreturns[t,:]))
    end

    # Fama-MacBeth point estimates and standard errors
    # λ = DataArray(Float64,k+1,1)
    λ = Array{Union{Float64, Missing}}(undef, k+1, 1)
    seλFM = zeros(1+k,1)
    tλFM  = zeros(1+k,1)
    for f=1:1+k
        nonmissinglambdatf = dropna(λt[:,f])
        λ[f] = mean(nonmissinglambdatf)
        seλFM[f] = sqrt(sum((nonmissinglambdatf .- λ[f]).^2) / T)/sqrt(T)
        tλFM[f] = λ[f]/seλFM[f]
    end

    # We apply namean here, so that potentially the returns and factor means
    # are estimated over different time-periods, which is consistent with
    # the Fama-MacBeth treatment of the unbalanced panel
    Erx = namean(excessreturns)
    Ef = namean(factors)

    # pricing errors
    predEr = β*λ
    α = Erx-predEr

    # chi-squared statistic for pricing errors
    X = convert(Array,X)
    invXX=inv(convert(Array,X'*X))
    covα = 1/naT*(eye(n)-X*invXX*X')*Σ*(eye(n)-X*invXX*X')'
    χstat = α'*pinv(covα)*α

    ### GMM standard errors a-la Cochrane (2005)

    # first add time-series moments
    ut = deepcopy(ɛt)
    for i = 1:k
        ut = [ut  ɛt.*(factors[:,i]*ones(1,n)) ]
    end

    # now add cross sectional moments
    rx = convert(DataArray,excessreturns)
    ut = [ ut rx-ones(T,1)*(predEr)']

    # following usual advice to demean S. (Ols moments already are, but not cross sectional moments)
    ut_demeaned = ut - ones(T,1)*namean(ut)'

    # Spectral density matrix
    S = naExx(ut_demeaned)[1]

    # GMM selection matrix
    a = [[eye(n*(k+1)) zeros(n*(k+1),n)]
         [zeros(k+1,n*(k+1)) X']]

    # GMM jacobian
    Eff = naExx(factors)[1]
    d = [1 Ef';
        Ef Eff]
    d = kron(d,eye(n)) # first block is just like OLS, so taken from above
    d = -[[d zeros(n*(k+1),k+1)];
        [zeros(n,n) kron(λ[2:end,:]',eye(n)) X]]

    # standard errors for λ
    σ2gmm = 1/naT*inv(a*d)*a*S*a'*inv(a*d)'
    seλGMM = sqrt.(diag(σ2gmm[end-k:end,end-k:end]))
    tλGMM = λ ./ seλGMM

    rsquared = var(X*λ)/var(Erx)
    # could also do the following, not clear which is right
    # rsquared = 1-var(α)/var(meanexcessreturns)

    # mean absolute pricing errors (MAPE)
    mape = mean(abs.(α))

    λ, tλFM, tλGMM, rsquared, mape, χstat, n, T, k
end

statlabels = ["Capital", "  t-FM", "  t-GMM", "Market", "  t-FM", "  t-GMM", "Intercept", "  t-FM", "  t-GMM", "R2", "MAPE %", "Assets", "Quarters"]

"Run XS tests for each asset class and store results in a dataframe"
function xsaptests(alldata)
    assetclasses, factors = organizedata(alldata)

    lambdaTable = DataFrame(stat=statlabels)
    for c=1:size(assetclasses,1)
        classname = classnames[c]
        excessreturns=assetclasses[c,:excessreturns]

        # keep only complete cases
        rx, fs = _completecases(classname,excessreturns,factors)

        # run XS test
        λ, tλFM, tλGMM, rsquared, mape, χstat, n, T, k = xsaptest(rx,fs)

        # organize results in a vector and add to dataframe
        # results = reshape(([λ tλFM tλGMM][[2,3,1],:]).', 3*length(λ))
        results = reshape(([λ tλFM tλGMM][[2,3,1],:])', 3*length(λ))
        lambdaTable[!, Symbol(classname)] = [results; rsquared; mape; n; T]
    end
    lambdaTable
end

##############################################################################
# Quarterly Cross-sectional Tests
##############################################################################

# read all data from file
alldata = CSV.read(qfilename)

# run cross-sectional tests
lambdaTable = xsaptests(alldata)

# export results to file
CSV.write(qresfilename,lambdaTable)

##############################################################################
# Quarterly Time-series plots of intermediary capital level and innovations
##############################################################################
alldata[!, :date]=map(yyyyq2date,alldata[!, :yyyyq])
alldata[!, :intermediary_capital_pct] = alldata[!, :intermediary_capital_ratio]*100
levelsplot = Gadfly.plot(
    layer(alldata, x="date", y="intermediary_capital_pct", Geom.line, Theme(default_color=colorant"darkblue")),
    layer(alldata, x="date", y="aem_leverage_ratio", Geom.line, Theme(default_color=colorant"darkred")),
    Guide.title("Figure 3a: Capital and Leverage Ratios (Levels)"),
    Guide.ylabel(""),
    Scale.y_log10)

factorsplot = Gadfly.plot(
  layer(alldata, x="date", y="intermediary_capital_risk_factor", Geom.line, Theme(default_color=colorant"darkblue")),
  layer(alldata, x="date", y="aem_leverage_factor", Geom.line, Theme(default_color=colorant"darkred")),
    Guide.title("Figure 3b: Risk Factors (Innovations)"),
    Guide.ylabel("")
    )


##############################################################################
# Monthly Cross-sectional Tests
##############################################################################

# read all data from file
alldata = CSV.read(mfilename)

# run cross-sectional tests
lambdaTable = xsaptests(alldata)

# export results to file
CSV.write(mresfilename,lambdaTable)

println("finished!")
