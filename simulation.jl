### A Pluto.jl notebook ###
# v0.15.1

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ f9949a62-b108-11eb-37d6-bb0790f7899a
begin
	using DataFrames
	using LRUCache
	using MixedModels, MixedModelsSim
	using PlutoUI
	using Random
	cache = LRU(;maxsize=10_000)
end;

# ╔═╡ 9aba0fc3-160a-4299-8371-c82081d808f9
begin
	using MixedModels: fixef!, stderror!, MixedModelBootstrap, getθ!
	using StaticArrays
	# modified from parametricbootstrap in MixedModels.jl
	# soon to be added to MixedModelsSim.jl
	function simulate_fit_different_form(
		rng::AbstractRNG,
		n::Integer,
		morig::MixedModel{T},
		form,
		data;
		use_threads::Bool=false,
		hide_progress::Bool=false,
		contrasts=Dict{Symbol,Any}()
	) where {T}
		mnew = fit(MixedModel, form, data; contrasts, progress=false)
		β = mnew.β
		σ = mnew.σ
		θ = mnew.θ
		
		β, θ = convert(Vector{T}, β), convert(Vector{T}, θ)
		βsc, θsc, p, k, m = similar(β), similar(θ), length(β), length(θ), deepcopy(morig)

		β_names = (Symbol.(fixefnames(mnew))...,)
		rank = length(β_names)

		# we need arrays of these for in-place operations to work across threads
		m_threads = [m]
		βsc_threads = [βsc]
		θsc_threads = [θsc]

		if use_threads
			Threads.resize_nthreads!(m_threads)
			Threads.resize_nthreads!(βsc_threads)
			Threads.resize_nthreads!(θsc_threads)
		end
		rnglock = Threads.SpinLock()
		samp = replicate(n; use_threads=use_threads, hide_progress=hide_progress) do
			tidx = use_threads ? Threads.threadid() : 1
			mod = m_threads[tidx]
			local βsc = βsc_threads[tidx]
			local θsc = θsc_threads[tidx]
			lock(rnglock)
			mod = simulate!(rng, mod)
			unlock(rnglock)
			mod = fit(MixedModel, form, data; contrasts, progress=false)
			(
				objective=mod.objective,
				σ=mod.σ,
				β=NamedTuple{β_names}(fixef!(βsc, mod)),
				se=SVector{p,T}(stderror!(βsc, mod)),
				θ=SVector{k,T}(getθ!(θsc, mod)),
			)
		end
		return MixedModelBootstrap(
			samp,
			deepcopy(morig.λ),
			getfield.(morig.reterms, :inds),
			morig.optsum.lowerbd[1:length(first(samp).θ)],
			NamedTuple{Symbol.(fnames(mnew))}(map(t -> (t.cnames...,), morig.reterms)),
		)
	end
end

# ╔═╡ 7faaf93e-b02a-4a5b-9c1d-2d60488f0590
md"""
Let's look at a simple fully crossed 2x2 design:
- **frequency** `high` vs. `low`/
- **context** `matched` vs. `unmatched`.
"""

# ╔═╡ da2e5642-3188-4f0d-8a8a-402a64860366
both_win = Dict(:context => ["matched", "unmatched"],
				:frequency => ["high", "low"]);


# ╔═╡ d2584c26-9db7-4f4e-afbc-9c1626130a16
contrasts = Dict(:frequency => EffectsCoding(base="high"),
                 :context => EffectsCoding(base="matched"))

# ╔═╡ 039bcc98-70d7-452f-9fef-785e848c6917
genform = @formula(dv ~ 1 + frequency * context +
                    (1 + frequency * context | subj) +
                    (1 + frequency * context | item));

# ╔═╡ 99969868-a8d9-4096-ae05-8025f146fbd7
md"Number of subjects: $(@bind n_subj NumberField(10:100; default=40))"

