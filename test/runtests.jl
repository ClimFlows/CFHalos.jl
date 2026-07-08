using CFHalos
using Test

using NetCDF
import InteractiveMPI: start
import ClimFlowsData: VoronoiLowRes

## halos

struct Halo
    other::Int # other rank involved in the exchange
    indices::Vector{Int32} # indices to send/receive
end

function split_halos(raw, pos=0)
    function next()
        pos = pos+1
        return raw[pos]
    end

    halos = Halo[]
    for _ in 1:next() # number of halos to receive
        halo = Halo(next(), Int32[])
        for j in 1:next()
            push!(halo.indices, next()) # indices in the file are already 1-based
        end
        push!(halos, halo)
    end
    @assert pos == length(raw)
    return halos
end

function on_halos(fun, halos)
    for halo in halos
        foreach(fun, halo.indices)
    end
end

function halo_buffers(data::AbstractVector, recv::Vector{Halo}, send::Vector{Halo})
    buffers(halos) = [similar(data, size(halo.indices)) for halo in halos]
    return buffers(recv), buffers(send)
end

function send_recv(MPI, comm, data_all, data_recv, data_send, recv, send)
    @assert length(data_recv) == length(recv)
    @assert length(data_send) == length(send)

    rank = MPI.Comm_rank(comm)

    # write into halos to be sent
    for (n, data) in enumerate(data_send)
        @assert length(data) == length(send[n].indices)
        for (j, index) in enumerate(send[n].indices)
            data[j] = data_all[index]
        end
    end

    # exchange halos
    send_reqs = [MPI.Isend(data, comm; dest=send[n].other, tag=rank) for (n, data) in enumerate(data_send)]
    recv_reqs = [MPI.Irecv!(data, comm; source=recv[n].other, tag=recv[n].other) for (n, data) in enumerate(data_recv)]

    # for req in send_reqs
    #     @info "Sending" from=req.source to=req.dest  tag=req.tag len=length(req.msg)
    # end
    # for req in recv_reqs
    #     @info "Receiving" from=req.source to=req.dest  tag=req.tag len=length(req.msg)
    # end

    # @info "Flush halo exchange" rank
    MPI.Waitall(vcat(send_reqs, recv_reqs))

    # read from received halos
    for (n, data) in enumerate(data_recv)
        @assert length(data) == length(recv[n].indices)
        for (j, index) in enumerate(recv[n].indices)
            data_all[index] = data[j]
        end
    end
end

## 

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
# slice(rank, array::AbstractArray{T,3}) where T = array[:, :, rank+1]

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
    pmesh = VoronoiLowRes("mesh4deg.16.nc")
    max_rank = length(NetCDF.open(pmesh,"primal_num"))
    start(MPI->main(MPI, pmesh), max_rank)
    @test true
end
