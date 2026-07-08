using CFHalos
using Documenter

DocMeta.setdocmeta!(CFHalos, :DocTestSetup, :(using CFHalos); recursive=true)

makedocs(;
    modules=[CFHalos],
    authors="Thomas Dubos <thomas.dubos@polytechnique.edu> and contributors",
    sitename="CFHalos.jl",
    format=Documenter.HTML(;
        canonical="https://ClimFlows.github.io/CFHalos.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/ClimFlows/CFHalos.jl",
    devbranch="main",
)