# ╔═╡ 8be15f3f-1fba-4f74-aeae-1aae66ba4689
md"Number of items: $(@bind n_item  NumberField(10:100; default=40))"

# ╔═╡ 5a015198-43c5-4c9e-a5b5-ae7821df1ae2
md"**Relative** By-subject standard deviation for `Intercept`: $(@bind s_subj_intercept NumberField(0:0.1:5; default=1))"

# ╔═╡ 4f6a4441-53b9-4d1e-b61a-da839f85d1a2
md"**Relative** By-subject standard deviation for `context`: $(@bind s_subj_context NumberField(0:0.1:5; default=1))"

# ╔═╡ 8ea30194-1ad1-44bb-8185-8236aa6c86eb
md"**Relative**  By-subject standard deviation for `frequency`: $(@bind s_subj_frequency  NumberField(0:0.1:5; default=1))"

# ╔═╡ fe53bb70-b1eb-4858-98fa-2256e8399b5b
md"**Relative**  By-subject standard deviation for `frequency`-`context` interaction: $(@bind s_subj_interaction  NumberField(0:0.1:5; default=1))"

# ╔═╡ fcbf836f-5e8e-4763-9c0f-ad9f9c3b5776
md"**Relative** By-item standard deviation for `Intercept`: $(@bind s_item_intercept  NumberField(0:0.1:5; default=1))"

# ╔═╡ a85ac4b0-1259-4a87-ac20-cca6a8924ba4
md"**Relative** By-item standard deviation for `context`: $(@bind s_item_context  NumberField(0:0.1:5; default=1))"

# ╔═╡ f6a1e981-46b8-4db9-b871-037014b6f1de
md"**Relative**  By-item standard deviation for `frequency`: $(@bind s_item_frequency  NumberField(0:0.1:5; default=1))"

# ╔═╡ b053fc48-cdd9-47bc-bbeb-1263e8cb13e7
md"**Relative**  By-item standard deviation for `frequency`-`context` interaction: $(@bind s_item_interaction  NumberField(0:0.1:5; default=1))"

# ╔═╡ 3287c778-ce89-42e7-b6c9-44da71590b71
β = [-2, -1, -2, 0.6]

# ╔═╡ 701566c0-e28d-4e7f-bc45-191b533c8c2c
md"Residual standard deviation"

# ╔═╡ b6a549f9-acff-40a1-98fd-41affd1fd3c3
@bind σ  NumberField(0:0.1:5; default=1)

# ╔═╡ 892ad822-4af3-4410-8e27-46ee175ac513
md"Number of simulations"

# ╔═╡ c60759a8-729d-4c1d-84bc-718abe575144
@bind n_sim  NumberField(100:100:1000; default=100)

# ╔═╡ 99a2bae0-523e-4820-b486-d400819d58c4
fitform = @formula(dv ~ 1 + frequency * context +
                    (1 + frequency + context | subj) +
                    (1 + frequency + context | item));

# ╔═╡ 8b9a2004-cd76-4c91-844a-cc280ad03846
begin
	design = simdat_crossed(MersenneTwister(42), n_subj, n_item;
                             both_win = both_win)
	design = pooled!(DataFrame(design))
	
	m0 = LinearMixedModel(genform, design; contrasts=contrasts)
	re_item = create_re(s_item_intercept, s_item_frequency, 
						s_item_context, s_item_interaction)
	re_subj = create_re(s_subj_intercept, s_subj_frequency, 
						s_subj_context, s_subj_interaction)
	if string(m0.reterms[1]) == "subj"
		update!(m0, float.(re_subj), float.(re_item))
	else	
		update!(m0, float.(re_item), float.(re_subj))
	end
	fit!(simulate!(MersenneTwister(42), m0; β=β, σ=σ, θ=m0.θ))
	design.dv = response(m0)
	m0
end;

# ╔═╡ ccae902d-7a27-46c3-b3a9-03d9d9fb8c3c
md"""The data-generating model: $(m0)"""

