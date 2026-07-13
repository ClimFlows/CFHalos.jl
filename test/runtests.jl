using NetCDF
import InteractiveMPI: start, ThreadsMPIBackend
import ClimFlowsData: VoronoiLowRes

using CFHalos: Halo, on_halos, halo_buffers, send_recv
using Test

# read halo info from DYNAMICO partitioned mesh file
function split_halos(raw::AbstractVector{I}, pos=0) where {I<:Integer}
    function next()
        pos = pos+1
        return raw[pos]
    end

    halos = Halo{I}[]
    for _ in 1:next() # number of halos to receive
        halo = Halo(Int(next()), I[])
        for j in 1:next()
            push!(halo.indices, next()) # indices in the file are already 1-based
        end
        push!(halos, halo)
    end
    @assert pos == length(raw)
    return halos
end

pget(MPI, pmesh, var) = MPI.Critical() do
    slice(MPI.Comm_rank(MPI.COMM_WORLD), NetCDF.open(pmesh, var))
end

pget(MPI, pmesh, num, var) = MPI.Critical() do
    rank = MPI.Comm_rank(MPI.COMM_WORLD)
    n = slice(rank, NetCDF.open(pmesh, num)) :: Int32
    return slice(rank, n, NetCDF.open(pmesh, var))
end

slice(rank, array::AbstractVector) = array[rank+1]
slice(rank, n, array::AbstractMatrix) = array[1:n, rank+1]

function main(MPI, pmesh)
    MPI.Init()
    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    primal_recv = split_halos(pget(MPI, pmesh, "primal_recv_num", "primal_recv"))
    primal_send = split_halos(pget(MPI, pmesh, "primal_send_num", "primal_send"))
    # @info "Rank" pmesh rank primal_recv primal_send

    Ai = pget(MPI, pmesh, "primal_num", "Ai")
    Ai_recv, Ai_send = halo_buffers(Ai, primal_recv, primal_send) # preallocate buffers

    # compute something
    Ai2 = Ai .* Ai 
    ref = copy(Ai2)
    @assert Ai2 ≈ ref

    # erase halo values
    on_halos(primal_recv) do ij
        Ai2[ij] = 0 
    end
    # exchange halos
    send_recv(MPI, comm, Ai2, Ai_recv, Ai_send, primal_recv, primal_send)
    # verify halo values
    # @info "Check" maximum(Ai2) maximum(abs, x-y for (x,y) in zip(Ai2, ref))
    @assert Ai2 ≈ ref
    @info "Success" rank
end

@testset "CFHalos.jl" begin
    nproc = 16
    pmesh = VoronoiLowRes("mesh4deg.$nproc.nc")
    backend = ThreadsMPIBackend(nproc)
    start(MPI->main(MPI, pmesh), backend)
    @test true
end