# ╔═╡ 8652fb19-6232-4c02-81c5-0c7318a58325
md"""Model with simplified formula fit to the same data: $(fit(MixedModel, fitform, design; contrasts=contrasts))"""

# ╔═╡ dd586970-9cb9-425e-8492-af194730c371
results = get!(cache, (m0, n_sim, fitform)) do 
	# this is actually generating the same data twice
	# which is kinda inefficient but makes for simpler code
	altenative = simulate_fit_different_form(MersenneTwister(24), n_sim, m0, fitform, design; contrasts)
	generating = parametricbootstrap(MersenneTwister(24), n_sim, m0)
	return (; alternative, generating)
end

# ╔═╡ 07307417-6dd5-40ac-99f8-599b69ec237d
shortestcovint(results.altenative)

# ╔═╡ ddb5fb01-64d8-483d-9df0-b2f7b4b750ef
shortestcovint(results.generating)

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
LRUCache = "8ac3fa9e-de4c-5943-b1dc-09c6b5f20637"
MixedModels = "ff71e718-51f3-5ec2-a782-8ffcbfa3c316"
MixedModelsSim = "d5ae56c5-23ca-4a1f-b505-9fc4796fc1fe"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[compat]
DataFrames = "~1.2.2"
LRUCache = "~1.3.0"
MixedModels = "~4.1.1"
MixedModelsSim = "~0.2.3"
PlutoUI = "~0.7.9"
StaticArrays = "~1.2.12"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[Arrow]]
deps = ["ArrowTypes", "BitIntegers", "CodecLz4", "CodecZstd", "DataAPI", "Dates", "Mmap", "PooledArrays", "SentinelArrays", "Tables", "TimeZones", "UUIDs"]
git-tree-sha1 = "b00e6eaba895683867728e73af78a00218f0db10"
uuid = "69666777-d1a9-59fb-9406-91d4454c9d45"
version = "1.6.2"

[[ArrowTypes]]
deps = ["UUIDs"]
git-tree-sha1 = "a0633b6d6efabf3f76dacd6eb1b3ec6c42ab0552"
uuid = "31f734f8-188a-4ce0-8406-c8a06bd891cd"
version = "1.2.1"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Statistics", "UUIDs"]
git-tree-sha1 = "42ac5e523869a84eac9669eaceed9e4aa0e1587b"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.1.4"

[[BitIntegers]]
deps = ["Random"]
git-tree-sha1 = "f50b5a99aa6ff9db7bf51255b5c21c8bc871ad54"
uuid = "c3b6d118-76ef-56ca-8cc7-ebb389d030a1"
version = "0.2.5"

[[Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "30ee06de5ff870b45c78f529a6b093b3323256a3"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.3.1"

[[CodecBzip2]]
deps = ["Bzip2_jll", "Libdl", "TranscodingStreams"]
git-tree-sha1 = "2e62a725210ce3c3c2e1a3080190e7ca491f18d7"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.7.2"

[[CodecLz4]]
deps = ["Lz4_jll", "TranscodingStreams"]
git-tree-sha1 = "59fe0cb37784288d6b9f1baebddbf75457395d40"
uuid = "5ba52731-8f18-5e0d-9241-30f10d1ec561"
version = "0.4.0"

[[CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[CodecZstd]]
deps = ["TranscodingStreams", "Zstd_jll"]
git-tree-sha1 = "d19cd9ae79ef31774151637492291d75194fc5fa"
uuid = "6b39b394-51ab-5f42-8807-6242bab2b4c2"
version = "0.7.0"

[[Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "727e463cfebd0c7b999bbf3e9e7e16f254b94193"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.34.0"

[[CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[Crayons]]
git-tree-sha1 = "3f71217b538d7aaee0b69ab47d9b7724ca8afa0d"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.0.4"

[[DataAPI]]
git-tree-sha1 = "bec2532f8adb82005476c141ec23e921fc20971b"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.8.0"

[[DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Reexport", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "d785f42445b63fc86caa08bb9a9351008be9b765"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.2.2"

[[DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "7d9d316f04214f7efdbb6398d545446e246eff02"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.10"

[[DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[Distributions]]
deps = ["ChainRulesCore", "FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "StatsBase", "StatsFuns"]
git-tree-sha1 = "f4efaa4b5157e0cdb8283ae0b5428bc9208436ed"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.16"

[[DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "a32185f5428d3986f47c2ab78b1f216d5e6cc96f"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.8.5"

[[Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[ExprTools]]
git-tree-sha1 = "b7e3d17636b348f005f11040025ae8c6f645fe92"
uuid = "e2ba6199-217a-4e67-a87a-7c52f15ade04"
version = "0.1.6"

[[FillArrays]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "Statistics"]
git-tree-sha1 = "a3b7b041753094f3b17ffa9d2e2e07d8cace09cd"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "0.12.3"

[[Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[GLM]]
deps = ["Distributions", "LinearAlgebra", "Printf", "Reexport", "SparseArrays", "SpecialFunctions", "Statistics", "StatsBase", "StatsFuns", "StatsModels"]
git-tree-sha1 = "f564ce4af5e79bb88ff1f4488e64363487674278"
uuid = "38e38edf-8417-5370-95a0-9cbb8c7f171a"
version = "1.5.1"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[InvertedIndices]]
git-tree-sha1 = "bee5f1ef5bf65df56bdd2e40447590b272a5471f"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.1.0"

[[IrrationalConstants]]
git-tree-sha1 = "f76424439413893a832026ca355fe273e93bce94"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.0"

[[IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "642a199af8b68253517b80bd3bfd17eb4e84df6e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.3.0"

[[JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "8076680b162ada2a031f707ac7b4953e30667a37"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.2"

[[JSON3]]
deps = ["Dates", "Mmap", "Parsers", "StructTypes", "UUIDs"]
git-tree-sha1 = "b3e5984da3c6c95bcf6931760387ff2e64f508f3"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.9.1"

[[LRUCache]]
git-tree-sha1 = "d64a0aff6691612ab9fb0117b0995270871c5dfc"
uuid = "8ac3fa9e-de4c-5943-b1dc-09c6b5f20637"
version = "1.3.0"

[[LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[LinearAlgebra]]
deps = ["Libdl"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[LogExpFunctions]]
deps = ["ChainRulesCore", "DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "86197a8ecb06e222d66797b0c2d2f0cc7b69e42b"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.2"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[Lz4_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "5d494bc6e85c4c9b626ee0cab05daa4085486ab1"
uuid = "5ced341a-0733-55b8-9ab6-a4889d929147"
version = "1.9.3+0"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "JSON", "LinearAlgebra", "MutableArithmetics", "OrderedCollections", "Printf", "SparseArrays", "Test", "Unicode"]
git-tree-sha1 = "debba84c7060716b0737504b59aabe976c9b91cb"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "0.10.0"

[[MathProgBase]]
deps = ["LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "9abbe463a1e9fc507f12a69e7f29346c2cdc472c"
uuid = "fdba3010-5040-5b88-9595-932c9decdf73"
version = "0.7.8"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "2ca267b08821e86c5ef4376cffed98a46c2cb205"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.1"

[[MixedModels]]
deps = ["Arrow", "DataAPI", "Distributions", "GLM", "JSON3", "LazyArtifacts", "LinearAlgebra", "Markdown", "NLopt", "PooledArrays", "ProgressMeter", "Random", "SparseArrays", "StaticArrays", "Statistics", "StatsBase", "StatsFuns", "StatsModels", "StructTypes", "Tables"]
git-tree-sha1 = "f318e42a48ec0a856292bafeec6b07aed3f6d600"
uuid = "ff71e718-51f3-5ec2-a782-8ffcbfa3c316"
version = "4.1.1"

[[MixedModelsSim]]
deps = ["LinearAlgebra", "MixedModels", "PooledArrays", "PrettyTables", "Random", "Statistics", "Tables"]
git-tree-sha1 = "ad4eaa164a5ab5fd22effcb86e7c991192ed3488"
uuid = "d5ae56c5-23ca-4a1f-b505-9fc4796fc1fe"
version = "0.2.3"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[Mocking]]
deps = ["ExprTools"]
git-tree-sha1 = "748f6e1e4de814b101911e64cc12d83a6af66782"
uuid = "78c3b35d-d492-501b-9361-3d52fe80e533"
version = "0.7.2"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "3927848ccebcc165952dc0d9ac9aa274a87bfe01"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "0.2.20"

[[NLopt]]
deps = ["MathOptInterface", "MathProgBase", "NLopt_jll"]
git-tree-sha1 = "f115030b9325ca09ef1619ba0617b2a64101ce84"
uuid = "76087f3c-5699-56af-9a33-bf431cd00edd"
version = "0.6.4"

[[NLopt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "2b597c46900f5f811bec31f0dcc88b45744a2a09"
uuid = "079eb43e-fd8e-5478-9966-2cf3e3edb778"
version = "2.7.0+0"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "4dd403333bcf0909341cfe57ec115152f937d7d8"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.1"

[[Parsers]]
deps = ["Dates"]
git-tree-sha1 = "438d35d2d95ae2c5e8780b330592b6de8494e779"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.0.3"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[PlutoUI]]
deps = ["Base64", "Dates", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "Suppressor"]
git-tree-sha1 = "44e225d5837e2a2345e69a1d1e01ac2443ff9fcb"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.9"

[[PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "a193d6ad9c45ada72c14b731a318bedd3c2f00cf"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.3.0"

[[Preferences]]
deps = ["TOML"]
git-tree-sha1 = "00cfd92944ca9c760982747e9a1d0d5d86ab1e5a"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.2.2"

[[PrettyTables]]
deps = ["Crayons", "Formatting", "Markdown", "Reexport", "Tables"]
git-tree-sha1 = "0d1245a357cc61c8cd61934c07447aa569ff22e6"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "1.1.0"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[ProgressMeter]]
deps = ["Distributed", "Printf"]
git-tree-sha1 = "afadeba63d90ff223a6a48d2009434ecee2ec9e8"
uuid = "92933f4c-e287-5a05-a399-4b506db050ca"
version = "1.7.1"

[[QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "12fbe86da16df6679be7521dfb39fbc861e1dc7b"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.4.1"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[RecipesBase]]
git-tree-sha1 = "44a75aa7a527910ee3d1751d1f0e4148698add9e"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.1.2"

[[Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "bf3188feca147ce108c76ad82c2792c57abe7b1f"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.7.0"

[[Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "68db32dff12bb6127bac73c209881191bf0efbb7"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.3.0+0"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "54f37736d8934a12a200edea2f9206b03bdf3159"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.7"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[ShiftedArrays]]
git-tree-sha1 = "22395afdcf37d6709a5a0766cc4a5ca52cb85ea0"
uuid = "1277b4bf-5013-50f5-be3d-901d8477a67a"
version = "1.0.0"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[SpecialFunctions]]
deps = ["ChainRulesCore", "LogExpFunctions", "OpenSpecFun_jll"]
git-tree-sha1 = "a322a9493e49c5f3a10b50df3aedaf1cdb3244b7"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "1.6.1"

[[StaticArrays]]
deps = ["LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "3240808c6d463ac46f1c1cd7638375cd22abbccb"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.2.12"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[StatsAPI]]
git-tree-sha1 = "1958272568dc176a1d881acb797beb909c785510"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.0.0"

[[StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "8cbbc098554648c84f79a463c9ff0fd277144b6c"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.10"

[[StatsFuns]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "46d7ccc7104860c38b11966dd1f72ff042f382e4"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "0.9.10"

[[StatsModels]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "Printf", "ShiftedArrays", "SparseArrays", "StatsBase", "StatsFuns", "Tables"]
git-tree-sha1 = "3fa15c1f8be168e76d59097f66970adc86bfeb95"
uuid = "3eaba693-59b7-5ba5-a881-562e759f1c8d"
version = "0.6.25"

[[StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "8445bf99a36d703a09c601f9a57e2f83000ef2ae"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.7.3"

[[SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[Suppressor]]
git-tree-sha1 = "a819d77f31f83e5792a76081eee1ea6342ab8787"
uuid = "fd094767-a336-5f1f-9728-57cf17d0bbfb"
version = "0.2.0"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "TableTraits", "Test"]
git-tree-sha1 = "368d04a820fe069f9080ff1b432147a6203c3c89"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.5.1"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[TimeZones]]
deps = ["Dates", "Future", "LazyArtifacts", "Mocking", "Pkg", "Printf", "RecipesBase", "Serialization", "Unicode"]
git-tree-sha1 = "6c9040665b2da00d30143261aea22c7427aada1c"
uuid = "f269a46b-ccf7-5d73-abea-4c690281aa53"
version = "1.5.7"

[[TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "216b95ea110b5972db65aa90f88d8d89dcb8851c"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.6"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "cc4bf3fdde8b7e3e9fa0351bdeedba1cf3b7f6e6"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.0+0"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
"""

# ╔═╡ Cell order:
# ╠═f9949a62-b108-11eb-37d6-bb0790f7899a
# ╟─7faaf93e-b02a-4a5b-9c1d-2d60488f0590
# ╟─da2e5642-3188-4f0d-8a8a-402a64860366
# ╠═d2584c26-9db7-4f4e-afbc-9c1626130a16
# ╠═039bcc98-70d7-452f-9fef-785e848c6917
# ╟─99969868-a8d9-4096-ae05-8025f146fbd7
# ╟─8be15f3f-1fba-4f74-aeae-1aae66ba4689
# ╟─5a015198-43c5-4c9e-a5b5-ae7821df1ae2
# ╟─4f6a4441-53b9-4d1e-b61a-da839f85d1a2
# ╟─8ea30194-1ad1-44bb-8185-8236aa6c86eb
# ╟─fe53bb70-b1eb-4858-98fa-2256e8399b5b
# ╟─fcbf836f-5e8e-4763-9c0f-ad9f9c3b5776
# ╟─a85ac4b0-1259-4a87-ac20-cca6a8924ba4
# ╟─f6a1e981-46b8-4db9-b871-037014b6f1de
# ╟─b053fc48-cdd9-47bc-bbeb-1263e8cb13e7
# ╠═3287c778-ce89-42e7-b6c9-44da71590b71
# ╟─701566c0-e28d-4e7f-bc45-191b533c8c2c
# ╟─b6a549f9-acff-40a1-98fd-41affd1fd3c3
# ╟─892ad822-4af3-4410-8e27-46ee175ac513
# ╟─c60759a8-729d-4c1d-84bc-718abe575144
# ╠═99a2bae0-523e-4820-b486-d400819d58c4
# ╟─8b9a2004-cd76-4c91-844a-cc280ad03846
# ╟─ccae902d-7a27-46c3-b3a9-03d9d9fb8c3c
# ╟─8652fb19-6232-4c02-81c5-0c7318a58325
# ╟─9aba0fc3-160a-4299-8371-c82081d808f9
# ╠═dd586970-9cb9-425e-8492-af194730c371
# ╠═07307417-6dd5-40ac-99f8-599b69ec237d
# ╠═ddb5fb01-64d8-483d-9df0-b2f7b4b750ef
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
